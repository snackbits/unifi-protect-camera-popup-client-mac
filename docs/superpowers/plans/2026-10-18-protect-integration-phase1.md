# Protect-Anbindung (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die App findet die UniFi-Konsole, verbindet sich per API-Schlüssel mit der Protect Integration API, listet die Kameras, holt Stream-Adressen selbst und löst Popups über die eigenen Protect-Ereignisse (Klingel, Person, Tier, Fahrzeug, Sprache …) aus – ohne manuelle RTSP-URL und ohne Webhook. Der Webhook-Weg bleibt als versteckte Option erhalten.

**Architecture:** Neue lokale Swift-Package `app/Packages/ProtectKit` mit allen testbaren Teilen (Modelle, Ereignis-Parser, Discovery-Parser, URL-Umwandlung, API-Client mit Zertifikats-Pinning). Die App bindet das Package ein und ergänzt: Verbindungsdaten im `SettingsStore` (Schlüssel im Schlüsselbund), einen `ProtectEventService` (WebSocket `/v1/subscribe/events`), Stream-Auflösung im `PopupController`, ein SwiftUI-Onboarding (Schritte 1–5 der Vorlage C) und einen schlanken Protect-Abschnitt in den bestehenden Einstellungen.

**Tech Stack:** Swift 5.9+/Swift 6 Toolchain, SwiftUI + AppKit, XCTest (über `swift test` im Package), URLSession/URLSessionWebSocketTask, BSD-Sockets für UDP-Broadcast, Security.framework (Schlüsselbund, Zertifikat).

**Spec:** Gesprächsergebnis vom 18.10.2026 plus finale UI: https://claude.ai/artifact/Q9JCg1b1gu5stRG2SxaKsP (Boards „Einrichtung & Alltag“, Bildschirme 1–5 und 7; „Einstellungen → Kameras“ inkl. „Erweitert“). API-Fakten aus `uiprotect` 23.2.0 (`api.py`, `data/public_devices.py`, `data/public_event.py`).

## Roadmap (nicht Teil dieses Plans)

- **Phase 2:** Einstellungen komplett nach Vorlage (Reiter Allgemein/Kameras/Ton/Unterwegs), Erscheinungsbild System/Hell/Dunkel, Stummschalten pro Kamera im Popup, konfigurierbare Dauern (15 Min./1 Std.), Popup-Leiste aus Variante B.
- **Phase 3:** Ton & Sprechen: Talkback-Session, MP3-/KI-Ansagen (`AVSpeechSynthesizer`), Push-to-Talk mit Mikrofon, mitgelieferte Thorsten-MP3s.
- **Phase 4:** WireGuard in der App (Prototyp `scratchpad/wgtest`), Onboarding-Schritt 6, Reiter „Unterwegs“.

## Global Constraints

- macOS-Deployment-Target bleibt **13.0**; keine Sandbox, Hardened Runtime bleibt aus (kein bezahlter Developer-Account).
- Basis-Pfad der API: `https://<host>/proxy/protect/integration`, Header `X-API-KEY: <key>`, Antworten JSON.
- Endpunkte: `GET /v1/meta/info`, `GET /v1/cameras`, `GET /v1/cameras/{id}/rtsps-stream`, `POST /v1/cameras/{id}/rtsps-stream` Body `{"qualities":["high"]}`, WebSocket `wss://<host>/proxy/protect/integration/v1/subscribe/events`.
- Ereignis-Nachricht: `{"type":"add"|"update","item":{"id","modelKey":"event","type":"ring"|"motion"|"smartDetectZone"|"smartDetectLine"|"smartAudioDetect"|…,"start":<ms>,"end":<ms|null>,"device":"<cameraId>","smartDetectTypes":[…]}}`. Nur `add` löst ein Popup aus.
- VLC spielt nur `rtsp://` (kein RTSPS): `rtsps://h:7441/A?enableSrtp` → `rtsp://h:7447/A`.
- API-Schlüssel nur im Schlüsselbund (`KeychainStore`), niemals in `settings.json` oder im Export ohne ausdrückliche Option.
- Konsolen-Zertifikat ist selbst signiert: Trust-on-first-use, SHA-256 des Leaf-Zertifikats wird gespeichert und danach erzwungen.
- UI-Texte deutsch, Du-Form, wie in der Vorlage. Code und Bezeichner englisch.
- Bestehende Webhook-Zuordnungen müssen nach dem Update unverändert weiter funktionieren.

## Review Focus

1. **Bestehende Konfiguration nach Update:** Alte `settings.json` ohne neue Felder lädt fehlerfrei; Webhook-Popups funktionieren wie vorher. → Test in Task 7.
2. **Zertifikat ändert sich** (Konsolen-Update, neues Zertifikat): Verbindung schlägt mit verständlicher Meldung „Zertifikat der Konsole hat sich geändert“ fehl statt still zu vertrauen; Nutzer kann neu vertrauen. → Test in Task 5.
3. **Ereignis-Flut:** `update`-Nachrichten und wiederholte `add` desselben Ereignisses dürfen kein zweites Popup erzeugen; dieselbe Kamera verlängert nur den Timer (vorhandenes Verhalten). → Test in Task 3 (nur `add`, Deduplizierung per Ereignis-ID).
4. **Kamera ohne aktiven RTSP-Stream:** `GET rtsps-stream` liefert keine Adresse → App legt `high` per POST an und nutzt sie. → Test in Task 2/5.
5. **Konsole nicht erreichbar / WebSocket bricht ab:** Wiederverbindung mit Backoff, Status in der Menüleiste, keine Absturzschleife. → Test in Task 8 (Backoff-Berechnung).

---

## File Structure

```
app/Packages/ProtectKit/
  Package.swift
  Sources/ProtectKit/
    TriggerKind.swift            Auslöser-Arten, Mapping von Protect-Wire-Werten, deutsche Labels
    StreamURL.swift              rtsps→rtsp-Normalisierung (aus SettingsView verschoben)
    Models.swift                 ProtectCamera, ProtectMetaInfo, RTSPSStreams (Decodable)
    EventMessage.swift           Parser für Events-WebSocket → ProtectTrigger, Deduplizierung
    Discovery.swift              UniFi-Discovery (UDP 10001): Paket bauen/parsen + Broadcast-Suche
    CertificatePinning.swift     SHA-256-Fingerprint, TOFU-Entscheidung
    ProtectClient.swift          async API-Client (URLSession) mit Pinning-Delegate
    Backoff.swift                Wiederverbindungs-Intervalle
  Tests/ProtectKitTests/
    Fixtures/cameras.json, rtsps-stream.json, rtsps-stream-empty.json, meta-info.json
    TriggerKindTests.swift, StreamURLTests.swift, ModelsTests.swift, EventMessageTests.swift,
    DiscoveryTests.swift, CertificatePinningTests.swift, ProtectClientTests.swift, BackoffTests.swift

app/UniFiCameraPopup/
  UniFiCameraPopup.xcodeproj/project.pbxproj   + lokales Package ProtectKit
  Models/WebhookMapping.swift                  + protectCameraId, triggers; TriggerEvent + mappingId
  Services/SettingsStore.swift                 + protectConnection (Host, Fingerprint), apiKey (Keychain)
  Services/ProtectEventService.swift (neu)     Events-WebSocket, Wiederverbindung, → TriggerEvent
  Services/ProtectSession.swift (neu)          hält ProtectClient + Kamera-Cache, Stream-Auflösung
  Services/PopupController.swift               Mapping-Suche per mappingId, Stream über ProtectSession
  Views/Onboarding/OnboardingView.swift (neu)  Schritte 1–5
  Views/Onboarding/OnboardingWindow.swift (neu) NSWindow-Hülle
  Views/SettingsView.swift                     Protect-Abschnitt, Kamera-Picker, Auslöser-Chips, „Erweitert“
  AppDelegate.swift                            Start der Dienste, Onboarding beim ersten Start, Menüeintrag
```

---

### Task 1: ProtectKit-Package mit TriggerKind und Stream-URL

**Files:**
- Create: `app/Packages/ProtectKit/Package.swift`
- Create: `app/Packages/ProtectKit/Sources/ProtectKit/TriggerKind.swift`
- Create: `app/Packages/ProtectKit/Sources/ProtectKit/StreamURL.swift`
- Test: `app/Packages/ProtectKit/Tests/ProtectKitTests/TriggerKindTests.swift`, `StreamURLTests.swift`

**Interfaces:**
- Produces: `public enum TriggerKind: String, Codable, CaseIterable, Sendable` mit `label: String`, `init?(wireValue: String)`, `static let ordered: [TriggerKind]`; `public enum StreamURL { static func normalizedRTSP(_: String) -> String }`

- [ ] **Step 1: Package anlegen**

`app/Packages/ProtectKit/Package.swift`:
```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ProtectKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ProtectKit", targets: ["ProtectKit"])
    ],
    targets: [
        .target(name: "ProtectKit"),
        .testTarget(
            name: "ProtectKitTests",
            dependencies: ["ProtectKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
```
Leeren Ordner `Tests/ProtectKitTests/Fixtures/` mit einer Datei `.keep` anlegen (sonst schlägt `.copy` fehl).

- [ ] **Step 2: Failing tests schreiben**

`Tests/ProtectKitTests/TriggerKindTests.swift`:
```swift
import XCTest
@testable import ProtectKit

final class TriggerKindTests: XCTestCase {
    func testWireValuesMapToKinds() {
        XCTAssertEqual(TriggerKind(wireValue: "person"), .person)
        XCTAssertEqual(TriggerKind(wireValue: "vehicle"), .vehicle)
        XCTAssertEqual(TriggerKind(wireValue: "animal"), .animal)
        XCTAssertEqual(TriggerKind(wireValue: "package"), .package)
        XCTAssertEqual(TriggerKind(wireValue: "licensePlate"), .licensePlate)
        XCTAssertEqual(TriggerKind(wireValue: "face"), .face)
        XCTAssertEqual(TriggerKind(wireValue: "alrmSpeak"), .speak)
        XCTAssertEqual(TriggerKind(wireValue: "alrmBark"), .bark)
        XCTAssertEqual(TriggerKind(wireValue: "alrmBabyCry"), .babyCry)
        XCTAssertEqual(TriggerKind(wireValue: "alrmGlassBreak"), .glassBreak)
        XCTAssertEqual(TriggerKind(wireValue: "alrmSmoke"), .smoke)
        XCTAssertEqual(TriggerKind(wireValue: "smoke_cmonx"), .smoke)
        XCTAssertEqual(TriggerKind(wireValue: "alrmCmonx"), .carbonMonoxide)
        XCTAssertEqual(TriggerKind(wireValue: "alrmSiren"), .siren)
        XCTAssertEqual(TriggerKind(wireValue: "alrmCarHorn"), .carHorn)
        XCTAssertEqual(TriggerKind(wireValue: "alrmBurglar"), .burglar)
        XCTAssertEqual(TriggerKind(wireValue: "car"), .vehicle)
        XCTAssertEqual(TriggerKind(wireValue: "pet"), .animal)
        XCTAssertNil(TriggerKind(wireValue: "somethingNew"))
    }

    func testOrderedListsRingFirstAndContainsAll() {
        XCTAssertEqual(TriggerKind.ordered.first, .ring)
        XCTAssertEqual(Set(TriggerKind.ordered), Set(TriggerKind.allCases))
    }

    func testLabelsAreGerman() {
        XCTAssertEqual(TriggerKind.ring.label, "Klingel")
        XCTAssertEqual(TriggerKind.speak.label, "Sprache")
        XCTAssertEqual(TriggerKind.glassBreak.label, "Glasbruch")
    }

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode([TriggerKind.ring, .person])
        XCTAssertEqual(String(data: data, encoding: .utf8), "[\"ring\",\"person\"]")
        XCTAssertEqual(try JSONDecoder().decode([TriggerKind].self, from: data), [.ring, .person])
    }
}
```

