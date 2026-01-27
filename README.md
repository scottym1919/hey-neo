# Hey Neo 🎙️

A native iOS + watchOS voice assistant app for [Clawdbot](https://github.com/clawdbot/clawdbot).

Say "Hey Neo" or tap to talk — your message goes straight to your personal AI assistant.

## Features

- 🎤 **Push-to-talk** on iPhone and Apple Watch
- 🗣️ **Voice wake** detection (say "Hey Neo")
- ⚡ **Direct WebSocket** connection to Clawdbot Gateway
- 🔒 **On-device** speech recognition (privacy-first)
- ⌚ **watchOS companion** for quick voice commands

## Requirements

- iOS 17.0+
- watchOS 10.0+
- Xcode 15.0+
- A running [Clawdbot Gateway](https://github.com/clawdbot/clawdbot)

## Setup

1. Clone this repo
2. Open `HeyNeo.xcodeproj` in Xcode
3. Configure your Gateway URL in Settings
4. Build and run on your device

## Configuration

In the app's Settings, enter:
- **Gateway URL:** Your Clawdbot gateway address (e.g., `192.168.1.100:18789`)
- **Auth Token:** Your gateway token (from `clawdbot dashboard`)

## Architecture

```
iPhone App ──WebSocket──▶ Clawdbot Gateway ──▶ AI Response
    │
    │ WatchConnectivity
    ▼
Apple Watch
```

## License

MIT

---

Built with ⚡ by Neo
