# Phase 5 – Nutzer-Feedback zu 1.2.0 – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die zwölf Punkte aus dem Build-Test des Nutzers umsetzen: Popup ohne doppelte Name/Zeit-Einblendung, neue Glocke, Version und Update im Menü, Popup-Größe automatisch und Stapel, der immer auf den Bildschirm passt, Sprechen nur per gedrücktem Button, gleich laute Ansagen und Mikrofon mit zwei Reglern, nur die Stimme Anna, Buttons mit Ton und die neue Kategorie „Ereignisse“ (Regeln je Kamera).

**Architecture:** Alle reine Logik kommt in das lokale Package `AppCore` (XCTest über `swift test`): Größe/Stapel-Layout (`PopupLayout.swift`), Lautheit und automatische Mikrofon-Verstärkung (`Loudness.swift`, `AutomaticGainControl.swift`, eingehängt in `TalkbackStreamer`), Stimmenwahl (`VoiceChoice.swift`), Ereignis-Regeln mit Entprellung (`EventRules.swift`), Button-Verfügbarkeit (`ActionAvailability.swift`) und die neuen Felder in `SettingsExtensions`. Die App verdrahtet: neue Werte in `WebhookMapping`/`CameraAction` (Haupt-Blob, damit sie im Export sind) und gespiegelt in `settingsExtensionsV2`, `PopupController` legt den Stapel animiert an, `EventRuleService` führt Regeln über dieselben Wege wie Buttons aus (`CameraActionService` mit Phase-4-Routing, `TalkbackService`).

**Tech Stack:** Swift 5.9 Tools / Xcode 27, SwiftUI + AppKit (macOS 13.0), AVFoundation (`AVSpeechSynthesizer`, `AVAudioPCMBuffer`), `NSAnimationContext`, XCTest über `swift test` (AppCore, ProtectKit).

**Spec:** `docs/superpowers/specs/2026-10-18-phase5-feedback.md` (verbindlich; Querschnitt-Regeln aus `docs/superpowers/specs/2026-10-18-phases-2-4.md` gelten weiter). Baut auf dem Stand nach Phase 4 auf (`docs/superpowers/plans/2026-10-18-phase4-wireguard.md`); Format und Befehle wie dort.

> **Vorab geprüft (18.10.2026):** Jeder Task wurde in einer Kopie des Worktrees (Stand `0c8183e`) der Reihe nach angewendet – die Code-Blöcke dieses Plans wurden dafür maschinell aus dem Plan gelesen und eingesetzt. Nach jedem Task: `** BUILD SUCCEEDED **`; am Ende `swift test` AppCore 119/119 (51 neu), ProtectKit 142/142. Die Bilder des DEBUG-Renderers (`--render-snapshots`) wurden angesehen: Popup mit/ohne Chip, neue Glocke, zweizeiliger Sprech-Button, schmales Popup (284 × 160) mit Mikrofon-Kreis, Panel mit Update-Button, Kameras mit „Kamera entfernen“ und „Ereignisse“, Regel-Sheet, Ton mit zwei Reglern und „Anna · macOS“. **Nicht geprüft:** echte Kamera/Konsole, Mausloslassen außerhalb des Popups, Animation am echten Bildschirm (manuelle Prüfpunkte in Task 12).

## Voraussetzung: Phase 4 ist umgesetzt

Vor Task 1 prüfen (jede Zeile > 0, die letzte = 0):

```bash
grep -c "public struct SettingsExtensions" Packages/AppCore/Sources/AppCore/SettingsExtensions.swift
grep -c "final class TalkbackStreamer" Packages/AppCore/Sources/AppCore/Talkback/TalkbackStreamer.swift
grep -c "enum TalkMode" Packages/AppCore/Sources/AppCore/Sound/SoundSettings.swift
grep -c "final class PushToTalkKey" UniFiCameraPopup/Services/PushToTalkKey.swift
grep -c "struct StatusPanelView" UniFiCameraPopup/Views/StatusPanel/StatusPanel.swift
grep -c "func webhookURL" UniFiCameraPopup/Services/Tunnel/ConnectionRouter.swift
grep -c "private let extensionsKey = \"settingsExtensionsV2\"" UniFiCameraPopup/Services/SettingsStore.swift
grep -c "E51000000000000000000001\|E52000000000000000000001" UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj   # → 0
```

Es gibt **kein** Test-Bundle im Xcode-Projekt (Phase-2-Entscheidung): Testbares liegt in `AppCore`.

## Global Constraints

- macOS-Deployment-Target **13.0**; keine API neuer als macOS 13 ohne `#available` (geplant: keine). Keine Sandbox, Hardened Runtime aus, kein bezahlter Developer-Account; Signatur unverändert.
- UI-Sprache Deutsch, Du-Form, typografische Anführungszeichen „…“; Code und Bezeichner Englisch. Wo die Vorlage etwas anderes zeigt, gilt der Nutzerwunsch (Spezifikation: „bewusste Abweichung, im Plan benennen“) – siehe „Bewusste Abweichungen von der Vorlage“.
- „Neue Einstellungen unter `settingsExtensionsV2` (nicht vom alten Build überschreibbar).“ Jeder neue Wert pro Kamera/Button steht in `SettingsExtensions` (Schlüssel `settingsExtensionsV2`) **und** im Haupt-Blob (`WebhookMapping`/`CameraAction`, damit er im Konfigurations-Export ist); beim Laden gewinnt die Erweiterung.
- „Reine Logik (Layout, Normalisierung/Gain, Ereignis-Regeln/Entprellung, Größen-Default) in `AppCore` mit Tests; UI nach bestehenden Design-Komponenten.“
- Lautheit: „Ziel −20 dBFS RMS, Spitze ≤ −1 dBFS“; Mikrofon „max. +18 dB, schnelle Spitzenbegrenzung“. Kamera-Lautsprecher-API nur, wenn in der Referenz belegt – ist sie nicht (Entscheidung 11).
- Popup-Stapel: Standardhöhe „≈ 42 % der sichtbaren Bildschirmhöhe (`visibleFrame`)“, „Untergrenze: 160 pt Höhe“, „Größenwechsel animiert, 300 ms, ease-in-out“, „Reduzierte Bewegung (Bedienungshilfen) → ohne Animation“.
- Ereignis-Regeln: „Verzögerung in Sekunden (0–600, Standard 0)“, „Entprellung pro Kamera+Regel: 30 s“, Token im Schlüsselbund, im Export ohne Token, unabhängig von Popup und Stummschaltung.
- Schlüssel nur im Schlüsselbund, nie im Log, nie im Export (Action-Tokens bleiben wie bisher im Export; Regel-Tokens nie).
- Version bleibt **1.2.0**, Build-Nummer unangetastet; nur der bestehende 1.2.0-Eintrag in `WhatsNewService` wird ergänzt. `build-release.sh` wird **nie** ausgeführt.
- `UniFiCameraPopup/AppConfig.swift` hat lokale Änderungen des Nutzers: **nie ändern, nie stagen, nie zurücksetzen**. Nur explizite Pfade `git add`; nie `git add -A`, `git add .` oder `git commit -a`. Vor jedem Commit: `git diff --cached --name-only | grep AppConfig` muss leer sein.
- Die App wird **nie normal gestartet**. Sichtprüfung nur über den DEBUG-Renderer `--render-snapshots` (eigene `UserDefaults`-Suite, kein Schlüsselbund, beendet sich selbst).
- Kein Merge, kein Push. Jeder Task endet mit grünem Build. Commit-Nachrichten enden mit `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Neue pbxproj-IDs: Präfix **E5** (`E51…` BuildFile, `E52…` FileRef) über `UniFiCameraPopup/scripts/pbxproj-add-files.py --prefix E5` (Task 11).

**Befehle** (aus dem Worktree-Wurzelverzeichnis `app-protect/`):

```bash
# App bauen
DD="${TMPDIR:-/tmp}/ucp-phase5-dd"
xcodebuild -project UniFiCameraPopup/UniFiCameraPopup.xcodeproj -scheme UniFiCameraPopup \
  -configuration Debug -derivedDataPath "$DD" build 2>&1 | grep -E "error:|\*\* BUILD" | tail -20
# Erwartet: ** BUILD SUCCEEDED **

# Tests
(cd Packages/AppCore && swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -3)
(cd Packages/ProtectKit && swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -3)

# Sichtprüfung ohne normalen Start (DEBUG-Renderer, schreibt PNGs 2×, hell + dunkel, und beendet sich)
OUT="${TMPDIR:-/tmp}/ucp-phase5-snap"; rm -rf "$OUT"; mkdir -p "$OUT"
"$DD/Build/Products/Debug/UniFi Camera Popup.app/Contents/MacOS/UniFi Camera Popup" --render-snapshots "$OUT" > /dev/null
open "$OUT"

# pbxproj nach Änderung prüfen
plutil -lint UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj
```

**Schreibweise der Code-Schritte:** „In `Pfad` ersetzen:“ + Block + „durch:“ + Block = genau dieser Text kommt genau einmal in der Datei vor und wird ersetzt (Edit-Werkzeug). „Datei `Pfad` neu anlegen:“ = ganze Datei. „An `Pfad` anhängen:“ = ans Dateiende.

## Review Focus

1. **Mehr Popups, als auf den Bildschirm passen – auch riesig eingetragene Größe, Hochkant-Kamera, zweiter Bildschirm mit verschobenem Ursprung:** Alle bleiben vollständig sichtbar, gleich groß verkleinert, ab 160 pt in eine zweite Spalte; der Sprech-Button wird im schmalen Popup zum Mikrofon-Kreis statt das Fenster zu verbreitern. → `PopupLayoutTests.testManyPopupsUseSecondColumnInsteadOfGoingBelowMinimum`, `testOversizedSinglePopupFitsScreen`, `testScreenWithOffsetOrigin`, `testTalkButtonFallsBackToMicrophoneInNarrowPopups` (Task 1); Bild `9-popup-schmal-*` muss 284 × 160 bleiben (Task 6).
2. **Erster Start über bestehenden Einstellungen bzw. die alte installierte Version schreibt den Haupt-Blob neu:** 480 × 270 wird automatisch, andere Größen bleiben; „Name und Zeit“ ist aus; Regeln, Button-Töne und Größe kommen aus der Erweiterung zurück; die eine alte Lautstärke steht in beiden Reglern; ein gespeicherter Sprech-Modus wird ignoriert. → `PopupLayoutTests.testMigrationTreatsOldDefaultAsAutomatic` (Task 1), `SettingsExtensionsTests.testPhase5FieldsRoundTripAndStayLenient` (Task 3), `SoundSettingsTests.testOldSingleVolumeGoesIntoBoth` (Task 8).
3. **Ereignis-Flut** (Bewegung alle 5 s, Person + Fahrzeug im selben Ereignis, Uhr zurückgestellt): Jede Regel läuft pro Ereignis einmal und je Kamera höchstens alle 30 s; andere Kameras/Regeln bleiben unabhängig. → `EventRulesTests.testBurstOfEventsRunsOncePerWindow`, `testDebouncePerCameraAndRule`, `testMatcherPicksKindAndSkipsRulesThatCannotRun` (Task 3).
4. **Extreme Pegel** (stille Datei, nur Rauschen, ein Knackser, übersteuerte MP3, lautes Wort nach Flüstern, Regler ganz rechts): nie eine Spitze über −1 dBFS, Rauschen wird nicht hochgezogen, Stille behält Faktor 1. → `LoudnessTests.testSilentFileKeepsGain`, `testSpikeLimitsGain`, `AutomaticGainControlTests.testNoiseIsNotBoosted`, `testBurstAfterQuietNeverExceedsCeiling`, `testFixedGainOnlyLimits` (Task 2).
5. **Verwaiste oder unvollständige Bezüge** (Ansage gelöscht, die ein Button/eine Regel nutzt; Kamera ohne Lautsprecher; Regel ohne gültige Aktion; Token im Export): Button zeigt nur noch seinen Webhook-Teil oder verschwindet, Regel wird übersprungen, Sichern bleibt gesperrt, kein Token im Export. → `ActionAvailabilityTests` (Task 3), `EventRulesTests.testIsConfigured`, `testTokenNeverEncoded`, `testMatcherPicksKindAndSkipsRulesThatCannotRun` (Task 3).

---

## Bewusste Abweichungen von der Vorlage (Nutzerwunsch)

1. **Popup-Chip** „Klingel · Haustür · 10:41“ (Vorlage Main 8, Punkt 1) ist standardmäßig **aus**; Schalter „Name und Zeit einblenden“ unter Kameras › Erweitert › Popup.
2. **Glocke** im Popup: Lucide `bell-off` (24er Raster, Strich 2, runde Enden) statt des Vorlagen-SVG; Tooltip „Diese Kamera stummschalten“.
3. **Sprech-Button** (Vorlage: „Leertaste halten“ einzeilig): zweizeilig „Sprechen“ / „Verbinde …“ / „Loslassen zum Beenden“ über „Gedrückt halten zum Sprechen“; keine Leertaste, kein „Umschalten“.
4. **Menüleisten-Panel** (Vorlage Main 7): zusätzlich Versionszeile und ggf. Update-Button zwischen Trennlinie und „Einstellungen …“.
5. **Kameras** (Vorlage S2/S3): „Ton des Livebilds“ in der Karte mit „Tastenkürzel …“; „Kamera entfernen“ rot neben „Erweitert“ (immer sichtbar); neuer Abschnitt „Ereignisse“ unter „Buttons im Popup“; „Größe“ ohne feste Platzhalter 480/270.
6. **Button-Sheet** (Vorlage S4): zusätzliche Zeile „Ton“ mit Hinweis; „Adresse“ ist optional, wenn ein Ton gewählt ist.
7. **Ton** (Vorlage S5): Zeile „Sprechen“ entfällt; „Lautstärke an der Kamera“ wird zu „Lautstärke Sprechen“ und „Lautstärke Ansagen“; das Stimmenfeld ist deaktiviert und zeigt „Anna · macOS“.

## Entscheidungen (wo die Spezifikation offen ist)

1. **Entscheidung:** Ist „Name und Zeit einblenden“ aus, entfällt der ganze Chip (auch die Ereignis-Art) – er besteht nur aus Art · Name · Zeit, und die Kamera-OSD zeigt Name und Zeit.
2. **Entscheidung:** Seitenverhältnis der automatischen Größe: Ausschnitt (falls gesetzt) → Bild der Kamera (aus dem ersten Snapshot gelernt; nach dem Laden der Kameraliste holt die App einmal je verknüpfter Kamera einen) → 16:9. Die Integration API liefert keine Auflösung.
3. **Entscheidung:** Ist nur ein Größenfeld ausgefüllt, folgt das andere dem Seitenverhältnis (Platzhalter zeigt den Wert); Werte unter 40 pt werden 40. Ein gesetzter Ausschnitt macht eine automatische Größe nicht fest, sie übernimmt nur sein Seitenverhältnis.
4. **Entscheidung:** Spalten werden der Reihe nach gefüllt (erste ⌈n/k⌉ Popups in Spalte 1); weitere Spalten liegen vom Anker weg (rechts verankert → nach links). Mittige Positionen zentrieren den ganzen Stapel. Auch das einzelne Popup ohne „Alle aktiven Kameras zeigen“ wird so eingepasst.
5. **Entscheidung:** „Schrittweise“ zurückwachsen = bei jedem Schließen ein animierter Übergang (300 ms) auf die neue Verteilung – kein mehrstufiges Wachsen.
6. **Entscheidung:** Der Sprech-Button hat die feste Breite seines längsten Textes (springt nicht). Passt die Leiste nicht mehr 10 pt innerhalb des Popups, zeigt er nur das Mikrofon (Kreis 40), der Hinweis steht im Tooltip. VoiceOver „Drücken“ schaltet weiter um (sonst wäre Sprechen ohne Maus unmöglich).
7. **Entscheidung:** Panel: „Version 1.2.0 (29)“ (11 `muted`) nach der Trennlinie, darunter bei einem Update ein Button im Stil der Stumm-Buttons (`SoftButtonStyle`, volle Breite) „Update auf 1.3.0 installieren“ bzw. „Update auf 1.2.0 (30) installieren“ (gleiche Version, neuerer Build); während des Ladens „Lade neue Version …“/„Installiere …“ (gesperrt). Der Button ruft die bestehende Update-Aktion (Rückfrage, Download, Neustart). Einen Eintrag „Nach Updates suchen“ gab es im alten Menü nicht – stattdessen sucht das Panel wie das alte Menü bei jedem Öffnen im Hintergrund.
8. **Entscheidung:** Ansagen-Normalisierung nicht destruktiv: Beim Import/Erzeugen wird der Faktor gemessen und an der Ansage gespeichert (`loudnessGain`), die Datei bleibt unverändert. Ansagen von vor Phase 5 und die mitgelieferten werden einmal im Hintergrund nach dem Start gemessen (sonst beim ersten Abspielen). Gemessen wird über 50-ms-Blöcke über −50 dBFS (Pausen zählen nicht), Faktor zwischen −30 und +18 dB.
9. **Entscheidung:** Mikrofon-Verstärkung −12 … +18 dB; sie fällt sofort und steigt höchstens 12 dB/s; Blöcke unter −50 dBFS (Pausen, Raumrauschen) ändern sie nicht. Danach wirkt „Lautstärke Sprechen“, zuletzt die Begrenzung auf −1 dBFS (10-ms-Blöcke). Für Ansagen gilt dieselbe Begrenzung ohne automatische Verstärkung – auch wenn ein Regler über 2/3 steht.
10. **Entscheidung:** Beide Regler wie bisher: 2/3 = unverändert, ganz rechts × 1,5. „Probehören“ am Mac bleibt in Originallautstärke.
11. **Entscheidung:** Eine Kamera-Lautsprecher-Lautstärke wird **nicht** gesetzt: `docs/superpowers/specs/phase2-4/reference/` enthält nur `uiprotect-stream.py` (Talkback), kein `PATCH /v1/cameras/{id}` mit Lautstärke.
12. **Entscheidung:** Stimme = Anna in der besten installierten Qualität; Feld zeigt immer „<Name> · macOS“. Fehlt Anna: beste deutsche Stimme (Qualität, de-DE vor de-AT/-CH, Name) und eine orange Hinweiszeile. „Übernehmen“ ist auch bei unverändertem Text aktiv, solange die Ansage eine andere Stimme hat (die mitgelieferten Thorsten-Aufnahmen spielen weiter, bis man übernimmt); „Anhören“ spricht immer mit Anna.
13. **Entscheidung:** Buttons mit Ton: Zeile „Ton“ im Sheet nur bei Kameras mit Lautsprecher; „Testen“ prüft nur den Webhook; Liste zeigt Badge „TON“ und „Ton „Name““ (mit Adresse: „<Adresse> + Ton“); eine gelöschte Ansage heißt im Sheet „Gelöschte Ansage“, im Popup läuft dann nur der Webhook-Teil (ohne Webhook verschwindet der Button). Ein Ton-Button ohne Webhook zeigt sofort das grüne Häkchen; Fehler der Ansage erscheinen als Popup-Hinweis.
14. **Entscheidung:** Ereignisse: Liste wie „Buttons im Popup“, höchstens 10 Regeln je Kamera, nur bei Protect-Kameras. Ereignis-Auswahl = was die Kamera melden kann (Chip-Reihenfolge), ohne Kameradaten Klingel, Person, Fahrzeug, Tier, Paket, Bewegung. Verzögerung als Feld „Sekunden (0–600)“, leer = 0. Entprellung zählt ab Eintreffen des Ereignisses; nach der Verzögerung wird die Regel neu gelesen (gelöscht → nichts). Ein Ton startet nur, wenn an keiner Kamera gerade gesprochen/angesagt wird (nie unterbrechen), sonst Logeintrag und Event-Log „… (fehlgeschlagen)“. Event-Log-Titel: „Klingel → Webhook + „Bin gleich da““. „Testen“ ruft den Webhook sofort auf. Regel-Tokens: eigener Schlüsselbund-Dienst `com.snackbits.UniFiCameraPopup.rule-token`; ein Import behält vorhandene Tokens gleicher Regel-IDs.
15. **Entscheidung:** Die zwei Lautstärken liegen in `SoundSettings` (Schlüssel `unifi.camera.popup.sound`, wie alle Ton-Einstellungen seit Phase 3). Diesen Schlüssel kennt die alte Version nicht, er ist also genauso geschützt wie `settingsExtensionsV2`; Ton-Einstellungen bleiben außerhalb des Exports.
16. **Entscheidung:** Ein gespeicherter Sprech-Modus (`talkMode`) wird beim Laden ignoriert und nicht mehr geschrieben.

## Offene Fragen

1. Entscheidungen 6 (Mikrofon-Kreis in schmalen Popups) und 14 (Ton einer Regel wird übersprungen, solange gesprochen wird) bestätigen?
2. Sollen ausgeführte Regeln zusätzlich in einem eigenen Protokoll (z. B. Reiter „Kameras“ › Ereignisse › „Zuletzt ausgeführt“) stehen, oder genügt das Event-Log im Menü?

---

## File Structure

```
Packages/AppCore/Sources/AppCore/
  PopupLayout.swift            (neu) PopupSizeOverride, PopupSizing, PopupAnchor, PopupStackLayout, PopupPillFit
  Sound/Loudness.swift         (neu) gated RMS, Spitze, Normalisierungsfaktor
  Sound/VoiceChoice.swift      (neu) Anna oder beste deutsche Stimme, Feldtext, Hinweis
  Sound/AnnouncementAudio.swift  + monoSamples, loudnessGain(of:), preferredVoice, candidate
  Sound/SoundSettings.swift    − TalkMode/talkMode; cameraVolume → talkVolume + announcementVolume
  Sound/Announcement.swift     + loudnessGain
  Talkback/AutomaticGainControl.swift (neu) Mikrofon-Ausgleich + Begrenzung −1 dBFS
  Talkback/TalkbackStreamer.swift + automaticGain (Begrenzung immer)
  EventRules.swift             (neu) EventRule(+Webhook, Liste), Matcher, Debouncer, Texte
  ActionAvailability.swift     (neu) Button: Webhook/Ton/beides
  SettingsExtensions.swift     + showNameAndTime, size, eventRules, Action.soundId
  DisplayText.swift            + version, updateButton, actionTarget
  DesignTokens.swift           + danger
Packages/AppCore/Tests/AppCoreTests/
  PopupLayoutTests, LoudnessTests, AutomaticGainControlTests, EventRulesTests, VoiceChoiceTests,
  ActionAvailabilityTests (neu); SettingsExtensionsTests, SoundSettingsTests, DisplayTextTests, DesignTokensTests (+)
UniFiCameraPopup/
  Models/WebhookMapping.swift  + showNameAndTime, sizeOverride, eventRules; CameraAction.soundId
  Models/PopupPosition.swift   + anchor
  Services/PopupController.swift  Stapel über PopupStackLayout, Animation, popupActions, popupSize
  Services/WindowPositioner.swift − stackedFrames
  Services/ProtectSession.swift  + aspectRatios
  Services/SettingsStore.swift  Erweiterungs-Felder, Regel-Tokens im Schlüsselbund, Import
  Services/TalkbackService.swift  − Leertaste/Modus; Verstärkungen; playAutomatically
  Services/PushToTalkKey.swift  (gelöscht)
  Services/SoundStore.swift     Lautheit messen, Anna
  Services/EventRuleService.swift (neu) Regeln ausführen
  Services/ProtectEventService.swift  ruft EventRuleService
  Services/KeychainStore.swift  + ruleTokenService
  Services/UpdateService.swift  + debugApply (DEBUG)
  Services/WhatsNewService.swift, Views/HelpView.swift  Texte
  Views/PopupWindow.swift, Views/Popup/PopupOverlayViews.swift, Views/Popup/PopupTalkViews.swift
  Views/StatusPanel/StatusPanel.swift, AppDelegate.swift
  Views/Settings/CamerasTab.swift, CameraAdvancedSection.swift, ActionEditorSheet.swift, SoundTab.swift
  Views/Settings/EventRulesSection.swift (neu) Abschnitt „Ereignisse“ + Regel-Sheet
  Debug/SnapshotRenderer.swift  neue Bilder für die Sichtprüfung
  Assets.xcassets/Icons/bellSlash.imageset/bellSlash.svg  Lucide bell-off
  scripts/pbxproj-add-files.py  + --prefix, Gruppen Services, Views/Settings
