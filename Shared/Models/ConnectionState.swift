import Foundation

/// Represents the connection state to the Gateway
enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case error(String)
    
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
    
    var displayText: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    var statusColor: String {
        switch self {
        case .disconnected:
            return "gray"
        case .connecting:
            return "orange"
        case .connected:
            return "green"
        case .error:
            return "red"
        }
    }
}
