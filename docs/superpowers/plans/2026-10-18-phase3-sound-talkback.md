# Phase 3 – Ton & Sprechen (Talkback, Push-to-Talk, Ansagen, Reiter „Ton“) – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bei Protect-Kameras mit Lautsprecher kann man im Popup per Push-to-Talk mit dem Mac-Mikrofon sprechen und Ansagen abspielen (MP3 oder Text mit macOS-Stimme); der Reiter „Ton“ der Einstellungen verwaltet Ansagen, Mikrofon, Sprech-Modus und Lautstärke – 1:1 nach Vorlage.

**Architecture:** Die gesamte Ton-Kette ist testbare Logik im Package `AppCore` (Ordner `Talkback/` und `Sound/`): PCM → `PCMResampler` (AVAudioConverter, mono 16 bit, Kamera-Rate, Verstärkung) → `TalkbackEncoder` (AudioToolbox: AAC-LC bzw. Opus) → `ADTS`-Rahmen bzw. `RTPPacketizer` (RFC 7587) → `RealtimePacer` → UDP über Network.framework (`TalkbackStreamer`). `ProtectKit` holt die Talkback-Sitzung (`ProtectClient.talkbackSession`, gleicher Zertifikats-Pin und API-Schlüssel) und parst sie tolerant. Die App verdrahtet: `SoundStore` (Ansagen, eigene Ablage), `MicrophoneCapture` (AVAudioEngine + Core-Audio-Gerät), `TalkbackService` (Ablauf, Fehler, Diagnose-Log), `PushToTalkKey` (Leertaste), Reiter `SoundTab` und `PopupTalkControls` im Popup.

**Tech Stack:** Swift 5.9 Tools / Xcode 27, SwiftUI + AppKit (macOS 13.0), AudioToolbox (`AudioConverterNew`/`AudioConverterFillComplexBuffer`), AVFoundation (`AVAudioEngine`, `AVAudioConverter`, `AVAudioFile`, `AVSpeechSynthesizer.write`), Network.framework (`NWConnection` UDP), Carbon-Hotkeys, XCTest über `swift test`.

**Spec:** `docs/superpowers/specs/2026-10-18-phases-2-4.md` (Abschnitte „Verbindliche Vorlage“, „Phase 3“, „Querschnitt“). Vorlage: `docs/superpowers/specs/phase2-4/design/Main.dc.html` (Bildschirm 8 „Popup mit Sprechen & Ton“, Popup aus Vorlage B) und `.../Einstellungen.dc.html` (Bildschirm S5 „Ton & Sprechen“). Referenz Talkback: `docs/superpowers/specs/phase2-4/reference/uiprotect-stream.py` (uiprotect 23.2.0). Ansagen: `docs/superpowers/specs/phase2-4/sounds/bin-gleich-da.mp3`, `paket-abstellen.mp3` (Piper, Stimme Thorsten, Datensatz CC0). Baut auf `docs/superpowers/plans/2026-10-18-phase2-design-mute.md` auf; Format/Befehle wie dort.

> **Vorab geprüft (18.10.2026):** Alle `AppCore`- und `ProtectKit`-Schritte (Task 1–4) wurden in einer Kopie der Packages auf dem Stand nach Phase-2-Task 4 angewendet: `swift test` AppCore 56/56 (davon 24 neu), ProtectKit 57/57 (5 neu) – inklusive echter Kodierung mit den System-Encodern (der AAC-Strom aus `ADTS`-Rahmen lässt sich mit `AVAudioFile` wieder öffnen), UDP über Loopback mit Echtzeit-Taktung und Sprachsynthese mit einer installierten deutschen macOS-Stimme. Die App-Dateien aus Task 5–8 wurden mit `swiftc -typecheck` gegen `AppCore`, `ProtectKit`, die echten Phase-2-Dateien `DesignComponents.swift`/`PopUpField.swift` und `PopupOverlayViews.swift` aus dem Phase-2-Plan (Task 7) geprüft (fehlerfrei, ohne Warnungen). Ein vollständiger `xcodebuild` steht aus, weil Phase 2 beim Schreiben noch nicht fertig war. **An echter Kamera nicht geprüft** (siehe Task 9, Hardware-Prüfpunkt).

## Voraussetzung: Phase 2 ist umgesetzt

Dieser Plan benutzt Typen, Dateien und Funktionen mit den Namen aus dem Phase-2-Plan. Vor Task 1 prüfen (jede Zeile > 0):

```bash
grep -c "public enum Tokens" Packages/AppCore/Sources/AppCore/DesignTokens.swift
grep -c "enum TemplateIcon" UniFiCameraPopup/Views/Design/DesignComponents.swift
grep -c "struct VolumeTrack\|struct TokenSegmented\|struct TokenTextField\|struct AccentButtonStyle\|struct LinkButtonStyle\|struct SectionLabel" UniFiCameraPopup/Views/Design/DesignComponents.swift
grep -c "struct PopUpField" UniFiCameraPopup/Views/Design/PopUpField.swift
grep -c "struct SoundTab\|struct RemoteTab" UniFiCameraPopup/Views/Settings/SoundAndRemoteTabs.swift
grep -c "struct PopupOverlayContent\|final class ActionPillView\|final class CircleIconButton\|func cgColor" UniFiCameraPopup/Views/Popup/PopupOverlayViews.swift
grep -c "private var muteMenu: PopupMuteMenuView?\|private func setupOverlay" UniFiCameraPopup/Views/PopupWindow.swift
grep -c "overlay: overlay," UniFiCameraPopup/Services/PopupController.swift
grep -c "func sendRaw" Packages/ProtectKit/Sources/ProtectKit/ProtectClient.swift
```

Weicht ein Name im Phase-2-Code ab, gilt der tatsächliche Name; die Stelle im Code dieses Plans wird entsprechend angepasst (nur der Name, nicht das Verhalten). Es gibt **kein** Test-Bundle im Xcode-Projekt (Phase-2-Entscheidung „Test-Target als lokales Package“): Testbares liegt in `AppCore` bzw. `ProtectKit`.

## Global Constraints

- macOS-Deployment-Target **13.0**; keine API neuer als macOS 13 ohne `#available` (geplant: keine). Keine Sandbox, Hardened Runtime bleibt aus, kein bezahlter Developer-Account; Signatur unverändert.
- Mikrofon: `NSMicrophoneUsageDescription` in `UniFiCameraPopup/Info.plist` (das Projekt hat `GENERATE_INFOPLIST_FILE = NO`, darum kein `INFOPLIST_KEY_…`).
- Talkback: `POST /v1/cameras/{id}/talkback-session` (Header `X-API-KEY`) über `ProtectClient` – gleicher Zertifikats-Pin, keine Weiterleitungen. Antwort: `url` (z. B. `rtp://<kamera-ip>:7004`), `codec` (`aac`/`opus`/`vorbis`), `samplingRate`, `bitsPerSample`. Ton **mono**, im angegebenen Codec, **in Echtzeit getaktet**, per UDP direkt an die Kamera: **AAC als ADTS-Rahmen, Opus als RTP**. Vorbis wird nicht gesendet (klare Fehlermeldung).
- AAC und Opus **nativ über AudioToolbox**; RTP-Paketierung (RFC 7587) und ADTS-Header schreibt die App selbst; **kein ffmpeg**. UDP über **Network.framework**.
- Nicht an echter Hardware verifiziert: Parsing tolerant, jeder Schritt im Diagnose-Log `~/Library/Logs/UniFi Camera Popup/talkback.log` und per `NSLog`, Fehler als Hinweis im Popup, manueller Prüfpunkt in Task 9.
- Ansagen: MP3 (mitgeliefert oder eigene Datei) oder Text mit **macOS-Stimmen** (`AVSpeechSynthesizer.write` in Puffer). **piper/espeak-ng (GPL) kommen nicht in die App.** Mitgeliefert: `bin-gleich-da.mp3` („Bin gleich da“), `paket-abstellen.mp3` („Paket bitte abstellen“), Lizenzhinweis Piper/Thorsten/CC0 in der Hilfe.
- Sprechen/Ansage nur für Protect-Kameras mit `ProtectCamera.hasSpeaker == true`.
- UI-Sprache Deutsch, Du-Form, typografische Anführungszeichen „…“; Code und Bezeichner Englisch. Die Vorlage ist **Vorgabe, keine Anregung**: Maße, Texte, Farben, Reihenfolge 1:1 aus `docs/design/einstellungen-ton.md` und `docs/design/popup.md` (Task 7/8 schreiben die Phase-3-Fassung). Abweichungen nur die unten genannten.
- API-Schlüssel nur im Schlüsselbund, nie im Log, nie im Konfigurations-Export. Ton-Einstellungen und Ansagen-Dateien liegen nur auf diesem Mac (eigener `UserDefaults`-Schlüssel `unifi.camera.popup.sound`, Dateien in `~/Library/Application Support/UniFi Camera Popup/Sounds/`).
- Version bleibt **1.2.0**, Build-Nummer unangetastet; nur der bestehende 1.2.0-Eintrag in `WhatsNewService` wird ergänzt. `build-release.sh` wird nicht ausgeführt.
- `UniFiCameraPopup/AppConfig.swift` hat lokale Änderungen des Nutzers: **nie ändern, nie stagen, nie zurücksetzen**. Nur explizite Pfade `git add`; nie `git add -A`, `git add .` oder `git commit -a`. Vor jedem Commit: `git diff --cached --name-only | grep AppConfig` muss leer sein.
- Kein Merge, kein Push. Jeder Task endet mit grünem Build. Commit-Nachrichten enden mit `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Neue pbxproj-IDs: Präfix **C3** (`C31…` BuildFile, `C32…` FileRef, `C34…` Gruppe) – kollidiert weder mit Phase 1/2 (`A…`) noch mit Phase 4 (`D4…`). Vorher `grep -c "C31000000000000000000001\|C34000000000000000000001" UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj` → `0`.
- Debug-Build und installierte App teilen Bundle-ID und `UserDefaults`: vor Sichtprüfungen die installierte App beenden.

**Befehle** (aus dem Worktree-Wurzelverzeichnis `app-protect/`):

```bash
# App bauen
DD="${TMPDIR:-/tmp}/ucp-phase3-dd"
xcodebuild -project UniFiCameraPopup/UniFiCameraPopup.xcodeproj -scheme UniFiCameraPopup \
  -configuration Debug -derivedDataPath "$DD" build 2>&1 | grep -E "error:|\*\* BUILD" | tail -20
# Erwartet: ** BUILD SUCCEEDED **

# Tests
(cd Packages/AppCore && swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -3)
(cd Packages/ProtectKit && swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -3)

# App starten (installierte App vorher beenden)
open "$DD/Build/Products/Debug/UniFi Camera Popup.app"

# pbxproj nach Handänderung prüfen
plutil -lint UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj

# Diagnose während der Prüfung
tail -f ~/Library/Logs/UniFi\ Camera\ Popup/talkback.log
```

## Review Focus

1. **Talkback-Antwort in unerwarteter Form** (in `data` gehüllt, Zahl als Text, ohne Port, IPv6 in Klammern, Port 0, leer, `vorbis`, unbekannte Rate): klare deutsche Meldung im Popup, nie Absturz oder stilles Nichts. → `TalkbackSessionTests.testToleratesVariants`, `testRejectsAnswersWithoutTarget` (Task 3), `TalkbackFramingTests.testTargetValidation` (Task 1).
2. **Loslassen oder Popup schließen mitten im Senden**: kein weiteres Paket, kein Nachschub-Schwall an die Kamera. → `TalkbackStreamerTests.testStopDropsPendingPackets` (Task 2); Ablauf-Token in `TalkbackService` (Task 6) verhindert, dass eine überholte Sitzung noch live geht.
3. **Mikrofon liefert ungleichmäßig oder hakt kurz**: keine Pakete im Schwall nach einer Pause, keine Lücken durch krumme Puffergrößen. → `TalkbackFramingTests.testPacerReanchorsAfterStall` (Task 1), `TalkbackEncoderTests.testOpusMakes20msPackets` (Task 2, krumme 1234er-Stücke).
4. **Lautstärke-Regler ganz rechts bei lauter Stimme**: Werte werden begrenzt statt überzulaufen (kein Knacken). → `TalkbackEncoderTests.testResamplerDownmixesAndAppliesGain` (Task 2).
5. **Kaputte oder alte Ton-Einstellungen** (unbekannter Modus, Lautstärke 7, defekter Eintrag, leeres Objekt): Laden klappt, Rest bleibt erhalten, mitgelieferte Ansagen sind da. → `SoundSettingsTests.testLenientDecoding` (Task 4).

---

## Abweichungen von der Vorlage

Jede Zeile ist eine Stelle, an der SwiftUI/AppKit oder ein fehlender Zustand der Vorlage eine Entscheidung erzwingt. Umgesetzt wird der genannte Vorschlag; zur Bestätigung siehe „Offene Fragen“.

1. **„Gong“** (Vorlage: erste Ansage, MP3, 0:02) wird nicht mitgeliefert – es gibt keine Datei. Mitgeliefert sind „Bin gleich da“ und „Paket bitte abstellen“.
2. **Mitgelieferte Ansagen** tragen wie in der Vorlage das Badge „KI-STIMME“; ihre Stimme heißt im Editor „Thorsten · mitgeliefert“ und ist nur für den mitgelieferten Wortlaut wählbar (Piper ist nicht in der App). Ändert man den Text, wird eine macOS-Stimme gewählt. Längen sind die echten (0:03 und 0:04 statt 0:03/0:05).
3. **Ansagen-Menü im Popup**: Vorlage `left: 70px; bottom: 64px` im 470er Popup. Umsetzung: Unterkante auf der Oberkante der Leiste (= 64), linke Kante 45 vor „Ton abspielen“ (= 70 bei 470 Breite, gemessen mit SF 12/700), mindestens 10 vom Rand – damit es bei anderen Popup-Größen am Button bleibt.
4. **Zustände der Sprechen-Taste** (Vorlage zeigt nur Ruhe „Leertaste halten“): Modus „Umschalten“ → Ruhe „Sprechen“; Aufbau „Verbinde …“ (70 % Deckkraft); senden „Spricht …“ (Halten) bzw. „Beenden“ (Umschalten). **„Ton abspielen“ während einer Ansage**: Fläche `accent`, Symbol weiß, Klick stoppt.
5. **Leertaste**: Das Popup wird nie Schlüsselfenster (der Fokus bleibt in der App des Nutzers). Die Leertaste wirkt deshalb als globaler Hotkey, **solange der Mauszeiger über einem Popup mit Sprechen ist**; zusätzlich wirkt Gedrückthalten der Taste mit der Maus.
6. **Fehlerhinweis im Popup** (Vorlage hat keinen): Kapsel wie der Chip (`overlay`, 4/9, 11/600 weiß), mittig 8 über der Leiste, 6 s sichtbar, Tooltip mit vollem Text.
7. **Ansagen-Menü**: Zeile unter der Maus `accent` + weiß wie im Stumm-Menü (Vorlage zeigt keinen Hover).
8. **Editor „MP3-Datei“** (Vorlage zeigt nur „KI-Stimme“): Zeile „MP3-Datei · 0:03“ bzw. „Noch keine Datei gewählt.“ (13 `muted`) · Freiraum · „Datei wählen …“ · „Anhören“, Hinweis „MP3 bis 5 Minuten. Die Datei wird in die App kopiert und bleibt auf diesem Mac.“ Fehler als Zeile 11 System-Orange unter dem Hinweis. Ohne Auswahl entfällt die Editor-Karte.
9. **Umbenennen/Löschen**: natives Kontextmenü der Zeile („Umbenennen …“, „Löschen“) mit nativen Dialogen. Der Name neuer Text-Ansagen folgt dem ersten Satz des Textes („Bin gleich da! Einen …“ → „Bin gleich da“), bis man umbenennt.
10. **Stimmenliste**: alle deutschen macOS-Stimmen, Premium vor Erweitert vor Standard, Text „Anna (Premium) · macOS“, „… (Erweitert) · macOS“, „… · macOS“. Ohne deutsche Stimme: „Keine deutsche Stimme installiert“.
11. **„Lautstärke an der Kamera“** ist eine digitale Verstärkung in der App (Wert 2/3 – Vorlagenstellung – = unverändert, ganz rechts × 1,5 mit Begrenzung), nicht die Lautsprecher-Einstellung der Kamera (dafür ist kein Integration-API-Aufruf bekannt).
12. **Mikrofon**: Liste der Core-Audio-Eingabegeräte mit deren Namen; ein abgestecktes gespeichertes Gerät fällt still auf den System-Standard zurück. Ohne Gerät: „Kein Mikrofon“.
13. **Reiter scrollt** bei mehr als drei Ansagen (Inhalt sonst höher als 540).
14. **Probehören**: Symbol bleibt das Dreieck, zweiter Klick stoppt.
15. **Ton-Einstellungen sind nicht Teil des Konfigurations-Exports** (Ansagen sind lokale Dateien).
16. **Webhook-Kameras und Kameras ohne Lautsprecher** zeigen weder „Ton abspielen“ noch „Leertaste halten“; die Leiste enthält dann nur die Buttons des Nutzers (wie Phase 2).

## Offene Fragen

1. **Gong:** mitliefern (welche Datei?) oder weglassen wie geplant (Abweichung 1)?
2. **Wortlaut der beiden MP3s**: Der Plan setzt „Bin gleich da! Einen kleinen Moment, bitte.“ (Vorlage) und „Paket bitte abstellen.“ als Text der mitgelieferten Ansagen – stimmt das mit den Aufnahmen überein?
3. **Lautstärke** digital in der App (Abweichung 11) in Ordnung, oder soll die Kamera-Lautsprecher-Lautstärke gesetzt werden (API unbekannt)?
4. **Leertaste nur bei Zeiger über dem Popup** (Abweichung 5) in Ordnung? Alternative: nur Maus.
5. **Unterwegs (Phase 4):** Talkback geht per UDP direkt an die Kamera-IP; durch den App-Tunnel aus Phase 4 läuft (Stand Phase-4-Plan) nur TCP. Sollen Sprechen/Ansage unterwegs ausgeblendet werden, oder bekommt Phase 4 einen UDP-Weg?
6. **Ton-Einstellungen nicht im Export** (Abweichung 15) in Ordnung?

---

## File Structure

```
Packages/AppCore/Sources/AppCore/
  Talkback/TalkbackTarget.swift   TalkbackCodec, TalkbackError (deutsche Texte), TalkbackTarget.make (Prüfung der Sitzung)
  Talkback/ADTS.swift             7-Byte-ADTS-Kopf für AAC-LC
  Talkback/RTPPacketizer.swift    RTP für Opus (RFC 7587, PT 97, 48-kHz-Takt, wie ffmpeg)
  Talkback/RealtimePacer.swift    absolute Echtzeit-Taktung, Neuverankerung nach Stau
  Talkback/TalkbackEncoder.swift  PCM16 mono → AAC/Opus (AudioToolbox)
  Talkback/PCMResampler.swift     beliebiges PCM → PCM16 mono Kamera-Rate, Verstärkung, Begrenzung
  Talkback/PCMBufferCopy.swift    tiefe Kopie von AVAudioPCMBuffer
  Talkback/TalkbackStreamer.swift Kette + UDP (NWConnection) + Ereignisse
  Sound/Announcement.swift        Ansage (MP3/Text), Längen- und Namensregeln
  Sound/SoundSettings.swift       Reiter Ton: Ansagen, Mikrofon, Modus, Lautstärke; mitgelieferte Ansagen; tolerant
  Sound/AnnouncementAudio.swift   Datei laden, Dauer, macOS-Stimmen, Sprache → Puffer, CAF schreiben, Float-Format
Packages/AppCore/Tests/AppCoreTests/
  TalkbackFramingTests.swift, TalkbackEncoderTests.swift, TalkbackStreamerTests.swift, SoundSettingsTests.swift

Packages/ProtectKit/Sources/ProtectKit/
  TalkbackSession.swift (neu)     tolerante Antwort der Talkback-Sitzung
  ProtectClient.swift             + talkbackSession(cameraId:)
Packages/ProtectKit/Tests/ProtectKitTests/TalkbackSessionTests.swift (neu)

docs/design/einstellungen-ton.md  Phase-3-Fassung (bedienbar)
docs/design/popup.md              + Ton abspielen, Sprechen, Ansagen-Menü, Hinweis

UniFiCameraPopup/
  Info.plist                                  + NSMicrophoneUsageDescription
  Resources/Sounds/bin-gleich-da.mp3, paket-abstellen.mp3 (neu, Kopie aus der Spezifikation)
  Assets.xcassets/Icons/mic.imageset, soundPlay.imageset (neu)
  Services/TalkbackLog.swift (neu)            Diagnose-Log
  Services/SoundStore.swift (neu)             Ansagen speichern, Dateien, Sprache übernehmen
  Services/PreviewPlayer.swift (neu)          Probehören am Mac
  Services/MicrophoneCapture.swift (neu)      Geräte, Berechtigung, Aufnahme
  Services/PushToTalkKey.swift (neu)          Leertaste als Hotkey (gedrückt/losgelassen)
  Services/TalkbackService.swift (neu)        Ablauf Sprechen/Ansage, Zustand, Hinweise
  Services/GlobalHotkeyManager.swift          fremde Hotkey-Signaturen weiterreichen
  Views/Design/DesignComponents.swift         + TemplateIcon.mic/.soundPlay, VolumeSlider statt VolumeTrack
  Views/Settings/SoundTab.swift (neu)         Reiter Ton (bedienbar), SoundFilePicker
  Views/Settings/SoundAndRemoteTabs.swift     Gerüst SoundTab entfällt (RemoteTab bleibt)
  Views/Popup/PopupTalkViews.swift (neu)      Sprechen-Taste, Ansagen-Menü, Hinweis, PopupTalkControls
  Views/Popup/PopupOverlayViews.swift         PopupOverlayContent.talk, ActionPillView(leadingViews:)
  Views/PopupWindow.swift                     Talk-Steuerung einhängen, Auto-Schließen wartet
  Services/PopupController.swift              talk-Inhalt für Kameras mit Lautsprecher
  Services/WhatsNewService.swift              1.2.0-Eintrag ergänzt
  Views/HelpView.swift                        Tipp „Sprechen und Ansagen“ mit Lizenzhinweis
```

**pbxproj-IDs:** BuildFile `C31…0001`–`C31…0008` (Swift), `C31…0009`/`C31…0010` (MP3), FileRef `C32…` gleiche Endungen, Gruppe `C34…0001` (Sounds).

---

### Task 1: AppCore – Talkback-Ziel, ADTS, RTP und Echtzeit-Taktung

**Files:**
- Create: `Packages/AppCore/Sources/AppCore/Talkback/TalkbackTarget.swift`, `ADTS.swift`, `RTPPacketizer.swift`, `RealtimePacer.swift`
- Test: `Packages/AppCore/Tests/AppCoreTests/TalkbackFramingTests.swift`

**Interfaces:**
- Consumes: nichts.
- Produces:
  - `public enum TalkbackCodec: String, Codable, Sendable, CaseIterable { aac, opus, vorbis }` – `init?(wireValue: String)`, `var supportedSampleRates: Set<Int>`, `var defaultSampleRate: Int` (AAC 22 050, sonst 48 000)
  - `public enum TalkbackError: Error, Equatable, LocalizedError` – `noSpeaker`, `notConnected`, `unsupportedCodec(String)`, `unsupportedSampleRate(Int)`, `invalidAddress(String)`, `encoder(Int32)`, `network(String)`, `microphoneDenied`, `microphoneUnavailable`, `audioFile(String)`, `fileTooLong`, `speechFailed`
  - `public struct TalkbackTarget: Equatable, Sendable { host: String; port: UInt16; codec: TalkbackCodec; sampleRate: Int }` – `init(host:port:codec:sampleRate:)`, `static func make(host:port:codecName:sampleRate:) throws -> TalkbackTarget`
  - `public enum ADTS` – `headerLength = 7`, `maxFrameLength = 0x1FFF`, `frequencyIndex(for:) -> Int?`, `header(payloadLength:sampleRate:channels:) -> Data?`, `frame(_:sampleRate:channels:) -> Data?`
  - `public struct RTPPacketizer: Sendable` – `opusPayloadType = 97`, `opusClockRate = 48_000`, `headerLength = 12`, `init(payloadType:sequenceNumber:timestamp:ssrc:)`, `sequenceNumber`, `timestamp`, `ssrc`, `static func timestampIncrement(frames:sampleRate:) -> UInt32`, `mutating func packet(payload:timestampIncrement:) -> Data`
  - `public struct RealtimePacer: Sendable` – `init(sampleRate: Int, maxLag: TimeInterval = 0.25)`, `scheduledSamples`, `mutating func sendTime(forSamples:now:) -> TimeInterval`

- [ ] **Step 1: Failing tests schreiben**

`Packages/AppCore/Tests/AppCoreTests/TalkbackFramingTests.swift`:
```swift
import XCTest
@testable import AppCore

