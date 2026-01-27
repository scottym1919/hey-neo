# Hey Neo - iOS + watchOS Voice Assistant for Clawdbot

## Overview

A native iOS app with watchOS companion that lets you say "Hey Neo" (or tap) to send voice commands to your Clawdbot Gateway. Think of it as a personal Siri that actually does what you want.

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────────┐
│   iPhone    │────▶│  Gateway    │────▶│   Clawdbot      │
│  Hey Neo    │◀────│  WebSocket  │◀────│   (responds)    │
└─────────────┘     └─────────────┘     └─────────────────┘
       │
       │ WatchConnectivity
       ▼
┌─────────────┐
│ Apple Watch │
│  Hey Neo    │
└─────────────┘
```

## Features

### Phase 1: Core (MVP) ✅
- [x] iOS app with push-to-talk button
- [x] Speech recognition (on-device)
- [x] WebSocket connection to Clawdbot Gateway
- [x] Send transcribed text as messages
- [x] Receive and display responses
- [x] Settings: Gateway URL, auth token
- [x] watchOS companion with push-to-talk

### Phase 2: Voice Wake
- [ ] Always-on voice wake detection ("Hey Neo")
- [ ] Background audio session handling
- [ ] Configurable wake words

### Phase 3: Polish
- [ ] Haptic feedback
- [ ] Audio feedback (chimes)
- [ ] Conversation history view
- [ ] Widget for quick access
- [ ] Siri Shortcuts integration (as backup)

## Tech Stack

- **Language:** Swift 6
- **UI:** SwiftUI
- **Minimum iOS:** 17.0
- **Minimum watchOS:** 10.0
- **Networking:** URLSessionWebSocketTask (native WebSocket)
- **Speech:** Speech framework (on-device recognition)
- **Watch Communication:** WatchConnectivity

## Project Structure

```
hey-neo/
├── HeyNeo/                     # iOS App
│   ├── App/
│   │   ├── HeyNeoApp.swift
│   │   └── AppDelegate.swift
│   ├── Core/
│   │   ├── Gateway/
│   │   │   ├── GatewayClient.swift      # WebSocket client
│   │   │   ├── GatewayMessage.swift     # Message types
│   │   │   └── GatewayAuth.swift        # Auth handling
│   │   ├── Speech/
│   │   │   ├── SpeechRecognizer.swift   # Speech-to-text
│   │   │   └── VoiceWakeDetector.swift  # Wake word detection
│   │   └── Settings/
│   │       └── AppSettings.swift        # UserDefaults wrapper
│   ├── Features/
│   │   ├── Home/
│   │   │   ├── HomeView.swift           # Main UI
│   │   │   └── HomeViewModel.swift
│   │   ├── Settings/
│   │   │   ├── SettingsView.swift
│   │   │   └── SettingsViewModel.swift
│   │   └── Conversation/
│   │       ├── ConversationView.swift
│   │       └── MessageBubble.swift
│   ├── Shared/
│   │   ├── Extensions/
│   │   ├── Components/
│   │   └── Utilities/
│   └── Resources/
│       ├── Assets.xcassets
│       └── Sounds/
├── HeyNeoWatch/                # watchOS App
│   ├── App/
│   │   └── HeyNeoWatchApp.swift
│   ├── Features/
│   │   ├── HomeWatchView.swift
│   │   └── SettingsWatchView.swift
│   └── Core/
│       └── WatchConnectivityManager.swift
├── Shared/                     # Shared code (iOS + watchOS)
│   ├── Models/
│   │   ├── Message.swift
│   │   └── ConnectionState.swift
│   └── Protocols/
│       └── GatewayProtocol.swift
└── HeyNeo.xcodeproj
```

## Gateway Protocol

The app connects to Clawdbot Gateway via WebSocket at `ws://<host>:18789/ws`.

### Authentication
- Token-based auth via `?token=<gateway_token>` query param
- Or header: `Authorization: Bearer <token>`

### Message Flow

**Send user message:**
```json
{
  "type": "chat.send",
  "payload": {
    "text": "What's the weather?",
    "source": "hey-neo-ios"
  }
}
```

**Receive response:**
```json
{
  "type": "chat.message",
  "payload": {
    "role": "assistant",
    "content": "The weather in Houston is..."
  }
}
```

## Development Phases

### Tonight (Phase 1 - MVP)
1. Create Xcode project with iOS + watchOS targets
2. Implement GatewayClient (WebSocket)
3. Implement SpeechRecognizer
4. Build HomeView with push-to-talk
5. Build SettingsView for gateway config
6. Implement WatchConnectivity
7. Build watchOS push-to-talk UI
8. Test end-to-end flow

### Tomorrow (Review + Phase 2)
1. Mark reviews and provides feedback
2. Add voice wake detection
3. Polish UI/UX

## Notes

- Gateway URL will likely be local (same network) or via Tailscale
- Consider mDNS/Bonjour discovery for automatic gateway finding
- Watch app should work independently when iPhone is nearby
- Handle reconnection gracefully (network changes, sleep/wake)

## Resources

- Clawdbot Gateway Protocol: `/opt/homebrew/lib/node_modules/clawdbot/docs/gateway/protocol.md`
- iOS Node Reference: `/opt/homebrew/lib/node_modules/clawdbot/docs/platforms/ios.md`
- Voice Wake Reference: `/opt/homebrew/lib/node_modules/clawdbot/docs/nodes/voicewake.md`