`Tests/ProtectKitTests/StreamURLTests.swift`:
```swift
import XCTest
@testable import ProtectKit

final class StreamURLTests: XCTestCase {
    func testConvertsProtectRTSPSURL() {
        XCTAssertEqual(
            StreamURL.normalizedRTSP("rtsps://192.168.1.1:7441/AbCdEf123?enableSrtp"),
            "rtsp://192.168.1.1:7447/AbCdEf123"
        )
    }

    func testKeepsOtherQueryParameters() {
        XCTAssertEqual(
            StreamURL.normalizedRTSP("rtsps://h:7441/A?enableSrtp&foo=1"),
            "rtsp://h:7447/A?foo=1"
        )
    }

    func testIsIdempotent() {
        let once = StreamURL.normalizedRTSP("rtsps://h:7441/A?enableSrtp")
        XCTAssertEqual(StreamURL.normalizedRTSP(once), once)
    }

    func testLeavesPlainRTSPUntouched() {
        XCTAssertEqual(StreamURL.normalizedRTSP("rtsp://u:p@h:7447/A"), "rtsp://u:p@h:7447/A")
    }
}
```

- [ ] **Step 3: Tests laufen lassen, Fehlschlag prüfen**

Run: `cd app/Packages/ProtectKit && swift test`
Expected: FAIL – `cannot find 'TriggerKind' in scope`.

- [ ] **Step 4: Implementieren**

`Sources/ProtectKit/TriggerKind.swift`:
```swift
import Foundation

/// What can make a camera open a popup. Raw values are stored in settings.json.
public enum TriggerKind: String, Codable, CaseIterable, Sendable {
    case ring
    case person
    case package
    case animal
    case vehicle
    case licensePlate
    case face
    case motion
    case speak
    case bark
    case babyCry
    case glassBreak
    case smoke
    case carbonMonoxide
    case siren
    case carHorn
    case burglar

    /// Display order in the UI.
    public static let ordered: [TriggerKind] = [
        .ring, .person, .package, .animal, .vehicle, .licensePlate, .face, .motion,
        .speak, .bark, .babyCry, .glassBreak, .smoke, .carbonMonoxide, .siren, .carHorn, .burglar
    ]

    /// Maps Protect `smartDetectTypes` / audio type wire values.
    public init?(wireValue: String) {
        switch wireValue {
        case "person": self = .person
        case "vehicle", "car": self = .vehicle
        case "animal", "pet": self = .animal
        case "package": self = .package
        case "licensePlate": self = .licensePlate
        case "face": self = .face
        case "alrmSpeak": self = .speak
        case "alrmBark": self = .bark
        case "alrmBabyCry": self = .babyCry
        case "alrmGlassBreak": self = .glassBreak
        case "alrmSmoke", "smoke_cmonx": self = .smoke
        case "alrmCmonx": self = .carbonMonoxide
        case "alrmSiren": self = .siren
        case "alrmCarHorn": self = .carHorn
        case "alrmBurglar": self = .burglar
        default: return nil
        }
    }

    public var label: String {
        switch self {
        case .ring: return "Klingel"
        case .person: return "Person"
        case .package: return "Paket"
        case .animal: return "Tier"
        case .vehicle: return "Fahrzeug"
        case .licensePlate: return "Kennzeichen"
        case .face: return "Gesicht"
        case .motion: return "Bewegung"
        case .speak: return "Sprache"
        case .bark: return "Hundebellen"
        case .babyCry: return "Babyweinen"
        case .glassBreak: return "Glasbruch"
        case .smoke: return "Rauchmelder"
        case .carbonMonoxide: return "CO-Melder"
        case .siren: return "Sirene"
        case .carHorn: return "Hupe"
        case .burglar: return "Einbruchalarm"
        }
    }
}
```

`Sources/ProtectKit/StreamURL.swift` (Logik 1:1 aus `SettingsView.normalizeRTSP`):
```swift
import Foundation

public enum StreamURL {
    /// rtsps:// → rtsp://, :7441 → :7447, removes `enableSrtp`. Idempotent.
    public static func normalizedRTSP(_ url: String) -> String {
        var result = url
        if let range = result.range(of: "rtsps://", options: .caseInsensitive) {
            result.replaceSubrange(range, with: "rtsp://")
        }
        result = result.replacingOccurrences(of: ":7441", with: ":7447")
        result = result.replacingOccurrences(
            of: "[?&]enableSrtp(=[^&]*)?",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        if !result.contains("?"), let amp = result.firstIndex(of: "&") {
            result.replaceSubrange(amp...amp, with: "?")
        }
        return result
    }
}
```

- [ ] **Step 5: Tests grün**

Run: `cd app/Packages/ProtectKit && swift test`
Expected: PASS (alle Tests in TriggerKindTests, StreamURLTests).

- [ ] **Step 6: Commit**

```bash
cd app && git add Packages/ProtectKit && git commit -m "feat(protect): add ProtectKit package with trigger kinds and stream URL normalization"
```

---

### Task 2: Package in das Xcode-Projekt einbinden

**Files:**
- Modify: `app/UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj`
- Modify: `app/UniFiCameraPopup/Views/SettingsView.swift:507-530` (`normalizeRTSP` → `StreamURL.normalizedRTSP`)

**Interfaces:**
- Consumes: `StreamURL.normalizedRTSP` (Task 1)
- Produces: `import ProtectKit` ist in allen App-Dateien verfügbar.

- [ ] **Step 1: pbxproj-Einträge ergänzen** (IDs folgen dem vorhandenen Schema `A…`; vorher mit `grep -n 'A1000000000000000000001[5-9]\|A5000000000000000000000[2-9]\|AB000000000000000000000' project.pbxproj` prüfen, dass sie frei sind)

1. In `/* Begin PBXBuildFile section */`:
```
		A10000000000000000000015 /* ProtectKit in Frameworks */ = {isa = PBXBuildFile; productRef = A50000000000000000000002 /* ProtectKit */; };
```
2. In der Frameworks-Build-Phase direkt unter `A10000000000000000000014 /* VLCKitSPM in Frameworks */,`:
```
				A10000000000000000000015 /* ProtectKit in Frameworks */,
```
3. Im Target unter `packageProductDependencies = (` nach `A50000000000000000000001 /* VLCKitSPM */,`:
```
				A50000000000000000000002 /* ProtectKit */,
```
4. Im Projekt unter `packageReferences = (` nach der vlckit-Zeile:
```
				AB0000000000000000000001 /* XCLocalSwiftPackageReference "../Packages/ProtectKit" */,
```
5. Neue Sektion vor `/* Begin XCRemoteSwiftPackageReference section */`:
```
/* Begin XCLocalSwiftPackageReference section */
		AB0000000000000000000001 /* XCLocalSwiftPackageReference "../Packages/ProtectKit" */ = {
			isa = XCLocalSwiftPackageReference;
			relativePath = ../Packages/ProtectKit;
		};
/* End XCLocalSwiftPackageReference section */

```
6. In `/* Begin XCSwiftPackageProductDependency section */`:
```
		A50000000000000000000002 /* ProtectKit */ = {
			isa = XCSwiftPackageProductDependency;
			productName = ProtectKit;
		};
```
(`relativePath` ist relativ zum Ordner, der `UniFiCameraPopup.xcodeproj` enthält, also `app/UniFiCameraPopup/`.)

- [ ] **Step 2: SettingsView auf Package umstellen**

In `Views/SettingsView.swift` oben `import ProtectKit` ergänzen. Die private Funktion `normalizeRTSP(_:)` (Zeilen ~507–530) löschen und ihre Aufrufer ersetzen:
```swift
let normalized = StreamURL.normalizedRTSP(newValue)
```

- [ ] **Step 3: Build prüfen**

Run: `cd app/UniFiCameraPopup && xcodebuild -project UniFiCameraPopup.xcodeproj -scheme UniFiCameraPopup -configuration Debug -derivedDataPath .build build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
cd app && git add UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj UniFiCameraPopup/Views/SettingsView.swift
git commit -m "build: link local ProtectKit package into the app"
```

---

### Task 3: Modelle und Ereignis-Parser

**Files:**
- Create: `Sources/ProtectKit/Models.swift`, `Sources/ProtectKit/EventMessage.swift`
- Create: `Tests/ProtectKitTests/Fixtures/cameras.json`, `rtsps-stream.json`, `rtsps-stream-empty.json`, `meta-info.json`
- Test: `Tests/ProtectKitTests/ModelsTests.swift`, `EventMessageTests.swift`

**Interfaces:**
- Consumes: `TriggerKind` (Task 1)
- Produces:
  - `public struct ProtectCamera: Decodable, Equatable, Identifiable, Sendable { id: String; name: String; modelName: String?; isConnected: Bool; hasSpeaker: Bool; hasMic: Bool; supportedTriggers: Set<TriggerKind>; enabledTriggers: Set<TriggerKind> }`
  - `public struct ProtectMetaInfo: Decodable, Equatable, Sendable { applicationVersion: String }`
  - `public struct RTSPSStreams: Decodable, Equatable, Sendable { urls: [String: String]; var preferred: String? }`
  - `public struct ProtectTrigger: Equatable, Sendable { eventId: String; cameraId: String; kinds: Set<TriggerKind>; start: Date }`
  - `public enum EventMessage { static func parse(_ data: Data) -> ProtectTrigger? }`
  - `public struct EventDeduplicator { mutating func isNew(_ eventId: String) -> Bool }`

- [ ] **Step 1: Fixtures anlegen**

`Fixtures/cameras.json`:
```json
[
  {"id":"cam-door","modelKey":"camera","name":"Haustür","type":"G4 Doorbell Pro","state":"CONNECTED","mac":"AABBCC000001",
   "lcdMessage":{},"featureFlags":{"hasSpeaker":true,"hasMic":true,"smartDetectTypes":["person","package","vehicle"],"smartDetectAudioTypes":["alrmSpeak"]},
   "smartDetectSettings":{"objectTypes":["person","package"],"audioTypes":[]}},
  {"id":"cam-drive","modelKey":"camera","name":"Einfahrt","state":"CONNECTED","mac":"AABBCC000002",
   "featureFlags":{"hasSpeaker":false,"hasMic":true,"smartDetectTypes":["person","vehicle","licensePlate","somethingNew"],"smartDetectAudioTypes":[]},
   "smartDetectSettings":{"objectTypes":["vehicle"],"audioTypes":[]}},
  {"id":"cam-old","modelKey":"camera","name":null,"state":"DISCONNECTED","mac":"AABBCC000003",
   "featureFlags":{}}
]
```
`Fixtures/rtsps-stream.json`:
```json
{"high":"rtsps://192.168.1.1:7441/HighAlias?enableSrtp","medium":"rtsps://192.168.1.1:7441/MedAlias?enableSrtp","low":null}
```
`Fixtures/rtsps-stream-empty.json`:
```json
{"high":null,"medium":null,"low":null}
```
`Fixtures/meta-info.json`:
```json
{"applicationVersion":"6.1.79"}
```