docs/design/*.md, docs/superpowers/manual-checks-1.2.0.md
```

---

### Task 1: AppCore – Popup-Größe, Stapel-Layout und Leisten-Passung

**Files:**
- Create: `Packages/AppCore/Sources/AppCore/PopupLayout.swift`
- Test: `Packages/AppCore/Tests/AppCoreTests/PopupLayoutTests.swift`

**Interfaces:**
- Consumes: nichts.
- Produces:
  - `public struct PopupSizeOverride: Codable, Equatable, Sendable { var width: Double?; var height: Double?; static let automatic; static let legacyDefault: CGSize; static let minimumValue = 40.0; var isAutomatic: Bool; static func migrated(width: Double, height: Double) -> PopupSizeOverride; static func value(fromText: String) -> Double? }`
  - `public enum PopupSizing { static let automaticHeightShare = 0.42; static func size(override: PopupSizeOverride, aspect: Double?, visible: CGSize, margin: CGFloat) -> CGSize; static func validAspect(_: Double?) -> Double }`
  - `public struct PopupAnchor { enum Horizontal { leading, center, trailing }; enum Vertical { top, middle, bottom }; init(horizontal:vertical:) }`
  - `public enum PopupStackLayout { static let gap: CGFloat = 12; static let minimumHeight: CGFloat = 160; static func frames(sizes: [CGSize], anchor: PopupAnchor, visible: CGRect, margin: CGFloat, gap: CGFloat = 12, minimumHeight: CGFloat = 160) -> [CGRect] }` – AppKit-Koordinaten (y nach oben), Reihenfolge wie `sizes`.
  - `public enum PopupPillFit { static func talkButtonFits(popupWidth: CGFloat, circles: Int, talkWidth: CGFloat) -> Bool }`

- [ ] **Step 1: Write the failing test**

Datei `Packages/AppCore/Tests/AppCoreTests/PopupLayoutTests.swift` neu anlegen:

```swift
import CoreGraphics
import XCTest
@testable import AppCore

final class PopupLayoutTests: XCTestCase {
    /// 1440 × 900 visible frame (menu bar already excluded), margin 16.
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let topRight = PopupAnchor(horizontal: .trailing, vertical: .top)
    private var auto: CGSize {
        PopupSizing.size(override: .automatic, aspect: nil, visible: visible.size, margin: 16)
    }

    // MARK: Größe

    func testAutomaticSizeIs42PercentOfVisibleHeight() {
        XCTAssertEqual(auto, CGSize(width: 672, height: 378))
        // Portrait camera picture: width follows the aspect ratio.
        XCTAssertEqual(PopupSizing.size(override: .automatic, aspect: 0.75, visible: visible.size, margin: 16),
                       CGSize(width: 284, height: 378))
    }

    func testTwoAutomaticPopupsFitBelowEachOther() {
        let frames = PopupStackLayout.frames(sizes: [auto, auto], anchor: topRight, visible: visible, margin: 16)
        XCTAssertEqual(frames, [
            CGRect(x: 752, y: 506, width: 672, height: 378),
            CGRect(x: 752, y: 116, width: 672, height: 378),
        ])
    }

    func testAutomaticSizeFitsNarrowScreens() {
        let narrow = CGSize(width: 500, height: 1200)
        let size = PopupSizing.size(override: .automatic, aspect: 16.0 / 9.0, visible: narrow, margin: 16)
        XCTAssertEqual(size.width, 468)
        XCTAssertEqual(size.height, 263)
    }

    func testOneTypedValueKeepsAspectRatio() {
        XCTAssertEqual(PopupSizing.size(override: PopupSizeOverride(width: 640), aspect: nil, visible: visible.size, margin: 16),
                       CGSize(width: 640, height: 360))
        XCTAssertEqual(PopupSizing.size(override: PopupSizeOverride(height: 300), aspect: 4.0 / 3.0, visible: visible.size, margin: 16),
                       CGSize(width: 400, height: 300))
        XCTAssertEqual(PopupSizing.size(override: PopupSizeOverride(width: 500, height: 200), aspect: nil, visible: visible.size, margin: 16),
                       CGSize(width: 500, height: 200))
    }

    func testTinyTypedValuesAreRaisedToMinimum() {
        XCTAssertEqual(PopupSizing.size(override: PopupSizeOverride(width: 5, height: 3), aspect: nil, visible: visible.size, margin: 16),
                       CGSize(width: 40, height: 40))
    }

    func testBrokenAspectFallsBackTo16by9() {
        for aspect in [Double.nan, 0, -1, 100] {
            XCTAssertEqual(PopupSizing.validAspect(aspect), 16.0 / 9.0)
        }
    }

    func testMigrationTreatsOldDefaultAsAutomatic() {
        XCTAssertTrue(PopupSizeOverride.migrated(width: 480, height: 270).isAutomatic)
        XCTAssertEqual(PopupSizeOverride.migrated(width: 640, height: 360), PopupSizeOverride(width: 640, height: 360))
    }

    func testFieldTextParsing() {
        XCTAssertNil(PopupSizeOverride.value(fromText: ""))
        XCTAssertNil(PopupSizeOverride.value(fromText: "abc"))
        XCTAssertEqual(PopupSizeOverride.value(fromText: "640 px"), 640)
        XCTAssertEqual(PopupSizeOverride.value(fromText: "5"), 5, "no clamping while typing")
        XCTAssertNil(PopupSizeOverride.value(fromText: "0"))
        XCTAssertEqual(PopupSizeOverride.value(fromText: "99999999"), 99999)
    }

    func testLenientDecoding() throws {
        let decoded = try JSONDecoder().decode(PopupSizeOverride.self, from: Data(#"{"width":"x","height":-3}"#.utf8))
        XCTAssertTrue(decoded.isAutomatic)
        let kept = try JSONDecoder().decode(PopupSizeOverride.self, from: Data(#"{"width":700}"#.utf8))
        XCTAssertEqual(kept, PopupSizeOverride(width: 700))
    }

    // MARK: Stapel

    func testThreePopupsShrinkUniformly() {
        let frames = PopupStackLayout.frames(sizes: [auto, auto, auto], anchor: topRight, visible: visible, margin: 16)
        XCTAssertEqual(frames.count, 3)
        let heights = Set(frames.map(\.height))
        XCTAssertEqual(heights.count, 1)
        XCTAssertLessThan(frames[0].height, 378)
        XCTAssertGreaterThanOrEqual(frames[0].height, 160)
        // Aspect ratio stays (± rounding).
        XCTAssertEqual(frames[0].width / frames[0].height, 672.0 / 378.0, accuracy: 0.01)
        // All on screen, in order from the top, 12 apart.
        for frame in frames { XCTAssertTrue(visible.insetBy(dx: 16, dy: 16).contains(frame)) }
        XCTAssertEqual(frames[0].minY - frames[1].maxY, 12)
        XCTAssertEqual(frames[0].maxY, 884)
    }

    func testManyPopupsUseSecondColumnInsteadOfGoingBelowMinimum() {
        let frames = PopupStackLayout.frames(sizes: Array(repeating: auto, count: 6), anchor: topRight, visible: visible, margin: 16)
        XCTAssertTrue(frames.allSatisfy { $0.height >= 160 })
        // Column 1 at the right edge, column 2 to its left.
        XCTAssertEqual(frames[0].maxX, 1424)
        XCTAssertEqual(frames[3].maxX, frames[0].minX - 12)
        XCTAssertEqual(frames[3].maxY, frames[0].maxY)
        for frame in frames { XCTAssertTrue(visible.insetBy(dx: 16, dy: 16).contains(frame)) }
    }

    func testRemainingPopupsGrowBackAfterOneCloses() {
        let three = PopupStackLayout.frames(sizes: [auto, auto, auto], anchor: topRight, visible: visible, margin: 16)
        let two = PopupStackLayout.frames(sizes: [auto, auto], anchor: topRight, visible: visible, margin: 16)
        XCTAssertGreaterThan(two[0].height, three[0].height)
        XCTAssertEqual(two[0].height, 378, "back to the configured size, not larger")
    }

    func testOversizedSinglePopupFitsScreen() {
        let frames = PopupStackLayout.frames(sizes: [CGSize(width: 3000, height: 2000)], anchor: topRight, visible: visible, margin: 16)
        let frame = frames[0]
        XCTAssertTrue(visible.insetBy(dx: 16, dy: 16).contains(frame))
        XCTAssertEqual(frame.width / frame.height, 1.5, accuracy: 0.01)
    }

    func testSmallPopupsNeverGrow() {
        let small = CGSize(width: 200, height: 120)
        let frames = PopupStackLayout.frames(sizes: [small], anchor: topRight, visible: visible, margin: 16)
        XCTAssertEqual(frames[0].size, small)
    }

    func testBottomAnchorStacksUpward() {
        let anchor = PopupAnchor(horizontal: .leading, vertical: .bottom)
        let frames = PopupStackLayout.frames(sizes: [auto, auto], anchor: anchor, visible: visible, margin: 16)
        XCTAssertEqual(frames[0], CGRect(x: 16, y: 16, width: 672, height: 378))
        XCTAssertEqual(frames[1].minY, frames[0].maxY + 12)
    }

    func testMiddleAnchorCentersTheStack() {
        let anchor = PopupAnchor(horizontal: .center, vertical: .middle)
        let frames = PopupStackLayout.frames(sizes: [auto, auto], anchor: anchor, visible: visible, margin: 16)
        let union = frames[0].union(frames[1])
        XCTAssertEqual(union.midY, 450, accuracy: 1)
        XCTAssertEqual(union.midX, 720, accuracy: 1)
        XCTAssertGreaterThan(frames[0].minY, frames[1].minY, "first popup on top")
    }

    func testScreenWithOffsetOrigin() {
        let second = CGRect(x: 1440, y: -200, width: 1920, height: 1055)
        let frames = PopupStackLayout.frames(sizes: [auto], anchor: topRight, visible: second, margin: 16)
        XCTAssertEqual(frames[0].maxX, 1440 + 1920 - 16)
        XCTAssertEqual(frames[0].maxY, -200 + 1055 - 16)
    }

    func testTalkButtonFallsBackToMicrophoneInNarrowPopups() {
        // Ton abspielen + three buttons + two-line talk button (≈ 207) = 387 wide.
        XCTAssertTrue(PopupPillFit.talkButtonFits(popupWidth: 470, circles: 4, talkWidth: 207))
        XCTAssertFalse(PopupPillFit.talkButtonFits(popupWidth: 284, circles: 4, talkWidth: 207))
        XCTAssertTrue(PopupPillFit.talkButtonFits(popupWidth: 284, circles: 1, talkWidth: 207))
        XCTAssertTrue(PopupPillFit.talkButtonFits(popupWidth: 284, circles: 4, talkWidth: 40), "microphone only fits the smallest 16:9 popup")
    }

    func testEmptyInput() {
        XCTAssertTrue(PopupStackLayout.frames(sizes: [], anchor: topRight, visible: visible, margin: 16).isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `(cd Packages/AppCore && swift test --filter PopupLayoutTests 2>&1 | grep -E "error:|Executed" | head -5)`
Expected: FAIL – `error: cannot find 'PopupSizing' in scope`

- [ ] **Step 3: Write minimal implementation**

Datei `Packages/AppCore/Sources/AppCore/PopupLayout.swift` neu anlegen:

```swift
import CoreGraphics
import Foundation

/// "Kamera › Größe": empty fields mean automatic. A single value keeps the aspect ratio.
public struct PopupSizeOverride: Codable, Equatable, Sendable {
    public var width: Double?
    public var height: Double?

    public static let automatic = PopupSizeOverride()
    /// The size every camera had before Phase 5 unless the user changed it.
    public static let legacyDefault = CGSize(width: 480, height: 270)
    /// Smallest popup side a typed value results in (applied by `PopupSizing`, not while typing).
    public static let minimumValue = 40.0

    public init(width: Double? = nil, height: Double? = nil) {
        self.width = Self.valid(width)
        self.height = Self.valid(height)
    }

    public var isAutomatic: Bool { width == nil && height == nil }

    /// Pre-Phase-5 entries: 480 × 270 counts as "never changed" (automatic), anything else is kept.
    public static func migrated(width: Double, height: Double) -> PopupSizeOverride {
        if width == Double(legacyDefault.width), height == Double(legacyDefault.height) { return .automatic }
        return PopupSizeOverride(width: width, height: height)
    }

    /// Text of a size field → value: digits only (at most 5), empty or 0 = automatic (nil).
    public static func value(fromText text: String) -> Double? {
        let digits = text.filter(\.isASCIIDigitCharacter)
        guard !digits.isEmpty, let parsed = Double(digits.prefix(5)), parsed > 0 else { return nil }
        return parsed
    }

    private static func valid(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private enum CodingKeys: String, CodingKey { case width, height }

    /// Lenient: a broken value counts as empty (automatic).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            width: (try? c.decodeIfPresent(Double.self, forKey: .width)) ?? nil,
            height: (try? c.decodeIfPresent(Double.self, forKey: .height)) ?? nil
        )
    }
}

private extension Character {
    var isASCIIDigitCharacter: Bool { isASCII && isNumber }
}

/// Size a camera popup asks for before stacking (Phase 5 default: 42 % of the visible height).
public enum PopupSizing {
    public static let automaticHeightShare = 0.42
    public static let defaultAspect = 16.0 / 9.0

    /// `aspect` = width / height (crop, camera picture or nil → 16:9). Automatic sizes also fit
    /// the visible width minus both margins.
    public static func size(
        override: PopupSizeOverride,
        aspect: Double?,
        visible: CGSize,
        margin: CGFloat
    ) -> CGSize {
        let ratio = validAspect(aspect)
        let minimum = PopupSizeOverride.minimumValue
        switch (override.width.map { max(minimum, $0) }, override.height.map { max(minimum, $0) }) {
        case let (width?, height?):
            return CGSize(width: width, height: height)
        case let (width?, nil):
            return CGSize(width: width, height: (width / ratio).rounded())
        case let (nil, height?):
            return CGSize(width: (height * ratio).rounded(), height: height)
        case (nil, nil):
            var height = Double(visible.height) * automaticHeightShare
            var width = height * ratio
            let maxWidth = max(Double(visible.width - 2 * margin), 1)
            if width > maxWidth {
                width = maxWidth
                height = width / ratio
            }
            return CGSize(width: width.rounded(), height: height.rounded())
        }
    }

    public static func validAspect(_ aspect: Double?) -> Double {
        guard let aspect, aspect.isFinite, aspect > 0.2, aspect < 5 else { return defaultAspect }
        return aspect
    }
}

/// Where the popup stack sits (mirrors the app's `PopupPosition`).
public struct PopupAnchor: Equatable, Sendable {
    public enum Horizontal: Sendable { case leading, center, trailing }
    public enum Vertical: Sendable { case top, middle, bottom }

    public let horizontal: Horizontal
    public let vertical: Vertical

    public init(horizontal: Horizontal, vertical: Vertical) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
}

/// Lays out all open popups so that every one is fully visible: one uniform scale factor
/// (aspect ratios stay), never larger than asked for, at least `minimumHeight` per popup where
/// possible – otherwise further columns next to the first. Coordinates are AppKit screen
/// coordinates (y up); the result keeps the order of `sizes` (first = at the anchor).
public enum PopupStackLayout {
    public static let gap: CGFloat = 12
    public static let minimumHeight: CGFloat = 160

    public static func frames(
        sizes: [CGSize],
        anchor: PopupAnchor,
        visible: CGRect,
        margin: CGFloat,
        gap: CGFloat = PopupStackLayout.gap,
        minimumHeight: CGFloat = PopupStackLayout.minimumHeight
    ) -> [CGRect] {
        guard !sizes.isEmpty else { return [] }
        let area = visible.insetBy(dx: min(margin, visible.width / 2), dy: min(margin, visible.height / 2))
        let sizes = sizes.map { CGSize(width: max($0.width, 1), height: max($0.height, 1)) }

        // Fewest columns whose scale keeps every popup at its minimum; else the largest scale.
        var best: (columns: [[Int]], scale: CGFloat)?
        for count in 1...sizes.count {
            let columns = split(sizes.indices.map { $0 }, into: count)
            let s = scale(columns: columns, sizes: sizes, area: area.size, gap: gap)
            let keepsMinimum = s >= 1 || sizes.allSatisfy { $0.height * s >= min($0.height, minimumHeight) - 0.5 }
            if keepsMinimum {
                best = (columns, s)
                break
            }
            if best == nil || s > best!.scale + 0.0001 {
                best = (columns, s)
            }
        }
        guard let (columns, s) = best else { return [] }
        return place(columns: columns, sizes: sizes, scale: s, anchor: anchor, area: area, gap: gap)
    }

    /// Consecutive groups: the first `ceil(n / count)` popups in column 1, and so on.
    static func split(_ indices: [Int], into count: Int) -> [[Int]] {
        let perColumn = Int((Double(indices.count) / Double(count)).rounded(.up))
        return stride(from: 0, to: indices.count, by: perColumn).map {
            Array(indices[$0..<min($0 + perColumn, indices.count)])
        }
    }

    static func scale(columns: [[Int]], sizes: [CGSize], area: CGSize, gap: CGFloat) -> CGFloat {
        var s: CGFloat = 1
        for column in columns {
            let heights = column.reduce(0) { $0 + sizes[$1].height }
            let room = area.height - gap * CGFloat(column.count - 1)
            s = min(s, room / heights)
        }
        let widths = columns.reduce(0) { total, column in total + (column.map { sizes[$0].width }.max() ?? 0) }
        s = min(s, (area.width - gap * CGFloat(columns.count - 1)) / widths)
        return max(s, 0.01)
    }

    private static func place(
        columns: [[Int]],
        sizes: [CGSize],
        scale s: CGFloat,
        anchor: PopupAnchor,
        area: CGRect,
        gap: CGFloat
    ) -> [CGRect] {
        let scaled = sizes.map { CGSize(width: ($0.width * s).rounded(.down), height: ($0.height * s).rounded(.down)) }
        let columnWidths = columns.map { column in column.map { scaled[$0].width }.max() ?? 0 }
        let totalWidth = columnWidths.reduce(0, +) + gap * CGFloat(columns.count - 1)
        var frames = [CGRect](repeating: .zero, count: sizes.count)

        // Column 1 sits at the anchor; further columns grow away from it (centered: as one block).
        var cursor: CGFloat
        switch anchor.horizontal {
        case .leading: cursor = area.minX
        case .trailing: cursor = area.maxX
        case .center: cursor = (area.midX - totalWidth / 2).rounded()
        }
        for (index, column) in columns.enumerated() {
            let width = columnWidths[index]
            let columnMinX: CGFloat
            switch anchor.horizontal {
            case .leading, .center:
                columnMinX = cursor
                cursor += width + gap
            case .trailing:
                columnMinX = cursor - width
                cursor -= width + gap
            }
            let columnHeight = column.reduce(0) { $0 + scaled[$1].height } + gap * CGFloat(column.count - 1)
            var top: CGFloat
            switch anchor.vertical {
            case .top: top = area.maxY
            case .middle: top = (area.midY + columnHeight / 2).rounded()
            case .bottom: top = area.minY + columnHeight
            }
            // Bottom anchors keep the first popup at the bottom edge (stack grows upward).
            let ordered = anchor.vertical == .bottom ? column.reversed() : column
            for item in ordered {
                let size = scaled[item]
                let x: CGFloat
                switch anchor.horizontal {
                case .leading: x = columnMinX
                case .trailing: x = columnMinX + width - size.width
                case .center: x = (columnMinX + (width - size.width) / 2).rounded()
                }
                frames[item] = CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
                top -= size.height + gap
            }
        }
        return frames
    }
}

/// The popup's bottom pill (padding 6, gap 8, circles 34) must stay 10 pt inside the popup, or the
/// window would grow with it. The two-line talk button is used while it fits, else only the microphone.
public enum PopupPillFit {
    public static func talkButtonFits(popupWidth: CGFloat, circles: Int, talkWidth: CGFloat) -> Bool {
        12 + CGFloat(max(circles, 0)) * (34 + 8) + talkWidth <= popupWidth - 20
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `(cd Packages/AppCore && swift test --filter PopupLayoutTests 2>&1 | grep -E "error:|Executed" | tail -1)`
Expected: `Executed 19 tests, with 0 failures`

Dann alle AppCore-Tests (Befehl oben) → 0 failures; Build-Befehl → `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Packages/AppCore/Sources/AppCore/PopupLayout.swift Packages/AppCore/Tests/AppCoreTests/PopupLayoutTests.swift
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "feat(core): popup size default, stack layout and pill fit" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: AppCore – Einheitliche Lautheit und automatische Mikrofon-Verstärkung

**Files:**
- Create: `Packages/AppCore/Sources/AppCore/Sound/Loudness.swift`
- Create: `Packages/AppCore/Sources/AppCore/Talkback/AutomaticGainControl.swift`
- Modify: `Packages/AppCore/Sources/AppCore/Sound/AnnouncementAudio.swift` (vor `write(_:to:)`)
- Modify: `Packages/AppCore/Sources/AppCore/Talkback/TalkbackStreamer.swift` (Eigenschaften, `init`, `append`)
- Test: `Packages/AppCore/Tests/AppCoreTests/LoudnessTests.swift`, `Packages/AppCore/Tests/AppCoreTests/AutomaticGainControlTests.swift`

**Interfaces:**
- Consumes: nichts.
- Produces:
  - `public enum Loudness { static let targetDBFS: Float = -20; static let ceilingDBFS: Float = -1; static func dB(_: Float) -> Float; static func linear(_: Float) -> Float; static func gatedRMSdB(_: [Float], sampleRate: Double) -> Float?; static func peakDB(_: [Float]) -> Float; static func normalizationGain(_: [Float], sampleRate: Double) -> Float }`
  - `public final class AutomaticGainControl { init(sampleRate: Int, outputGain: Float = 1, adaptive: Bool = true); func process(_: [Int16]) -> [Int16]; private(set) var gainDB: Float; static let ceiling: Float }`
  - `AnnouncementAudio.monoSamples(_: AVAudioPCMBuffer) throws -> [Float]`, `AnnouncementAudio.loudnessGain(of: AVAudioPCMBuffer) throws -> Float`
  - `TalkbackStreamer.init(target:gain:automaticGain: Bool = false, readyTimeout:log:onEvent:)` – `gain` = Lautstärke des Nutzers, `automaticGain` = Mikrofon-Ausgleich; Spitzen immer ≤ −1 dBFS.

- [ ] **Step 1: Write the failing tests**

Datei `Packages/AppCore/Tests/AppCoreTests/LoudnessTests.swift` neu anlegen:

```swift
import AVFoundation
import XCTest
@testable import AppCore

final class LoudnessTests: XCTestCase {
    private func sine(_ amplitude: Float, seconds: Double, rate: Double = 16_000) -> [Float] {
        (0..<Int(seconds * rate)).map { amplitude * Float(sin(2 * .pi * 440 * Double($0) / rate)) }
    }

    func testPausesDoNotCount() throws {
        // Sine 0.1 = −23 dBFS RMS; one second of silence after it changes nothing.
        let speech = sine(0.1, seconds: 1) + [Float](repeating: 0, count: 16_000)
        let rms = try XCTUnwrap(Loudness.gatedRMSdB(speech, sampleRate: 16_000))
        XCTAssertEqual(rms, -23.0, accuracy: 0.2)
        XCTAssertEqual(Loudness.dB(Loudness.normalizationGain(speech, sampleRate: 16_000)), 3.0, accuracy: 0.2)
    }

    func testLoudFileIsTurnedDown() {
        let loud = sine(0.9, seconds: 1)
        XCTAssertEqual(Loudness.dB(Loudness.normalizationGain(loud, sampleRate: 16_000)), -16.1, accuracy: 0.2)
    }

    func testSpikeLimitsGain() {
        // Quiet speech (−29 dBFS) with one click near full scale: the peak, not the level, decides.
        var samples = sine(0.05, seconds: 1)
        samples[8_000] = 0.9
        let gain = Loudness.dB(Loudness.normalizationGain(samples, sampleRate: 16_000))
        XCTAssertEqual(gain, -1 - Loudness.dB(0.9), accuracy: 0.05)
        XCTAssertLessThanOrEqual(0.9 * Loudness.linear(gain), Loudness.linear(-1) + 0.0001)
    }

    func testBoostIsCapped() {
        let quiet = sine(0.01, seconds: 1) // −43 dBFS
        XCTAssertEqual(Loudness.dB(Loudness.normalizationGain(quiet, sampleRate: 16_000)), 18, accuracy: 0.01)
    }

    func testSilentFileKeepsGain() {
        XCTAssertEqual(Loudness.normalizationGain([Float](repeating: 0, count: 16_000), sampleRate: 16_000), 1)
        XCTAssertEqual(Loudness.normalizationGain([], sampleRate: 16_000), 1)
        // Only hiss below the gate: not boosted.
        XCTAssertEqual(Loudness.normalizationGain(sine(0.001, seconds: 1), sampleRate: 16_000), 1)
    }

    func testBufferMeasurementAveragesChannels() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        buffer.frameLength = 16_000
        let tone = sine(0.1, seconds: 1)
        for index in 0..<16_000 {
            buffer.floatChannelData![0][index] = tone[index]
            buffer.floatChannelData![1][index] = tone[index]
        }
        XCTAssertEqual(try AnnouncementAudio.monoSamples(buffer).count, 16_000)
        XCTAssertEqual(Loudness.dB(try AnnouncementAudio.loudnessGain(of: buffer)), 3.0, accuracy: 0.2)
    }
}
```

Datei `Packages/AppCore/Tests/AppCoreTests/AutomaticGainControlTests.swift` neu anlegen:

```swift
import XCTest
@testable import AppCore

final class AutomaticGainControlTests: XCTestCase {
    private let rate = 16_000

    /// Sine with the given RMS level in dBFS.
    private func tone(dBFS: Float, seconds: Double) -> [Int16] {
        let amplitude = Double(Loudness.linear(dBFS)) * 32_768 * 2.0.squareRoot()
        return (0..<Int(seconds * Double(rate))).map {
            Int16(max(-32_768, min(32_767, amplitude * sin(2 * .pi * 440 * Double($0) / Double(rate)))))
        }
    }

    private func rmsDB(_ samples: ArraySlice<Int16>) -> Float {
        let sum = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        return Loudness.dB(Float((sum / Double(samples.count)).squareRoot()) / 32_768)
    }

    /// Feeds in microphone-sized chunks (1024 frames).
    private func run(_ agc: AutomaticGainControl, _ input: [Int16]) -> [Int16] {
        stride(from: 0, to: input.count, by: 1_024).flatMap {
            agc.process(Array(input[$0..<min($0 + 1_024, input.count)]))
        }
    }

    func testQuietSpeechIsRaisedToTarget() {
        let output = run(AutomaticGainControl(sampleRate: rate), tone(dBFS: -30, seconds: 3))
        XCTAssertEqual(rmsDB(output.suffix(rate)), -20, accuracy: 1)
    }

    func testBoostStopsAt18dB() {
        let output = run(AutomaticGainControl(sampleRate: rate), tone(dBFS: -45, seconds: 3))
        XCTAssertEqual(rmsDB(output.suffix(rate)), -27, accuracy: 1)
    }

    func testNoiseIsNotBoosted() {
        let agc = AutomaticGainControl(sampleRate: rate)
        let noise = tone(dBFS: -70, seconds: 2)
        let output = run(agc, noise)
        XCTAssertEqual(agc.gainDB, 0)
        XCTAssertEqual(rmsDB(output[...]), rmsDB(noise[...]), accuracy: 0.1)
    }

    func testBurstAfterQuietNeverExceedsCeiling() {
        let agc = AutomaticGainControl(sampleRate: rate, outputGain: 1.5)
        let quiet = run(agc, tone(dBFS: -45, seconds: 2))
        XCTAssertGreaterThan(agc.gainDB, 15)
        let burst = run(agc, tone(dBFS: -3, seconds: 0.5))
        let peak = burst.map { abs(Int32($0)) }.max() ?? 0
        XCTAssertLessThanOrEqual(Float(peak), AutomaticGainControl.ceiling + 1)
        XCTAssertFalse(quiet.isEmpty)
    }

    func testUserVolumeOnTop() {
        let output = run(AutomaticGainControl(sampleRate: rate, outputGain: 1.5), tone(dBFS: -20, seconds: 2))
        XCTAssertEqual(rmsDB(output.suffix(rate)), -20 + Loudness.dB(1.5), accuracy: 0.5)
    }

    func testFixedGainOnlyLimits() {
        // Announcements: no automatic gain, just volume and the −1 dBFS ceiling.
        let agc = AutomaticGainControl(sampleRate: rate, outputGain: 1.5, adaptive: false)
        let quiet = tone(dBFS: -30, seconds: 1)
        XCTAssertEqual(rmsDB(run(agc, quiet).suffix(rate / 2)), -30 + Loudness.dB(1.5), accuracy: 0.3)
        let loud = run(agc, tone(dBFS: -4, seconds: 1))
        XCTAssertLessThanOrEqual(Float(loud.map { abs(Int32($0)) }.max() ?? 0), AutomaticGainControl.ceiling + 1)
        XCTAssertEqual(agc.gainDB, 0)
    }

    func testEmptyInput() {
        XCTAssertTrue(AutomaticGainControl(sampleRate: rate).process([]).isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `(cd Packages/AppCore && swift test --filter "LoudnessTests|AutomaticGainControlTests" 2>&1 | grep -E "error:|Executed" | head -5)`
Expected: FAIL – `error: cannot find 'Loudness' in scope`

- [ ] **Step 3: Implement Loudness and AutomaticGainControl**

Datei `Packages/AppCore/Sources/AppCore/Sound/Loudness.swift` neu anlegen:

```swift
import Foundation

/// One loudness for every announcement (Phase 5): −20 dBFS RMS, peaks at most −1 dBFS.
/// The microphone (`AutomaticGainControl`) aims at the same level, so talking and
/// announcements arrive equally loud at the camera.
public enum Loudness {
    public static let targetDBFS: Float = -20
    public static let ceilingDBFS: Float = -1
    /// Blocks quieter than this are pauses and do not count (no boosting of breaks).
    public static let gateDBFS: Float = -50
    public static let maxBoostDB: Float = 18
    public static let maxCutDB: Float = -30
    /// Measuring block (50 ms).
    public static let blockSeconds = 0.05

    public static func dB(_ linear: Float) -> Float {
        linear > 0 ? 20 * log10(linear) : -120
    }

    public static func linear(_ dB: Float) -> Float {
        pow(10, dB / 20)
    }

    /// RMS of the blocks above `gateDBFS` (samples −1…1, mono); nil = silence only.
    public static func gatedRMSdB(_ samples: [Float], sampleRate: Double) -> Float? {
        let block = max(1, Int(sampleRate * blockSeconds))
        var sum: Double = 0
        var counted = 0
        var start = 0
        while start < samples.count {
            let end = min(start + block, samples.count)
            var blockSum: Double = 0
            for index in start..<end {
                let value = Double(samples[index])
                blockSum += value * value
            }
            let rms = Float((blockSum / Double(end - start)).squareRoot())
            if dB(rms) > gateDBFS {
                sum += blockSum
                counted += end - start
            }
            start = end
        }
        guard counted > 0 else { return nil }
        return dB(Float((sum / Double(counted)).squareRoot()))
    }

    public static func peakDB(_ samples: [Float]) -> Float {
        dB(samples.reduce(0) { max($0, abs($1)) })
    }

    /// Factor that brings the samples to −20 dBFS RMS without peaks above −1 dBFS
    /// (between −30 and +18 dB). Silence keeps 1.
    public static func normalizationGain(_ samples: [Float], sampleRate: Double) -> Float {
        guard let rms = gatedRMSdB(samples, sampleRate: sampleRate) else { return 1 }
        let byLevel = targetDBFS - rms
        let byPeak = ceilingDBFS - peakDB(samples)
        return linear(min(maxBoostDB, max(maxCutDB, min(byLevel, byPeak))))
    }
}
```

Datei `Packages/AppCore/Sources/AppCore/Talkback/AutomaticGainControl.swift` neu anlegen:

```swift
import Foundation

/// Level control between resampler and encoder (16-bit mono at the camera rate).
///
/// `adaptive` (microphone): brings speech to −20 dBFS RMS like the announcements – at most +18 dB,
/// at least −12 dB; the gain falls at once and rises by at most 12 dB/s; blocks below −50 dBFS
/// (pauses, room noise) leave it unchanged. Always: `outputGain` (the user's volume) on top and a
/// fast peak limit at −1 dBFS, in 10 ms blocks. Not thread-safe: use from one queue.
public final class AutomaticGainControl {
    public static let targetDBFS: Float = Loudness.targetDBFS
    public static let maxGainDB: Float = 18
    public static let minGainDB: Float = -12
    public static let gateDBFS: Float = -50
    public static let riseDBPerSecond: Float = 12
    public static let ceiling: Float = Loudness.linear(Loudness.ceilingDBFS) * 32_767

    public let sampleRate: Int
    public let outputGain: Float
    public let adaptive: Bool
    /// Current automatic gain in dB (0 when not adaptive).
    public private(set) var gainDB: Float = 0
    private var applied: Float

    public init(sampleRate: Int, outputGain: Float = 1, adaptive: Bool = true) {
        self.sampleRate = max(sampleRate, 1)
        self.outputGain = max(0, outputGain.isFinite ? outputGain : 1)
        self.adaptive = adaptive
        applied = self.outputGain
    }

    public func process(_ samples: [Int16]) -> [Int16] {
        guard !samples.isEmpty else { return [] }
        let block = max(1, sampleRate / 100)
        var output: [Int16] = []
        output.reserveCapacity(samples.count)
        var start = 0
        while start < samples.count {
            let end = min(start + block, samples.count)
            processBlock(samples[start..<end], into: &output)
            start = end
        }
        return output
    }

    private func processBlock(_ chunk: ArraySlice<Int16>, into output: inout [Int16]) {
        var sumSquares: Double = 0
        var peak: Float = 0
        for sample in chunk {
            let value = Float(sample)
            sumSquares += Double(value) * Double(value)
            peak = max(peak, abs(value))
        }
        if adaptive {
            let level = Loudness.dB(Float((sumSquares / Double(chunk.count)).squareRoot()) / 32_768)
            if level > Self.gateDBFS {
                let desired = min(Self.maxGainDB, max(Self.minGainDB, Self.targetDBFS - level))
                if desired < gainDB {
                    gainDB = desired
                } else {
                    let step = Self.riseDBPerSecond * Float(chunk.count) / Float(sampleRate)
                    gainDB = min(desired, gainDB + step)
                }
            }
        }
        var target = Loudness.linear(gainDB) * outputGain
        if peak > 0, peak * target > Self.ceiling {
            target = Self.ceiling / peak
        }
        // Falling: at once (no peak slips through). Rising: ramp across the block (no click).
        let from = target < applied ? target : applied
        let count = Float(chunk.count)
        for (offset, sample) in chunk.enumerated() {
            let gain = from + (target - from) * Float(offset + 1) / count
            let scaled = (Float(sample) * gain).rounded()
            output.append(Int16(max(-32_768, min(32_767, scaled))))
        }
        applied = target
    }
}
```

In `Packages/AppCore/Sources/AppCore/Sound/AnnouncementAudio.swift` ersetzen:

```swift
    /// Writes a buffer as CAF (used to cache rendered speech).
```

durch:

```swift
    /// All channels averaged to one float channel (−1…1).
    public static func monoSamples(_ buffer: AVAudioPCMBuffer) throws -> [Float] {
        let float = try standardized(buffer)
        guard let channels = float.floatChannelData else { return [] }
        let count = Int(float.frameLength)
        let channelCount = Int(float.format.channelCount)
        guard count > 0, channelCount > 0 else { return [] }
        var mono = [Float](repeating: 0, count: count)
        for channel in 0..<channelCount {
            let data = channels[channel]
            for index in 0..<count { mono[index] += data[index] }
        }
        if channelCount > 1 {
            let scale = 1 / Float(channelCount)
            for index in 0..<count { mono[index] *= scale }
        }
        return mono
    }

    /// Factor for one loudness across all announcements (see `Loudness`).
    public static func loudnessGain(of buffer: AVAudioPCMBuffer) throws -> Float {
        Loudness.normalizationGain(try monoSamples(buffer), sampleRate: buffer.format.sampleRate)
    }

    /// Writes a buffer as CAF (used to cache rendered speech).
```

- [ ] **Step 4: Level control in the streamer**

In `Packages/AppCore/Sources/AppCore/Talkback/TalkbackStreamer.swift` ersetzen:

```swift
    private let resampler: PCMResampler
```

durch:

```swift
    private let resampler: PCMResampler
    private let level: AutomaticGainControl
```

In `Packages/AppCore/Sources/AppCore/Talkback/TalkbackStreamer.swift` ersetzen:

```swift
    /// Throws for codecs or rates the encoder cannot produce.
    public init(
        target: TalkbackTarget,
        gain: Float = 1,
```

durch:

```swift
    /// Throws for codecs or rates the encoder cannot produce. `gain` is the user's volume;
    /// `automaticGain` levels the microphone (see `AutomaticGainControl`). Peaks never exceed −1 dBFS.
    public init(
        target: TalkbackTarget,
        gain: Float = 1,
        automaticGain: Bool = false,
```

In `Packages/AppCore/Sources/AppCore/Talkback/TalkbackStreamer.swift` ersetzen:

```swift
        resampler = PCMResampler(sampleRate: target.sampleRate, gain: gain)
```

durch:

```swift
        resampler = PCMResampler(sampleRate: target.sampleRate)
        level = AutomaticGainControl(sampleRate: target.sampleRate, outputGain: gain, adaptive: automaticGain)
```

In `Packages/AppCore/Sources/AppCore/Talkback/TalkbackStreamer.swift` ersetzen:

```swift
                let samples = try self.resampler.convert(copy)
```

durch:

```swift
                let samples = self.level.process(try self.resampler.convert(copy))
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `(cd Packages/AppCore && swift test --filter "LoudnessTests|AutomaticGainControlTests|TalkbackStreamerTests" 2>&1 | grep -E "error:|Executed" | tail -1)`
Expected: `Executed 19 tests, with 0 failures`

Dann alle AppCore-Tests → 0 failures; Build-Befehl → `** BUILD SUCCEEDED **` (die App übergibt noch keinen `automaticGain`: Verhalten bis Task 8 = bisherige Lautstärke plus Begrenzung auf −1 dBFS).

- [ ] **Step 6: Commit**

```bash
git add Packages/AppCore/Sources/AppCore/Sound/Loudness.swift Packages/AppCore/Sources/AppCore/Talkback/AutomaticGainControl.swift \
  Packages/AppCore/Sources/AppCore/Sound/AnnouncementAudio.swift Packages/AppCore/Sources/AppCore/Talkback/TalkbackStreamer.swift \
  Packages/AppCore/Tests/AppCoreTests/LoudnessTests.swift Packages/AppCore/Tests/AppCoreTests/AutomaticGainControlTests.swift
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "feat(core): common loudness for announcements, automatic microphone gain, −1 dBFS limit" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: AppCore – Stimme, Ereignis-Regeln, Buttons mit Ton, neue Erweiterungs-Felder, Texte

**Files:**
- Create: `Packages/AppCore/Sources/AppCore/Sound/VoiceChoice.swift`
- Create: `Packages/AppCore/Sources/AppCore/EventRules.swift`
- Create: `Packages/AppCore/Sources/AppCore/ActionAvailability.swift`
- Modify: `Packages/AppCore/Sources/AppCore/Sound/AnnouncementAudio.swift` (Stimmenwahl, Standardstimme von `render`)
- Modify: `Packages/AppCore/Sources/AppCore/SettingsExtensions.swift` (`Mapping`, `Action`)
- Modify: `Packages/AppCore/Sources/AppCore/DisplayText.swift` (anhängen)
- Modify: `Packages/AppCore/Sources/AppCore/DesignTokens.swift` (`danger`)
- Test: `EventRulesTests.swift`, `VoiceChoiceTests.swift`, `ActionAvailabilityTests.swift` (neu), `SettingsExtensionsTests.swift`, `DisplayTextTests.swift`, `DesignTokensTests.swift` (alle in `Packages/AppCore/Tests/AppCoreTests/`)

**Interfaces:**
- Consumes: `PopupSizeOverride` (Task 1).
- Produces:
  - `public enum VoiceChoice { struct Candidate { identifier, name, language: String; quality: Int }; static func pick(from: [Candidate]) -> Candidate?; static func fieldLabel(_: Candidate?) -> String; static func hint(_: Candidate?) -> String? }`
  - `AnnouncementAudio.preferredVoice() -> AVSpeechSynthesisVoice?`, `AnnouncementAudio.candidate(_: AVSpeechSynthesisVoice) -> VoiceChoice.Candidate`; `render(text:voiceIdentifier: nil)` spricht jetzt mit `preferredVoice()`.
  - `public struct EventRuleWebhook { var method: String; var url: String; var requestURL: URL? }`
  - `public struct EventRule: Identifiable { var id: UUID; var kind: String /* TriggerKind.rawValue */; var webhook: EventRuleWebhook?; var bearerToken: String /* nie kodiert */; var soundId: UUID?; var delaySeconds: Int; var hasWebhook: Bool; var isConfigured: Bool; static let maxDelay = 600; static let debounce: TimeInterval = 30; static let maxPerCamera = 10; static func delay(fromText: String) -> Int }`
  - `public struct EventRuleList: Codable { var rules: [EventRule]; init(_ rules: [EventRule] = []) }` – verlustarm dekodiert, kodiert als Array.
  - `public enum EventRuleMatcher { static func matching(_: [EventRule], kinds: Set<String>, canPlaySound: Bool, soundExists: (UUID) -> Bool) -> [EventRule] }`
  - `public struct EventRuleDebouncer { mutating func shouldRun(entry: String, rule: UUID, at: Date, window: TimeInterval = 30) -> Bool }`
  - `public enum EventRuleText { static func actionSummary(webhookAddress: String?, soundName: String?, delaySeconds: Int) -> String; static func logTitle(kindLabel: String, webhook: Bool, soundName: String?, failed: Bool) -> String }`
  - `public enum ActionAvailability { static func isConfigured(title:address:hasValidURL:hasSound:) -> Bool; static func isShown(hasWebhook:hasSound:canPlaySound:) -> Bool; static func playsSound(hasSound:canPlaySound:) -> Bool }`
  - `SettingsExtensions.Mapping`: `+ showNameAndTime: Bool?`, `+ size: PopupSizeOverride?`, `+ eventRules: EventRuleList?` (nil = von einer älteren Build geschrieben); `SettingsExtensions.Action`: `+ soundId: String?`
  - `DisplayText.version(short: String, build: Int) -> String`, `DisplayText.updateButton(targetShort: String?, targetBuild: Int, currentShort: String) -> String`, `DisplayText.actionTarget(url: String, soundName: String?) -> String`
  - `Tokens.danger = ThemeColor(0xD70015, 0xFF6961)`

- [ ] **Step 1: Write the failing tests**

Datei `Packages/AppCore/Tests/AppCoreTests/EventRulesTests.swift` neu anlegen:

```swift
import XCTest
@testable import AppCore

