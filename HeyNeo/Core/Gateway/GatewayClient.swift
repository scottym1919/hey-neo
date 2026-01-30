import Foundation
import Combine

/// WebSocket client for Clawdbot Gateway communication
@MainActor
final class GatewayClient: ObservableObject {
    // MARK: - Published State
    
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var messages: [Message] = []
    @Published private(set) var currentStreamingContent: String = ""
    
    // MARK: - Private Properties
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var requestId: Int = 0
    private var isReceiving = false
    private var reconnectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    
    private let settings: AppSettings
    
    /// Session key for chat - format: agent:<agentId>:<sessionKey>
    private let sessionKey = "agent:main:ios-\(UUID().uuidString.prefix(8))"
    
    /// Track active run IDs from our chat.send requests
    private var activeRunIds: Set<String> = []
    
    // MARK: - Initialization
    
    init(settings: AppSettings) {
        self.settings = settings
    }
    
    deinit {
        // Clean up tasks synchronously - can't call MainActor methods from deinit
        reconnectTask?.cancel()
        pingTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
    }
    
    // MARK: - Public Methods
    
    /// Connect to the Gateway WebSocket
    func connect() async {
        guard !connectionState.isConnected else { 
            print("[GatewayClient] ⚠️ Already connected, skipping")
            return 
        }
        
        let urlString = settings.gatewayURL
        print("[GatewayClient] 📡 Attempting connection with URL: '\(urlString)'")
        
        guard !urlString.isEmpty else {
            print("[GatewayClient] ❌ Gateway URL is empty")
            connectionState = .error("Gateway URL not configured")
            return
        }
        
        let token = settings.gatewayToken
        guard !token.isEmpty else {
            print("[GatewayClient] ❌ Gateway token is empty")
            connectionState = .error("Gateway token not configured")
            return
        }
        
        print("[GatewayClient] ✓ Token found (length: \(token.count))")
        
        // Build WebSocket URL
        var wsURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove any existing protocol prefix
        if wsURL.hasPrefix("http://") {
            wsURL = String(wsURL.dropFirst(7))
            print("[GatewayClient] Stripped http:// prefix")
        } else if wsURL.hasPrefix("https://") {
            wsURL = String(wsURL.dropFirst(8))
            print("[GatewayClient] Stripped https:// prefix")
        } else if wsURL.hasPrefix("ws://") {
            wsURL = String(wsURL.dropFirst(5))
            print("[GatewayClient] Stripped ws:// prefix")
        } else if wsURL.hasPrefix("wss://") {
            wsURL = String(wsURL.dropFirst(6))
            print("[GatewayClient] Stripped wss:// prefix")
        }
        
        // Remove any path
        if let slashIndex = wsURL.firstIndex(of: "/") {
            wsURL = String(wsURL[..<slashIndex])
            print("[GatewayClient] Removed path from URL")
        }
        
        // Build the final URL
        let finalURL = "ws://\(wsURL)/ws"
        
        print("[GatewayClient] 🔗 Final WebSocket URL: \(finalURL)")
        
        guard let url = URL(string: finalURL) else {
            print("[GatewayClient] ❌ Invalid URL format: \(finalURL)")
            connectionState = .error("Invalid Gateway URL: \(finalURL)")
            return
        }
        
        print("[GatewayClient] ✓ URL validated successfully")
        connectionState = .connecting
        
        // Create WebSocket
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        
        print("[GatewayClient] Creating URLSession and WebSocket task...")
        session = URLSession(configuration: configuration)
        webSocketTask = session?.webSocketTask(with: url)
        
        print("[GatewayClient] 🚀 Resuming WebSocket task...")
        webSocketTask?.resume()
        
        // Start receiving messages
        print("[GatewayClient] Starting message receiver...")
        startReceiving()
        
        // Send connect handshake
        print("[GatewayClient] Sending connect handshake...")
        await sendConnectHandshake(token: token)
        
        // Start ping task
        startPingTask()
    }
    
    /// Disconnect from the Gateway
    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        pingTask?.cancel()
        pingTask = nil
        
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
        
