# Hey Neo 🎙️

A native iOS + watchOS voice assistant app that connects to [Clawdbot Gateway](https://github.com/clawd-app/clawdbot).

Say "Hey Neo" (or tap the button) to send voice commands to your AI assistant.

## Features

### iOS App
- 🎤 **Push-to-talk** - Hold to record, release to send
- 🗣️ **On-device speech recognition** - Privacy-first, no cloud transcription
- 🔌 **WebSocket connection** to Clawdbot Gateway
- 💬 **Chat interface** with streaming responses
- ⚙️ **Settings** - Gateway URL and token (stored securely in Keychain)

### watchOS App
- ⌚ **Push-to-talk on your wrist**
- 📱 **Relays through iPhone** via WatchConnectivity
- 🔔 **Haptic feedback** for recording start/stop

## Requirements

- iOS 17.0+
- watchOS 10.0+
- Xcode 15.4+
- A running [Clawdbot Gateway](https://github.com/clawd-app/clawdbot)

## Setup

### 1. Clone the repo
```bash
git clone https://github.com/scottym1919/hey-neo.git
cd hey-neo
```

### 2. Open in Xcode
```bash
open HeyNeo.xcodeproj
```

### 3. Configure signing
- Select the HeyNeo target
- Go to Signing & Capabilities
- Set your Development Team
- Repeat for HeyNeoWatch target

### 4. Build and run
- Select an iPhone simulator or device
- Press ⌘R to build and run

### 5. Configure the app
1. Open Settings in the app
2. Enter your Gateway URL (e.g., `192.168.1.100:18789` or `myhost.tail12345.ts.net:18789`)
3. Enter your Gateway token (`CLAWDBOT_GATEWAY_TOKEN`)
4. Save and tap Connect

## Gateway Protocol

The app connects via WebSocket to `ws://<host>:18789/ws` using the Clawdbot Gateway protocol v3.

**Handshake:**
```json
{
  "type": "req",
  "id": "1",
  "method": "connect",
  "params": {
    "minProtocol": 3,
    "maxProtocol": 3,
    "client": {
      "id": "hey-neo-ios",
      "version": "1.0.0",
      "platform": "ios",
      "mode": "operator"
    },
    "role": "operator",
    "scopes": ["operator.read", "operator.write"],
    "auth": { "token": "<your_token>" }
  }
}
```

**Send message:**
```json
{
  "type": "req",
  "id": "2",
  "method": "chat.send",
  "params": { "text": "What's the weather?" }
}
```

## Project Structure

```
hey-neo/
├── HeyNeo/                     # iOS App
│   ├── App/
│   │   └── HeyNeoApp.swift
│   ├── Core/
│   │   ├── Gateway/
│   │   │   └── GatewayClient.swift
│   │   ├── Speech/
│   │   │   └── SpeechRecognizer.swift
│   │   ├── Settings/
│   │   │   └── AppSettings.swift
│   │   └── WatchConnectivityManager.swift
│   ├── Features/
│   │   ├── Home/
│   │   │   ├── HomeView.swift
│   │   │   └── HomeViewModel.swift
│   │   ├── Settings/
│   │   │   └── SettingsView.swift
│   │   └── Conversation/
│   │       └── MessageBubble.swift
│   └── Resources/
│       └── Assets.xcassets
├── HeyNeoWatch/                # watchOS App
│   ├── App/
│   │   └── HeyNeoWatchApp.swift
│   ├── Core/
│   │   └── WatchPhoneConnectivity.swift
│   ├── Features/
│   │   └── HomeWatchView.swift
│   └── Resources/
│       └── Assets.xcassets
├── Shared/                     # Shared code
│   └── Models/
│       ├── Message.swift
│       ├── ConnectionState.swift
│       └── GatewayMessage.swift
└── HeyNeo.xcodeproj
```

## Roadmap

### Phase 1: Core (MVP) ✅
- [x] iOS app with push-to-talk
- [x] Speech recognition (on-device)
- [x] WebSocket connection to Gateway
- [x] Send/receive messages
- [x] Settings screen
- [x] watchOS companion app

### Phase 2: Voice Wake
- [ ] Always-on "Hey Neo" wake word detection
- [ ] Background audio session
- [ ] Configurable wake words

### Phase 3: Polish
- [ ] Haptic feedback on iOS
- [ ] Audio chimes
- [ ] Conversation history
- [ ] Widget for quick access
- [ ] Siri Shortcuts integration

## Permissions

The app requires:
- **Microphone** - To record your voice
- **Speech Recognition** - To transcribe speech on-device

## License

MIT

## Contributing

PRs welcome! See [PLAN.md](PLAN.md) for architecture details.
