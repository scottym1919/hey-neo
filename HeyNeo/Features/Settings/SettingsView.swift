import SwiftUI

/// Settings view for configuring Gateway connection and wake word
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var gatewayURL: String = ""
    @State private var gatewayToken: String = ""
    @State private var showToken = false
    @State private var picovoiceAccessKey: String = ""
    @State private var showAccessKey = false

    /// Built-in Porcupine keywords available for testing.
    private let builtInKeywords = [
        "porcupine", "alexa", "blueberry", "bumblebee",
        "computer", "grapevine", "grasshopper", "hey google",
        "hey siri", "jarvis", "ok google", "picovoice",
        "porcupine", "terminator"
    ]

    var body: some View {
        NavigationStack {
            Form {
                gatewaySection
                authSection
                behaviorSection
                wakeWordSection
                wakeWordKeywordSection
                wakeWordTipsSection
                aboutSection
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
                picovoiceAccessKey = settings.picovoiceAccessKey
            }
        }
    }

    // MARK: - Gateway

    private var gatewaySection: some View {
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
    }

    // MARK: - Auth

    private var authSection: some View {
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
    }

    // MARK: - Behavior

    private var behaviorSection: some View {
        Section {
            Toggle("Auto-connect on launch", isOn: $settings.autoConnect)
            Toggle("Speak responses aloud", isOn: $settings.speakResponses)
        } header: {
            Text("Behavior")
        } footer: {
            Text("When enabled, Neo will speak assistant responses using text-to-speech")
        }
    }

    // MARK: - Wake Word

    private var wakeWordSection: some View {
        Section {
            Toggle("Enable wake word", isOn: $settings.wakeWordEnabled)

            if settings.wakeWordEnabled {
                // Picovoice access key
                HStack {
                    if showAccessKey {
                        TextField("Picovoice Access Key", text: $picovoiceAccessKey)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("Picovoice Access Key", text: $picovoiceAccessKey)
                    }

                    Button {
                        showAccessKey.toggle()
                    } label: {
                        Image(systemName: showAccessKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Text("Get your free key at console.picovoice.ai")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Sensitivity slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Sensitivity")
                        Spacer()
                        Text(sensitivityLabel)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.wakeWordSensitivity, in: 0.0...1.0, step: 0.1)
                }

                Text("Higher sensitivity detects the wake word more easily but may trigger on similar-sounding words. Start at 0.5 and adjust.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label("Wake Word", systemImage: "waveform.circle")
        } footer: {
            if settings.wakeWordEnabled {
                Text("The app will listen for your wake word and activate hands-free when detected")
            } else {
                Text("Enable to activate Neo by saying a wake word, like \"Hey Siri\" but for your app")
            }
        }
    }

    private var sensitivityLabel: String {
        switch settings.wakeWordSensitivity {
        case 0.0..<0.3: return "Low"
        case 0.3..<0.7: return "Medium"
        default: return "High"
        }
    }

    // MARK: - Keyword Selection

    private var wakeWordKeywordSection: some View {
        Group {
            if settings.wakeWordEnabled {
                Section {
                    // Built-in keyword picker
                    Picker("Keyword", selection: $settings.wakeWordKeyword) {
                        ForEach(builtInKeywords, id: \.self) { keyword in
                            Text(keyword.localizedCapitalized)
                                .tag(keyword)
                        }
                        Text("Custom (.ppn file)")
                            .tag("custom")
                    }

                    if settings.wakeWordKeyword == "custom" {
                        TextField("Custom keyword filename", text: $settings.wakeWordCustomFile)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()

                        Text("Enter the filename of your .ppn file (without extension). The file must be added to the Xcode project bundle.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Keyword")
                } footer: {
                    if settings.wakeWordKeyword == "custom" {
                        Text("Train a custom wake word at console.picovoice.ai, download the iOS .ppn file, and add it to your project")
                    } else {
                        Text("Using built-in keyword \"\(settings.wakeWordKeyword.localizedCapitalized)\" for testing. Create a custom keyword for production use.")
                    }
                }
            }
        }
    }

    // MARK: - Wake Word Tips

    private var wakeWordTipsSection: some View {
        Group {
            if settings.wakeWordEnabled {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        tipRow(
                            icon: "checkmark.circle.fill",
                            color: .green,
                            title: "Use 2-4 syllables",
                            detail: "\"Hey Neo\" or \"Ok Neo\" work great. Short enough to say quickly, long enough to avoid false triggers."
                        )

                        tipRow(
                            icon: "checkmark.circle.fill",
                            color: .green,
                            title: "Mix consonants and vowels",
                            detail: "Words with clear consonants (N, T, K, P) are easier to detect. \"Neo\" has a strong N onset."
                        )

                        tipRow(
                            icon: "checkmark.circle.fill",
                            color: .green,
                            title: "Make it distinct",
                            detail: "Choose something you won't say in normal conversation. Adding \"Hey\" or \"Ok\" as a prefix helps."
                        )

                        Divider()

                        tipRow(
                            icon: "xmark.circle.fill",
                            color: .red,
                            title: "Avoid single syllables",
                            detail: "\"Go\" or \"Start\" are too short — high false positive rate."
                        )

                        tipRow(
                            icon: "xmark.circle.fill",
                            color: .red,
                            title: "Avoid common words",
                            detail: "\"Hello\" or \"Okay\" will trigger constantly in normal speech."
                        )

                        tipRow(
                            icon: "xmark.circle.fill",
                            color: .red,
                            title: "Avoid similar sounds",
                            detail: "If your wake word sounds like a common word (\"Neo\" vs \"no\"), add a prefix like \"Hey Neo\"."
                        )
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Good examples")
                            .font(.subheadline.weight(.semibold))
                        Text("\"Hey Neo\"  /  \"Ok Neo\"  /  \"Neo Wake\"  /  \"Clawdbot\"")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Label("Tips for Custom Wake Words", systemImage: "lightbulb")
                } footer: {
                    Text("To create a custom wake word, visit console.picovoice.ai, train your keyword, download the .ppn file for iOS, and add it to the Xcode project.")
                }
            }
        }
    }

    private func tipRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.body)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
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

    // MARK: - Save

    private func saveSettings() {
        settings.gatewayURL = gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.gatewayToken = gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.picovoiceAccessKey = picovoiceAccessKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings())
}