final class TalkbackFramingTests: XCTestCase {
    func testADTSHeaderBytes() throws {
        // 48 kHz (index 3), mono, 100 bytes payload → frame length 107.
        let header = try XCTUnwrap(ADTS.header(payloadLength: 100, sampleRate: 48_000))
        XCTAssertEqual([UInt8](header), [0xFF, 0xF1, 0x4C, 0x40, 0x0D, 0x7F, 0xFC])
        // 22 050 Hz (index 7), 300 bytes → 307 = 0b1_0011_0011.
        let other = try XCTUnwrap(ADTS.header(payloadLength: 300, sampleRate: 22_050))
        XCTAssertEqual([UInt8](other), [0xFF, 0xF1, 0x5C, 0x40, 0x26, 0x7F, 0xFC])
    }

    func testADTSRejectsUnsupportedInput() {
        XCTAssertNil(ADTS.header(payloadLength: 10, sampleRate: 44_000))
        XCTAssertNil(ADTS.header(payloadLength: 8_185, sampleRate: 48_000))
        XCTAssertNil(ADTS.header(payloadLength: -1, sampleRate: 48_000))
        XCTAssertNotNil(ADTS.header(payloadLength: 8_184, sampleRate: 48_000))
        XCTAssertEqual(ADTS.frame(Data([1, 2, 3]), sampleRate: 16_000)?.count, 10)
    }

    func testRTPHeaderLayout() {
        var rtp = RTPPacketizer(sequenceNumber: 0x1234, timestamp: 0x0102_0304, ssrc: 0xA1B2_C3D4)
        let packet = rtp.packet(payload: Data([0xAA, 0xBB]), timestampIncrement: 960)
        XCTAssertEqual([UInt8](packet), [0x80, 0xE1, 0x12, 0x34, 0x01, 0x02, 0x03, 0x04, 0xA1, 0xB2, 0xC3, 0xD4, 0xAA, 0xBB])
        XCTAssertEqual(rtp.sequenceNumber, 0x1235)
        XCTAssertEqual(rtp.timestamp, 0x0102_0304 + 960)
    }

    func testRTPWrapsSequenceAndTimestamp() {
        var rtp = RTPPacketizer(sequenceNumber: .max, timestamp: .max - 100, ssrc: 1)
        _ = rtp.packet(payload: Data(), timestampIncrement: 960)
        XCTAssertEqual(rtp.sequenceNumber, 0)
        XCTAssertEqual(rtp.timestamp, 859)
    }

    func testOpusTimestampUses48kClock() {
        XCTAssertEqual(RTPPacketizer.timestampIncrement(frames: 960, sampleRate: 48_000), 960)
        XCTAssertEqual(RTPPacketizer.timestampIncrement(frames: 320, sampleRate: 16_000), 960)
    }

    func testPacerKeepsAbsoluteSchedule() {
        var pacer = RealtimePacer(sampleRate: 48_000)
        XCTAssertEqual(pacer.sendTime(forSamples: 960, now: 100), 100, accuracy: 1e-9)
        XCTAssertEqual(pacer.sendTime(forSamples: 960, now: 100), 100.02, accuracy: 1e-9)
        XCTAssertEqual(pacer.sendTime(forSamples: 960, now: 100.001), 100.04, accuracy: 1e-9)
        // Slightly late: send now, keep the schedule.
        XCTAssertEqual(pacer.sendTime(forSamples: 960, now: 100.1), 100.1, accuracy: 1e-9)
        XCTAssertEqual(pacer.sendTime(forSamples: 960, now: 100.1), 100.1, accuracy: 1e-9)
    }

    func testPacerReanchorsAfterStall() {
        var pacer = RealtimePacer(sampleRate: 48_000, maxLag: 0.25)
        _ = pacer.sendTime(forSamples: 960, now: 0)
        // Source stalled for a second: no burst afterwards.
        XCTAssertEqual(pacer.sendTime(forSamples: 960, now: 1.0), 1.0, accuracy: 1e-9)
        XCTAssertEqual(pacer.sendTime(forSamples: 960, now: 1.0), 1.02, accuracy: 1e-9)
    }

    func testTargetValidation() throws {
        let aac = try TalkbackTarget.make(host: " 192.168.1.20 ", port: 7004, codecName: "AAC", sampleRate: 0)
        XCTAssertEqual(aac, TalkbackTarget(host: "192.168.1.20", port: 7004, codec: .aac, sampleRate: 22_050))
        let opus = try TalkbackTarget.make(host: "cam", port: 7004, codecName: "libopus", sampleRate: 16_000)
        XCTAssertEqual(opus.codec, .opus)
        XCTAssertEqual(opus.sampleRate, 16_000)
        XCTAssertThrowsError(try TalkbackTarget.make(host: "cam", port: 7004, codecName: "vorbis", sampleRate: 48_000)) {
            XCTAssertEqual($0 as? TalkbackError, .unsupportedCodec("vorbis"))
        }
        XCTAssertThrowsError(try TalkbackTarget.make(host: "cam", port: 7004, codecName: "", sampleRate: 48_000)) {
            XCTAssertEqual($0 as? TalkbackError, .unsupportedCodec("unbekannt"))
        }
        XCTAssertThrowsError(try TalkbackTarget.make(host: "", port: 7004, codecName: "opus", sampleRate: 48_000)) {
            XCTAssertEqual($0 as? TalkbackError, .invalidAddress("leer"))
        }
        XCTAssertThrowsError(try TalkbackTarget.make(host: "cam", port: 7004, codecName: "opus", sampleRate: 44_100)) {
            XCTAssertEqual($0 as? TalkbackError, .unsupportedSampleRate(44_100))
        }
    }
}
```

- [ ] **Step 2: Tests laufen lassen, Fehlschlag prüfen**

Run: `(cd Packages/AppCore && swift test --filter TalkbackFramingTests 2>&1 | grep -E "error:" | head -3)`
Expected: Kompilierfehler `cannot find 'ADTS' in scope` (bzw. `TalkbackTarget`, `RTPPacketizer`, `RealtimePacer`).

- [ ] **Step 3: Implementierung schreiben**

`Packages/AppCore/Sources/AppCore/Talkback/TalkbackTarget.swift`:
```swift
import Foundation

/// Audio formats a camera may ask for in its talkback session.
public enum TalkbackCodec: String, Codable, Sendable, CaseIterable {
    case aac
    case opus
    case vorbis

    /// Tolerant mapping of the API's codec name ("aac", "AAC", "libopus", " opus ").
    public init?(wireValue: String) {
        let value = wireValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.contains("opus") {
            self = .opus
        } else if value.contains("aac") {
            self = .aac
        } else if value.contains("vorbis") {
            self = .vorbis
        } else {
            return nil
        }
    }

    /// Rates the system encoders accept (AAC: MPEG-4 rates up to 48 kHz, Opus: its five rates).
    public var supportedSampleRates: Set<Int> {
        switch self {
        case .aac: return [8_000, 11_025, 12_000, 16_000, 22_050, 24_000, 32_000, 44_100, 48_000]
        case .opus: return [8_000, 12_000, 16_000, 24_000, 48_000]
        case .vorbis: return []
        }
    }

    /// Used when the session names no (or a nonsensical) sampling rate.
    public var defaultSampleRate: Int {
        switch self {
        case .aac: return 22_050
        case .opus, .vorbis: return 48_000
        }
    }
}

/// Why talking to a camera did not work. Texts are shown in the popup.
public enum TalkbackError: Error, Equatable, LocalizedError {
    case noSpeaker
    case notConnected
    case unsupportedCodec(String)
    case unsupportedSampleRate(Int)
    case invalidAddress(String)
    case encoder(Int32)
    case network(String)
    case microphoneDenied
    case microphoneUnavailable
    case audioFile(String)
    case fileTooLong
    case speechFailed

    public var errorDescription: String? {
        switch self {
        case .noSpeaker:
            return "Diese Kamera hat keinen Lautsprecher."
        case .notConnected:
            return "Keine Verbindung zu UniFi Protect."
        case .unsupportedCodec(let name):
            return "Die Kamera verlangt das Tonformat „\(name)“ – das kann die App nicht senden."
        case .unsupportedSampleRate(let rate):
            return "Die Kamera verlangt \(rate) Hz – das kann die App nicht senden."
        case .invalidAddress(let raw):
            return "Die Kamera nannte keine gültige Adresse für den Ton („\(raw)“)."
        case .encoder(let status):
            return "Der Ton konnte nicht kodiert werden (Fehler \(status))."
        case .network(let detail):
            return "Senden an die Kamera fehlgeschlagen (\(detail))."
        case .microphoneDenied:
            return "Kein Zugriff aufs Mikrofon. Erlaube ihn unter Systemeinstellungen › Datenschutz & Sicherheit › Mikrofon."
        case .microphoneUnavailable:
            return "Kein Mikrofon gefunden."
        case .audioFile(let detail):
            return "Die Ansage konnte nicht gelesen werden (\(detail))."
        case .fileTooLong:
            return "Die Datei ist länger als 5 Minuten."
        case .speechFailed:
            return "Die Stimme hat keinen Ton erzeugt."
        }
    }
}

/// Where and how talkback audio goes: UDP to the camera, mono, in the camera's codec.
public struct TalkbackTarget: Equatable, Sendable {
    public let host: String
    public let port: UInt16
    public let codec: TalkbackCodec
    public let sampleRate: Int

    public init(host: String, port: UInt16, codec: TalkbackCodec, sampleRate: Int) {
        self.host = host
        self.port = port
        self.codec = codec
        self.sampleRate = sampleRate
    }

    /// Validates what the talkback session returned. Vorbis (Ogg) is not sent by the app.
    public static func make(host: String, port: UInt16, codecName: String, sampleRate: Int) throws -> TalkbackTarget {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty, port > 0 else {
            throw TalkbackError.invalidAddress(trimmedHost.isEmpty ? "leer" : "\(trimmedHost):\(port)")
        }
        guard let codec = TalkbackCodec(wireValue: codecName), codec != .vorbis else {
            throw TalkbackError.unsupportedCodec(codecName.isEmpty ? "unbekannt" : codecName)
        }
        let rate = sampleRate > 0 ? sampleRate : codec.defaultSampleRate
        guard codec.supportedSampleRates.contains(rate) else { throw TalkbackError.unsupportedSampleRate(rate) }
        return TalkbackTarget(host: trimmedHost, port: port, codec: codec, sampleRate: rate)
    }
}
```

`Packages/AppCore/Sources/AppCore/Talkback/ADTS.swift`:
```swift
import Foundation

/// ADTS framing for raw AAC-LC packets (ISO/IEC 13818-7), as ffmpeg's "adts" muxer writes it:
/// 7-byte header without CRC, one frame per UDP datagram.
public enum ADTS {
    public static let headerLength = 7
    /// 13-bit frame_length field.
    public static let maxFrameLength = 0x1FFF

    private static let rates = [96_000, 88_200, 64_000, 48_000, 44_100, 32_000, 24_000,
                                22_050, 16_000, 12_000, 11_025, 8_000, 7_350]

    public static func frequencyIndex(for sampleRate: Int) -> Int? {
        rates.firstIndex(of: sampleRate)
    }

    /// nil for an unsupported rate, a channel count outside 1…7 or a frame longer than 8191 bytes.
    public static func header(payloadLength: Int, sampleRate: Int, channels: Int = 1) -> Data? {
        guard let index = frequencyIndex(for: sampleRate), (1...7).contains(channels) else { return nil }
        let length = payloadLength + headerLength
        guard payloadLength >= 0, length <= maxFrameLength else { return nil }
        let profile = 1 // AAC LC (audio object type 2) − 1
        return Data([
            0xFF,
            0xF1, // MPEG-4, layer 0, protection absent
            UInt8((profile << 6) | (index << 2) | (channels >> 2)),
            UInt8(((channels & 0x3) << 6) | (length >> 11)),
            UInt8((length >> 3) & 0xFF),
            UInt8(((length & 0x7) << 5) | 0x1F), // buffer fullness 0x7FF (VBR) …
            0xFC, // … continued, one raw data block
        ])
    }

    public static func frame(_ payload: Data, sampleRate: Int, channels: Int = 1) -> Data? {
        guard var frame = header(payloadLength: payload.count, sampleRate: sampleRate, channels: channels) else { return nil }
        frame.append(payload)
        return frame
    }
}
```

`Packages/AppCore/Sources/AppCore/Talkback/RTPPacketizer.swift`:
```swift
import Foundation

/// RTP for Opus (RFC 7587), matching ffmpeg's RTP muxer: one Opus packet per RTP packet,
/// dynamic payload type 97, 48 kHz timestamp clock, marker bit set, random start values.
public struct RTPPacketizer: Sendable {
    public static let opusPayloadType: UInt8 = 97
    /// RFC 7587: the RTP clock of Opus is always 48 kHz, whatever the encoder rate.
    public static let opusClockRate = 48_000
    public static let headerLength = 12

    public let payloadType: UInt8
    public let ssrc: UInt32
    public private(set) var sequenceNumber: UInt16
    public private(set) var timestamp: UInt32

    public init(
        payloadType: UInt8 = RTPPacketizer.opusPayloadType,
        sequenceNumber: UInt16 = .random(in: 0...UInt16.max),
        timestamp: UInt32 = .random(in: 0...UInt32.max),
        ssrc: UInt32 = .random(in: 0...UInt32.max)
    ) {
        self.payloadType = payloadType & 0x7F
        self.sequenceNumber = sequenceNumber
        self.timestamp = timestamp
        self.ssrc = ssrc
    }

    /// Timestamp increment of a packet with `frames` samples at `sampleRate`.
    public static func timestampIncrement(frames: Int, sampleRate: Int) -> UInt32 {
        UInt32(frames * opusClockRate / max(sampleRate, 1))
    }

    /// Builds the next packet and advances sequence number and timestamp (both wrap).
    public mutating func packet(payload: Data, timestampIncrement: UInt32) -> Data {
        var data = Data(capacity: Self.headerLength + payload.count)
        data.append(0x80) // version 2, no padding, no extension, no CSRC
        data.append(0x80 | payloadType) // marker + payload type
        data.append(UInt8(sequenceNumber >> 8))
        data.append(UInt8(sequenceNumber & 0xFF))
        for shift in stride(from: 24, through: 0, by: -8) {
            data.append(UInt8((timestamp >> UInt32(shift)) & 0xFF))
        }
        for shift in stride(from: 24, through: 0, by: -8) {
            data.append(UInt8((ssrc >> UInt32(shift)) & 0xFF))
        }
        data.append(payload)
        sequenceNumber &+= 1
        timestamp &+= timestampIncrement
        return data
    }
}
```

`Packages/AppCore/Sources/AppCore/Talkback/RealtimePacer.swift`:
```swift
import Foundation

/// Real-time pacing like uiprotect's TalkbackStream: packet n leaves at
/// start + samplesBefore / rate (absolute schedule, no drift). UDP has no flow control,
/// so sending faster than real time floods the camera. When the source falls behind by more
/// than `maxLag` (a stalled microphone), the schedule is re-anchored instead of bursting.
public struct RealtimePacer: Sendable {
    public let sampleRate: Double
    public let maxLag: TimeInterval
    public private(set) var scheduledSamples = 0
    private var anchor: TimeInterval?

    public init(sampleRate: Int, maxLag: TimeInterval = 0.25) {
        self.sampleRate = Double(max(sampleRate, 1))
        self.maxLag = maxLag
    }

    /// When the next packet (holding `samples` samples) should be sent; never earlier than `now`.
    public mutating func sendTime(forSamples samples: Int, now: TimeInterval) -> TimeInterval {
        let start = anchor ?? now
        anchor = start
        var due = start + Double(scheduledSamples) / sampleRate
        if due < now - maxLag {
            anchor = now - Double(scheduledSamples) / sampleRate
            due = now
        }
        scheduledSamples += samples
        return max(due, now)
    }
}
```

- [ ] **Step 4: Tests laufen lassen**

Run: `(cd Packages/AppCore && swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -2)`
Expected: `Executed … tests, with 0 failures` (8 neue Tests in `TalkbackFramingTests`).

- [ ] **Step 5: Build und Commit**

Run: Build-Befehl → `** BUILD SUCCEEDED **` (die App bindet `AppCore` schon ein; nichts ist im Projekt zu ändern).
```bash
git add Packages/AppCore/Sources/AppCore/Talkback Packages/AppCore/Tests/AppCoreTests/TalkbackFramingTests.swift
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "feat(talkback): session target validation, ADTS and RTP framing, real-time pacer" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: AppCore – Kodierer (AudioToolbox), Umrechnung und UDP-Sender

**Files:**
- Create: `Packages/AppCore/Sources/AppCore/Talkback/TalkbackEncoder.swift`, `PCMResampler.swift`, `PCMBufferCopy.swift`, `TalkbackStreamer.swift`
- Test: `Packages/AppCore/Tests/AppCoreTests/TalkbackEncoderTests.swift`, `TalkbackStreamerTests.swift`

**Interfaces:**
- Consumes: `TalkbackCodec.supportedSampleRates`, `TalkbackError`, `TalkbackTarget`, `ADTS.frame`, `RTPPacketizer`, `RealtimePacer` (Task 1).
- Produces:
  - `public struct EncodedPacket: Equatable, Sendable { data: Data; frames: Int }`
  - `public final class TalkbackEncoder` – `init(codec:sampleRate:) throws`, `codec`, `sampleRate`, `framesPerPacket` (AAC 1024, Opus Rate/50), `func encode(_ samples: [Int16]) throws -> [EncodedPacket]`
  - `public final class PCMResampler` – `init(sampleRate: Int, gain: Float = 1)`, `outputFormat`, `gain`, `func convert(_ buffer: AVAudioPCMBuffer) throws -> [Int16]`, `func silence(seconds: Double) -> [Int16]`
  - `extension AVAudioPCMBuffer { func deepCopy() -> AVAudioPCMBuffer? }` (intern)
  - `public final class TalkbackStreamer: @unchecked Sendable` – `enum Event: Equatable, Sendable { ready, finished(packets: Int), failed(String) }`, `init(target:gain:log:onEvent:) throws`, `target`, `start()`, `append(_ buffer: AVAudioPCMBuffer)` (thread-sicher, kopiert), `finish()` (0,3 s Stille, dann `.finished`), `stop()` (sofort, kein Ereignis)

- [ ] **Step 1: Failing tests schreiben**

`Packages/AppCore/Tests/AppCoreTests/TalkbackEncoderTests.swift`:
```swift
import AVFoundation
import XCTest
@testable import AppCore

final class TalkbackEncoderTests: XCTestCase {
    static func sine(seconds: Double, rate: Int, frequency: Double = 440) -> [Int16] {
        (0..<Int(seconds * Double(rate))).map { index in
            Int16(12_000 * sin(2 * .pi * frequency * Double(index) / Double(rate)))
        }
    }

    func testOpusMakes20msPackets() throws {
        let encoder = try TalkbackEncoder(codec: .opus, sampleRate: 48_000)
        XCTAssertEqual(encoder.framesPerPacket, 960)
        var packets: [EncodedPacket] = []
        // Fed in uneven chunks like a microphone tap.
        let samples = Self.sine(seconds: 1, rate: 48_000)
        for start in stride(from: 0, to: samples.count, by: 1_234) {
            packets += try encoder.encode(Array(samples[start..<min(start + 1_234, samples.count)]))
        }
        XCTAssertGreaterThanOrEqual(packets.count, 48)
        XCTAssertLessThanOrEqual(packets.count, 50)
        XCTAssertTrue(packets.allSatisfy { !$0.data.isEmpty && $0.data.count < 1_400 && $0.frames == 960 })
    }

    func testAACProducesDecodableADTS() throws {
        let rate = 22_050
        let encoder = try TalkbackEncoder(codec: .aac, sampleRate: rate)
        XCTAssertEqual(encoder.framesPerPacket, 1_024)
        let packets = try encoder.encode(Self.sine(seconds: 1, rate: rate))
        XCTAssertGreaterThanOrEqual(packets.count, 18)
        var stream = Data()
        for packet in packets {
            stream.append(try XCTUnwrap(ADTS.frame(packet.data, sampleRate: rate)))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("talkback-\(UUID().uuidString).aac")
        defer { try? FileManager.default.removeItem(at: url) }
        try stream.write(to: url)
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.fileFormat.sampleRate, Double(rate))
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertGreaterThan(Double(file.length) / Double(rate), 0.7)
    }

    func testRejectsVorbisAndOddRates() {
        XCTAssertThrowsError(try TalkbackEncoder(codec: .vorbis, sampleRate: 48_000))
        XCTAssertThrowsError(try TalkbackEncoder(codec: .opus, sampleRate: 44_100))
        XCTAssertThrowsError(try TalkbackEncoder(codec: .aac, sampleRate: 7_000))
    }

    func testResamplerDownmixesAndAppliesGain() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800)!
        buffer.frameLength = 4_800
        for channel in 0..<2 {
            for index in 0..<4_800 { buffer.floatChannelData![channel][index] = 0.9 }
        }
        let loud = try PCMResampler(sampleRate: 16_000, gain: 1.5).convert(buffer)
        // The sample-rate converter keeps a little back for the next buffer.
        XCTAssertGreaterThan(loud.count, 1_200)
        XCTAssertLessThanOrEqual(loud.count, 1_600)
        // 0.9 × 1.5 clips at full scale instead of wrapping around.
        XCTAssertEqual(loud[800], 32_767)
        XCTAssertEqual(PCMResampler(sampleRate: 16_000).silence(seconds: 0.3).count, 4_800)
    }
}
```

