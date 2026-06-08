# UniFi Camera Popup (macOS)

Menu bar app that shows a borderless RTSPS camera popup when UniFi Protect alarms are received via the relay server.

## Features

- Menu bar only (no Dock icon)
- WebSocket connection to relay server with auto-reconnect
- Instant thumbnail display, then live RTSPS stream with audio (VLCKit)
- Close on click anywhere or ESC
- Configurable size, position (9 presets), screen margin
- Multiple webhook → RTSPS mappings
- Launch at login
- Auto-close timeout

## Requirements

- macOS 13+
- Xcode 15+

## Build

1. Open `UniFiCameraPopup.xcodeproj` in Xcode (inside the `UniFiCameraPopup` folder)
2. Wait for Swift Package `VLCKitSPM` to resolve
3. Build and run (⌘R)

## Configuration

1. **Server URL**: `wss://your-domain.example/ws`
2. **App Token**: same as `APP_TOKEN` on the server
3. Add camera mappings:
   - **Webhook ID**: path segment from UniFi delivery URL (`/webhook/front-door` → `front-door`)
   - **RTSPS URL**: local stream URL with credentials (never sent to server)

Example RTSPS URL:

```
rtsps://user:password@192.168.1.10:7441/s0WhqXXX
```

## Usage

- Click the camera icon in the menu bar
- **Einstellungen** – configure server and cameras
- **Test-Popup** – test with first configured mapping
- **Neu verbinden** – force WebSocket reconnect

Popup closes when you click anywhere on it or press ESC.

## Server setup

See the [server SETUP.md](../server/SETUP.md) for deployment instructions.