- [ ] **Step 2: Failing tests schreiben**

`Tests/ProtectKitTests/ModelsTests.swift`:
```swift
import XCTest
@testable import ProtectKit

func fixture(_ name: String) throws -> Data {
    let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

final class ModelsTests: XCTestCase {
    func testDecodesCameras() throws {
        let cams = try JSONDecoder().decode([ProtectCamera].self, from: fixture("cameras"))
        XCTAssertEqual(cams.count, 3)

        let door = cams[0]
        XCTAssertEqual(door.id, "cam-door")
        XCTAssertEqual(door.name, "Haustür")
        XCTAssertEqual(door.modelName, "G4 Doorbell Pro")
        XCTAssertTrue(door.isConnected)
        XCTAssertTrue(door.hasSpeaker)
        XCTAssertEqual(door.supportedTriggers, [.ring, .motion, .person, .package, .vehicle, .speak])
        XCTAssertEqual(door.enabledTriggers, [.ring, .motion, .person, .package])

        let drive = cams[1]
        XCTAssertFalse(drive.hasSpeaker)
        XCTAssertEqual(drive.supportedTriggers, [.motion, .person, .vehicle, .licensePlate])
        XCTAssertFalse(drive.supportedTriggers.contains(.ring))

        let old = cams[2]
        XCTAssertEqual(old.name, "Kamera AABBCC000003")
        XCTAssertFalse(old.isConnected)
        XCTAssertEqual(old.supportedTriggers, [.motion])
    }

    func testDecodesStreamsAndPrefersHigh() throws {
        let s = try JSONDecoder().decode(RTSPSStreams.self, from: fixture("rtsps-stream"))
        XCTAssertEqual(s.preferred, "rtsps://192.168.1.1:7441/HighAlias?enableSrtp")
        let empty = try JSONDecoder().decode(RTSPSStreams.self, from: fixture("rtsps-stream-empty"))
        XCTAssertNil(empty.preferred)
    }

    func testPreferredFallsBackToMediumThenLow() throws {
        let s = try JSONDecoder().decode(RTSPSStreams.self, from: Data(#"{"high":null,"low":"rtsps://h:7441/L?enableSrtp"}"#.utf8))
        XCTAssertEqual(s.preferred, "rtsps://h:7441/L?enableSrtp")
    }

    func testDecodesMetaInfo() throws {
        XCTAssertEqual(try JSONDecoder().decode(ProtectMetaInfo.self, from: fixture("meta-info")).applicationVersion, "6.1.79")
    }
}
```

`Tests/ProtectKitTests/EventMessageTests.swift`:
```swift
import XCTest
@testable import ProtectKit

final class EventMessageTests: XCTestCase {
    private func msg(_ json: String) -> Data { Data(json.utf8) }

    func testRingAdd() throws {
        let t = try XCTUnwrap(EventMessage.parse(msg(#"{"type":"add","item":{"id":"e1","modelKey":"event","type":"ring","start":1760780000000,"device":"cam-door"}}"#)))
        XCTAssertEqual(t.eventId, "e1")
        XCTAssertEqual(t.cameraId, "cam-door")
        XCTAssertEqual(t.kinds, [.ring])
        XCTAssertEqual(t.start, Date(timeIntervalSince1970: 1_760_780_000))
    }

    func testSmartDetectZoneUsesSmartTypes() throws {
        let t = try XCTUnwrap(EventMessage.parse(msg(#"{"type":"add","item":{"id":"e2","modelKey":"event","type":"smartDetectZone","start":1,"device":"c","smartDetectTypes":["person","vehicle"]}}"#)))
        XCTAssertEqual(t.kinds, [.person, .vehicle])
    }

    func testSmartDetectLineAndAudio() throws {
        XCTAssertEqual(EventMessage.parse(msg(#"{"type":"add","item":{"id":"e3","modelKey":"event","type":"smartDetectLine","start":1,"device":"c","smartDetectTypes":["animal"]}}"#))?.kinds, [.animal])
        XCTAssertEqual(EventMessage.parse(msg(#"{"type":"add","item":{"id":"e4","modelKey":"event","type":"smartAudioDetect","start":1,"device":"c","smartDetectTypes":["alrmSpeak"]}}"#))?.kinds, [.speak])
    }

    func testMotion() {
        XCTAssertEqual(EventMessage.parse(msg(#"{"type":"add","item":{"id":"e5","modelKey":"event","type":"motion","start":1,"device":"c"}}"#))?.kinds, [.motion])
    }

    func testIgnoresUpdatesUnknownTypesAndGarbage() {
        XCTAssertNil(EventMessage.parse(msg(#"{"type":"update","item":{"id":"e1","modelKey":"event","end":2}}"#)))
        XCTAssertNil(EventMessage.parse(msg(#"{"type":"add","item":{"id":"e6","modelKey":"event","type":"sensorOpened","start":1,"device":"s"}}"#)))
        XCTAssertNil(EventMessage.parse(msg(#"{"type":"add","item":{"id":"e7","modelKey":"event","type":"smartDetectZone","start":1,"device":"c","smartDetectTypes":["unknownThing"]}}"#)))
        XCTAssertNil(EventMessage.parse(msg(#"{"type":"add","item":{"id":"e8","modelKey":"event","type":"ring","start":1}}"#)))
        XCTAssertNil(EventMessage.parse(msg("not json")))
    }

    func testDeduplicatorRemembersRecentIds() {
        var d = EventDeduplicator(capacity: 3)
        XCTAssertTrue(d.isNew("a"))
        XCTAssertFalse(d.isNew("a"))
        XCTAssertTrue(d.isNew("b"))
        XCTAssertTrue(d.isNew("c"))
        XCTAssertTrue(d.isNew("d"))   // evicts "a"
        XCTAssertTrue(d.isNew("a"))
    }
}
```

- [ ] **Step 3: Fehlschlag prüfen**

Run: `cd app/Packages/ProtectKit && swift test`
Expected: FAIL – `cannot find 'ProtectCamera' in scope`.

- [ ] **Step 4: Implementieren**

`Sources/ProtectKit/Models.swift`:
```swift
import Foundation

public struct ProtectMetaInfo: Decodable, Equatable, Sendable {
    public let applicationVersion: String
}

public struct ProtectCamera: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let modelName: String?
    public let isConnected: Bool
    public let hasSpeaker: Bool
    public let hasMic: Bool
    /// What this camera can detect at all.
    public let supportedTriggers: Set<TriggerKind>
    /// What is currently switched on in Protect for this camera.
    public let enabledTriggers: Set<TriggerKind>

    private enum CodingKeys: String, CodingKey {
        case id, name, type, state, mac, lcdMessage, featureFlags, smartDetectSettings
    }
    private struct FeatureFlags: Decodable {
        var hasSpeaker: Bool?
        var hasMic: Bool?
        var smartDetectTypes: [String]?
        var smartDetectAudioTypes: [String]?
    }
    private struct SmartSettings: Decodable {
        var objectTypes: [String]?
        var audioTypes: [String]?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        let mac = (try? c.decodeIfPresent(String.self, forKey: .mac)) ?? nil
        let rawName = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil
        name = rawName?.isEmpty == false ? rawName! : "Kamera \(mac ?? id)"
        modelName = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? nil
        isConnected = ((try? c.decodeIfPresent(String.self, forKey: .state)) ?? nil) == "CONNECTED"

        let flags = (try? c.decodeIfPresent(FeatureFlags.self, forKey: .featureFlags)) ?? nil
        hasSpeaker = flags?.hasSpeaker ?? false
        hasMic = flags?.hasMic ?? false

        let isDoorbell = c.contains(.lcdMessage)
            || (modelName?.localizedCaseInsensitiveContains("doorbell") ?? false)
        let smart = ((flags?.smartDetectTypes ?? []) + (flags?.smartDetectAudioTypes ?? []))
            .compactMap(TriggerKind.init(wireValue:))
        var supported = Set(smart).union([.motion])
        if isDoorbell { supported.insert(.ring) }
        supportedTriggers = supported

        let settings = (try? c.decodeIfPresent(SmartSettings.self, forKey: .smartDetectSettings)) ?? nil
        let enabledSmart = ((settings?.objectTypes ?? []) + (settings?.audioTypes ?? []))
            .compactMap(TriggerKind.init(wireValue:))
        var enabled = Set(enabledSmart).union([.motion])
        if isDoorbell { enabled.insert(.ring) }
        enabledTriggers = enabled.intersection(supported)
    }
}

public struct RTSPSStreams: Decodable, Equatable, Sendable {
    /// Quality ("high", "medium", "low", "package", …) → rtsps URL. Nulls dropped.
    public let urls: [String: String]

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode([String: String?].self)
        urls = raw.compactMapValues { $0 }
    }

    public var preferred: String? {
        urls["high"] ?? urls["medium"] ?? urls["low"]
    }
}
```

`Sources/ProtectKit/EventMessage.swift`:
```swift
import Foundation

public struct ProtectTrigger: Equatable, Sendable {
    public let eventId: String
    public let cameraId: String
    public let kinds: Set<TriggerKind>
    public let start: Date
}

public enum EventMessage {
    private struct Envelope: Decodable {
        let type: String
        let item: Item
    }
    private struct Item: Decodable {
        let id: String?
        let type: String?
        let start: Double?
        let device: String?
        let smartDetectTypes: [String]?
    }

    /// Returns a trigger for new camera events (`add`), nil for everything else.
    public static func parse(_ data: Data) -> ProtectTrigger? {
        guard let env = try? JSONDecoder().decode(Envelope.self, from: data),
              env.type == "add",
              let id = env.item.id,
              let camera = env.item.device,
              let type = env.item.type else { return nil }

        let kinds: Set<TriggerKind>
        switch type {
        case "ring":
            kinds = [.ring]
        case "motion":
            kinds = [.motion]
        case "smartDetectZone", "smartDetectLine", "smartAudioDetect":
            kinds = Set((env.item.smartDetectTypes ?? []).compactMap(TriggerKind.init(wireValue:)))
        default:
            return nil
        }
        guard !kinds.isEmpty else { return nil }

        let start = Date(timeIntervalSince1970: (env.item.start ?? Date().timeIntervalSince1970 * 1000) / 1000)
        return ProtectTrigger(eventId: id, cameraId: camera, kinds: kinds, start: start)
    }
}

/// Remembers the last `capacity` event ids so repeated `add` frames do not re-trigger.
public struct EventDeduplicator {
    private var order: [String] = []
    private var seen: Set<String> = []
    private let capacity: Int

    public init(capacity: Int = 200) { self.capacity = capacity }

    public mutating func isNew(_ eventId: String) -> Bool {
        guard !seen.contains(eventId) else { return false }
        seen.insert(eventId)
        order.append(eventId)
        if order.count > capacity {
            seen.remove(order.removeFirst())
        }
        return true
    }
}
```

- [ ] **Step 5: Tests grün**

Run: `cd app/Packages/ProtectKit && swift test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd app && git add Packages/ProtectKit && git commit -m "feat(protect): decode cameras, RTSPS streams and event websocket messages"
```

---

### Task 4: Konsolen-Suche im Netzwerk (UniFi Discovery)

**Files:**
- Create: `Sources/ProtectKit/Discovery.swift`
- Test: `Tests/ProtectKitTests/DiscoveryTests.swift`