`Packages/AppCore/Tests/AppCoreTests/TalkbackStreamerTests.swift` (ein UDP-Empfänger auf 127.0.0.1 spielt die Kamera):
```swift
import AVFoundation
import Network
import XCTest
@testable import AppCore

/// Receives UDP datagrams on 127.0.0.1 like a camera speaker would.
final class UDPSink: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "udp-sink")
    private let lock = NSLock()
    private var datagrams: [(Data, TimeInterval)] = []
    private var connections: [NWConnection] = []

    init() throws {
        let parameters = NWParameters.udp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            let once = OnceFlag()
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    if once.claim() { continuation.resume(returning: listener.port?.rawValue ?? 0) }
                case .failed(let error):
                    if once.claim() { continuation.resume(throwing: error) }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                self.lock.withLock { self.connections.append(connection) }
                connection.start(queue: self.queue)
                self.receive(on: connection)
            }
            listener.start(queue: queue)
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data {
                let now = Double(DispatchTime.now().uptimeNanoseconds) / 1e9
                self.lock.withLock { self.datagrams.append((data, now)) }
            }
            if error == nil { self.receive(on: connection) }
        }
    }

    var received: [(Data, TimeInterval)] { lock.withLock { datagrams } }

    func stop() {
        listener.cancel()
        lock.withLock { connections.forEach { $0.cancel() } }
    }
}

final class TalkbackStreamerTests: XCTestCase {
    private func sineBuffer(seconds: Double, rate: Double = 44_100) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let frames = AVAudioFrameCount(seconds * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for index in 0..<Int(frames) {
            buffer.floatChannelData![0][index] = Float(0.4 * sin(2 * .pi * 440 * Double(index) / rate))
        }
        return buffer
    }

    private func stream(codec: TalkbackCodec, rate: Int, seconds: Double) async throws -> (packets: [(Data, TimeInterval)], event: TalkbackStreamer.Event) {
        let sink = try UDPSink()
        let port = try await sink.start()
        defer { sink.stop() }
        let finished = expectation(description: "finished")
        let box = EventBox()
        let streamer = try TalkbackStreamer(
            target: TalkbackTarget(host: "127.0.0.1", port: port, codec: codec, sampleRate: rate)
        ) { event in
            guard event != .ready, box.set(event) else { return }
            finished.fulfill()
        }
        streamer.start()
        streamer.append(sineBuffer(seconds: seconds))
        streamer.finish()
        await fulfillment(of: [finished], timeout: seconds + 5)
        try await Task.sleep(nanoseconds: 300_000_000)
        return (sink.received, try XCTUnwrap(box.value))
    }

    func testOpusIsSentAsPacedRTP() async throws {
        let result = try await stream(codec: .opus, rate: 48_000, seconds: 1)
        guard case .finished(let count) = result.event else { return XCTFail("\(result.event)") }
        XCTAssertGreaterThanOrEqual(result.packets.count, 50)
        XCTAssertEqual(result.packets.count, count)
        let first = [UInt8](result.packets[0].0)
        XCTAssertEqual(first[0], 0x80)
        XCTAssertEqual(first[1], 0xE1)
        let sequences = result.packets.map { UInt16($0.0[2]) << 8 | UInt16($0.0[3]) }
        for (a, b) in zip(sequences, sequences.dropFirst()) { XCTAssertEqual(b, a &+ 1) }
        // Real time: 1.3 s of audio (incl. 0.3 s flush) must not arrive in a burst.
        let span = result.packets.last!.1 - result.packets.first!.1
        XCTAssertGreaterThan(span, 1.1)
        XCTAssertLessThan(span, 1.6)
    }

    func testAACIsSentAsADTSFrames() async throws {
        let result = try await stream(codec: .aac, rate: 16_000, seconds: 0.5)
        guard case .finished = result.event else { return XCTFail("\(result.event)") }
        XCTAssertGreaterThan(result.packets.count, 8)
        for (datagram, _) in result.packets {
            XCTAssertEqual(datagram[0], 0xFF)
            XCTAssertEqual(datagram[1], 0xF1)
            let length = (Int(datagram[3] & 0x03) << 11) | (Int(datagram[4]) << 3) | (Int(datagram[5]) >> 5)
            XCTAssertEqual(length, datagram.count)
        }
    }

    func testStopDropsPendingPackets() async throws {
        let sink = try UDPSink()
        let port = try await sink.start()
        defer { sink.stop() }
        let streamer = try TalkbackStreamer(
            target: TalkbackTarget(host: "127.0.0.1", port: port, codec: .opus, sampleRate: 48_000)
        ) { _ in }
        streamer.start()
        streamer.append(sineBuffer(seconds: 3))
        try await Task.sleep(nanoseconds: 500_000_000)
        streamer.stop()
        try await Task.sleep(nanoseconds: 500_000_000)
        let afterStop = sink.received.count
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(sink.received.count, afterStop)
        XCTAssertLessThan(afterStop, 60)
    }
}

final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: TalkbackStreamer.Event?
    var value: TalkbackStreamer.Event? { lock.withLock { stored } }
    /// true only for the first event.
    func set(_ event: TalkbackStreamer.Event) -> Bool {
        lock.withLock {
            guard stored == nil else { return false }
            stored = event
            return true
        }
    }
}

final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func claim() -> Bool {
        lock.withLock {
            guard !used else { return false }
            used = true
            return true
        }
    }
}
```

- [ ] **Step 2: Tests laufen lassen, Fehlschlag prüfen**

Run: `(cd Packages/AppCore && swift test --filter "TalkbackEncoderTests|TalkbackStreamerTests" 2>&1 | grep -E "error:" | head -3)`
Expected: Kompilierfehler `cannot find 'TalkbackEncoder' in scope` (bzw. `PCMResampler`, `TalkbackStreamer`).

- [ ] **Step 3: Implementierung schreiben**

`Packages/AppCore/Sources/AppCore/Talkback/TalkbackEncoder.swift` – das Eingabe-Callback gibt höchstens so viele Samples ab, wie der Konverter verlangt, und hält den übergebenen Speicher bis zum nächsten Callback (Vorgabe von AudioToolbox); `needMoreInput` beendet eine Runde, ohne den Strom zu beenden:
```swift
import AudioToolbox
import Foundation

/// One compressed packet and how many PCM samples (at the encoder rate) it carries.
public struct EncodedPacket: Equatable, Sendable {
    public let data: Data
    public let frames: Int
}

/// 16-bit mono PCM → AAC-LC (raw, for ADTS) or Opus with the system encoders (AudioToolbox).
/// Not thread-safe: use from one queue.
public final class TalkbackEncoder {
    public let codec: TalkbackCodec
    public let sampleRate: Int
    /// Samples per packet: AAC 1024, Opus 20 ms.
    public let framesPerPacket: Int

    private var converter: AudioConverterRef?
    private var pending: [Int16] = []
    /// Memory handed to the converter must stay valid until its next input callback.
    private var supplied: UnsafeMutablePointer<Int16>?
    private var suppliedCapacity = 0
    private let maxPacketSize: Int
    private let outputBuffer: UnsafeMutableRawPointer

    /// Returned from the input callback when all pending samples are used up.
    private static let needMoreInput: OSStatus = 0x6E6D6F72 // 'nmor'

    public init(codec: TalkbackCodec, sampleRate: Int) throws {
        guard codec != .vorbis else { throw TalkbackError.unsupportedCodec(codec.rawValue) }
        guard codec.supportedSampleRates.contains(sampleRate) else { throw TalkbackError.unsupportedSampleRate(sampleRate) }
        self.codec = codec
        self.sampleRate = sampleRate

        var input = AudioStreamBasicDescription(
            mSampleRate: Double(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var output = AudioStreamBasicDescription()
        output.mSampleRate = Double(sampleRate)
        output.mChannelsPerFrame = 1
        switch codec {
        case .aac:
            output.mFormatID = kAudioFormatMPEG4AAC
            output.mFormatFlags = UInt32(MPEG4ObjectID.AAC_LC.rawValue)
            output.mFramesPerPacket = 1024
        case .opus, .vorbis:
            output.mFormatID = kAudioFormatOpus
            output.mFramesPerPacket = UInt32(sampleRate / 50)
        }

        var created: AudioConverterRef?
        let status = AudioConverterNew(&input, &output, &created)
        guard status == noErr, let created else { throw TalkbackError.encoder(status) }
        converter = created

        // What the encoder actually uses (it may round the packet size).
        var actual = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        if AudioConverterGetProperty(created, kAudioConverterCurrentOutputStreamDescription, &size, &actual) == noErr,
           actual.mFramesPerPacket > 0 {
            framesPerPacket = Int(actual.mFramesPerPacket)
        } else {
            framesPerPacket = Int(output.mFramesPerPacket)
        }

        var maxSize: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioConverterGetProperty(created, kAudioConverterPropertyMaximumOutputPacketSize, &size, &maxSize) != noErr || maxSize == 0 {
            maxSize = 8_192
        }
        maxPacketSize = Int(maxSize)
        outputBuffer = UnsafeMutableRawPointer.allocate(byteCount: Int(maxSize), alignment: 16)
    }

    deinit {
        if let converter { AudioConverterDispose(converter) }
        supplied?.deallocate()
        outputBuffer.deallocate()
    }

    /// Feeds samples, returns every packet that is complete now (may be none: encoder delay).
    public func encode(_ samples: [Int16]) throws -> [EncodedPacket] {
        pending.append(contentsOf: samples)
        guard let converter else { return [] }
        var packets: [EncodedPacket] = []
        while true {
            var packetCount: UInt32 = 1
            var description = AudioStreamPacketDescription()
            var bufferList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(maxPacketSize), mData: outputBuffer)
            )
            let status = AudioConverterFillComplexBuffer(
                converter,
                { _, ioPackets, ioData, _, userData -> OSStatus in
                    let encoder = Unmanaged<TalkbackEncoder>.fromOpaque(userData!).takeUnretainedValue()
                    return encoder.supply(ioPackets, ioData)
                },
                Unmanaged.passUnretained(self).toOpaque(),
                &packetCount,
                &bufferList,
                &description
            )
            if packetCount > 0 {
                let byteCount = Int(bufferList.mBuffers.mDataByteSize)
                let offset = Int(description.mStartOffset)
                let length = description.mDataByteSize > 0 ? Int(description.mDataByteSize) : byteCount
                if length > 0 {
                    packets.append(EncodedPacket(
                        data: Data(bytes: outputBuffer.advanced(by: offset), count: length),
                        frames: framesPerPacket
                    ))
                }
            }
            if status == Self.needMoreInput || packetCount == 0 { break }
            guard status == noErr else { throw TalkbackError.encoder(status) }
        }
        return packets
    }

    /// Input callback: hands over as many pending samples as the converter asks for.
    private func supply(
        _ ioPackets: UnsafeMutablePointer<UInt32>,
        _ ioData: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        guard !pending.isEmpty else {
            ioPackets.pointee = 0
            ioData.pointee.mBuffers.mDataByteSize = 0
            return Self.needMoreInput
        }
        let requested = Int(ioPackets.pointee)
        let count = requested > 0 ? min(requested, pending.count) : pending.count
        if suppliedCapacity < count {
            supplied?.deallocate()
            supplied = UnsafeMutablePointer<Int16>.allocate(capacity: count)
            suppliedCapacity = count
        }
        pending.withUnsafeBufferPointer { source in
            supplied!.update(from: source.baseAddress!, count: count)
        }
        pending.removeFirst(count)
        ioPackets.pointee = UInt32(count)
        ioData.pointee.mNumberBuffers = 1
        ioData.pointee.mBuffers.mNumberChannels = 1
        ioData.pointee.mBuffers.mDataByteSize = UInt32(count * 2)
        ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(supplied!)
        return noErr
    }
}
```

`Packages/AppCore/Sources/AppCore/Talkback/PCMResampler.swift`:
```swift
import AVFoundation

/// Any PCM buffer (mic, file, speech) → 16-bit mono at the camera rate, with gain and clipping.
/// Not thread-safe: use from one queue.
public final class PCMResampler {
    public let outputFormat: AVAudioFormat
    public let gain: Float
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    public init(sampleRate: Int, gain: Float = 1) {
        outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(sampleRate), channels: 1, interleaved: true)!
        self.gain = max(0, gain)
    }

    public func convert(_ buffer: AVAudioPCMBuffer) throws -> [Int16] {
        guard buffer.frameLength > 0 else { return [] }
        if converter == nil || inputFormat != buffer.format {
            guard let made = AVAudioConverter(from: buffer.format, to: outputFormat) else {
                throw TalkbackError.audioFile("Format \(buffer.format.sampleRate) Hz, \(buffer.format.channelCount) Kanäle")
            }
            made.downmix = true
            converter = made
            inputFormat = buffer.format
        }
        guard let converter else { return [] }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return [] }
        var handedOver = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if handedOver {
                inputStatus.pointee = .noDataNow
                return nil
            }
            handedOver = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status == .error {
            throw TalkbackError.audioFile(error?.localizedDescription ?? "Umwandlung")
        }
        guard let channel = output.int16ChannelData?[0] else { return [] }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        guard gain != 1 else { return samples }
        return samples.map { sample in
            let scaled = Float(sample) * gain
            return Int16(max(-32_768, min(32_767, scaled.rounded())))
        }
    }

    /// `seconds` of silence in the output format (pushes encoder and resampler delay out).
    public func silence(seconds: Double) -> [Int16] {
        [Int16](repeating: 0, count: Int(outputFormat.sampleRate * seconds))
    }
}
```

`Packages/AppCore/Sources/AppCore/Talkback/PCMBufferCopy.swift`:
```swift
import AVFoundation

extension AVAudioPCMBuffer {
    /// Independent copy (tap and synthesizer buffers are reused after their callback returns).
    func deepCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(frameLength, 1)) else { return nil }
        copy.frameLength = frameLength
        let bytes = Int(frameLength) * Int(format.streamDescription.pointee.mBytesPerFrame)
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBufferList))
        let target = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (from, to) in zip(source, target) {
            guard let src = from.mData, let dst = to.mData else { continue }
            memcpy(dst, src, min(bytes, Int(from.mDataByteSize), Int(to.mDataByteSize)))
        }
        return copy
    }
}
```

`Packages/AppCore/Sources/AppCore/Talkback/TalkbackStreamer.swift` – ein Datagramm je ADTS-Rahmen bzw. RTP-Paket (so schreibt es ffmpeg in der Referenz auf `udp://`/`rtp://`); kein RTCP:
```swift
import AVFoundation
import Foundation
import Network

/// Sends audio to a camera speaker: PCM → resample → AAC (ADTS) or Opus (RTP) → UDP,
/// paced in real time. Thread-safe; all work happens on one private queue.
public final class TalkbackStreamer: @unchecked Sendable {
    public enum Event: Equatable, Sendable {
        /// UDP path is up (first packet can leave).
        case ready
        /// Every packet was sent after `finish()`.
        case finished(packets: Int)
        case failed(String)
    }

    public let target: TalkbackTarget
    private let queue = DispatchQueue(label: "com.snackbits.UniFiCameraPopup.talkback", qos: .userInteractive)
    private let connection: NWConnection
    private let encoder: TalkbackEncoder
    private let resampler: PCMResampler
    private var packetizer = RTPPacketizer()
    private var pacer: RealtimePacer
    private let onEvent: @Sendable (Event) -> Void
    private let log: @Sendable (String) -> Void
    private var stopped = false
    private var finishing = false
    private var outstanding = 0
    private var sent = 0
    private var reportedFirstPacket = false

    /// Throws for codecs or rates the encoder cannot produce.
    public init(
        target: TalkbackTarget,
        gain: Float = 1,
        log: @escaping @Sendable (String) -> Void = { _ in },
        onEvent: @escaping @Sendable (Event) -> Void
    ) throws {
        guard let port = NWEndpoint.Port(rawValue: target.port) else {
            throw TalkbackError.invalidAddress("\(target.host):\(target.port)")
        }
        self.target = target
        encoder = try TalkbackEncoder(codec: target.codec, sampleRate: target.sampleRate)
        resampler = PCMResampler(sampleRate: target.sampleRate, gain: gain)
        pacer = RealtimePacer(sampleRate: target.sampleRate)
        let host = target.host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .udp)
        self.onEvent = onEvent
        self.log = log
    }

    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.log("Talkback: UDP bereit → \(self.target.host):\(self.target.port) \(self.target.codec.rawValue) \(self.target.sampleRate) Hz, \(self.encoder.framesPerPacket) Samples/Paket")
                self.onEvent(.ready)
            case .waiting(let error):
                self.log("Talkback: UDP wartet (\(error.localizedDescription))")
            case .failed(let error):
                self.fail(error.localizedDescription)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    /// Takes a copy of the buffer; any PCM format and length.
    public func append(_ buffer: AVAudioPCMBuffer) {
        guard let copy = buffer.deepCopy() else { return }
        queue.async { [weak self] in
            guard let self, !self.stopped, !self.finishing else { return }
            do {
                let samples = try self.resampler.convert(copy)
                self.schedule(try self.encoder.encode(samples))
            } catch {
                self.fail(error.localizedDescription)
            }
        }
    }

    /// Ends the stream: 0.3 s of silence flushes encoder delay, then `.finished` after the last packet.
    public func finish() {
        queue.async { [weak self] in
            guard let self, !self.stopped, !self.finishing else { return }
            do {
                self.schedule(try self.encoder.encode(self.resampler.silence(seconds: 0.3)))
            } catch {
                self.fail(error.localizedDescription)
                return
            }
            self.finishing = true
            self.completeIfDone()
        }
    }

    /// Stops at once; pending packets are dropped. No event.
    public func stop() {
        queue.async { [weak self] in
            guard let self, !self.stopped else { return }
            self.stopped = true
            self.connection.cancel()
        }
    }

    // MARK: Queue-confined

    private func schedule(_ packets: [EncodedPacket]) {
        for packet in packets {
            guard let datagram = datagram(for: packet) else {
                fail("Paket zu groß (\(packet.data.count) Bytes)")
                return
            }
            let now = Self.clock()
            let due = pacer.sendTime(forSamples: packet.frames, now: now)
            outstanding += 1
            let deadline = DispatchTime.now() + max(0, due - now)
            queue.asyncAfter(deadline: deadline) { [weak self] in
                self?.send(datagram)
            }
        }
    }

    private func datagram(for packet: EncodedPacket) -> Data? {
        switch target.codec {
        case .aac:
            return ADTS.frame(packet.data, sampleRate: target.sampleRate)
        case .opus, .vorbis:
            return packetizer.packet(
                payload: packet.data,
                timestampIncrement: RTPPacketizer.timestampIncrement(frames: packet.frames, sampleRate: target.sampleRate)
            )
        }
    }

    private func send(_ datagram: Data) {
        outstanding -= 1
        guard !stopped else { return }
        connection.send(content: datagram, completion: .contentProcessed { [weak self] error in
            guard let self, let error else { return }
            self.fail(error.localizedDescription)
        })
        sent += 1
        if !reportedFirstPacket {
            reportedFirstPacket = true
            log("Talkback: erstes Paket gesendet (\(datagram.count) Bytes)")
        }
        completeIfDone()
    }

    private func completeIfDone() {
        guard finishing, outstanding == 0, !stopped else { return }
        stopped = true
        log("Talkback: fertig, \(sent) Pakete")
        let count = sent
        // Give the last datagram a moment to leave before the connection goes away.
        queue.asyncAfter(deadline: .now() + 0.1) { [connection] in connection.cancel() }
        onEvent(.finished(packets: count))
    }

    private func fail(_ message: String) {
        guard !stopped else { return }
        stopped = true
        connection.cancel()
        log("Talkback: Fehler – \(message)")
        onEvent(.failed(message))
    }

    private static func clock() -> TimeInterval {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }
}
```

- [ ] **Step 4: Tests laufen lassen**

Run: `(cd Packages/AppCore && swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -2)`
Expected: `0 failures` (7 neue Tests; die Streamer-Tests dauern zusammen ~4 s, weil in Echtzeit gesendet wird).

- [ ] **Step 5: Build und Commit**

Run: Build-Befehl → `** BUILD SUCCEEDED **`.
```bash
git add Packages/AppCore/Sources/AppCore/Talkback Packages/AppCore/Tests/AppCoreTests/TalkbackEncoderTests.swift Packages/AppCore/Tests/AppCoreTests/TalkbackStreamerTests.swift
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "feat(talkback): AAC/Opus encoding with AudioToolbox and paced UDP streaming" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: ProtectKit – Talkback-Sitzung

**Files:**
- Create: `Packages/ProtectKit/Sources/ProtectKit/TalkbackSession.swift`
- Modify: `Packages/ProtectKit/Sources/ProtectKit/ProtectClient.swift` (nach `snapshot(cameraId:)`)
- Test: `Packages/ProtectKit/Tests/ProtectKitTests/TalkbackSessionTests.swift`

**Interfaces:**
- Consumes: `ProtectClient.sendRaw(_:_:body:accept:)` (Phase 2, Task 2), `StubProtocol` aus `ProtectClientTests.swift`.
- Produces:
  - `public struct TalkbackSession: Equatable, Sendable` – `defaultPort: UInt16 = 7004`, `url`, `codec: String`, `samplingRate: Int` (0 = fehlt), `bitsPerSample: Int`, `host: String` (ohne Klammern), `port: UInt16`, `raw: String` (≤ 500 Zeichen, fürs Log), `init(url:codec:samplingRate:bitsPerSample:raw:) throws`, `static func parse(_ data: Data) throws -> TalkbackSession` (wirft `ProtectError.decoding`)
  - `ProtectClient.talkbackSession(cameraId: String) async throws -> TalkbackSession`

- [ ] **Step 1: Failing tests schreiben**

`Packages/ProtectKit/Tests/ProtectKitTests/TalkbackSessionTests.swift`:
```swift
import XCTest
@testable import ProtectKit

final class TalkbackSessionTests: XCTestCase {
    private let base = "/proxy/protect/integration/v1"

    override func setUp() {
        StubProtocol.responses = [:]
        StubProtocol.requests = []
        StubProtocol.redirects = [:]
    }