final class EventRulesTests: XCTestCase {
    private let door = "DOOR-ENTRY"
    private let gong = UUID(uuidString: "6F0C6A52-4C4B-4E58-9B1E-2F3C1C0A0001")!

    private func rule(_ kind: String, url: String? = nil, sound: UUID? = nil) -> EventRule {
        EventRule(kind: kind, webhook: url.map { EventRuleWebhook(method: "POST", url: $0) }, soundId: sound)
    }

    func testTokenNeverEncoded() throws {
        let secret = EventRule(kind: "ring", webhook: EventRuleWebhook(url: "https://ha.local/x"), bearerToken: "geheim-123")
        let json = String(decoding: try JSONEncoder().encode(EventRuleList([secret])), as: UTF8.self)
        XCTAssertFalse(json.contains("geheim-123"))
        XCTAssertFalse(json.contains("bearerToken"))
        let back = try JSONDecoder().decode(EventRuleList.self, from: Data(json.utf8))
        XCTAssertEqual(back.rules.first?.id, secret.id)
        XCTAssertEqual(back.rules.first?.bearerToken, "")
    }

    func testLenientListKeepsGoodEntries() throws {
        let json = #"[{"kind":"ring","delaySeconds":"x"},42,{"nokind":true},{"kind":"motion","delaySeconds":9999,"webhook":{"method":"PUT","url":"http://a.b"}}]"#
        let list = try JSONDecoder().decode(EventRuleList.self, from: Data(json.utf8))
        XCTAssertEqual(list.rules.map(\.kind), ["ring", "motion"])
        XCTAssertEqual(list.rules[0].delaySeconds, 0)
        XCTAssertEqual(list.rules[1].delaySeconds, 600)
        XCTAssertEqual(list.rules[1].webhook?.method, "POST")
    }

    func testDelayFromText() {
        XCTAssertEqual(EventRule.delay(fromText: ""), 0)
        XCTAssertEqual(EventRule.delay(fromText: "abc"), 0)
        XCTAssertEqual(EventRule.delay(fromText: "-5"), 5)
        XCTAssertEqual(EventRule.delay(fromText: "45 s"), 45)
        XCTAssertEqual(EventRule.delay(fromText: "9999"), 600)
        XCTAssertEqual(EventRule.delay(fromText: "99999999999999999999"), 600)
        XCTAssertEqual(EventRule(kind: "ring", delaySeconds: -3).delaySeconds, 0)
    }

    func testIsConfigured() {
        XCTAssertFalse(rule("ring").isConfigured)
        XCTAssertTrue(rule("ring", url: "https://ha.local/hook").isConfigured)
        XCTAssertFalse(rule("ring", url: "ha.local/hook").isConfigured, "invalid address never saves")
        XCTAssertFalse(rule("ring", url: "ftp://x", sound: gong).isConfigured)
        XCTAssertTrue(rule("ring", url: "  ", sound: gong).isConfigured)
        XCTAssertTrue(rule("ring", sound: gong).isConfigured)
    }

    func testMatcherPicksKindAndSkipsRulesThatCannotRun() {
        let rules = [
            rule("ring", url: "https://ha.local/a"),
            rule("person", url: "https://ha.local/b"),
            rule("ring", sound: gong),
            rule("ring", sound: UUID()),            // announcement deleted
            rule("ring", url: "https://ha.local/c", sound: gong),
        ]
        let withSpeaker = EventRuleMatcher.matching(rules, kinds: ["ring"], canPlaySound: true) { $0 == self.gong }
        XCTAssertEqual(withSpeaker.map(\.id), [rules[0].id, rules[2].id, rules[4].id])
        let noSpeaker = EventRuleMatcher.matching(rules, kinds: ["ring"], canPlaySound: false) { $0 == self.gong }
        XCTAssertEqual(noSpeaker.map(\.id), [rules[0].id, rules[4].id], "webhook part still runs")
        let both = EventRuleMatcher.matching(rules, kinds: ["ring", "person"], canPlaySound: true) { _ in true }
        XCTAssertEqual(both.count, 5, "each rule once per event, even with several kinds")
    }

    func testDebouncePerCameraAndRule() {
        var debouncer = EventRuleDebouncer()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let a = UUID(), b = UUID()
        XCTAssertTrue(debouncer.shouldRun(entry: door, rule: a, at: start))
        XCTAssertFalse(debouncer.shouldRun(entry: door, rule: a, at: start.addingTimeInterval(10)))
        XCTAssertFalse(debouncer.shouldRun(entry: door, rule: a, at: start.addingTimeInterval(29.9)))
        XCTAssertTrue(debouncer.shouldRun(entry: door, rule: b, at: start.addingTimeInterval(10)), "other rule")
        XCTAssertTrue(debouncer.shouldRun(entry: "GARAGE", rule: a, at: start.addingTimeInterval(10)), "other camera")
        XCTAssertTrue(debouncer.shouldRun(entry: door, rule: a, at: start.addingTimeInterval(30)))
        // Clock set back: still "just now".
        XCTAssertFalse(debouncer.shouldRun(entry: door, rule: a, at: start.addingTimeInterval(20)))
    }

    func testBurstOfEventsRunsOncePerWindow() {
        var debouncer = EventRuleDebouncer()
        let start = Date(timeIntervalSince1970: 2_000_000)
        let id = UUID()
        let runs = (0..<10).filter { debouncer.shouldRun(entry: door, rule: id, at: start.addingTimeInterval(Double($0) * 5)) }
        XCTAssertEqual(runs, [0, 6], "every 5 s for 50 s → at 0 s and 30 s")
    }

    func testTexts() {
        XCTAssertEqual(EventRuleText.actionSummary(webhookAddress: "ha.local/hook", soundName: "Bin gleich da", delaySeconds: 10),
                       "ha.local/hook + „Bin gleich da“ · nach 10 s")
        XCTAssertEqual(EventRuleText.actionSummary(webhookAddress: nil, soundName: nil, delaySeconds: 0), "Keine Aktion")
        XCTAssertEqual(EventRuleText.logTitle(kindLabel: "Klingel", webhook: true, soundName: "Gong", failed: false),
                       "Klingel → Webhook + „Gong“")
        XCTAssertEqual(EventRuleText.logTitle(kindLabel: "Paket", webhook: true, soundName: nil, failed: true),
                       "Paket → Webhook (fehlgeschlagen)")
    }

    func testWebhookURLValidation() {
        XCTAssertNotNil(EventRuleWebhook(url: " https://ha.local/api ").requestURL)
        XCTAssertNil(EventRuleWebhook(url: "https://").requestURL)
        XCTAssertNil(EventRuleWebhook(url: "mailto:x@y").requestURL)
    }
}
```

Datei `Packages/AppCore/Tests/AppCoreTests/VoiceChoiceTests.swift` neu anlegen:

```swift
import XCTest
@testable import AppCore

final class VoiceChoiceTests: XCTestCase {
    private func voice(_ name: String, _ language: String = "de-DE", quality: Int = 1) -> VoiceChoice.Candidate {
        VoiceChoice.Candidate(identifier: "com.apple.\(name).\(quality).\(language)", name: name, language: language, quality: quality)
    }

    func testAnnaWinsInHerBestQuality() {
        let pick = VoiceChoice.pick(from: [voice("Petra", quality: 3), voice("Anna"), voice("Anna", quality: 2), voice("Samantha", "en-US", quality: 3)])
        XCTAssertEqual(pick, voice("Anna", quality: 2))
        XCTAssertEqual(VoiceChoice.fieldLabel(pick), "Anna · macOS")
        XCTAssertNil(VoiceChoice.hint(pick))
    }

    func testWithoutAnnaTheBestGermanVoice() {
        let pick = VoiceChoice.pick(from: [voice("Yannick"), voice("Petra", "de-AT", quality: 2), voice("Helena", quality: 2)])
        XCTAssertEqual(pick?.name, "Helena", "same quality: de-DE before de-AT")
        XCTAssertEqual(VoiceChoice.fieldLabel(pick), "Helena · macOS")
        XCTAssertEqual(VoiceChoice.hint(pick)?.contains("„Helena“"), true)
    }

    func testNoGermanVoice() {
        let pick = VoiceChoice.pick(from: [voice("Samantha", "en-US")])
        XCTAssertNil(pick)
        XCTAssertEqual(VoiceChoice.fieldLabel(pick), "Keine deutsche Stimme installiert")
        XCTAssertNotNil(VoiceChoice.hint(pick))
    }
}
```

Datei `Packages/AppCore/Tests/AppCoreTests/ActionAvailabilityTests.swift` neu anlegen:

```swift
import XCTest
@testable import AppCore

final class ActionAvailabilityTests: XCTestCase {
    func testConfigured() {
        XCTAssertFalse(ActionAvailability.isConfigured(title: " ", address: "https://a.b", hasValidURL: true, hasSound: false))
        XCTAssertTrue(ActionAvailability.isConfigured(title: "Tür", address: "https://a.b", hasValidURL: true, hasSound: false))
        XCTAssertFalse(ActionAvailability.isConfigured(title: "Tür", address: "", hasValidURL: false, hasSound: false))
        XCTAssertTrue(ActionAvailability.isConfigured(title: "Gong", address: "", hasValidURL: false, hasSound: true),
                      "address only required without sound")
        XCTAssertFalse(ActionAvailability.isConfigured(title: "Gong", address: "kaputt", hasValidURL: false, hasSound: true),
                       "a typed address must be valid")
    }

    func testShownOnlyWhereItCanDoSomething() {
        XCTAssertTrue(ActionAvailability.isShown(hasWebhook: true, hasSound: true, canPlaySound: false))
        XCTAssertFalse(ActionAvailability.isShown(hasWebhook: false, hasSound: true, canPlaySound: false))
        XCTAssertTrue(ActionAvailability.isShown(hasWebhook: false, hasSound: true, canPlaySound: true))
        XCTAssertFalse(ActionAvailability.playsSound(hasSound: true, canPlaySound: false))
    }
}
```

In `Packages/AppCore/Tests/AppCoreTests/SettingsExtensionsTests.swift` ersetzen:

```swift
    func testPrunedDropsStaleIds() {
```

durch:

```swift
    func testPhase5FieldsRoundTripAndStayLenient() throws {
        let rule = EventRule(kind: "ring", webhook: EventRuleWebhook(url: "https://ha.local/x"), bearerToken: "t0k3n", delaySeconds: 5)
        let ext = SettingsExtensions(
            mappings: ["A": .init(showNameAndTime: true, size: PopupSizeOverride(width: 640), eventRules: EventRuleList([rule]))],
            actions: ["X": .init(icon: "door", soundId: "6F0C6A52-4C4B-4E58-9B1E-2F3C1C0A0001")]
        )
        let data = try JSONEncoder().encode(ext)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("t0k3n"))
        let back = try XCTUnwrap(SettingsExtensions.decode(data))
        XCTAssertEqual(back.mappings["A"]?.showNameAndTime, true)
        XCTAssertEqual(back.mappings["A"]?.size, PopupSizeOverride(width: 640))
        XCTAssertEqual(back.mappings["A"]?.eventRules?.rules.map(\.id), [rule.id])
        XCTAssertEqual(back.actions["X"]?.soundId, "6F0C6A52-4C4B-4E58-9B1E-2F3C1C0A0001")

        // Written by the Phase-2–4 build: no new keys → nil (caller migrates); garbage → nil, rest kept.
        let old = try XCTUnwrap(SettingsExtensions.decode(Data(#"{"mappings":{"A":{"chimeOnOpen":true,"size":"big","eventRules":7}}}"#.utf8)))
        XCTAssertEqual(old.mappings["A"]?.chimeOnOpen, true)
        XCTAssertNil(old.mappings["A"]?.showNameAndTime)
        XCTAssertNil(old.mappings["A"]?.size)
        XCTAssertNil(old.mappings["A"]?.eventRules)
    }

    func testPrunedDropsStaleIds() {
```

An `Packages/AppCore/Tests/AppCoreTests/DisplayTextTests.swift` anhängen:

```swift

final class DisplayTextPhase5Tests: XCTestCase {
    func testVersionAndUpdateTexts() {
        XCTAssertEqual(DisplayText.version(short: "1.2.0", build: 29), "Version 1.2.0 (29)")
        XCTAssertEqual(DisplayText.updateButton(targetShort: "1.3.0", targetBuild: 31, currentShort: "1.2.0"), "Update auf 1.3.0 installieren")
        XCTAssertEqual(DisplayText.updateButton(targetShort: "1.2.0", targetBuild: 30, currentShort: "1.2.0"), "Update auf 1.2.0 (30) installieren")
        XCTAssertEqual(DisplayText.updateButton(targetShort: nil, targetBuild: 30, currentShort: "1.2.0"), "Update auf 1.2.0 (30) installieren")
        XCTAssertEqual(DisplayText.updateButton(targetShort: " ", targetBuild: 30, currentShort: "1.2.0"), "Update auf 1.2.0 (30) installieren")
    }

    func testActionTarget() {
        XCTAssertEqual(DisplayText.actionTarget(url: "https://ha.local/x", soundName: nil), "ha.local/x")
        XCTAssertEqual(DisplayText.actionTarget(url: "https://ha.local/x", soundName: "Gong"), "ha.local/x + Ton")
        XCTAssertEqual(DisplayText.actionTarget(url: " ", soundName: "Gong"), "Ton „Gong“")
        XCTAssertEqual(DisplayText.actionTarget(url: "", soundName: nil), "")
    }
}
```

In `Packages/AppCore/Tests/AppCoreTests/DesignTokensTests.swift` ersetzen:

```swift
        XCTAssertEqual(Tokens.overlay.light, Tokens.overlay.dark)
```

durch:

```swift
        XCTAssertEqual(Tokens.overlay.light, Tokens.overlay.dark)
        XCTAssertEqual(Tokens.danger, ThemeColor(0xD70015, 0xFF6961))
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `(cd Packages/AppCore && swift test 2>&1 | grep -E "error:" | head -5)`
Expected: FAIL – u. a. `error: cannot find 'EventRule' in scope`

- [ ] **Step 3: New AppCore types**

Datei `Packages/AppCore/Sources/AppCore/Sound/VoiceChoice.swift` neu anlegen:

```swift
import Foundation

/// Phase 5: every announcement speaks with Anna; without Anna the best German voice.
public enum VoiceChoice {
    public static let preferredName = "Anna"

    /// What the choice needs from `AVSpeechSynthesisVoice` (testable without installed voices).
    public struct Candidate: Equatable, Sendable {
        public let identifier: String
        public let name: String
        public let language: String
        /// Higher is better (default 1, enhanced 2, premium 3).
        public let quality: Int

        public init(identifier: String, name: String, language: String, quality: Int) {
            self.identifier = identifier
            self.name = name
            self.language = language
            self.quality = quality
        }
    }

    /// Anna in her best installed quality; else the best German voice (quality, de-DE first, name).
    public static func pick(from candidates: [Candidate]) -> Candidate? {
        let german = candidates.filter { $0.language.lowercased().hasPrefix("de") }
        let ranked = german.sorted { lhs, rhs in
            if lhs.quality != rhs.quality { return lhs.quality > rhs.quality }
            let lhsDE = lhs.language.lowercased() == "de-de"
            let rhsDE = rhs.language.lowercased() == "de-de"
            if lhsDE != rhsDE { return lhsDE }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return ranked.first { $0.name == preferredName } ?? ranked.first
    }

    /// Text of the (disabled) voice field: „Anna · macOS“.
    public static func fieldLabel(_ voice: Candidate?) -> String {
        guard let voice else { return "Keine deutsche Stimme installiert" }
        return "\(voice.name) · macOS"
    }

    /// Hint under the field when Anna is missing; nil when Anna speaks.
    public static func hint(_ voice: Candidate?) -> String? {
        guard let voice else {
            return "Lade eine deutsche Stimme unter Systemeinstellungen › Bedienungshilfen › Gesprochene Inhalte."
        }
        guard voice.name != preferredName else { return nil }
        return "Anna ist auf diesem Mac nicht installiert – es spricht „\(voice.name)“. Anna lädst du unter Systemeinstellungen › Bedienungshilfen › Gesprochene Inhalte."
    }
}
```

Datei `Packages/AppCore/Sources/AppCore/EventRules.swift` neu anlegen:

```swift
import Foundation

/// Webhook part of an event rule: same request as a popup button.
public struct EventRuleWebhook: Codable, Equatable, Sendable {
    public var method: String
    public var url: String

    public init(method: String = "POST", url: String = "") {
        self.method = method == "GET" ? "GET" : "POST"
        self.url = url
    }

    /// A valid http(s) URL with a host, else nil.
    public var requestURL: URL? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              parsed.host?.isEmpty == false else { return nil }
        return parsed
    }

    private enum CodingKeys: String, CodingKey { case method, url }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            method: (try? c.decodeIfPresent(String.self, forKey: .method)) ?? "POST",
            url: (try? c.decodeIfPresent(String.self, forKey: .url)) ?? ""
        )
    }
}

/// Kameras › Ereignisse: when the camera reports `kind`, call a webhook and/or play an announcement
/// at the camera, after `delaySeconds`. Runs regardless of popups and mutes.
public struct EventRule: Codable, Equatable, Identifiable, Sendable {
    public static let maxDelay = 600
    /// The same rule fires at most once per camera within this window.
    public static let debounce: TimeInterval = 30
    public static let maxPerCamera = 10

    public var id: UUID
    /// `TriggerKind` raw value ("ring", "motion", "person", …).
    public var kind: String
    public var webhook: EventRuleWebhook?
    /// Bearer token: lives in the keychain only and is never encoded (settings, extension, export).
    public var bearerToken: String
    /// Announcement id (Einstellungen › Ton); nil = no sound.
    public var soundId: UUID?
    /// 0…600 seconds.
    public var delaySeconds: Int

    public init(
        id: UUID = UUID(),
        kind: String = "ring",
        webhook: EventRuleWebhook? = nil,
        bearerToken: String = "",
        soundId: UUID? = nil,
        delaySeconds: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.webhook = webhook
        self.bearerToken = bearerToken
        self.soundId = soundId
        self.delaySeconds = Self.clampedDelay(delaySeconds)
    }

    /// A webhook that can be called (valid address).
    public var hasWebhook: Bool { webhook?.requestURL != nil }

    /// Saveable: a valid webhook, or a sound with an empty address field.
    public var isConfigured: Bool {
        let addressEmpty = webhook?.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        return addressEmpty ? soundId != nil : hasWebhook
    }

    public static func clampedDelay(_ seconds: Int) -> Int {
        min(maxDelay, max(0, seconds))
    }

    /// "Verzögerung" field → seconds: digits only, empty = 0, at most 600.
    public static func delay(fromText text: String) -> Int {
        let digits = text.filter { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty else { return 0 }
        return clampedDelay(Int(digits.prefix(4)) ?? maxDelay)
    }

    private enum CodingKeys: String, CodingKey { case id, kind, webhook, soundId, delaySeconds }

    /// Lenient: only `kind` is required; a broken field falls back to its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        self.init(
            id: (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID(),
            kind: kind,
            webhook: (try? c.decodeIfPresent(EventRuleWebhook.self, forKey: .webhook)) ?? nil,
            soundId: (try? c.decodeIfPresent(UUID.self, forKey: .soundId)) ?? nil,
            delaySeconds: (try? c.decodeIfPresent(Int.self, forKey: .delaySeconds)) ?? 0
        )
    }

    /// The token is deliberately left out.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(webhook, forKey: .webhook)
        try c.encodeIfPresent(soundId, forKey: .soundId)
        try c.encode(delaySeconds, forKey: .delaySeconds)
    }
}

/// A list of rules that survives broken entries (each element decoded on its own).
public struct EventRuleList: Codable, Equatable, Sendable {
    public var rules: [EventRule]

    public init(_ rules: [EventRule] = []) {
        self.rules = rules
    }

    private struct Skip: Decodable {
        init(from decoder: Decoder) throws {}
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var rules: [EventRule] = []
        while !container.isAtEnd {
            if let rule = try? container.decode(EventRule.self) {
                rules.append(rule)
            } else {
                _ = try? container.decode(Skip.self)
            }
        }
        self.rules = rules
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(contentsOf: rules)
    }
}

public enum EventRuleMatcher {
    /// Rules an event with `kinds` triggers, in list order, each once. Rules that could do nothing
    /// here (sound only, but no speaker or the announcement is gone) are left out.
    public static func matching(
        _ rules: [EventRule],
        kinds: Set<String>,
        canPlaySound: Bool,
        soundExists: (UUID) -> Bool
    ) -> [EventRule] {
        rules.filter { rule in
            guard kinds.contains(rule.kind) else { return false }
            let plays = canPlaySound && rule.soundId.map(soundExists) == true
            return rule.hasWebhook || plays
        }
    }
}

/// Per camera entry and rule: at most one run within `EventRule.debounce`.
public struct EventRuleDebouncer: Sendable {
    private var lastRun: [String: Date] = [:]

    public init() {}

    public mutating func shouldRun(entry: String, rule: UUID, at date: Date, window: TimeInterval = EventRule.debounce) -> Bool {
        let key = "\(entry)|\(rule.uuidString)"
        // abs: a clock set back counts as "just now", never as "long ago".
        if let last = lastRun[key], abs(date.timeIntervalSince(last)) < window { return false }
        lastRun = lastRun.filter { abs(date.timeIntervalSince($0.value)) < window }
        lastRun[key] = date
        return true
    }
}

public enum EventRuleText {
    /// Row in Kameras › Ereignisse: "Webhook + „Bin gleich da“ · nach 10 s".
    public static func actionSummary(webhookAddress: String?, soundName: String?, delaySeconds: Int) -> String {
        var parts: [String] = []
        if let webhookAddress, !webhookAddress.isEmpty { parts.append(webhookAddress) }
        if let soundName { parts.append("„\(soundName)“") }
        var text = parts.isEmpty ? "Keine Aktion" : parts.joined(separator: " + ")
        if delaySeconds > 0 { text += " · nach \(delaySeconds) s" }
        return text
    }

    /// Event log / menu panel: "Klingel → Webhook + „Bin gleich da“", "… (fehlgeschlagen)".
    public static func logTitle(kindLabel: String, webhook: Bool, soundName: String?, failed: Bool) -> String {
        var actions: [String] = []
        if webhook { actions.append("Webhook") }
        if let soundName { actions.append("„\(soundName)“") }
        let text = "\(kindLabel) → \(actions.isEmpty ? "nichts" : actions.joined(separator: " + "))"
        return failed ? "\(text) (fehlgeschlagen)" : text
    }
}
```

Datei `Packages/AppCore/Sources/AppCore/ActionAvailability.swift` neu anlegen:

```swift
import Foundation

/// Popup buttons (Phase 5): a button calls a webhook, plays an announcement at the camera, or both.
public enum ActionAvailability {
    /// Saveable: a title and something to do. A typed address must be valid; it may stay
    /// empty when a sound is chosen.
    public static func isConfigured(title: String, address: String, hasValidURL: Bool, hasSound: Bool) -> Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let addressEmpty = address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return addressEmpty ? hasSound : hasValidURL
    }

    /// Shown in this popup: the webhook part always, a sound only on a camera with speaker.
    public static func isShown(hasWebhook: Bool, hasSound: Bool, canPlaySound: Bool) -> Bool {
        hasWebhook || (hasSound && canPlaySound)
    }

    public static func playsSound(hasSound: Bool, canPlaySound: Bool) -> Bool {
        hasSound && canPlaySound
    }
}
```

- [ ] **Step 4: Preferred voice in AnnouncementAudio**

In `Packages/AppCore/Sources/AppCore/Sound/AnnouncementAudio.swift` ersetzen:

```swift
    /// "Anna (Premium) · macOS" – template wording of the voice pop-up.
```

durch:

```swift
    /// The voice every new rendering uses (Anna, else the best German voice).
    public static func preferredVoice() -> AVSpeechSynthesisVoice? {
        let all = voices()
        guard let pick = VoiceChoice.pick(from: all.map(candidate)) else { return nil }
        return all.first { $0.identifier == pick.identifier }
    }

    public static func candidate(_ voice: AVSpeechSynthesisVoice) -> VoiceChoice.Candidate {
        let quality: Int
        switch voice.quality {
        case .premium: quality = 3
        case .enhanced: quality = 2
        default: quality = 1
        }
        return VoiceChoice.Candidate(identifier: voice.identifier, name: voice.name, language: voice.language, quality: quality)
    }

    /// "Anna (Premium) · macOS" – template wording of the voice pop-up.
```

In `Packages/AppCore/Sources/AppCore/Sound/AnnouncementAudio.swift` ersetzen:

```swift
    /// Speaks `text` into a buffer (`AVSpeechSynthesizer.write`). Unknown voice = system default German voice.
```

durch:

```swift
    /// Speaks `text` into a buffer (`AVSpeechSynthesizer.write`). Unknown voice = `preferredVoice()`.
```

In `Packages/AppCore/Sources/AppCore/Sound/AnnouncementAudio.swift` ersetzen:

```swift
            utterance.voice = voices().first ?? AVSpeechSynthesisVoice(language: "de-DE")
```

durch:

```swift
            utterance.voice = preferredVoice() ?? AVSpeechSynthesisVoice(language: "de-DE")
```

- [ ] **Step 5: New extension fields**

In `Packages/AppCore/Sources/AppCore/SettingsExtensions.swift` ersetzen:

```swift
        public var chimeOnOpen: Bool?

        public init(
            protectCameraId: String? = nil,
            triggers: [String]? = nil,
            webhookTriggerEnabled: Bool? = nil,
            chimeOnOpen: Bool? = nil
        ) {
            self.protectCameraId = protectCameraId
            self.triggers = triggers
            self.webhookTriggerEnabled = webhookTriggerEnabled
            self.chimeOnOpen = chimeOnOpen
        }

        private enum CodingKeys: String, CodingKey {
            case protectCameraId, triggers, webhookTriggerEnabled, chimeOnOpen
        }
```

durch:

```swift
        public var chimeOnOpen: Bool?
        /// Phase 5: „Name und Zeit einblenden“ (nil = not written yet → off).
        public var showNameAndTime: Bool?
        /// Phase 5: „Größe“; nil = not written yet (migrated from the main blob's width/height).
        public var size: PopupSizeOverride?
        /// Phase 5: Kameras › Ereignisse (without tokens).
        public var eventRules: EventRuleList?

        public init(
            protectCameraId: String? = nil,
            triggers: [String]? = nil,
            webhookTriggerEnabled: Bool? = nil,
            chimeOnOpen: Bool? = nil,
            showNameAndTime: Bool? = nil,
            size: PopupSizeOverride? = nil,
            eventRules: EventRuleList? = nil
        ) {
            self.protectCameraId = protectCameraId
            self.triggers = triggers
            self.webhookTriggerEnabled = webhookTriggerEnabled
            self.chimeOnOpen = chimeOnOpen
            self.showNameAndTime = showNameAndTime
            self.size = size
            self.eventRules = eventRules
        }

        private enum CodingKeys: String, CodingKey {
            case protectCameraId, triggers, webhookTriggerEnabled, chimeOnOpen
            case showNameAndTime, size, eventRules
        }
```

In `Packages/AppCore/Sources/AppCore/SettingsExtensions.swift` ersetzen:

```swift
            chimeOnOpen = (try? c.decodeIfPresent(Bool.self, forKey: .chimeOnOpen)) ?? nil
        }
```

durch:

```swift
            chimeOnOpen = (try? c.decodeIfPresent(Bool.self, forKey: .chimeOnOpen)) ?? nil
            showNameAndTime = (try? c.decodeIfPresent(Bool.self, forKey: .showNameAndTime)) ?? nil
            size = (try? c.decodeIfPresent(PopupSizeOverride.self, forKey: .size)) ?? nil
            eventRules = (try? c.decodeIfPresent(EventRuleList.self, forKey: .eventRules)) ?? nil
        }
```

In `Packages/AppCore/Sources/AppCore/SettingsExtensions.swift` ersetzen:

```swift
        public var confirmBeforeRun: Bool?

        public init(icon: String? = nil, confirmBeforeRun: Bool? = nil) {
            self.icon = icon
            self.confirmBeforeRun = confirmBeforeRun
        }

        private enum CodingKeys: String, CodingKey { case icon, confirmBeforeRun }
```

durch:

```swift
        public var confirmBeforeRun: Bool?
        /// Phase 5: announcement id (UUID string) the button plays; nil = no sound.
        public var soundId: String?

        public init(icon: String? = nil, confirmBeforeRun: Bool? = nil, soundId: String? = nil) {
            self.icon = icon
            self.confirmBeforeRun = confirmBeforeRun
            self.soundId = soundId
        }

        private enum CodingKeys: String, CodingKey { case icon, confirmBeforeRun, soundId }
```

In `Packages/AppCore/Sources/AppCore/SettingsExtensions.swift` ersetzen:

```swift
            confirmBeforeRun = (try? c.decodeIfPresent(Bool.self, forKey: .confirmBeforeRun)) ?? nil
        }
```

durch:

```swift
            confirmBeforeRun = (try? c.decodeIfPresent(Bool.self, forKey: .confirmBeforeRun)) ?? nil
            soundId = (try? c.decodeIfPresent(String.self, forKey: .soundId)) ?? nil
        }
```

- [ ] **Step 6: Texts and the red token**

An `Packages/AppCore/Sources/AppCore/DisplayText.swift` anhängen:

```swift

// MARK: - Phase 5

extension DisplayText {
    /// Menu panel: "Version 1.2.0 (29)".
    public static func version(short: String, build: Int) -> String {
        "Version \(short) (\(build))"
    }

    /// Menu panel update button: "Update auf 1.3.0 installieren"; same marketing version
    /// (newer build only) or none: "Update auf 1.2.0 (30) installieren".
    public static func updateButton(targetShort: String?, targetBuild: Int, currentShort: String) -> String {
        let short = (targetShort ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if short.isEmpty || short == currentShort {
            return "Update auf \(currentShort) (\(targetBuild)) installieren"
        }
        return "Update auf \(short) installieren"
    }

    /// Button row in Kameras: address without scheme, "Ton „Gong“" or "ha.local/x + Ton".
    public static func actionTarget(url: String, soundName: String?) -> String {
        let address = actionAddress(url)
        switch (address.isEmpty, soundName) {
        case (false, nil): return address
        case (false, .some): return "\(address) + Ton"
        case (true, let name?): return "Ton „\(name)“"
        case (true, nil): return ""
        }
    }
}
```

In `Packages/AppCore/Sources/AppCore/DesignTokens.swift` ersetzen:

```swift
    public static let popupRing = ThemeColor.fixed(RGBA(0xFFFFFF, alpha: 0.1))
```

durch:

```swift
    public static let popupRing = ThemeColor.fixed(RGBA(0xFFFFFF, alpha: 0.1))

    // Phase 5 (not in the template): red link „Kamera entfernen“ – macOS systemRed, accessible variant.
    public static let danger = ThemeColor(0xD70015, 0xFF6961)
```

- [ ] **Step 7: Run tests to verify they pass**

Run: alle AppCore-Tests (Befehl oben)
Expected: `Executed 117 tests, with 0 failures` (68 vorher + 19 aus Task 1 + 13 aus Task 2 + 17 neu)

Build-Befehl → `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add Packages/AppCore/Sources/AppCore/Sound/VoiceChoice.swift Packages/AppCore/Sources/AppCore/EventRules.swift \
  Packages/AppCore/Sources/AppCore/ActionAvailability.swift Packages/AppCore/Sources/AppCore/Sound/AnnouncementAudio.swift \
  Packages/AppCore/Sources/AppCore/SettingsExtensions.swift Packages/AppCore/Sources/AppCore/DisplayText.swift \
  Packages/AppCore/Sources/AppCore/DesignTokens.swift \
  Packages/AppCore/Tests/AppCoreTests/EventRulesTests.swift Packages/AppCore/Tests/AppCoreTests/VoiceChoiceTests.swift \
  Packages/AppCore/Tests/AppCoreTests/ActionAvailabilityTests.swift Packages/AppCore/Tests/AppCoreTests/SettingsExtensionsTests.swift \
  Packages/AppCore/Tests/AppCoreTests/DisplayTextTests.swift Packages/AppCore/Tests/AppCoreTests/DesignTokensTests.swift
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "feat(core): event rules, voice choice, button sound availability, phase-5 extension fields" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Popup ohne Name/Zeit, neue Glocke, Kamera-Karten umsortiert (Spezifikation 1, 5, 6, 8)

**Files:**
- Modify: `UniFiCameraPopup/Models/WebhookMapping.swift` (`WebhookMapping`: Feld, Schlüssel, init, Coding)
- Modify: `UniFiCameraPopup/Services/SettingsStore.swift` (`overlay`, `currentExtensions`)
- Modify: `UniFiCameraPopup/Views/Popup/PopupOverlayViews.swift` (`PopupOverlayContent`)
- Modify: `UniFiCameraPopup/Views/PopupWindow.swift` (`setupOverlay`)
- Modify: `UniFiCameraPopup/Services/PopupController.swift` (`makeAlarmWindow`)
- Modify: `UniFiCameraPopup/Views/Settings/CameraAdvancedSection.swift`, `UniFiCameraPopup/Views/Settings/CamerasTab.swift`
- Modify: `UniFiCameraPopup/Assets.xcassets/Icons/bellSlash.imageset/bellSlash.svg`
- Modify: `UniFiCameraPopup/Debug/SnapshotRenderer.swift` (Bild `8-popup-ohne-chip`)

**Interfaces:**
- Consumes: `Tokens.danger` (Task 3), `SettingsExtensions.Mapping.showNameAndTime` (Task 3).
- Produces: `WebhookMapping.showNameAndTime: Bool` (Standard `false`, auch für bestehende Kameras); `PopupOverlayContent.chipText: String?` (nil = kein Chip); `CameraAdvancedSection(mapping:lastTriggered:)` (ohne `onRemove`).

Es gibt kein Test-Target für App-Code; die Logik dieses Tasks ist Verdrahtung. Prüfung: Build + Bildvergleich.

- [ ] **Step 1: Model and persistence**

In `UniFiCameraPopup/Models/WebhookMapping.swift` ersetzen:

```swift
    /// "Hinweiston beim Öffnen": system sound when a triggered popup opens.
    var chimeOnOpen: Bool
```

durch:

```swift
    /// "Hinweiston beim Öffnen": system sound when a triggered popup opens.
    var chimeOnOpen: Bool
    /// „Name und Zeit einblenden“: the app's own chip (camera OSD shows the same). Default off.
    var showNameAndTime: Bool
```

In `UniFiCameraPopup/Models/WebhookMapping.swift` ersetzen:

```swift
        case chimeOnOpen
        case widthOverride
```

durch:

```swift
        case chimeOnOpen
        case showNameAndTime
        case widthOverride
```

In `UniFiCameraPopup/Models/WebhookMapping.swift` ersetzen:

```swift
        webhookTriggerEnabled: Bool = false,
        chimeOnOpen: Bool = false
    ) {
```

durch:

```swift
        webhookTriggerEnabled: Bool = false,
        chimeOnOpen: Bool = false,
        showNameAndTime: Bool = false
    ) {
```

In `UniFiCameraPopup/Models/WebhookMapping.swift` ersetzen:

```swift
        self.chimeOnOpen = chimeOnOpen
    }
```

durch:

```swift
        self.chimeOnOpen = chimeOnOpen
        self.showNameAndTime = showNameAndTime
    }
```

In `UniFiCameraPopup/Models/WebhookMapping.swift` ersetzen:

```swift
        chimeOnOpen = (try? container.decodeIfPresent(Bool.self, forKey: .chimeOnOpen)) ?? false
    }
```

durch:

```swift
        chimeOnOpen = (try? container.decodeIfPresent(Bool.self, forKey: .chimeOnOpen)) ?? false
        // Phase 5: existing cameras start without the chip, too.
        showNameAndTime = (try? container.decodeIfPresent(Bool.self, forKey: .showNameAndTime)) ?? false
    }