**Interfaces:**
- Produces:
  - `public struct DiscoveredConsole: Equatable, Hashable, Sendable { ip: String; mac: String?; hostname: String?; model: String? ; var displayName: String }`
  - `public enum DiscoveryPacket { static let request: [UInt8]; static func parse(_ bytes: [UInt8], sourceIP: String) -> DiscoveredConsole? }`
  - `public final class ConsoleDiscovery { init(); func scan(duration: TimeInterval) async -> [DiscoveredConsole] }`

Protokoll: Anfrage `01 00 00 00` per UDP-Broadcast an Port 10001. Antwort: Byte 0 Version (`01`), Byte 1 Kommando (`00`), Bytes 2–3 Nutzlänge (Big Endian), danach TLVs aus Typ (1 Byte), Länge (2 Bytes BE), Wert. Relevante Typen: `0x01` MAC (6 B), `0x02` MAC+IPv4 (10 B), `0x0B` Hostname (UTF-8), `0x0C` Kurz-Modell (UTF-8), `0x14`/`0x15` Modellname (UTF-8). Unbekannte Typen überspringen.

- [ ] **Step 1: Failing test schreiben**

`Tests/ProtectKitTests/DiscoveryTests.swift`:
```swift
import XCTest
@testable import ProtectKit

final class DiscoveryTests: XCTestCase {
    private func tlv(_ type: UInt8, _ value: [UInt8]) -> [UInt8] {
        [type, UInt8(value.count >> 8), UInt8(value.count & 0xFF)] + value
    }

    func testRequestBytes() {
        XCTAssertEqual(DiscoveryPacket.request, [0x01, 0x00, 0x00, 0x00])
    }

    func testParsesResponse() throws {
        let body = tlv(0x02, [0xAA, 0xBB, 0xCC, 0x00, 0x00, 0x01, 192, 168, 1, 1])
            + tlv(0x0B, Array("UDM-Pro".utf8))
            + tlv(0x0C, Array("UDMPRO".utf8))
            + tlv(0x15, Array("UniFi Dream Machine Pro".utf8))
            + tlv(0x7E, [1, 2, 3])
        let packet: [UInt8] = [0x01, 0x00, UInt8(body.count >> 8), UInt8(body.count & 0xFF)] + body

        let c = try XCTUnwrap(DiscoveryPacket.parse(packet, sourceIP: "192.168.1.1"))
        XCTAssertEqual(c.ip, "192.168.1.1")
        XCTAssertEqual(c.mac, "aa:bb:cc:00:00:01")
        XCTAssertEqual(c.hostname, "UDM-Pro")
        XCTAssertEqual(c.model, "UniFi Dream Machine Pro")
        XCTAssertEqual(c.displayName, "UniFi Dream Machine Pro")
    }

    func testRejectsOwnRequestAndTruncatedPackets() {
        XCTAssertNil(DiscoveryPacket.parse([0x01, 0x00, 0x00, 0x00], sourceIP: "1.2.3.4"))
        XCTAssertNil(DiscoveryPacket.parse([0x01, 0x00, 0x00, 0x09, 0x0B, 0x00, 0x05, 0x41], sourceIP: "1.2.3.4"))
        XCTAssertNil(DiscoveryPacket.parse([0x02, 0x00, 0x00, 0x00], sourceIP: "1.2.3.4"))
    }

    func testDisplayNameFallsBackToHostnameThenIP() {
        XCTAssertEqual(DiscoveredConsole(ip: "10.0.0.1", mac: nil, hostname: "ck", model: nil).displayName, "ck")
        XCTAssertEqual(DiscoveredConsole(ip: "10.0.0.1", mac: nil, hostname: nil, model: nil).displayName, "10.0.0.1")
    }
}
```

- [ ] **Step 2: Fehlschlag prüfen**

Run: `cd app/Packages/ProtectKit && swift test --filter DiscoveryTests`
Expected: FAIL – `cannot find 'DiscoveryPacket' in scope`.

- [ ] **Step 3: Implementieren**

`Sources/ProtectKit/Discovery.swift`:
```swift
import Darwin
import Foundation

public struct DiscoveredConsole: Equatable, Hashable, Sendable {
    public let ip: String
    public let mac: String?
    public let hostname: String?
    public let model: String?

    public init(ip: String, mac: String?, hostname: String?, model: String?) {
        self.ip = ip; self.mac = mac; self.hostname = hostname; self.model = model
    }

    public var displayName: String { model ?? hostname ?? ip }
}

public enum DiscoveryPacket {
    public static let request: [UInt8] = [0x01, 0x00, 0x00, 0x00]

    public static func parse(_ bytes: [UInt8], sourceIP: String) -> DiscoveredConsole? {
        guard bytes.count > 4, bytes[0] == 0x01, bytes[1] == 0x00 else { return nil }
        let length = Int(bytes[2]) << 8 | Int(bytes[3])
        guard length > 0, bytes.count >= 4 + length else { return nil }

        var mac: String?
        var hostname: String?
        var shortModel: String?
        var model: String?
        var i = 4
        let end = 4 + length
        while i + 3 <= end {
            let type = bytes[i]
            let len = Int(bytes[i + 1]) << 8 | Int(bytes[i + 2])
            let start = i + 3
            guard start + len <= end else { return nil }
            let value = Array(bytes[start..<start + len])
            switch type {
            case 0x01 where len == 6, 0x02 where len == 10:
                mac = value.prefix(6).map { String(format: "%02x", $0) }.joined(separator: ":")
            case 0x0B: hostname = String(decoding: value, as: UTF8.self)
            case 0x0C: shortModel = String(decoding: value, as: UTF8.self)
            case 0x14, 0x15: model = String(decoding: value, as: UTF8.self)
            default: break
            }
            i = start + len
        }
        return DiscoveredConsole(ip: sourceIP, mac: mac, hostname: hostname, model: model ?? shortModel)
    }
}

/// Broadcasts a discovery request and collects answers for `duration` seconds.
public final class ConsoleDiscovery {
    public init() {}

    public func scan(duration: TimeInterval = 3) async -> [DiscoveredConsole] {
        await Task.detached { Self.blockingScan(duration: duration) }.value
    }

    private static func blockingScan(duration: TimeInterval) -> [DiscoveredConsole] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var dest = sockaddr_in()
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = in_port_t(10001).bigEndian
        dest.sin_addr.s_addr = INADDR_BROADCAST

        let request = DiscoveryPacket.request
        func send() {
            _ = withUnsafePointer(to: &dest) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, request, request.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        var found: [String: DiscoveredConsole] = [:]
        let deadline = Date().addingTimeInterval(duration)
        var lastSend = Date.distantPast
        var buffer = [UInt8](repeating: 0, count: 2048)
        while Date() < deadline {
            if Date().timeIntervalSince(lastSend) > 1 { send(); lastSend = Date() }
            var from = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(fd, &buffer, buffer.count, 0, $0, &fromLen)
                }
            }
            guard n > 0 else { continue }
            let ip = String(cString: inet_ntoa(from.sin_addr))
            if let console = DiscoveryPacket.parse(Array(buffer[0..<n]), sourceIP: ip) {
                found[ip] = console
            }
        }
        return found.values.sorted { $0.ip < $1.ip }
    }
}
```

- [ ] **Step 4: Tests grün**

Run: `cd app/Packages/ProtectKit && swift test --filter DiscoveryTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd app && git add Packages/ProtectKit && git commit -m "feat(protect): discover UniFi consoles via UDP 10001 broadcast"
```

---

### Task 5: API-Client mit Zertifikats-Pinning

**Files:**
- Create: `Sources/ProtectKit/CertificatePinning.swift`, `Sources/ProtectKit/ProtectClient.swift`
- Test: `Tests/ProtectKitTests/CertificatePinningTests.swift`, `ProtectClientTests.swift`

**Interfaces:**
- Consumes: Modelle aus Task 3
- Produces:
  - `public enum PinDecision: Equatable { case trustAndRemember(String), trust, reject }`
  - `public enum CertificatePinning { static func fingerprint(of der: Data) -> String; static func decide(presented: String, pinned: String?) -> PinDecision }`
  - `public enum ProtectError: Error, Equatable, LocalizedError { case invalidHost, unauthorized, certificateChanged, http(Int), unreachable(String), decoding }`
  - `public final class ProtectClient: NSObject, URLSessionDelegate, @unchecked Sendable`
    - `init(host: String, apiKey: String, pinnedFingerprint: String?, onNewFingerprint: @escaping @Sendable (String) -> Void, protocolClasses: [AnyClass]? = nil)`
    - `func metaInfo() async throws -> ProtectMetaInfo`
    - `func cameras() async throws -> [ProtectCamera]`
    - `func rtspURL(cameraId: String) async throws -> String?` (holt, legt bei Bedarf `high` an, liefert bereits normalisierte `rtsp://`-URL)
    - `func eventsWebSocket() -> URLSessionWebSocketTask`
    - `static func baseURL(for host: String) -> URL?`

- [ ] **Step 1: Failing tests schreiben**

`Tests/ProtectKitTests/CertificatePinningTests.swift`:
```swift
import XCTest
@testable import ProtectKit

final class CertificatePinningTests: XCTestCase {
    func testFingerprintIsUppercaseColonSeparatedSHA256() {
        // SHA-256("abc")
        XCTAssertEqual(
            CertificatePinning.fingerprint(of: Data("abc".utf8)),
            "BA:78:16:BF:8F:01:CF:EA:41:41:40:DE:5D:AE:22:23:B0:03:61:A3:96:17:7A:9C:B4:10:FF:61:F2:00:15:AD"
        )
    }

    func testDecisions() {
        XCTAssertEqual(CertificatePinning.decide(presented: "AA", pinned: nil), .trustAndRemember("AA"))
        XCTAssertEqual(CertificatePinning.decide(presented: "AA", pinned: "AA"), .trust)
        XCTAssertEqual(CertificatePinning.decide(presented: "BB", pinned: "AA"), .reject)
    }
}
```

