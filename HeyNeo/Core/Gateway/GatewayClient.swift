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
    
    // MARK: - Initialization
    
    init(settings: AppSettings) {
        self.settings = settings
    }
    
    deinit {
        disconnect()
    }
    
    // MARK: - Public Methods
    
    /// Connect to the Gateway WebSocket
    func connect() async {
        guard !connectionState.isConnected else { return }
        
        let urlString = settings.gatewayURL
        guard !urlString.isEmpty else {
            connectionState = .error("Gateway URL not configured")
            return
        }
        
        let token = settings.gatewayToken
        guard !token.isEmpty else {
            connectionState = .error("Gateway token not configured")
            return
        }
        
        // Build WebSocket URL
        var wsURL = urlString
        if !wsURL.hasPrefix("ws://") && !wsURL.hasPrefix("wss://") {
            wsURL = "ws://\(wsURL)"
        }
        if !wsURL.hasSuffix("/ws") {
            wsURL = wsURL.hasSuffix("/") ? "\(wsURL)ws" : "\(wsURL)/ws"
        }
        
        guard let url = URL(string: wsURL) else {
            connectionState = .error("Invalid Gateway URL")
            return
        }
        
        connectionState = .connecting
        
        // Create WebSocket
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        
        session = URLSession(configuration: configuration)
        webSocketTask = session?.webSocketTask(with: url)
        webSocketTask?.resume()
        
        // Start receiving messages
        startReceiving()
        
        // Send connect handshake
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
        let request = GatewayRequest(
            id: nextRequestId(),
            method: "chat.send",
            params: .chatSend(ChatSendParams(text: text))
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
            
            print("[GatewayClient] Sending: \(string)")
            
            try await webSocketTask?.send(.string(string))
        } catch {
            print("[GatewayClient] Send error: \(error)")
            connectionState = .error("Send failed: \(error.localizedDescription)")
        }
    }
    
    private func startReceiving() {
        guard !isReceiving else { return }
        isReceiving = true
        
        Task { [weak self] in
            guard let self = self else { return }
            
            while isReceiving {
                do {
                    guard let message = try await webSocketTask?.receive() else {
                        break
                    }
                    
                    await MainActor.run {
                        self.handleMessage(message)
                    }
                } catch {
                    await MainActor.run {
                        if self.isReceiving {
                            print("[GatewayClient] Receive error: \(error)")
                            self.connectionState = .error("Connection lost")
                            self.isReceiving = false
                            self.scheduleReconnect()
                        }
                    }
                    break
                }
            }
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
        guard let response = try? decoder.decode(GatewayResponse.self, from: data) else {
            print("[GatewayClient] Failed to decode response")
            return
        }
        
        if response.ok {
            if response.payload?.type == "hello-ok" {
                print("[GatewayClient] Connected successfully!")
                connectionState = .connected
            }
        } else {
            let errorMsg = response.error?.message ?? "Unknown error"
            print("[GatewayClient] Request failed: \(errorMsg)")
            connectionState = .error(errorMsg)
        }
    }
    
    private func handleEvent(_ data: Data, decoder: JSONDecoder, rawFrame: RawFrame) {
        guard let event = try? decoder.decode(GatewayEvent.self, from: data) else {
            print("[GatewayClient] Failed to decode event")
            return
        }
        
        switch event.event {
        case "chat.chunk":
            handleChatChunk(event)
        case "chat.message":
            handleChatMessage(event)
        case "connect.challenge":
            // Challenge event - we already sent connect, can ignore
            break
        default:
            print("[GatewayClient] Unhandled event: \(event.event)")
        }
    }
    
    private func handleChatChunk(_ event: GatewayEvent) {
        // Accumulate streaming content
        if let text = event.payload?.text ?? event.payload?.chunk ?? event.payload?.delta {
            currentStreamingContent += text
        }
    }
    
    private func handleChatMessage(_ event: GatewayEvent) {
        // Complete message received
        let content = event.payload?.content 
            ?? event.payload?.message?.content 
            ?? event.payload?.message?.text
            ?? currentStreamingContent
        
        if !content.isEmpty {
            let assistantMessage = Message(role: .assistant, content: content)
            messages.append(assistantMessage)
        }
        
        // Clear streaming content
        currentStreamingContent = ""
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
