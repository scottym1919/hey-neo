import Foundation
import AVFoundation
import Combine
import Porcupine

/// Manages always-on wake word detection using Picovoice Porcupine.
///
/// Usage:
/// ```swift
/// let manager = WakeWordManager(accessKey: "YOUR_PICOVOICE_ACCESS_KEY")
/// manager.onWakeWordDetected = {
///     print("Wake word detected!")
/// }
/// try manager.startListening()
/// ```
///
/// By default, WakeWordManager configures its own AVAudioSession. If your app
/// manages the audio session elsewhere (e.g., SpeechRecognizer, TextToSpeech),
/// set `ownsAudioSession: false` at init to skip session configuration.
final class WakeWordManager: NSObject, ObservableObject {
    // MARK: - Published State

    @Published private(set) var isListening = false

    // MARK: - Callback

    /// Called on the main thread when the wake word is detected.
    var onWakeWordDetected: (() -> Void)?

    // MARK: - Configuration

    /// Picovoice access key from https://console.picovoice.ai/
    private let accessKey: String

    /// Built-in keyword to use. Set to nil and provide `customKeywordPath` instead
    /// for a custom .ppn file trained in the Picovoice console.
    private let builtInKeyword: Porcupine.BuiltInKeyword?

    /// Path to a custom .ppn keyword file. Used when `builtInKeyword` is nil.
    private let customKeywordPath: String?

    /// Sensitivity for keyword detection (0.0 to 1.0). Higher = more sensitive but more false positives.
    private let sensitivity: Float32

    /// Whether this manager owns and configures the AVAudioSession.
    /// Set to `false` if the app manages the audio session elsewhere.
    private let ownsAudioSession: Bool

    // MARK: - Private Properties

    private var porcupine: Porcupine?
    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?
    private let processingQueue = DispatchQueue(label: "com.hey-neo.wakeword", qos: .utility)
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    // MARK: - Initialization

    /// Create a WakeWordManager.
    ///
    /// - Parameters:
    ///   - accessKey: Your Picovoice access key.
    ///   - builtInKeyword: A built-in keyword for testing (default: `.porcupine`).
    ///                     Set to `nil` and provide `customKeywordPath` for production.
    ///   - customKeywordPath: Path to a custom `.ppn` keyword file.
    ///   - sensitivity: Detection sensitivity 0.0–1.0 (default: 0.5).
    ///   - ownsAudioSession: Whether this manager configures the AVAudioSession (default: true).
    init(
        accessKey: String,
        builtInKeyword: Porcupine.BuiltInKeyword? = .porcupine,
        customKeywordPath: String? = nil,
        sensitivity: Float32 = 0.5,
        ownsAudioSession: Bool = true
    ) {
        self.accessKey = accessKey
        self.builtInKeyword = builtInKeyword
        self.customKeywordPath = customKeywordPath
        self.sensitivity = sensitivity
        self.ownsAudioSession = ownsAudioSession
        super.init()
    }

    deinit {
        stopListeningSync()
    }

    // MARK: - Public Methods

    /// Start listening for the wake word.
    ///
    /// Requests microphone permission if needed, initializes Porcupine,
    /// configures the audio session (if `ownsAudioSession` is true),
    /// and begins processing microphone audio on a background queue.
    func startListening() throws {
        guard !isListening else {
            log("Already listening, ignoring startListening()")
            return
        }

        log("Starting wake word detection...")

        // Initialize Porcupine
        do {
            porcupine = try createPorcupineInstance()
        } catch {
            throw WakeWordError.porcupineInitFailed(underlying: error)
        }

        // Configure audio session if we own it
        if ownsAudioSession {
            do {
                try configureAudioSession()
            } catch {
                cleanup()
                throw WakeWordError.audioSessionFailed(underlying: error)
            }
        }

        // Set up audio engine and start processing
        do {
            try setupAudioEngine()
        } catch {
            cleanup()
            throw WakeWordError.audioEngineFailed(underlying: error)
        }

        // Observe interruptions and route changes
        registerNotifications()

        DispatchQueue.main.async { [weak self] in
            self?.isListening = true
        }
        log("Wake word detection started.")
    }