```

In `UniFiCameraPopup/Models/WebhookMapping.swift` ersetzen:

```swift
        try container.encode(chimeOnOpen, forKey: .chimeOnOpen)
    }
```

durch:

```swift
        try container.encode(chimeOnOpen, forKey: .chimeOnOpen)
        try container.encode(showNameAndTime, forKey: .showNameAndTime)
    }
```

In `UniFiCameraPopup/Services/SettingsStore.swift` ersetzen:

```swift
                if let chime = m.chimeOnOpen { mapping.chimeOnOpen = chime }
```

durch:

```swift
                if let chime = m.chimeOnOpen { mapping.chimeOnOpen = chime }
                if let show = m.showNameAndTime { mapping.showNameAndTime = show }
```

In `UniFiCameraPopup/Services/SettingsStore.swift` ersetzen:

```swift
                webhookTriggerEnabled: mapping.webhookTriggerEnabled,
                chimeOnOpen: mapping.chimeOnOpen
            )
```

durch:

```swift
                webhookTriggerEnabled: mapping.webhookTriggerEnabled,
                chimeOnOpen: mapping.chimeOnOpen,
                showNameAndTime: mapping.showNameAndTime
            )
```

- [ ] **Step 2: Popup without chip, new mute tooltip**

In `UniFiCameraPopup/Views/Popup/PopupOverlayViews.swift` ersetzen:

```swift
struct PopupOverlayContent {
    let chipText: String
```

durch:

```swift
struct PopupOverlayContent {
    /// „Klingel · Haustür · 10:41“; nil = „Name und Zeit einblenden“ is off (no chip).
    let chipText: String?
```

In `UniFiCameraPopup/Views/PopupWindow.swift` ersetzen:

```swift
        let chip = OverlayChipView(text: overlay.chipText)
        let close
```

durch:

```swift
        let close
```

In `UniFiCameraPopup/Views/PopupWindow.swift` ersetzen:

```swift
        let mute = CircleIconButton(icon: .bellSlash, iconSize: 13, diameter: 24,
                                    fill: Tokens.overlay, tint: Tokens.white, label: "\(overlay.cameraName) stummschalten")
```

durch:

```swift
        let mute = CircleIconButton(icon: .bellSlash, iconSize: 13, diameter: 24,
                                    fill: Tokens.overlay, tint: Tokens.white, label: "Diese Kamera stummschalten")
```

In `UniFiCameraPopup/Views/PopupWindow.swift` ersetzen:

```swift
        content.addSubview(chip)
        content.addSubview(close)
        content.addSubview(mute)
        var constraints = [
            chip.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            chip.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            chip.trailingAnchor.constraint(lessThanOrEqualTo: mute.leadingAnchor, constant: -8),
            close.trailingAnchor
```

durch:

```swift
        content.addSubview(close)
        content.addSubview(mute)
        var constraints = [
            close.trailingAnchor
```

In `UniFiCameraPopup/Views/PopupWindow.swift` ersetzen:

```swift
            mute.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
        ]
```

durch:

```swift
            mute.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
        ]
        if let chipText = overlay.chipText {
            let chip = OverlayChipView(text: chipText)
            content.addSubview(chip)
            constraints += [
                chip.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
                chip.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
                chip.trailingAnchor.constraint(lessThanOrEqualTo: mute.leadingAnchor, constant: -8),
            ]
        }
```

In `UniFiCameraPopup/Services/PopupController.swift` ersetzen:

```swift
        let overlay = PopupOverlayContent(
            chipText: DisplayText.popupChip(
                kind: Self.kindLabel(for: event, mapping: mapping),
                camera: cameraName,
                date: event.timestamp
            ),
```

durch:

```swift
        let overlay = PopupOverlayContent(
            chipText: mapping.showNameAndTime
                ? DisplayText.popupChip(kind: Self.kindLabel(for: event, mapping: mapping), camera: cameraName, date: event.timestamp)
                : nil,
```

- [ ] **Step 3: Lucide bell-off**

Die Datei `UniFiCameraPopup/Assets.xcassets/Icons/bellSlash.imageset/bellSlash.svg` vollständig ersetzen (eine Zeile; `Contents.json` bleibt, Template-Rendering bleibt):

```bash
cat > UniFiCameraPopup/Assets.xcassets/Icons/bellSlash.imageset/bellSlash.svg <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#000000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10.268 21a2 2 0 0 0 3.464 0"/><path d="M17 17H4a1 1 0 0 1-.74-1.673C4.59 13.956 6 12.499 6 8a6 6 0 0 1 .258-1.742"/><path d="M2 2l20 20"/><path d="M8.668 3.01A6 6 0 0 1 18 8c0 2.687.77 4.653 1.707 6.05"/></svg>
EOF
grep -rn "TemplateIcon.bellSlash\|icon: .bellSlash" UniFiCameraPopup --include='*.swift' | grep -v "/.build/"
```
Expected: genau ein Treffer (`PopupWindow.swift`, Stummschalten im Popup) – das ist die einzige Verwendung, die neue Datei gilt damit überall.

- [ ] **Step 4: Settings: switch, card order, red remove link**

In `UniFiCameraPopup/Views/Settings/CameraAdvancedSection.swift` ersetzen:

```swift
    let lastTriggered: Date?
    let onRemove: () -> Void
```

durch:

```swift
    let lastTriggered: Date?
```

In `UniFiCameraPopup/Views/Settings/CameraAdvancedSection.swift` ersetzen:

```swift
            }
            Button("Kamera entfernen …", action: onRemove)
                .buttonStyle(LinkButtonStyle(color: Tokens.muted))
        }
```

durch:

```swift
            }
        }
```

In `UniFiCameraPopup/Views/Settings/CameraAdvancedSection.swift` ersetzen:

```swift
                CardToggleRow(title: "Ton des Livebilds", isOn: $mapping.soundEnabled, vertical: 9, horizontal: 12)
```

durch:

```swift
                CardToggleRow(title: "Name und Zeit einblenden", isOn: $mapping.showNameAndTime, vertical: 9, horizontal: 12)
```

In `UniFiCameraPopup/Views/Settings/CamerasTab.swift` ersetzen:

```swift
                        Spacer(minLength: 0)
                        DisclosureButton(title: "Erweitert", expanded: $advancedExpanded)
                            .id("advanced")
                        if advancedExpanded {
                            CameraAdvancedSection(
                                mapping: $mapping,
                                lastTriggered: events.lastTriggered(entryId: mapping.entryId),
                                onRemove: { confirmRemoval = true }
                            )
                        }
```

durch:

```swift
                        Spacer(minLength: 0)
                        // „Kamera entfernen“ stays visible with „Erweitert“ collapsed (Phase 5).
                        HStack {
                            DisclosureButton(title: "Erweitert", expanded: $advancedExpanded)
                            Spacer()
                            Button("Kamera entfernen") { confirmRemoval = true }
                                .buttonStyle(LinkButtonStyle(color: Tokens.danger))
                        }
                        .id("advanced")
                        if advancedExpanded {
                            CameraAdvancedSection(
                                mapping: $mapping,
                                lastTriggered: events.lastTriggered(entryId: mapping.entryId)
                            )
                        }
```

In `UniFiCameraPopup/Views/Settings/CamerasTab.swift` ersetzen:

```swift
            CardToggleRow(title: "Zoom und Ausschnitt merken", isOn: $mapping.rememberZoom, vertical: 8, horizontal: 12)
        }
```

durch:

```swift
            CardToggleRow(title: "Zoom und Ausschnitt merken", isOn: $mapping.rememberZoom, vertical: 8, horizontal: 12)
            CardDivider()
            CardToggleRow(title: "Ton des Livebilds", isOn: $mapping.soundEnabled, vertical: 8, horizontal: 12)
        }
```

Die Rückfrage `.alert("Kamera entfernen?" …)` in `CameraDetail` bleibt unverändert.

- [ ] **Step 5: Snapshot of the default popup (no chip)**

In `UniFiCameraPopup/Debug/SnapshotRenderer.swift` ersetzen:

```swift
            // 8 – popup chrome, mute menu closed and open.
            for menuOpen in [false, true] {
```

durch:

```swift
            // 8 – popup chrome, mute menu closed and open; Phase 5 default: no chip.
            let plain = PopupWindow(
                frame: NSRect(x: 0, y: 0, width: 470, height: 300),
                streamURL: "", soundEnabled: false,
                thumbnailDataURI: placeholderDataURI(size: CGSize(width: 470, height: 300)),
                autoCloseSeconds: 0,
                actions: sample.door.actions,
                overlay: PopupOverlayContent(
                    chipText: nil, cameraName: "Haustür",
                    muteOptions: sample.settings.muteOptions, onMute: { _ in }
                ),
                onClose: {}
            )
            write(window: plain, appearance: appearance, includeFrame: false,
                  to: directory.appendingPathComponent("8-popup-ohne-chip-\(suffix).png"))
            for menuOpen in [false, true] {
```

- [ ] **Step 6: Build and look**

Run: Build-Befehl → `** BUILD SUCCEEDED **`; dann den Renderer (Befehl oben).
Expected (Bilder ansehen, hell + dunkel):
- `8-popup-ohne-chip-*`: kein Chip oben links; Glocke vollständig mit Bogen unten, Strich von links oben nach rechts unten, Klöppel unten – keine offene Glocke mehr.
- `8-popup-*` (mit Chip-Text): Chip wie bisher.
- `S2-kameras-*`: Karte „Tastenkürzel · Hinweiston beim Öffnen · Zoom und Ausschnitt merken · Ton des Livebilds“; unten „Erweitert“ links, „Kamera entfernen“ rot rechts in derselben Zeile (ohne „…“).
- `S3-kameras-erweitert-*`: in „Popup“ steht „Name und Zeit einblenden“ (aus), kein „Ton des Livebilds“, kein grauer Entfernen-Link mehr.

- [ ] **Step 7: Commit**

```bash
git add UniFiCameraPopup/Models/WebhookMapping.swift UniFiCameraPopup/Services/SettingsStore.swift \
  UniFiCameraPopup/Views/Popup/PopupOverlayViews.swift UniFiCameraPopup/Views/PopupWindow.swift \
  UniFiCameraPopup/Services/PopupController.swift UniFiCameraPopup/Views/Settings/CameraAdvancedSection.swift \
  UniFiCameraPopup/Views/Settings/CamerasTab.swift UniFiCameraPopup/Assets.xcassets/Icons/bellSlash.imageset/bellSlash.svg \
  UniFiCameraPopup/Debug/SnapshotRenderer.swift
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "feat(popup): name/time chip off by default, Lucide bell-off, remove link always visible" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Menüleisten-Panel – Version und Update (Spezifikation 2)

**Files:**
- Modify: `UniFiCameraPopup/Views/StatusPanel/StatusPanel.swift` (`StatusPanelActions`, `StatusPanelView`)
- Modify: `UniFiCameraPopup/AppDelegate.swift` (Panel-Aufbau, `statusItemClicked`)
- Modify: `UniFiCameraPopup/Services/UpdateService.swift` (`debugApply`, nur DEBUG)
- Modify: `UniFiCameraPopup/Debug/SnapshotRenderer.swift` (Panel-Aufrufe, Bild `7-panel-update`)

**Interfaces:**
- Consumes: `DisplayText.version(short:build:)`, `DisplayText.updateButton(targetShort:targetBuild:currentShort:)` (Task 3); bestehend `UpdateService.state`, `.availableManifest`, `.isInstalling`, `AppDelegate.installUpdate()` (Rückfrage + Installation).
- Produces: `StatusPanelActions.installUpdate: () -> Void` (zwischen `openCamera` und `close`); `StatusPanelView(…, clock:, updates: UpdateService, actions:)`; `UpdateService.debugApply(state:manifest:)` (DEBUG).

- [ ] **Step 1: Panel section**

In `UniFiCameraPopup/Views/StatusPanel/StatusPanel.swift` ersetzen:

```swift
    let openCamera: (UUID) -> Void
    let close: () -> Void
```

durch:

```swift
    let openCamera: (UUID) -> Void
    /// „Update auf … installieren“: the former menu's update action (confirmation, download, restart).
    let installUpdate: () -> Void
    let close: () -> Void
```

In `UniFiCameraPopup/Views/StatusPanel/StatusPanel.swift` ersetzen:

```swift
    @ObservedObject var clock: StatusPanelClock
    @ObservedObject private var router = ConnectionRouter.shared
```

durch:

```swift
    @ObservedObject var clock: StatusPanelClock
    @ObservedObject var updates: UpdateService
    @ObservedObject private var router = ConnectionRouter.shared
```

In `UniFiCameraPopup/Views/StatusPanel/StatusPanel.swift` ersetzen:

```swift
            CardDivider(color: Tokens.mainBorder)
            footerRow("Einstellungen …"
```

durch:

```swift
            CardDivider(color: Tokens.mainBorder)
            versionSection
            footerRow("Einstellungen …"
```

In `UniFiCameraPopup/Views/StatusPanel/StatusPanel.swift` ersetzen:

```swift
    // MARK: Fuß
```

durch:

```swift
    // MARK: Version und Update (Phase 5, not in the template)

    /// „Version 1.2.0 (29)“ 11 `muted`; with an update a full-width button like the mute buttons.
    private var versionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(DisplayText.version(short: AppConfig.shortVersion, build: AppConfig.buildNumber))
                .font(.system(size: 11))
                .foregroundStyle(Tokens.muted.color)
            if let title = updateButtonTitle {
                Button(title, action: actions.installUpdate)
                    .buttonStyle(SoftButtonStyle())
                    .disabled(updates.isInstalling)
            }
        }
    }

    private var updateButtonTitle: String? {
        switch updates.state {
        case .downloading: return "Lade neue Version …"
        case .installing: return "Installiere …"
        default:
            guard let manifest = updates.availableManifest else { return nil }
            return DisplayText.updateButton(
                targetShort: manifest.shortVersion,
                targetBuild: manifest.buildNumber,
                currentShort: AppConfig.shortVersion
            )
        }
    }

    // MARK: Fuß
```

- [ ] **Step 2: Wire the panel**

In `UniFiCameraPopup/AppDelegate.swift` ersetzen:

```swift
            clock: clock,
            actions: StatusPanelActions(
```

durch:

```swift
            clock: clock,
            updates: updateService,
            actions: StatusPanelActions(
```

In `UniFiCameraPopup/AppDelegate.swift` ersetzen:

```swift
                openCamera: { [weak self] id in
                    self?.statusPanel.close()
                    self?.openCamera(entryId: id)
                },
```

durch:

```swift
                openCamera: { [weak self] id in
                    self?.statusPanel.close()
                    self?.openCamera(entryId: id)
                },
                installUpdate: { [weak self] in
                    self?.statusPanel.close()
                    self?.installUpdate()
                },
```

In `UniFiCameraPopup/AppDelegate.swift` ersetzen:

```swift
        } else {
            statusPanel.toggle(from: sender)
        }
```

durch:

```swift
        } else {
            // Like the former menu: every opening looks for a newer build in the background.
            if !statusPanel.isShown { Task { await updateService.checkForUpdates() } }
            statusPanel.toggle(from: sender)
        }
```

In `UniFiCameraPopup/Services/UpdateService.swift` ersetzen:

```swift
    func dismissError() {
```

durch:

```swift
    #if DEBUG
    /// Snapshot renderer only: shows the panel with an available update.
    func debugApply(state: UpdateState, manifest: UpdateManifest?) {
        self.state = state
        availableManifest = manifest
    }
    #endif

    func dismissError() {
```

- [ ] **Step 3: Snapshot renderer**

In `UniFiCameraPopup/Debug/SnapshotRenderer.swift` ersetzen:

```swift
                relay: relay, protect: ProtectSession.shared, clock: StatusPanelClock(),
                actions: StatusPanelActions(openSettings: {}, openHelp: {}, quit: {}, openCamera: { _ in },
                                            close: {}, resize: { _ in })
```

durch:

```swift
                relay: relay, protect: ProtectSession.shared, clock: StatusPanelClock(), updates: UpdateService(),
                actions: StatusPanelActions(openSettings: {}, openHelp: {}, quit: {}, openCamera: { _ in },
                                            installUpdate: {}, close: {}, resize: { _ in })
```

In `UniFiCameraPopup/Debug/SnapshotRenderer.swift` ersetzen:

```swift
            write(window: panelWindow, appearance: appearance, includeFrame: false,
                  to: directory.appendingPathComponent("7-panel-\(suffix).png"))
```

durch:

```swift
            write(window: panelWindow, appearance: appearance, includeFrame: false,
                  to: directory.appendingPathComponent("7-panel-\(suffix).png"))

            // 7 – menu panel with an available update (Phase 5).
            let updates = UpdateService()
            let manifestJSON = #"{"versionId":"x","buildNumber":30,"shortVersion":"1.3.0","url":"https://example.invalid/app.zip","sha256":"","signature":"s"}"#
            if let manifest = try? JSONDecoder().decode(UpdateManifest.self, from: Data(manifestJSON.utf8)) {
                updates.debugApply(state: .available(buildNumber: 30, shortVersion: "1.3.0"), manifest: manifest)
            }
            let updatePanel = NSHostingView(rootView: StatusPanelView(
                settings: sample.settings, events: EventLog.shared, protectEvents: protectEvents,
                relay: relay, protect: ProtectSession.shared, clock: StatusPanelClock(), updates: updates,
                actions: StatusPanelActions(openSettings: {}, openHelp: {}, quit: {}, openCamera: { _ in },
                                            installUpdate: {}, close: {}, resize: { _ in })
            ))
            updatePanel.frame = NSRect(origin: .zero, size: CGSize(width: 338, height: updatePanel.fittingSize.height))
            let updateWindow = NSWindow(contentRect: updatePanel.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            updateWindow.backgroundColor = .clear
            updateWindow.contentView = updatePanel
            write(window: updateWindow, appearance: appearance, includeFrame: false,
                  to: directory.appendingPathComponent("7-panel-update-\(suffix).png"))
```

- [ ] **Step 4: Build and look**

Run: Build-Befehl → `** BUILD SUCCEEDED **`; Renderer.
Expected: `7-panel-*`: nach der Trennlinie „Version 1.2.0 (<Build>)“ 11 pt grau, dann „Einstellungen …“. `7-panel-update-*`: darunter zusätzlich ein Button volle Breite im Stil „15 Min.“/„1 Std.“ mit „Update auf 1.3.0 installieren“.

- [ ] **Step 5: Commit**

```bash
git add UniFiCameraPopup/Views/StatusPanel/StatusPanel.swift UniFiCameraPopup/AppDelegate.swift \
  UniFiCameraPopup/Services/UpdateService.swift UniFiCameraPopup/Debug/SnapshotRenderer.swift
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "feat(menu): version line and update button in the menu bar panel" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Sprechen nur per gedrücktem Button (Spezifikation 9)

**Files:**
- Delete: `UniFiCameraPopup/Services/PushToTalkKey.swift` (+ 4 Zeilen in `project.pbxproj`)
- Modify: `Packages/AppCore/Sources/AppCore/Sound/SoundSettings.swift` (`TalkMode`/`talkMode` entfernen)
- Modify: `Packages/AppCore/Tests/AppCoreTests/SoundSettingsTests.swift`
- Modify: `UniFiCameraPopup/Services/TalkbackService.swift` (Leertaste, Modus)
- Modify: `UniFiCameraPopup/Services/GlobalHotkeyManager.swift` (Kommentar)
- Modify: `UniFiCameraPopup/Views/Popup/PopupTalkViews.swift` (`TalkButtonView` neu, `PopupTalkControls`)
- Modify: `UniFiCameraPopup/Views/PopupWindow.swift` (Zeiger-Weitergabe weg, Breitenanpassung)
- Modify: `UniFiCameraPopup/Views/Popup/PopupOverlayViews.swift` (Kommentare)
- Modify: `UniFiCameraPopup/Views/Settings/SoundTab.swift` (Zeile „Sprechen“ weg)
- Modify: `UniFiCameraPopup/Debug/SnapshotRenderer.swift` (Bild `9-popup-schmal`)

**Interfaces:**
- Consumes: `PopupPillFit.talkButtonFits(popupWidth:circles:talkWidth:)` (Task 1).
- Produces: `TalkbackService.startTalking(entryId:)`, `.stopTalking()`, `.toggleTalk(entryId:)` (VoiceOver), `.popupClosed(entryId:)` – `pressTalk`, `releaseTalk`, `pointerEntered/Exited` entfallen. `TalkButtonView()` mit `static let idleTitle/connectingTitle/liveTitle/hint`, `let fullWidth: CGFloat`, `var isCompact: Bool`. `PopupTalkControls.fit(popupWidth:circles:)`. `SoundSettings` ohne `talkMode`.

- [ ] **Step 1: Update the SoundSettings tests (talk mode is gone)**

In `Packages/AppCore/Tests/AppCoreTests/SoundSettingsTests.swift` ersetzen:

```swift
        XCTAssertTrue(settings.announcements.allSatisfy(\.usesBundledRecording))
        XCTAssertEqual(settings.talkMode, .hold)
```

durch:

```swift
        XCTAssertTrue(settings.announcements.allSatisfy(\.usesBundledRecording))
```

In `Packages/AppCore/Tests/AppCoreTests/SoundSettingsTests.swift` ersetzen:

```swift
        XCTAssertEqual(settings.announcements.map(\.name), ["Gong"])
        XCTAssertEqual(settings.talkMode, .hold)
```

durch:

```swift
        XCTAssertEqual(settings.announcements.map(\.name), ["Gong"])
```

Run: `(cd Packages/AppCore && swift test --filter SoundSettingsTests 2>&1 | grep -E "error:|Executed" | tail -1)` → noch grün (die Tests prüfen den Modus nur nicht mehr).

- [ ] **Step 2: Remove the talk mode from SoundSettings**

In `Packages/AppCore/Sources/AppCore/Sound/SoundSettings.swift` ersetzen:

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
```

durch:

```swift
import Foundation
```

(Der Block reicht von `import Foundation` bis zur schließenden Klammer von `enum TalkMode`; danach steht weiter `/// Einstellungen › Ton. …`.)

In `Packages/AppCore/Sources/AppCore/Sound/SoundSettings.swift` ersetzen:

```swift
    public var microphoneUID: String?
    public var talkMode: TalkMode
```

durch:

```swift
    public var microphoneUID: String?
```

In `Packages/AppCore/Sources/AppCore/Sound/SoundSettings.swift` ersetzen:

```swift
        microphoneUID: String? = nil,
        talkMode: TalkMode = .hold,
```

durch:

```swift
        microphoneUID: String? = nil,
```

In `Packages/AppCore/Sources/AppCore/Sound/SoundSettings.swift` ersetzen:

```swift
        self.microphoneUID = microphoneUID
        self.talkMode = talkMode
```

durch:

```swift
        self.microphoneUID = microphoneUID
```

In `Packages/AppCore/Sources/AppCore/Sound/SoundSettings.swift` ersetzen:

```swift
        case announcements, microphoneUID, talkMode, cameraVolume
    }

    /// Lenient: unknown talk modes, broken entries or a missing list fall back to defaults.
```

durch:

```swift
        case announcements, microphoneUID, cameraVolume
    }

    /// Lenient: broken entries or a missing list fall back to defaults. A stored `talkMode`
    /// (Phase 3) is ignored and no longer written.
```

In `Packages/AppCore/Sources/AppCore/Sound/SoundSettings.swift` ersetzen:

```swift
        let mode = (try? container.decodeIfPresent(String.self, forKey: .talkMode)) ?? nil
        talkMode = mode.flatMap(TalkMode.init(rawValue:)) ?? .hold
        let volume
```

durch:

```swift
        let volume
```

Run: `(cd Packages/AppCore && swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -1)` → `Executed 117 tests, with 0 failures`.

- [ ] **Step 3: TalkbackService – only start/stop**

In `UniFiCameraPopup/Services/TalkbackService.swift` ersetzen:

```swift
/// Push-to-talk and announcements: talkback session from Protect, microphone or file,
```

durch:

```swift
/// Talking (while the popup's talk button is held) and announcements: talkback session from Protect, microphone or file,
```

In `UniFiCameraPopup/Services/TalkbackService.swift` ersetzen:

```swift
    private var run: UUID?
    private var spaceEntry: UUID?
    private var disarmAfterRelease = false
```

durch:

```swift
    private var run: UUID?
```

In `UniFiCameraPopup/Services/TalkbackService.swift` ersetzen:

```swift
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
        // Pointer left the popup while the mouse button was held: nothing else frees the space bar.
        if disarmAfterRelease { disarmSpace() }
    }
```

durch:

```swift
    // MARK: Talking (only while the talk button is held; the popup never takes the keyboard)
```

In `UniFiCameraPopup/Services/TalkbackService.swift` ersetzen:

```swift
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
```

durch:

```swift
    /// The popup closes: stop what it started.
    func popupClosed(entryId: UUID) {
        if activity?.entryId == entryId { stopCurrent() }
    }
```

In `UniFiCameraPopup/Services/GlobalHotkeyManager.swift` ersetzen:

```swift
                // The push-to-talk space bar (PushToTalkKey) has its own signature and handler.
```

durch:

```swift
                // Only this manager's hot keys (own signature).
```

- [ ] **Step 4: Delete PushToTalkKey**

```bash
git rm -q UniFiCameraPopup/Services/PushToTalkKey.swift
grep -c "PushToTalkKey.swift" UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj   # → 4 (BuildFile, FileRef, Gruppe, Sources)
sed -i '' '/PushToTalkKey.swift/d' UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj
plutil -lint UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj   # → OK
grep -rn "PushToTalkKey\|pressTalk\|releaseTalk\|pointerEntered\|talkMode" UniFiCameraPopup --include='*.swift' | grep -v "/.build/"
```
Expected: die letzte Suche findet nur noch `PopupTalkViews.swift` und `SoundTab.swift` – die folgen in Step 5 und 7.

- [ ] **Step 5: Two-line talk button that talks only while held**

In `UniFiCameraPopup/Views/Popup/PopupTalkViews.swift` ersetzen:

```swift
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
```

durch:

```swift
/// Talk button (Phase 5, two lines): capsule 40 high, padding 0/18, radius 20, `accent`, mic 16 + 6 +
/// state line 12 pt bold („Sprechen“ → „Verbinde …“ → „Loslassen zum Beenden“) over the fixed hint
/// „Gedrückt halten zum Sprechen“ 10 pt, white 80 %. Talks only while the mouse button is held;
/// releasing ends it, also outside the button or the popup. Width = widest text (never jumps).
/// Compact (popup too narrow for the pill): a 40 pt circle with the microphone only, hint as tooltip.
final class TalkButtonView: NSView {
    static let idleTitle = "Sprechen"
    static let connectingTitle = "Verbinde …"
    static let liveTitle = "Loslassen zum Beenden"
    static let hint = "Gedrückt halten zum Sprechen"

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onAccessibilityPress: (() -> Void)?
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: TalkButtonView.hint)
    private var isHeld = false
    private let lines: NSStackView
    private var fullConstraints: [NSLayoutConstraint] = []
    private var compactConstraints: [NSLayoutConstraint] = []
    /// Width of the two-line form.
    let fullWidth: CGFloat
    /// Mouse-up anywhere (other apps included) while held: the window may not see it.
    private var releaseMonitors: [Any] = []

    init() {
        let titleFont = NSFont.systemFont(ofSize: 12, weight: .bold)
        let hintFont = NSFont.systemFont(ofSize: 10)
        let texts = [Self.idleTitle, Self.connectingTitle, Self.liveTitle].map { ($0, titleFont) } + [(Self.hint, hintFont)]
        let textWidth = texts.map { NSAttributedString(string: $0.0, attributes: [.font: $0.1]).size().width }.max() ?? 0
        fullWidth = 18 + 16 + 6 + textWidth.rounded(.up) + 18
        lines = NSStackView(views: [label, hintLabel])
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 20

        icon.image = TemplateIcon.mic.nsImage(size: 16)
        icon.contentTintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false
        label.font = titleFont
        label.textColor = .white
        hintLabel.font = hintFont
        hintLabel.textColor = NSColor.white.withAlphaComponent(0.8)
        lines.orientation = .vertical
        lines.alignment = .leading
        lines.spacing = 0
        lines.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        addSubview(lines)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 40),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            lines.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            lines.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        fullConstraints = [
            widthAnchor.constraint(equalToConstant: fullWidth),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
        ]
        compactConstraints = [
            widthAnchor.constraint(equalToConstant: 40),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
        ]
        NSLayoutConstraint.activate(fullConstraints)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityHelp(Self.hint)
        update(title: Self.idleTitle, busy: false)
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var isCompact = false {
        didSet {
            guard isCompact != oldValue else { return }
            lines.isHidden = isCompact
            NSLayoutConstraint.deactivate(isCompact ? fullConstraints : compactConstraints)
            NSLayoutConstraint.activate(isCompact ? compactConstraints : fullConstraints)
        }
    }

    /// `busy` while the talkback session is being opened (70 %).
    func update(title: String, busy: Bool) {
        label.stringValue = title
        toolTip = Self.hint
        setAccessibilityLabel(title)
        alphaValue = busy ? 0.7 : 1
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard !isHeld else { return }
        isHeld = true
        onPress?()
        let local = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.release()
            return event
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated { self?.release() }
        }
        releaseMonitors = [local, global].compactMap { $0 }
    }

    override func mouseUp(with event: NSEvent) { release() }

    /// The popup closes or the button leaves its window while held: end like a release.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { release() }
    }

    private func release() {
        guard isHeld else { return }
        isHeld = false
        releaseMonitors.forEach(NSEvent.removeMonitor)
        releaseMonitors = []
        onRelease?()
    }

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
```

In `UniFiCameraPopup/Views/Popup/PopupTalkViews.swift` ersetzen:

```swift
/// "Ton abspielen" + "Leertaste halten" of one popup, wired to `TalkbackService`.
```

durch:

```swift
/// "Ton abspielen" + talk button of one popup, wired to `TalkbackService`.
```

In `UniFiCameraPopup/Views/Popup/PopupTalkViews.swift` ersetzen:

```swift
        talkButton = TalkButtonView(title: Self.idleTitle)
```

durch:

```swift
        talkButton = TalkButtonView()
```

In `UniFiCameraPopup/Views/Popup/PopupTalkViews.swift` ersetzen:

```swift
        talkButton.onPress = { service.pressTalk(entryId: entryId) }
        talkButton.onRelease = { service.releaseTalk() }
```

durch:

```swift
        talkButton.onPress = { service.startTalking(entryId: entryId) }
        talkButton.onRelease = { service.stopTalking() }
```

In `UniFiCameraPopup/Views/Popup/PopupTalkViews.swift` ersetzen:

```swift
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
```

durch:

```swift
            .sink { [weak self] notice in self?.notice.show(notice.text) }
            .store(in: &cancellables)
    }
```

In `UniFiCameraPopup/Views/Popup/PopupTalkViews.swift` ersetzen:

```swift
        let leading = soundMenu.leadingAnchor.constraint(equalTo: soundButton.leadingAnchor, constant: -45)
        leading.priority = .defaultHigh
```

durch:

```swift
        let leading = soundMenu.leadingAnchor.constraint(equalTo: soundButton.leadingAnchor, constant: -45)
        // Below the window's own size (500): a hidden menu must never widen the popup.
        leading.priority = NSLayoutConstraint.Priority(490)
```

In `UniFiCameraPopup/Views/Popup/PopupTalkViews.swift` ersetzen:

```swift
    /// true when the click only closed the open menu.
```

durch:

```swift
    /// Two-line talk button while the pill fits into the popup, else the microphone only.
    func fit(popupWidth: CGFloat, circles: Int) {
        talkButton.isCompact = !PopupPillFit.talkButtonFits(popupWidth: popupWidth, circles: circles, talkWidth: talkButton.fullWidth)
    }

    /// true when the click only closed the open menu.
```

In `UniFiCameraPopup/Views/Popup/PopupTalkViews.swift` ersetzen:

```swift
    var isBusy: Bool { TalkbackService.shared.isActive(entryId: entryId) }

    func pointerInside(_ inside: Bool) {
        if inside {
            TalkbackService.shared.pointerEntered(entryId: entryId)
        } else {
            TalkbackService.shared.pointerExited(entryId: entryId)
        }
    }
```

durch:

```swift
    var isBusy: Bool { TalkbackService.shared.isActive(entryId: entryId) }
```

In `UniFiCameraPopup/Views/Popup/PopupTalkViews.swift` ersetzen:

```swift
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
```

durch:

```swift
        case .talk?:
            let live = mine?.phase == .live
            talkButton.update(title: live ? TalkButtonView.liveTitle : TalkButtonView.connectingTitle, busy: !live)
            setSoundActive(false)
        case .announcement?:
            talkButton.update(title: TalkButtonView.idleTitle, busy: false)
            setSoundActive(true)
        case nil:
            talkButton.update(title: TalkButtonView.idleTitle, busy: false)
            setSoundActive(false)
```

- [ ] **Step 6: Popup window – no pointer tracking for keys, follow the width**

In `UniFiCameraPopup/Views/PopupWindow.swift` ersetzen:

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

durch:

```swift
            clickCatcher.onMouseEnter = { [weak self] in
                self?.pauseAutoClose()
            }
            clickCatcher.onMouseExit = { [weak self] in
                self?.resumeAutoClose()
            }
```

In `UniFiCameraPopup/Views/PopupWindow.swift` ersetzen:

```swift
    private var escapeMonitor: Any?
```

durch:

```swift
    private var escapeMonitor: Any?
    private var resizeObserver: NSObjectProtocol?
```

In `UniFiCameraPopup/Views/PopupWindow.swift` ersetzen:

```swift
            controls.onMenuOpened = { [weak self] in self?.muteMenu?.isHidden = true }
            talkControls = controls
        }
```

durch:

```swift
            controls.onMenuOpened = { [weak self] in self?.muteMenu?.isHidden = true }
            talkControls = controls
            // The stack resizes popups (also animated): the talk button follows the width.
            let circles = 1 + min(actions.count, WebhookMapping.maxActions)
            controls.fit(popupWidth: frame.width, circles: circles)
            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification, object: self, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.talkControls?.fit(popupWidth: self.frame.width, circles: circles)
                }
            }
        }
```

In `UniFiCameraPopup/Views/PopupWindow.swift` ersetzen:

```swift
    func closePopup() {
        talkControls?.popupClosed()
```

durch:

```swift
    func closePopup() {
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
            self.resizeObserver = nil
        }
        talkControls?.popupClosed()
```

In `UniFiCameraPopup/Views/Popup/PopupOverlayViews.swift` ersetzen:

```swift
    /// Phase 3: "Ton abspielen" and "Leertaste halten"; nil = camera without speaker.
```

durch:

```swift
    /// "Ton abspielen" and the talk button; nil = camera without speaker.
```

In `UniFiCameraPopup/Views/Popup/PopupOverlayViews.swift` ersetzen:

```swift
    /// `leadingViews` (Ton abspielen, Leertaste halten) come before the user's buttons.
```

durch:

```swift
    /// `leadingViews` (Ton abspielen, Sprechen) come before the user's buttons.
```

- [ ] **Step 7: Settings › Ton without „Sprechen“**

In `UniFiCameraPopup/Views/Settings/SoundTab.swift` ersetzen:

```swift
            CardDivider()
            CardRow(title: "Sprechen") {
                TokenSegmented(
                    selection: $store.settings.talkMode,
                    options: TalkMode.allCases.map { (value: $0, title: $0.label) }
                )
            }
            CardDivider()
```

durch:

```swift
            CardDivider()
```

In `UniFiCameraPopup/Views/Settings/SoundTab.swift` ersetzen:

```swift
    // MARK: Microphone, mode, volume
```

durch:

```swift
    // MARK: Microphone, volume
```

- [ ] **Step 8: Snapshot of the narrowest popup**

In `UniFiCameraPopup/Debug/SnapshotRenderer.swift` ersetzen:

```swift
            // 9 – popup with "Ton abspielen" / "Leertaste halten": idle, announcement menu, connecting, talking, playing, notice.
```

durch:

```swift
            // 9 – popup with "Ton abspielen" / "Sprechen": idle, announcement menu, connecting, talking, playing, notice.
```

In `UniFiCameraPopup/Debug/SnapshotRenderer.swift` ersetzen:

```swift
                TalkbackService.shared.debugApply(activity: nil, notice: nil)
            }
```

durch:

```swift
                TalkbackService.shared.debugApply(activity: nil, notice: nil)
            }

            // 9 – smallest stacked popup (160 high, 16:9): talk button shrinks to the microphone (Phase 5).
            let narrow = PopupWindow(
                frame: NSRect(x: 0, y: 0, width: 284, height: 160),
                streamURL: "", soundEnabled: false,
                thumbnailDataURI: placeholderDataURI(size: CGSize(width: 284, height: 160)),
                autoCloseSeconds: 0,
                actions: sample.door.actions,
                overlay: PopupOverlayContent(
                    chipText: nil, cameraName: "Haustür",
                    muteOptions: sample.settings.muteOptions, onMute: { _ in },
                    talk: PopupTalkContent(entryId: doorId)
                ),
                onClose: {}
            )
            write(window: narrow, appearance: appearance, includeFrame: false,
                  to: directory.appendingPathComponent("9-popup-schmal-\(suffix).png"))
```

- [ ] **Step 9: Build and look**

Run: Build-Befehl → `** BUILD SUCCEEDED **`; Renderer; dabei die Konsolenzeilen prüfen:

```bash
"$DD/Build/Products/Debug/UniFi Camera Popup.app/Contents/MacOS/UniFi Camera Popup" --render-snapshots "$OUT" | grep "render 9"
```
Expected: alle `9-popup-sprechen-*` mit `window (470.0, 300.0)`, `9-popup-schmal-*` mit `window (284.0, 160.0)` – **nie breiter** (vorher hat das versteckte Ansagen-Menü das Fenster auf 486 verbreitert). Bilder: `9-popup-sprechen-ruhe`: Button zweizeilig „Sprechen“ / „Gedrückt halten zum Sprechen“; `-verbinde`: „Verbinde …“ 70 %; `-spricht`: „Loslassen zum Beenden“; Button-Breite in allen drei gleich. `9-popup-schmal`: Mikrofon im Kreis, Leiste innerhalb des Popups.

- [ ] **Step 10: Commit**

```bash
git add Packages/AppCore/Sources/AppCore/Sound/SoundSettings.swift Packages/AppCore/Tests/AppCoreTests/SoundSettingsTests.swift \
  UniFiCameraPopup/Services/TalkbackService.swift UniFiCameraPopup/Services/GlobalHotkeyManager.swift \
  UniFiCameraPopup/Views/Popup/PopupTalkViews.swift UniFiCameraPopup/Views/PopupWindow.swift \
  UniFiCameraPopup/Views/Popup/PopupOverlayViews.swift UniFiCameraPopup/Views/Settings/SoundTab.swift \
  UniFiCameraPopup/Debug/SnapshotRenderer.swift UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "feat(talk): talk only while the button is held, two-line button, no space bar" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
(`git rm` hat `PushToTalkKey.swift` schon vorgemerkt.)

---

### Task 7: Popup-Größe automatisch, Stapel passt immer, animiert (Spezifikation 3, 4)

**Files:**
- Modify: `UniFiCameraPopup/Models/WebhookMapping.swift` (`sizeOverride`, Migration 480 × 270)
- Modify: `UniFiCameraPopup/Models/PopupPosition.swift` (`anchor`)
- Modify: `UniFiCameraPopup/Services/SettingsStore.swift` (Erweiterung, Ausschnitt)
- Modify: `UniFiCameraPopup/Services/ProtectSession.swift` (Seitenverhältnisse)
- Modify: `UniFiCameraPopup/Services/PopupController.swift` (Größe, `relayout`, Ausschnitt-Fenster, `popupSize`)
- Modify: `UniFiCameraPopup/Services/WindowPositioner.swift` (`stackedFrames` entfällt)
- Modify: `UniFiCameraPopup/Views/Settings/CameraAdvancedSection.swift` („Größe“)

**Interfaces:**
- Consumes: `PopupSizeOverride`, `PopupSizing`, `PopupAnchor`, `PopupStackLayout` (Task 1); `SettingsExtensions.Mapping.size` (Task 3).
- Produces: `WebhookMapping.sizeOverride: PopupSizeOverride`; `PopupPosition.anchor: PopupAnchor`; `ProtectSession.aspectRatios: [String: Double]` (published), `ProtectSession.aspectRatio(cameraId:) -> Double?`; `@MainActor extension WebhookMapping { var popupAspectRatio: Double?; func popupSize(on: NSScreen, margin: CGFloat) -> CGSize }`.

Logik und Grenzfälle sind in `PopupLayoutTests` (Task 1) abgedeckt; hier nur Verdrahtung.

- [ ] **Step 1: Size override in the model (with migration)**

In `UniFiCameraPopup/Models/WebhookMapping.swift` ersetzen:

```swift
import Foundation
import ProtectKit
```

durch:

```swift
import AppCore
import Foundation
import ProtectKit
```

In `UniFiCameraPopup/Models/WebhookMapping.swift` ersetzen:

```swift
    /// „Name und Zeit einblenden“: the app's own chip (camera OSD shows the same). Default off.
    var showNameAndTime: Bool
```

durch:

```swift
    /// „Name und Zeit einblenden“: the app's own chip (camera OSD shows the same). Default off.
    var showNameAndTime: Bool
    /// „Größe“ (Phase 5): empty = automatic (42 % of the screen height). `width`/`height` stay the
    /// last concrete size (crop, older builds) and give the aspect ratio of a crop.
    var sizeOverride: PopupSizeOverride
```

In `UniFiCameraPopup/Models/WebhookMapping.swift` ersetzen:

```swift
        case showNameAndTime
        case widthOverride
```

durch:

```swift
        case showNameAndTime
        case sizeOverride
        case widthOverride
```

In `UniFiCameraPopup/Models/WebhookMapping.swift` ersetzen:

```swift
        chimeOnOpen: Bool = false,
        showNameAndTime: Bool = false
    ) {
```

durch:

```swift
        chimeOnOpen: Bool = false,
        showNameAndTime: Bool = false,
        sizeOverride: PopupSizeOverride = .automatic
    ) {
```

In `UniFiCameraPopup/Models/WebhookMapping.swift` ersetzen:

```swift
        self.showNameAndTime = showNameAndTime
    }
```

durch:

```swift
        self.showNameAndTime = showNameAndTime
        self.sizeOverride = sizeOverride
    }
