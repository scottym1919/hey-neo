import Foundation
import Security

/// Manages app settings with UserDefaults and Keychain
@MainActor
final class AppSettings: ObservableObject {
    // MARK: - Published Properties
    
    @Published var gatewayURL: String {
        didSet {
            UserDefaults.standard.set(gatewayURL, forKey: Keys.gatewayURL)
        }
    }
    
    @Published var autoConnect: Bool {
        didSet {
            UserDefaults.standard.set(autoConnect, forKey: Keys.autoConnect)
        }
    }
    
    @Published var speakResponses: Bool {
        didSet {
            UserDefaults.standard.set(speakResponses, forKey: Keys.speakResponses)
        }
    }

    // MARK: - Wake Word Settings

    @Published var wakeWordEnabled: Bool {
        didSet {
            UserDefaults.standard.set(wakeWordEnabled, forKey: Keys.wakeWordEnabled)
        }
    }

    @Published var wakeWordSensitivity: Float {
        didSet {
            UserDefaults.standard.set(wakeWordSensitivity, forKey: Keys.wakeWordSensitivity)
        }
    }

    /// Which built-in keyword to use, or empty string for custom .ppn file.
    @Published var wakeWordKeyword: String {
        didSet {
            UserDefaults.standard.set(wakeWordKeyword, forKey: Keys.wakeWordKeyword)
        }
    }

    /// Filename of a custom .ppn keyword file bundled in the app.
    @Published var wakeWordCustomFile: String {
        didSet {
            UserDefaults.standard.set(wakeWordCustomFile, forKey: Keys.wakeWordCustomFile)
        }
    }

    // MARK: - Keychain Properties

    var picovoiceAccessKey: String {
        get {
            KeychainHelper.read(key: Keys.picovoiceAccessKey) ?? ""
        }
        set {
            if newValue.isEmpty {
                KeychainHelper.delete(key: Keys.picovoiceAccessKey)
            } else {
                KeychainHelper.save(key: Keys.picovoiceAccessKey, value: newValue)
            }
            objectWillChange.send()
        }
    }

    // MARK: - Keychain Token
    
    var gatewayToken: String {
        get {
            KeychainHelper.read(key: Keys.gatewayToken) ?? ""
        }
        set {
            if newValue.isEmpty {
                KeychainHelper.delete(key: Keys.gatewayToken)
            } else {
                KeychainHelper.save(key: Keys.gatewayToken, value: newValue)
            }
            objectWillChange.send()
        }
    }
    
    // MARK: - Computed Properties
    
    var isConfigured: Bool {
        !gatewayURL.isEmpty && !gatewayToken.isEmpty
    }
    
    // MARK: - Keys
    
    private enum Keys {
        static let gatewayURL = "gatewayURL"
        static let gatewayToken = "gatewayToken"
        static let autoConnect = "autoConnect"
        static let speakResponses = "speakResponses"
        static let wakeWordEnabled = "wakeWordEnabled"
        static let wakeWordSensitivity = "wakeWordSensitivity"
        static let wakeWordKeyword = "wakeWordKeyword"
        static let wakeWordCustomFile = "wakeWordCustomFile"
        static let picovoiceAccessKey = "picovoiceAccessKey"
    }
    
    // MARK: - Initialization
    
    init() {
        self.gatewayURL = UserDefaults.standard.string(forKey: Keys.gatewayURL) ?? ""
        self.autoConnect = UserDefaults.standard.bool(forKey: Keys.autoConnect)
        // Default to true for TTS if not set
        self.speakResponses = UserDefaults.standard.object(forKey: Keys.speakResponses) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Keys.speakResponses)

        // Wake word defaults
        self.wakeWordEnabled = UserDefaults.standard.bool(forKey: Keys.wakeWordEnabled)
        self.wakeWordSensitivity = UserDefaults.standard.object(forKey: Keys.wakeWordSensitivity) == nil
            ? 0.5
            : UserDefaults.standard.float(forKey: Keys.wakeWordSensitivity)
        self.wakeWordKeyword = UserDefaults.standard.string(forKey: Keys.wakeWordKeyword) ?? "porcupine"
        self.wakeWordCustomFile = UserDefaults.standard.string(forKey: Keys.wakeWordCustomFile) ?? ""
    }
}

// MARK: - Keychain Helper

private enum KeychainHelper {
    private static let service = "com.hey-neo.gateway"
    
    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        // Delete existing item first
        delete(key: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("[Keychain] Save failed: \(status)")
        }
    }
    
    static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
