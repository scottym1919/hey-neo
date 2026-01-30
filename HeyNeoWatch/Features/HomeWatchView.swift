import SwiftUI
import WatchKit

/// Main watch view - relays to phone for speech recognition
struct HomeWatchView: View {
    @EnvironmentObject private var connectivity: WatchPhoneConnectivity
    
    @State private var isWaiting = false
    @State private var showTextInput = false
    
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
                
                if isWaiting {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Sending...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    // Dictation button - uses watchOS built-in dictation
                    Button {
                        showTextInput = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.blue)
                                .frame(width: 60, height: 60)
                            
                            Image(systemName: "mic.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!connectivity.isReachable)
                    .opacity(connectivity.isReachable ? 1.0 : 0.5)
                    
                    Text("Tap to speak")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                if !connectivity.isReachable {
                    Text("iPhone not reachable")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .padding()
            .navigationTitle("Hey Neo")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showTextInput) {
                DictationView { text in
                    sendMessage(text)
                }
            }
            .onAppear {
                connectivity.refreshConnectionState()
            }
        }
    }
    
    private func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        isWaiting = true
        WKInterfaceDevice.current().play(.click)
        
        connectivity.sendChatMessage(trimmed)
        
        // Reset after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isWaiting = false
            WKInterfaceDevice.current().play(.success)
        }
    }
}

/// Simple dictation input view
struct DictationView: View {
    @Environment(\.dismiss) private var dismiss
    let onSubmit: (String) -> Void
    
    @State private var text = ""
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Say your message")
                .font(.headline)
            
            TextField("Message", text: $text)
                .multilineTextAlignment(.center)
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundStyle(.red)
                
                Button("Send") {
                    onSubmit(text)
                    dismiss()
                }
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
    }
}

#Preview {
    HomeWatchView()
        .environmentObject(WatchPhoneConnectivity())
}
