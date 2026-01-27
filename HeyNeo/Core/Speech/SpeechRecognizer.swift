import Foundation
import Speech
import AVFoundation

/// Manages speech recognition using the Speech framework
@MainActor
final class SpeechRecognizer: ObservableObject {
    // MARK: - Published State
    
    @Published private(set) var isRecording = false
    @Published private(set) var transcribedText = ""
    @Published private(set) var isAuthorized = false
    @Published private(set) var errorMessage: String?
    
    // MARK: - Private Properties
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    
    // MARK: - Initialization
    
    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }
    
    // MARK: - Public Methods
    
    /// Request authorization for speech recognition and microphone
    func requestAuthorization() async {
        // Request speech recognition permission
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        
        guard speechStatus == .authorized else {
            errorMessage = "Speech recognition not authorized"
            isAuthorized = false
            return
        }
        
        // Request microphone permission
        let audioStatus = await AVAudioApplication.requestRecordPermission()
        
        guard audioStatus else {
            errorMessage = "Microphone access not authorized"
            isAuthorized = false
            return
        }
        
        isAuthorized = true
        errorMessage = nil
    }
    
    /// Start recording and transcribing speech
    func startRecording() async throws {
        guard isAuthorized else {
            throw SpeechRecognizerError.notAuthorized
        }
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw SpeechRecognizerError.recognizerNotAvailable
        }
        
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        // Create audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw SpeechRecognizerError.audioEngineError
        }
        
        let inputNode = audioEngine.inputNode
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw SpeechRecognizerError.requestError
        }
        
        // Configure for on-device recognition if available
        if speechRecognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
        }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.addsPunctuation = true
        
        // Reset transcribed text
        transcribedText = ""
        
        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                if let result = result {
                    self.transcribedText = result.bestTranscription.formattedString
                }
                
                if let error = error {
                    print("[SpeechRecognizer] Recognition error: \(error)")
                    // Only set error if not a cancellation
                    if (error as NSError).code != 216 { // Cancelled error code
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
        
        // Configure audio input
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()
        
        isRecording = true
        errorMessage = nil
    }
    
    /// Stop recording and return the final transcription
    func stopRecording() -> String {
        // Stop audio engine
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        
        // End recognition request
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        // Cancel task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false)
        
        isRecording = false
        
        // Return the final transcription
        let finalText = transcribedText
        return finalText
    }
    
    /// Cancel recording without returning results
    func cancelRecording() {
        _ = stopRecording()
        transcribedText = ""
    }
}

// MARK: - Errors

enum SpeechRecognizerError: LocalizedError {
    case notAuthorized
    case recognizerNotAvailable
    case audioEngineError
    case requestError
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition not authorized"
        case .recognizerNotAvailable:
            return "Speech recognizer not available"
        case .audioEngineError:
            return "Could not create audio engine"
        case .requestError:
            return "Could not create recognition request"
        }
    }
}
