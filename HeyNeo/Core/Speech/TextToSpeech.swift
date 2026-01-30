import AVFoundation
import Combine

/// Text-to-speech manager using AVSpeechSynthesizer
@MainActor
final class TextToSpeech: NSObject, ObservableObject {
    // MARK: - Published State
    
    @Published private(set) var isSpeaking = false
    
    // MARK: - Private Properties
    
    private let synthesizer = AVSpeechSynthesizer()
    private var audioSession: AVAudioSession { AVAudioSession.sharedInstance() }
    
    // Voice settings
    private var voiceIdentifier: String?
    private var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    private var pitch: Float = 1.0
    private var volume: Float = 1.0
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        synthesizer.delegate = self
        configureDefaultVoice()
    }
    
    // MARK: - Public Methods
    
    /// Speak the given text
    func speak(_ text: String) {
        // Don't interrupt if already speaking - queue it
        let utterance = AVSpeechUtterance(string: text)
        
        // Configure voice
        if let voiceId = voiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: voiceId) {
            utterance.voice = voice
        } else {
            // Fallback to best available English voice
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        
        utterance.rate = rate
        utterance.pitchMultiplier = pitch
        utterance.volume = volume
        
        // Configure audio session for playback
        configureAudioSession()
        
        synthesizer.speak(utterance)
        isSpeaking = true
    }
    
    /// Stop speaking immediately
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
    
    /// Pause speaking
    func pause() {
        synthesizer.pauseSpeaking(at: .word)
    }
    
    /// Resume speaking
    func resume() {
        synthesizer.continueSpeaking()
    }
    
    /// Configure voice settings
    func configure(voiceIdentifier: String? = nil, rate: Float? = nil, pitch: Float? = nil, volume: Float? = nil) {
        if let voiceId = voiceIdentifier {
            self.voiceIdentifier = voiceId
        }
        if let r = rate {
            self.rate = r
        }
        if let p = pitch {
            self.pitch = p
        }
        if let v = volume {
            self.volume = v
        }
    }
    
    /// Get available voices for a language
    static func availableVoices(for language: String = "en") -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
    }
    
    /// Get premium/enhanced voices
    static func premiumVoices(for language: String = "en") -> [AVSpeechSynthesisVoice] {
        availableVoices(for: language)
            .filter { $0.quality == .enhanced || $0.quality == .premium }
    }
    
    // MARK: - Private Methods
    
    private func configureDefaultVoice() {
        // Try to find a premium English voice
        let premiumVoices = Self.premiumVoices(for: "en-US")
        if let bestVoice = premiumVoices.first {
            voiceIdentifier = bestVoice.identifier
            print("[TTS] Using premium voice: \(bestVoice.name)")
        } else {
            // Fallback to any enhanced voice
            let enhanced = Self.premiumVoices(for: "en")
            if let voice = enhanced.first {
                voiceIdentifier = voice.identifier
                print("[TTS] Using enhanced voice: \(voice.name)")
            }
        }
        
        // Slightly faster than default for snappier responses
        rate = AVSpeechUtteranceDefaultSpeechRate * 1.1
    }
    
    private func configureAudioSession() {
        do {
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true)
        } catch {
            print("[TTS] Audio session error: \(error)")
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TextToSpeech: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = true
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            // Deactivate audio session when done
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
        }
    }
}