`Tests/ProtectKitTests/ProtectClientTests.swift`:
```swift
import XCTest
@testable import ProtectKit

/// Serves canned responses keyed by "METHOD path".
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [String: (Int, Data)] = [:]
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let key = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")"
        let (status, body) = Self.responses[key] ?? (404, Data())
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ProtectClientTests: XCTestCase {
    private let base = "/proxy/protect/integration/v1"

    override func setUp() {
        StubProtocol.responses = [:]
        StubProtocol.requests = []
    }

    private func client() -> ProtectClient {
        ProtectClient(host: "192.168.1.1", apiKey: "KEY", pinnedFingerprint: nil, onNewFingerprint: { _ in }, protocolClasses: [StubProtocol.self])
    }

    func testBaseURL() {
        XCTAssertEqual(ProtectClient.baseURL(for: "192.168.1.1")?.absoluteString, "https://192.168.1.1/proxy/protect/integration")
        XCTAssertEqual(ProtectClient.baseURL(for: " https://konsole.local/ ")?.absoluteString, "https://konsole.local/proxy/protect/integration")
        XCTAssertEqual(ProtectClient.baseURL(for: "konsole.local:8443")?.absoluteString, "https://konsole.local:8443/proxy/protect/integration")
        XCTAssertNil(ProtectClient.baseURL(for: ""))
    }

    func testSendsApiKeyAndDecodesCameras() async throws {
        StubProtocol.responses["GET \(base)/cameras"] = (200, try fixture("cameras"))
        let cams = try await client().cameras()
        XCTAssertEqual(cams.map(\.id), ["cam-door", "cam-drive", "cam-old"])
        XCTAssertEqual(StubProtocol.requests.first?.value(forHTTPHeaderField: "X-API-KEY"), "KEY")
    }

    func testUnauthorized() async {
        StubProtocol.responses["GET \(base)/meta/info"] = (401, Data())
        do { _ = try await client().metaInfo(); XCTFail() } catch { XCTAssertEqual(error as? ProtectError, .unauthorized) }
    }

    func testRTSPURLUsesExistingStream() async throws {
        StubProtocol.responses["GET \(base)/cameras/c1/rtsps-stream"] = (200, try fixture("rtsps-stream"))
        let url = try await client().rtspURL(cameraId: "c1")
        XCTAssertEqual(url, "rtsp://192.168.1.1:7447/HighAlias")
        XCTAssertFalse(StubProtocol.requests.contains { $0.httpMethod == "POST" })
    }

    func testRTSPURLCreatesStreamWhenMissing() async throws {
        StubProtocol.responses["GET \(base)/cameras/c1/rtsps-stream"] = (200, try fixture("rtsps-stream-empty"))
        StubProtocol.responses["POST \(base)/cameras/c1/rtsps-stream"] = (200, Data(#"{"high":"rtsps://192.168.1.1:7441/New?enableSrtp"}"#.utf8))
        let url = try await client().rtspURL(cameraId: "c1")
        XCTAssertEqual(url, "rtsp://192.168.1.1:7447/New")
        let post = try XCTUnwrap(StubProtocol.requests.first { $0.httpMethod == "POST" })
        let body = try XCTUnwrap(post.httpBody ?? post.httpBodyStream.map { s -> Data in
            s.open(); defer { s.close() }
            var d = Data(); var buf = [UInt8](repeating: 0, count: 256)
            while s.hasBytesAvailable { let n = s.read(&buf, maxLength: 256); if n <= 0 { break }; d.append(buf, count: n) }
            return d
        })
        XCTAssertEqual(String(data: body, encoding: .utf8), #"{"qualities":["high"]}"#)
    }
}
```

- [ ] **Step 2: Fehlschlag prüfen**

Run: `cd app/Packages/ProtectKit && swift test`
Expected: FAIL – `cannot find 'CertificatePinning' in scope`.

- [ ] **Step 3: Implementieren**

`Sources/ProtectKit/CertificatePinning.swift`:
```swift
import CryptoKit
import Foundation

public enum PinDecision: Equatable {
    case trustAndRemember(String)
    case trust
    case reject
}

public enum CertificatePinning {
    public static func fingerprint(of der: Data) -> String {
        SHA256.hash(data: der).map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    /// Trust on first use; afterwards only the remembered certificate.
    public static func decide(presented: String, pinned: String?) -> PinDecision {
        guard let pinned else { return .trustAndRemember(presented) }
        return pinned == presented ? .trust : .reject
    }
}
```

`Sources/ProtectKit/ProtectClient.swift`:
```swift
import Foundation
import Security

public enum ProtectError: Error, Equatable, LocalizedError {
    case invalidHost
    case unauthorized
    case certificateChanged
    case http(Int)
    case unreachable(String)
    case decoding

    public var errorDescription: String? {
        switch self {
        case .invalidHost: return "Die Adresse der Konsole ist ungültig."
        case .unauthorized: return "Der API-Schlüssel wurde abgelehnt."
        case .certificateChanged: return "Das Zertifikat der Konsole hat sich geändert. Bitte die Verbindung neu bestätigen."
        case .http(let code): return "Die Konsole antwortete mit Fehler \(code)."
        case .unreachable(let detail): return "Die Konsole ist nicht erreichbar (\(detail))."
        case .decoding: return "Die Antwort der Konsole war unerwartet."
        }
    }
}

public final class ProtectClient: NSObject, URLSessionDelegate, @unchecked Sendable {
    public let baseURL: URL
    private let apiKey: String
    private let lock = NSLock()
    private var pinnedFingerprint: String?
    private var sawChangedCertificate = false
    private let onNewFingerprint: @Sendable (String) -> Void
    private var session: URLSession!

    public init(
        host: String,
        apiKey: String,
        pinnedFingerprint: String?,
        onNewFingerprint: @escaping @Sendable (String) -> Void,
        protocolClasses: [AnyClass]? = nil
    ) {
        self.baseURL = Self.baseURL(for: host) ?? URL(string: "https://invalid.invalid")!
        self.apiKey = apiKey
        self.pinnedFingerprint = pinnedFingerprint
        self.onNewFingerprint = onNewFingerprint
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        if let protocolClasses { config.protocolClasses = protocolClasses }
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    public static func baseURL(for host: String) -> URL? {
        var trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        guard var comps = URLComponents(string: trimmed), let h = comps.host, !h.isEmpty else { return nil }
        comps.scheme = "https"
        comps.path = "/proxy/protect/integration"
        comps.query = nil
        return comps.url
    }

    // MARK: API

    public func metaInfo() async throws -> ProtectMetaInfo {
        try await get("/v1/meta/info")
    }

    public func cameras() async throws -> [ProtectCamera] {
        try await get("/v1/cameras")
    }

    public func rtspURL(cameraId: String) async throws -> String? {
        let existing: RTSPSStreams = try await get("/v1/cameras/\(cameraId)/rtsps-stream")
        if let url = existing.preferred { return StreamURL.normalizedRTSP(url) }
        let created: RTSPSStreams = try await send(
            "POST", "/v1/cameras/\(cameraId)/rtsps-stream",
            body: Data(#"{"qualities":["high"]}"#.utf8)
        )
        return created.preferred.map(StreamURL.normalizedRTSP)
    }

    public func eventsWebSocket() -> URLSessionWebSocketTask {
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        comps.scheme = "wss"
        comps.path += "/v1/subscribe/events"
        var request = URLRequest(url: comps.url!)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        return session.webSocketTask(with: request)
    }

    // MARK: Transport

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await send("GET", path, body: nil)
    }

    private func send<T: Decodable>(_ method: String, _ path: String, body: Data?) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(String(path.dropFirst())))
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if lock.withLock({ sawChangedCertificate }) { throw ProtectError.certificateChanged }
            throw ProtectError.unreachable((error as NSError).localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw ProtectError.decoding }
        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw ProtectError.unauthorized
        default: throw ProtectError.http(http.statusCode)
        }
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw ProtectError.decoding }
    }

    // MARK: URLSessionDelegate (TOFU pinning)

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let presented = CertificatePinning.fingerprint(of: SecCertificateCopyData(leaf) as Data)
        let decision = lock.withLock { CertificatePinning.decide(presented: presented, pinned: pinnedFingerprint) }
        switch decision {
        case .trustAndRemember(let fp):
            lock.withLock { pinnedFingerprint = fp }
            onNewFingerprint(fp)
            completionHandler(.useCredential, URLCredential(trust: trust))
        case .trust:
            completionHandler(.useCredential, URLCredential(trust: trust))
        case .reject:
            lock.withLock { sawChangedCertificate = true }
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
```

- [ ] **Step 4: Tests grün**

Run: `cd app/Packages/ProtectKit && swift test`
Expected: PASS (alle bisherigen Tests).

- [ ] **Step 5: Commit**

```bash
cd app && git add Packages/ProtectKit && git commit -m "feat(protect): add Protect API client with trust-on-first-use certificate pinning"
```

---

### Task 6: Wiederverbindungs-Backoff

**Files:**
- Create: `Sources/ProtectKit/Backoff.swift`
- Test: `Tests/ProtectKitTests/BackoffTests.swift`

**Interfaces:**
- Produces: `public struct Backoff { init(base: TimeInterval = 2, max: TimeInterval = 60); mutating func next() -> TimeInterval; mutating func reset() }`

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import ProtectKit

final class BackoffTests: XCTestCase {
    func testDoublesUpToMaxAndResets() {
        var b = Backoff(base: 2, max: 30)
        XCTAssertEqual([b.next(), b.next(), b.next(), b.next(), b.next(), b.next()], [2, 4, 8, 16, 30, 30])
        b.reset()
        XCTAssertEqual(b.next(), 2)
    }
}
```

- [ ] **Step 2: Fehlschlag prüfen** – `swift test --filter BackoffTests` → FAIL `cannot find 'Backoff'`.

- [ ] **Step 3: Implementieren**

```swift
import Foundation

public struct Backoff {
    private let base: TimeInterval
    private let max: TimeInterval
    private var attempt = 0

    public init(base: TimeInterval = 2, max: TimeInterval = 60) {
        self.base = base
        self.max = max
    }

    public mutating func next() -> TimeInterval {
        let value = Swift.min(max, base * pow(2, Double(attempt)))
        attempt += 1
        return value
    }

    public mutating func reset() { attempt = 0 }
}
```

- [ ] **Step 4: Tests grün** – `swift test` → PASS.

- [ ] **Step 5: Commit**

```bash
cd app && git add Packages/ProtectKit && git commit -m "feat(protect): add reconnect backoff"
```

---

### Task 7: Einstellungen erweitern (Verbindung, Kamera-Zuordnung, Auslöser)

**Files:**
- Modify: `app/UniFiCameraPopup/Models/WebhookMapping.swift` (Felder + Codable; `TriggerEvent`)
- Modify: `app/UniFiCameraPopup/Services/SettingsStore.swift` (`protectHost`, `protectCertificateFingerprint`, `protectAPIKey`, `mapping(forProtectCamera:)`, `mapping(forEntry:)`)
- Modify: `app/UniFiCameraPopup/Services/KeychainStore.swift` (Service-Konstante)

**Interfaces:**
- Consumes: `TriggerKind`
- Produces:
  - `WebhookMapping.protectCameraId: String?`, `WebhookMapping.triggers: Set<TriggerKind>` (Default `[.ring, .person]`), `WebhookMapping.webhookTriggerEnabled: Bool` (Default: `!webhookId.isEmpty` bei Migration, sonst `false`)
  - `TriggerEvent` erhält `let mappingId: UUID?` und `let kinds: Set<TriggerKind>`; vorhandener Initialisierer bleibt nutzbar über Default-Werte
  - `SettingsStore.protectHost: String`, `SettingsStore.protectCertificateFingerprint: String?`, `SettingsStore.protectAPIKey: String` (Getter/Setter über Keychain), `SettingsStore.isProtectConfigured: Bool`, `SettingsStore.mappings(forProtectCamera:) -> [WebhookMapping]`
  - `KeychainStore.protectAPIKeyService = "com.snackbits.UniFiCameraPopup.protect-api-key"`

Hinweis: Die App hat kein Test-Target. Die Migration wird über eine kleine reine Funktion im Package abgesichert? Nein – `WebhookMapping` lebt in der App. Deshalb hier ein **manueller, reproduzierbarer Check** mit einer alten `settings.json` (Step 4).

- [ ] **Step 1: `WebhookMapping` erweitern**

In `Models/WebhookMapping.swift` oben `import ProtectKit`. Im Struct nach `var actions: [CameraAction]`:
```swift
    /// Protect camera id (Integration API). nil = legacy webhook/RTSP-only entry.
    var protectCameraId: String?
    /// Protect events that open this camera's popup.
    var triggers: Set<TriggerKind>
    /// Hidden option: also open the popup when the relay server receives `webhookId`.
    var webhookTriggerEnabled: Bool
```
`CodingKeys` um `case protectCameraId, triggers, webhookTriggerEnabled` ergänzen. Im `init(...)` Parameter mit Defaults ergänzen:
```swift
        protectCameraId: String? = nil,
        triggers: Set<TriggerKind> = [.ring, .person],
        webhookTriggerEnabled: Bool = false,