```

In `UniFiCameraPopup/Models/WebhookMapping.swift` ersetzen:

```swift
        showNameAndTime = (try? container.decodeIfPresent(Bool.self, forKey: .showNameAndTime)) ?? false
    }
```

durch:

```swift
        showNameAndTime = (try? container.decodeIfPresent(Bool.self, forKey: .showNameAndTime)) ?? false
        // Written before Phase 5: the old default 480 × 270 becomes automatic, other sizes stay.
        sizeOverride = ((try? container.decodeIfPresent(PopupSizeOverride.self, forKey: .sizeOverride)) ?? nil)
            ?? .migrated(width: width, height: height)
    }
```

In `UniFiCameraPopup/Models/WebhookMapping.swift` ersetzen:

```swift
        try container.encode(showNameAndTime, forKey: .showNameAndTime)
    }
```

durch:

```swift
        try container.encode(showNameAndTime, forKey: .showNameAndTime)
        try container.encode(sizeOverride, forKey: .sizeOverride)
    }
```

In `UniFiCameraPopup/Models/PopupPosition.swift` ersetzen:

```swift
import Foundation
```

durch:

```swift
import AppCore
import Foundation
```

In `UniFiCameraPopup/Models/PopupPosition.swift` ersetzen:

```swift
    var stacksUpward: Bool {
        switch self {
        case .bottomLeft, .bottomCenter, .bottomRight:
            return true
        default:
            return false
        }
    }
}
```

durch:

```swift
    var stacksUpward: Bool {
        switch self {
        case .bottomLeft, .bottomCenter, .bottomRight:
            return true
        default:
            return false
        }
    }

    /// Anchor of the popup stack (`PopupStackLayout`).
    var anchor: PopupAnchor {
        switch self {
        case .topLeft: return PopupAnchor(horizontal: .leading, vertical: .top)
        case .topCenter: return PopupAnchor(horizontal: .center, vertical: .top)
        case .topRight: return PopupAnchor(horizontal: .trailing, vertical: .top)
        case .middleLeft: return PopupAnchor(horizontal: .leading, vertical: .middle)
        case .center: return PopupAnchor(horizontal: .center, vertical: .middle)
        case .middleRight: return PopupAnchor(horizontal: .trailing, vertical: .middle)
        case .bottomLeft: return PopupAnchor(horizontal: .leading, vertical: .bottom)
        case .bottomCenter: return PopupAnchor(horizontal: .center, vertical: .bottom)
        case .bottomRight: return PopupAnchor(horizontal: .trailing, vertical: .bottom)
        }
    }
}
```

- [ ] **Step 2: Persistence and crop**

In `UniFiCameraPopup/Services/SettingsStore.swift` ersetzen:

```swift
                if let show = m.showNameAndTime { mapping.showNameAndTime = show }
```

durch:

```swift
                if let show = m.showNameAndTime { mapping.showNameAndTime = show }
                if let size = m.size { mapping.sizeOverride = size }
```

In `UniFiCameraPopup/Services/SettingsStore.swift` ersetzen:

```swift
                chimeOnOpen: mapping.chimeOnOpen,
                showNameAndTime: mapping.showNameAndTime
            )
```

durch:

```swift
                chimeOnOpen: mapping.chimeOnOpen,
                showNameAndTime: mapping.showNameAndTime,
                size: mapping.sizeOverride
            )
```

In `UniFiCameraPopup/Services/SettingsStore.swift` ersetzen:

```swift
        mappings[index].crop = savedCrop
        mappings[index].width = max(pixelWidth, 40)
        mappings[index].height = max(pixelHeight, 40)
    }
```

durch:

```swift
        mappings[index].crop = savedCrop
        mappings[index].width = max(pixelWidth, 40)
        mappings[index].height = max(pixelHeight, 40)
        // A typed size becomes the crop's size (as before); automatic stays automatic with the crop's aspect.
        if mappings[index].sizeOverride.width != nil, mappings[index].sizeOverride.height != nil {
            mappings[index].sizeOverride = PopupSizeOverride(width: mappings[index].width, height: mappings[index].height)
        }
    }
```

In `UniFiCameraPopup/Services/SettingsStore.swift` ersetzen:

```swift
        mappings[index].width = crop.originalWidth
        mappings[index].height = crop.originalHeight
        mappings[index].crop = nil
    }
```

durch:

```swift
        mappings[index].width = crop.originalWidth
        mappings[index].height = crop.originalHeight
        mappings[index].crop = nil
        if mappings[index].sizeOverride.width != nil, mappings[index].sizeOverride.height != nil {
            mappings[index].sizeOverride = PopupSizeOverride(width: crop.originalWidth, height: crop.originalHeight)
        }
    }
```

- [ ] **Step 3: Learn each camera's aspect ratio**

In `UniFiCameraPopup/Services/ProtectSession.swift` ersetzen:

```swift
    private var snapshotCache: [String: (image: NSImage, date: Date)] = [:]
```

durch:

```swift
    private var snapshotCache: [String: (image: NSImage, date: Date)] = [:]
    /// Width / height of each camera's picture, learned from snapshots (automatic popup size).
    /// Kept across reconnects: a camera's picture format does not depend on the route.
    @Published private(set) var aspectRatios: [String: Double] = [:]
```

In `UniFiCameraPopup/Services/ProtectSession.swift` ersetzen:

```swift
            guard client === self.client else { return }
            cameras = result
            lastError = nil
        } catch {
```

durch:

```swift
            guard client === self.client else { return }
            cameras = result
            lastError = nil
            prefetchAspectRatios()
        } catch {
```

In `UniFiCameraPopup/Services/ProtectSession.swift` ersetzen:

```swift
        if client === self.client {
            snapshotCache[cameraId] = (image, Date())
        }
        return image
    }
```

durch:

```swift
        if client === self.client {
            snapshotCache[cameraId] = (image, Date())
        }
        if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            aspectRatios[cameraId] = Double(rep.pixelsWide) / Double(rep.pixelsHigh)
        }
        return image
    }

    /// nil until a snapshot of the camera was seen.
    func aspectRatio(cameraId: String) -> Double? {
        aspectRatios[cameraId]
    }

    /// One snapshot per linked camera whose picture format is still unknown (once per launch).
    private func prefetchAspectRatios() {
        let missing = Set(settings.mappings.compactMap(\.protectCameraId)).filter { aspectRatios[$0] == nil }
        guard !missing.isEmpty else { return }
        Task {
            for cameraId in missing {
                _ = await snapshot(cameraId: cameraId)
            }
        }
    }
```

- [ ] **Step 4: Stack with PopupStackLayout, animated**

In `UniFiCameraPopup/Services/PopupController.swift` ersetzen:

```swift
        /// The position used when only a single popup is shown.
        let position: PopupPosition
    }
```

durch:

```swift
        /// The position used when only a single popup is shown.
        let position: PopupPosition
        /// Crop selection keeps its size; the stack never resizes it.
        var fixedSize = false
    }
```

In `UniFiCameraPopup/Services/PopupController.swift` ersetzen:

```swift
            let window = makeAlarmWindow(event: event, mapping: mapping, streamURL: streamURL)
            activePopups.append(
                ActivePopup(
                    entryId: mapping.entryId,
                    window: window,
                    size: CGSize(width: CGFloat(mapping.width), height: CGFloat(mapping.height)),
                    position: mapping.positionOverride ?? settings.defaultPosition
                )
            )
```

durch:

```swift
            let screen = WindowPositioner.targetScreen(for: settings.screenTarget)
            let size = mapping.popupSize(on: screen, margin: CGFloat(settings.edgeMargin))
            let window = makeAlarmWindow(event: event, mapping: mapping, streamURL: streamURL, size: size)
            activePopups.append(
                ActivePopup(
                    entryId: mapping.entryId,
                    window: window,
                    size: size,
                    position: mapping.positionOverride ?? settings.defaultPosition
                )
            )
```

In `UniFiCameraPopup/Services/PopupController.swift` ersetzen:

```swift
    private func makeAlarmWindow(
        event: TriggerEvent,
        mapping: WebhookMapping,
        streamURL: String
    ) -> PopupWindow {
```

durch:

```swift
    private func makeAlarmWindow(
        event: TriggerEvent,
        mapping: WebhookMapping,
        streamURL: String,
        size: CGSize
    ) -> PopupWindow {
```

In `UniFiCameraPopup/Services/PopupController.swift` ersetzen:

```swift
            frame: NSRect(x: 0, y: 0, width: CGFloat(mapping.width), height: CGFloat(mapping.height)),
            streamURL: streamURL,
            soundEnabled: mapping.soundEnabled,
```

durch:

```swift
            frame: NSRect(origin: .zero, size: size),
            streamURL: streamURL,
            soundEnabled: mapping.soundEnabled,
```

In `UniFiCameraPopup/Services/PopupController.swift` ersetzen:

```swift
    /// Repositions every active popup. With "show all" enabled the popups are
    /// stacked at the default position; otherwise the single popup uses its own
    /// (possibly overridden) position.
    private func relayout() {
        guard !activePopups.isEmpty else { return }

        let screen = WindowPositioner.targetScreen(for: settings.screenTarget)
        let margin = CGFloat(settings.edgeMargin)

        if settings.showAllActiveCameras {
            let frames = WindowPositioner.stackedFrames(
                sizes: activePopups.map(\.size),
                position: settings.defaultPosition,
                margin: margin,
                screen: screen
            )
            for (index, popup) in activePopups.enumerated() {
                popup.window.setFrame(frames[index], display: true)
            }
        } else {
            for popup in activePopups {
                let frame = WindowPositioner.frame(
                    width: popup.size.width,
                    height: popup.size.height,
                    position: popup.position,
                    margin: margin,
                    screen: screen
                )
                popup.window.setFrame(frame, display: true)
            }
        }
    }
```

durch:

```swift
    /// Lays out every active popup (`PopupStackLayout`): all stay fully visible – with more popups
    /// than room they shrink together, after a close they grow back towards their own size.
    /// With "show all" the stack sits at the default position, otherwise the single popup at its own.
    /// Size changes animate 300 ms ease-in-ease-out, without animation under "Bewegung reduzieren".
    private func relayout() {
        let popups = activePopups.filter { !$0.fixedSize }
        guard !popups.isEmpty else { return }

        let screen = WindowPositioner.targetScreen(for: settings.screenTarget)
        let margin = CGFloat(settings.edgeMargin)
        // Re-read the settings: a changed size or a learned aspect ratio applies on the next layout.
        let sizes = popups.map { popup in
            settings.mapping(forEntry: popup.entryId)?.popupSize(on: screen, margin: margin) ?? popup.size
        }
        let position = settings.showAllActiveCameras ? settings.defaultPosition : popups[0].position
        let frames = PopupStackLayout.frames(
            sizes: sizes,
            anchor: position.anchor,
            visible: screen.visibleFrame,
            margin: margin
        )
        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for (popup, frame) in zip(popups, frames) {
            let window = popup.window
            // A popup not on screen yet appears in place; the others glide.
            guard animate, window.isVisible, window.frame != frame else {
                window.setFrame(frame, display: true)
                continue
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            }
        }
    }
```

In `UniFiCameraPopup/Services/PopupController.swift` ersetzen:

```swift
        let position = mapping.positionOverride ?? settings.defaultPosition
        let width = CGFloat(mapping.width)
        let height = CGFloat(mapping.height)
        let screen = WindowPositioner.targetScreen(for: settings.screenTarget)
        let frame = WindowPositioner.frame(
            width: width,
            height: height,
            position: position,
            margin: CGFloat(settings.edgeMargin),
            screen: screen
        )

        let entryId = mapping.entryId
        let originalWidth = mapping.width
        let originalHeight = mapping.height
```

durch:

```swift
        let position = mapping.positionOverride ?? settings.defaultPosition
        let screen = WindowPositioner.targetScreen(for: settings.screenTarget)
        let margin = CGFloat(settings.edgeMargin)
        // The popup's real size (automatic or typed); the crop is measured against it.
        let size = mapping.popupSize(on: screen, margin: margin)
        let frame = PopupStackLayout.frames(
            sizes: [size],
            anchor: position.anchor,
            visible: screen.visibleFrame,
            margin: margin
        )[0]

        let entryId = mapping.entryId
        let originalWidth = Double(frame.width)
        let originalHeight = Double(frame.height)
```

In `UniFiCameraPopup/Services/PopupController.swift` ersetzen:

```swift
        activePopups.append(
            ActivePopup(
                entryId: entryId,
                window: window,
                size: CGSize(width: width, height: height),
                position: position
            )
        )
        window.orderFrontRegardless()
```

durch:

```swift
        activePopups.append(
            ActivePopup(
                entryId: entryId,
                window: window,
                size: frame.size,
                position: position,
                fixedSize: true
            )
        )
        window.orderFrontRegardless()
```

An `UniFiCameraPopup/Services/PopupController.swift` anhängen:

```swift

extension WebhookMapping {
    /// Width / height for the automatic size: the crop's, else the camera picture's (once seen),
    /// else nil (16:9).
    @MainActor
    var popupAspectRatio: Double? {
        if crop != nil, width > 0, height > 0 { return width / height }
        return protectCameraId.flatMap(ProtectSession.shared.aspectRatio(cameraId:))
    }

    /// The size this camera's popup asks for on `screen` (before the stack shrinks it).
    @MainActor
    func popupSize(on screen: NSScreen, margin: CGFloat) -> CGSize {
        PopupSizing.size(override: sizeOverride, aspect: popupAspectRatio, visible: screen.visibleFrame.size, margin: margin)
    }
}
```

In `UniFiCameraPopup/Services/WindowPositioner.swift` ersetzen (vom Ende von `frame(…)` bis zum Dateiende – `stackedFrames` wird nicht mehr gebraucht):

```swift
        return NSRect(origin: origin, size: size)
    }

    /// Lays out several popups in a vertical stack anchored at `position`. The
    /// first entry sits at the anchor; subsequent entries are placed beneath it
    /// (or above it for bottom anchors so the stack stays on screen). Horizontal
    /// alignment for each popup matches the single-popup placement for its size,
    /// preserving the order of `sizes`.
    static func stackedFrames(
        sizes: [CGSize],
        position: PopupPosition,
        margin: CGFloat,
        screen: NSScreen,
        gap: CGFloat = 12
    ) -> [NSRect] {
        guard !sizes.isEmpty else { return [] }

        let baseFrames = sizes.map {
            frame(width: $0.width, height: $0.height, position: position, margin: margin, screen: screen)
        }

        var result: [NSRect] = []
        result.reserveCapacity(sizes.count)

        if position.stacksUpward {
            var bottom = baseFrames[0].minY
            for (index, size) in sizes.enumerated() {
                result.append(NSRect(x: baseFrames[index].minX, y: bottom, width: size.width, height: size.height))
                bottom += size.height + gap
            }
        } else {
            var top = baseFrames[0].maxY
            for (index, size) in sizes.enumerated() {
                let originY = top - size.height
                result.append(NSRect(x: baseFrames[index].minX, y: originY, width: size.width, height: size.height))
                top = originY - gap
            }
        }

        return result
    }
}
```

durch:

```swift
        return NSRect(origin: origin, size: size)
    }
}
```

- [ ] **Step 5: „Größe“ – empty = automatic, placeholders show the computed size**

In `UniFiCameraPopup/Views/Settings/CameraAdvancedSection.swift` ersetzen:

```swift
                FixedLabelRow(title: "Größe") {
                    TokenTextField(placeholder: "480", text: dimensionBinding($mapping.width)).frame(width: 64)
                    Text("×").foregroundStyle(Tokens.muted.color)
                    TokenTextField(placeholder: "270", text: dimensionBinding($mapping.height)).frame(width: 64)
                    Text("px").font(.system(size: 12)).foregroundStyle(Tokens.muted.color)
                    Spacer(minLength: 0)
                }
