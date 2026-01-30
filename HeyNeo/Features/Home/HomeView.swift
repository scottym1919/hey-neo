import SwiftUI

/// Main view with push-to-talk button and conversation display
struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var textToSpeech: TextToSpeech
    
    @State private var showSettings = false
    
    init(gateway: GatewayClient, speechRecognizer: SpeechRecognizer, textToSpeech: TextToSpeech, settings: AppSettings) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(
            gateway: gateway,
            speechRecognizer: speechRecognizer,
            textToSpeech: textToSpeech,
            settings: settings
        ))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Connection status bar
                connectionStatusBar
                
                // Conversation area
                conversationArea
                
                // Push-to-talk button
                pushToTalkArea
            }
            .navigationTitle("Hey Neo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 16) {
                        Button {
                            viewModel.clearConversation()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(viewModel.messages.isEmpty)
                        
                        // TTS toggle
                        Button {
                            viewModel.speakResponses.toggle()
                        } label: {
                            Image(systemName: viewModel.speakResponses ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        }
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        // Stop speaking button (when active)
                        if viewModel.isSpeaking {
                            Button {
                                viewModel.stopSpeaking()
                            } label: {
                                Image(systemName: "stop.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                        
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gear")
                        }
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .task {
                await viewModel.onAppear()
            }
        }
    }
    
    // MARK: - Subviews
    
    private var connectionStatusBar: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(viewModel.connectionState.displayText)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            if !viewModel.connectionState.isConnected {
                Button("Connect") {
                    Task {
                        await viewModel.connect()
                    }
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
    
    private var statusColor: Color {
        switch viewModel.connectionState {
        case .disconnected: return .gray
        case .connecting: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }
    
    private var conversationArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    
                    // Show streaming content if available
                    if !viewModel.streamingContent.isEmpty {
                        MessageBubble(
                            message: Message(
                                role: .assistant,
                                content: viewModel.streamingContent
                            )
                        )
                        .opacity(0.7)
                    }
                    
                    // Show transcription while recording
                    if viewModel.isRecording && !viewModel.transcribedText.isEmpty {
                        HStack {
                            Text(viewModel.transcribedText)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .italic()
                            Spacer()
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let lastMessage = viewModel.messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var pushToTalkArea: some View {
        VStack(spacing: 16) {
            // Error message if any
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            // Push-to-talk button
            PushToTalkButton(
                isRecording: viewModel.isRecording,
                isEnabled: viewModel.canRecord
            ) {
                // On press
                Task {
                    await viewModel.startRecording()
                }
            } onRelease: {
                // On release
                Task {
                    await viewModel.stopRecordingAndSend()
                }
            }
            
            Text(viewModel.isRecording ? "Release to send" : "Hold to talk")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

// MARK: - Push-to-Talk Button

struct PushToTalkButton: View {
    let isRecording: Bool
    let isEnabled: Bool
    let onPress: () -> Void
    let onRelease: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Circle()
            .fill(buttonColor)
            .frame(width: 80, height: 80)
            .overlay {
                Image(systemName: isRecording ? "waveform" : "mic.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor, isActive: isRecording)
            }
            .shadow(color: buttonColor.opacity(0.5), radius: isRecording ? 20 : 10)
            .scaleEffect(isPressed ? 1.1 : 1.0)
            .animation(.spring(response: 0.3), value: isPressed)
            .animation(.spring(response: 0.3), value: isRecording)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard isEnabled && !isPressed else { return }
                        isPressed = true
                        onPress()
                    }
                    .onEnded { _ in
                        guard isPressed else { return }
                        isPressed = false
                        onRelease()
                    }
            )
            .opacity(isEnabled ? 1.0 : 0.5)
            .allowsHitTesting(isEnabled)
    }
    
    private var buttonColor: Color {
        if isRecording {
            return .red
        } else if isEnabled {
            return .blue
        } else {
            return .gray
        }
    }
}

#Preview {
    let settings = AppSettings()
    let gateway = GatewayClient(settings: settings)
    let speech = SpeechRecognizer()
    let tts = TextToSpeech()
    
    HomeView(gateway: gateway, speechRecognizer: speech, textToSpeech: tts, settings: settings)
        .environmentObject(settings)
        .environmentObject(tts)
}
