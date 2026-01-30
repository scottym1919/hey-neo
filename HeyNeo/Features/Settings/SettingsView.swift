import SwiftUI

/// Settings view for configuring Gateway connection
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    
    @State private var gatewayURL: String = ""
    @State private var gatewayToken: String = ""
    @State private var showToken = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Gateway URL", text: $gatewayURL)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    
                    Text("Example: 192.168.1.100:18789 or myhost.tail12345.ts.net:18789")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Gateway Connection")
                } footer: {
                    Text("Enter the host and port of your Clawdbot Gateway")
                }
                
                Section {
                    HStack {
                        if showToken {
                            TextField("Gateway Token", text: $gatewayToken)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("Gateway Token", text: $gatewayToken)
                        }
                        
                        Button {
                            showToken.toggle()
                        } label: {
                            Image(systemName: showToken ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Authentication")
                } footer: {
                    Text("Your Gateway token (CLAWDBOT_GATEWAY_TOKEN)")
                }
                
                Section {
                    Toggle("Auto-connect on launch", isOn: $settings.autoConnect)
                    Toggle("Speak responses aloud", isOn: $settings.speakResponses)
                } header: {
                    Text("Behavior")
                } footer: {
                    Text("When enabled, Neo will speak assistant responses using text-to-speech")
                }
                
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSettings()
                        dismiss()
                    }
                }
            }
            .onAppear {
                gatewayURL = settings.gatewayURL
                gatewayToken = settings.gatewayToken
            }
        }
    }
    
    private func saveSettings() {
        settings.gatewayURL = gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.gatewayToken = gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings())
}
