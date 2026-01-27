import Foundation
import Combine

/// ViewModel for the Home view
@MainActor
final class HomeViewModel: ObservableObject {
    // MARK: - Published State
    
    @Published private(set) var isRecording = false
    @Published private(set) var transcribedText = ""
    @Published private(set) var errorMessage: String?
    
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
    
    // MARK: - Computed Properties
    
    var canRecord: Bool {
        speechRecognizer.isAuthorized && connectionState.isConnected
    }
    
    // MARK: - Private Properties
    
    private let gateway: GatewayClient
    private let speechRecognizer: SpeechRecognizer
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(gateway: GatewayClient, speechRecognizer: SpeechRecognizer) {
        self.gateway = gateway
        self.speechRecognizer = speechRecognizer
        
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
        
        // Propagate gateway changes
        gateway.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}
