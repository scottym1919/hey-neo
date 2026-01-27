import Foundation

// MARK: - Gateway Protocol Messages

/// Base types for Gateway WebSocket protocol
enum GatewayFrameType: String, Codable, Sendable {
    case req
    case res
    case event
}

// MARK: - Outgoing Messages (Client → Gateway)

/// A request frame sent to the Gateway
struct GatewayRequest: Codable, Sendable {
    let type: String = "req"
    let id: String
    let method: String
    let params: GatewayParams
    
    init(id: String, method: String, params: GatewayParams) {
        self.id = id
        self.method = method
        self.params = params
    }
}

/// Parameters for gateway requests
enum GatewayParams: Codable, Sendable {
    case connect(ConnectParams)
    case chatSend(ChatSendParams)
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .connect(let params):
            try container.encode(params)
        case .chatSend(let params):
            try container.encode(params)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Try to decode as ConnectParams first, then ChatSendParams
        if let connect = try? container.decode(ConnectParams.self) {
            self = .connect(connect)
        } else if let chatSend = try? container.decode(ChatSendParams.self) {
            self = .chatSend(chatSend)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown params type")
            )
        }
    }
}

/// Parameters for the connect handshake
struct ConnectParams: Codable, Sendable {
    let minProtocol: Int
    let maxProtocol: Int
    let client: ClientInfo
    let role: String
    let scopes: [String]
    let auth: AuthParams
    
    static func `default`(token: String) -> ConnectParams {
        ConnectParams(
            minProtocol: 3,
            maxProtocol: 3,
            client: ClientInfo(
                id: "hey-neo-ios",
                version: "1.0.0",
                platform: "ios",
                mode: "operator"
            ),
            role: "operator",
            scopes: ["operator.read", "operator.write"],
            auth: AuthParams(token: token)
        )
    }
}

struct ClientInfo: Codable, Sendable {
    let id: String
    let version: String
    let platform: String
    let mode: String
}

struct AuthParams: Codable, Sendable {
    let token: String
}

/// Parameters for sending a chat message
struct ChatSendParams: Codable, Sendable {
    let text: String
}

// MARK: - Incoming Messages (Gateway → Client)

/// A response frame from the Gateway
struct GatewayResponse: Codable, Sendable {
    let type: String
    let id: String
    let ok: Bool
    let payload: ResponsePayload?
    let error: GatewayError?
}

struct ResponsePayload: Codable, Sendable {
    let type: String?
    let `protocol`: Int?
    let policy: PolicyInfo?
    let auth: AuthResponse?
}

struct PolicyInfo: Codable, Sendable {
    let tickIntervalMs: Int?
}

struct AuthResponse: Codable, Sendable {
    let deviceToken: String?
    let role: String?
    let scopes: [String]?
}

struct GatewayError: Codable, Sendable {
    let code: String?
    let message: String?
}

/// An event frame from the Gateway
struct GatewayEvent: Codable, Sendable {
    let type: String
    let event: String
    let payload: EventPayload?
    let seq: Int?
    let stateVersion: Int?
}

/// Flexible payload for events
struct EventPayload: Codable, Sendable {
    // For chat.chunk events
    let text: String?
    let chunk: String?
    let delta: String?
    
    // For chat.message events
    let role: String?
    let content: String?
    let message: MessagePayload?
    
    // Generic
    let data: [String: AnyCodable]?
}

struct MessagePayload: Codable, Sendable {
    let role: String?
    let content: String?
    let text: String?
}

/// Type-erased codable for flexible JSON
struct AnyCodable: Codable, Sendable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        default:
            try container.encodeNil()
        }
    }
}

// MARK: - Raw Frame Parsing

/// Raw frame for initial parsing to determine type
struct RawFrame: Codable {
    let type: String
    let id: String?
    let method: String?
    let event: String?
    let ok: Bool?
}
