import Foundation
import WatchConnectivity

/// Manages communication from Watch to iPhone
@MainActor
final class WatchPhoneConnectivity: NSObject, ObservableObject {
    // MARK: - Published State
    
    @Published private(set) var isReachable = false
    @Published private(set) var isConnected = false
    @Published private(set) var connectionDisplayText = "Disconnected"
    @Published private(set) var lastResponse: String?
    @Published private(set) var isSending = false
    
    // MARK: - Private Properties
    
    private var session: WCSession?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }
    
    // MARK: - Public Methods
    
    /// Send a chat message through the iPhone
    func sendChatMessage(_ text: String) {
        guard let session = session, session.isReachable else {
            lastResponse = "iPhone not reachable"
            return
        }
        
        isSending = true
        
        let message: [String: Any] = [
            "type": "sendChat",
            "text": text
        ]
        
        session.sendMessage(message, replyHandler: { [weak self] reply in
            Task { @MainActor in
                self?.isSending = false
                if let status = reply["status"] as? String {
                    print("[WatchConnectivity] Send status: \(status)")
                }
            }
        }, errorHandler: { [weak self] error in
            Task { @MainActor in
                self?.isSending = false
                self?.lastResponse = "Send error: \(error.localizedDescription)"
            }
        })
    }
    
    /// Request current connection state from iPhone
    func refreshConnectionState() {
        guard let session = session, session.isReachable else { return }
        
        let message: [String: Any] = ["type": "getConnectionState"]
        
        session.sendMessage(message, replyHandler: { [weak self] reply in
            Task { @MainActor in
                if let connected = reply["isConnected"] as? Bool,
                   let displayText = reply["displayText"] as? String {
                    self?.isConnected = connected
                    self?.connectionDisplayText = displayText
                }
            }
        }, errorHandler: { error in
            print("[WatchConnectivity] Refresh error: \(error)")
        })
    }
    
    /// Request iPhone to connect to gateway
    func requestConnect() {
        guard let session = session, session.isReachable else { return }
        
        let message: [String: Any] = ["type": "connect"]
        
        session.sendMessage(message, replyHandler: { reply in
            print("[WatchConnectivity] Connect reply: \(reply)")
        }, errorHandler: { error in
            print("[WatchConnectivity] Connect error: \(error)")
        })
    }
}

// MARK: - WCSessionDelegate

extension WatchPhoneConnectivity: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("[WatchConnectivity] Activation error: \(error)")
            } else {
                print("[WatchConnectivity] Activated")
                isReachable = session.isReachable
                refreshConnectionState()
            }
        }
    }
    
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isReachable = session.isReachable
            if session.isReachable {
                refreshConnectionState()
            }
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        Task { @MainActor in
            handleMessage(message)
        }
    }
    
    // MARK: - Private Methods
    
    @MainActor
    private func handleMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        
        switch type {
        case "connectionState":
            if let connected = message["isConnected"] as? Bool,
               let displayText = message["displayText"] as? String {
                isConnected = connected
                connectionDisplayText = displayText
            }
            
        case "message":
            // Received a chat message from assistant
            if let role = message["role"] as? String,
               let content = message["content"] as? String,
               role == "assistant" {
                lastResponse = content
            }
            
        default:
            print("[WatchConnectivity] Unknown message type: \(type)")
        }
    }
}
