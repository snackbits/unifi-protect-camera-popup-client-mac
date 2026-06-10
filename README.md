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

The server connection (URL and app token) is compiled into the app via
`AppConfig.swift` and is not user-editable.

Under **Einstellungen → Verbindung**:

1. **Eindeutige ID**: a unique per-install ID, auto-generated. Used in the
   webhook URL so different users never share webhook paths. A new ID can be
   generated (requires reconfiguring UniFi webhooks).
2. **Webhook URL**: copyable `http://159.69.76.60:3847/webhook/<uid>/<slug>` —
   replace `<WEBHOOK-SLUG>` with each camera's slug.

Add camera mappings:

- **Beschreibung**: friendly label (e.g. Eingang)
- **Webhook-Slug**: path segment used in the webhook URL (e.g. `front-door`)
- **RTSP URL**: local stream URL with credentials (never sent to server)

Example RTSP URL:

```
rtsp://user:password@192.168.1.10:7447/s0WhqXXX
```

Use `rtsp://` on port **7447** — `rtsps://`, port 7441 and `?enableSrtp` are not
supported. Pasted URLs are automatically corrected.

## Usage

- Click the camera icon in the menu bar
- **Einstellungen** – configure cameras and view connection status
- **Test-Popup** – test with first configured mapping

The app reconnects automatically every 60 seconds while disconnected.

Popup closes when you click anywhere on it or press ESC. Auto-close pauses while the mouse is over the popup.

## Server setup

See the [server SETUP.md](../server/SETUP.md) for deployment instructions.