```

durch:

```swift
                FixedLabelRow(title: "Größe") {
                    // Empty = automatic; the placeholders show what is used right now.
                    let current = mapping.popupSize(
                        on: WindowPositioner.targetScreen(for: settings.screenTarget),
                        margin: CGFloat(settings.edgeMargin)
                    )
                    TokenTextField(placeholder: String(Int(current.width)), text: sizeBinding(\.width)).frame(width: 64)
                    Text("×").foregroundStyle(Tokens.muted.color)
                    TokenTextField(placeholder: String(Int(current.height)), text: sizeBinding(\.height)).frame(width: 64)
                    Text("px").font(.system(size: 12)).foregroundStyle(Tokens.muted.color)
                    Spacer(minLength: 0)
                }
```

In `UniFiCameraPopup/Views/Settings/CameraAdvancedSection.swift` ersetzen:

```swift
    private func dimensionBinding(_ value: Binding<Double>) -> Binding<String> {
        Binding(
            get: { String(Int(value.wrappedValue)) },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                guard !digits.isEmpty, let parsed = Double(digits) else { return }
                value.wrappedValue = parsed
            }
        )
    }
```

durch:

```swift
    /// One size field: digits, empty = automatic for this side.
    private func sizeBinding(_ side: WritableKeyPath<PopupSizeOverride, Double?>) -> Binding<String> {
        Binding(
            get: { mapping.sizeOverride[keyPath: side].map { String(Int($0)) } ?? "" },
            set: { mapping.sizeOverride[keyPath: side] = PopupSizeOverride.value(fromText: $0) }
        )
    }
```

(`CameraAdvancedSection` beobachtet `ProtectSession.shared` schon: ein gelerntes Seitenverhältnis aktualisiert die Platzhalter.)

- [ ] **Step 6: Build and look**

Run: Build-Befehl → `** BUILD SUCCEEDED **`; `grep -rn "stackedFrames" UniFiCameraPopup --include='*.swift' | grep -v "/.build/"` → keine Ausgabe; Renderer.
Expected: `S3-kameras-erweitert-*`: „Größe“ zeigt zwei leere Felder mit grauen Platzhaltern (≈ 42 % der Bildschirmhöhe dieses Macs × 16:9, z. B. „809 × 455“ bei 1080 pt sichtbarer Höhe), danach „px“.

- [ ] **Step 7: Commit**

```bash
git add UniFiCameraPopup/Models/WebhookMapping.swift UniFiCameraPopup/Models/PopupPosition.swift \
  UniFiCameraPopup/Services/SettingsStore.swift UniFiCameraPopup/Services/ProtectSession.swift \
  UniFiCameraPopup/Services/PopupController.swift UniFiCameraPopup/Services/WindowPositioner.swift \
  UniFiCameraPopup/Views/Settings/CameraAdvancedSection.swift
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "feat(popup): automatic size, stack always fits the screen, animated resizing" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Lautstärke – gleich laut, zwei Regler (Spezifikation 10)

**Files:**
- Modify: `Packages/AppCore/Sources/AppCore/Sound/SoundSettings.swift` (zwei Lautstärken, Übernahme der alten)
- Modify: `Packages/AppCore/Sources/AppCore/Sound/Announcement.swift` (`loudnessGain`)
- Modify: `Packages/AppCore/Tests/AppCoreTests/SoundSettingsTests.swift`
- Modify: `UniFiCameraPopup/Services/SoundStore.swift` (messen beim Import/Erzeugen, Hintergrund-Messung)
- Modify: `UniFiCameraPopup/Services/TalkbackService.swift` (Verstärkungen an den Sender)
- Modify: `UniFiCameraPopup/Views/Settings/SoundTab.swift` (zwei Regler)

**Interfaces:**
- Consumes: `AnnouncementAudio.loudnessGain(of:)`, `TalkbackStreamer(target:gain:automaticGain:…)` (Task 2).
- Produces: `SoundSettings.talkVolume`, `.announcementVolume: Double` (0…1), `.talkGain`, `.announcementGain: Float` (× 1,5); `SoundSettings.cameraVolume`/`.gain` entfallen. `Announcement.loudnessGain: Double?`. `SoundStore.storeLoudness(of: AVAudioPCMBuffer, for: UUID) -> Float` (`@discardableResult`).

- [ ] **Step 1: Write the failing tests**

In `Packages/AppCore/Tests/AppCoreTests/SoundSettingsTests.swift` ersetzen:

```swift
        XCTAssertEqual(settings.gain, 1, accuracy: 0.0001)
```

durch:

```swift
        XCTAssertEqual(settings.talkGain, 1, accuracy: 0.0001)
        XCTAssertEqual(settings.announcementGain, 1, accuracy: 0.0001)
```

In `Packages/AppCore/Tests/AppCoreTests/SoundSettingsTests.swift` ersetzen:

```swift
        XCTAssertEqual(settings.cameraVolume, 1)
```

durch:

```swift
        XCTAssertEqual(settings.talkVolume, 1)
        XCTAssertEqual(settings.announcementVolume, 1)
```

In `Packages/AppCore/Tests/AppCoreTests/SoundSettingsTests.swift` ersetzen:

```swift
    func testRoundTripAndEditing() throws {
```

durch:

```swift
    func testOldSingleVolumeGoesIntoBoth() throws {
        let old = try JSONDecoder().decode(SoundSettings.self, from: Data(#"{"talkMode":"toggle","cameraVolume":0.4}"#.utf8))
        XCTAssertEqual(old.talkVolume, 0.4)
        XCTAssertEqual(old.announcementVolume, 0.4)
        var changed = old
        changed.talkVolume = 0.9
        let json = String(decoding: try JSONEncoder().encode(changed), as: UTF8.self)
        XCTAssertFalse(json.contains("talkMode"))
        XCTAssertFalse(json.contains("cameraVolume"))
        let again = try JSONDecoder().decode(SoundSettings.self, from: Data(json.utf8))
        XCTAssertEqual(again.talkVolume, 0.9)
        XCTAssertEqual(again.announcementVolume, 0.4)
    }

    func testLoudnessGainIsLenient() throws {
        let json = #"{"id":"6F0C6A52-4C4B-4E58-9B1E-2F3C1C0A0009","name":"Gong","kind":"file","loudnessGain":"laut"}"#
        XCTAssertNil(try JSONDecoder().decode(Announcement.self, from: Data(json.utf8)).loudnessGain)
        let measured = Announcement(name: "Gong", kind: .file, loudnessGain: 0.5)
        XCTAssertEqual(try JSONDecoder().decode(Announcement.self, from: JSONEncoder().encode(measured)).loudnessGain, 0.5)
        XCTAssertNil(Announcement(name: "x", kind: .file, loudnessGain: .infinity).loudnessGain)
    }

    func testRoundTripAndEditing() throws {
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `(cd Packages/AppCore && swift test --filter SoundSettingsTests 2>&1 | grep -E "error:" | head -3)`
Expected: FAIL – `error: value of type 'SoundSettings' has no member 'talkGain'`

- [ ] **Step 3: Two volumes, measured loudness**

In `Packages/AppCore/Sources/AppCore/Sound/SoundSettings.swift` ersetzen:

```swift
    public var microphoneUID: String?
    /// 0…1 slider; gain = volume × 1.5 (template default 2/3 = 1.0).
    public var cameraVolume: Double

    public init(
        announcements: [Announcement] = SoundSettings.bundled,
        microphoneUID: String? = nil,
        cameraVolume: Double = SoundSettings.defaultVolume
    ) {
        self.announcements = announcements
        self.microphoneUID = microphoneUID
        self.cameraVolume = min(1, max(0, cameraVolume))
    }

    public var gain: Float { Float(cameraVolume * 1.5) }
```

durch:

```swift
    public var microphoneUID: String?
    /// „Lautstärke Sprechen“, 0…1; gain = volume × 1.5 (2/3 = unchanged after the automatic gain).
    public var talkVolume: Double
    /// „Lautstärke Ansagen“, 0…1; gain = volume × 1.5 (2/3 = unchanged after normalization).
    public var announcementVolume: Double

    public init(
        announcements: [Announcement] = SoundSettings.bundled,
        microphoneUID: String? = nil,
        talkVolume: Double = SoundSettings.defaultVolume,
        announcementVolume: Double = SoundSettings.defaultVolume
    ) {
        self.announcements = announcements
        self.microphoneUID = microphoneUID
        self.talkVolume = Self.clamped(talkVolume)
        self.announcementVolume = Self.clamped(announcementVolume)
    }

    public var talkGain: Float { Float(talkVolume * 1.5) }
    public var announcementGain: Float { Float(announcementVolume * 1.5) }

    private static func clamped(_ volume: Double) -> Double {
        volume.isFinite ? min(1, max(0, volume)) : defaultVolume
    }
```

In `Packages/AppCore/Sources/AppCore/Sound/SoundSettings.swift` ersetzen:

```swift
        case announcements, microphoneUID, cameraVolume
    }
```

durch:

```swift
        /// `cameraVolume`: the single slider before Phase 5, read once into both new ones.
        case announcements, microphoneUID, talkVolume, announcementVolume, cameraVolume
    }
```

In `Packages/AppCore/Sources/AppCore/Sound/SoundSettings.swift` ersetzen:

```swift
        let volume = (try? container.decodeIfPresent(Double.self, forKey: .cameraVolume)) ?? nil
        cameraVolume = min(1, max(0, volume ?? Self.defaultVolume))
    }
```

durch:

```swift
        let legacy = (try? container.decodeIfPresent(Double.self, forKey: .cameraVolume)) ?? nil
        let talk = (try? container.decodeIfPresent(Double.self, forKey: .talkVolume)) ?? nil
        let announcement = (try? container.decodeIfPresent(Double.self, forKey: .announcementVolume)) ?? nil
        talkVolume = Self.clamped(talk ?? legacy ?? Self.defaultVolume)
        announcementVolume = Self.clamped(announcement ?? legacy ?? Self.defaultVolume)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(announcements, forKey: .announcements)
        try container.encodeIfPresent(microphoneUID, forKey: .microphoneUID)
        try container.encode(talkVolume, forKey: .talkVolume)
        try container.encode(announcementVolume, forKey: .announcementVolume)
    }
```

In `Packages/AppCore/Sources/AppCore/Sound/Announcement.swift` ersetzen:

```swift
    /// Seconds; 0 = unknown.
    public var duration: TimeInterval
```

durch:

```swift
    /// Seconds; 0 = unknown.
    public var duration: TimeInterval
    /// Factor to the common loudness (`Loudness`), measured on import/rendering; nil = not yet.
    public var loudnessGain: Double?
```

In `Packages/AppCore/Sources/AppCore/Sound/Announcement.swift` ersetzen:

```swift
        bundledResource: String? = nil,
        duration: TimeInterval = 0
    ) {
```

durch:

```swift
        bundledResource: String? = nil,
        duration: TimeInterval = 0,
        loudnessGain: Double? = nil
    ) {
```

In `Packages/AppCore/Sources/AppCore/Sound/Announcement.swift` ersetzen:

```swift
        self.duration = duration
    }
```

durch:

```swift
        self.duration = duration
        self.loudnessGain = Self.validGain(loudnessGain)
    }

    private static func validGain(_ gain: Double?) -> Double? {
        guard let gain, gain.isFinite, gain > 0, gain < 100 else { return nil }
        return gain
    }
```

In `Packages/AppCore/Sources/AppCore/Sound/Announcement.swift` ersetzen:

```swift
        case id, name, kind, text, voiceIdentifier, fileName, bundledResource, duration
```

durch:

```swift
        case id, name, kind, text, voiceIdentifier, fileName, bundledResource, duration, loudnessGain
```

In `Packages/AppCore/Sources/AppCore/Sound/Announcement.swift` ersetzen:

```swift
        duration = seconds.isFinite && seconds > 0 ? seconds : 0
```

durch:

```swift
        duration = seconds.isFinite && seconds > 0 ? seconds : 0
        loudnessGain = Self.validGain((try? c.decodeIfPresent(Double.self, forKey: .loudnessGain)) ?? nil)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: alle AppCore-Tests → `Executed 119 tests, with 0 failures`

- [ ] **Step 5: Measure on import and rendering, once in the background for older entries**

In `UniFiCameraPopup/Services/SoundStore.swift` ersetzen:

```swift
/// Einstellungen › Ton: announcements, microphone, talk mode, camera volume.
```

durch:

```swift
/// Einstellungen › Ton: announcements, microphone, the two volumes.
```

In `UniFiCameraPopup/Services/SoundStore.swift` ersetzen:

```swift
        removeUnreferencedFiles()
        if !Self.isSnapshot { seedGongIfNeeded() }
    }
```

durch:

```swift
        removeUnreferencedFiles()
        if !Self.isSnapshot {
            seedGongIfNeeded()
            measureMissingLoudness()
        }
    }

    // MARK: Loudness

    /// Measures the common-loudness factor of `buffer`, stores it on the entry and returns it.
    @discardableResult
    func storeLoudness(of buffer: AVAudioPCMBuffer, for id: UUID) -> Float {
        let gain = (try? AnnouncementAudio.loudnessGain(of: buffer)) ?? 1
        if var entry = settings.announcement(id: id), entry.loudnessGain == nil {
            entry.loudnessGain = Double(gain)
            settings.update(entry)
        }
        return gain
    }

    /// Entries from before Phase 5 (and the bundled recordings): measured once in the background.
    private func measureMissingLoudness() {
        let pending = settings.announcements.compactMap { entry -> (UUID, URL)? in
            guard entry.loudnessGain == nil, let url = audioURL(for: entry) else { return nil }
            return (entry.id, url)
        }
        guard !pending.isEmpty else { return }
        Task.detached(priority: .utility) {
            for (id, url) in pending {
                guard let buffer = try? AnnouncementAudio.load(url),
                      let gain = try? AnnouncementAudio.loudnessGain(of: buffer) else { continue }
                await MainActor.run {
                    guard var entry = SoundStore.shared.settings.announcement(id: id), entry.loudnessGain == nil else { return }
                    entry.loudnessGain = Double(gain)
                    SoundStore.shared.settings.update(entry)
                }
            }
        }
    }
```

In `UniFiCameraPopup/Services/SoundStore.swift` ersetzen:

```swift
        settings.add(Announcement(name: "Gong", kind: .file, fileName: name, duration: duration))
```

durch:

```swift
        let level = (try? AnnouncementAudio.load(target)).flatMap { try? AnnouncementAudio.loudnessGain(of: $0) }
        settings.add(Announcement(name: "Gong", kind: .file, fileName: name, duration: duration, loudnessGain: level.map(Double.init)))
```

In `UniFiCameraPopup/Services/SoundStore.swift` ersetzen:

```swift
            entry.voiceIdentifier = nil
            entry.fileName = nil
            entry.duration = original.duration
```

durch:

```swift
            entry.voiceIdentifier = nil
            entry.fileName = nil
            entry.duration = original.duration
            entry.loudnessGain = nil
```

In `UniFiCameraPopup/Services/SoundStore.swift` ersetzen:

```swift
            try AnnouncementAudio.write(buffer, to: target)
            entry.voiceIdentifier = voice
            entry.fileName = name
            entry.duration = Double(buffer.frameLength) / buffer.format.sampleRate
```

durch:

```swift
            try AnnouncementAudio.write(buffer, to: target)
            entry.voiceIdentifier = voice
            entry.fileName = name
            entry.duration = Double(buffer.frameLength) / buffer.format.sampleRate
            entry.loudnessGain = (try? AnnouncementAudio.loudnessGain(of: buffer)).map(Double.init)
```

In `UniFiCameraPopup/Services/SoundStore.swift` ersetzen:

```swift
        latest.fileName = entry.fileName
        latest.duration = entry.duration
```

durch:

```swift
        latest.fileName = entry.fileName
        latest.duration = entry.duration
        latest.loudnessGain = entry.loudnessGain
```

In `UniFiCameraPopup/Services/SoundStore.swift` ersetzen:

```swift
        var updated = entry
        updated.fileName = name
        updated.duration = duration
        return updated
```

durch:

```swift
        var updated = entry
        updated.fileName = name
        updated.duration = duration
        // Measured once here (a 5-minute MP3 decodes in well under a second).
        updated.loudnessGain = (try? AnnouncementAudio.load(target))
            .flatMap { try? AnnouncementAudio.loudnessGain(of: $0) }
            .map(Double.init)
        return updated
```

- [ ] **Step 6: Gains into the streamer**

In `UniFiCameraPopup/Services/TalkbackService.swift` ersetzen:

```swift
            let streamer = try makeStreamer(target: target, entryId: entryId)
            streamer.start()
            current = streamer
            try microphone.start(
```

durch:

```swift
            // The microphone is levelled to the announcements' loudness, then „Lautstärke Sprechen“.
            let streamer = try makeStreamer(
                target: target,
                entryId: entryId,
                gain: SoundStore.shared.settings.talkGain,
                automaticGain: true
            )
            streamer.start()
            current = streamer
            try microphone.start(
```

In `UniFiCameraPopup/Services/TalkbackService.swift` ersetzen:

```swift
        Task { await runAnnouncement(url: url, name: announcement.name, mapping: mapping, token: token) }
```

durch:

```swift
        Task { await runAnnouncement(url: url, announcement: announcement, mapping: mapping, token: token) }
```

In `UniFiCameraPopup/Services/TalkbackService.swift` ersetzen:

```swift
    private func runAnnouncement(url: URL, name: String, mapping: WebhookMapping, token: UUID) async {
        let entryId = mapping.entryId
        do {
            let loading = Task.detached { () throws -> PCMBox in PCMBox(buffer: try AnnouncementAudio.load(url)) }
            let target = try await openSession(for: mapping)
            let audio = try await loading.value.buffer
            guard run == token else { return }
            let streamer = try makeStreamer(target: target, entryId: entryId)
```

durch:

```swift
    private func runAnnouncement(url: URL, announcement: Announcement, mapping: WebhookMapping, token: UUID) async {
        let entryId = mapping.entryId
        let name = announcement.name
        do {
            let loading = Task.detached { () throws -> PCMBox in PCMBox(buffer: try AnnouncementAudio.load(url)) }
            let target = try await openSession(for: mapping)
            let audio = try await loading.value.buffer
            guard run == token else { return }
            // Common loudness (measured on import; older entries now), then „Lautstärke Ansagen“.
            let level = announcement.loudnessGain.map(Float.init)
                ?? SoundStore.shared.storeLoudness(of: audio, for: announcement.id)
            let streamer = try makeStreamer(
                target: target,
                entryId: entryId,
                gain: SoundStore.shared.settings.announcementGain * level,
                automaticGain: false
            )
```

In `UniFiCameraPopup/Services/TalkbackService.swift` ersetzen:

```swift
    private func makeStreamer(target: TalkbackTarget, entryId: UUID) throws -> TalkbackStreamer {
```

durch:

```swift
    private func makeStreamer(target: TalkbackTarget, entryId: UUID, gain: Float, automaticGain: Bool) throws -> TalkbackStreamer {
```

In `UniFiCameraPopup/Services/TalkbackService.swift` ersetzen:

```swift
            gain: SoundStore.shared.settings.gain,
```

durch:

```swift
            gain: gain,
            automaticGain: automaticGain,
```

- [ ] **Step 7: Two sliders**

In `UniFiCameraPopup/Views/Settings/SoundTab.swift` ersetzen:

```swift
            CardDivider()
            CardRow(title: "Lautstärke an der Kamera") {
                VolumeSlider(value: $store.settings.cameraVolume, label: "Lautstärke an der Kamera")
            }
```

durch:

```swift
            CardDivider()
            CardRow(title: "Lautstärke Sprechen") {
                VolumeSlider(value: $store.settings.talkVolume, label: "Lautstärke Sprechen")
            }
            CardDivider()
            CardRow(title: "Lautstärke Ansagen") {
                VolumeSlider(value: $store.settings.announcementVolume, label: "Lautstärke Ansagen")
            }
```

- [ ] **Step 8: Build and look**

Run: Build-Befehl → `** BUILD SUCCEEDED **`; `grep -rn "cameraVolume\|settings\.gain[^A-Za-z]" UniFiCameraPopup --include='*.swift' | grep -v "/.build/"` → keine Ausgabe; Renderer.
Expected: `S5-ton-*`: letzte Karte „Mikrofon“ · „Lautstärke Sprechen“ · „Lautstärke Ansagen“, beide Regler auf 2/3.

- [ ] **Step 9: Commit**

```bash
git add Packages/AppCore/Sources/AppCore/Sound/SoundSettings.swift Packages/AppCore/Sources/AppCore/Sound/Announcement.swift \
  Packages/AppCore/Tests/AppCoreTests/SoundSettingsTests.swift UniFiCameraPopup/Services/SoundStore.swift \
  UniFiCameraPopup/Services/TalkbackService.swift UniFiCameraPopup/Views/Settings/SoundTab.swift
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "feat(sound): same loudness for talking and announcements, separate volume sliders" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Nur die Stimme Anna (Spezifikation 7)

**Files:**
- Modify: `UniFiCameraPopup/Services/SoundStore.swift` (`previewBuffer`, `addText`, `applySpeech`)
- Modify: `UniFiCameraPopup/Views/Settings/SoundTab.swift` (Stimmenfeld, Hinweis, „Übernehmen“)

**Interfaces:**
- Consumes: `AnnouncementAudio.preferredVoice()`, `.candidate(_:)`, `VoiceChoice.fieldLabel(_:)`, `.hint(_:)` (Task 3).
- Produces: `SoundStore.previewBuffer(text: String) async throws -> AVAudioPCMBuffer`, `SoundStore.applySpeech(id: UUID, text: String) async throws` (ohne Stimmen-Parameter).

- [ ] **Step 1: The store always renders with Anna**

In `UniFiCameraPopup/Services/SoundStore.swift` ersetzen:

```swift
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
```

durch:

```swift
    /// Audio for "Anhören": the text as „Übernehmen“ would render it (Anna).
    func previewBuffer(text: String) async throws -> AVAudioPCMBuffer {
        try await AnnouncementAudio.render(text: text, voiceIdentifier: AnnouncementAudio.preferredVoice()?.identifier)
    }
```

In `UniFiCameraPopup/Services/SoundStore.swift` ersetzen:

```swift
    /// "Ansage aus Text …": new empty text entry with the best German macOS voice.
    @discardableResult
    func addText() -> Announcement {
        let entry = Announcement(
            name: Announcement.newName,
            kind: .speech,
            voiceIdentifier: AnnouncementAudio.voices().first?.identifier
        )
```

durch:

```swift
    /// "Ansage aus Text …": new empty text entry for Anna (else the best German voice).
    @discardableResult
    func addText() -> Announcement {
        let entry = Announcement(
            name: Announcement.newName,
            kind: .speech,
            voiceIdentifier: AnnouncementAudio.preferredVoice()?.identifier
        )
```

In `UniFiCameraPopup/Services/SoundStore.swift` ersetzen:

```swift
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
            entry.loudnessGain = nil
        } else {
            let voice = voiceIdentifier ?? AnnouncementAudio.voices().first?.identifier
            let buffer = try await AnnouncementAudio.render(text: trimmed, voiceIdentifier: voice)
            let name = "\(UUID().uuidString).caf"
            guard let target = resolve(name) else { throw TalkbackError.audioFile("Ablage") }
            try AnnouncementAudio.write(buffer, to: target)
            entry.voiceIdentifier = voice
            entry.fileName = name
            entry.duration = Double(buffer.frameLength) / buffer.format.sampleRate
            entry.loudnessGain = (try? AnnouncementAudio.loudnessGain(of: buffer)).map(Double.init)
        }
```

durch:

```swift
    /// "Übernehmen": the text becomes the entry's audio, always spoken by Anna (Phase 5; entries in
    /// another voice – the bundled recordings too – change to Anna on their next rendering).
    func applySpeech(id: UUID, text: String) async throws {
        guard let current = settings.announcement(id: id) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var entry = current
        entry.kind = .speech
        entry.text = trimmed
        let voice = AnnouncementAudio.preferredVoice()?.identifier
        let buffer = try await AnnouncementAudio.render(text: trimmed, voiceIdentifier: voice)
        let name = "\(UUID().uuidString).caf"
        guard let target = resolve(name) else { throw TalkbackError.audioFile("Ablage") }
        try AnnouncementAudio.write(buffer, to: target)
        entry.voiceIdentifier = voice
        entry.fileName = name
        entry.duration = Double(buffer.frameLength) / buffer.format.sampleRate
        entry.loudnessGain = (try? AnnouncementAudio.loudnessGain(of: buffer)).map(Double.init)
```

- [ ] **Step 2: Disabled voice field „Anna · macOS“**

In `UniFiCameraPopup/Views/Settings/SoundTab.swift` ersetzen:

```swift
    @State private var draftVoice: String?
```

durch:

```swift
    /// Anna (else the best German voice); read once per appearance of the tab.
    @State private var voice: VoiceChoice.Candidate? = AnnouncementAudio.preferredVoice().map(AnnouncementAudio.candidate)
```

In `UniFiCameraPopup/Views/Settings/SoundTab.swift` ersetzen:

```swift
            devices = MicrophoneCapture.inputDevices()
```

durch:

```swift
            devices = MicrophoneCapture.inputDevices()
            voice = AnnouncementAudio.preferredVoice().map(AnnouncementAudio.candidate)
```

In `UniFiCameraPopup/Views/Settings/SoundTab.swift` ersetzen:

```swift
        .onChange(of: draftText) { _ in
            // The bundled voice can only say the bundled wording.
            if draftVoice == nil, let selected, !SoundSettings.offersBundledVoice(for: selected, text: draftText) {
                draftVoice = AnnouncementAudio.voices().first?.identifier
            }
        }
    }
```

durch:

```swift
    }
```

In `UniFiCameraPopup/Views/Settings/SoundTab.swift` ersetzen:

```swift
                    PopUpField(selection: $draftVoice, options: voiceOptions(for: sound))
```

durch:

```swift
                    // Only Anna is offered (Phase 5): the field shows the voice and cannot be changed.
                    PopUpField(selection: .constant(0), options: [(value: 0, title: VoiceChoice.fieldLabel(voice))])
                        .disabled(true)
                        .accessibilityLabel("Stimme")
```

In `UniFiCameraPopup/Views/Settings/SoundTab.swift` ersetzen:

```swift
                Text("Wird auf diesem Mac erzeugt – ohne Internet, ohne Konto.")
                    .font(.system(size: 11))
                    .foregroundStyle(Tokens.muted.color)
```

durch:

```swift
                Text("Wird auf diesem Mac erzeugt – ohne Internet, ohne Konto.")
                    .font(.system(size: 11))
                    .foregroundStyle(Tokens.muted.color)
                if let hint = VoiceChoice.hint(voice) {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .systemOrange))
                        .fixedSize(horizontal: false, vertical: true)
                }
```

In `UniFiCameraPopup/Views/Settings/SoundTab.swift` ersetzen:

```swift
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
```

durch:

```swift
    /// New text, or an entry still in another voice (also the bundled recordings): render with Anna.
    private func canApply(_ sound: Announcement) -> Bool {
        guard !trimmedDraft.isEmpty, let voice else { return false }
        return sound.kind != .speech || trimmedDraft != sound.text || sound.voiceIdentifier != voice.identifier
    }
```

In `UniFiCameraPopup/Views/Settings/SoundTab.swift` ersetzen:

```swift
        draftText = sound?.text ?? ""
        draftVoice = sound?.voiceIdentifier
        if let sound, sound.kind == .speech, sound.voiceIdentifier == nil,
           !SoundSettings.offersBundledVoice(for: sound, text: sound.text) {
            draftVoice = AnnouncementAudio.voices().first?.identifier
        }
    }
```

durch:

```swift
        draftText = sound?.text ?? ""
    }