```
und zuweisen. Im `init(from:)` (defensiv wie die übrigen Felder):
```swift
        protectCameraId = (try? container.decodeIfPresent(String.self, forKey: .protectCameraId)) ?? nil
        triggers = Set((try? container.decodeIfPresent([TriggerKind].self, forKey: .triggers)) ?? [.ring, .person])
        // Legacy entries were webhook-driven: keep them working.
        webhookTriggerEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .webhookTriggerEnabled))
            ?? !webhookId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
```
Im `encode(to:)`:
```swift
        try container.encodeIfPresent(protectCameraId, forKey: .protectCameraId)
        try container.encode(TriggerKind.ordered.filter(triggers.contains), forKey: .triggers)
        try container.encode(webhookTriggerEnabled, forKey: .webhookTriggerEnabled)
```
(Die Zuweisung von `webhookTriggerEnabled` muss **nach** `webhookId` stehen.)

`TriggerEvent` ersetzen durch:
```swift
struct TriggerEvent: Equatable {
    let webhookId: String
    let thumbnail: String?
    let alarmName: String?
    let timestamp: Date
    /// Set for Protect events: the mapping entry to show.
    var mappingId: UUID? = nil
    var kinds: Set<TriggerKind> = []
}
```

- [ ] **Step 2: `SettingsStore` erweitern**

`KeychainStore`: Konstante ergänzen
```swift
    static let protectAPIKeyService = "com.snackbits.UniFiCameraPopup.protect-api-key"
```
In `SettingsStore` neben den anderen `@Published`-Eigenschaften (Persistenz über die vorhandene `persist()`-Funktion; `PersistedSettings` um `var protectHost: String?` und `var protectCertificateFingerprint: String?` ergänzen, in `currentPersistedSettings()` mitschreiben, im `init` mit `saved.protectHost ?? ""` bzw. `saved.protectCertificateFingerprint` laden und im Zweig ohne gespeicherte Daten mit `""`/`nil` initialisieren):
```swift
    @Published var protectHost: String { didSet { persist() } }
    @Published var protectCertificateFingerprint: String? { didSet { persist() } }

    var protectAPIKey: String {
        get { KeychainStore.string(service: KeychainStore.protectAPIKeyService, account: "default") ?? "" }
        set {
            if newValue.isEmpty {
                KeychainStore.delete(service: KeychainStore.protectAPIKeyService, account: "default")
            } else {
                _ = KeychainStore.set(newValue, service: KeychainStore.protectAPIKeyService, account: "default")
            }
            objectWillChange.send()
        }
    }

    var isProtectConfigured: Bool {
        !protectHost.trimmingCharacters(in: .whitespaces).isEmpty && !protectAPIKey.isEmpty
    }

    func mappings(forProtectCamera cameraId: String) -> [WebhookMapping] {
        mappings.filter { $0.protectCameraId == cameraId }
    }

    func mapping(forEntry id: UUID) -> WebhookMapping? {
        mappings.first { $0.entryId == id }
    }
```

Bestehende Funktion `mapping(for webhookId:)` so ändern, dass nur Einträge mit `webhookTriggerEnabled == true` gefunden werden:
```swift
    func mapping(for webhookId: String) -> WebhookMapping? {
        mappings.first { $0.webhookTriggerEnabled && $0.webhookId == webhookId }
    }
```

- [ ] **Step 3: Build**

Run: `cd app/UniFiCameraPopup && xcodebuild -project UniFiCameraPopup.xcodeproj -scheme UniFiCameraPopup -configuration Debug -derivedDataPath .build build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Migrations-Check mit alter Konfiguration**

Die Einstellungen liegen in `UserDefaults` (`com.snackbits.UniFiCameraPopup`, Schlüssel `unifi.camera.popup.settings`, JSON als Data). Vorher Menü → Einstellungen → „Konfiguration exportieren“ als Sicherung ausführen.
```bash
cd app/UniFiCameraPopup
open ".build/Build/Products/Debug/UniFi Camera Popup.app"; sleep 5
osascript -e 'quit app "UniFi Camera Popup"'; sleep 1
python3 - <<'PY'
import json, plistlib, subprocess
raw = subprocess.run(["defaults", "export", "com.snackbits.UniFiCameraPopup", "-"], capture_output=True).stdout
d = json.loads(plistlib.loads(raw)["unifi.camera.popup.settings"])
print([(m["webhookId"], m.get("webhookTriggerEnabled"), m.get("triggers")) for m in d["mappings"]])
PY
```
Expected: Jeder alte Eintrag mit nicht leerer `webhookId` hat `webhookTriggerEnabled: true`; ein Test-Popup über den Webhook (Menü → Kameras → Test) erscheint wie vorher.

- [ ] **Step 5: Commit**

```bash
cd app && git add UniFiCameraPopup/Models UniFiCameraPopup/Services/SettingsStore.swift UniFiCameraPopup/Services/KeychainStore.swift
git commit -m "feat(protect): store console, API key and per-camera Protect triggers"
```

---

### Task 8: ProtectSession und Ereignis-Dienst

**Files:**
- Create: `app/UniFiCameraPopup/Services/ProtectSession.swift`
- Create: `app/UniFiCameraPopup/Services/ProtectEventService.swift`
- Modify: `app/UniFiCameraPopup/Services/PopupController.swift:37-72` (Mapping-Suche, Stream-Auflösung)
- Modify: `app/UniFiCameraPopup/AppDelegate.swift:50-54` (Dienste starten), Statusanzeige

**Interfaces:**
- Consumes: `ProtectClient`, `EventMessage`, `EventDeduplicator`, `Backoff` (ProtectKit); `SettingsStore` (Task 7)
- Produces:
  - `@MainActor final class ProtectSession: ObservableObject { static let shared; @Published private(set) var cameras: [ProtectCamera]; @Published private(set) var lastError: String?; var client: ProtectClient? ; func reconnect(); func refreshCameras() async; func streamURL(for mapping: WebhookMapping) async -> String? }`
  - `@MainActor final class ProtectEventService: ObservableObject { @Published private(set) var status: ConnectionStatus; var onTrigger: ((TriggerEvent) -> Void)?; func start(); func stop() }`

- [ ] **Step 1: `ProtectSession` anlegen**

```swift
import Foundation
import ProtectKit

/// Owns the Protect API client for the configured console and caches cameras/stream URLs.
@MainActor
final class ProtectSession: ObservableObject {
    static let shared = ProtectSession()

    @Published private(set) var cameras: [ProtectCamera] = []
    @Published private(set) var lastError: String?
    private(set) var client: ProtectClient?
    private var streamCache: [String: String] = [:]
    private let settings = SettingsStore.shared

    private init() {}

    /// Rebuilds the client from current settings (after onboarding or settings changes).
    func reconnect() {
        streamCache = [:]
        guard settings.isProtectConfigured else {
            client = nil
            cameras = []
            return
        }
        client = ProtectClient(
            host: settings.protectHost,
            apiKey: settings.protectAPIKey,
            pinnedFingerprint: settings.protectCertificateFingerprint,
            onNewFingerprint: { fp in
                Task { @MainActor in SettingsStore.shared.protectCertificateFingerprint = fp }
            }
        )
        Task { await refreshCameras() }
    }

    func refreshCameras() async {
        guard let client else { return }
        do {
            cameras = try await client.cameras()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Manual RTSP URL wins (hidden "Erweitert" field); otherwise ask Protect.
    func streamURL(for mapping: WebhookMapping) async -> String? {
        let manual = mapping.rtspsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !manual.isEmpty { return StreamURL.normalizedRTSP(manual) }
        guard let cameraId = mapping.protectCameraId, let client else { return nil }
        if let cached = streamCache[cameraId] { return cached }
        do {
            let url = try await client.rtspURL(cameraId: cameraId)
            if let url { streamCache[cameraId] = url }
            return url
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }
}
```

- [ ] **Step 2: `ProtectEventService` anlegen**

```swift
import Foundation
import ProtectKit

/// Listens to /v1/subscribe/events and turns matching Protect events into popups.
@MainActor
final class ProtectEventService: ObservableObject {
    @Published private(set) var status: ConnectionStatus = .disconnected
    var onTrigger: ((TriggerEvent) -> Void)?

    private let settings = SettingsStore.shared
    private var task: URLSessionWebSocketTask?
    private var loop: Task<Void, Never>?
    private var dedup = EventDeduplicator()
    private var backoff = Backoff(base: 2, max: 60)

    func start() {
        stop()
        loop = Task { [weak self] in await self?.run() }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        status = .disconnected
    }

    private func run() async {
        while !Task.isCancelled {
            guard let client = ProtectSession.shared.client else {
                status = .disconnected
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                continue
            }
            status = .connecting
            let ws = client.eventsWebSocket()
            task = ws
            ws.resume()
            do {
                while !Task.isCancelled {
                    let message = try await ws.receive()
                    if status != .connected { status = .connected; backoff.reset() }
                    let data: Data
                    switch message {
                    case .string(let text): data = Data(text.utf8)
                    case .data(let d): data = d
                    @unknown default: continue
                    }
                    handle(data)
                }
            } catch {
                NSLog("Protect events websocket closed: \(error.localizedDescription)")
            }
            status = .disconnected
            let delay = backoff.next()
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    private func handle(_ data: Data) {
        guard let trigger = EventMessage.parse(data), dedup.isNew(trigger.eventId) else { return }
        for mapping in settings.mappings(forProtectCamera: trigger.cameraId)
        where !mapping.triggers.isDisjoint(with: trigger.kinds) {
            let label = TriggerKind.ordered.first { trigger.kinds.contains($0) && mapping.triggers.contains($0) }?.label
            onTrigger?(TriggerEvent(
                webhookId: mapping.webhookId,
                thumbnail: nil,
                alarmName: [label, mapping.label].compactMap { $0 }.joined(separator: " · "),
                timestamp: trigger.start,
                mappingId: mapping.entryId,
                kinds: trigger.kinds
            ))
        }
    }
}
```

- [ ] **Step 3: `PopupController` anpassen**

In `present(event:)` die Mapping-Suche und Stream-Auflösung ersetzen:
```swift
    private func present(event: TriggerEvent) {
        let found = event.mappingId.flatMap(settings.mapping(forEntry:)) ?? settings.mapping(for: event.webhookId)
        guard let mapping = found else {
            NSLog("No mapping for event: \(event.webhookId) \(String(describing: event.mappingId))")
            return
        }
        let key = mapping.entryId.uuidString

        if let existing = activePopups.first(where: { $0.webhookId == key }) {
            existing.window.extendAutoClose(seconds: settings.autoCloseTimeout)
            return
        }

        Task { @MainActor in
            guard let streamURL = await ProtectSession.shared.streamURL(for: mapping) else {
                NSLog("No stream URL for \(mapping.label)")
                return
            }
            if !settings.showAllActiveCameras { dismiss() }
            let window = makeAlarmWindow(event: event, mapping: mapping, streamURL: streamURL)
            activePopups.append(ActivePopup(
                webhookId: key,
                window: window,
                size: CGSize(width: CGFloat(mapping.width), height: CGFloat(mapping.height)),
                position: mapping.positionOverride ?? settings.defaultPosition
            ))
            relayout()
            window.orderFrontRegardless()
            window.startPlayback()
        }
    }
```
`ActivePopup.webhookId` speichert ab jetzt den Eintrags-Schlüssel (`entryId.uuidString`). Alle anderen Stellen im `PopupController`, die `activePopups` über `webhookId` suchen oder entfernen (`removePopup(webhookId:)`, `showManualPopup`, Callbacks aus `makeAlarmWindow`), auf `mapping.entryId.uuidString` umstellen. Die manuellen Popups (`showTestPopup`, `showHotkeyPopup`) lösen ihre Stream-URL ebenfalls über `await ProtectSession.shared.streamURL(for:)` auf statt `mapping.rtspsURL`.

