import Foundation

/// Represents a chat message in the conversation
struct Message: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date
    
    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

/// The role of a message sender
enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}