```

In `UniFiCameraPopup/Views/Settings/SoundTab.swift` ersetzen:

```swift
        let text = draftText
        let voice = draftVoice
        Task { @MainActor in
            do {
                try await store.applySpeech(id: sound.id, text: text, voiceIdentifier: voice)
```

durch:

```swift
        let text = draftText
        Task { @MainActor in
            do {
                try await store.applySpeech(id: sound.id, text: text)
```

In `UniFiCameraPopup/Views/Settings/SoundTab.swift` ersetzen:

```swift
        let text = trimmedDraft
        let voice = draftVoice
        Task { @MainActor in
            do {
                let buffer = try await store.previewBuffer(for: sound, text: text, voiceIdentifier: voice)
```

durch:

```swift
        let text = trimmedDraft
        Task { @MainActor in
            do {
                let buffer = try await store.previewBuffer(text: text)
```

- [ ] **Step 3: Build and look**

Run: Build-Befehl → `** BUILD SUCCEEDED **`; `grep -rn "draftVoice\|offersBundledVoice" UniFiCameraPopup --include='*.swift' | grep -v "/.build/"` → keine Ausgabe; Renderer.
Expected: `S5-ton-*`: Zeile „Stimme“ mit grauem, nicht bedienbarem Feld „Anna · macOS“ (ist Anna auf dem Mac nicht installiert: anderer Name und darunter die orange Zeile „Anna ist auf diesem Mac nicht installiert – …“). „Übernehmen“ ist bei der mitgelieferten Ansage aktiv (sie hat noch die Thorsten-Aufnahme).

- [ ] **Step 4: Commit**

```bash
git add UniFiCameraPopup/Services/SoundStore.swift UniFiCameraPopup/Views/Settings/SoundTab.swift
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "feat(sound): only the voice Anna, fallback to the best German voice with a hint" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Buttons können Töne abspielen (Spezifikation 11)

**Files:**
- Modify: `UniFiCameraPopup/Models/WebhookMapping.swift` (`CameraAction.soundId`, `isConfigured`)
- Modify: `UniFiCameraPopup/Services/SettingsStore.swift` (Erweiterung `Action.soundId`)
- Modify: `UniFiCameraPopup/Services/PopupController.swift` (`popupActions(of:)`)
- Modify: `UniFiCameraPopup/Views/PopupWindow.swift` (`run(_:from:)`)
- Modify: `UniFiCameraPopup/Views/Settings/ActionEditorSheet.swift` (Feld „Ton“)
- Modify: `UniFiCameraPopup/Views/Settings/CamerasTab.swift` (Liste, Sheet-Aufruf)
- Modify: `UniFiCameraPopup/Debug/SnapshotRenderer.swift` (Beispiel-Button mit Ton)

**Interfaces:**
- Consumes: `ActionAvailability` (Task 3), `DisplayText.actionTarget(url:soundName:)` (Task 3), `TalkbackService.play(_:entryId:)`, `.canTalk(_:)` (bestehend).
- Produces: `CameraAction.soundId: UUID?` (Haupt-Blob `soundId`, Erweiterung `Action.soundId`); `CameraAction.isConfigured` nach `ActionAvailability.isConfigured`; `PopupController.popupActions(of: WebhookMapping) -> [CameraAction]` (static); `ActionEditorSheet(action:isNew:sounds: [Announcement] = [], canPlaySound: Bool = false, onSave:onDelete:)`.

- [ ] **Step 1: Model**

In `UniFiCameraPopup/Models/WebhookMapping.swift` ersetzen:

```swift
/// A user-defined button shown in the popup that calls a webhook (e.g. "Tür öffnen").
```

durch:

```swift
/// A user-defined button shown in the popup: calls a webhook (e.g. "Tür öffnen"), plays an
/// announcement at the camera, or both at once (Phase 5).
```

In `UniFiCameraPopup/Models/WebhookMapping.swift` ersetzen:

```swift
    /// Ask before calling the webhook (e.g. opening a door).
    var confirmBeforeRun: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case url
        case method
        case bearerToken
        case icon
        case confirmBeforeRun
    }
```

durch:

```swift
    /// Ask before calling the webhook (e.g. opening a door).
    var confirmBeforeRun: Bool
    /// Announcement (Einstellungen › Ton) played at the popup's camera; nil = „Kein Ton“.
    var soundId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case url
        case method
        case bearerToken
        case icon
        case confirmBeforeRun
        case soundId
    }
```

In `UniFiCameraPopup/Models/WebhookMapping.swift` ersetzen:

```swift
        icon: ActionIcon = .bolt,
        confirmBeforeRun: Bool = false
    ) {
```

durch:

```swift
        icon: ActionIcon = .bolt,
        confirmBeforeRun: Bool = false,
        soundId: UUID? = nil
    ) {
```

In `UniFiCameraPopup/Models/WebhookMapping.swift` ersetzen:

```swift
        self.confirmBeforeRun = confirmBeforeRun
    }

    init(from decoder: Decoder) throws {
```

durch:

```swift
        self.confirmBeforeRun = confirmBeforeRun
        self.soundId = soundId
    }

    init(from decoder: Decoder) throws {
```

In `UniFiCameraPopup/Models/WebhookMapping.swift` ersetzen:

```swift
        confirmBeforeRun = (try? container.decodeIfPresent(Bool.self, forKey: .confirmBeforeRun)) ?? false
    }
```

durch:

```swift
        confirmBeforeRun = (try? container.decodeIfPresent(Bool.self, forKey: .confirmBeforeRun)) ?? false
        soundId = (try? container.decodeIfPresent(UUID.self, forKey: .soundId)) ?? nil
    }
```

In `UniFiCameraPopup/Models/WebhookMapping.swift` ersetzen:

```swift
        try container.encode(confirmBeforeRun, forKey: .confirmBeforeRun)

        let includeAll
```

durch:

```swift
        try container.encode(confirmBeforeRun, forKey: .confirmBeforeRun)
        try container.encodeIfPresent(soundId, forKey: .soundId)

        let includeAll
```

In `UniFiCameraPopup/Models/WebhookMapping.swift` ersetzen:

```swift
    /// Only fully configured actions are shown in the popup.
    var isConfigured: Bool {
        !trimmedTitle.isEmpty && requestURL != nil
    }
```

durch:

```swift
    /// Title plus webhook and/or sound; a typed address must be valid (see `ActionAvailability`).
    var isConfigured: Bool {
        ActionAvailability.isConfigured(title: title, address: url, hasValidURL: requestURL != nil, hasSound: soundId != nil)
    }
```

In `UniFiCameraPopup/Services/SettingsStore.swift` ersetzen:

```swift
                    if let confirm = a.confirmBeforeRun { action.confirmBeforeRun = confirm }
```

durch:

```swift
                    if let confirm = a.confirmBeforeRun { action.confirmBeforeRun = confirm }
                    // The extension entry is complete: no sound id there means „Kein Ton“.
                    action.soundId = a.soundId.flatMap(UUID.init(uuidString:))
```

In `UniFiCameraPopup/Services/SettingsStore.swift` ersetzen:

```swift
                actionValues[action.id.uuidString] = .init(
                    icon: action.icon.rawValue,
                    confirmBeforeRun: action.confirmBeforeRun
                )
```

durch:

```swift
                actionValues[action.id.uuidString] = .init(
                    icon: action.icon.rawValue,
                    confirmBeforeRun: action.confirmBeforeRun,
                    soundId: action.soundId?.uuidString
                )
```

- [ ] **Step 2: Popup – show and run**

In `UniFiCameraPopup/Services/PopupController.swift` ersetzen:

```swift
            actions: mapping.actions.filter(\.isConfigured),
```

durch:

```swift
            actions: Self.popupActions(of: mapping),
```

In `UniFiCameraPopup/Services/PopupController.swift` ersetzen:

```swift
    /// Event kind for the popup chip and the menu panel
```

durch:

```swift
    /// Buttons shown in this camera's popup: the webhook part always, a sound only on a camera
    /// with speaker and while the announcement exists.
    static func popupActions(of mapping: WebhookMapping) -> [CameraAction] {
        let canPlaySound = TalkbackService.shared.canTalk(mapping)
        return mapping.actions.filter { action in
            action.isConfigured && ActionAvailability.isShown(
                hasWebhook: action.requestURL != nil,
                hasSound: action.soundId.flatMap(SoundStore.shared.settings.announcement(id:)) != nil,
                canPlaySound: canPlaySound
            )
        }
    }

    /// Event kind for the popup chip and the menu panel
```

In `UniFiCameraPopup/Views/PopupWindow.swift` ersetzen:

```swift
    /// Calls the button's webhook; the popup stays open. Optional confirmation first.
    private func run(_ action: CameraAction, from button: CircleIconButton) {
```

durch:

```swift
    /// Calls the button's webhook and/or plays its sound at this camera, both at once; the popup
    /// stays open. Optional confirmation first.
    private func run(_ action: CameraAction, from button: CircleIconButton) {
```

In `UniFiCameraPopup/Views/PopupWindow.swift` ersetzen:

```swift
        button.showRunning()
        Task {
            do {
                try await CameraActionService.trigger(action)
                button.showResult(error: nil)
            } catch {
```

durch:

```swift
        // Sound only where this popup can talk (camera with speaker); errors show as the popup notice.
        if let entryId = overlay?.talk?.entryId,
           let announcement = action.soundId.flatMap(SoundStore.shared.settings.announcement(id:)) {
            TalkbackService.shared.play(announcement, entryId: entryId)
        }
        guard action.requestURL != nil else {
            button.showResult(error: nil)
            return
        }
        button.showRunning()
        Task {
            do {
                try await CameraActionService.trigger(action)
                button.showResult(error: nil)
            } catch {
```

- [ ] **Step 3: Sheet field „Ton“**

In `UniFiCameraPopup/Views/Settings/ActionEditorSheet.swift` ersetzen:

```swift
    private let onDelete: (() -> Void)?
    @State private var test: TestState = .idle
    @Environment(\.dismiss) private var dismiss

    init(action: CameraAction, isNew: Bool, onSave: @escaping (CameraAction) -> Void, onDelete: (() -> Void)?) {
        _draft = State(initialValue: action)
        originalTitle = isNew ? "" : action.trimmedTitle
        self.onSave = onSave
        self.onDelete = onDelete
    }
```

durch:

```swift
    private let onDelete: (() -> Void)?
    /// Announcements for „Ton“; the line only shows on a camera with speaker.
    private let sounds: [Announcement]
    private let canPlaySound: Bool
    @State private var test: TestState = .idle
    @Environment(\.dismiss) private var dismiss

    init(
        action: CameraAction,
        isNew: Bool,
        sounds: [Announcement] = [],
        canPlaySound: Bool = false,
        onSave: @escaping (CameraAction) -> Void,
        onDelete: (() -> Void)?
    ) {
        _draft = State(initialValue: action)
        originalTitle = isNew ? "" : action.trimmedTitle
        self.sounds = sounds
        self.canPlaySound = canPlaySound
        self.onSave = onSave
        self.onDelete = onDelete
    }
```

In `UniFiCameraPopup/Views/Settings/ActionEditorSheet.swift` ersetzen:

```swift
            FormLine(label: "Adresse") {
                TokenTextField(placeholder: "https://…", text: $draft.url,
                               fontSize: 12, vertical: 5, horizontal: 8, radius: 6)
            }
```

durch:

```swift
            FormLine(label: "Adresse") {
                TokenTextField(placeholder: draft.soundId == nil ? "https://…" : "https://… (optional)", text: $draft.url,
                               fontSize: 12, vertical: 5, horizontal: 8, radius: 6)
            }
```

In `UniFiCameraPopup/Views/Settings/ActionEditorSheet.swift` ersetzen:

```swift
            if let urlWarning {
                FormLine(label: "") {
```

durch:

```swift
            if canPlaySound {
                FormLine(label: "Ton") {
                    PopUpField(selection: $draft.soundId, options: soundOptions)
                }
                FormLine(label: "") {
                    Text("Spielt die Ansage an der Kamera ab. Mit Adresse laufen Ton und Webhook gleichzeitig.")
                        .font(.system(size: 11))
                        .foregroundStyle(Tokens.muted.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let urlWarning {
                FormLine(label: "") {
```

In `UniFiCameraPopup/Views/Settings/ActionEditorSheet.swift` ersetzen:

```swift
                    .disabled(!draft.isConfigured || test == .running)
```

durch:

```swift
                    .disabled(draft.requestURL == nil || test == .running)
```

In `UniFiCameraPopup/Views/Settings/ActionEditorSheet.swift` ersetzen:

```swift
    private var urlWarning: String? {
```

durch:

```swift
    /// „Kein Ton“ + the announcements; a deleted one stays listed as such until changed.
    private var soundOptions: [(value: UUID?, title: String)] {
        var options: [(value: UUID?, title: String)] = [(value: nil, title: "Kein Ton")]
        options += sounds.map { (value: Optional($0.id), title: $0.name) }
        if let id = draft.soundId, !sounds.contains(where: { $0.id == id }) {
            options.append((value: id, title: "Gelöschte Ansage"))
        }
        return options
    }

    private var urlWarning: String? {
```

(„Sichern“ bleibt `.disabled(!draft.isConfigured)` – das prüft jetzt „Adresse nur Pflicht ohne Ton, eine eingetragene Adresse muss gültig sein“.)

- [ ] **Step 4: Camera list and sheet call**

In `UniFiCameraPopup/Views/Settings/CamerasTab.swift` ersetzen:

```swift
                        Text(action.method.rawValue)
                            .font(.system(size: 10, weight: .bold))
```

durch:

```swift
                        Text(action.requestURL == nil && action.soundId != nil ? "TON" : action.method.rawValue)
                            .font(.system(size: 10, weight: .bold))
```

In `UniFiCameraPopup/Views/Settings/CamerasTab.swift` ersetzen:

```swift
                        Text(DisplayText.actionAddress(action.url))
                            .foregroundStyle(Tokens.muted.color)
```

durch:

```swift
                        Text(DisplayText.actionTarget(url: action.url, soundName: soundName(action.soundId)))
                            .foregroundStyle(Tokens.muted.color)
```

In `UniFiCameraPopup/Views/Settings/CamerasTab.swift` ersetzen:

```swift
            ActionEditorSheet(
                action: context.action,
                isNew: context.isNew,
                onSave: save,
```

durch:

```swift
            ActionEditorSheet(
                action: context.action,
                isNew: context.isNew,
                sounds: sounds.settings.announcements,
                canPlaySound: TalkbackService.shared.canTalk(mapping),
                onSave: save,
```

In `UniFiCameraPopup/Views/Settings/CamerasTab.swift` ersetzen:

```swift
    @ObservedObject private var events = EventLog.shared
```

durch:

```swift
    @ObservedObject private var events = EventLog.shared
    @ObservedObject private var sounds = SoundStore.shared
```

In `UniFiCameraPopup/Views/Settings/CamerasTab.swift` ersetzen:

```swift
    private func save(_ action: CameraAction) {
```

durch:

```swift
    private func soundName(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return sounds.settings.announcement(id: id)?.name ?? "Gelöschte Ansage"
    }

    private func save(_ action: CameraAction) {
```

- [ ] **Step 5: Snapshot sample**

In `UniFiCameraPopup/Debug/SnapshotRenderer.swift` ersetzen:

```swift
            CameraAction(id: UUID(), title: "Flurlicht", url: "https://home.example/light", method: .get,
                         bearerToken: "", icon: .bulb, confirmBeforeRun: false),
        ]
```

durch:

```swift
            CameraAction(id: UUID(), title: "Flurlicht", url: "https://home.example/light", method: .get,
                         bearerToken: "", icon: .bulb, confirmBeforeRun: false),
            // Phase 5: a button that only plays an announcement.
            CameraAction(id: UUID(), title: "Gleich da", url: "", method: .post,
                         bearerToken: "", icon: .house, confirmBeforeRun: false, soundId: SoundSettings.bundledBinGleichDa.id),
        ]
```

Bild 8 bleibt vorlagengetreu bei zwei Buttons.

In `UniFiCameraPopup/Debug/SnapshotRenderer.swift` ersetzen:

```swift
                actions: sample.door.actions,
                overlay: PopupOverlayContent(
                    chipText: nil, cameraName: "Haustür",
                    muteOptions: sample.settings.muteOptions, onMute: { _ in }
                ),
```

durch:

```swift
                actions: Array(sample.door.actions.prefix(2)),
                overlay: PopupOverlayContent(
                    chipText: nil, cameraName: "Haustür",
                    muteOptions: sample.settings.muteOptions, onMute: { _ in }
                ),
```

In `UniFiCameraPopup/Debug/SnapshotRenderer.swift` ersetzen:

```swift
                    actions: sample.door.actions,
                    overlay: PopupOverlayContent(
                        chipText: "Klingel · Haustür · 10:41", cameraName: "Haustür",
                        muteOptions: sample.settings.muteOptions, onMute: { _ in }
                    ),
```

durch:

```swift
                    actions: Array(sample.door.actions.prefix(2)),
                    overlay: PopupOverlayContent(
                        chipText: "Klingel · Haustür · 10:41", cameraName: "Haustür",
                        muteOptions: sample.settings.muteOptions, onMute: { _ in }
                    ),
```

- [ ] **Step 6: Build and look**

Run: Build-Befehl → `** BUILD SUCCEEDED **`; Renderer.
Expected: `S2-kameras-*`: dritte Zeile „Gleich da · TON · Ton „Bin gleich da“ · Ändern“, darunter „Höchstens drei Buttons.“. `9-popup-sprechen-ruhe-*`: Leiste mit Ton abspielen · Sprechen · Tür · Lampe · Haus. `S4-button-sheet-*` unverändert (Renderer ruft das Sheet ohne Lautsprecher auf; die Zeile „Ton“ erscheint nur bei `canPlaySound`).

- [ ] **Step 7: Commit**

```bash
git add UniFiCameraPopup/Models/WebhookMapping.swift UniFiCameraPopup/Services/SettingsStore.swift \
  UniFiCameraPopup/Services/PopupController.swift UniFiCameraPopup/Views/PopupWindow.swift \
  UniFiCameraPopup/Views/Settings/ActionEditorSheet.swift UniFiCameraPopup/Views/Settings/CamerasTab.swift \
  UniFiCameraPopup/Debug/SnapshotRenderer.swift
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "feat(buttons): popup buttons can play an announcement, webhook optional" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Neue Kategorie „Ereignisse“ (Spezifikation 12)

**Files:**
- Create: `UniFiCameraPopup/Services/EventRuleService.swift`
- Create: `UniFiCameraPopup/Views/Settings/EventRulesSection.swift`
- Modify: `UniFiCameraPopup/scripts/pbxproj-add-files.py` (`--prefix`, Gruppen `Services`, `Views/Settings`), `UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj` (per Skript)
- Modify: `UniFiCameraPopup/Services/KeychainStore.swift` (`ruleTokenService`)
- Modify: `UniFiCameraPopup/Models/WebhookMapping.swift` (`eventRules`)
- Modify: `UniFiCameraPopup/Services/SettingsStore.swift` (Laden, Erweiterung, Schlüsselbund, Import)
- Modify: `UniFiCameraPopup/Services/ProtectEventService.swift` (`handle`)
- Modify: `UniFiCameraPopup/Services/TalkbackService.swift` (`playAutomatically`)
- Modify: `UniFiCameraPopup/Views/Settings/ActionEditorSheet.swift` (Testergebnis teilen)
- Modify: `UniFiCameraPopup/Views/Settings/CamerasTab.swift` (Abschnitt einbinden)
- Modify: `UniFiCameraPopup/Debug/SnapshotRenderer.swift` (Beispielregeln, Bild `S4-regel-sheet`)

**Interfaces:**
- Consumes: `EventRule`, `EventRuleList`, `EventRuleWebhook`, `EventRuleMatcher`, `EventRuleDebouncer`, `EventRuleText` (Task 3); `CameraActionService.trigger(_:)` (Phase 4, Routing zu Hause/unterwegs); `TalkbackService.canTalk(_:)`, `.play(_:entryId:)`; `EventLog.shared.record(mapping:kindLabel:date:)`; `ProtectTrigger` (ProtectKit).
- Produces: `WebhookMapping.eventRules: [EventRule]` (Haupt-Blob `eventRules` ohne Token, Erweiterung `Mapping.eventRules`); `KeychainStore.ruleTokenService`; `EventRuleService.shared.handle(_: ProtectTrigger)`, `EventRuleService.request(for: EventRule) -> CameraAction` (static); `TalkbackService.playAutomatically(_:entryId:) -> Bool`; `enum WebhookTestState`, `struct WebhookTestResult: View` (aus `ActionEditorSheet` herausgezogen); `EventRulesSection(mapping: Binding<WebhookMapping>, camera: ProtectCamera?)`, `EventRuleEditorSheet(rule:isNew:kinds:sounds:canPlaySound:onSave:onDelete:)`.

- [ ] **Step 1: Model, keychain service**

In `UniFiCameraPopup/Services/KeychainStore.swift` ersetzen:

```swift
    static let protectAPIKeyService = "com.snackbits.UniFiCameraPopup.protect-api-key"
```

durch:

```swift
    static let protectAPIKeyService = "com.snackbits.UniFiCameraPopup.protect-api-key"
    /// Bearer tokens of event rules (Kameras › Ereignisse); account = rule id. Never exported.
    static let ruleTokenService = "com.snackbits.UniFiCameraPopup.rule-token"
```

In `UniFiCameraPopup/Models/WebhookMapping.swift` ersetzen:

```swift
    /// „Größe“ (Phase 5): empty = automatic
```

durch:

```swift
    /// Kameras › Ereignisse (Phase 5). Tokens only in memory/keychain, never encoded.
    var eventRules: [EventRule]
    /// „Größe“ (Phase 5): empty = automatic
```

In `UniFiCameraPopup/Models/WebhookMapping.swift` ersetzen:

```swift
        case sizeOverride
        case widthOverride
```

durch:

```swift
        case sizeOverride
        case eventRules
        case widthOverride
```

In `UniFiCameraPopup/Models/WebhookMapping.swift` ersetzen:

```swift
        showNameAndTime: Bool = false,
        sizeOverride: PopupSizeOverride = .automatic
    ) {
```

durch:

```swift
        showNameAndTime: Bool = false,
        sizeOverride: PopupSizeOverride = .automatic,
        eventRules: [EventRule] = []
    ) {
```

In `UniFiCameraPopup/Models/WebhookMapping.swift` ersetzen:

```swift
        self.sizeOverride = sizeOverride
    }
```

durch:

```swift
        self.sizeOverride = sizeOverride
        self.eventRules = eventRules
    }
```

In `UniFiCameraPopup/Models/WebhookMapping.swift` ersetzen:

```swift
            ?? .migrated(width: width, height: height)
    }
```

durch:

```swift
            ?? .migrated(width: width, height: height)
        eventRules = ((try? container.decodeIfPresent(EventRuleList.self, forKey: .eventRules)) ?? nil)?.rules ?? []
    }
```

In `UniFiCameraPopup/Models/WebhookMapping.swift` ersetzen:

```swift
        try container.encode(sizeOverride, forKey: .sizeOverride)
    }
```

durch:

```swift
        try container.encode(sizeOverride, forKey: .sizeOverride)
        // Part of the configuration export, without tokens (EventRule never encodes them).
        try container.encode(EventRuleList(eventRules), forKey: .eventRules)
    }
```

- [ ] **Step 2: SettingsStore – extension, tokens in the keychain, import keeps tokens**

In `UniFiCameraPopup/Services/SettingsStore.swift` ersetzen:

```swift
            if let ext {
                mappings = Self.overlay(ext, onto: mappings)
            }

            // Decode succeeded: rewrite the (possibly migrated/normalized) payload.
```

durch:

```swift
            if let ext {
                mappings = Self.overlay(ext, onto: mappings)
            }
            // After the overlay: the extension may carry rules the main blob lost.
            let rules = Self.loadRuleTokens(into: mappings)
            mappings = rules.mappings
            keychainRuleTokens = rules.fromKeychain

            // Decode succeeded: rewrite the (possibly migrated/normalized) payload.
```

In `UniFiCameraPopup/Services/SettingsStore.swift` ersetzen:

```swift
                if let size = m.size { mapping.sizeOverride = size }
```

durch:

```swift
                if let size = m.size { mapping.sizeOverride = size }
                if let rules = m.eventRules { mapping.eventRules = rules.rules }
```

In `UniFiCameraPopup/Services/SettingsStore.swift` ersetzen:

```swift
                showNameAndTime: mapping.showNameAndTime,
                size: mapping.sizeOverride
            )
```

durch:

```swift
                showNameAndTime: mapping.showNameAndTime,
                size: mapping.sizeOverride,
                eventRules: EventRuleList(mapping.eventRules)
            )
```

In `UniFiCameraPopup/Services/SettingsStore.swift` ersetzen:

```swift
    private func persist() {
        let plaintextTokenIDs = syncActionTokensToKeychain()
```

durch:

```swift
    private func persist() {
        syncRuleTokensToKeychain()
        let plaintextTokenIDs = syncActionTokensToKeychain()
```

In `UniFiCameraPopup/Services/SettingsStore.swift` ersetzen:

```swift
        mappings = saved.mappings
```

durch:

```swift
        // Exports carry no rule tokens: keep the ones this Mac already has for the same rules.
        let rules = Self.loadRuleTokens(into: saved.mappings)
        keychainRuleTokens.merge(rules.fromKeychain) { _, new in new }
        mappings = rules.mappings
```

In `UniFiCameraPopup/Services/SettingsStore.swift` ersetzen:

```swift
    // MARK: - Configuration export / import
```

durch:

```swift
    // MARK: - Event rule tokens (keychain only)

    /// Rule tokens as last written to the keychain.
    private var keychainRuleTokens: [UUID: String] = [:]

    /// Fills in each rule's bearer token from the keychain.
    private static func loadRuleTokens(
        into mappings: [WebhookMapping]
    ) -> (mappings: [WebhookMapping], fromKeychain: [UUID: String]) {
        var found: [UUID: String] = [:]
        let filled = mappings.map { mapping in
            var updated = mapping
            updated.eventRules = mapping.eventRules.map { rule in
                var rule = rule
                if rule.bearerToken.isEmpty,
                   let token = KeychainStore.string(service: KeychainStore.ruleTokenService, account: rule.id.uuidString) {
                    rule.bearerToken = token
                    found[rule.id] = token
                }
                return rule
            }
            return updated
        }
        return (filled, found)
    }

    /// Writes changed rule tokens, removes those of deleted rules or cleared fields. A token the
    /// keychain refuses is only kept in memory (rules never carry tokens in plain text).
    private func syncRuleTokensToKeychain() {
        var current: [UUID: String] = [:]
        for rule in mappings.flatMap(\.eventRules) where !rule.bearerToken.isEmpty {
            current[rule.id] = rule.bearerToken
        }
        for (id, token) in current where keychainRuleTokens[id] != token {
            if KeychainStore.set(token, service: KeychainStore.ruleTokenService, account: id.uuidString) {
                keychainRuleTokens[id] = token
            } else {
                NSLog("SettingsStore: event rule token could not be stored in the keychain")
            }
        }
        for id in keychainRuleTokens.keys where current[id] == nil {
            KeychainStore.delete(service: KeychainStore.ruleTokenService, account: id.uuidString)
            keychainRuleTokens[id] = nil
        }
    }

    // MARK: - Configuration export / import
```

- [ ] **Step 3: Run the rules on every event**

In `UniFiCameraPopup/Services/TalkbackService.swift` ersetzen:

```swift
    func stopPlayback() {
```

durch:

```swift
    /// Event rules: plays only while nothing else is sent – never cuts off talking or another
    /// announcement. false = skipped.
    @discardableResult
    func playAutomatically(_ announcement: Announcement, entryId: UUID) -> Bool {
        guard activity == nil else { return false }
        play(announcement, entryId: entryId)
        return activity?.entryId == entryId
    }

    func stopPlayback() {
```

Datei `UniFiCameraPopup/Services/EventRuleService.swift` neu anlegen:

```swift
import AppCore
import Foundation
import ProtectKit

/// Kameras › Ereignisse: runs the rules of each Protect event – independent of popups, mutes and
/// Focus (those only concern popups on this Mac). Same paths as the popup buttons: the webhook via
/// `CameraActionService` (home/away routing of Phase 4, no redirects), the sound via
/// `TalkbackService`. Every run lands in the event log (menu panel).
@MainActor
final class EventRuleService {
    static let shared = EventRuleService()

    private let settings = SettingsStore.shared
    private var debouncer = EventRuleDebouncer()

    private init() {}

    /// Called for every new event (already de-duplicated by event id).
    func handle(_ trigger: ProtectTrigger) {
        let kinds = Set(trigger.kinds.map(\.rawValue))
        let now = Date()
        for mapping in settings.mappings(forProtectCamera: trigger.cameraId) {
            let rules = EventRuleMatcher.matching(
                mapping.eventRules,
                kinds: kinds,
                canPlaySound: TalkbackService.shared.canTalk(mapping),
                soundExists: { SoundStore.shared.settings.announcement(id: $0) != nil }
            )
            for rule in rules where debouncer.shouldRun(entry: mapping.entryId.uuidString, rule: rule.id, at: now) {
                schedule(ruleId: rule.id, entryId: mapping.entryId, delay: rule.delaySeconds)
            }
        }
    }

    private func schedule(ruleId: UUID, entryId: UUID, delay: Int) {
        Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            }
            await run(ruleId: ruleId, entryId: entryId)
        }
    }

    /// Reads the rule again: edits during the delay apply, a removed rule or camera does nothing.
    private func run(ruleId: UUID, entryId: UUID) async {
        guard let mapping = settings.mapping(forEntry: entryId),
              let rule = mapping.eventRules.first(where: { $0.id == ruleId }) else {
            NSLog("Event rule \(ruleId) was removed before it ran")
            return
        }
        let kindLabel = TriggerKind(rawValue: rule.kind)?.label ?? rule.kind
        // Sound and webhook at the same time: the sound starts first, the webhook does not wait for it.
        let sound = startSound(rule, mapping: mapping)
        var failed = sound?.played == false
        if rule.hasWebhook {
            do {
                try await CameraActionService.trigger(Self.request(for: rule))
            } catch {
                failed = true
                NSLog("Event rule webhook failed: \(error.localizedDescription)")
            }
        }
        EventLog.shared.record(
            mapping: mapping,
            kindLabel: EventRuleText.logTitle(
                kindLabel: kindLabel,
                webhook: rule.hasWebhook,
                soundName: sound?.name,
                failed: failed
            ),
            date: Date()
        )
    }

    /// nil = the rule plays nothing here; `played` false = skipped (the camera is busy talking).
    private func startSound(_ rule: EventRule, mapping: WebhookMapping) -> (name: String, played: Bool)? {
        guard let id = rule.soundId, TalkbackService.shared.canTalk(mapping),
              let announcement = SoundStore.shared.settings.announcement(id: id) else { return nil }
        let played = TalkbackService.shared.playAutomatically(announcement, entryId: mapping.entryId)
        if !played {
            TalkbackLog.write("Regel: Ton „\(announcement.name)“ übersprungen – \(mapping.label) sendet gerade")
        }
        return (announcement.name, played)
    }

    /// The rule's webhook as a transient popup button: same request, same routing.
    static func request(for rule: EventRule) -> CameraAction {
        CameraAction(
            title: "Regel",
            url: rule.webhook?.url ?? "",
            method: CameraAction.Method(rawValue: rule.webhook?.method ?? "POST") ?? .post,
            bearerToken: rule.bearerToken
        )
    }
}
```

In `UniFiCameraPopup/Services/ProtectEventService.swift` ersetzen:

```swift
        guard let trigger = EventMessage.parse(data), dedup.isNew(trigger.eventId) else { return }
```

durch:

```swift
        guard let trigger = EventMessage.parse(data), dedup.isNew(trigger.eventId) else { return }
        // Kameras › Ereignisse: independent of popups, mutes and Focus.
        EventRuleService.shared.handle(trigger)
```

- [ ] **Step 4: Share the webhook test result between both sheets**

In `UniFiCameraPopup/Views/Settings/ActionEditorSheet.swift` ersetzen:

```swift
/// Edits one popup button (template "Button bearbeiten (Sheet)").
struct ActionEditorSheet: View {
    private enum TestState: Equatable {
        case idle
        case running
        case succeeded(Int)
        case failed(String)
    }

    @State private var draft: CameraAction
```

durch:

```swift
/// „Testen“ of a webhook (button and event rule sheets).
enum WebhookTestState: Equatable {
    case idle
    case running
    case succeeded(Int)
    case failed(String)
}

/// Result line under a webhook test (template S4 item 4); nothing while idle or running.
struct WebhookTestResult: View {
    let state: WebhookTestState

    var body: some View {
        switch state {
        case .idle, .running:
            EmptyView()
        case .succeeded(let status):
            box(icon: true, text: "Test erfolgreich · HTTP \(status)", foreground: Tokens.ok.color, background: Tokens.okBg.color)
        case .failed(let message):
            box(icon: false, text: message, foreground: Color(nsColor: .systemOrange),
                background: Color(nsColor: .systemOrange).opacity(0.12))
        }
    }

    private func box(icon: Bool, text: String, foreground: Color, background: Color) -> some View {
        HStack(spacing: 6) {
            if icon { TemplateIcon.check.image(size: 13) }
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
        .foregroundStyle(foreground)
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7).fill(background))
    }
}

/// Edits one popup button (template "Button bearbeiten (Sheet)").
struct ActionEditorSheet: View {
    @State private var draft: CameraAction
```

In `UniFiCameraPopup/Views/Settings/ActionEditorSheet.swift` ersetzen:

```swift
    @State private var test: TestState = .idle
```

durch:

```swift
    @State private var test: WebhookTestState = .idle
```

In `UniFiCameraPopup/Views/Settings/ActionEditorSheet.swift` ersetzen:

```swift
            testResult
            HStack(spacing: 8) {
```

durch:

```swift
            WebhookTestResult(state: test)
            HStack(spacing: 8) {
```

In `UniFiCameraPopup/Views/Settings/ActionEditorSheet.swift` ersetzen:

```swift
    @ViewBuilder
    private var testResult: some View {
        switch test {
        case .idle, .running:
            EmptyView()
        case .succeeded(let status):
            resultBox(icon: true, text: "Test erfolgreich · HTTP \(status)", foreground: Tokens.ok.color, background: Tokens.okBg.color)
        case .failed(let message):
            resultBox(icon: false, text: message, foreground: Color(nsColor: .systemOrange),
                      background: Color(nsColor: .systemOrange).opacity(0.12))
        }
    }

    private func resultBox(icon: Bool, text: String, foreground: Color, background: Color) -> some View {
        HStack(spacing: 6) {
            if icon { TemplateIcon.check.image(size: 13) }
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
        .foregroundStyle(foreground)
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7).fill(background))
    }

    /// „Kein Ton“ + the announcements; a deleted one stays listed as such until changed.
```

durch:

```swift
    /// „Kein Ton“ + the announcements; a deleted one stays listed as such until changed.
```

- [ ] **Step 5: Settings section „Ereignisse“ and the rule sheet**

Datei `UniFiCameraPopup/Views/Settings/EventRulesSection.swift` neu anlegen:

```swift
import AppCore
import ProtectKit
import SwiftUI

struct EventRuleEditorContext: Identifiable {
    let id = UUID()
    let rule: EventRule
    let isNew: Bool
}

/// Kameras › „Ereignisse“ (Phase 5, not in the template): built like „Buttons im Popup“.
/// Rows: event 600 (90 wide) · actions `muted`, truncated · link „Ändern“.
struct EventRulesSection: View {
    @Binding var mapping: WebhookMapping
    let camera: ProtectCamera?
    @ObservedObject private var sounds = SoundStore.shared
    @State private var editor: EventRuleEditorContext?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Ereignisse")
            Card(radius: 9) {
                ForEach(mapping.eventRules) { rule in
                    HStack(spacing: 8) {
                        Text(Self.label(rule.kind))
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .frame(width: 90, alignment: .leading)
                        Text(summary(rule))
                            .foregroundStyle(Tokens.muted.color)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Ändern") { editor = EventRuleEditorContext(rule: rule, isNew: false) }
                            .buttonStyle(LinkButtonStyle())
                    }
                    .font(.system(size: 12))
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    CardDivider()
                }
                if mapping.eventRules.count < EventRule.maxPerCamera {
                    Button("Regel hinzufügen …") {
                        editor = EventRuleEditorContext(rule: EventRule(kind: kinds.first?.rawValue ?? "ring"), isNew: true)
                    }
                    .buttonStyle(LinkButtonStyle())
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                } else {
                    Text("Höchstens \(EventRule.maxPerCamera) Regeln.")
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.muted.color)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 12)
                }
            }
            Text("Regeln laufen auch ohne Popup und während einer Stummschaltung.")
                .font(.system(size: 11))
                .foregroundStyle(Tokens.muted.color)
        }
        .sheet(item: $editor) { context in
            EventRuleEditorSheet(
                rule: context.rule,
                isNew: context.isNew,
                kinds: kinds,
                sounds: sounds.settings.announcements,
                canPlaySound: TalkbackService.shared.canTalk(mapping),
                onSave: save,
                onDelete: context.isNew ? nil : { delete(context.rule.id) }
            )
        }
    }

    /// What the camera can report, in chip order; without camera data the common ones.
    private var kinds: [TriggerKind] {
        guard let camera else { return [.ring, .person, .vehicle, .animal, .package, .motion] }
        return TriggerKind.displayOrder.filter { camera.supportedTriggers.contains($0) }
    }

    static func label(_ kind: String) -> String {
        TriggerKind(rawValue: kind)?.label ?? kind
    }

    private func summary(_ rule: EventRule) -> String {
        let soundName = rule.soundId.map { id in sounds.settings.announcement(id: id)?.name ?? "Gelöschte Ansage" }
        return EventRuleText.actionSummary(
            webhookAddress: rule.webhook.map { DisplayText.actionAddress($0.url) },
            soundName: soundName,
            delaySeconds: rule.delaySeconds
        )
    }

    private func save(_ rule: EventRule) {
        if let index = mapping.eventRules.firstIndex(where: { $0.id == rule.id }) {
            mapping.eventRules[index] = rule
        } else if mapping.eventRules.count < EventRule.maxPerCamera {
            mapping.eventRules.append(rule)
        }
    }

    private func delete(_ id: UUID) {
        mapping.eventRules.removeAll { $0.id == id }
    }
}

