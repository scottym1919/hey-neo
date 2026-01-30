import Foundation
import Combine

/// ViewModel for the Home view
@MainActor
final class HomeViewModel: ObservableObject {
    // MARK: - Published State
    
    @Published private(set) var isRecording = false
    @Published private(set) var transcribedText = ""
    @Published private(set) var errorMessage: String?
    
    // MARK: - Settings Reference
    
    private let settings: AppSettings
    
    // MARK: - Gateway State (forwarded)
    
    var connectionState: ConnectionState {
        gateway.connectionState
    }
    
    var messages: [Message] {
        gateway.messages
    }
    
    var streamingContent: String {
        gateway.currentStreamingContent
    }
    
    var isSpeaking: Bool {
        textToSpeech.isSpeaking
    }
    
    // MARK: - Computed Properties
    
    var canRecord: Bool {
        speechRecognizer.isAuthorized && connectionState.isConnected
    }
    
    // MARK: - Private Properties
    
    private let gateway: GatewayClient
    private let speechRecognizer: SpeechRecognizer
    private let textToSpeech: TextToSpeech
    private var cancellables = Set<AnyCancellable>()
    private var lastMessageCount = 0
    
    // MARK: - TTS Control (forwards to settings)
    
    var speakResponses: Bool {
        get { settings.speakResponses }
        set { settings.speakResponses = newValue }
    }
    
    // MARK: - Initialization
    
    init(gateway: GatewayClient, speechRecognizer: SpeechRecognizer, textToSpeech: TextToSpeech, settings: AppSettings) {
        self.gateway = gateway
        self.speechRecognizer = speechRecognizer
        self.textToSpeech = textToSpeech
        self.settings = settings
        
        setupBindings()
    }
    
    // MARK: - Public Methods
    
    func onAppear() async {
        // Request speech permissions
        await speechRecognizer.requestAuthorization()
        
        // Auto-connect if configured
        if gateway.connectionState == .disconnected {
            await connect()
        }
    }
    
    func connect() async {
        await gateway.connect()
    }
    
    func startRecording() async {
        guard canRecord else {
            if !speechRecognizer.isAuthorized {
                errorMessage = "Microphone access required. Please enable in Settings."
            } else if !connectionState.isConnected {
                errorMessage = "Not connected to Gateway"
            }
            return
        }
        
        errorMessage = nil
        
        do {
            try await speechRecognizer.startRecording()
            isRecording = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func stopRecordingAndSend() async {
        guard isRecording else { return }
        
        let finalText = speechRecognizer.stopRecording()
        isRecording = false
        transcribedText = ""
        
        // Send if we have text
        guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        await gateway.sendMessage(finalText)
    }
    
    func cancelRecording() {
        speechRecognizer.cancelRecording()
        isRecording = false
        transcribedText = ""
    }
    
    func clearConversation() {
        gateway.clearMessages()
    }
    
    /// Stop any ongoing speech
    func stopSpeaking() {
        textToSpeech.stop()
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // Forward speech recognizer state
        speechRecognizer.$transcribedText
            .receive(on: DispatchQueue.main)
            .assign(to: &$transcribedText)
        
        // Forward speech recognizer errors
        speechRecognizer.$errorMessage
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] error in
                self?.errorMessage = error
            }
            .store(in: &cancellables)
        
        // Propagate gateway changes and check for new messages
        gateway.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.checkForNewMessages()
            }
            .store(in: &cancellables)
        
        // Propagate TTS changes
        textToSpeech.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // Propagate settings changes (for TTS toggle)
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // Initialize message count
        lastMessageCount = gateway.messages.count
    }
    
    private func checkForNewMessages() {
        let currentCount = gateway.messages.count
        guard currentCount > lastMessageCount else { return }
        
        // Get new messages
        let newMessages = gateway.messages.suffix(currentCount - lastMessageCount)
        lastMessageCount = currentCount
        
        // Speak new assistant messages if TTS is enabled
        guard speakResponses else { return }
        
        for message in newMessages where message.role == .assistant {
            // Clean up the message for speech (remove markdown, code blocks, etc.)
            let cleanedContent = cleanForSpeech(message.content)
            if !cleanedContent.isEmpty {
                textToSpeech.speak(cleanedContent)
            }
        }
    }
    
    private func cleanForSpeech(_ text: String) -> String {
        var result = text
        
        // Remove code blocks
        result = result.replacingOccurrences(of: "```[\\s\\S]*?```", with: "code block omitted", options: .regularExpression)
        
        // Remove inline code
        result = result.replacingOccurrences(of: "`[^`]+`", with: "", options: .regularExpression)
        
        // Remove markdown links but keep text
        result = result.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        
        // Remove markdown formatting
        result = result.replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\*([^*]+)\\*", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "__([^_]+)__", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "_([^_]+)_", with: "$1", options: .regularExpression)
        
        // Remove headers
        result = result.replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression)
        
        // Clean up multiple newlines
        result = result.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