- [ ] **Step 4: `AppDelegate` verdrahten**

Eigenschaft ergänzen: `private let protectEvents = ProtectEventService()`. In `setupWebSocket()`:
```swift
    private func setupWebSocket() {
        webSocketClient.onTrigger = { event in
            PopupController.shared.show(event: event)
        }
        protectEvents.onTrigger = { event in
            PopupController.shared.show(event: event)
        }
        ProtectSession.shared.reconnect()
        protectEvents.start()
    }
```
In `applicationWillTerminate` `protectEvents.stop()` ergänzen. Der Relay-WebSocket (`webSocketClient.start()`) soll nur starten, wenn mindestens ein Eintrag `webhookTriggerEnabled` hat – vorhandenen Start-Aufruf entsprechend mit `if settings.mappings.contains(where: \.webhookTriggerEnabled)` umschließen.

Statuszeile im Menü: Der vorhandene Status-Text (aus `webSocketClient.status`) bekommt die Protect-Verbindung vorangestellt: Beobachtung von `protectEvents.$status` analog zur vorhandenen Beobachtung ergänzen; Text: `"Protect: verbunden"` / `"Protect: verbinde …"` / `"Protect: getrennt"`.

- [ ] **Step 5: Build und Live-Test**

Run: `cd app/UniFiCameraPopup && xcodebuild -project UniFiCameraPopup.xcodeproj -scheme UniFiCameraPopup -configuration Debug -derivedDataPath .build build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

Live (mit echter Konsole, nach Task 9/10 einfacher – hier per `defaults`-freier Vorbereitung): App starten, über Task 10 Konsole + Schlüssel setzen, Kamera „Haustür“ mit Auslöser Klingel zuordnen, klingeln. Expected: Popup erscheint innerhalb von ~2 s mit Titel „Klingel · Haustür“; Menüstatus „Protect: verbunden“. Netzwerk am Mac 30 s trennen → Status „getrennt“, danach automatisch „verbunden“.

- [ ] **Step 6: Commit**

```bash
cd app && git add UniFiCameraPopup && git commit -m "feat(protect): open popups from Protect events and resolve streams via the API"
```

---

### Task 9: Onboarding (Schritte 1–5)

**Files:**
- Create: `app/UniFiCameraPopup/Views/Onboarding/OnboardingView.swift`
- Create: `app/UniFiCameraPopup/Views/Onboarding/OnboardingWindow.swift`
- Modify: `app/UniFiCameraPopup/AppDelegate.swift` (beim ersten Start zeigen; Menüeintrag „Einrichtung …“)
- Modify: `project.pbxproj` (zwei neue Dateien in Sources-Build-Phase und Gruppe `Views`, IDs nach vorhandenem Schema)

**Interfaces:**
- Consumes: `ConsoleDiscovery`, `DiscoveredConsole`, `ProtectClient`, `ProtectCamera`, `TriggerKind`, `SettingsStore`, `ProtectSession`
- Produces: `@MainActor enum OnboardingWindow { static func show() }`

Gestaltung nach Vorlage C (Board „Einrichtung & Alltag“): zentriert, Kreis-Icon oben, Titel 20 pt bold, Erklärtext 12 pt sekundär, primärer Button 220 pt breit unten, darunter Fortschrittspunkte. Akzentfarbe `Color(red: 0.294, green: 0.247, blue: 0.82)` (#4B3FD1) hell / #5B4FE0 dunkel über `Color("AccentIndigo")` im Asset-Katalog **oder** direkt als dynamische `NSColor`. Fenster 560 × 420, `titlebarAppearsTransparent`, Systemerscheinungsbild.

- [ ] **Step 1: Zustandsmodell und View**

`Views/Onboarding/OnboardingView.swift`:
```swift
import ProtectKit
import SwiftUI

@MainActor
final class OnboardingModel: ObservableObject {
    enum Step: Int, CaseIterable { case welcome, console, key, cameras, triggers }

    @Published var step: Step = .welcome
    @Published var consoles: [DiscoveredConsole] = []
    @Published var isScanning = false
    @Published var selectedHost = ""
    @Published var manualHost = ""
    @Published var apiKey = ""
    @Published var checking = false
    @Published var keyError: String?
    @Published var cameras: [ProtectCamera] = []
    @Published var selectedCameraIds: Set<String> = []
    @Published var triggers: [String: Set<TriggerKind>] = [:]
    @Published var triggerTab: String = ""
    var onFinish: () -> Void = {}

    private var fingerprint: String?

    var host: String { manualHost.trimmingCharacters(in: .whitespaces).isEmpty ? selectedHost : manualHost }

    func scan() {
        isScanning = true
        Task {
            let found = await ConsoleDiscovery().scan(duration: 3)
            consoles = found
            if selectedHost.isEmpty, let first = found.first { selectedHost = first.ip }
            isScanning = false
        }
    }

    func checkKey() {
        checking = true
        keyError = nil
        let client = ProtectClient(host: host, apiKey: apiKey, pinnedFingerprint: nil, onNewFingerprint: { [weak self] fp in
            Task { @MainActor in self?.fingerprint = fp }
        })
        Task {
            do {
                _ = try await client.metaInfo()
                let cams = try await client.cameras()
                cameras = cams
                selectedCameraIds = Set(cams.filter(\.isConnected).map(\.id))
                for cam in cams {
                    triggers[cam.id] = cam.enabledTriggers.intersection([.ring, .person, .package, .vehicle, .animal])
                }
                triggerTab = cams.first(where: { selectedCameraIds.contains($0.id) })?.id ?? ""
                step = .cameras
            } catch {
                keyError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            checking = false
        }
    }

    func finish() {
        let settings = SettingsStore.shared
        settings.protectHost = host
        settings.protectCertificateFingerprint = fingerprint
        settings.protectAPIKey = apiKey
        for cam in cameras where selectedCameraIds.contains(cam.id) {
            if let index = settings.mappings.firstIndex(where: { $0.protectCameraId == cam.id }) {
                settings.mappings[index].triggers = triggers[cam.id] ?? []
            } else {
                var mapping = WebhookMapping(rtspsURL: "", label: cam.name)
                mapping.protectCameraId = cam.id
                mapping.triggers = triggers[cam.id] ?? [.ring, .person]
                settings.mappings.append(mapping)
            }
        }
        ProtectSession.shared.reconnect()
        onFinish()
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 12) {
            switch model.step {
            case .welcome: welcome
            case .console: console
            case .key: key
            case .cameras: camerasStep
            case .triggers: triggersStep
            }
            dots
        }
        .padding(.horizontal, 44)
        .padding(.top, 28)
        .padding(.bottom, 22)
        .frame(width: 560, height: 420)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingModel.Step.allCases, id: \.self) { s in
                Circle()
                    .fill(s == model.step ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Schritt \(model.step.rawValue + 1) von \(OnboardingModel.Step.allCases.count)")
    }

    private func header(_ symbol: String, _ title: String, _ text: String?) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Color.accentColor.opacity(0.14)))
            Text(title).font(.title3.bold()).multilineTextAlignment(.center)
            if let text {
                Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func primary(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).frame(width: 196) }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(disabled)
    }

    private var welcome: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.fill")
                .font(.system(size: 38))
                .foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color.accentColor))
            Text("Willkommen bei Camera Popup").font(.title2.bold())
            Text("Wenn jemand klingelt oder eine Kamera etwas erkennt, siehst du es sofort – und kannst direkt antworten.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            primary("Weiter") { model.step = .console; model.scan() }
        }
    }

    private var console: some View {
        VStack(spacing: 12) {
            header("server.rack", model.consoles.isEmpty ? "Wir suchen deine Konsole …" : "Wir haben deine Konsole gefunden", nil)
            VStack(spacing: 6) {
                ForEach(model.consoles, id: \.ip) { c in
                    Button { model.selectedHost = c.ip; model.manualHost = "" } label: {
                        HStack {
                            Text(c.displayName).fontWeight(model.selectedHost == c.ip ? .semibold : .regular)
                            Spacer()
                            Text(c.ip).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(model.selectedHost == c.ip && model.manualHost.isEmpty ? Color.accentColor : Color.secondary.opacity(0.3),
                                          lineWidth: model.selectedHost == c.ip && model.manualHost.isEmpty ? 2 : 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if model.isScanning { ProgressView().controlSize(.small) }
                TextField("Oder Adresse eingeben, z. B. 192.168.1.1", text: $model.manualHost)
                    .textFieldStyle(.roundedBorder)
            }
            Spacer()
            primary("Diese verwenden", disabled: model.host.isEmpty) { model.step = .key }
        }
    }

    private var key: some View {
        VStack(spacing: 11) {
            header("key.fill", "Ein Schlüssel für die App",
                   "Erzeuge in deiner Konsole unter Einstellungen einen API-Schlüssel – der Bereich heißt meist „API“ oder „Integrationen“ – und füge ihn hier ein.")
            SecureField("API-Schlüssel", text: $model.apiKey)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.checkKey() }
            if let error = model.keyError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.red)
            }
            Link("Konsole im Browser öffnen", destination: URL(string: "https://\(model.host)")!)
                .font(.callout)
            Spacer()
            HStack {
                Button("Zurück") { model.step = .console }.controlSize(.large)
                primary(model.checking ? "Prüfe …" : "Verbinden", disabled: model.apiKey.isEmpty || model.checking) { model.checkKey() }
            }
        }
    }

    private var camerasStep: some View {
        VStack(spacing: 12) {
            Text("Welche Kameras sollen sich melden?").font(.title3.bold())
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                    ForEach(model.cameras) { cam in
                        let on = model.selectedCameraIds.contains(cam.id)
                        Button {
                            if on { model.selectedCameraIds.remove(cam.id) } else { model.selectedCameraIds.insert(cam.id) }
                        } label: {
                            VStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.black.opacity(0.75))
                                    .frame(height: 70)
                                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 3))
                                    .overlay(alignment: .bottomTrailing) {
                                        if on {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, Color.accentColor).padding(5)
                                        }
                                    }
                                    .opacity(cam.isConnected ? 1 : 0.5)
                                Text(cam.name).font(.callout.weight(.semibold)).lineLimit(1)
                                Text(cam.hasSpeaker ? "mit Lautsprecher" : "nur Bild").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            primary("Weiter mit \(model.selectedCameraIds.count) Kameras", disabled: model.selectedCameraIds.isEmpty) {
                model.triggerTab = model.cameras.first { model.selectedCameraIds.contains($0.id) }?.id ?? ""
                model.step = .triggers
            }
        }
    }

    private var triggersStep: some View {
        let selected = model.cameras.filter { model.selectedCameraIds.contains($0.id) }
        let current = selected.first { $0.id == model.triggerTab } ?? selected.first
        return VStack(spacing: 14) {
            Text("Wann soll sich welche Kamera melden?").font(.title3.bold())
            Picker("Kamera", selection: $model.triggerTab) {
                ForEach(selected) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if let cam = current {
                Text("Tippe an, was bei \(cam.name) ein Popup auslöst. Gestrichelt: kann diese Kamera nicht.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                TriggerChips(camera: cam, selection: Binding(
                    get: { model.triggers[cam.id] ?? [] },
                    set: { model.triggers[cam.id] = $0 }
                ))
            }
            Spacer()
            primary("Fertig") { model.finish() }
        }
    }
}

