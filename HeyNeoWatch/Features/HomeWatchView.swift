import SwiftUI
import Speech
import AVFoundation

/// Main watch view with push-to-talk
struct HomeWatchView: View {
    @EnvironmentObject private var connectivity: WatchPhoneConnectivity
    
    @State private var isRecording = false
    @State private var transcribedText = ""
    @State private var errorMessage: String?
    @State private var speechRecognizer: SFSpeechRecognizer?
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var audioEngine: AVAudioEngine?
    @State private var isAuthorized = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Connection status
                HStack {
                    Circle()
                        .fill(connectivity.isConnected ? .green : .gray)
                        .frame(width: 8, height: 8)
                    
                    Text(connectivity.isConnected ? "Connected" : "Disconnected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                // Last response (if any)
                if let response = connectivity.lastResponse {
                    ScrollView {
                        Text(response)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 4)
                    }
                    .frame(maxHeight: 60)
                }
                
                Spacer()
                
                // Transcription while recording
                if isRecording && !transcribedText.isEmpty {
                    Text(transcribedText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                // Push-to-talk button
                Button {
                    // Toggle recording
                } label: {
                    ZStack {
                        Circle()
                            .fill(isRecording ? .red : .blue)
                            .frame(width: 60, height: 60)
                        
                        Image(systemName: isRecording ? "waveform" : "mic.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !isRecording {
                                startRecording()
                            }
                        }
                        .onEnded { _ in
                            stopRecordingAndSend()
                        }
                )
                .disabled(!isAuthorized || !connectivity.isReachable)
                .opacity((isAuthorized && connectivity.isReachable) ? 1.0 : 0.5)
                
                Text(isRecording ? "Release to send" : "Hold to talk")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            .padding()
            .navigationTitle("Hey Neo")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await requestAuthorization()
                connectivity.refreshConnectionState()
            }
        }
    }
    
    // MARK: - Speech Recognition
    
    private func requestAuthorization() async {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        
        guard speechStatus == .authorized else {
            errorMessage = "Speech not authorized"
            return
        }
        
        let audioStatus = await AVAudioApplication.requestRecordPermission()
        
        guard audioStatus else {
            errorMessage = "Mic not authorized"
            return
        }
        
        isAuthorized = true
    }
    
    private func startRecording() {
        guard isAuthorized,
              let speechRecognizer = speechRecognizer,
              speechRecognizer.isAvailable else {
            return
        }
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            audioEngine = AVAudioEngine()
            guard let audioEngine = audioEngine else { return }
            
            let inputNode = audioEngine.inputNode
            
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else { return }
            
            if speechRecognizer.supportsOnDeviceRecognition {
                recognitionRequest.requiresOnDeviceRecognition = true
            }
            recognitionRequest.shouldReportPartialResults = true
            
            transcribedText = ""
            
            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
                if let result = result {
                    transcribedText = result.bestTranscription.formattedString
                }
            }
            
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                self.recognitionRequest?.append(buffer)
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            
            isRecording = true
            errorMessage = nil
            
            // Haptic feedback
            WKInterfaceDevice.current().play(.start)
            
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func stopRecordingAndSend() {
        guard isRecording else { return }
        
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        try? AVAudioSession.sharedInstance().setActive(false)
        
        isRecording = false
        
        // Haptic feedback
        WKInterfaceDevice.current().play(.stop)
        
        // Send if we have text
        let finalText = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        transcribedText = ""
        
        guard !finalText.isEmpty else { return }
        
        connectivity.sendChatMessage(finalText)
        
        // Success haptic
        WKInterfaceDevice.current().play(.success)
    }
}

#Preview {
    HomeWatchView()
        .environmentObject(WatchPhoneConnectivity())
}
