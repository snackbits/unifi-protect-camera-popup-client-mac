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

### Mit Xcode

1. Open `UniFiCameraPopup.xcodeproj` in Xcode (inside the `UniFiCameraPopup` folder)
2. Wait for Swift Package `VLCKitSPM` to resolve
3. Build and run (⌘R)

### Ohne Xcode (Kommandozeile)

Voraussetzung: Xcode Command Line Tools (`xcode-select --install`).

```bash
cd app/UniFiCameraPopup

# Release-Build inkl. korrekter Signatur für VLCKit (empfohlen)
./scripts/build-release.sh

# App starten
open .build/Build/Products/Release/UniFiCameraPopup.app
```

Die fertige `.app` liegt danach unter  
`app/UniFiCameraPopup/.build/Build/Products/Release/UniFiCameraPopup.app`  
und kann in den Programme-Ordner kopiert werden.

**Wichtig beim Kopieren:** Die App nutzt das eingebettete VLCKit-Framework. Ohne einheitliche Code-Signatur verweigert macOS beim Start das Laden der Bibliothek (`different Team IDs`). Das Build-Skript signiert die App deshalb nach dem Build neu. Falls du nur `xcodebuild` verwendest, danach ausführen:

```bash
./scripts/resign-app.sh .build/Build/Products/Release/UniFiCameraPopup.app
```

Alternativ manuell:

```bash
codesign --force --deep --sign - /Applications/UniFiCameraPopup.app
```

Debug-Build und direkt starten:

```bash
xcodebuild \
  -project UniFiCameraPopup.xcodeproj \
  -scheme UniFiCameraPopup \
  -configuration Debug \
  -derivedDataPath .build \
  build && \
open .build/Build/Products/Debug/UniFiCameraPopup.app
```

## Configuration

1. **Server URL**: `wss://your-domain.example/ws`
2. **App Token**: same as `APP_TOKEN` on the server
3. Add camera mappings:
   - **Webhook ID**: path segment from UniFi delivery URL (`/webhook/front-door` → `front-door`)
   - **RTSP URL**: local stream URL with credentials (never sent to server)

Example RTSP URL:

```
rtsp://user:password@192.168.1.10:7447/s0WhqXXX
```

Use `rtsp://` on port **7447** — `rtsps://` and port 7441 are not supported by the app.

## Usage

- Click the camera icon in the menu bar
- **Einstellungen** – configure server and cameras
- **Test-Popup** – test with first configured mapping
- **Neu verbinden** – force WebSocket reconnect

Popup closes when you click anywhere on it or press ESC. Auto-close pauses while the mouse is over the popup.

## Server setup

See the [server SETUP.md](../server/SETUP.md) for deployment instructions.