/// Toggle chips for trigger kinds; shared with the settings view.
struct TriggerChips: View {
    let camera: ProtectCamera
    @Binding var selection: Set<TriggerKind>

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(TriggerKind.ordered.filter { camera.supportedTriggers.contains($0) || [.ring, .person, .vehicle, .animal, .package].contains($0) }, id: \.self) { kind in
                let supported = camera.supportedTriggers.contains(kind)
                let on = selection.contains(kind)
                Button {
                    if on { selection.remove(kind) } else { selection.insert(kind) }
                } label: {
                    Text(kind.label)
                        .font(.callout.weight(on ? .semibold : .regular))
                        .strikethrough(!supported)
                        .padding(.horizontal, 13).padding(.vertical, 6)
                        .foregroundStyle(on ? Color.white : (supported ? Color.primary : Color.secondary))
                        .background(Capsule().fill(on ? Color.accentColor : Color.clear))
                        .overlay(Capsule().strokeBorder(Color.secondary.opacity(on ? 0 : 0.5),
                                                        style: StrokeStyle(lineWidth: 1, dash: supported ? [] : [3])))
                }
                .buttonStyle(.plain)
                .disabled(!supported)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Minimal wrapping layout (macOS 13+).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if rows[rows.count - 1].width + size.width > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
```

- [ ] **Step 2: Fenster-Hülle**

`Views/Onboarding/OnboardingWindow.swift`:
```swift
import AppKit
import SwiftUI

@MainActor
enum OnboardingWindow {
    private static var window: NSWindow?

    static func show() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let model = OnboardingModel()
        let host = NSHostingController(rootView: OnboardingView(model: model))
        let w = NSWindow(contentViewController: host)
        w.title = "Camera Popup einrichten"
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.setContentSize(NSSize(width: 560, height: 420))
        w.center()
        model.onFinish = { w.close() }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            Task { @MainActor in window = nil }
        }
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 3: AppDelegate**

Nach dem Aufbau des Menüs (in `applicationDidFinishLaunching`, nach `setupStatusItem()`):
```swift
        if !settings.isProtectConfigured && settings.mappings.isEmpty {
            OnboardingWindow.show()
        }
```
Im Menü vor „Einstellungen…“:
```swift
        let setupItem = NSMenuItem(title: "Einrichtung …", action: #selector(openOnboarding), keyEquivalent: "")
        setupItem.target = self
        menu.addItem(setupItem)
```
und
```swift
    @objc private func openOnboarding() { OnboardingWindow.show() }
```
Die App-Akzentfarbe auf Indigo setzen: in `Assets.xcassets` eine Farbe `AccentColor` mit Hell #4B3FD1 / Dunkel #5B4FE0 anlegen (falls `AccentColor` existiert, Werte ersetzen) – SwiftUI `Color.accentColor` und `.borderedProminent` übernehmen sie.

- [ ] **Step 4: Dateien ins Xcode-Projekt eintragen**

In `project.pbxproj` je Datei einen `PBXFileReference`, einen `PBXBuildFile` (Sources), Eintrag in der Gruppe `Views` (Untergruppe `Onboarding`) und in `PBXSourcesBuildPhase` – nach dem Muster einer vorhandenen View wie `WhatsNewView.swift` (dessen Einträge mit `grep -n WhatsNewView project.pbxproj` finden und analog mit freien IDs kopieren).

- [ ] **Step 5: Build und Durchlauf**

Run: Build wie in Task 2. Dann:
```bash
open ".build/Build/Products/Debug/UniFi Camera Popup.app"
```
Menü → „Einrichtung …“ (die vorhandene Konfiguration **nicht** löschen). Expected: Willkommen → Konsole wird nach ≤ 3 s gelistet (oder manuelle Adresse) → falscher Schlüssel zeigt „Der API-Schlüssel wurde abgelehnt.“ → richtiger Schlüssel listet Kameras → Auslöser je Kamera über den Segment-Umschalter → „Fertig“ legt Einträge an; Hell/Dunkel folgt dem System.

- [ ] **Step 6: Commit**

```bash
cd app && git add UniFiCameraPopup && git commit -m "feat(onboarding): guided setup with console discovery, API key and camera triggers"
```

---

### Task 10: Protect in den bestehenden Einstellungen

**Files:**
- Modify: `app/UniFiCameraPopup/Views/SettingsView.swift`

**Interfaces:**
- Consumes: `SettingsStore` (Task 7), `ProtectSession` (Task 8), `TriggerChips` (Task 9), `OnboardingWindow`

Ziel (Übergang bis Phase 2): Oben ein Abschnitt „UniFi Protect“; pro Kamera-Eintrag ein Kamera-Picker und die Auslöser-Chips; Webhook-ID und RTSP-URL wandern in ein zugeklapptes „Erweitert“.

- [ ] **Step 1: Abschnitt „UniFi Protect“ oben in der Form**

```swift
        Section("UniFi Protect") {
            LabeledContent("Konsole") {
                HStack(spacing: 6) {
                    Circle().fill(protect.lastError == nil && settings.isProtectConfigured ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(settings.protectHost.isEmpty ? "nicht eingerichtet" : settings.protectHost)
                        .foregroundStyle(.secondary)
                    Button("Einrichtung …") { OnboardingWindow.show() }
                }
            }
            if let error = protect.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                if error == ProtectError.certificateChanged.errorDescription {
                    Button("Neuem Zertifikat vertrauen") {
                        settings.protectCertificateFingerprint = nil
                        ProtectSession.shared.reconnect()
                    }
                }
            }
        }
```
mit `@ObservedObject private var protect = ProtectSession.shared` in `SettingsView` und `import ProtectKit`.

- [ ] **Step 2: Pro Eintrag Kamera-Picker, Auslöser, „Erweitert“**

Im vorhandenen Block pro `mapping` (dort, wo bisher das RTSP-Feld steht, ca. Zeile 140) das RTSP-Feld und das Webhook-ID-Feld in einen `DisclosureGroup("Erweitert")` verschieben und davor einfügen:
```swift
                Picker("Kamera", selection: $mapping.protectCameraId) {
                    Text("Keine (nur Webhook)").tag(String?.none)
                    ForEach(protect.cameras) { cam in
                        Text(cam.name).tag(Optional(cam.id))
                    }
                }
                if let id = mapping.protectCameraId, let cam = protect.cameras.first(where: { $0.id == id }) {
                    LabeledContent("Auslöser") {
                        TriggerChips(camera: cam, selection: $mapping.triggers)
                    }
                }
                DisclosureGroup("Erweitert") {
                    Toggle("Zusätzlich per Webhook auslösen", isOn: $mapping.webhookTriggerEnabled)
                    if mapping.webhookTriggerEnabled {
                        // vorhandenes Webhook-ID-Feld hierher verschieben
                    }
                    // vorhandenes RTSP-URL-Feld hierher verschieben, Prompt: "automatisch aus Protect"
                }
```
Die beiden Kommentare stehen für das **Verschieben der vorhandenen Felder** (kein neuer Code): das bestehende `TextField` für `webhookId` und das bestehende `TextField("RTSP URL", …)` samt Warnung aus ihrer bisherigen Position ausschneiden und an diesen Stellen einfügen. Beim RTSP-Feld den Prompt auf `Text("automatisch aus Protect")` ändern.

Die Gültigkeitsprüfung, die bisher eine RTSP-URL verlangt (`SettingsView.swift:438` und `AppDelegate.swift:527`: `!mapping.rtspsURL…isEmpty`), erweitern auf `mapping.protectCameraId != nil || !mapping.rtspsURL…isEmpty`.

- [ ] **Step 3: Kameras beim Öffnen laden**

Am Ende der `body`-Form: `.task { await ProtectSession.shared.refreshCameras() }`.

- [ ] **Step 4: Build und Sichtprüfung**

Build wie in Task 2, App starten, Einstellungen öffnen. Expected: Abschnitt „UniFi Protect“ zeigt Konsole und Status; Einträge aus dem Onboarding zeigen Kamera und Auslöser-Chips; „Erweitert“ ist zugeklappt und enthält Webhook-Schalter, Webhook-ID und RTSP-Feld; alte Webhook-Einträge zeigen „Keine (nur Webhook)“ mit eingeschaltetem Webhook-Schalter.

- [ ] **Step 5: Commit**

```bash
cd app && git add UniFiCameraPopup/Views/SettingsView.swift UniFiCameraPopup/AppDelegate.swift
git commit -m "feat(settings): Protect camera picker, trigger chips and hidden webhook options"
```

---

### Task 11: Ende-zu-Ende-Prüfung, Version, „Was ist neu“

**Files:**
- Modify: Versionsnummer (wie in `build-release.sh`/Info.plist üblich) → **1.2.0**
- Modify: `app/UniFiCameraPopup/Services/WhatsNewService.swift` (Eintrag 1.2.0)

- [ ] **Step 1: Alle Package-Tests**

Run: `cd app/Packages/ProtectKit && swift test`
Expected: PASS, 0 failures.

- [ ] **Step 2: Echter Ablauf mit Konsole** (Checkliste, jeweils Ergebnis notieren)

1. Frisches Onboarding findet die Konsole per Discovery.
2. Falscher Schlüssel → Fehlermeldung; richtiger → Kameraliste mit korrekten Namen und „mit Lautsprecher“.
3. Klingeln an der Türklingel → Popup „Klingel · Haustür“ in ≤ 2 s, Livebild läuft.
4. Person vor einer Kamera mit Auslöser „Person“ → Popup; vor einer Kamera ohne diesen Auslöser → kein Popup.
5. Kamera ohne zuvor aktivierten RTSP-Stream → Popup läuft trotzdem (Stream wurde per API angelegt).
6. Alter Webhook-Eintrag → Webhook-Popup wie vor dem Update.
7. Mac 60 s offline → Status „getrennt“, danach automatisch „verbunden“, nächstes Ereignis kommt an.

- [ ] **Step 3: Version und „Was ist neu“**

Version auf 1.2.0 setzen (Stellen wie beim Commit `8c5fb67` für 1.1.0). In `WhatsNewService` einen Eintrag ergänzen:
```
1.2.0 – Direkt mit UniFi Protect
• Einrichtung in wenigen Schritten: Konsole wird im Netzwerk gefunden, API-Schlüssel genügt.
• Popups bei Klingel, Person, Tier, Fahrzeug, Sprache und mehr – direkt aus Protect.
• Stream-Adressen holt die App selbst. Webhooks gibt es weiterhin unter „Erweitert“.
```
(Format an die vorhandenen Einträge in `WhatsNewService.swift` anpassen.)

- [ ] **Step 4: Release-Build**

Run: `cd app/UniFiCameraPopup && ./scripts/build-release.sh`
Expected: Build erfolgreich, App startet.

- [ ] **Step 5: Commit**

```bash
cd app && git add -A UniFiCameraPopup && git commit -m "chore: release 1.2.0 with direct UniFi Protect integration"
```
(Push und Server-Deploy erst nach Rückfrage – siehe Release-Ablauf.)
