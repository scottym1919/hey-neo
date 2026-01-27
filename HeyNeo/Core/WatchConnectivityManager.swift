import Foundation
import WatchConnectivity
import Combine

/// Manages communication between iPhone and Apple Watch
@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    // MARK: - Published State
    
    @Published private(set) var isReachable = false
    @Published private(set) var isPaired = false
    @Published private(set) var isWatchAppInstalled = false
    
    // MARK: - Private Properties
    
    private var session: WCSession?
    private weak var gateway: GatewayClient?
    
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
    
    func setGateway(_ gateway: GatewayClient) {
        self.gateway = gateway
    }
    
    /// Send connection state to watch
    func sendConnectionState(_ state: ConnectionState) {
        guard let session = session, session.isReachable else { return }
        
        let message: [String: Any] = [
            "type": "connectionState",
            "isConnected": state.isConnected,
            "displayText": state.displayText
        ]
        
        session.sendMessage(message, replyHandler: nil) { error in
            print("[WatchConnectivity] Send error: \(error)")
        }
    }
    
    /// Send a message to the watch
    func sendMessage(_ message: Message) {
        guard let session = session, session.isReachable else { return }
        
        let payload: [String: Any] = [
            "type": "message",
            "id": message.id.uuidString,
            "role": message.role.rawValue,
            "content": message.content,
            "timestamp": message.timestamp.timeIntervalSince1970
        ]
        
        session.sendMessage(payload, replyHandler: nil) { error in
            print("[WatchConnectivity] Send error: \(error)")
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("[WatchConnectivity] Activation error: \(error)")
            } else {
                print("[WatchConnectivity] Activated with state: \(activationState.rawValue)")
                updateState(from: session)
            }
        }
    }
    
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        print("[WatchConnectivity] Session became inactive")
    }
    
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        print("[WatchConnectivity] Session deactivated")
        // Reactivate for switching between watches
        session.activate()
    }
    
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isReachable = session.isReachable
            print("[WatchConnectivity] Reachability changed: \(session.isReachable)")
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        Task { @MainActor in
            handleMessage(message)
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        Task { @MainActor in
            handleMessage(message, replyHandler: replyHandler)
        }
    }
    
    // MARK: - Private Methods
    
    @MainActor
    private func updateState(from session: WCSession) {
        isPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
        isReachable = session.isReachable
    }
    
    @MainActor
    private func handleMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)? = nil) {
        guard let type = message["type"] as? String else { return }
        
        switch type {
        case "sendChat":
            // Watch wants to send a chat message
            if let text = message["text"] as? String {
                Task {
                    await gateway?.sendMessage(text)
                    replyHandler?(["status": "sent"])
                }
            }
            
        case "getConnectionState":
            // Watch wants current connection state
            let state = gateway?.connectionState ?? .disconnected
            replyHandler?([
                "isConnected": state.isConnected,
                "displayText": state.displayText
            ])
            
        case "connect":
            // Watch wants to connect
            Task {
                await gateway?.connect()
                replyHandler?(["status": "connecting"])
            }
            
        default:
            print("[WatchConnectivity] Unknown message type: \(type)")
            replyHandler?(["error": "Unknown message type"])
        }
    }
}