/// Sheet „Regel“: same frame as „Button bearbeiten“ (480 wide, padding 18/20, gap 11, 96 label column).
struct EventRuleEditorSheet: View {
    @State private var draft: EventRule
    @State private var address: String
    @State private var method: CameraAction.Method
    @State private var delayText: String
    @State private var test: WebhookTestState = .idle
    private let isNew: Bool
    private let kinds: [TriggerKind]
    private let sounds: [Announcement]
    private let canPlaySound: Bool
    private let onSave: (EventRule) -> Void
    private let onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(
        rule: EventRule,
        isNew: Bool,
        kinds: [TriggerKind],
        sounds: [Announcement],
        canPlaySound: Bool,
        onSave: @escaping (EventRule) -> Void,
        onDelete: (() -> Void)?
    ) {
        _draft = State(initialValue: rule)
        _address = State(initialValue: rule.webhook?.url ?? "")
        _method = State(initialValue: CameraAction.Method(rawValue: rule.webhook?.method ?? "POST") ?? .post)
        _delayText = State(initialValue: rule.delaySeconds > 0 ? String(rule.delaySeconds) : "")
        self.isNew = isNew
        self.kinds = kinds
        self.sounds = sounds
        self.canPlaySound = canPlaySound
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(isNew ? "Neue Regel" : "Regel „\(EventRulesSection.label(draft.kind))“")
                .font(.system(size: 15, weight: .bold))
            FormLine(label: "Ereignis") {
                PopUpField(selection: $draft.kind, options: kindOptions)
            }
            FormLine(label: "Methode") {
                TokenSegmented(
                    selection: $method,
                    options: CameraAction.Method.allCases.map { (value: $0, title: $0.rawValue) },
                    width: 120
                )
            }
            FormLine(label: "Adresse") {
                TokenTextField(placeholder: draft.soundId == nil ? "https://…" : "https://… (optional)", text: $address,
                               fontSize: 12, vertical: 5, horizontal: 8, radius: 6)
            }
            FormLine(label: "Token") {
                TokenTextField(placeholder: "", text: $draft.bearerToken,
                               fontSize: 12, vertical: 5, horizontal: 8, radius: 6, secure: true)
            }
            FormLine(label: "") {
                Text("Bearer-Token, liegt im Schlüsselbund. Optional.")
                    .font(.system(size: 11))
                    .foregroundStyle(Tokens.muted.color)
            }
            if canPlaySound {
                FormLine(label: "Ton") {
                    PopUpField(selection: $draft.soundId, options: soundOptions)
                }
            }
            FormLine(label: "Verzögerung") {
                HStack(spacing: 6) {
                    TokenTextField(placeholder: "0", text: $delayText,
                                   fontSize: 12, vertical: 5, horizontal: 8, radius: 6)
                        .frame(width: 64)
                    Text("Sekunden (0–600)")
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.muted.color)
                }
            }
            if let urlWarning {
                FormLine(label: "") {
                    Text(urlWarning).font(.system(size: 11)).foregroundStyle(Color(nsColor: .systemOrange))
                }
            }
            WebhookTestResult(state: test)
            HStack(spacing: 8) {
                Button(test == .running ? "Teste …" : "Testen", action: runTest)
                    .buttonStyle(FieldButtonStyle(fontSize: 13, vertical: 5, horizontal: 12))
                    .disabled(!result.hasWebhook || test == .running)
                if let onDelete {
                    Button("Entfernen") {
                        onDelete()
                        dismiss()
                    }
                    .buttonStyle(LinkButtonStyle(color: Tokens.muted))
                }
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .buttonStyle(FieldButtonStyle(fontSize: 13, vertical: 5, horizontal: 12))
                    .keyboardShortcut(.cancelAction)
                Button("Sichern") {
                    onSave(result)
                    dismiss()
                }
                .buttonStyle(AccentButtonStyle(fontSize: 13, vertical: 5, horizontal: 14))
                .keyboardShortcut(.defaultAction)
                .disabled(!result.isConfigured)
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(width: 480)
        .background(Tokens.win.color)
        .foregroundStyle(Tokens.fg.color)
        .font(.system(size: 13))
    }

    /// The edited rule: empty address = no webhook, delay from the field (0…600).
    private var result: EventRule {
        var rule = draft
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        rule.webhook = trimmed.isEmpty ? nil : EventRuleWebhook(method: method.rawValue, url: trimmed)
        rule.delaySeconds = EventRule.delay(fromText: delayText)
        rule.bearerToken = draft.bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return rule
    }

    private var kindOptions: [(value: String, title: String)] {
        var options = kinds.map { (value: $0.rawValue, title: $0.label) }
        if !options.contains(where: { $0.value == draft.kind }) {
            options.append((value: draft.kind, title: EventRulesSection.label(draft.kind)))
        }
        return options
    }

    private var soundOptions: [(value: UUID?, title: String)] {
        var options: [(value: UUID?, title: String)] = [(value: nil, title: "Kein Ton")]
        options += sounds.map { (value: Optional($0.id), title: $0.name) }
        if let id = draft.soundId, !sounds.contains(where: { $0.id == id }) {
            options.append((value: id, title: "Gelöschte Ansage"))
        }
        return options
    }

    private var urlWarning: String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, result.webhook?.requestURL == nil else { return nil }
        return "Bitte eine gültige http:// oder https:// Adresse eintragen."
    }

    /// Calls the webhook once, now (no delay, no sound).
    private func runTest() {
        let request = EventRuleService.request(for: result)
        test = .running
        Task {
            do {
                test = .succeeded(try await CameraActionService.trigger(request))
            } catch {
                test = .failed(error.localizedDescription)
            }
        }
    }
}
```

In `UniFiCameraPopup/Views/Settings/CamerasTab.swift` ersetzen:

```swift
                        optionsCard
                        buttonsSection
```

durch:

```swift
                        optionsCard
                        buttonsSection
                        if mapping.protectCameraId != nil {
                            EventRulesSection(mapping: $mapping, camera: camera)
                        }
```

- [ ] **Step 6: Add the two files to the project**

`pbxproj-add-files.py` kann bisher nur Phase-4-IDs (`D4…`) und Tunnel-Gruppen.

In `UniFiCameraPopup/scripts/pbxproj-add-files.py` ersetzen:

```python
usage: scripts/pbxproj-add-files.py <group> <first-id> <file> [<file> ...]

  group     Services/Tunnel | Views/Tunnel | Source (top-level group, for resources)
  first-id  two hex digits; file n gets PBXBuildFile D41…<id+n> and PBXFileReference D42…<id+n>
```

durch:

```python
usage: scripts/pbxproj-add-files.py [--prefix XY] <group> <first-id> <file> [<file> ...]

  --prefix  two characters for new ids (default D4 = Phase 4; Phase 5 uses E5)
  group     Services | Views/Settings | Services/Tunnel | Views/Tunnel | Source (top-level group, for resources)
  first-id  two hex digits; file n gets PBXBuildFile <prefix>1…<id+n> and PBXFileReference <prefix>2…<id+n>
```

In `UniFiCameraPopup/scripts/pbxproj-add-files.py` ersetzen:

```python
    "Source": ("A40000000000000000000002", None, None),
}
```

durch:

```python
    "Source": ("A40000000000000000000002", None, None),
    "Services": ("A40000000000000000000005", None, None),
    "Views/Settings": ("A40000000000000000000071", None, None),
}
```

In `UniFiCameraPopup/scripts/pbxproj-add-files.py` ersetzen:

```python
    group, first, *files = sys.argv[1:]
```

durch:

```python
    args = sys.argv[1:]
    prefix = "D4"
    if args[:1] == ["--prefix"]:
        prefix, args = args[1], args[2:]
    group, first, *files = args
```

In `UniFiCameraPopup/scripts/pbxproj-add-files.py` ersetzen:

```python
        build_id = f"D41{n:021X}"
        ref_id = f"D42{n:021X}"
```

durch:

```python
        build_id = f"{prefix}1{n:021X}"
        ref_id = f"{prefix}2{n:021X}"
```

Run:
```bash
python3 UniFiCameraPopup/scripts/pbxproj-add-files.py --prefix E5 Services 01 EventRuleService.swift
python3 UniFiCameraPopup/scripts/pbxproj-add-files.py --prefix E5 Views/Settings 02 EventRulesSection.swift
plutil -lint UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj
```
Expected: `added EventRuleService.swift E51000000000000000000001 E52000000000000000000001`, `added EventRulesSection.swift E51000000000000000000002 E52000000000000000000002`, `… OK`.

- [ ] **Step 7: Snapshot samples**

In `UniFiCameraPopup/Debug/SnapshotRenderer.swift` ersetzen:

```swift
        let door = WebhookMapping(label: "Haustür", actions: actions, protectCameraId: "cam-door",
                                  triggers: [.ring, .person], chimeOnOpen: true)
```

durch:

```swift
        let rules = [
            EventRule(kind: "ring", webhook: EventRuleWebhook(method: "POST", url: "https://home.example/klingel"),
                      soundId: SoundSettings.bundledBinGleichDa.id),
            EventRule(kind: "package", soundId: SoundSettings.bundledPaket.id, delaySeconds: 20),
        ]
        let door = WebhookMapping(label: "Haustür", actions: actions, protectCameraId: "cam-door",
                                  triggers: [.ring, .person], chimeOnOpen: true, eventRules: rules)
```

In `UniFiCameraPopup/Debug/SnapshotRenderer.swift` ersetzen:

```swift
            write(window: sheetWindow, appearance: appearance,
                  to: directory.appendingPathComponent("S4-button-sheet-\(suffix).png"))
```

durch:

```swift
            write(window: sheetWindow, appearance: appearance,
                  to: directory.appendingPathComponent("S4-button-sheet-\(suffix).png"))

            // Phase 5: event rule sheet over the same dimmed Kameras tab.
            let ruleRoot = ZStack {
                SettingsRootView(navigation: navigation)
                Color.black.opacity(0.3).frame(width: 760, height: 540)
                EventRuleEditorSheet(
                    rule: sample.door.eventRules[0], isNew: false,
                    kinds: [.ring, .person, .package, .animal, .vehicle, .motion],
                    sounds: SoundStore.shared.settings.announcements, canPlaySound: true,
                    onSave: { _ in }, onDelete: {}
                )
                .background(Tokens.win.color)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .environmentObject(sample.settings)
            .environmentObject(relay)
            .environmentObject(protectEvents)
            let ruleWindow = SettingsWindowController.makeWindow(rootView: ruleRoot)
            ruleWindow.title = "Kameras"
            write(window: ruleWindow, appearance: appearance,
                  to: directory.appendingPathComponent("S4-regel-sheet-\(suffix).png"))
```

- [ ] **Step 8: Build and look**

Run: Build-Befehl → `** BUILD SUCCEEDED **`; AppCore-Tests → 119/119; Renderer.
Expected: `S4-regel-sheet-*`: Titel „Regel „Klingel““; Zeilen Ereignis (Auswahl „Klingel“), Methode GET · POST, Adresse, Token + Hinweis, Ton („Bin gleich da“), Verzögerung (leeres Feld, Platzhalter „0“, „Sekunden (0–600)“); unten Testen · Entfernen · Abbrechen · Sichern. In `S2-kameras-*` beginnt unter den Buttons der Abschnitt „Ereignisse“ (der Rest liegt unterhalb des Fensters; das Detail scrollt).

- [ ] **Step 9: Commit**

```bash
git add UniFiCameraPopup/Services/EventRuleService.swift UniFiCameraPopup/Views/Settings/EventRulesSection.swift \
  UniFiCameraPopup/scripts/pbxproj-add-files.py UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj \
  UniFiCameraPopup/Services/KeychainStore.swift UniFiCameraPopup/Models/WebhookMapping.swift \
  UniFiCameraPopup/Services/SettingsStore.swift UniFiCameraPopup/Services/ProtectEventService.swift \
  UniFiCameraPopup/Services/TalkbackService.swift UniFiCameraPopup/Views/Settings/ActionEditorSheet.swift \
  UniFiCameraPopup/Views/Settings/CamerasTab.swift UniFiCameraPopup/Debug/SnapshotRenderer.swift
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "feat(events): per-camera event rules with webhook and/or sound, delay and debounce" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: „Was ist neu“, Hilfe, Design-Doku, Bildvergleich, manuelle Prüfpunkte

**Files:**
- Modify: `UniFiCameraPopup/Services/WhatsNewService.swift` (1.2.0-Eintrag)
- Modify: `UniFiCameraPopup/Views/HelpView.swift` („Aktions-Buttons“, „Sprechen und Ansagen“, neu „Ereignisse“)
- Modify: `docs/design/popup.md`, `docs/design/menue.md`, `docs/design/einstellungen-kameras.md`, `docs/design/einstellungen-ton.md`, `docs/design/tokens.md` (Phase-5-Abschnitt anhängen)
- Modify: `docs/superpowers/manual-checks-1.2.0.md` (Phase-5-Prüfpunkte anhängen)

**Interfaces:**
- Consumes: alles aus Task 1–11.
- Produces: geprüfter Stand, Texte, Prüfliste.

- [ ] **Step 1: „Was ist neu“ (nur der 1.2.0-Eintrag)**

In `UniFiCameraPopup/Services/WhatsNewService.swift` ersetzen:

```swift
            "Das Popup zeigt Ereignis, Kamera und Uhrzeit, deine Buttons (z. B. „Tür öffnen“) haben jetzt Symbole.",
            "Sprechen und Ansagen: Bei Kameras mit Lautsprecher hältst du im Popup die Leertaste (oder den Button) und sprichst über die Kamera – im Modus „Umschalten“ tippst du einmal zum Starten und einmal zum Beenden. Fertige Ansagen spielst du als MP3 oder mit einer macOS-Stimme aus eigenem Text ab – einzurichten im Reiter Ton.",
```

durch:

```swift
            "Deine Buttons im Popup (z. B. „Tür öffnen“) haben Symbole und können auch eine Ansage an der Kamera abspielen. Name und Uhrzeit blendet das Popup nur noch auf Wunsch ein (Kameras › Erweitert) – die Kamera zeigt beides ohnehin.",
            "Sprechen und Ansagen: Bei Kameras mit Lautsprecher hältst du im Popup den Button „Sprechen“ gedrückt und sprichst über die Kamera; Loslassen beendet. Fertige Ansagen spielst du als MP3 oder mit der macOS-Stimme Anna aus eigenem Text ab. Sprechen und Ansagen kommen gleich laut an, die Lautstärke regelst du für beides getrennt im Reiter Ton.",
            "Popups passen sich dem Bildschirm an: Zwei Kameras passen untereinander. Öffnen sich mehr, werden alle gleichmäßig kleiner und wachsen danach wieder auf ihre Größe.",
            "Ereignisse: Pro Kamera lösen Klingeln, Bewegung, Person, Fahrzeug, Tier oder Paket auf Wunsch einen Webhook und/oder eine Ansage aus – auch ohne Popup, während einer Stummschaltung und mit Verzögerung.",
            "Im Menü siehst du jetzt die Version und installierst ein Update direkt von dort.",
```

- [ ] **Step 2: Help texts**

In `UniFiCameraPopup/Views/HelpView.swift` ersetzen:

```swift
                + "die Details siehst du im Tooltip. Mit „Testen“ in den Einstellungen prüfst du die URL vorab.")
```

durch:

```swift
                + "die Details siehst du im Tooltip. Mit „Testen“ in den Einstellungen prüfst du die URL vorab. "
                + "Bei Kameras mit Lautsprecher kann ein Button zusätzlich (oder statt des Webhooks) eine Ansage aus dem Reiter Ton an der Kamera abspielen.")

            tip("Ereignisse", "bell.badge",
                "Unter Einstellungen › Kameras › Ereignisse legst du pro Kamera Regeln an: Bei Klingeln, Bewegung, Person, Fahrzeug, Tier oder Paket "
                + "ruft die App einen Webhook auf und/oder spielt eine Ansage an der Kamera ab – auf Wunsch mit Verzögerung (bis 600 Sekunden). "
                + "Regeln laufen auch ohne Popup und während einer Stummschaltung; dieselbe Regel löst höchstens alle 30 Sekunden aus. "
                + "Ausgeführte Regeln erscheinen im Menü unter den letzten Ereignissen.")
```

In `UniFiCameraPopup/Views/HelpView.swift` ersetzen:

```swift
                "Bei Kameras mit Lautsprecher zeigt das Popup unten „Ton abspielen“ und „Leertaste halten“. "
                + "Halte den Button oder – solange der Mauszeiger über dem Popup ist – die Leertaste gedrückt und sprich; "
                + "Loslassen beendet. Im Modus „Umschalten“ tippst du einmal zum Starten und einmal zum Beenden. Unter Einstellungen › Ton wählst du Mikrofon, Sprech-Modus und Lautstärke und verwaltest "
                + "die Ansagen (MP3 oder Text mit einer macOS-Stimme, erzeugt auf diesem Mac). Die mitgelieferten Ansagen "
```

durch:

```swift
                "Bei Kameras mit Lautsprecher zeigt das Popup unten „Ton abspielen“ und „Sprechen“. "
                + "Halte „Sprechen“ mit der Maus gedrückt und sprich; Loslassen beendet – auch wenn der Zeiger dabei das Popup verlässt. "
                + "Die App gleicht dein Mikrofon automatisch an die Lautstärke der Ansagen an. Unter Einstellungen › Ton wählst du das Mikrofon, "
                + "regelst „Lautstärke Sprechen“ und „Lautstärke Ansagen“ getrennt und verwaltest "
                + "die Ansagen (MP3 oder Text, gesprochen von der macOS-Stimme Anna, erzeugt auf diesem Mac). Die mitgelieferten Ansagen "
```

Run: `grep -rn "Leertaste\|Umschalten" UniFiCameraPopup --include='*.swift' | grep -v "/.build/"` → nur noch `Models/CameraHotkey.swift` (Tastenname „Leertaste“ für Kamera-Kürzel).

- [ ] **Step 3: Design documents (what the code is checked against)**

An `docs/design/popup.md` anhängen:

```markdown

## Phase 5 (Nutzerwunsch, gilt vor der Vorlage)
- Chip oben links nur, wenn Kameras › Erweitert › „Name und Zeit einblenden“ an ist (Standard: aus); ohne Chip entfällt er ganz.
- Stummschalten: Symbol Lucide `bell-off` (24er Raster, Strich 2, runde Enden), Tooltip „Diese Kamera stummschalten“.
- Sprechen statt „Leertaste halten“: 40 hoch, Innenabstand 0/18, Radius 20, `accent`, Mikrofon 16 + 6 + zwei Zeilen:
  oben 12/700 weiß „Sprechen“ → „Verbinde …“ (Deckkraft 70 %) → „Loslassen zum Beenden“; darunter 10 weiß 80 %
  „Gedrückt halten zum Sprechen“ (immer). Breite = längster Text. Spricht nur, solange die Maustaste gedrückt ist;
  Loslassen auch außerhalb beendet. Keine Leertaste. Passt die Leiste nicht 10 innerhalb des Popups: nur Mikrofon, Kreis 40.
- Buttons des Nutzers können statt/zusätzlich zum Webhook eine Ansage abspielen (nur bei Kameras mit Lautsprecher sichtbar, sonst nur ihr Webhook-Teil).
- Größe: ≈ 42 % der sichtbaren Bildschirmhöhe, Breite aus dem Seitenverhältnis; mehr Popups als Platz → alle gleichmäßig kleiner
  (mind. 160 hoch, sonst zweite Spalte), Wechsel 300 ms ease-in-out, „Bewegung reduzieren“ → sofort.
```

An `docs/design/menue.md` anhängen:

```markdown

## Phase 5 (Nutzerwunsch, gilt vor der Vorlage)
Nach der Trennlinie (4) und vor „Einstellungen …“: „Version 1.2.0 (29)“ 11 `muted`. Bei einem Update darunter (Abstand 6)
Button volle Breite wie die Stumm-Buttons (12/600, 6/0, Radius 7, `accSoft`/`accText`): „Update auf 1.3.0 installieren“
(gleiche Version, neuerer Build: „Update auf 1.2.0 (30) installieren“); während des Ladens „Lade neue Version …“ / „Installiere …“, gesperrt.
```

An `docs/design/einstellungen-kameras.md` anhängen:

```markdown

## Phase 5 (Nutzerwunsch, gilt vor der Vorlage)
- Karte 3 bekommt als vierte Zeile „Ton des Livebilds“ | Schalter (8/12). In „Erweitert › Popup“ steht dort „Name und Zeit einblenden“ (aus).
- Zeile 5: „Erweitert“ links, rechts Link „Kamera entfernen“ 12, `danger`, unterstrichen, immer sichtbar; Rückfrage bleibt.
- „Größe“: leere Felder = automatisch, Platzhalter = berechnete Werte; ein Wert allein hält das Seitenverhältnis.
- Button-Zeilen: Badge „TON“ (statt GET/POST) bei Buttons nur mit Ton; Adresse-Spalte „Ton „Name““ bzw. „<Adresse> + Ton“.
- Sheet S4: nach „Token“-Hinweis „Ton“ | Auswahl („Kein Ton“, Ansagen) + Hinweis 11 `muted` „Spielt die Ansage an der Kamera ab. Mit Adresse laufen Ton und Webhook gleichzeitig.“ – nur bei Kameras mit Lautsprecher. „Adresse“ ist dann optional.
- Neu nach „Buttons im Popup“: „Ereignisse“ 11/600 `muted`, Karte Radius 9; Zeilen 7/12, 12: Ereignis 600 (90 breit) · Aktionen `muted` gekürzt
  („home.example/klingel + „Bin gleich da““, „ · nach 20 s“) · „Ändern“; dann „Regel hinzufügen …“ (max. 10); darunter 11 `muted`
  „Regeln laufen auch ohne Popup und während einer Stummschaltung.“
- Sheet „Regel“: wie S4 (480, 18/20, Abstand 11, Raster 96): Titel „Neue Regel“ / „Regel „Klingel““ · Ereignis · Methode · Adresse · Token +
  Hinweis · Ton (nur mit Lautsprecher) · Verzögerung (Feld 64 + „Sekunden (0–600)“) · Ergebnis · Testen | Entfernen | Abbrechen | Sichern.
```

An `docs/design/einstellungen-ton.md` anhängen:

```markdown

## Phase 5 (Nutzerwunsch, gilt vor der Vorlage)
- Stimme: Auswahlfeld deaktiviert, zeigt „Anna · macOS“; ohne Anna „<beste deutsche Stimme> · macOS“ und darunter 11 System-Orange
  „Anna ist auf diesem Mac nicht installiert – es spricht „<Name>“. …“. „Thorsten · mitgeliefert“ wird nicht mehr angeboten.
- Karte 3: „Mikrofon“ · „Lautstärke Sprechen“ · „Lautstärke Ansagen“ (beide Regler wie „Lautstärke an der Kamera“, 2/3 = unverändert);
  die Zeile „Sprechen“ (Leertaste halten · Umschalten) entfällt.
```

An `docs/design/tokens.md` anhängen:

```markdown

## Phase 5 (nicht in der Vorlage)
`danger` #D70015 / #FF6961 (macOS systemRed, kontraststarke Variante) – nur für „Kamera entfernen“.
```

- [ ] **Step 4: Manual checks (append to the 1.2.0 list)**

An `docs/superpowers/manual-checks-1.2.0.md` anhängen:

```markdown

## Phase 5: Nutzer-Feedback (an echter Kamera, Debug-Build; installierte App vorher beenden)

Vorher: `defaults export com.snackbits.UniFiCameraPopup ~/ucp-backup-phase5.plist`; `tail -f ~/Library/Logs/UniFi\ Camera\ Popup/talkback.log` in einem Terminal.

- [ ] Erster Start über den 1.2.0-Einstellungen: Kameras mit 480 × 270 haben leere Größenfelder (Platzhalter ≈ 42 % der Bildschirmhöhe), andere Größen stehen weiter drin; kein Popup zeigt den Chip; Reiter Ton: beide Regler auf dem alten Wert, keine Zeile „Sprechen“.
- [ ] Alte installierte Version kurz starten und wieder beenden, dann den Debug-Build: Größen, „Name und Zeit einblenden“, Button-Töne und Regeln sind unverändert da.
- [ ] Popup: Glocke vollständig durchgestrichen, Tooltip „Diese Kamera stummschalten“; „Name und Zeit einblenden“ an → Chip erscheint beim nächsten Popup.
- [ ] Zwei Kameras auslösen („Alle aktiven Kameras zeigen“ an): passen untereinander ohne Verkleinerung. Vier auslösen (Test-Popups): alle werden gleichmäßig kleiner und bleiben vollständig sichtbar; ab sechs (bzw. < 160 pt) zweite Spalte. Eins schließen → die übrigen wachsen in 0,3 s weich zurück. „Bewegung reduzieren“ an → ohne Animation. Position „Unten links“ und „Bildschirmmitte“ prüfen, zweiter Bildschirm über „Bildschirm: Maus“.
- [ ] Größe nur Breite 800 eintragen → Höhe folgt (Platzhalter), Popup 800 breit; Feld leeren → wieder automatisch.
- [ ] Sprechen: Button gedrückt halten → „Verbinde …“ → „Loslassen zum Beenden“, an der Kamera hörbar; Maus bei gedrückter Taste aus dem Popup und über eine andere App ziehen, dort loslassen → Log „Mikrofon zu“, keine weiteren Pakete. Kurz antippen (vor „Live“) → nichts wird gesendet. Leertaste über dem Popup tut nichts (tippt in der App darunter).
- [ ] Popup mit 160 pt Höhe (sechs Popups): Sprech-Button ist der Mikrofon-Kreis, Halten funktioniert, Fenster wird nicht breiter.
- [ ] Lautstärke: „Bin gleich da“, eine laute eigene MP3 und Sprechen mit normaler Stimme klingen an der Kamera etwa gleich laut; geflüstert wird hörbar lauter angehoben, Schreien nicht übersteuert. Regler „Lautstärke Ansagen“ ganz links/rechts → leiser/lauter, „Lautstärke Sprechen“ unabhängig davon.
- [ ] Stimme: Feld zeigt „Anna · macOS“ (deaktiviert). „Ansage aus Text …“ + „Übernehmen“ → spricht Anna. Mitgelieferte Ansage: „Übernehmen“ ohne Textänderung → danach Anna statt Thorsten. Ohne installierte Anna (Systemeinstellungen › Bedienungshilfen › Gesprochene Inhalte: Anna entfernen) → anderer Name + orange Hinweiszeile.
- [ ] Button mit Ton und ohne Adresse: Sichern geht; im Popup der Türklingel spielt er die Ansage; an einer Kamera ohne Lautsprecher fehlt er. Button mit Adresse + Ton: Webhook und Ansage gleichzeitig. Ansage löschen → Button mit Adresse zeigt nur noch den Webhook-Teil, Sheet „Gelöschte Ansage“.
- [ ] Ereignisse: Regel „Klingel → Webhook (Home Assistant) + „Bin gleich da“, Verzögerung 0“ – klingeln → Webhook kommt an, Ansage an der Kamera, Menü-Panel zeigt „Klingel → Webhook + „Bin gleich da““. Auch bei globaler Stummschaltung und ohne Popup (Auslöser „Klingel“ aus).
- [ ] Ereignisse: Regel „Bewegung → Webhook, Verzögerung 20“: vor der Kamera bewegen → Webhook nach ≈ 20 s; erneut innerhalb von 30 s → kein zweiter Aufruf; nach 30 s wieder.
- [ ] Ereignisse unterwegs (Phase-4-Tunnel aktiv): Webhook an eine LAN-Adresse im Tunnel kommt an.
- [ ] Regel mit Token: Konfiguration exportieren → `grep -c "<Token>" export.json` → 0, `grep -c eventRules export.json` → ≥ 1; Import auf demselben Mac → Token ist noch da (Regel „Testen“ → HTTP 2xx).
- [ ] Menü-Panel: „Version 1.2.0 (<Build>)“ über „Einstellungen …“. Mit einem Test-Manifest höheren Builds auf dem Server (nur wenn ohnehin ein Release ansteht – sonst „nicht prüfbar“ notieren): Button „Update auf … installieren“ → bestehende Rückfrage.
- [ ] Kameras: „Kamera entfernen“ rot neben „Erweitert“, auch eingeklappt; Rückfrage erscheint; „Ton des Livebilds“ steht in der oberen Karte.
```

- [ ] **Step 5: Full verification and image comparison**

Run:
```bash
(cd Packages/AppCore && swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -1)      # 119 tests, 0 failures
(cd Packages/ProtectKit && swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -1)   # 142 tests, 0 failures
```
Build-Befehl → `** BUILD SUCCEEDED **`; Renderer. Dann je Bild die Vorlage (https://claude.ai/artifact/Q9JCg1b1gu5stRG2SxaKsP, Ausschnitte wie Phase-2-Plan Task 9 Step 3) und die Phase-5-Abschnitte in `docs/design/*.md` danebenlegen und abhaken: `7-panel`, `7-panel-update`, `8-popup`, `8-popup-ohne-chip`, `8-popup-menue`, `9-popup-sprechen-{ruhe,menue,verbinde,spricht,ansage,hinweis}`, `9-popup-schmal`, `S2`, `S3`, `S4-button-sheet`, `S4-regel-sheet`, `S5-ton` – hell und dunkel. Jede Differenz, die weder in „Bewusste Abweichungen“ noch in „Entscheidungen“ steht, wird behoben (zurück in den Task) oder als Frage gemeldet.

- [ ] **Step 6: Commit**

```bash
git add UniFiCameraPopup/Services/WhatsNewService.swift UniFiCameraPopup/Views/HelpView.swift \
  docs/design/popup.md docs/design/menue.md docs/design/einstellungen-kameras.md docs/design/einstellungen-ton.md \
  docs/design/tokens.md docs/superpowers/manual-checks-1.2.0.md
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "docs: phase 5 release notes, help, design notes and manual checks" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
Kein Push, kein Merge, kein Release-Build. `git status --short` zeigt danach nur ` M UniFiCameraPopup/AppConfig.swift`.