    /// Stop listening and release all resources.
    func stopListening() {
        stopListeningSync()
    }

    /// Restart listening after a failure or interruption.
    /// Stops the current session (if any) and starts fresh.
    func restart() throws {
        log("Restarting wake word detection...")
        stopListeningSync()
        try startListening()
    }

    // MARK: - Porcupine Instance

    private func createPorcupineInstance() throws -> Porcupine {
        if let keywordPath = customKeywordPath {
            log("Initializing Porcupine with custom keyword: \(keywordPath)")
            return try Porcupine(
                accessKey: accessKey,
                keywordPath: keywordPath,
                sensitivity: sensitivity
            )
        } else if let keyword = builtInKeyword {
            log("Initializing Porcupine with built-in keyword: \(keyword)")
            return try Porcupine(
                accessKey: accessKey,
                keyword: keyword,
                sensitivity: sensitivity
            )
        } else {
            throw WakeWordError.noKeywordConfigured
        }
    }

    // MARK: - Audio Session

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // Request a longer I/O buffer duration to reduce hardware interrupt frequency.
        // 0.06s (~60ms) balances latency vs power: fewer CPU wake-ups while still
        // detecting the wake word promptly. Default is ~0.02s (20ms).
        try session.setPreferredIOBufferDuration(0.06)
        log("Audio session configured (I/O buffer: \(session.ioBufferDuration)s).")
    }

    // MARK: - Audio Engine

    private func setupAudioEngine() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        guard let porcupine = porcupine else {
            throw WakeWordError.porcupineInitFailed(underlying: nil)
        }

        // Porcupine requires 16kHz mono 16-bit PCM
        let sampleRate = Double(porcupine.sampleRate)
        let frameLength = UInt32(porcupine.frameLength)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw WakeWordError.audioEngineFailed(underlying: nil)
        }

        // Determine if we need to resample
        let needsConversion = hardwareFormat.sampleRate != sampleRate
            || hardwareFormat.channelCount != 1
            || hardwareFormat.commonFormat != .pcmFormatInt16

        if needsConversion {
            log("Audio conversion required: \(hardwareFormat) -> \(targetFormat)")
            // Create an intermediate float format for the converter input
            guard let converterInputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: hardwareFormat.sampleRate,
                channels: hardwareFormat.channelCount,
                interleaved: false
            ) else {
                throw WakeWordError.audioEngineFailed(underlying: nil)
            }
            let converter = AVAudioConverter(from: converterInputFormat, to: targetFormat)
            guard let converter = converter else {
                throw WakeWordError.audioEngineFailed(underlying: nil)
            }
            self.audioConverter = converter
        } else {
            log("Hardware format matches Porcupine requirements, no conversion needed.")
            self.audioConverter = nil
        }

        // Accumulation buffer for Porcupine frames
        var sampleBuffer = [Int16]()
        let requiredSamples = Int(frameLength)

        // Install tap on input node.
        // Use a larger buffer (4096 samples) to reduce callback frequency and CPU wake-ups.
        // We accumulate samples in sampleBuffer anyway, so larger batches are fine.
        let tapBufferSize: UInt32 = 4096
        let tapFormat = needsConversion ? hardwareFormat : nil
        inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: tapFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            self.processingQueue.async { [weak self] in
                guard let self = self, let porcupine = self.porcupine else { return }

                let samples: [Int16]

                if let converter = self.audioConverter {
                    // Convert to 16kHz mono Int16
                    guard let converted = self.convertBuffer(buffer, using: converter, frameCapacity: frameLength) else {
                        return
                    }
                    samples = converted
                } else {
                    // Already in correct format — read Int16 samples directly
                    let frameCount = Int(buffer.frameLength)
                    guard let channelData = buffer.int16ChannelData else { return }
                    samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
                }

                sampleBuffer.append(contentsOf: samples)

                // Process complete frames
                while sampleBuffer.count >= requiredSamples {
                    let frame = Array(sampleBuffer.prefix(requiredSamples))
                    sampleBuffer.removeFirst(requiredSamples)

                    do {
                        let keywordIndex = try porcupine.process(pcm: frame)
                        if keywordIndex >= 0 {
                            self.log("Wake word detected! (keyword index: \(keywordIndex))")
                            DispatchQueue.main.async { [weak self] in
                                self?.onWakeWordDetected?()
                            }
                        }
                    } catch {
                        self.log("Porcupine process error: \(error)")
                    }
                }
            }
        }

        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        log("Audio engine started.")
    }

    /// Convert an audio buffer to Porcupine's required format (16kHz mono Int16).
    private func convertBuffer(
        _ inputBuffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        frameCapacity: UInt32
    ) -> [Int16]? {
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: frameCapacity
        ) else {
            return nil
        }

        var error: NSError?
        var hasData = true
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if hasData {
                hasData = false
                outStatus.pointee = .haveData
                return inputBuffer
            }
            outStatus.pointee = .noDataNow
            return nil
        }

        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        guard status != .error, error == nil, outputBuffer.frameLength > 0 else {
            return nil
        }

        let frameCount = Int(outputBuffer.frameLength)
        guard let channelData = outputBuffer.int16ChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
    }

    // MARK: - Notifications

    private func registerNotifications() {
        let nc = NotificationCenter.default

        interruptionObserver = nc.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }

        routeChangeObserver = nc.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }
    }

    private func unregisterNotifications() {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            log("Audio session interrupted — pausing wake word detection.")
            audioEngine?.pause()

        case .ended:
            log("Audio session interruption ended — resuming.")
            let options = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: options)
                .contains(.shouldResume)

            if shouldResume {
                do {
                    try audioEngine?.start()
                    log("Audio engine resumed after interruption.")
                } catch {
                    log("Failed to resume audio engine: \(error)")
                    // Attempt full restart
                    try? restart()
                }
            }

        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        log("Audio route changed: \(reason)")

        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable:
            // Input device changed — restart to pick up new hardware format
            log("Input device changed, restarting audio engine...")
            do {
                try restart()
            } catch {
                log("Failed to restart after route change: \(error)")
            }
        default:
            break
        }
    }

    // MARK: - Cleanup

    private func stopListeningSync() {
        guard isListening || audioEngine != nil || porcupine != nil else { return }
        log("Stopping wake word detection...")
        cleanup()
        DispatchQueue.main.async { [weak self] in
            self?.isListening = false
        }
        log("Wake word detection stopped.")
    }

    private func cleanup() {
        unregisterNotifications()

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        audioConverter = nil

        porcupine?.delete()
        porcupine = nil

        if ownsAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    // MARK: - Logging

    private func log(_ message: String) {
        print("[WakeWordManager] \(message)")
    }
}

// MARK: - Errors

enum WakeWordError: LocalizedError {
    case porcupineInitFailed(underlying: Error?)
    case audioSessionFailed(underlying: Error?)
    case audioEngineFailed(underlying: Error?)
    case noKeywordConfigured

    var errorDescription: String? {
        switch self {
        case .porcupineInitFailed(let error):
            if let error = error {
                return "Failed to initialize Porcupine: \(error.localizedDescription)"
            }
            return "Failed to initialize Porcupine (invalid access key or missing keyword file?)"
        case .audioSessionFailed(let error):
            return "Failed to configure audio session: \(error?.localizedDescription ?? "unknown")"
        case .audioEngineFailed(let error):
            return "Failed to start audio engine: \(error?.localizedDescription ?? "unknown")"
        case .noKeywordConfigured:
            return "No wake word keyword configured. Provide either a built-in keyword or a custom .ppn file path."
        }
    }
}