    func testParsesDocumentedAnswer() throws {
        let session = try TalkbackSession.parse(Data(#"{"url":"rtp://192.168.1.20:7004","codec":"opus","samplingRate":48000,"bitsPerSample":16}"#.utf8))
        XCTAssertEqual(session.host, "192.168.1.20")
        XCTAssertEqual(session.port, 7004)
        XCTAssertEqual(session.codec, "opus")
        XCTAssertEqual(session.samplingRate, 48_000)
        XCTAssertEqual(session.bitsPerSample, 16)
        XCTAssertTrue(session.raw.contains("rtp://"))
    }

    func testToleratesVariants() throws {
        let wrapped = try TalkbackSession.parse(Data(#"{"data":{"url":"udp://cam.local","codec":"AAC","samplingRate":"22050"}}"#.utf8))
        XCTAssertEqual(wrapped.host, "cam.local")
        XCTAssertEqual(wrapped.port, TalkbackSession.defaultPort)
        XCTAssertEqual(wrapped.samplingRate, 22_050)
        XCTAssertEqual(wrapped.bitsPerSample, 16)
        let bare = try TalkbackSession.parse(Data(#"[{"uri":"10.0.0.5:7010","typeFmt":"aac","sampleRate":16000.0}]"#.utf8))
        XCTAssertEqual(bare.host, "10.0.0.5")
        XCTAssertEqual(bare.port, 7010)
        XCTAssertEqual(bare.codec, "aac")
        XCTAssertEqual(bare.samplingRate, 16_000)
        let ipv6 = try TalkbackSession.parse(Data(#"{"url":"rtp://[fe80::1]:7004","codec":"opus"}"#.utf8))
        XCTAssertEqual(ipv6.host, "fe80::1")
        XCTAssertEqual(ipv6.samplingRate, 0)
    }

    func testRejectsAnswersWithoutTarget() {
        for body in [#"{}"#, #"{"url":""}"#, #"{"url":"rtp://:7004"}"#, #"{"url":"rtp://cam:0"}"#, "nonsense", #""text""#] {
            XCTAssertThrowsError(try TalkbackSession.parse(Data(body.utf8)), body) {
                XCTAssertEqual($0 as? ProtectError, .decoding)
            }
        }
    }

    func testClientPostsWithKey() async throws {
        StubProtocol.responses["POST \(base)/cameras/cam1/talkback-session"] = (200, Data(#"{"url":"rtp://192.168.1.20:7004","codec":"opus","samplingRate":48000}"#.utf8))
        let client = ProtectClient(host: "192.168.1.1", apiKey: "KEY", pinnedFingerprint: nil, onNewFingerprint: { _ in }, protocolClasses: [StubProtocol.self])
        defer { client.invalidate() }
        let session = try await client.talkbackSession(cameraId: "cam1")
        XCTAssertEqual(session.port, 7004)
        let request = try XCTUnwrap(StubProtocol.requests.last)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-KEY"), "KEY")
    }

    func testClientMapsHTTPErrors() async {
        StubProtocol.responses["POST \(base)/cameras/cam1/talkback-session"] = (404, Data())
        let client = ProtectClient(host: "192.168.1.1", apiKey: "KEY", pinnedFingerprint: nil, onNewFingerprint: { _ in }, protocolClasses: [StubProtocol.self])
        defer { client.invalidate() }
        do { _ = try await client.talkbackSession(cameraId: "cam1"); XCTFail() } catch {
            XCTAssertEqual(error as? ProtectError, .http(404))
        }
    }
}
```

- [ ] **Step 2: Tests laufen lassen, Fehlschlag prüfen**

Run: `(cd Packages/ProtectKit && swift test --filter TalkbackSessionTests 2>&1 | grep -E "error:" | head -3)`
Expected: Kompilierfehler `cannot find 'TalkbackSession' in scope`.

- [ ] **Step 3: Implementierung schreiben**

`Packages/ProtectKit/Sources/ProtectKit/TalkbackSession.swift`:
```swift
import Foundation

/// Answer of `POST /v1/cameras/{id}/talkback-session`: where the camera expects audio.
/// Not verified against real hardware yet, so parsing is tolerant (wrapped in "data",
/// numbers as strings, alternative key spellings, URL with or without scheme/port).
public struct TalkbackSession: Equatable, Sendable {
    public static let defaultPort: UInt16 = 7004

    public let url: String
    public let codec: String
    /// 0 = not given.
    public let samplingRate: Int
    public let bitsPerSample: Int
    public let host: String
    public let port: UInt16
    /// Response body (no secrets) for the diagnosis log, at most 500 characters.
    public let raw: String

    public init(url: String, codec: String, samplingRate: Int, bitsPerSample: Int = 16, raw: String = "") throws {
        guard let (host, port) = Self.endpoint(from: url) else { throw ProtectError.decoding }
        self.url = url
        self.codec = codec
        self.samplingRate = samplingRate
        self.bitsPerSample = bitsPerSample
        self.host = host
        self.port = port
        self.raw = raw
    }

    public static func parse(_ data: Data) throws -> TalkbackSession {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { throw ProtectError.decoding }
        let object: [String: Any]?
        if let dict = json as? [String: Any] {
            object = (dict["data"] as? [String: Any]) ?? dict
        } else {
            object = (json as? [[String: Any]])?.first
        }
        guard let object else { throw ProtectError.decoding }
        let raw = String(String(decoding: data, as: UTF8.self).prefix(500))
        let url = string(object, ["url", "uri", "streamUrl", "talkbackUrl"]) ?? ""
        return try TalkbackSession(
            url: url,
            codec: string(object, ["codec", "typeFmt", "format"]) ?? "",
            samplingRate: integer(object, ["samplingRate", "sampleRate", "sampling_rate"]) ?? 0,
            bitsPerSample: integer(object, ["bitsPerSample", "bits_per_sample"]) ?? 16,
            raw: raw
        )
    }

    /// "rtp://192.168.1.20:7004", "udp://[fe80::1]:7004", "192.168.1.20" → host + port (default 7004).
    static func endpoint(from url: String) -> (String, UInt16)? {
        var trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") { trimmed = "udp://" + trimmed }
        guard let comps = URLComponents(string: trimmed), let rawHost = comps.host else { return nil }
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard !host.isEmpty else { return nil }
        guard let port = comps.port else { return (host, defaultPort) }
        guard (1...65_535).contains(port) else { return nil }
        return (host, UInt16(port))
    }

    private static func string(_ object: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    private static func integer(_ object: [String: Any], _ keys: [String]) -> Int? {
        for key in keys {
            if let value = object[key] as? Int { return value }
            if let value = object[key] as? Double, value.isFinite { return Int(value) }
            if let value = object[key] as? String, let number = Int(value.trimmingCharacters(in: .whitespaces)) { return number }
        }
        return nil
    }
}
```

In `ProtectClient.swift` direkt nach der Funktion `snapshot(cameraId:)` einfügen (ohne Body, wie uiprotect; gleicher Pin, gleicher Schlüssel, keine Weiterleitung):
```swift
    /// Asks the camera for a talkback stream (UDP target and codec). Same pin and key as every call.
    public func talkbackSession(cameraId: String) async throws -> TalkbackSession {
        let data = try await sendRaw("POST", "/v1/cameras/\(cameraId)/talkback-session", body: nil, accept: "application/json")
        return try TalkbackSession.parse(data)
    }
```

- [ ] **Step 4: Tests laufen lassen**

Run: `(cd Packages/ProtectKit && swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -2)`
Expected: `0 failures` (5 neue Tests).

- [ ] **Step 5: Build und Commit**

Run: Build-Befehl → `** BUILD SUCCEEDED **`.
```bash
git add Packages/ProtectKit/Sources/ProtectKit/TalkbackSession.swift Packages/ProtectKit/Sources/ProtectKit/ProtectClient.swift Packages/ProtectKit/Tests/ProtectKitTests/TalkbackSessionTests.swift
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "feat(protect): talkback session request with tolerant parsing" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: AppCore – Ansagen, Ton-Einstellungen, Audio laden und Sprache erzeugen

**Files:**
- Create: `Packages/AppCore/Sources/AppCore/Sound/Announcement.swift`, `SoundSettings.swift`, `AnnouncementAudio.swift`
- Test: `Packages/AppCore/Tests/AppCoreTests/SoundSettingsTests.swift`

**Interfaces:**
- Consumes: `TalkbackError` (Task 1), `AVAudioPCMBuffer.deepCopy()` (Task 2).
- Produces:
  - `public struct Announcement: Codable, Equatable, Identifiable, Sendable` – `enum Kind { file, speech }`, `id`, `name`, `kind`, `text`, `voiceIdentifier: String?` (nil = Stimme der mitgelieferten Aufnahme), `fileName: String?`, `bundledResource: String?`, `duration`; `init(id:name:kind:text:voiceIdentifier:fileName:bundledResource:duration:)`; `badge` („MP3“/„KI-STIMME“), `menuTag` („MP3“/„KI-Stimme“), `usesBundledRecording`, `hasAutomaticName`; `static let newName = "Neue Ansage"`, `static func lengthText(_:) -> String`, `static func suggestedName(forText:)`, `static func suggestedName(forFile:)`
  - `public enum TalkMode: String, Codable, CaseIterable, Sendable { hold, toggle }` – `label` („Leertaste halten“/„Umschalten“)
  - `public struct SoundSettings: Codable, Equatable, Sendable` – `maxFileDuration = 300`, `defaultVolume = 2/3`, `bundledBinGleichDa`, `bundledPaket`, `bundled`, `bundledVoiceLabel = "Thorsten · mitgeliefert"`, `bundledOriginal(for:)`, `offersBundledVoice(for:text:)`, `announcements`, `microphoneUID: String?`, `talkMode`, `cameraVolume` (0…1), `gain: Float` (= Wert × 1,5), `announcement(id:)`, `add(_:)`, `update(_:)`, `remove(id:) -> Announcement?`, `referencedFiles: Set<String>`
  - `public enum AnnouncementAudio` – `load(_ url:) throws -> AVAudioPCMBuffer`, `duration(of:) throws -> TimeInterval`, `voices(language: "de") -> [AVSpeechSynthesisVoice]`, `label(for:) -> String`, `render(text:voiceIdentifier:) async throws -> AVAudioPCMBuffer`, `standardized(_:) throws -> AVAudioPCMBuffer`, `write(_:to:) throws`

- [ ] **Step 1: Failing tests schreiben**

`Packages/AppCore/Tests/AppCoreTests/SoundSettingsTests.swift` (der Sprach-Test überspringt sich, wenn keine deutsche Stimme installiert ist):
```swift
import AVFoundation
import XCTest
@testable import AppCore

final class SoundSettingsTests: XCTestCase {
    func testDefaultsShipBothRecordings() {
        let settings = SoundSettings()
        XCTAssertEqual(settings.announcements.map(\.name), ["Bin gleich da", "Paket bitte abstellen"])
        XCTAssertEqual(settings.announcements.map(\.badge), ["KI-STIMME", "KI-STIMME"])
        XCTAssertEqual(settings.announcements.map(\.menuTag), ["KI-Stimme", "KI-Stimme"])
        XCTAssertTrue(settings.announcements.allSatisfy(\.usesBundledRecording))
        XCTAssertEqual(settings.talkMode, .hold)
        XCTAssertEqual(settings.gain, 1, accuracy: 0.0001)
    }

    func testLenientDecoding() throws {
        let json = #"{"announcements":[{"broken":true},{"id":"6F0C6A52-4C4B-4E58-9B1E-2F3C1C0A0009","name":"Gong","kind":"file","text":"","fileName":"gong.mp3","duration":2}],"talkMode":"shout","cameraVolume":7}"#
        let settings = try JSONDecoder().decode(SoundSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.announcements.map(\.name), ["Gong"])
        XCTAssertEqual(settings.talkMode, .hold)
        XCTAssertEqual(settings.cameraVolume, 1)
        XCTAssertEqual(settings.referencedFiles, ["gong.mp3"])
        let empty = try JSONDecoder().decode(SoundSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, SoundSettings())
    }

    func testRoundTripAndEditing() throws {
        var settings = SoundSettings()
        let gong = Announcement(name: "Gong", kind: .file, fileName: "a.mp3", duration: 2.2)
        settings.add(gong)
        var edited = gong
        edited.name = "Gong 2"
        settings.update(edited)
        XCTAssertEqual(settings.announcement(id: gong.id)?.name, "Gong 2")
        let again = try JSONDecoder().decode(SoundSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(again, settings)
        XCTAssertEqual(settings.remove(id: gong.id)?.fileName, "a.mp3")
        XCTAssertNil(settings.remove(id: gong.id))
    }

    func testLengthText() {
        XCTAssertEqual(Announcement.lengthText(2.74), "0:03")
        XCTAssertEqual(Announcement.lengthText(0.2), "0:01")
        XCTAssertEqual(Announcement.lengthText(65), "1:05")
        XCTAssertEqual(Announcement.lengthText(0), "–:–")
        XCTAssertEqual(Announcement.lengthText(.nan), "–:–")
    }

    func testSuggestedNames() {
        XCTAssertEqual(Announcement.suggestedName(forText: "Bin gleich da! Einen kleinen Moment, bitte."), "Bin gleich da")
        XCTAssertEqual(Announcement.suggestedName(forText: "   "), "Neue Ansage")
        XCTAssertEqual(Announcement.suggestedName(forText: "!!!"), "Neue Ansage")
        XCTAssertEqual(Announcement.suggestedName(forText: String(repeating: "a", count: 40)).count, 32)
        XCTAssertEqual(Announcement.suggestedName(forFile: URL(fileURLWithPath: "/tmp/Gong laut.mp3")), "Gong laut")
    }

    func testBundledVoiceOnlyForBundledWording() {
        let original = SoundSettings.bundledBinGleichDa
        XCTAssertTrue(SoundSettings.offersBundledVoice(for: original, text: " Bin gleich da! Einen kleinen Moment, bitte. "))
        XCTAssertFalse(SoundSettings.offersBundledVoice(for: original, text: "Bin gleich da."))
        var rerendered = original
        rerendered.fileName = "x.caf"
        rerendered.voiceIdentifier = "com.apple.voice.premium.de-DE.Anna"
        XCTAssertFalse(rerendered.usesBundledRecording)
        XCTAssertEqual(SoundSettings.bundledOriginal(for: rerendered), original)
        XCTAssertFalse(SoundSettings.offersBundledVoice(for: Announcement(name: "Gong", kind: .file), text: ""))
    }

    func testAutomaticNames() {
        XCTAssertTrue(Announcement(name: "Neue Ansage", kind: .speech).hasAutomaticName)
        XCTAssertTrue(SoundSettings.bundledBinGleichDa.hasAutomaticName)
        XCTAssertFalse(Announcement(name: "Paketbote", kind: .speech, text: "Bitte vor die Tür legen.").hasAutomaticName)
        XCTAssertFalse(Announcement(name: "Gong", kind: .file).hasAutomaticName)
    }

    func testStandardizedConvertsInt16() throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 22_050, channels: 1, interleaved: true)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 100)!
        buffer.frameLength = 100
        buffer.int16ChannelData![0][10] = 16_384
        let float = try AnnouncementAudio.standardized(buffer)
        XCTAssertEqual(float.format.commonFormat, .pcmFormatFloat32)
        XCTAssertEqual(float.frameLength, 100)
        XCTAssertEqual(float.floatChannelData![0][10], 0.5, accuracy: 0.001)
    }

    func testSpeechRendersIntoBuffer() async throws {
        guard let voice = AnnouncementAudio.voices().first else { throw XCTSkip("Keine deutsche macOS-Stimme installiert") }
        XCTAssertTrue(AnnouncementAudio.label(for: voice).hasSuffix(" · macOS"))
        let buffer = try await AnnouncementAudio.render(text: "Bin gleich da.", voiceIdentifier: voice.identifier)
        XCTAssertGreaterThan(Double(buffer.frameLength) / buffer.format.sampleRate, 0.3)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("speech-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        try AnnouncementAudio.write(buffer, to: url)
        XCTAssertEqual(try AnnouncementAudio.duration(of: url), Double(buffer.frameLength) / buffer.format.sampleRate, accuracy: 0.05)
        XCTAssertEqual(Double(try AnnouncementAudio.load(url).frameLength), Double(buffer.frameLength), accuracy: Double(buffer.frameLength) * 0.02)
    }
}
```

- [ ] **Step 2: Tests laufen lassen, Fehlschlag prüfen**

Run: `(cd Packages/AppCore && swift test --filter SoundSettingsTests 2>&1 | grep -E "error:" | head -3)`
Expected: Kompilierfehler `cannot find 'SoundSettings' in scope`.

- [ ] **Step 3: Implementierung schreiben**

`Packages/AppCore/Sources/AppCore/Sound/Announcement.swift`:
```swift
import Foundation

/// One entry of "Ansagen für „Ton abspielen“": an MP3 file or a text spoken by a voice.
public struct Announcement: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case file
        case speech
    }

    public var id: UUID
    public var name: String
    public var kind: Kind
    /// Spoken text (speech only).
    public var text: String
    /// macOS voice (`AVSpeechSynthesisVoice.identifier`); nil = the bundled recording's voice.
    public var voiceIdentifier: String?
    /// Audio in the app's sound folder: the copied MP3 or the rendered speech.
    public var fileName: String?
    /// Bundled MP3 in the app (resource name without extension), used while `fileName` is nil.
    public var bundledResource: String?
    /// Seconds; 0 = unknown.
    public var duration: TimeInterval

    public init(
        id: UUID = UUID(),
        name: String,
        kind: Kind,
        text: String = "",
        voiceIdentifier: String? = nil,
        fileName: String? = nil,
        bundledResource: String? = nil,
        duration: TimeInterval = 0
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.text = text
        self.voiceIdentifier = voiceIdentifier
        self.fileName = fileName
        self.bundledResource = bundledResource
        self.duration = duration
    }

    /// Badge in Einstellungen › Ton ("MP3" / "KI-STIMME").
    public var badge: String { kind == .file ? "MP3" : "KI-STIMME" }
    /// Tag in the popup's sound menu ("MP3" / "KI-Stimme").
    public var menuTag: String { kind == .file ? "MP3" : "KI-Stimme" }
    /// The bundled voice is only valid for the bundled wording.
    public var usesBundledRecording: Bool { bundledResource != nil && fileName == nil }

    /// Name still follows the text (new entries, unchanged suggestions): renaming it is automatic.
    public var hasAutomaticName: Bool {
        name == Announcement.newName || (kind == .speech && name == Announcement.suggestedName(forText: text))
    }

    public static let newName = "Neue Ansage"

    /// "0:03" – rounded to whole seconds, at least 0:01; "–:–" when unknown.
    public static func lengthText(_ duration: TimeInterval) -> String {
        guard duration.isFinite, duration > 0 else { return "–:–" }
        let seconds = max(1, Int(duration.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// List name for a text announcement: first sentence, without end punctuation, at most 32 characters.
    public static func suggestedName(forText text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return newName }
        let firstSentence = trimmed.split(whereSeparator: { ".!?\n".contains($0) }).first.map(String.init) ?? trimmed
        let clean = firstSentence.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !clean.isEmpty else { return newName }
        guard clean.count > 32 else { return clean }
        return String(clean.prefix(31)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// List name for an added file: file name without extension.
    public static func suggestedName(forFile url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? newName : base
    }
}
```

`Packages/AppCore/Sources/AppCore/Sound/SoundSettings.swift` (Wortlaut der mitgelieferten Ansagen: siehe Offene Frage 2):
```swift
import Foundation

/// How push-to-talk reacts to the space bar / talk button.
public enum TalkMode: String, Codable, CaseIterable, Sendable {
    /// "Leertaste halten": talk while held.
    case hold
    /// "Umschalten": first press starts, second press stops.
    case toggle

    public var label: String {
        switch self {
        case .hold: return "Leertaste halten"
        case .toggle: return "Umschalten"
        }
    }
}

/// Einstellungen › Ton. Stored on this Mac only (not part of the configuration export).
public struct SoundSettings: Codable, Equatable, Sendable {
    /// Longest file accepted for "MP3 hinzufügen …".
    public static let maxFileDuration: TimeInterval = 300
    /// Template slider position (120 of 180) = unchanged loudness.
    public static let defaultVolume = 2.0 / 3.0

    public static let bundledBinGleichDa = Announcement(
        id: UUID(uuidString: "6F0C6A52-4C4B-4E58-9B1E-2F3C1C0A0001")!,
        name: "Bin gleich da",
        kind: .speech,
        text: "Bin gleich da! Einen kleinen Moment, bitte.",
        bundledResource: "bin-gleich-da",
        duration: 2.74
    )
    public static let bundledPaket = Announcement(
        id: UUID(uuidString: "6F0C6A52-4C4B-4E58-9B1E-2F3C1C0A0002")!,
        name: "Paket bitte abstellen",
        kind: .speech,
        text: "Paket bitte abstellen.",
        bundledResource: "paket-abstellen",
        duration: 4.0
    )

    public static var bundled: [Announcement] { [bundledBinGleichDa, bundledPaket] }
    /// Label of the voice of the bundled recordings (Piper, Thorsten, CC0).
    public static let bundledVoiceLabel = "Thorsten · mitgeliefert"

    /// The shipped original an entry was made from (also after it was re-rendered with a macOS voice).
    public static func bundledOriginal(for entry: Announcement) -> Announcement? {
        guard let resource = entry.bundledResource else { return nil }
        return bundled.first { $0.bundledResource == resource }
    }

    /// The bundled voice can only say the bundled wording.
    public static func offersBundledVoice(for entry: Announcement, text: String) -> Bool {
        guard let original = bundledOriginal(for: entry) else { return false }
        return original.text == text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var announcements: [Announcement]
    /// Core Audio device UID; nil = system default input.
    public var microphoneUID: String?
    public var talkMode: TalkMode
    /// 0…1 slider; gain = volume × 1.5 (template default 2/3 = 1.0).
    public var cameraVolume: Double

    public init(
        announcements: [Announcement] = SoundSettings.bundled,
        microphoneUID: String? = nil,
        talkMode: TalkMode = .hold,
        cameraVolume: Double = SoundSettings.defaultVolume
    ) {
        self.announcements = announcements
        self.microphoneUID = microphoneUID
        self.talkMode = talkMode
        self.cameraVolume = min(1, max(0, cameraVolume))
    }

    public var gain: Float { Float(cameraVolume * 1.5) }

    public func announcement(id: UUID) -> Announcement? {
        announcements.first { $0.id == id }
    }

    public mutating func add(_ announcement: Announcement) {
        announcements.append(announcement)
    }

    public mutating func update(_ announcement: Announcement) {
        guard let index = announcements.firstIndex(where: { $0.id == announcement.id }) else { return }
        announcements[index] = announcement
    }

    /// Removes the entry and returns it (the caller deletes its file).
    @discardableResult
    public mutating func remove(id: UUID) -> Announcement? {
        guard let index = announcements.firstIndex(where: { $0.id == id }) else { return nil }
        return announcements.remove(at: index)
    }

    /// File names still referenced (everything else in the sound folder can go).
    public var referencedFiles: Set<String> {
        Set(announcements.compactMap(\.fileName))
    }

    private enum CodingKeys: String, CodingKey {
        case announcements, microphoneUID, talkMode, cameraVolume
    }

    /// Lenient: unknown talk modes, broken entries or a missing list fall back to defaults.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SoundSettings()
        if let lossy = try? container.decodeIfPresent([LossyAnnouncement].self, forKey: .announcements) {
            announcements = lossy.compactMap(\.value)
        } else {
            announcements = defaults.announcements
        }
        microphoneUID = (try? container.decodeIfPresent(String.self, forKey: .microphoneUID)) ?? nil
        let mode = (try? container.decodeIfPresent(String.self, forKey: .talkMode)) ?? nil
        talkMode = mode.flatMap(TalkMode.init(rawValue:)) ?? .hold
        let volume = (try? container.decodeIfPresent(Double.self, forKey: .cameraVolume)) ?? nil
        cameraVolume = min(1, max(0, volume ?? Self.defaultVolume))
    }

    private struct LossyAnnouncement: Decodable {
        let value: Announcement?
        init(from decoder: Decoder) throws {
            value = try? Announcement(from: decoder)
        }
    }
}
```

`Packages/AppCore/Sources/AppCore/Sound/AnnouncementAudio.swift`:
```swift
import AVFoundation
import Foundation

/// Loads announcement audio and renders text with macOS voices (no network, no GPL engines).
public enum AnnouncementAudio {
    /// Whole file as one PCM buffer in its processing format.
    public static func load(_ url: URL) throws -> AVAudioPCMBuffer {
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) } catch {
            throw TalkbackError.audioFile(error.localizedDescription)
        }
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else {
            throw TalkbackError.audioFile("leer")
        }
        do { try file.read(into: buffer) } catch {
            throw TalkbackError.audioFile(error.localizedDescription)
        }
        return buffer
    }

    public static func duration(of url: URL) throws -> TimeInterval {
        do {
            let file = try AVAudioFile(forReading: url)
            return Double(file.length) / file.processingFormat.sampleRate
        } catch {
            throw TalkbackError.audioFile(error.localizedDescription)
        }
    }

    /// German voices first (premium, enhanced, default), then by name.
    public static func voices(language: String = "de") -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix(language.lowercased()) }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality { return lhs.quality.rawValue > rhs.quality.rawValue }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    /// "Anna (Premium) · macOS" – template wording of the voice pop-up.
    public static func label(for voice: AVSpeechSynthesisVoice) -> String {
        let quality: String
        switch voice.quality {
        case .premium: quality = " (Premium)"
        case .enhanced: quality = " (Erweitert)"
        default: quality = ""
        }
        return "\(voice.name)\(quality) · macOS"
    }

    /// Speaks `text` into a buffer (`AVSpeechSynthesizer.write`). Unknown voice = system default German voice.
    public static func render(text: String, voiceIdentifier: String?) async throws -> AVAudioPCMBuffer {
        let utterance = AVSpeechUtterance(string: text)
        if let voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = voices().first ?? AVSpeechSynthesisVoice(language: "de-DE")
        }
        let collector = SpeechCollector()
        return try await withCheckedThrowingContinuation { continuation in
            collector.start(utterance) { result in
                continuation.resume(with: result)
            }
        }
    }

    /// Same audio as 32-bit float, non-interleaved (what AVAudioPlayerNode and the mixer accept).
    public static func standardized(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let format = buffer.format
        if format.commonFormat == .pcmFormatFloat32, !format.isInterleaved { return buffer }
        guard let target = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: format.channelCount),
              let converter = AVAudioConverter(from: format, to: target),
              let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: max(buffer.frameLength, 1)) else {
            throw TalkbackError.audioFile("Format")
        }
        do { try converter.convert(to: output, from: buffer) } catch {
            throw TalkbackError.audioFile(error.localizedDescription)
        }
        return output
    }

    /// Writes a buffer as CAF (used to cache rendered speech).
    public static func write(_ buffer: AVAudioPCMBuffer, to url: URL) throws {
        do {
            let file = try AVAudioFile(forWriting: url, settings: buffer.format.settings,
                                       commonFormat: buffer.format.commonFormat, interleaved: buffer.format.isInterleaved)
            try file.write(from: buffer)
        } catch {
            throw TalkbackError.audioFile(error.localizedDescription)
        }
    }
}

/// Keeps the synthesizer alive and concatenates its buffers; a zero-length buffer ends the utterance.
private final class SpeechCollector: @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private var chunks: [AVAudioPCMBuffer] = []
    private var done = false
    private let lock = NSLock()

    func start(_ utterance: AVSpeechUtterance, completion: @escaping (Result<AVAudioPCMBuffer, Error>) -> Void) {
        synthesizer.write(utterance) { [self] buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            let finished: Bool = lock.withLock {
                guard !done else { return false }
                if pcm.frameLength == 0 {
                    done = true
                    return true
                }
                if let copy = pcm.deepCopy() { chunks.append(copy) }
                return false
            }
            guard finished else { return }
            let parts = lock.withLock { chunks }
            if let joined = Self.join(parts) {
                completion(.success(joined))
            } else {
                completion(.failure(TalkbackError.speechFailed))
            }
            withExtendedLifetime(self) {}
        }
    }

    private static func join(_ parts: [AVAudioPCMBuffer]) -> AVAudioPCMBuffer? {
        guard let format = parts.first?.format else { return nil }
        let total = parts.reduce(0) { $0 + $1.frameLength }
        guard total > 0, let joined = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total) else { return nil }
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        let target = UnsafeMutableAudioBufferListPointer(joined.mutableAudioBufferList)
        var offset = 0
        for part in parts where part.format == format {
            let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: part.audioBufferList))
            let bytes = Int(part.frameLength) * bytesPerFrame
            for (from, to) in zip(source, target) {
                guard let src = from.mData, let dst = to.mData else { continue }
                memcpy(dst.advanced(by: offset), src, bytes)
            }
            offset += bytes
        }
        joined.frameLength = AVAudioFrameCount(offset / bytesPerFrame)
        return joined
    }
}
```

- [ ] **Step 4: Tests laufen lassen**

Run: `(cd Packages/AppCore && swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests|skipped" | tail -3)`
Expected: `0 failures` (9 neue Tests; `testSpeechRendersIntoBuffer` läuft auf diesem Mac, ohne deutsche Stimme `skipped`).

- [ ] **Step 5: Build und Commit**

Run: Build-Befehl → `** BUILD SUCCEEDED **`.
```bash
git add Packages/AppCore/Sources/AppCore/Sound Packages/AppCore/Tests/AppCoreTests/SoundSettingsTests.swift
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "feat(sound): announcements, sound settings, file loading and macOS speech rendering" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: App – Ansagen-Ablage, Probehören, mitgelieferte MP3s, Diagnose-Log

**Files:**
- Create: `UniFiCameraPopup/Services/TalkbackLog.swift`, `UniFiCameraPopup/Services/SoundStore.swift`, `UniFiCameraPopup/Services/PreviewPlayer.swift`
- Create: `UniFiCameraPopup/Resources/Sounds/bin-gleich-da.mp3`, `paket-abstellen.mp3` (Kopie aus `docs/superpowers/specs/phase2-4/sounds/`)
- Modify: `UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj` (drei Swift-Dateien, Gruppe Sounds, zwei Ressourcen)

**Interfaces:**
- Consumes: `Announcement`, `SoundSettings`, `AnnouncementAudio`, `TalkbackError` (Task 1/4).
- Produces:
  - `enum TalkbackLog` – `static let fileURL`, `static func write(_ message: String)`
  - `@MainActor final class SoundStore: ObservableObject` – `static let shared`, `@Published var settings: SoundSettings` (speichert bei jeder Änderung), `folder: URL`, `audioURL(for:) -> URL?`, `previewBuffer(for:text:voiceIdentifier:) async throws -> AVAudioPCMBuffer`, `addFile(from:) throws -> Announcement`, `addText() -> Announcement`, `replaceWithFile(id:from:) throws`, `applySpeech(id:text:voiceIdentifier:) async throws`, `rename(id:to:)`, `remove(id:)`
  - `@MainActor final class PreviewPlayer: ObservableObject` – `static let shared`, `@Published private(set) var playingId: UUID?`, `play(_ buffer:id:)`, `stop()`

- [ ] **Step 1: Mitgelieferte Ansagen ablegen**

```bash
mkdir -p UniFiCameraPopup/Resources/Sounds
cp docs/superpowers/specs/phase2-4/sounds/bin-gleich-da.mp3 docs/superpowers/specs/phase2-4/sounds/paket-abstellen.mp3 UniFiCameraPopup/Resources/Sounds/
afinfo UniFiCameraPopup/Resources/Sounds/bin-gleich-da.mp3 | grep "estimated duration"    # 2.742857 sec
afinfo UniFiCameraPopup/Resources/Sounds/paket-abstellen.mp3 | grep "estimated duration"  # 3.996735 sec
```
Die Längen passen zu `SoundSettings.bundledBinGleichDa.duration` (2,74) und `bundledPaket.duration` (4,0).

- [ ] **Step 2: Diagnose-Log**

`UniFiCameraPopup/Services/TalkbackLog.swift`:
```swift
import Foundation

/// Diagnosis for talkback (not yet verified on real hardware): every step goes to the system
/// log and to ~/Library/Logs/UniFi Camera Popup/talkback.log (rotated at 512 KB).
/// Never logs the API key – only camera ids, the session answer and packet counts.
enum TalkbackLog {
    static let fileURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/UniFi Camera Popup/talkback.log")
    private static let queue = DispatchQueue(label: "com.snackbits.UniFiCameraPopup.talkback-log")
    private static let maxBytes = 512 * 1024

    static func write(_ message: String) {
        NSLog("%@", message)
        let line = "\(ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withInternetDateTime, .withFractionalSeconds])) \(message)\n"
        queue.async {
            let manager = FileManager.default
            try? manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = (try? manager.attributesOfItem(atPath: fileURL.path))?[.size] as? Int, size > maxBytes {
                let old = fileURL.deletingPathExtension().appendingPathExtension("old.log")
                try? manager.removeItem(at: old)
                try? manager.moveItem(at: fileURL, to: old)
            }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: fileURL)
            }
        }
    }
}
```

- [ ] **Step 3: Ansagen-Ablage**

`UniFiCameraPopup/Services/SoundStore.swift`:
```swift
import AppCore
import AVFoundation
import Combine
import Foundation

/// Einstellungen › Ton: announcements, microphone, talk mode, camera volume.
/// Own UserDefaults key and files in Application Support – not part of the configuration export.
@MainActor
final class SoundStore: ObservableObject {
    static let shared = SoundStore()

    @Published var settings: SoundSettings {
        didSet { save() }
    }

    /// ~/Library/Application Support/UniFi Camera Popup/Sounds
    let folder: URL
    private static let storageKey = "unifi.camera.popup.sound"
    private let defaults = UserDefaults.standard

    private init() {
        folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UniFi Camera Popup/Sounds", isDirectory: true)
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(SoundSettings.self, from: data) {
            settings = saved
        } else {
            settings = SoundSettings()
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        removeUnreferencedFiles()
    }

    // MARK: Audio

    /// Playable audio of an entry: copied/rendered file, else the bundled MP3. nil = file missing.
    func audioURL(for announcement: Announcement) -> URL? {
        if let name = announcement.fileName {
            let url = folder.appendingPathComponent(name)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        if let resource = announcement.bundledResource {
            return Bundle.main.url(forResource: resource, withExtension: "mp3")
        }
        return nil
    }

    /// Audio for "Anhören": the bundled recording for its own wording, else the text rendered now.
    func previewBuffer(for entry: Announcement, text: String, voiceIdentifier: String?) async throws -> AVAudioPCMBuffer {
        if voiceIdentifier == nil,
           SoundSettings.offersBundledVoice(for: entry, text: text),
           let original = SoundSettings.bundledOriginal(for: entry),
           let url = audioURL(for: original) {
            return try AnnouncementAudio.load(url)
        }
        return try await AnnouncementAudio.render(text: text, voiceIdentifier: voiceIdentifier)
    }

    // MARK: Editing

    /// "MP3 hinzufügen …": copies the file into the sound folder and appends an entry.
    @discardableResult
    func addFile(from source: URL) throws -> Announcement {
        let entry = try importFile(source, into: Announcement(name: Announcement.suggestedName(forFile: source), kind: .file))
        settings.add(entry)
        TalkbackLog.write("Ansage hinzugefügt: \(entry.name) (\(Announcement.lengthText(entry.duration)))")
        return entry
    }

    /// "Ansage aus Text …": new empty text entry with the best German macOS voice.
    @discardableResult
    func addText() -> Announcement {
        let entry = Announcement(
            name: Announcement.newName,
            kind: .speech,
            voiceIdentifier: AnnouncementAudio.voices().first?.identifier
        )
        settings.add(entry)
        return entry
    }

    /// Editor segment "MP3-Datei" › "Datei wählen …": the entry now plays this file.
    func replaceWithFile(id: UUID, from source: URL) throws {
        guard let current = settings.announcement(id: id) else { return }
        var entry = try importFile(source, into: current)
        if current.hasAutomaticName || current.kind == .speech {
            entry.name = Announcement.suggestedName(forFile: source)
        }
        entry.kind = .file
        entry.text = ""
        entry.voiceIdentifier = nil
        entry.bundledResource = nil
        settings.update(entry)
        deleteFile(current.fileName)
    }

    /// "Übernehmen": text + voice become the entry's audio. The bundled voice (nil) only
    /// for the bundled wording – then the bundled recording is used again.
    func applySpeech(id: UUID, text: String, voiceIdentifier: String?) async throws {
        guard let current = settings.announcement(id: id) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var entry = current
        entry.kind = .speech
        entry.text = trimmed
        if voiceIdentifier == nil,
           SoundSettings.offersBundledVoice(for: current, text: trimmed),
           let original = SoundSettings.bundledOriginal(for: current) {
            entry.voiceIdentifier = nil
            entry.fileName = nil
            entry.duration = original.duration
        } else {
            let voice = voiceIdentifier ?? AnnouncementAudio.voices().first?.identifier
            let buffer = try await AnnouncementAudio.render(text: trimmed, voiceIdentifier: voice)
            let name = "\(UUID().uuidString).caf"
            try AnnouncementAudio.write(buffer, to: folder.appendingPathComponent(name))
            entry.voiceIdentifier = voice
            entry.fileName = name
            entry.duration = Double(buffer.frameLength) / buffer.format.sampleRate
        }
        if current.hasAutomaticName {
            entry.name = Announcement.suggestedName(forText: trimmed)
        }
        // Deleted while rendering: drop the new file.
        guard settings.announcement(id: id) != nil else {
            deleteFile(entry.fileName)
            return
        }
        settings.update(entry)
        if current.fileName != entry.fileName {
            deleteFile(current.fileName)
        }
    }

    func rename(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var entry = settings.announcement(id: id) else { return }
        entry.name = String(trimmed.prefix(60))
        settings.update(entry)
    }

    func remove(id: UUID) {
        let removed = settings.remove(id: id)
        deleteFile(removed?.fileName)
    }

    // MARK: Files

    private func importFile(_ source: URL, into entry: Announcement) throws -> Announcement {
        let duration = try AnnouncementAudio.duration(of: source)
        guard duration > 0 else { throw TalkbackError.audioFile("leer") }
        guard duration <= SoundSettings.maxFileDuration else { throw TalkbackError.fileTooLong }
        let ext = source.pathExtension.isEmpty ? "mp3" : source.pathExtension.lowercased()
        let name = "\(UUID().uuidString).\(ext)"
        do {
            try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(name))
        } catch {
            throw TalkbackError.audioFile(error.localizedDescription)
        }
        var updated = entry
        updated.fileName = name
        updated.duration = duration
        return updated
    }

    private func deleteFile(_ name: String?) {
        guard let name else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
    }

    /// Leftovers of deleted or re-rendered entries (e.g. after a crash).
    private func removeUnreferencedFiles() {
        let keep = settings.referencedFiles
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for file in files where !keep.contains(file) {
            deleteFile(file)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
```

- [ ] **Step 4: Probehören**

`UniFiCameraPopup/Services/PreviewPlayer.swift`:
```swift
import AppCore
import AVFoundation

/// "Probehören" / "Anhören" on this Mac's speakers (never sent to a camera).
@MainActor
final class PreviewPlayer: ObservableObject {
    static let shared = PreviewPlayer()

    /// Announcement being previewed; nil when silent.
    @Published private(set) var playingId: UUID?
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var connectedFormat: AVAudioFormat?
    private var generation = 0

    private init() {
        engine.attach(node)
    }

    func play(_ buffer: AVAudioPCMBuffer, id: UUID) {
        stop()
        do {
            let playable = try AnnouncementAudio.standardized(buffer)
            if connectedFormat != playable.format {
                engine.disconnectNodeOutput(node)
                engine.connect(node, to: engine.mainMixerNode, format: playable.format)
                connectedFormat = playable.format
            }
            if !engine.isRunning { try engine.start() }
            generation += 1
            let current = generation
            playingId = id
            // Called on the render thread.
            node.scheduleBuffer(playable) { [weak self] in
                Task { @MainActor in
                    guard let self, self.generation == current else { return }
                    self.playingId = nil
                }
            }
            node.play()
        } catch {
            NSLog("Preview failed: \(error.localizedDescription)")
            playingId = nil
        }
    }

    func stop() {
        generation += 1
        node.stop()
        playingId = nil
    }
}
```

- [ ] **Step 5: pbxproj**

Vorher: `grep -c "C31000000000000000000001\|C34000000000000000000001" UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj` → `0`.

1. `/* Begin PBXBuildFile section */`, am Ende des Abschnitts:
```
		C31000000000000000000001 /* SoundStore.swift in Sources */ = {isa = PBXBuildFile; fileRef = C32000000000000000000001 /* SoundStore.swift */; };
		C31000000000000000000002 /* PreviewPlayer.swift in Sources */ = {isa = PBXBuildFile; fileRef = C32000000000000000000002 /* PreviewPlayer.swift */; };
		C31000000000000000000003 /* TalkbackLog.swift in Sources */ = {isa = PBXBuildFile; fileRef = C32000000000000000000003 /* TalkbackLog.swift */; };
		C31000000000000000000009 /* bin-gleich-da.mp3 in Resources */ = {isa = PBXBuildFile; fileRef = C32000000000000000000009 /* bin-gleich-da.mp3 */; };
		C31000000000000000000010 /* paket-abstellen.mp3 in Resources */ = {isa = PBXBuildFile; fileRef = C32000000000000000000010 /* paket-abstellen.mp3 */; };
```
2. `/* Begin PBXFileReference section */`, am Ende des Abschnitts:
```
		C32000000000000000000001 /* SoundStore.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SoundStore.swift; sourceTree = "<group>"; };
		C32000000000000000000002 /* PreviewPlayer.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PreviewPlayer.swift; sourceTree = "<group>"; };
		C32000000000000000000003 /* TalkbackLog.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = TalkbackLog.swift; sourceTree = "<group>"; };
		C32000000000000000000009 /* bin-gleich-da.mp3 */ = {isa = PBXFileReference; lastKnownFileType = audio.mp3; path = "bin-gleich-da.mp3"; sourceTree = "<group>"; };
		C32000000000000000000010 /* paket-abstellen.mp3 */ = {isa = PBXFileReference; lastKnownFileType = audio.mp3; path = "paket-abstellen.mp3"; sourceTree = "<group>"; };
```
3. In der Gruppe `A40000000000000000000005 /* Services */` am Ende der `children`:
```
				C32000000000000000000001 /* SoundStore.swift */,
				C32000000000000000000002 /* PreviewPlayer.swift */,
				C32000000000000000000003 /* TalkbackLog.swift */,
```
4. Neue Gruppe im `PBXGroup`-Abschnitt (nach der Gruppe `A40000000000000000000006 /* Views */`):
```
		C34000000000000000000001 /* Sounds */ = {
			isa = PBXGroup;
			children = (
				C32000000000000000000009 /* bin-gleich-da.mp3 */,
				C32000000000000000000010 /* paket-abstellen.mp3 */,
			);
			path = "Resources/Sounds";
			sourceTree = "<group>";
		};
```
5. In der Gruppe `A40000000000000000000002 /* Source */` nach `A40000000000000000000006 /* Views */,`: `C34000000000000000000001 /* Sounds */,`
6. In `A60000000000000000000002 /* Sources */` am Ende der `files`:
```
				C31000000000000000000001 /* SoundStore.swift in Sources */,
				C31000000000000000000002 /* PreviewPlayer.swift in Sources */,
				C31000000000000000000003 /* TalkbackLog.swift in Sources */,
```
7. In `A60000000000000000000003 /* Resources */` nach `A10000000000000000000013 /* Assets.xcassets in Resources */,`:
```
				C31000000000000000000009 /* bin-gleich-da.mp3 in Resources */,
				C31000000000000000000010 /* paket-abstellen.mp3 in Resources */,
```

- [ ] **Step 6: Lint, Build, Ressourcen im Paket prüfen**

Run: `plutil -lint UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj` → `OK`
Run: Build-Befehl → `** BUILD SUCCEEDED **`
Run: `ls "$DD/Build/Products/Debug/UniFi Camera Popup.app/Contents/Resources/" | grep -c "\.mp3$"`
Expected: `2`

- [ ] **Step 7: Commit**

```bash
git add UniFiCameraPopup/Services/TalkbackLog.swift UniFiCameraPopup/Services/SoundStore.swift UniFiCameraPopup/Services/PreviewPlayer.swift UniFiCameraPopup/Resources/Sounds UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "feat(sound): announcement store, local preview, bundled Piper recordings and talkback log" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: App – Mikrofon, Talkback-Ablauf und Leertaste

**Files:**
- Create: `UniFiCameraPopup/Services/MicrophoneCapture.swift`, `UniFiCameraPopup/Services/PushToTalkKey.swift`, `UniFiCameraPopup/Services/TalkbackService.swift`
- Modify: `UniFiCameraPopup/Services/GlobalHotkeyManager.swift:9` und `:122` (fremde Hotkey-Signaturen weiterreichen)
- Modify: `UniFiCameraPopup/Info.plist` (`NSMicrophoneUsageDescription`)
- Modify: `project.pbxproj` (drei Dateien)

**Interfaces:**
- Consumes: `TalkbackStreamer`, `TalkbackTarget.make`, `TalkbackError` (Task 1/2); `ProtectClient.talkbackSession`, `TalkbackSession` (Task 3); `Announcement`, `AnnouncementAudio.load` (Task 4); `SoundStore`, `TalkbackLog` (Task 5); `SettingsStore.shared.isProtectConfigured`, `mapping(forEntry:)`, `ProtectSession.shared.client`, `.cameras`, `WebhookMapping.entryId`, `.protectCameraId`, `.label` (bestehend).
- Produces:
  - `struct AudioInputDevice: Identifiable, Hashable { id: AudioDeviceID; uid: String; name: String }`
  - `@MainActor final class MicrophoneCapture` – `static func inputDevices()`, `static func defaultInputDevice()`, `static func requestPermission() async -> Bool`, `func start(deviceUID:onBuffer:) throws`, `func stop()`
  - `@MainActor final class PushToTalkKey` – `static let shared`, `nonisolated static let signature`, `isArmed`, `arm(onPress:onRelease:)`, `disarm()`
  - `enum TalkbackPurpose: Equatable { talk, announcement(UUID) }`, `struct TalkbackActivity: Equatable { entryId; purpose; phase: Phase { preparing, live } }`, `struct TalkbackNotice: Equatable { id; entryId; text }`
  - `@MainActor final class TalkbackService: ObservableObject` – `static let shared`, `@Published private(set) var activity: TalkbackActivity?`, `@Published private(set) var notice: TalkbackNotice?`, `canTalk(_ mapping: WebhookMapping) -> Bool`, `isActive(entryId:) -> Bool`, `pressTalk(entryId:)`, `releaseTalk()`, `toggleTalk(entryId:)`, `startTalking(entryId:)`, `stopTalking()`, `play(_ announcement:entryId:)`, `stopPlayback()`, `pointerEntered(entryId:)`, `pointerExited(entryId:)`, `popupClosed(entryId:)`

- [ ] **Step 1: Mikrofon**

`UniFiCameraPopup/Services/MicrophoneCapture.swift`:
```swift
import AppCore
import AudioToolbox
import AVFoundation
import CoreAudio

/// An input device for the "Mikrofon" pop-up.
struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

/// The Mac microphone for push-to-talk: AVAudioEngine input on the chosen Core Audio device.
@MainActor
final class MicrophoneCapture {
    private var engine: AVAudioEngine?

    // MARK: Devices

    static func inputDevices() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard inputChannels(of: id) > 0,
                  let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            return AudioInputDevice(id: id, uid: uid, name: name)
        }
    }

    static func defaultInputDevice() -> AudioInputDevice? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != 0 else { return nil }
        return inputDevices().first { $0.id == id }
    }

    private static func inputChannels(of id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    // MARK: Permission

    /// Asks once (system dialog with NSMicrophoneUsageDescription); false = denied or restricted.
    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    // MARK: Capture

    /// Delivers microphone buffers on the audio thread until `stop()`. Unknown UID = system default.
    func start(deviceUID: String?, onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        stop()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if let deviceUID, let device = Self.inputDevices().first(where: { $0.uid == deviceUID }), let unit = input.audioUnit {
            var id = device.id
            let status = AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &id,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr {
                TalkbackLog.write("Mikrofon „\(device.name)“ nicht wählbar (\(status)) – nehme den Standard")
            }
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw TalkbackError.microphoneUnavailable }
        input.installTap(onBus: 0, bufferSize: 1_024, format: format, block: Self.tap(onBuffer))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            TalkbackLog.write("Mikrofon startet nicht: \(error.localizedDescription)")
            throw TalkbackError.microphoneUnavailable
        }
        TalkbackLog.write("Mikrofon: \(Int(format.sampleRate)) Hz, \(format.channelCount) Kanal/Kanäle")
        self.engine = engine
    }

    func stop() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    /// Built outside the main actor: the tap runs on the audio thread.
    private nonisolated static func tap(_ onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in onBuffer(buffer) }
    }
}
```

- [ ] **Step 2: Leertaste als Hotkey**

`UniFiCameraPopup/Services/PushToTalkKey.swift`:
```swift
import Carbon.HIToolbox
import Foundation

/// Space bar as a global hot key (pressed + released) while the pointer is over a popup that can talk.
/// The popup never becomes key, so a local key monitor would not see the space bar.
@MainActor
final class PushToTalkKey {
    static let shared = PushToTalkKey()

    nonisolated static let signature: OSType = 0x5543_5054 // "UCPT"
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var onPress: (() -> Void)?
    private var onRelease: (() -> Void)?

    private init() {}

    var isArmed: Bool { hotKey != nil }

    func arm(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease
        installHandlerIfNeeded()
        guard hotKey == nil else { return }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_Space),
            0,
            EventHotKeyID(signature: Self.signature, id: 1),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKey = ref
        } else {
            TalkbackLog.write("Leertaste nicht belegbar (\(status))")
        }
    }

    func disarm() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        onPress = nil
        onRelease = nil
    }

    private func handle(pressed: Bool) {
        if pressed { onPress?() } else { onRelease?() }
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let error = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &id
                )
                // Other hot keys (camera shortcuts) belong to GlobalHotkeyManager.
                guard error == noErr, id.signature == PushToTalkKey.signature else { return OSStatus(eventNotHandledErr) }
                let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
                let key = Unmanaged<PushToTalkKey>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in key.handle(pressed: pressed) }
                return noErr
            },
            types.count,
            &types,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        if status != noErr {
            TalkbackLog.write("Leertasten-Handler fehlt (\(status))")
        }
    }
}
```

In `UniFiCameraPopup/Services/GlobalHotkeyManager.swift`:
1. `private static let signature: OSType = 0x5543_504B // "UCPK"` ersetzen durch
```swift
    nonisolated private static let signature: OSType = 0x5543_504B // "UCPK"
```
2. Im Handler von `installHandlerIfNeeded()` nach `guard error == noErr else { return error }` einfügen:
```swift
                // The push-to-talk space bar (PushToTalkKey) has its own signature and handler.
                guard hotkeyID.signature == GlobalHotkeyManager.signature else { return OSStatus(eventNotHandledErr) }
```
Sonst schluckt dieser Handler (er antwortet immer `noErr`) das Drücken der Leertaste, falls er nach `PushToTalkKey` installiert wird.

- [ ] **Step 3: Talkback-Ablauf**

`UniFiCameraPopup/Services/TalkbackService.swift` – ein Ablauf-Token (`run`) sorgt dafür, dass eine Sitzung, die nach dem Loslassen oder nach einem neueren Start ankommt, nie live geht; nach dem Loslassen sendet der Streamer noch 0,3 s Stille (Encoder-Verzögerung) und wird bis `.finished` in `draining` gehalten:
```swift
import AppCore
import AVFoundation
import Combine
import Foundation
import ProtectKit

/// What is being sent to a camera.
enum TalkbackPurpose: Equatable {
    case talk
    case announcement(UUID)
}

/// The one talkback in progress (one microphone, one stream at a time).
struct TalkbackActivity: Equatable {
    enum Phase: Equatable {
        /// Permission, talkback session, file loading.
        case preparing
        /// Audio is flowing.
        case live
    }

    let entryId: UUID
    let purpose: TalkbackPurpose
    var phase: Phase
}

/// Error text for the popup of `entryId` (shown for a few seconds).
struct TalkbackNotice: Equatable {
    let id = UUID()
    let entryId: UUID
    let text: String
}

/// Push-to-talk and announcements: talkback session from Protect, microphone or file,
/// `TalkbackStreamer` to the camera. Every step is logged (TalkbackLog) for the hardware check.
@MainActor
final class TalkbackService: ObservableObject {
    static let shared = TalkbackService()

    @Published private(set) var activity: TalkbackActivity?
    @Published private(set) var notice: TalkbackNotice?

    private let microphone = MicrophoneCapture()
    private var current: TalkbackStreamer?
    /// Streams sending their last packets after the user stopped talking.
    private var draining: [ObjectIdentifier: TalkbackStreamer] = [:]
    /// Token of the start that may still go live; a newer start or a stop replaces it.
    private var run: UUID?
    private var spaceEntry: UUID?
    private var disarmAfterRelease = false

    private init() {}

    /// Sprechen and Ton abspielen exist only for Protect cameras with a speaker.
    func canTalk(_ mapping: WebhookMapping) -> Bool {
        guard SettingsStore.shared.isProtectConfigured, let cameraId = mapping.protectCameraId else { return false }
        return ProtectSession.shared.cameras.first { $0.id == cameraId }?.hasSpeaker == true
    }

    func isActive(entryId: UUID) -> Bool {
        activity?.entryId == entryId
    }

    // MARK: Push-to-talk

    /// Talk button pressed or space bar down.
    func pressTalk(entryId: UUID) {
        switch SoundStore.shared.settings.talkMode {
        case .hold:
            startTalking(entryId: entryId)
        case .toggle:
            if activity?.purpose == .talk, activity?.entryId == entryId {
                stopTalking()
            } else {
                startTalking(entryId: entryId)
            }
        }
    }

    /// Talk button or space bar released.
    func releaseTalk() {
        guard SoundStore.shared.settings.talkMode == .hold else { return }
        stopTalking()
    }

    /// VoiceOver press: always toggles.
    func toggleTalk(entryId: UUID) {
        if activity?.purpose == .talk, activity?.entryId == entryId {
            stopTalking()
        } else {
            startTalking(entryId: entryId)
        }
    }

    func startTalking(entryId: UUID) {
        if activity?.purpose == .talk { return }
        stopCurrent()
        guard let mapping = SettingsStore.shared.mapping(forEntry: entryId) else { return }
        activity = TalkbackActivity(entryId: entryId, purpose: .talk, phase: .preparing)
        let token = UUID()
        run = token
        Task { await runTalk(mapping, token: token) }
    }

    func stopTalking() {
        guard let activity, activity.purpose == .talk else { return }
        self.activity = nil
        run = nil
        // Released before the session was open: nothing is sent.
        guard activity.phase == .live else { return }
        microphone.stop()
        if let streamer = current {
            draining[ObjectIdentifier(streamer)] = streamer
            streamer.finish()
        }
        current = nil
        TalkbackLog.write("Talkback: Mikrofon zu")
    }

    private func runTalk(_ mapping: WebhookMapping, token: UUID) async {
        let entryId = mapping.entryId
        do {
            guard await MicrophoneCapture.requestPermission() else { throw TalkbackError.microphoneDenied }
            let target = try await openSession(for: mapping)
            guard run == token else { return }
            let streamer = try makeStreamer(target: target, entryId: entryId)
            streamer.start()
            current = streamer
            try microphone.start(
                deviceUID: SoundStore.shared.settings.microphoneUID,
                onBuffer: Self.forward(to: streamer)
            )
            activity?.phase = .live
            TalkbackLog.write("Talkback: Mikrofon offen für \(mapping.label)")
        } catch {
            report(error, entryId: entryId)
        }
    }

    // MARK: Announcements

    func play(_ announcement: Announcement, entryId: UUID) {
        if activity?.purpose == .talk { return }
        stopCurrent()
        guard let mapping = SettingsStore.shared.mapping(forEntry: entryId) else { return }
        guard let url = SoundStore.shared.audioURL(for: announcement) else {
            report(TalkbackError.audioFile("Datei fehlt"), entryId: entryId)
            return
        }
        let purpose = TalkbackPurpose.announcement(announcement.id)
        activity = TalkbackActivity(entryId: entryId, purpose: purpose, phase: .preparing)
        let token = UUID()
        run = token
        Task { await runAnnouncement(url: url, name: announcement.name, mapping: mapping, token: token) }
    }

    func stopPlayback() {
        guard let activity, case .announcement = activity.purpose else { return }
        self.activity = nil
        run = nil
        current?.stop()
        current = nil
    }

    private func runAnnouncement(url: URL, name: String, mapping: WebhookMapping, token: UUID) async {
        let entryId = mapping.entryId
        do {
            let loading = Task.detached { () throws -> PCMBox in PCMBox(buffer: try AnnouncementAudio.load(url)) }
            let target = try await openSession(for: mapping)
            let audio = try await loading.value.buffer
            guard run == token else { return }
            let streamer = try makeStreamer(target: target, entryId: entryId)
            streamer.start()
            streamer.append(audio)
            streamer.finish()
            current = streamer
            activity?.phase = .live
            TalkbackLog.write("Talkback: Ansage „\(name)“ an \(mapping.label), \(Announcement.lengthText(Double(audio.frameLength) / audio.format.sampleRate))")
        } catch {
            report(error, entryId: entryId)
        }
    }

    // MARK: Space bar (pointer over a popup that can talk)

    func pointerEntered(entryId: UUID) {
        spaceEntry = entryId
        disarmAfterRelease = false
        PushToTalkKey.shared.arm(
            onPress: { [weak self] in self?.spacePressed() },
            onRelease: { [weak self] in self?.spaceReleased() }
        )
    }

    func pointerExited(entryId: UUID) {
        guard spaceEntry == entryId else { return }
        // Still holding the space bar: keep it until released.
        if activity?.purpose == .talk, activity?.entryId == entryId, SoundStore.shared.settings.talkMode == .hold {
            disarmAfterRelease = true
            return
        }
        disarmSpace()
    }

    /// The popup closes: stop what it started, free the space bar.
    func popupClosed(entryId: UUID) {
        if activity?.entryId == entryId { stopCurrent() }
        if spaceEntry == entryId { disarmSpace() }
    }

    private func spacePressed() {
        guard let spaceEntry else { return }
        pressTalk(entryId: spaceEntry)
    }

    private func spaceReleased() {
        releaseTalk()
        if disarmAfterRelease { disarmSpace() }
    }

    private func disarmSpace() {
        PushToTalkKey.shared.disarm()
        spaceEntry = nil
        disarmAfterRelease = false
    }

    // MARK: Plumbing

    private func openSession(for mapping: WebhookMapping) async throws -> TalkbackTarget {
        guard let cameraId = mapping.protectCameraId, let client = ProtectSession.shared.client else {
            throw TalkbackError.notConnected
        }
        TalkbackLog.write("Talkback: Sitzung anfordern – \(mapping.label) (\(cameraId))")
        let session = try await client.talkbackSession(cameraId: cameraId)
        TalkbackLog.write("Talkback: Antwort \(session.raw)")
        let target = try TalkbackTarget.make(
            host: session.host,
            port: session.port,
            codecName: session.codec,
            sampleRate: session.samplingRate
        )
        TalkbackLog.write("Talkback: Ziel \(target.host):\(target.port), \(target.codec.rawValue), \(target.sampleRate) Hz, \(session.bitsPerSample) Bit")
        return target
    }

    private func makeStreamer(target: TalkbackTarget, entryId: UUID) throws -> TalkbackStreamer {
        var streamer: TalkbackStreamer?
        let made = try TalkbackStreamer(
            target: target,
            gain: SoundStore.shared.settings.gain,
            log: { TalkbackLog.write($0) },
            onEvent: { [weak self] event in
                Task { @MainActor in
                    guard let self, let streamer else { return }
                    self.handle(event, from: streamer, entryId: entryId)
                }
            }
        )
        streamer = made
        return made
    }

    private func handle(_ event: TalkbackStreamer.Event, from streamer: TalkbackStreamer, entryId: UUID) {
        switch event {
        case .ready:
            break
        case .finished:
            draining[ObjectIdentifier(streamer)] = nil
            if current === streamer {
                current = nil
                activity = nil
            }
        case .failed(let message):
            draining[ObjectIdentifier(streamer)] = nil
            guard current === streamer else { return }
            report(TalkbackError.network(message), entryId: entryId)
        }
    }

    /// Ends whatever runs now, at once.
    private func stopCurrent() {
        run = nil
        microphone.stop()
        current?.stop()
        current = nil
        activity = nil
    }

    private func report(_ error: Error, entryId: UUID) {
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        TalkbackLog.write("Talkback: Fehler – \(text)")
        if activity?.entryId == entryId {
            stopCurrent()
        }
        notice = TalkbackNotice(entryId: entryId, text: text)
    }

    private nonisolated static func forward(to streamer: TalkbackStreamer) -> @Sendable (AVAudioPCMBuffer) -> Void {
        { buffer in streamer.append(buffer) }
    }
}

/// Moves a decoded file from the loading task to the main actor (read-only afterwards).
private struct PCMBox: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}
```

- [ ] **Step 4: Mikrofon-Berechtigung**

In `UniFiCameraPopup/Info.plist` nach dem Eintrag `NSLocalNetworkUsageDescription` (Schlüssel + Text) einfügen:
```xml
	<key>NSMicrophoneUsageDescription</key>
	<string>Zum Sprechen über den Lautsprecher deiner Kamera: Solange du im Popup den Button oder die Leertaste hältst, geht dein Ton an die Kamera.</string>
```

- [ ] **Step 5: pbxproj**

PBXBuildFile:
```
		C31000000000000000000004 /* MicrophoneCapture.swift in Sources */ = {isa = PBXBuildFile; fileRef = C32000000000000000000004 /* MicrophoneCapture.swift */; };
		C31000000000000000000005 /* PushToTalkKey.swift in Sources */ = {isa = PBXBuildFile; fileRef = C32000000000000000000005 /* PushToTalkKey.swift */; };
		C31000000000000000000006 /* TalkbackService.swift in Sources */ = {isa = PBXBuildFile; fileRef = C32000000000000000000006 /* TalkbackService.swift */; };
```
PBXFileReference:
```
		C32000000000000000000004 /* MicrophoneCapture.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MicrophoneCapture.swift; sourceTree = "<group>"; };
		C32000000000000000000005 /* PushToTalkKey.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PushToTalkKey.swift; sourceTree = "<group>"; };
		C32000000000000000000006 /* TalkbackService.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = TalkbackService.swift; sourceTree = "<group>"; };
```
Gruppe `A40000000000000000000005 /* Services */`, am Ende der `children`: die drei `C32…0004/0005/0006`-Zeilen (`C32000000000000000000004 /* MicrophoneCapture.swift */,` usw.). Sources-Phase `A60000000000000000000002`, am Ende der `files`: die drei `C31…0004/0005/0006`-Zeilen (`C31000000000000000000004 /* MicrophoneCapture.swift in Sources */,` usw.).

- [ ] **Step 6: Lint, Build, Info.plist prüfen**

Run: `plutil -lint UniFiCameraPopup/Info.plist UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj` → zweimal `OK`
Run: Build-Befehl → `** BUILD SUCCEEDED **`
Run: `plutil -extract NSMicrophoneUsageDescription raw "$DD/Build/Products/Debug/UniFi Camera Popup.app/Contents/Info.plist"`
Expected: der Text aus Step 4.
Run: App starten, ein Kamera-Tastenkürzel drücken → Popup öffnet wie bisher (Hotkey-Änderung bricht nichts).

- [ ] **Step 7: Commit**

```bash
git add UniFiCameraPopup/Services/MicrophoneCapture.swift UniFiCameraPopup/Services/PushToTalkKey.swift UniFiCameraPopup/Services/TalkbackService.swift UniFiCameraPopup/Services/GlobalHotkeyManager.swift UniFiCameraPopup/Info.plist UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "feat(talkback): microphone capture, talkback flow with diagnosis and space-bar push-to-talk" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Einstellungen › Ton – bedienbar nach Vorlage

**Files:**
- Modify: `docs/design/einstellungen-ton.md` (Phase-3-Fassung, ganze Datei)
- Modify: `UniFiCameraPopup/Views/Design/DesignComponents.swift` (`VolumeTrack` → `VolumeSlider`)
- Create: `UniFiCameraPopup/Views/Settings/SoundTab.swift`
- Modify: `UniFiCameraPopup/Views/Settings/SoundAndRemoteTabs.swift` (Gerüst `SoundTab` entfällt)
- Modify: `project.pbxproj` (eine Datei)

**Interfaces:**
- Consumes: `Card`, `CardDivider`, `CardRow`, `SectionLabel`, `FieldButtonStyle`, `AccentButtonStyle`, `LinkButtonStyle`, `TokenSegmented`, `TokenTextField`, `PopUpField`, `TemplateIcon.play`, `Tokens` (Phase 2, Task 3); `SettingsRootView` zeigt `SoundTab()` (Phase 2, Task 5); `SoundStore`, `PreviewPlayer` (Task 5); `MicrophoneCapture.inputDevices()`, `.defaultInputDevice()`, `AudioInputDevice` (Task 6); `Announcement`, `SoundSettings`, `TalkMode`, `AnnouncementAudio`, `TalkbackError` (Task 1/4).
- Produces:
  - `struct VolumeSlider: View` – `init(value: Binding<Double>, label: String)`
  - `@MainActor enum SoundFilePicker` – `static func chooseMP3() -> URL?`
  - `struct SoundTab: View` (gleicher Name wie das Phase-2-Gerüst, `SettingsRootView` bleibt unverändert)

- [ ] **Step 1: Spezifikation ablegen (vor dem Code)**

`docs/design/einstellungen-ton.md` komplett ersetzen durch (Quelle: `Einstellungen.dc.html` Zeilen 143–170 und `soundRows` in `renderVals()`; Abweichungen 1, 2, 8–15 dieses Plans):
```markdown
# Einstellungen › Ton (Vorlage S5)

Kopf wie Allgemein, Titel „Ton & Sprechen“, Reiter „Ton“ aktiv.
Inhalt Innenabstand 14/40, Abstand 10, Schrift 13. Scrollt, wenn der Inhalt höher als das Fenster ist.
1. Abschnitt Abstand 5: „Ansagen für „Ton abspielen““ 11/600 `muted`. Karte Radius 10, `group`, Rand 1 `border`:
   Zeilen Abstand 10, Innenabstand 6/12, Trennlinie 1 `border` unter jeder Ansage:
   Play-Knopf 22 rund `accSoft`, Dreieck 9 (gefüllt) `accText` („Probehören“ am Mac, zweiter Klick stoppt) ·
   Name 500, füllt, einzeilig · Länge 11 `muted` tabellarisch („0:03“, auf Sekunden gerundet) ·
   Badge 10/700 Innenabstand 2/6 Radius 4 (MP3: `btn2`/`muted`; KI-STIMME: `accSoft`/`accText`).
   Ausgewählte Zeile Fläche `accSoft`; Klick auf die Zeile wählt aus.
   Kontextmenü (nativ): „Umbenennen …“, „Löschen“ – beide mit nativem Dialog.
   Mitgeliefert: „Bin gleich da“ 0:03 KI-STIMME · „Paket bitte abstellen“ 0:04 KI-STIMME.
   Danach Zeile Abstand 14, Innenabstand 6/12, 12: Links „MP3 hinzufügen …“ · „Ansage aus Text …“
   (`accText`, unterstrichen).
2. Editor-Karte (nur mit ausgewählter Ansage): Abstand 8, Innenabstand 10/12, Radius 10, `group`, Rand 1 `accent`:
   - „„<Name>““ 600, füllt | Segment „MP3-Datei“ · „KI-Stimme“
   KI-Stimme:
   - Eingabe „Text der Ansage“ 13, Innenabstand 5/8, Radius 6
   - Zeile Abstand 8: „Stimme“ 12 `muted` · Auswahlfeld · Freiraum · „Anhören“ (Feld-Button 12, 3/10) ·
     „Übernehmen“ (12/600, 3/10, `accent`, weiß). Stimmen: „Thorsten · mitgeliefert“ (nur mitgelieferte
     Ansage mit Originalwortlaut), dann deutsche macOS-Stimmen „Anna (Premium) · macOS“,
     „<Name> (Erweitert) · macOS“, „<Name> · macOS“.
   - „Wird auf diesem Mac erzeugt – ohne Internet, ohne Konto.“ 11 `muted`
   MP3-Datei:
   - Zeile Abstand 8: „MP3-Datei · 0:03“ bzw. „Noch keine Datei gewählt.“ 13 `muted` · Freiraum ·
     „Datei wählen …“ · „Anhören“ (Feld-Buttons 12, 3/10)
   - „MP3 bis 5 Minuten. Die Datei wird in die App kopiert und bleibt auf diesem Mac.“ 11 `muted`
   Fehler: eine Zeile 11 System-Orange unter dem Hinweis.
3. Karte Radius 10, Zeilen 10/14, Trennlinie 1 `border`:
   - „Mikrofon“ | Auswahlfeld mit den Eingabegeräten (Core-Audio-Name, z. B. „MacBook Pro-Mikrofon“)
   - „Sprechen“ | Segment „Leertaste halten“ · „Umschalten“
   - „Lautstärke an der Kamera“ | Regler: Spur 180 × 4 Radius 2 `toggleOff`, Füllung bis zum Wert `accent`,
     Knopf 16 weiß mittig auf dem Ende der Füllung, Schatten 0 1 3 rgba(0,0,0,.35).
     Vorlagenstellung 2/3 (Füllung 120, Knopf x 112) = unveränderte Lautstärke, ganz rechts × 1,5.
```

- [ ] **Step 2: Regler statt Gerüst-Spur**

`VolumeTrack` (nur im Phase-2-Gerüst benutzt) entfernen:
```bash
python3 - <<'EOF'
import pathlib
p = pathlib.Path("UniFiCameraPopup/Views/Design/DesignComponents.swift")
s = p.read_text()
start = s.index("/// Static volume slider of the Ton scaffold")
end = s.index("\n}\n", s.index("struct VolumeTrack: View {")) + 3
p.write_text(s[:start].rstrip() + "\n" + s[end:])
EOF
grep -c "VolumeTrack" UniFiCameraPopup/Views/Design/DesignComponents.swift   # Expected: 0
```
Ans Ende von `DesignComponents.swift` anhängen (die Datei importiert `AppCore` und `SwiftUI` bereits):
```swift
/// Slider of Einstellungen › Ton: track 180 × 4 radius 2 `toggleOff`, fill `accent` up to the value,
/// knob 16 white centered on the fill end, shadow 0 1 3 rgba(0,0,0,.35). 2/3 = template (fill 120, knob x 112).
struct VolumeSlider: View {
    @Binding var value: Double
    let label: String
    private let width: CGFloat = 180

    var body: some View {
        let clamped = min(1, max(0, value))
        let fill = CGFloat(clamped) * width
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(Tokens.toggleOff.color).frame(width: width, height: 4)
            RoundedRectangle(cornerRadius: 2).fill(Tokens.accent.color).frame(width: fill, height: 4)
            Circle()
                .fill(Color.white)
                .frame(width: 16, height: 16)
                .shadow(color: Color.black.opacity(0.35), radius: 1.5, y: 1)
                .offset(x: min(width - 16, max(0, fill - 8)))
        }
        .frame(width: width, height: 16)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
            value = Double(min(1, max(0, drag.location.x / width)))
        })
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((clamped * 100).rounded())) Prozent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, clamped + 0.05)
            case .decrement: value = max(0, clamped - 0.05)
            @unknown default: break
            }
        }
    }
}
```

- [ ] **Step 3: Reiter Ton**

`UniFiCameraPopup/Views/Settings/SoundTab.swift`:
```swift
import AppCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Open panel for "MP3 hinzufügen …" (settings and popup).
@MainActor
enum SoundFilePicker {
    static func chooseMP3() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "MP3 hinzufügen"
        panel.prompt = "Hinzufügen"
        panel.allowedContentTypes = [.mp3]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Einstellungen › Ton (docs/design/einstellungen-ton.md).
struct SoundTab: View {
    @ObservedObject private var store = SoundStore.shared
    @ObservedObject private var preview = PreviewPlayer.shared
    @State private var selectedId: UUID?
    @State private var draftKind: Announcement.Kind = .speech
    @State private var draftText = ""
    @State private var draftVoice: String?
    @State private var busy = false
    @State private var errorText: String?
    @State private var devices: [AudioInputDevice] = []

    private var selected: Announcement? {
        selectedId.flatMap { store.settings.announcement(id: $0) }
    }

    private var trimmedDraft: String {
        draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                announcementList
                if let selected {
                    editor(selected)
                }
                deviceCard
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 40)
        }
        .onAppear {
            devices = MicrophoneCapture.inputDevices()
            if selected == nil {
                select(store.settings.announcements.first)
            }
        }
        .onChange(of: draftText) { _ in
            // The bundled voice can only say the bundled wording.
            if draftVoice == nil, let selected, !SoundSettings.offersBundledVoice(for: selected, text: draftText) {
                draftVoice = AnnouncementAudio.voices().first?.identifier
            }
        }
    }

    // MARK: List

    private var announcementList: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionLabel(text: "Ansagen für „Ton abspielen“")
            Card {
                ForEach(store.settings.announcements) { sound in
                    row(sound)
                    CardDivider()
                }
                HStack(spacing: 14) {
                    Button("MP3 hinzufügen …", action: addFile).buttonStyle(LinkButtonStyle())
                    Button("Ansage aus Text …", action: addText).buttonStyle(LinkButtonStyle())
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
            }
        }
    }

    private func row(_ sound: Announcement) -> some View {
        HStack(spacing: 10) {
            Button { togglePreview(sound) } label: {
                ZStack {
                    Circle().fill(Tokens.accSoft.color).frame(width: 22, height: 22)
                    TemplateIcon.play.image(size: 9).foregroundStyle(Tokens.accText.color)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(preview.playingId == sound.id ? "Probehören beenden" : "Probehören")
            Text(sound.name)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(Announcement.lengthText(sound.duration))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Tokens.muted.color)
            Text(sound.badge)
                .font(.system(size: 10, weight: .bold))
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
                .foregroundStyle(sound.kind == .file ? Tokens.muted.color : Tokens.accText.color)
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill(sound.kind == .file ? Tokens.btn2.color : Tokens.accSoft.color))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(sound.id == selectedId ? Tokens.accSoft.color : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { select(sound) }
        .contextMenu {
            Button("Umbenennen …") { rename(sound) }
            Button("Löschen") { delete(sound) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(sound.id == selectedId ? .isSelected : [])
    }

    // MARK: Editor

    private func editor(_ sound: Announcement) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("„\(sound.name)“")
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TokenSegmented(
                    selection: $draftKind,
                    options: [(value: Announcement.Kind.file, title: "MP3-Datei"), (value: Announcement.Kind.speech, title: "KI-Stimme")]
                )
            }
            if draftKind == .speech {
                TokenTextField(placeholder: "Text der Ansage", text: $draftText, fontSize: 13, vertical: 5, horizontal: 8, radius: 6)
                    .accessibilityLabel("Text der Ansage")
                HStack(spacing: 8) {
                    Text("Stimme").font(.system(size: 12)).foregroundStyle(Tokens.muted.color)
                    PopUpField(selection: $draftVoice, options: voiceOptions(for: sound))
                    Spacer()
                    Button("Anhören") { listen(sound) }
                        .buttonStyle(FieldButtonStyle())
                        .disabled(busy || trimmedDraft.isEmpty)
                    Button("Übernehmen") { apply(sound) }
                        .buttonStyle(AccentButtonStyle(fontSize: 12, vertical: 3, horizontal: 10))
                        .disabled(busy || !canApply(sound))
                }
                Text("Wird auf diesem Mac erzeugt – ohne Internet, ohne Konto.")
                    .font(.system(size: 11))
                    .foregroundStyle(Tokens.muted.color)
            } else {
                HStack(spacing: 8) {
                    Text(sound.kind == .file ? "MP3-Datei · \(Announcement.lengthText(sound.duration))" : "Noch keine Datei gewählt.")
                        .foregroundStyle(Tokens.muted.color)
                        .lineLimit(1)
                    Spacer()
                    Button("Datei wählen …") { chooseFile(for: sound) }
                        .buttonStyle(FieldButtonStyle())
                    Button("Anhören") { togglePreview(sound) }
                        .buttonStyle(FieldButtonStyle())
                        .disabled(sound.kind != .file)
                }
                Text("MP3 bis 5 Minuten. Die Datei wird in die App kopiert und bleibt auf diesem Mac.")
                    .font(.system(size: 11))
                    .foregroundStyle(Tokens.muted.color)
            }
            if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Tokens.group.color))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Tokens.accent.color, lineWidth: 1))
    }

    private func voiceOptions(for sound: Announcement) -> [(value: String?, title: String)] {
        var options: [(value: String?, title: String)] = []
        if SoundSettings.offersBundledVoice(for: sound, text: draftText) {
            options.append((value: nil, title: SoundSettings.bundledVoiceLabel))
        }
        options += AnnouncementAudio.voices().map { (value: Optional($0.identifier), title: AnnouncementAudio.label(for: $0)) }
        if options.isEmpty {
            options.append((value: nil, title: "Keine deutsche Stimme installiert"))
        }
        return options
    }

    private func canApply(_ sound: Announcement) -> Bool {
        guard !trimmedDraft.isEmpty else { return false }
        guard draftVoice != nil || SoundSettings.offersBundledVoice(for: sound, text: draftText) else { return false }
        return sound.kind != .speech || trimmedDraft != sound.text || draftVoice != sound.voiceIdentifier
    }

    // MARK: Microphone, mode, volume

    private var deviceCard: some View {
        Card {
            CardRow(title: "Mikrofon") {
                PopUpField(selection: microphone, options: microphoneOptions)
            }
            CardDivider()
            CardRow(title: "Sprechen") {
                TokenSegmented(
                    selection: $store.settings.talkMode,
                    options: TalkMode.allCases.map { (value: $0, title: $0.label) }
                )
            }
            CardDivider()
            CardRow(title: "Lautstärke an der Kamera") {
                VolumeSlider(value: $store.settings.cameraVolume, label: "Lautstärke an der Kamera")
            }
        }
    }

    /// Stored UID if connected, else the system default (also when the stored one is unplugged).
    private var microphone: Binding<String> {
        Binding(
            get: {
                if let uid = store.settings.microphoneUID, devices.contains(where: { $0.uid == uid }) { return uid }
                return MicrophoneCapture.defaultInputDevice()?.uid ?? ""
            },
            set: { store.settings.microphoneUID = $0.isEmpty ? nil : $0 }
        )
    }

    private var microphoneOptions: [(value: String, title: String)] {
        devices.isEmpty ? [(value: "", title: "Kein Mikrofon")] : devices.map { (value: $0.uid, title: $0.name) }
    }

    // MARK: Actions

    private func select(_ sound: Announcement?) {
        selectedId = sound?.id
        errorText = nil
        draftKind = sound?.kind ?? .speech
        draftText = sound?.text ?? ""
        draftVoice = sound?.voiceIdentifier
        if let sound, sound.kind == .speech, sound.voiceIdentifier == nil,
           !SoundSettings.offersBundledVoice(for: sound, text: sound.text) {
            draftVoice = AnnouncementAudio.voices().first?.identifier
        }
    }

    private func addFile() {
        guard let url = SoundFilePicker.chooseMP3() else { return }
        do {
            select(try store.addFile(from: url))
        } catch {
            errorText = message(error)
        }
    }

    private func addText() {
        select(store.addText())
    }

    private func chooseFile(for sound: Announcement) {
        guard let url = SoundFilePicker.chooseMP3() else { return }
        do {
            try store.replaceWithFile(id: sound.id, from: url)
            select(store.settings.announcement(id: sound.id))
        } catch {
            errorText = message(error)
        }
    }

    private func apply(_ sound: Announcement) {
        busy = true
        errorText = nil
        let text = draftText
        let voice = draftVoice
        Task { @MainActor in
            do {
                try await store.applySpeech(id: sound.id, text: text, voiceIdentifier: voice)
                select(store.settings.announcement(id: sound.id))
            } catch {
                errorText = message(error)
            }
            busy = false
        }
    }

    private func listen(_ sound: Announcement) {
        busy = true
        errorText = nil
        let text = trimmedDraft
        let voice = draftVoice
        Task { @MainActor in
            do {
                let buffer = try await store.previewBuffer(for: sound, text: text, voiceIdentifier: voice)
                preview.play(buffer, id: sound.id)
            } catch {
                errorText = message(error)
            }
            busy = false
        }
    }

    private func togglePreview(_ sound: Announcement) {
        if preview.playingId == sound.id {
            preview.stop()
            return
        }
        guard let url = store.audioURL(for: sound) else {
            errorText = TalkbackError.audioFile("Datei fehlt").errorDescription
            return
        }
        do {
            preview.play(try AnnouncementAudio.load(url), id: sound.id)
        } catch {
            errorText = message(error)
        }
    }

    private func rename(_ sound: Announcement) {
        let alert = NSAlert()
        alert.messageText = "Ansage umbenennen"
        let field = NSTextField(string: sound.name)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Umbenennen")
        alert.addButton(withTitle: "Abbrechen")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.rename(id: sound.id, to: field.stringValue)
    }

    private func delete(_ sound: Announcement) {
        let alert = NSAlert()
        alert.messageText = "„\(sound.name)“ löschen?"
        alert.informativeText = "Die Ansage verschwindet aus allen Popups."
        alert.addButton(withTitle: "Löschen")
        alert.addButton(withTitle: "Abbrechen")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if preview.playingId == sound.id { preview.stop() }
        store.remove(id: sound.id)
        if selectedId == sound.id {
            select(store.settings.announcements.first)
        }
    }

    private func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
```

Gerüst entfernen (das bisherige `SoundTab` in `SoundAndRemoteTabs.swift`; `RemoteTab` bleibt):
```bash
python3 - <<'EOF'
import pathlib
p = pathlib.Path("UniFiCameraPopup/Views/Settings/SoundAndRemoteTabs.swift")
s = p.read_text()
start = s.index("/// Einstellungen › Ton –")
end = s.index("/// Einstellungen › Unterwegs –")
p.write_text(s[:start] + s[end:])
EOF
grep -c "struct SoundTab\|VolumeTrack" UniFiCameraPopup/Views/Settings/SoundAndRemoteTabs.swift   # Expected: 0
grep -c "struct RemoteTab" UniFiCameraPopup/Views/Settings/SoundAndRemoteTabs.swift               # Expected: 1
```

- [ ] **Step 4: pbxproj**

PBXBuildFile `C31000000000000000000007 /* SoundTab.swift in Sources */ = {isa = PBXBuildFile; fileRef = C32000000000000000000007 /* SoundTab.swift */; };`
PBXFileReference `C32000000000000000000007 /* SoundTab.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SoundTab.swift; sourceTree = "<group>"; };`
In der Gruppe `A40000000000000000000071 /* Settings */` nach `A20000000000000000000078 /* SoundAndRemoteTabs.swift */,`: `C32000000000000000000007 /* SoundTab.swift */,`. Sources-Phase am Ende der `files`: `C31000000000000000000007 /* SoundTab.swift in Sources */,`.

- [ ] **Step 5: Lint und Build**

`plutil -lint …` → OK; Build → `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Sicht- und Funktionsprüfung gegen `docs/design/einstellungen-ton.md`** (Hell und Dunkel über Allgemein › Erscheinungsbild)

1. Reiter „Ton“: Reihenfolge, Texte, Abstände und Farben wie in der Spezifikation; „Bin gleich da“ und „Paket bitte abstellen“ mit 0:03/0:04 und KI-STIMME; erste Zeile ausgewählt.
2. Play-Knopf spielt die Aufnahme am Mac, zweiter Klick stoppt; ein Klick auf eine andere Zeile stoppt die alte.
3. „Ansage aus Text …“ → neue Zeile „Neue Ansage“, ausgewählt, Editor „KI-Stimme“ mit leerem Feld; Text „Paket bitte vor die Tür.“, Stimme wählen, „Anhören“ spielt am Mac, „Übernehmen“ → Zeile heißt „Paket bitte vor die Tür“, Länge stimmt, eine `.caf`-Datei liegt in `~/Library/Application Support/UniFi Camera Popup/Sounds/`.
4. Bei „Bin gleich da“: Stimme „Thorsten · mitgeliefert“; ein Zeichen im Text ändern → Stimme springt auf eine macOS-Stimme; Text zurücksetzen → Thorsten wieder wählbar; „Übernehmen“ mit Thorsten benutzt wieder die Aufnahme (keine neue Datei).
5. „MP3 hinzufügen …“ mit einer MP3 über 5 Minuten → orange „Die Datei ist länger als 5 Minuten.“; kurze MP3 → neue Zeile mit Badge MP3 und Länge.
6. Segment „MP3-Datei“ bei einer Text-Ansage → „Noch keine Datei gewählt.“; „Datei wählen …“ macht daraus eine MP3-Ansage.
7. Kontextmenü „Umbenennen …“ / „Löschen“; nach Löschen ist die Datei aus dem Sounds-Ordner weg.
8. Mikrofon-Liste zeigt die Eingabegeräte; Auswahl, Sprech-Modus und Lautstärke überleben einen Neustart (`defaults read com.snackbits.UniFiCameraPopup unifi.camera.popup.sound` zeigt Daten).
9. Mit fünf Ansagen scrollt der Inhalt; die Reiterleiste bleibt stehen.

- [ ] **Step 7: Commit**

```bash
git add docs/design/einstellungen-ton.md UniFiCameraPopup/Views/Design/DesignComponents.swift UniFiCameraPopup/Views/Settings/SoundTab.swift UniFiCameraPopup/Views/Settings/SoundAndRemoteTabs.swift UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "feat(settings): working Sound tab with announcements, voices, microphone and volume" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Popup – „Ton abspielen“, „Leertaste halten“, Ansagen-Menü, Hinweis

**Files:**
- Modify: `docs/design/popup.md` (Phase-3-Fassung, ganze Datei)
- Create: `UniFiCameraPopup/Assets.xcassets/Icons/mic.imageset`, `soundPlay.imageset`
- Modify: `UniFiCameraPopup/Views/Design/DesignComponents.swift` (`TemplateIcon`)
- Create: `UniFiCameraPopup/Views/Popup/PopupTalkViews.swift`
- Modify: `UniFiCameraPopup/Views/Popup/PopupOverlayViews.swift` (`PopupOverlayContent.talk`, `ActionPillView(actions:leadingViews:)`)
- Modify: `UniFiCameraPopup/Views/PopupWindow.swift` (Talk-Steuerung, Auto-Schließen)
- Modify: `UniFiCameraPopup/Services/PopupController.swift` (`makeAlarmWindow`)
- Modify: `project.pbxproj` (eine Datei)

**Interfaces:**
- Consumes: `CircleIconButton(icon:iconSize:diameter:fill:tint:label:)`, `NSView.cgColor(_:)`, `PopupOverlayContent`, `ActionPillView`, `FirstMouseButton`, `PopupWindow.setupOverlay(in:)`, `muteMenu` (Phase 2, Task 7); `Tokens`, `ThemeColor`, `TemplateIcon.nsImage(size:)` (Phase 2, Task 3); `TalkbackService`, `TalkbackActivity`, `TalkbackNotice` (Task 6); `SoundStore` (Task 5); `SoundFilePicker` (Task 7); `Announcement.menuTag` (Task 4).
- Produces:
  - `TemplateIcon.mic`, `TemplateIcon.soundPlay`
  - `struct PopupTalkContent { entryId: UUID }`; `PopupOverlayContent.talk: PopupTalkContent?` (Standard `nil`)
  - `ActionPillView(actions: [CameraAction], leadingViews: [NSView] = [])`
  - `final class TalkButtonView: NSView` (`onPress`, `onRelease`, `onAccessibilityPress`, `update(title:busy:)`), `final class SoundMenuRow`, `final class SoundMenuView` (`onPick`, `onAdd`, `reload(_:)`), `final class PopupNoticeView` (`show(_:)`)
  - `@MainActor final class PopupTalkControls` – `init(content: PopupTalkContent)`, `soundButton`, `talkButton`, `install(in:above:)`, `closeMenu() -> Bool`, `isBusy`, `pointerInside(_:)`, `popupClosed()`

- [ ] **Step 1: Spezifikation ablegen (vor dem Code)**

`docs/design/popup.md` komplett ersetzen durch (Quelle: `Main.dc.html` Zeilen 142–165, `sounds` in `renderVals()`; Abweichungen 3–7, 16):
```markdown
# Popup (Vorlage Main 8, „Popup mit Sprechen & Ton“, Popup aus B)

Fenster randlos, Radius 12, nativer Schatten, Ring 1 `popupRing`. Größe pro Kamera
(Vorlage: 470 × 300). Hintergrund Vorschaubild/Livebild.
1. Chip oben links (10/10): Kapsel `overlay`, Innenabstand 4/9, 11/600 weiß:
   „Klingel · Haustür · 10:41“ = Ereignis-Art · Kameraname · HH:mm (ohne Art: „Haustür · 10:41“).
2. Oben rechts, beide 24 rund `overlay`, Symbol weiß:
   - Schließen: rechts 10, oben 10, X 11 (Strich 2,6)
   - Stummschalten: rechts 40, oben 10, Glocke durchgestrichen 13 (Strich 2)
3. Stumm-Menü (offen nach Klick auf Stummschalten): rechts 10, oben 40, Breite 190 + 2×5,
   Radius 9, Fläche `menu`, Schatten 0 10 24 rgba(0,0,0,.4), Ring 1 `mainBorder`, Schrift 12 `fg`:
   Kopf „Haustür stummschalten“ 11/600 `muted`, Innenabstand 4/8; Einträge Innenabstand 5/8,
   Radius 5: „für 15 Minuten“, „für 1 Stunde“ (Texte aus den eingestellten Dauern);
   Eintrag unter der Maus `accent` + weiß.
4. Leiste unten mittig (unten 12): Kapsel `pill`, Innenabstand 6, Abstand 8, Schatten 0 6 18
   rgba(0,0,0,.3), Ring 1 `pillRing`, Inhalt senkrecht mittig. Reihenfolge:
   „Ton abspielen“ · „Leertaste halten“ · Buttons des Nutzers. Die ersten beiden nur bei
   Protect-Kameras mit Lautsprecher; ohne alles keine Leiste.
   - „Ton abspielen“: Kreis 34 `pillBtn`, Lautsprecher 16 (Strich 1,8) `pillFg`, Tooltip „Ton abspielen“.
     Während eine Ansage aus diesem Popup läuft: Fläche `accent`, Symbol weiß, Tooltip „Ansage stoppen“, Klick stoppt.
   - „Leertaste halten“: 40 hoch, Innenabstand 0/18, Radius 20, `accent`, 12/700 weiß,
     Mikrofon 16 (Strich 2) + 6 + Text. Texte: Ruhe „Leertaste halten“ (Modus Halten) bzw. „Sprechen“
     (Umschalten); Aufbau „Verbinde …“ (Deckkraft 70 %); senden „Spricht …“ (Halten) bzw. „Beenden“ (Umschalten).
     Maustaste gedrückt halten = sprechen. Die Leertaste wirkt, solange der Zeiger über dem Popup ist.
   - Buttons des Nutzers: Kreis 34 `pillBtn`, Symbol 16 (Strich 1,8) `pillFg` (Tür/Lampe/Haus/Blitz), Tooltip = Titel.
5. Ansagen-Menü (offen nach Klick auf „Ton abspielen“): Unterkante auf der Oberkante der Leiste
   (Vorlage: unten 64), linke Kante 45 vor „Ton abspielen“ (Vorlage: links 70), mindestens 10 vom Rand.
   Breite 180 + 2×5, Radius 9, `menu`, Schatten 0 10 24 rgba(0,0,0,.4), Ring 1 `mainBorder`, Schrift 12 `fg`:
   je Ansage eine Zeile, Innenabstand 5/8, Radius 5: Name links, rechts Art 10 `muted`
   („MP3“ / „KI-Stimme“), Abstand 8; danach Trennlinie 1 `mainBorder`, Rand 3/4; „MP3 hinzufügen …“
   `accText`, Innenabstand 5/8. Zeile unter der Maus `accent` + weiß. Klick spielt an der Kamera ab.
6. Hinweis bei Fehlern: Kapsel `overlay`, Innenabstand 4/9, 11/600 weiß, mittig 8 über der Leiste,
   höchstens Popup-Breite − 20 (gekürzt, voller Text als Tooltip), 6 s sichtbar, Klicks gehen durch.
7. Ein Klick neben ein offenes Menü schließt erst das Menü. Während gesprochen oder eine Ansage
   gesendet wird, schließt sich das Popup nicht automatisch.
```

- [ ] **Step 2: Symbole aus der Vorlage**

Pfade 1:1 aus `Main.dc.html` Zeile 156 („Ton abspielen“, Strich 1,8) und Zeile 157 (Mikrofon, Strich 2). Aus dem Worktree-Wurzelverzeichnis:
```bash
ICONS=UniFiCameraPopup/Assets.xcassets/Icons
while IFS='|' read -r name width body; do
  [ -z "$name" ] && continue
  dir="$ICONS/$name.imageset"
  mkdir -p "$dir"
  attrs="fill=\"none\" stroke=\"#000000\" stroke-width=\"$width\" stroke-linecap=\"round\" stroke-linejoin=\"round\""
  printf '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" %s>%s</svg>\n' "$attrs" "$body" > "$dir/$name.svg"
  printf '{\n  "images" : [ { "filename" : "%s.svg", "idiom" : "universal" } ],\n  "info" : { "author" : "xcode", "version" : 1 },\n  "properties" : { "preserves-vector-representation" : true, "template-rendering-intent" : "template" }\n}\n' "$name" > "$dir/Contents.json"
done <<'EOF'
mic|2|<path d="M12 3a3 3 0 0 0-3 3v6a3 3 0 0 0 6 0V6a3 3 0 0 0-3-3z"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/>
soundPlay|1.8|<path d="M4 9h4l5-4v14l-5-4H4z"/><path d="M16.5 8.5a5 5 0 0 1 0 7"/>
EOF
ls "$ICONS" | grep -c "imageset"   # Expected: 19
```
In `DesignComponents.swift` im `enum TemplateIcon` nach `case actionDoor, actionBulb, actionHouse, actionBolt` die Zeile einfügen:
```swift
    case mic, soundPlay
```

- [ ] **Step 3: Popup-Bausteine für Sprechen und Ton**

`UniFiCameraPopup/Views/Popup/PopupTalkViews.swift` (Prüfgrundlage `docs/design/popup.md` Punkte 4–7):
```swift
import AppCore
import AppKit
import Combine

/// Popup of a camera that can talk (Protect camera with speaker).
struct PopupTalkContent {
    let entryId: UUID
}

/// "Leertaste halten": capsule 40 high, padding 0/18, radius 20, `accent`, 12 pt bold white,
/// mic 16 + 6 + label. Pressing starts, releasing ends (hold); the service decides for toggle mode.
final class TalkButtonView: NSView {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onAccessibilityPress: (() -> Void)?
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")

    init(title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 20

        icon.image = TemplateIcon.mic.nsImage(size: 16)
        icon.contentTintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 40),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        update(title: title, busy: false)
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `busy` while the talkback session is being opened (70 %).
    func update(title: String, busy: Bool) {
        label.stringValue = title
        toolTip = title
        setAccessibilityLabel(title)
        alphaValue = busy ? 0.7 : 1
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onPress?() }
    override func mouseUp(with event: NSEvent) { onRelease?() }

    override func accessibilityPerformPress() -> Bool {
        onAccessibilityPress?()
        return true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        layer?.backgroundColor = cgColor(Tokens.accent)
    }
}

/// One announcement in the popup's sound menu: name left, tag (10 pt `muted`) right, gap 8,
/// padding 5/8, radius 5; `accent` with white text under the mouse (like the mute menu).
final class SoundMenuRow: NSView {
    var onClick: (() -> Void)?
    private let title = NSTextField(labelWithString: "")
    private let tagLabel = NSTextField(labelWithString: "")
    private let titleColor: ThemeColor
    private var hovering = false {
        didSet { applyColors() }
    }

    init(name: String, tag tagText: String?, color: ThemeColor = Tokens.fg) {
        titleColor = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 5

        title.stringValue = name
        title.font = .systemFont(ofSize: 12)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)
        var constraints = [
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            title.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ]
        if let tagText {
            tagLabel.stringValue = tagText
            tagLabel.font = .systemFont(ofSize: 10)
            tagLabel.translatesAutoresizingMaskIntoConstraints = false
            tagLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            addSubview(tagLabel)
            constraints += [
                tagLabel.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 8),
                tagLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                tagLabel.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
            ]
        } else {
            constraints.append(title.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8))
        }
        NSLayoutConstraint.activate(constraints)
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(tagText.map { "\(name), \($0)" } ?? name)
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        layer?.backgroundColor = hovering ? cgColor(Tokens.accent) : NSColor.clear.cgColor
        title.textColor = hovering ? .white : titleColor.nsColor
        tagLabel.textColor = hovering ? NSColor.white.withAlphaComponent(0.85) : Tokens.muted.nsColor
    }
}