        connectionState = .disconnected
        isReceiving = false
    }
    
    /// Send a chat message
    func sendMessage(_ text: String) async {
        guard connectionState.isConnected else {
            print("[GatewayClient] Cannot send message: not connected")
            return
        }
        
        // Add user message to conversation
        let userMessage = Message(role: .user, content: text)
        messages.append(userMessage)
        
        // Clear any previous streaming content
        currentStreamingContent = ""
        
        // Send to Gateway
        print("[GatewayClient] 💬 Sending chat to session: \(sessionKey)")
        let request = GatewayRequest(
            id: nextRequestId(),
            method: "chat.send",
            params: .chatSend(ChatSendParams(sessionKey: sessionKey, message: text))
        )
        
        await sendRequest(request)
    }
    
    /// Clear conversation history
    func clearMessages() {
        messages.removeAll()
        currentStreamingContent = ""
    }
    
    // MARK: - Private Methods
    
    private func nextRequestId() -> String {
        requestId += 1
        return String(requestId)
    }
    
    private func sendConnectHandshake(token: String) async {
        let request = GatewayRequest(
            id: nextRequestId(),
            method: "connect",
            params: .connect(ConnectParams.default(token: token))
        )
        
        await sendRequest(request)
    }
    
    private func sendRequest(_ request: GatewayRequest) async {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(request)
            let string = String(data: data, encoding: .utf8) ?? ""
            
            print("[GatewayClient] 📤 Sending: \(string)")
            
            guard let task = webSocketTask else {
                print("[GatewayClient] ❌ Cannot send: WebSocket task is nil")
                connectionState = .error("WebSocket not connected")
                return
            }
            
            try await task.send(.string(string))
            print("[GatewayClient] ✓ Message sent successfully")
        } catch {
            print("[GatewayClient] ❌ Send error: \(error)")
            print("[GatewayClient] Error type: \(type(of: error))")
            print("[GatewayClient] Error description: \(error.localizedDescription)")
            connectionState = .error("Send failed: \(error.localizedDescription)")
        }
    }
    
    private func startReceiving() {
        guard !isReceiving else { 
            print("[GatewayClient] ⚠️ Already receiving messages")
            return 
        }
        isReceiving = true
        print("[GatewayClient] ✓ Message receiver started")
        
        Task { [weak self] in
            guard let self = self else { return }
            
            while isReceiving {
                do {
                    print("[GatewayClient] 📥 Waiting for message...")
                    guard let message = try await webSocketTask?.receive() else {
                        print("[GatewayClient] ❌ WebSocket task returned nil")
                        break
                    }
                    
                    print("[GatewayClient] ✓ Message received")
                    await MainActor.run {
                        self.handleMessage(message)
                    }
                } catch {
                    await MainActor.run {
                        if self.isReceiving {
                            print("[GatewayClient] ❌ Receive error: \(error)")
                            print("[GatewayClient] Error type: \(type(of: error))")
                            print("[GatewayClient] Error description: \(error.localizedDescription)")
                            
                            // Check for specific error types
                            if let urlError = error as? URLError {
                                print("[GatewayClient] URLError code: \(urlError.code.rawValue)")
                                print("[GatewayClient] URLError: \(urlError.localizedDescription)")
                            }
                            
                            self.connectionState = .error("Connection lost: \(error.localizedDescription)")
                            self.isReceiving = false
                            self.scheduleReconnect()
                        }
                    }
                    break
                }
            }
            print("[GatewayClient] 🛑 Message receiver stopped")
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            print("[GatewayClient] Received: \(text.prefix(500))")
            parseAndHandleFrame(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseAndHandleFrame(text)
            }
        @unknown default:
            break
        }
    }
    
    private func parseAndHandleFrame(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        
        let decoder = JSONDecoder()
        
        // First, parse the raw frame to determine type
        guard let rawFrame = try? decoder.decode(RawFrame.self, from: data) else {
            print("[GatewayClient] Failed to parse frame")
            return
        }
        
        switch rawFrame.type {
        case "res":
            handleResponse(data, decoder: decoder)
        case "event":
            handleEvent(data, decoder: decoder, rawFrame: rawFrame)
        default:
            print("[GatewayClient] Unknown frame type: \(rawFrame.type)")
        }
    }
    
    private func handleResponse(_ data: Data, decoder: JSONDecoder) {
        // Try to get runId from response for chat.send tracking
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let payload = json["payload"] as? [String: Any],
           let runId = payload["runId"] as? String,
           let status = payload["status"] as? String {
            if status == "started" {
                print("[GatewayClient] 🚀 Chat run started with runId: \(runId)")
                activeRunIds.insert(runId)
            }
        }
        
        guard let response = try? decoder.decode(GatewayResponse.self, from: data) else {
            print("[GatewayClient] Failed to decode response")
            return
        }
        
        if response.ok {
            if response.payload?.type == "hello-ok" {
                print("[GatewayClient] ✓ Connected successfully!")
                print("[GatewayClient] Session key: \(sessionKey)")
                connectionState = .connected
            }
        } else {
            let errorMsg = response.error?.message ?? "Unknown error"
            print("[GatewayClient] Request failed: \(errorMsg)")
            connectionState = .error(errorMsg)
        }
    }
    
    private func sendChatSubscribe() async {
        print("[GatewayClient] 📥 Subscribing to chat events for session: \(sessionKey)")
        
        do {
            let payload = ChatSubscribePayload(sessionKey: sessionKey)
            let event = try GatewayOutgoingEvent(event: "chat.subscribe", payload: payload)
            
            let encoder = JSONEncoder()
            let data = try encoder.encode(event)
            let string = String(data: data, encoding: .utf8) ?? ""
            
            print("[GatewayClient] 📤 Sending subscribe: \(string)")
            
            guard let task = webSocketTask else {
                print("[GatewayClient] ❌ Cannot subscribe: WebSocket task is nil")
                return
            }
            
            try await task.send(.string(string))
            print("[GatewayClient] ✓ Subscribe sent successfully")
        } catch {
            print("[GatewayClient] ❌ Subscribe error: \(error)")
        }
    }
    
    private func handleEvent(_ data: Data, decoder: JSONDecoder, rawFrame: RawFrame) {
        let rawString = String(data: data, encoding: .utf8) ?? "(invalid utf8)"
        
        do {
            let event = try decoder.decode(GatewayEvent.self, from: data)
            
            switch event.event {
            case "chat":
                print("[GatewayClient] 💬 Chat event received, payload: \(event.payload != nil ? "present" : "nil")")
                handleChatEvent(event)
            case "agent":
                // Agent lifecycle events - can be used for tool call display later
                print("[GatewayClient] 🔧 Agent event")
            case "connect.challenge":
                // Challenge event - we already sent connect, can ignore
                break
            default:
                print("[GatewayClient] Unhandled event: \(event.event)")
            }
        } catch {
            print("[GatewayClient] ❌ Failed to decode event: \(error)")
            print("[GatewayClient] Raw frame: \(rawString.prefix(500))")
        }
    }
    
    private func handleChatEvent(_ event: GatewayEvent) {
        guard let payload = event.payload else {
            print("[GatewayClient] Chat event missing payload")
            return
        }
        
        let runId = payload.runId ?? ""
        print("[GatewayClient] 📨 Chat payload - runId: \(runId), state: \(payload.state ?? "nil")")
        print("[GatewayClient] 📨 Active runIds: \(activeRunIds)")
        print("[GatewayClient] 📨 Message present: \(payload.message != nil), content: \(payload.message?.content?.count ?? 0) blocks")
        
        // Filter by runId - only process events for our active runs
        // Also accept events matching our session key (for backwards compat)
        let matchesRunId = !runId.isEmpty && activeRunIds.contains(runId)
        let matchesSession = payload.sessionKey == sessionKey
        
        if !matchesRunId && !matchesSession {
            print("[GatewayClient] ⏭️ Ignoring chat event - runId: \(runId), sessionKey: \(payload.sessionKey ?? "nil")")
            return
        }
        
        let state = payload.state ?? ""
        print("[GatewayClient] ✅ Processing chat event (matched by \(matchesRunId ? "runId" : "sessionKey")) state: \(state)")
        
        switch state {
        case "delta":
            // Streaming content update
            if let text = payload.textContent {
                currentStreamingContent = text  // Server sends full accumulated text
                print("[GatewayClient] 📝 Delta text: \(text.prefix(100))...")
            } else {
                print("[GatewayClient] ⚠️ Delta event but textContent is nil")
            }
            
        case "final":
            // Complete message received
            let payloadText = payload.textContent
            print("[GatewayClient] 📝 Final - payload.textContent: \(payloadText?.prefix(50) ?? "nil")")
            print("[GatewayClient] 📝 Final - currentStreamingContent: \(currentStreamingContent.prefix(50))...")
            
            let content = payloadText ?? currentStreamingContent
            
            if !content.isEmpty {
                let assistantMessage = Message(role: .assistant, content: content)
                messages.append(assistantMessage)
                print("[GatewayClient] ✅ Final message added (\(content.count) chars): \(content.prefix(100))...")
                print("[GatewayClient] 📊 Total messages now: \(messages.count)")
            } else {
                print("[GatewayClient] ⚠️ Final event but content is empty")
            }
            
            // Clear streaming content and remove completed runId
            currentStreamingContent = ""
            if !runId.isEmpty {
                activeRunIds.remove(runId)
                print("[GatewayClient] 🏁 Run completed, removed runId: \(runId)")
            }
            
        case "error":
            // Error occurred
            let errorMsg = payload.errorMessage ?? "Unknown error"
            print("[GatewayClient] ❌ Chat error: \(errorMsg)")
            currentStreamingContent = ""
            if !runId.isEmpty {
                activeRunIds.remove(runId)
                print("[GatewayClient] 🏁 Run errored, removed runId: \(runId)")
            }
            
        default:
            print("[GatewayClient] Unknown chat state: \(state)")
        }
    }
    
    private func startPingTask() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self = self, self.connectionState.isConnected else { continue }
                self.webSocketTask?.sendPing { error in
                    if let error = error {
                        print("[GatewayClient] Ping failed: \(error)")
                    }
                }
            }
        }
    }
    
    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self = self, !Task.isCancelled else { return }
            print("[GatewayClient] Attempting reconnect...")
            await self.connect()
        }
    }
}