/// Sound menu above "Ton abspielen": 180 + 2 × 5 wide, radius 9, `menu`, ring 1 `mainBorder`,
/// shadow 0 10 24 rgba(0,0,0,.4); announcements, separator (1, margin 3/4), "MP3 hinzufügen …" `accText`.
final class SoundMenuView: NSView {
    var onPick: ((Announcement) -> Void)?
    var onAdd: (() -> Void)?
    private let stack = NSStackView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.masksToBounds = false
        layer?.borderWidth = 1
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.4
        layer?.shadowRadius = 12
        layer?.shadowOffset = CGSize(width: 0, height: -10)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.menu)
        setAccessibilityLabel("Ton abspielen")
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Rebuilt on every opening, so new announcements appear at once.
    func reload(_ announcements: [Announcement]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for announcement in announcements {
            let row = SoundMenuRow(name: announcement.name, tag: announcement.menuTag)
            row.onClick = { [weak self] in self?.onPick?(announcement) }
            add(row)
        }
        if !announcements.isEmpty {
            let separator = SeparatorView()
            stack.addArrangedSubview(separator)
            stack.setCustomSpacing(0, after: separator)
            NSLayoutConstraint.activate([separator.widthAnchor.constraint(equalToConstant: 180)])
        }
        let add = SoundMenuRow(name: "MP3 hinzufügen …", tag: nil, color: Tokens.accText)
        add.onClick = { [weak self] in self?.onAdd?() }
        self.add(add)
    }

    private func add(_ row: NSView) {
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalToConstant: 180).isActive = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        layer?.backgroundColor = cgColor(Tokens.menu)
        layer?.borderColor = cgColor(Tokens.mainBorder)
    }
}

/// 1 pt `mainBorder` line with 3 pt above/below and 4 pt left/right (template `margin: 3px 4px`).
private final class SeparatorView: NSView {
    private let line = NSView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        line.wantsLayer = true
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 7),
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            line.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            line.centerYAnchor.constraint(equalTo: centerYAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
        ])
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        line.layer?.backgroundColor = cgColor(Tokens.mainBorder)
    }
}

/// Error line above the pill: capsule `overlay`, padding 4/9, 11 pt semibold white, 6 s. Click-through.
final class PopupNoticeView: NSView {
    private let label = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = Tokens.overlay.light.nsColor.cgColor
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ text: String) {
        label.stringValue = text
        toolTip = text
        setAccessibilityLabel(text)
        isHidden = false
        NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [.announcement: text])
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.isHidden = true }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }
}

/// "Ton abspielen" + "Leertaste halten" of one popup, wired to `TalkbackService`.
@MainActor
final class PopupTalkControls {
    let soundButton: CircleIconButton
    let talkButton: TalkButtonView
    private let soundMenu = SoundMenuView()
    private let notice = PopupNoticeView()
    private let entryId: UUID
    private var cancellables: Set<AnyCancellable> = []

    init(content talk: PopupTalkContent) {
        entryId = talk.entryId
        soundButton = CircleIconButton(
            icon: .soundPlay,
            iconSize: 16,
            diameter: 34,
            fill: Tokens.pillBtn,
            tint: Tokens.pillFg,
            label: "Ton abspielen"
        )
        talkButton = TalkButtonView(title: Self.idleTitle)
        soundMenu.isHidden = true

        soundButton.target = self
        soundButton.action = #selector(soundTapped)
        let service = TalkbackService.shared
        let entryId = talk.entryId
        talkButton.onPress = { service.pressTalk(entryId: entryId) }
        talkButton.onRelease = { service.releaseTalk() }
        talkButton.onAccessibilityPress = { service.toggleTalk(entryId: entryId) }
        soundMenu.onPick = { [weak self] announcement in
            self?.soundMenu.isHidden = true
            service.play(announcement, entryId: entryId)
        }
        soundMenu.onAdd = { [weak self] in
            self?.soundMenu.isHidden = true
            self?.addMP3()
        }

        service.$activity
            .receive(on: RunLoop.main)
            .sink { [weak self] activity in self?.render(activity) }
            .store(in: &cancellables)
        service.$notice
            .compactMap { $0 }
            .filter { $0.entryId == entryId }
            .receive(on: RunLoop.main)
            .sink { [weak self] notice in self?.notice.show(notice.text) }
            .store(in: &cancellables)
        SoundStore.shared.$settings
            .map(\.talkMode)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.render(TalkbackService.shared.activity) }
            .store(in: &cancellables)
    }

    /// Talk button label when idle: hold mode "Leertaste halten", toggle mode "Sprechen".
    private static var idleTitle: String {
        SoundStore.shared.settings.talkMode == .hold ? "Leertaste halten" : "Sprechen"
    }

    /// Menu over the pill (bottom edge on the pill's top edge), 45 pt left of the sound button (template: left 70 in a 470 popup),
    /// at least 10 from the popup edge; notice 8 above the pill, centered.
    func install(in content: NSView, above pill: NSView) {
        content.addSubview(notice)
        content.addSubview(soundMenu)
        let leading = soundMenu.leadingAnchor.constraint(equalTo: soundButton.leadingAnchor, constant: -45)
        leading.priority = .defaultHigh
        NSLayoutConstraint.activate([
            leading,
            soundMenu.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 10),
            soundMenu.bottomAnchor.constraint(equalTo: pill.topAnchor),
            notice.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            notice.bottomAnchor.constraint(equalTo: pill.topAnchor, constant: -8),
            notice.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, constant: -20),
        ])
    }

    /// true when the click only closed the open menu.
    func closeMenu() -> Bool {
        guard !soundMenu.isHidden else { return false }
        soundMenu.isHidden = true
        return true
    }

    /// Keep the popup open while something is being sent from it.
    var isBusy: Bool { TalkbackService.shared.isActive(entryId: entryId) }

    func pointerInside(_ inside: Bool) {
        if inside {
            TalkbackService.shared.pointerEntered(entryId: entryId)
        } else {
            TalkbackService.shared.pointerExited(entryId: entryId)
        }
    }

    func popupClosed() {
        TalkbackService.shared.popupClosed(entryId: entryId)
        cancellables.removeAll()
    }

    @objc private func soundTapped() {
        // While an announcement plays from this popup, the button stops it.
        if let activity = TalkbackService.shared.activity, activity.entryId == entryId,
           case .announcement = activity.purpose {
            TalkbackService.shared.stopPlayback()
            return
        }
        if soundMenu.isHidden {
            soundMenu.reload(SoundStore.shared.settings.announcements)
        }
        soundMenu.isHidden.toggle()
    }

    private func addMP3() {
        guard let url = SoundFilePicker.chooseMP3() else { return }
        do {
            let added = try SoundStore.shared.addFile(from: url)
            TalkbackService.shared.play(added, entryId: entryId)
        } catch {
            notice.show((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func render(_ activity: TalkbackActivity?) {
        let mine = activity?.entryId == entryId ? activity : nil
        switch mine?.purpose {
        case .talk?:
            let live = mine?.phase == .live
            let liveTitle = SoundStore.shared.settings.talkMode == .hold ? "Spricht …" : "Beenden"
            talkButton.update(title: live ? liveTitle : "Verbinde …", busy: !live)
            setSoundActive(false)
        case .announcement?:
            talkButton.update(title: Self.idleTitle, busy: false)
            setSoundActive(true)
        case nil:
            talkButton.update(title: Self.idleTitle, busy: false)
            setSoundActive(false)
        }
    }

    /// Playing: `accent` fill, white symbol (template has no playing state).
    private func setSoundActive(_ active: Bool) {
        soundButton.layer?.backgroundColor = soundButton.cgColor(active ? Tokens.accent : Tokens.pillBtn)
        soundButton.contentTintColor = active ? .white : Tokens.pillFg.nsColor
        soundButton.toolTip = active ? "Ansage stoppen" : "Ton abspielen"
    }
}
```

- [ ] **Step 4: Overlay-Inhalt und Leiste erweitern**

In `UniFiCameraPopup/Views/Popup/PopupOverlayViews.swift`:
1. Im `struct PopupOverlayContent` nach `let onMute: (MuteDuration) -> Void` einfügen (mit Standardwert, damit bestehende Aufrufe gültig bleiben):
```swift
    /// Phase 3: "Ton abspielen" and "Leertaste halten"; nil = camera without speaker.
    var talk: PopupTalkContent? = nil
```
2. In `final class ActionPillView` die Zeile `init(actions: [CameraAction]) {` ersetzen durch:
```swift
    /// `leadingViews` (Ton abspielen, Leertaste halten) come before the user's buttons.
    init(actions: [CameraAction], leadingViews: [NSView] = []) {
```
und direkt vor `for action in actions.prefix(WebhookMapping.maxActions) {` einfügen:
```swift
        for view in leadingViews {
            stack.addArrangedSubview(view)
        }
```

- [ ] **Step 5: PopupWindow einhängen**

In `UniFiCameraPopup/Views/PopupWindow.swift`:
1. Nach `private var muteMenu: PopupMuteMenuView?` einfügen: `private var talkControls: PopupTalkControls?`
2. In `clickCatcher.onClick` direkt nach `guard let self else { return }` einfügen:
```swift
                if self.talkControls?.closeMenu() == true {
                    return
                }
```
3. `clickCatcher.onMouseEnter`/`onMouseExit` ersetzen durch:
```swift
            clickCatcher.onMouseEnter = { [weak self] in
                self?.pauseAutoClose()
                self?.talkControls?.pointerInside(true)
            }
            clickCatcher.onMouseExit = { [weak self] in
                self?.resumeAutoClose()
                self?.talkControls?.pointerInside(false)
            }
```
4. In `setupOverlay(in:)` den Block `if !actions.isEmpty { let pill = ActionPillView(actions: actions) … }` ersetzen durch:
```swift
        var leading: [NSView] = []
        if let talk = overlay.talk {
            let controls = PopupTalkControls(content: talk)
            leading = [controls.soundButton, controls.talkButton]
            talkControls = controls
        }
        if !actions.isEmpty || !leading.isEmpty {
            let pill = ActionPillView(actions: actions, leadingViews: leading)
            pill.onAction = { [weak self] action, button in
                self?.run(action, from: button)
            }
            content.addSubview(pill)
            constraints += [
                pill.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                pill.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            ]
            talkControls?.install(in: content, above: pill)
        }
```
(Das Stumm-Menü wird danach hinzugefügt und liegt damit weiter über allem.)
5. `scheduleAutoClose(after:)` und `resumeAutoClose()` ersetzen durch (nur `closePopup()` → `autoCloseFired()`), und `autoCloseFired()` dahinter einfügen:
```swift
    private func scheduleAutoClose(after seconds: TimeInterval) {
        autoCloseTimer?.invalidate()
        autoCloseTimer = nil
        autoCloseDeadline = seconds > 0 ? Date().addingTimeInterval(seconds) : nil
        guard seconds > 0, !mouseInside else { return }

        autoCloseTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.autoCloseFired()
        }
    }

    private func resumeAutoClose() {
        mouseInside = false
        guard let deadline = autoCloseDeadline else { return }

        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else {
            autoCloseFired()
            return
        }

        autoCloseTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
            self?.autoCloseFired()
        }
    }

    /// Auto-close waits while this popup talks or sends an announcement.
    private func autoCloseFired() {
        if talkControls?.isBusy == true {
            scheduleAutoClose(after: 5)
            return
        }
        closePopup()
    }
```
6. In `closePopup()` als erste Zeile: `talkControls?.popupClosed()`

- [ ] **Step 6: PopupController reicht `talk` durch**

In `PopupController.swift`, `makeAlarmWindow(event:mapping:streamURL:)`, im `PopupOverlayContent(…)`-Aufruf nach dem `onMute`-Argument ergänzen:
```swift
            onMute: { [weak self] duration in
                self?.settings.mute(entryId: entryId, for: duration)
            },
            talk: TalkbackService.shared.canTalk(mapping) ? PopupTalkContent(entryId: entryId) : nil
        )
```

- [ ] **Step 7: pbxproj**

PBXBuildFile `C31000000000000000000008 /* PopupTalkViews.swift in Sources */ = {isa = PBXBuildFile; fileRef = C32000000000000000000008 /* PopupTalkViews.swift */; };`
PBXFileReference `C32000000000000000000008 /* PopupTalkViews.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PopupTalkViews.swift; sourceTree = "<group>"; };`
In der Gruppe `A40000000000000000000072 /* Popup */` nach `A20000000000000000000080 /* PopupOverlayViews.swift */,`: `C32000000000000000000008 /* PopupTalkViews.swift */,`. Sources-Phase am Ende der `files`: `C31000000000000000000008 /* PopupTalkViews.swift in Sources */,`.

- [ ] **Step 8: Lint, Build, Symbole prüfen**

Run: `plutil -lint UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj` → `OK`
Run: Build-Befehl → `** BUILD SUCCEEDED **`
Run: `xcrun --sdk macosx assetutil --info "$DD/Build/Products/Debug/UniFi Camera Popup.app/Contents/Resources/Assets.car" | grep -c '"Name" : "\(mic\|soundPlay\)"'`
Expected: Zahl ≥ 2.

- [ ] **Step 9: Sicht- und Funktionsprüfung gegen `docs/design/popup.md`** (ohne Kamera-Lautsprecher prüfbar bis auf den Ton an der Kamera)

Test-Popup einer Protect-Kamera **mit** Lautsprecher (Kameras › Erweitert › Test-Popup) und einer ohne:
1. Mit Lautsprecher: Leiste „Ton abspielen“ · „Leertaste halten“ · Buttons, Maße und Farben wie Punkt 4; ohne Lautsprecher bzw. Webhook-Kamera: nur die Buttons (oder keine Leiste).
2. „Ton abspielen“ → Menü mit den Ansagen aus Einstellungen › Ton (Name + „MP3“/„KI-Stimme“), Trennlinie, „MP3 hinzufügen …“; Unterkante auf der Leiste. Klick daneben schließt nur das Menü.
3. Maustaste auf „Leertaste halten“ halten → „Verbinde …“ (70 %), danach „Spricht …“; loslassen → „Leertaste halten“. Ohne Mikrofon-Freigabe: Systemdialog; bei „Nicht erlauben“ Hinweis „Kein Zugriff aufs Mikrofon …“ über der Leiste.
4. Zeiger über dem Popup, Leertaste halten → wie 3; Zeiger weg → die Leertaste tippt in anderen Apps wieder Leerzeichen.
5. Einstellungen › Ton › „Umschalten“: Ruhe „Sprechen“, Klick → „Beenden“, Klick → „Sprechen“.
6. Ansage wählen → „Ton abspielen“ wird indigo, Klick darauf stoppt; nach dem Ende wieder grau.
7. Ohne erreichbare Kamera (z. B. WLAN aus) → Hinweis mit der Fehlermeldung, 6 s; das Log `~/Library/Logs/UniFi Camera Popup/talkback.log` zeigt Sitzung anfordern → Fehler.
8. Während gesprochen wird, schließt das Popup nicht automatisch; schließen per Klick beendet das Senden (Log: „Mikrofon zu“ bzw. kein weiteres Paket).
9. Hell/Dunkel: Leiste, Menü und Hinweis wechseln wie in der Spezifikation.

- [ ] **Step 10: Commit**

```bash
git add docs/design/popup.md UniFiCameraPopup/Assets.xcassets/Icons/mic.imageset UniFiCameraPopup/Assets.xcassets/Icons/soundPlay.imageset UniFiCameraPopup/Views/Design/DesignComponents.swift UniFiCameraPopup/Views/Popup UniFiCameraPopup/Views/PopupWindow.swift UniFiCameraPopup/Services/PopupController.swift UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "feat(popup): push-to-talk button, announcement menu and talkback notices" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: „Was ist neu“, Hilfe mit Lizenzhinweis, Bildvergleich, Hardware-Prüfpunkt

**Files:**
- Modify: `UniFiCameraPopup/Services/WhatsNewService.swift` (1.2.0-Eintrag)
- Modify: `UniFiCameraPopup/Views/HelpView.swift` (Tipp „Sprechen und Ansagen“)

**Interfaces:**
- Consumes: alles aus Task 1–8.
- Produces: geprüfter Stand, Vergleichsbilder (nur lokal), Prüfprotokoll an echter Hardware.

- [ ] **Step 1: „Was ist neu“ ergänzen**

In `WhatsNewService.swift` im `ChangelogEntry(version: "1.2.0", items: [ … ])` als letzten Eintrag (nach den Phase-2-Einträgen) anfügen:
```swift
            "Sprechen und Ansagen: Bei Kameras mit Lautsprecher hältst du im Popup die Leertaste (oder den Button) und sprichst über die Kamera. Fertige Ansagen spielst du als MP3 oder mit einer macOS-Stimme aus eigenem Text ab – einzurichten im Reiter Ton.",
```

- [ ] **Step 2: Hilfe mit Lizenzhinweis**

In `HelpView.swift` in `tipsBody` nach dem Tipp „Aktions-Buttons“ einfügen:
```swift
            tip("Sprechen und Ansagen", "mic",
                "Bei Kameras mit Lautsprecher zeigt das Popup unten „Ton abspielen“ und „Leertaste halten“. "
                + "Halte den Button oder – solange der Mauszeiger über dem Popup ist – die Leertaste gedrückt und sprich; "
                + "Loslassen beendet. Unter Einstellungen › Ton wählst du Mikrofon, Sprech-Modus und Lautstärke und verwaltest "
                + "die Ansagen (MP3 oder Text mit einer macOS-Stimme, erzeugt auf diesem Mac). Die mitgelieferten Ansagen "
                + "„Bin gleich da“ und „Paket bitte abstellen“ wurden mit Piper und der Stimme „Thorsten“ erzeugt "
                + "(Datensatz CC0, gemeinfrei). Klappt etwas nicht, steht der Ablauf in "
                + "~/Library/Logs/UniFi Camera Popup/talkback.log.")
```

- [ ] **Step 3: Alle Tests und Build**

Run: `(cd Packages/AppCore && swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -2)` → `0 failures`
Run: `(cd Packages/ProtectKit && swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -2)` → `0 failures`
Run: Build-Befehl → `** BUILD SUCCEEDED **`
Run: `find UniFiCameraPopup Packages -iname "*piper*" -o -iname "*espeak*" | grep -v "/.build/"` → keine Ausgabe (keine GPL-Engine im Projekt; „Piper“ steht nur im Hilfetext und in Kommentaren).

- [ ] **Step 4: Bildvergleich (Pflicht vor „fertig“, ~/Projects/snackbits/CLAUDE.md)**

Wie Phase-2-Plan Task 9 Step 3: veröffentlichtes Artefakt https://claude.ai/artifact/Q9JCg1b1gu5stRG2SxaKsP im angemeldeten Browser (Chrome DevTools MCP / Playwright MCP), Zoom 100 %, Board-Screenshot, Fenster ausschneiden:

| Bild | Board | x | y | Breite × Höhe |
|---|---|---|---|---|
| S5 Ton | Einstellungen | 887 | 716 | 760 × 540 |
| 8 Popup mit Sprechen & Ton | Main | 1915 + 45 | 596 + 60 | 470 × 300 |

Dasselbe für die Dunkel-Boards. App aufnehmen: Einstellungen › Ton mit genau den Vorlagen-Inhalten so weit möglich („Bin gleich da“ ausgewählt, Editor „KI-Stimme“, Text „Bin gleich da! Einen kleinen Moment, bitte.“), Popup 470 × 300 mit einem Button „Tür öffnen“ und offenem Ansagen-Menü; Aufnahme mit dem Fenster-Listing aus Phase-2-Task 9 (`swift windows.swift`, `screencapture -o -x -l <ID>`), Retina-Bilder mit `sips -Z` auf 1× verkleinern.

Je Bildschirm Vorlage und App nebeneinander ansehen und gegen `docs/design/einstellungen-ton.md` bzw. `docs/design/popup.md` abhaken: Reihenfolge, Texte, Abstände, Schriftgrößen/-schnitte, Farben hell und dunkel, Lage des Ansagen-Menüs (links ≈ 70, Unterkante = Oberkante Leiste). Jede Differenz, die nicht unter „Abweichungen von der Vorlage“ steht, wird behoben (zurück in Task 7/8) oder als neue Frage gemeldet – nicht still akzeptiert.

- [ ] **Step 5: Hardware-Prüfpunkt (Talkback an echter Kamera – manuell, Ergebnis je Punkt notieren)**

Vorher: `tail -f ~/Library/Logs/UniFi\ Camera\ Popup/talkback.log` in einem Terminal; in einem zweiten `sudo tcpdump -n -i any udp and host <Kamera-IP> -c 40` (zeigt, ob Pakete den Mac verlassen).
1. Test-Popup der Türklingel (Lautsprecher). „Leertaste halten“ mit der Maus halten, 3 s sprechen. Log: „Sitzung anfordern“, „Antwort {…}“ (Rohtext notieren: `url`, `codec`, `samplingRate`, `bitsPerSample`), „Ziel …“, „UDP bereit“, „erstes Paket gesendet“, „Mikrofon zu“, „fertig, N Pakete“ (N ≈ Sekunden × 50 bei Opus bzw. × Rate/1024 bei AAC). tcpdump zeigt Pakete an `<Kamera-IP>:<Port>` im 20-ms- bzw. 46-ms-Takt.
2. **Ton an der Kamera hörbar und verständlich?** Notieren: ja/nein, Verzögerung, Aussetzer.
3. „Ton abspielen“ › „Bin gleich da“ → an der Kamera hörbar, ohne Beschleunigung/Abbruch.
4. Eigene MP3 und eine Text-Ansage (macOS-Stimme) → hörbar.
5. Lautstärke-Regler ganz links/mitte/rechts → leiser/normal/lauter, rechts ohne Knacken.
6. Wenn **kein Ton** trotz Paketen: Log-Antwort prüfen. Opus → nacheinander prüfen: RTP-Payload-Typ (Konstante `RTPPacketizer.opusPayloadType`, ffmpeg nimmt 97), Marker-Bit, fehlendes RTCP (ffmpeg sendet an Port + 1); AAC → Abtastrate im ADTS-Kopf = `samplingRate` der Antwort. Befund mit Rohantwort und tcpdump-Auszug als Rückfrage melden, **keine Änderung ins Blaue**.
7. Wenn die Sitzung scheitert: HTTP-Status aus dem Log (z. B. „Fehler 404/400“) notieren – evtl. verlangt die Konsole einen Body (`{}`) oder eine neuere Protect-Version; als Rückfrage melden.

- [ ] **Step 6: Ende-zu-Ende-Prüfung** (Ergebnis je Punkt notieren)

1. Erster Start über bestehenden Einstellungen: Reiter Ton zeigt die zwei mitgelieferten Ansagen; Konfigurations-Export enthält keine Ton-Daten (`grep -c "announcements" <export>` → 0) und keinen API-Schlüssel.
2. Mikrofon-Dialog erscheint genau einmal; nach „Nicht erlauben“ zeigt das Popup den Hinweis, nach Freigabe in den Systemeinstellungen geht Sprechen ohne Neustart.
3. Zwei Popups gleichzeitig (zwei Kameras): Sprechen in einem stoppt eine laufende Ansage im anderen; die Leertaste gehört dem Popup unter dem Zeiger.
4. Popup während des Sprechens schließen → Log „Mikrofon zu“ bzw. keine weiteren Pakete (tcpdump verstummt).
5. Kamera-Tastenkürzel (⌥⌘1 …) funktionieren weiter, auch während der Zeiger über einem Popup liegt.
6. Ansagen-Datei im Finder aus dem Sounds-Ordner löschen → „Ton abspielen“ › diese Ansage → Hinweis „Die Ansage konnte nicht gelesen werden (Datei fehlt).“, kein Absturz.

- [ ] **Step 7: Commit**

```bash
git add UniFiCameraPopup/Services/WhatsNewService.swift UniFiCameraPopup/Views/HelpView.swift
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "chore: 1.2.0 release notes and help for talkback and announcements" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
Kein Push, kein Merge, kein Release-Build.
