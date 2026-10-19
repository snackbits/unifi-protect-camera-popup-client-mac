# Phase 2 – Einstellungen & Popup nach Vorlage, Stummschalten – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Einstellungsfenster (Reiter Allgemein / Kameras / Ton / Unterwegs), Popup (Vorlage B) und Menüleisten-Panel werden 1:1 nach der verbindlichen Vorlage gebaut; Stummschalten gibt es global und pro Kamera mit konfigurierbaren Dauern, das Ende überlebt einen Neustart; Erscheinungsbild System/Hell/Dunkel; ein Test-Target macht die Logik testbar.

**Architecture:** Testbare Logik (Stumm-Zeitplan, Dauern, Erscheinungsbild, Ereignis-Verlauf, Anzeigetexte, Design-Tokens) wandert in ein neues lokales Swift-Package `Packages/AppCore` mit Test-Target (`swift test`), so wie `ProtectKit` in Phase 1. Die App bekommt einen kleinen Satz Vorlagen-Bausteine (SwiftUI) und Vorlagen-Symbole (SVG aus der Vorlage, als Asset), darauf bauen das neue Einstellungsfenster (feste Größe 760 × 540, eigene Reiterleiste), das Menüleisten-Panel (eigenes `NSPanel`) und die Popup-Überlagerungen (AppKit). `SettingsStore` speichert die neuen Felder abwärtskompatibel.

**Tech Stack:** Swift 5.9 Tools / Xcode 27, SwiftUI + AppKit (macOS 13.0), XCTest über `swift test` in lokalen Packages, Asset-Katalog mit SVG (Vektor, Template-Rendering).

**Spec:** `docs/superpowers/specs/2026-10-18-phases-2-4.md` (Abschnitte „Verbindliche Vorlage“, „Phase 2“, „Querschnitt“). Vorlage: `docs/superpowers/specs/phase2-4/design/Einstellungen.dc.html` (Bildschirme S1–S6) und `.../Main.dc.html` (Bildschirme 7 Menüleiste und 8 Popup); Dunkel-Varianten = dieselben Komponenten mit den `night`-Tokens. Veröffentlicht: https://claude.ai/artifact/Q9JCg1b1gu5stRG2SxaKsP. Format/Befehle wie `docs/superpowers/plans/2026-10-18-protect-integration-phase1.md`.

> **Vorab geprüft (18.10.2026):** Alle Code-Schritte wurden in einer Kopie des Worktrees angewendet; nach jedem Task 1–8 und am Ende: `** BUILD SUCCEEDED **`, `swift test` AppCore 31/31, ProtectKit 52/52. Sichtprüfung und Bildvergleich stehen aus (Task-Schritte).

## Entscheidung: Test-Target als lokales Package `AppCore`

Die Spezifikation verlangt ein App-Test-Target. Gewählt wird **ein lokales Swift-Package `Packages/AppCore` mit Test-Target**, nicht ein XCTest-Bundle im Xcode-Projekt. Begründung:

1. Ein Unit-Test-Bundle im Projekt läuft *in* der App (Test-Host): `applicationDidFinishLaunching` startet dabei Onboarding-Fenster, Relay-WebSocket, Protect-Socket, Update-Prüfung und `SMAppService`-Abgleich (Anmeldeobjekt!) – auf dem Rechner des Nutzers, mit dessen echten `UserDefaults` und Schlüsselbund (gleiche Bundle-ID).
2. Das Projekt hat kein geteiltes Scheme (`xcshareddata/xcschemes` fehlt); ein Test-Bundle bräuchte eine handgeschriebene `.xcscheme` mit Test-Aktion plus eigene Signatur (Self-Signed-Identität, kein bezahlter Account).
3. `swift test` läuft headless und schnell, genau wie bei `ProtectKit` – ein Befehl, keine Signatur, kein Simulator.

Konsequenz: Alles, was getestet werden muss, liegt in `AppCore` als reine Werttypen ohne Singletons; die App ist dünne Verdrahtung darum herum.

## Global Constraints

- macOS-Deployment-Target **13.0**; keine API neuer als macOS 13 ohne `#available` (geplant: keine).
- Keine Sandbox, Hardened Runtime bleibt aus, kein bezahlter Developer-Account; Signatur unverändert.
- UI-Sprache Deutsch, Du-Form, typografische Anführungszeichen „…“; Code und Bezeichner Englisch.
- Die Vorlage ist **Vorgabe, keine Anregung**: Maße, Texte, Farben, Reihenfolge 1:1 aus `docs/design/*.md` (Task 3). Abweichungen nur die im Abschnitt „Abweichungen von der Vorlage“ dieses Plans genannten.
- Breiten in der Vorlage sind CSS-`content-box`, wo kein `box-sizing` gesetzt ist: Gesamtbreite = `width` + Innenabstand + Rand (Werte in `docs/design/tokens.md`).
- Akzentfarbe Indigo **#4B3FD1** (hell) / **#5B4FE0** (dunkel); Asset `AccentColor` existiert und bleibt.
- API-Schlüssel nur im Schlüsselbund; nie im Konfigurations-Export (Bestehendes Verhalten der Aktions-Tokens bleibt).
- Version bleibt **1.2.0**, Build-Nummer unangetastet; nur der bestehende 1.2.0-Eintrag in `WhatsNewService` wird ergänzt.
- `UniFiCameraPopup/AppConfig.swift` hat lokale Änderungen des Nutzers: **nie ändern, nie stagen, nie zurücksetzen**. Immer nur mit expliziten Pfaden `git add`; nie `git add -A`, `git add .` oder `git commit -a`. Vor jedem Commit: `git diff --cached --name-only | grep AppConfig` muss leer sein.
- Kein Merge, kein Push.
- Debug-Build und installierte App teilen Bundle-ID und `UserDefaults`: neue Einstellungsfelder sind optional und tolerant dekodiert; `muteUntil` wird weiter geschrieben, damit die installierte Version nicht bricht. Vor Sichtprüfungen die installierte App beenden (sonst zwei Menüleisten-Symbole).
- Jeder Task endet mit grünem Build.

**Befehle** (aus dem Worktree-Wurzelverzeichnis `app-protect/`):

```bash
# App bauen (erster Lauf löst vlckit-spm auf, braucht Netz)
DD="${TMPDIR:-/tmp}/ucp-phase2-dd"
xcodebuild -project UniFiCameraPopup/UniFiCameraPopup.xcodeproj -scheme UniFiCameraPopup \
  -configuration Debug -derivedDataPath "$DD" build 2>&1 | grep -E "error:|\*\* BUILD" | tail -20
# Erwartet: ** BUILD SUCCEEDED **

# Tests
(cd Packages/AppCore && swift test 2>&1 | tail -5)
(cd Packages/ProtectKit && swift test 2>&1 | tail -5)

# App starten (installierte App vorher beenden)
open "$DD/Build/Products/Debug/UniFi Camera Popup.app"

# pbxproj nach Handänderung prüfen
plutil -lint UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj
```

## Review Focus

1. **Alte Einstellungen nach dem Update** (nur `muteUntil`, kein `appearance`, oder ein unbekannter Wert von einem neueren Build): Laden klappt, eine laufende globale Stummschaltung bleibt erhalten, unbekanntes Erscheinungsbild wird „System“. → Tests `MuteScheduleTests.testLegacyMigrationKeepsGlobalMute`, `AppearanceModeTests.testUnknownValueFallsBackToSystem` (Task 1).
2. **Stummschaltung läuft ab, während die App beendet ist**: Nach dem Neustart kommen wieder Popups, im Menü steht kein „Aufheben“ mehr, kein Timer mit negativer Laufzeit. → `MuteScheduleTests.testSurvivesRestartAndExpiresWhileQuit` (Task 1).
3. **Kamera wird entfernt, während sie stumm ist oder Ereignisse hat**: kein verwaister Eintrag „stumm“ im Menü, keine Geister-Ereignisse. → `MuteScheduleTests.testPruneDropsRemovedCameras`, `EventHistoryTests.testRemoveEntries` (Task 1).
4. **Unsinnige Eingabe im Dauer-Feld** (leer, „0“, „12a“, „-5“, „5000“): Feld behält den alten Wert bzw. begrenzt auf 1…999, nie 0 Sekunden Stummschaltung. → `MuteDurationTests.testParseRejectsGarbageAndClamps` (Task 1).
5. **Popup ohne Ereignis-Art** (Tastenkürzel, Test-Popup, Webhook) oder ohne Namen: Leiste zeigt „Haustür · 10:41“ bzw. „Kamera · 10:41“, nie „nil“, „ · · “ oder einen leeren Chip. → `DisplayTextTests.testPopupChipWithoutKindOrName` (Task 1).

---

## Abweichungen von der Vorlage

Jede Zeile ist eine Stelle, an der SwiftUI/AppKit oder ein fehlender Zustand der Vorlage eine Entscheidung erzwingt. Sie stehen hier zur Bestätigung (siehe „Offene Fragen“), umgesetzt wird der jeweils genannte Vorschlag.

1. **Fensterrahmen nativ:** Ampeln und Titel kommen von macOS (Titelleiste transparent, Höhe 28 pt wie Vorlage). Grüne Ampel ist ausgegraut, weil das Fenster feste Größe hat. Fenster-, Popup- und Panel-Schatten sind der native Fensterschatten statt der CSS-Schatten. Fensterecken-Radius ist der des Systems.
2. **Allgemein – „Erweitert“:** Links in der Export-Zeile ein zugeklapptes „Erweitert“ (Stil wie in Kameras). Darunter, scrollend: Popup (Bildschirm, Randabstand, Automatisch schließen, Alle aktiven Kameras zeigen), Updates (Automatisch aktualisieren, Version), Webhooks/Relay (Verbindung, Eindeutige ID, Webhook-Adresse, Bearer-Token), Hilfe. Sonst wären diese heutigen Einstellungen nicht mehr erreichbar.
3. **Allgemein – Zusatzzeilen nur bei Bedarf:** Verbindungsfehler/„Neuem Zertifikat vertrauen“ (Karte Konsole), Hinweis Festplattenvollzugriff (unter „Im Fokus-Modus keine Popups“), Hinweis Anmeldeobjekte-Freigabe (unter „Bei Anmeldung starten“). Hinweis zum Export-Inhalt als Tooltip am Export-Button.
4. **Konsole-Zeile:** „Name · Adresse“ nur, wenn der Name aus der Konsolensuche bekannt ist, sonst nur die Adresse; nicht eingerichtet → „nicht eingerichtet“ und Button „Einrichten …“. Statuspunkt: grün #34C759 verbunden, Orange (System) verbinde/Fehler, Rot (System) getrennt, `toggleOff` nicht eingerichtet (Vorlage zeigt nur grün).
5. **„Ändern …“ / „Ersetzen …“** öffnen die vorhandene Einrichtung (Schritt Konsole bzw. Schlüssel) statt eines eigenen Dialogs.
6. **Auswahlfelder** (Popup-Position, Einheit, Protect-Kamera …): das Feld ist 1:1 gezeichnet, die aufklappende Liste ist ein natives `NSMenu`. Schieberegler in „Erweitert“ sind nativ (Akzentfarbe).
7. **Kameras – Seitenleiste:** unten Link „Kamera hinzufügen …“ (Menü: „Aus Protect wählen …“ / „Nur per Webhook“). Zustandszeile zusätzlich „stumm bis 10:56“ und „Webhook“. Vorschaubild = Schnappschuss der Kamera (`GET /v1/cameras/{id}/snapshot`), die Streifen der Vorlage sind Platzhalter beim Laden/ohne Bild.
8. **Kameras – Kopf:** Untertitel = Protect-Modellname (+ „ · Lautsprecher“); reine Webhook-Einträge „nur Webhook“ und statt der Chips der Hinweis „Diese Kamera meldet sich nur per Webhook (siehe „Erweitert“).“
9. **„Hinweiston beim Öffnen“** ist eine neue Einstellung (Systemton „Glass“, Standard **aus**); der bisherige Schalter „Ton“ (Ton des Livebilds) wandert nach Erweitert › Popup als „Ton des Livebilds“. **„Zoom und Ausschnitt merken“** schaltet das bisherige „Zoom merken“; den Ausschnitt setzt man unter Erweitert.
10. **Buttons-Liste:** Bei drei Buttons ersetzt „Höchstens drei Buttons.“ (12 pt, `muted`) den Link „Button hinzufügen …“.
11. **Kameras – Erweitert:** zusätzliche Karte „Popup“ (Name, Protect-Kamera, Position, Größe, Ton des Livebilds, Ausschnitt setzen/löschen, Test-Popup) und Link „Kamera entfernen …“ (Stil wie „Tunnel entfernen“). Webhook-ID und Aufruf-Adresse nur bei eingeschaltetem Webhook. „Webhook jetzt testen“ öffnet ein Test-Popup. Nie ausgelöst → „Zuletzt ausgelöst: noch nie“. Warnungen zur Stream-Adresse (rtsps, 7441, enableSrtp) als Zusatzzeile.
12. **Button-Sheet:** native Sheet-Darstellung von macOS 13 (eigene runde Ecken, kein abgedunkelter Hintergrund `scrim`). Neuer Button: Titel „Neuer Button“. Zusätzlich Link „Entfernen“ links neben dem Spacer. Testfehler in System-Orange statt `ok`-Grün. „Vor dem Ausführen nachfragen“ fragt im Popup per Systemdialog.
13. **Ton und Unterwegs:** Gerüst mit dem Vorlagen-Layout und den Beispielwerten der Vorlage, nicht bedienbar (Funktion in Phase 3/4, alles geht gemeinsam als 1.2.0 raus).
14. **Popup:** Die Leiste unten zeigt in Phase 2 nur die Buttons des Nutzers mit ihrem Symbol (Sprechen und „Ton abspielen“ ab Phase 3); ohne Buttons keine Leiste. Ohne Ereignis-Art lautet der Chip „Haustür · 10:41“. Rückmeldung eines Buttons: halbtransparent während der Anfrage, danach 1,5 s grün bzw. orange eingefärbt. Das Stumm-Menü ist eine eigene Ansicht im Popup (kein `NSMenu`), Klick daneben schließt erst das Menü. Popup-Größe bleibt pro Kamera einstellbar (Vorlage zeigt 470 × 300 als Beispiel).
15. **Menüleiste:** Linksklick öffnet ein eigenes Panel nach Vorlage (kein `NSMenu`), 8 pt unter der Menüleiste, rechte Kante bündig mit dem Statussymbol (im Vorlagen-Mockup nicht exakt ableitbar). Rechtsklick/⌃-Klick öffnet das bisherige Menü (Status, Version, Update, Kameras, Einrichtung …). Status-Chip: „Zu Hause“ (verbunden), „Verbinde …“, „Getrennt“, „Nicht eingerichtet“. Neuer Bereich „Stummgeschaltet“ mit „Aufheben“ je Eintrag (Vorlage zeigt keinen Stumm-Zustand). Zusätzliche Zeilen „Hilfe“ und „Beenden ⌘Q“. Ereignisse sind anklickbar (öffnet die Kamera); ohne Ereignisse entfällt die Liste; Zeit älterer Ereignisse „gestern“ bzw. „12.10.“.
16. **Menüleisten-Symbol** bleibt das bisherige Asset mit Statusfarbe und Zzz-Abzeichen.
17. **Deaktivierte Bedienelemente** 45 % Deckkraft, gedrückt 70 % (Vorlage zeigt beides nicht).

## Offene Fragen

1. **Hinweiston:** Ist „Hinweiston beim Öffnen“ wirklich ein neuer Ton beim Öffnen (dann: welcher, Standard an oder aus?) oder war der bisherige Schalter „Ton“ (Ton des Livebilds) gemeint? Plan: neu, „Glass“, Standard aus (Abweichung 9).
2. **Stumm-Zustand im Menü-Panel:** Passt der vorgeschlagene Bereich „Stummgeschaltet“ mit „Aufheben“ (Abweichung 15), oder gibt es dafür einen Entwurf?
3. **Menü-Panel vs. bisheriges Menü:** Ist Rechtsklick für Version/Update/Kameras/Einrichtung in Ordnung, und sollen „Hilfe“ und „Beenden“ im Panel stehen?
4. **Ton/Unterwegs-Gerüst** mit den Beispielwerten der Vorlage (deaktiviert) – in Ordnung, da 1.2.0 erst mit Phase 3/4 erscheint?
5. **„Webhook jetzt testen“** = Test-Popup öffnen – oder soll ein echter Aufruf über den Relay-Server simuliert werden?
6. **Bildvergleich:** `support.js` der `.dc.html` liegt nicht im Repo, die Vorlage rendert lokal nicht. Plan: Vergleich gegen das veröffentlichte Artefakt im angemeldeten Browser (Task 9). Gibt es stattdessen exportierte PNGs?
7. **Schnappschuss-Endpunkt** `GET /proxy/protect/integration/v1/cameras/{id}/snapshot` ist nicht an echter Hardware geprüft; ohne Antwort bleiben die Streifen-Platzhalter.

---

## File Structure

```
Packages/AppCore/                                   (neu, Test-Target der App-Logik)
  Package.swift
  Sources/AppCore/
    MuteDuration.swift        angebotene Stumm-Dauer (Wert/Einheit, Texte, Eingabe-Parser)
    MuteSchedule.swift        globale + Pro-Kamera-Stummschaltung, Ablauf, Migration
    AppearanceMode.swift      System/Hell/Dunkel → NSAppearance
    EventHistory.swift        letzte Ereignisse (Menü, „Zuletzt ausgelöst“)
    DisplayText.swift         Anzeigetexte: Popup-Chip, Uhrzeiten, Kamera-Zustand, Adressen
    DesignTokens.swift        Farb-Tokens der Vorlage (hell/dunkel) als dynamische Farben
  Tests/AppCoreTests/         je eine Testdatei pro Quelldatei

Packages/ProtectKit/
  Sources/ProtectKit/TriggerKind.swift      + displayOrder, chips(supported:)
  Sources/ProtectKit/ProtectClient.swift    + snapshot(cameraId:)
  Sources/ProtectKit/Discovery.swift        + ConsoleProbe.decide (401-Fallback meta/info)
  Tests/ProtectKitTests/…                   + Tests dazu

docs/design/                                (neu, Prüfgrundlage)
  tokens.md, einstellungen-allgemein.md, einstellungen-kameras.md, einstellungen-ton.md,
  einstellungen-unterwegs.md, popup.md, menue.md

UniFiCameraPopup/
  UniFiCameraPopup.xcodeproj/project.pbxproj   + AppCore, + neue Dateien, − SettingsView.swift
  Assets.xcassets/Icons/*.imageset             Vorlagen-Symbole als SVG (Template)
  Models/WebhookMapping.swift                  + chimeOnOpen; CameraAction + icon, confirmBeforeRun; ActionIcon
  Services/SettingsStore.swift                 + muteSchedule, muteShort/Long, appearance, protectConsoleName
  Services/EventLog.swift (neu)                Ereignis-Verlauf + Schnappschüsse
  Services/ProtectSession.swift                + snapshot(cameraId:maxAge:)
  Services/PopupController.swift               Pro-Kamera-Stumm, Verlauf, Hinweiston, Overlay-Inhalt
  Services/CameraActionService.swift           trigger gibt HTTP-Status zurück
  Views/Design/DesignComponents.swift (neu)    Vorlagen-Bausteine (Karten, Schalter, Segmente, Buttons, Felder)
  Views/Design/PopUpField.swift (neu)          Auswahlfeld + NSMenu-Präsentation
  Views/Settings/SettingsWindow.swift (neu)    Fenster, Reiterleiste, Navigation, AppActions
  Views/Settings/GeneralTab.swift (neu)        Reiter Allgemein
  Views/Settings/SoundAndRemoteTabs.swift (neu) Gerüste Ton und Unterwegs
  Views/Settings/CamerasTab.swift (neu)        Reiter Kameras (Seitenleiste, Detail, Buttons)
  Views/Settings/CameraAdvancedSection.swift (neu) Kameras › Erweitert
  Views/Settings/ActionEditorSheet.swift (neu) Sheet „Button bearbeiten“
  Views/SettingsView.swift                     entfällt (Task 6)
  Views/HotkeyRecorderView.swift               Zeile im Vorlagenstil
  Views/Onboarding/OnboardingWindow.swift      + show(startAt:)
  Views/Onboarding/OnboardingView.swift        kanonische Adresse im Hinweis, Chips nach Vorlage, Konsolenname
  Views/Popup/PopupOverlayViews.swift (neu)    Chip, Rund-Buttons, Stumm-Menü, Button-Leiste
  Views/PopupWindow.swift                      Overlays nach Vorlage B statt MuteBar
  Views/StatusPanel/StatusPanel.swift (neu)    Menüleisten-Panel
  AppDelegate.swift                            Panel/Rechtsklick-Menü, Erscheinungsbild, Stumm-Ablauf
  Services/WhatsNewService.swift               1.2.0-Eintrag ergänzt
```

**Neue pbxproj-IDs** (frei geprüft; Schema wie Phase 1): BuildFile `A1…0070`–`A1…0082`, FileRef `A2…0071`–`A2…0082`, Gruppen `A4…0070` (Design), `A4…0071` (Settings), `A4…0072` (Popup), `A4…0073` (StatusPanel), Package-Referenz `AB…0002`, Produkt `A5…0003`. Vor jeder Änderung prüfen: `grep -c "A10000000000000000000071" UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj` → `0`.

---

## Design-Spezifikation

Task 3 legt diese Dateien unverändert unter `docs/design/` ab. Der Code jedes UI-Tasks wird gegen sie geprüft, nicht gegen das Gedächtnis. Alle Maße in pt (= CSS-px der Vorlage, 1×).

### `docs/design/tokens.md`

```markdown
# Design-Tokens (Vorlage Phase 2–4)

Quelle: `docs/superpowers/specs/phase2-4/design/Einstellungen.dc.html` und `Main.dc.html`,
Objekte `light` / `night` in `renderVals()`. Code: `Packages/AppCore/Sources/AppCore/DesignTokens.swift`.

## Farben (Hell / Dunkel)

| Token | Hell | Dunkel | Verwendung |
|---|---|---|---|
| page | #DCDDE6 | #121318 | nur Vorlagen-Hintergrund |
| win | #FBFBFD | #26262C | Fensterfläche, Sheet, Menü-Panel |
| bar | #F3F3F7 | #2C2C33 | Titelleiste + Reiterleiste |
| side | #F2F2F6 | #222227 | Kameras-Seitenleiste |
| group | #FFFFFF | #2E2E35 | Karten |
| fg | #1D1D1F | #EDEDF2 | Text |
| muted | #55555F | #ABABB7 | Nebentext, Abschnittsüberschriften |
| accent | #4B3FD1 | #5B4FE0 | Schalter an, Chips an, Hauptbutton, Auswahl Seitenleiste |
| accSoft | #ECEAFB | #312C5C | weiche Akzentflächen, Methoden-Badge, Stumm-Buttons im Menü |
| accText | #3528A8 | #C3BDFF | Links, aktiver Reiter, Badge-Text |
| border | #DEDEE6 | #3B3B45 | Kartenrand, Trennlinien (Einstellungen) |
| field | #FFFFFF | #1C1C21 | Eingabefelder, Feld-Buttons |
| ok | #1C6B30 | #86E3A6 | Erfolgstext |
| okBg | #E3F5E8 | #1F3A2A | Erfolgsfläche, Status-Chip „Zu Hause“ |
| segBg | #E8E8EE | #1C1C21 | Segment-Hintergrund |
| segOn | #FFFFFF | #3E3E48 | aktives Segment |
| segShadow | rgba(0,0,0,.14) | rgba(0,0,0,.4) | Schatten aktives Segment, 0 1 2 |
| chipOff | #FFFFFF | #34343C | Chip aus (Einstellungen) |
| chipBorder | #C9C9D6 | #4A4A55 | Rand Felder/Chips |
| naFg | #7A7A86 | #8A8A97 | Chip „kann die Kamera nicht“ |
| toggleOff | #D1D1D8 | #4A4A55 | Schalter aus, Regler-Spur |
| btn2 | #EFEFF4 | #34343C | Symbolauswahl aus, MP3-Badge |
| scrim | rgba(30,30,50,.18) | rgba(0,0,0,.42) | (Sheet-Abdunklung, nativ nicht genutzt) |
| tabOn | #E4E2F8 | #3A3566 | aktiver Reiter |
| mainBorder | #D9D9E3 | #3B3B45 | Rand/Trenner Menü-Panel und Stumm-Menü (Main) |
| mainChipOff | #FFFFFF | #2E2E35 | Chip aus im Onboarding (Main) |
| menu | #FBFBFD | #2B2B31 | Stumm-Menü im Popup |
| dotOff | #C9C9D6 | #4A4A55 | Onboarding-Punkte |
| dropBorder | #B8B2F2 | #6D63D9 | Ablagefläche (Phase 4) |
| pill | rgba(250,250,252,.9) | rgba(20,21,24,.84) | Button-Leiste im Popup |
| pillRing | rgba(0,0,0,.08) | rgba(255,255,255,.1) | Ring der Button-Leiste |
| pillBtn | #E6E6EE | #3A3B42 | Rund-Buttons in der Leiste |
| pillFg | #1D1D1F | #EDEDF0 | Symbole in der Leiste |

Fest (beide Erscheinungsbilder): overlay rgba(0,0,0,.62) · white #FFFFFF · statusGreen #34C759 ·
Streifen #2A2D36/#30343E (Kamera-Platzhalter, 135°) · popupRing rgba(255,255,255,.1) ·
Ampeln #FF5F57/#FEBC2E/#28C840 (nativ).

## Schrift

System (SF Pro). Gewichte: 400 regular, 500 medium, 600 semibold, 700 bold.
Grundgröße Einstellungen 13. Weitere Größen: 16/700 Kamera-Titel, 15/700 Sheet-Titel,
14/700 Panel-Titel und Statuszeile Unterwegs, 12 Feld-Buttons/Felder/Links, 11 Abschnitts-
überschriften (600) und Nebentext, 10 Badges (700) und Zustandszeile Seitenleiste. Zahlen
in Dauer-Feldern, Längen und Uhrzeiten: tabellarische Ziffern. Links sind unterstrichen
(Browser-Standard für `<a>` in der Vorlage).

## content-box

Ohne `box-sizing` zählt `width` ohne Innenabstand und Rand. Daraus:
Seitenleiste Kameras 190 + 2×8 + 1 Rand = 207 · Sheet 440 + 2×20 = 480 ·
Menü-Panel 310 + 2×14 = 338 · Stumm-Menü im Popup 190 + 2×5 = 200 ·
Segment GET/POST 120 + 2×2 = 124 · Dauer-Eingabe 34 + 2×6 = 46.
Fenster 760 × 540, Reiter-Buttons 78 breit (ohne horizontalen Innenabstand).

## Schatten (CSS, nur wo nicht nativ)

Popup-Stumm-Menü 0 10 24 rgba(0,0,0,.4) + Ring 1 mainBorder · Button-Leiste 0 6 18
rgba(0,0,0,.3) + Ring 1 pillRing · Regler-Knopf 0 1 3 rgba(0,0,0,.35).
Fenster, Popup und Menü-Panel: nativer Fensterschatten.

## Symbole

Inline-SVGs der Vorlage, 24er viewBox, als Vektor-Assets `Assets.xcassets/Icons/<name>.imageset`
(Template-Rendering, Farbe = Vordergrund). Strichstärke je Symbol wie in der Vorlage.
```

### `docs/design/einstellungen-allgemein.md`

```markdown
# Einstellungen › Allgemein (Vorlage S1)

Fenster 760 × 540, Fläche `win`. Kopf (`bar`, Rand unten 1 `border`): Titelleiste 28 hoch,
Titel „Allgemein“ 13/600 mittig (nativ); darunter Reiterleiste.

## Reiterleiste (alle Reiter gleich)
Zentriert, Abstand 4, Innenabstand oben 2 unten 8. Reiter-Button 78 breit, Innenabstand 5
oben/unten, Radius 7, senkrecht Symbol 20 + 3 + Text 11.
Reihenfolge/Texte/Symbole: Allgemein (tabGeneral) · Kameras (tabCameras) · Ton (tabSound) ·
Unterwegs (tabRemote). Aktiv: Fläche `tabOn`, Farbe `accText`; sonst transparent, `muted`.
Fenstertitel je Reiter: „Allgemein“, „Kameras“, „Ton & Sprechen“, „Unterwegs“.

## Inhalt
Innenabstand 22 oben/unten, 40 links/rechts; Abstand 16; Schrift 13. Scrollt bei Bedarf.

1. Karte (Radius 10, `group`, Rand 1 `border`), Zeilen Innenabstand 11/14, Abstand 10,
   Trennlinie 1 `border`:
   - „Konsole“ | Punkt 8 #34C759 + 6 + „UDM Pro · 192.168.1.1“ (`muted`) | Button „Ändern …“
   - „API-Schlüssel“ | „im Schlüsselbund“ (`muted`) | Button „Ersetzen …“
   Feld-Button: 12, Innenabstand 3/10, Radius 6, Rand 1 `chipBorder`, Fläche `field`, Text `fg`.
2. Karte, Zeilen Innenabstand 10/14:
   - „Erscheinungsbild“ | Segment „System“ (aktiv) · „Hell“ · „Dunkel“
     Segment: Fläche `segBg`, Radius 7, Innenabstand 2, Schrift 12; Segment Innenabstand
     3/12; aktiv Radius 5, `segOn`, Schatten `segShadow` 0 1 2, 600; inaktiv `muted`.
   - „Popup-Position“ | Auswahlfeld „Oben rechts“ + Doppelpfeil 9 (Abstand 6, 12, Innenabstand
     3/10, Radius 6, Rand 1 `chipBorder`, Fläche `field`)
   - „Im Fokus-Modus keine Popups“ | Schalter an
   - „Bei Anmeldung starten“ | Schalter an
   Schalter: 32 × 19, Radius 10, an `accent` (Knopf rechts), aus `toggleOff` (Knopf links);
   Knopf 15, weiß, 2 vom Rand.
3. Abschnitt (Abstand 6): Überschrift „Stummschalten (Menüleiste)“ 11/600 `muted`; Karte,
   Zeilen Innenabstand 9/14:
   - „Kurz“ | Dauer-Feld „15“ + „Minuten“
   - „Lang“ | Dauer-Feld „1“ + „Stunden“
   Dauer-Feld: Rahmen Radius 6, Rand 1 `chipBorder`, Fläche `field`, Schrift 12; Eingabe 34
   breit, Innenabstand 3/6, rechtsbündig, tabellarisch; Trenner 1 `chipBorder`; Einheit
   Innenabstand 3/8, Abstand 5, Text + Doppelpfeil 9. Einheitentext immer Plural.
4. Zeile rechtsbündig, Abstand 8: „Konfiguration exportieren …“ · „Importieren …“
   (Feld-Button, Innenabstand 4/12).
```

### `docs/design/einstellungen-kameras.md`

```markdown
# Einstellungen › Kameras (Vorlage S2, S3, S4)

Kopf wie Allgemein, Titel „Kameras“, Reiter „Kameras“ aktiv.

## Seitenleiste (S2)
Breite 190 + Innenabstand 10/8 + Rand rechts 1 `border` (gesamt 207), Fläche `side`,
Abstand 2. Eintrag: Abstand 8, Innenabstand 6/8, Radius 7; Bild 34 × 22 Radius 4 (Streifen
#2A2D36/#30343E, 6 breit, 135°); Text senkrecht: Name 12/600, Zustand 10 Deckkraft 0,85.
Ausgewählt: Fläche `accent`, Text weiß; sonst transparent, `fg`.
Beispiele: Haustür „Klingel, Person, Paket“ · Einfahrt „Fahrzeug“ · Garage „Person“ · Garten „aus“.

## Detail (S2)
Innenabstand 16/22, Abstand 12, Schrift 13.
1. Kopf: „Haustür“ 16/700 links; rechts „G4 Doorbell Pro · Lautsprecher“ 11 `muted`.
2. „Auslöser“ 11/600 `muted`, Abstand 7; Chips umbrechend, linksbündig, Abstand 6:
   an: 12/600, Innenabstand 4/11, Kapsel `accent`, weiß;
   aus: 12, Innenabstand 3/10, Rand 1 `chipBorder`, Fläche `chipOff`;
   nicht möglich: 12, Innenabstand 3/10, Rand 1 gestrichelt `chipBorder`, Text `naFg`, durchgestrichen.
   Reihenfolge Beispiel: Klingel, Person, Paket (an) · Tier, Sprache, Glasbruch, Bewegung (aus) ·
   Fahrzeug (nicht möglich) – Regel: unterstützte in Anzeigereihenfolge, danach nicht unterstützte.
3. Karte Radius 9, Zeilen Innenabstand 8/12:
   - „Tastenkürzel“ | Tasten-Chip „⌥⌘1“ (12, Innenabstand 2/8, Radius 5, Rand 1 `chipBorder`, `field`)
   - „Hinweiston beim Öffnen“ | Schalter an
   - „Zoom und Ausschnitt merken“ | Schalter aus
4. „Buttons im Popup (max. 3)“ 11/600 `muted`, Abstand 6; Karte Radius 9:
   Zeilen Raster `1fr | 46 | 1.6fr | 44`, Abstand 8, Innenabstand 7/12, Schrift 12, Trennlinie:
   Titel 600 · Methoden-Badge 10/700 Innenabstand 2/5 Radius 4 `accSoft`/`accText` zentriert, füllt
   die 46er-Spalte · Adresse ohne Schema `muted`, gekürzt mit … · Link „Ändern“ `accText`.
   Beispiele: „Tür öffnen“ POST homeassistant.local/api/webhook/tuer-auf · „Licht an“ GET
   shelly-eingang.local/relay/0?turn=on. Danach Link „Button hinzufügen …“ Innenabstand 7/12, 12.
5. Freiraum, dann unten links „Erweitert“: Pfeil rechts 10 (Strich 2,8) + 5 + Text 12 `muted`.

## Erweitert aufgeklappt (S3)
Detail nach oben gescrollt, „Erweitert“ oben: Pfeil unten, 12/600 `fg`. Dann:
1. Karte Radius 9:
   - Innenabstand 10/12: „Zusätzlich per Webhook auslösen“ + darunter (2) „Für Alarm Manager,
     Home Assistant oder andere Systeme.“ 11 `muted` | Schalter an
   - Innenabstand 9/12: Beschriftung 110 breit „Webhook-ID“ | Eingabe „haustuer-klingel“
     (12, Innenabstand 4/7, Radius 5, Rand 1 `chipBorder`, `field`)
   - Innenabstand 9/12: „Aufruf-Adresse“ (110) | Adresse 12 `muted` gekürzt | Feld-Button „Kopieren“
2. Karte Radius 9:
   - 9/12: „Stream-Adresse“ (110) | Eingabe mit Platzhalter „automatisch aus Protect“
   - 8/12: „Nur ausfüllen, wenn der Stream nicht über die Protect-API kommen soll
     (rtsp://…:7447/…).“ 11, Zeilenhöhe 1,45, `muted`
3. Freiraum, Fußzeile: links Link „Webhook jetzt testen“ 12 `accText`; rechts „Zuletzt
   ausgelöst: heute, 10:12“ 11 `muted`.

## Sheet „Button bearbeiten“ (S4)
Breite 440 + Innenabstand 18/20 (gesamt 480), Fläche `win`, Abstand 11, Schrift 13.
1. „Button „Tür öffnen““ 15/700.
2. Raster 96 | Rest, Abstand 10, Zeilen mittig:
   - „Beschriftung“ | Eingabe 13, Innenabstand 5/8, Radius 6
   - „Symbol“ | 4 Kacheln 30 × 30 Radius 7 Abstand 6, Symbol 16 (Strich 1,8): Tür, Lampe,
     Haus, Blitz; gewählt `accent` + weiß, sonst `btn2` + `fg`
   - „Methode“ | Segment GET · POST, Breite 120 (+ 2×2), Segmente gleich breit, Innenabstand 3/0
   - „Adresse“ | Eingabe 12, 5/8, Radius 6
   - „Token“ | Passwortfeld 12, 5/8, Radius 6
   - leer | „Bearer-Token, liegt im Schlüsselbund. Optional.“ 11 `muted`
3. „Vor dem Ausführen nachfragen“ | Schalter an (Abstand 10).
4. Ergebnis: Häkchen 13 (Strich 2,4) + 6 + „Test erfolgreich · HTTP 200“, 12, Innenabstand 7/10,
   Radius 7, `okBg`/`ok`.
5. Zeile Abstand 8: „Testen“ | Freiraum | „Abbrechen“ | „Sichern“.
   Feld-Button 13, Innenabstand 5/12; „Sichern“ 13/600, Innenabstand 5/14, `accent`, weiß, ohne Rand.
```

### `docs/design/einstellungen-ton.md`

```markdown
# Einstellungen › Ton (Vorlage S5) – Gerüst in Phase 2

Kopf wie Allgemein, Titel „Ton & Sprechen“, Reiter „Ton“ aktiv.
Inhalt Innenabstand 14/40, Abstand 10, Schrift 13.
1. Abschnitt Abstand 5: „Ansagen für „Ton abspielen““ 11/600 `muted`. Karte Radius 10:
   Zeilen Abstand 10, Innenabstand 6/12, Trennlinie: Play-Knopf 22 rund `accSoft`, Dreieck 9
   (gefüllt) `accText` · Name 500 · Länge 11 `muted` tabellarisch · Badge 10/700 Innenabstand
   2/6 Radius 4 (MP3: `btn2`/`muted`; KI-STIMME: `accSoft`/`accText`). Ausgewählte Zeile Fläche `accSoft`.
   Zeilen: Gong 0:02 MP3 · Bin gleich da 0:03 KI-STIMME (ausgewählt) · Paket bitte abstellen 0:05 KI-STIMME.
   Danach Zeile Abstand 14, Innenabstand 6/12, 12: Links „MP3 hinzufügen …“ · „Ansage aus Text …“.
2. Editor-Karte: Abstand 8, Innenabstand 10/12, Radius 10, `group`, Rand 1 `accent`:
   - „„Bin gleich da““ 600 | Segment „MP3-Datei“ · „KI-Stimme“ (aktiv)
   - Eingabe „Bin gleich da! Einen kleinen Moment, bitte.“ 13, 5/8, Radius 6
   - Zeile Abstand 8: „Stimme“ 12 `muted` · Auswahl „Anna (Premium) · macOS“ · Freiraum ·
     „Anhören“ (Feld-Button 12, 3/10) · „Übernehmen“ (12/600, 3/10, `accent`, weiß)
   - „Wird auf diesem Mac erzeugt – ohne Internet, ohne Konto.“ 11 `muted`
3. Karte Radius 10, Zeilen 10/14:
   - „Mikrofon“ | Auswahl „MacBook Pro-Mikrofon“
   - „Sprechen“ | Segment „Leertaste halten“ (aktiv) · „Umschalten“
   - „Lautstärke an der Kamera“ | Regler: Spur 180 × 4 Radius 2 `toggleOff`, Füllung 120 `accent`,
     Knopf 16 weiß bei x 112, y −6, Schatten 0 1 3 rgba(0,0,0,.35)
Phase 2: nicht bedienbar, Werte sind die Beispiele der Vorlage.
```

### `docs/design/einstellungen-unterwegs.md`

```markdown
# Einstellungen › Unterwegs (Vorlage S6) – Gerüst in Phase 2

Kopf wie Allgemein, Titel „Unterwegs“, Reiter „Unterwegs“ aktiv.
Inhalt Innenabstand 20/40, Abstand 14, Schrift 13.
1. Statusfläche: Abstand 14, Innenabstand 14/16, Radius 12, `accSoft`. Kreis 40 `accent` mit
   Schild-Häkchen 20 (Strich 1,8) weiß · Text senkrecht Abstand 2: „Bereit · gerade zu Hause“
   14/700, „Der Tunnel springt an, sobald die Konsole nicht direkt erreichbar ist.“ 12 `muted`
   · Feld-Button „Jetzt testen“ (12, 4/12).
2. Karte Radius 10, Zeilen 10/14, Beschriftung 140 breit:
   „Konfiguration“ | „macbook-camera-popup.conf“ `muted` | „Ersetzen …“ ·
   „Gegenstelle“ | „[DEINE-HEIM-ADRESSE]:51820“ `muted` ·
   „Letzte Verbindung“ | „gestern, 18:22 · über Mobilfunk“ `muted` ·
   „Tunnel verwenden“ (füllt) | Auswahl „Automatisch“.
3. Zeile verteilt: Link „Anleitung: WireGuard auf dem UniFi-Gateway einrichten“ 12 `accText` ·
   Link „Tunnel entfernen“ 12 `muted`.
Phase 2: nicht bedienbar, Werte sind die Beispiele der Vorlage.
```

### `docs/design/popup.md`

```markdown
# Popup (Vorlage Main 8, „Popup aus B“)

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
   rgba(0,0,0,.3), Ring 1 `pillRing`. Phase 2: je Button des Nutzers ein Kreis 34 `pillBtn`
   mit Symbol 16 (Strich 1,8) `pillFg` (Tür/Lampe/Haus/Blitz), Tooltip = Titel.
   Ab Phase 3 zusätzlich „Ton abspielen“ (Kreis 34) und „Leertaste halten“ (40 hoch, 0/18,
   Radius 20, `accent`, 12/700, Mikrofon 16).
```

### `docs/design/menue.md`

```markdown
# Menüleisten-Panel (Vorlage Main 7)

Panel 310 + 2×14 (gesamt 338) breit, Radius 14, Fläche `win`, Ring 1 `mainBorder`, nativer
Schatten, Innenabstand 14, Abstand 10, Schrift 13. 8 unter der Menüleiste.
1. Kopf verteilt: „Camera Popup“ 14/700 · Chip „Zu Hause“ 11/600, Innenabstand 3/8, Kapsel,
   `okBg`/`ok`.
2. Ereignisse, Abstand 6; Zeile Abstand 10: Bild 54 × 34 Radius 6 (Streifen 8) · senkrecht
   „Klingel“ 12/600 und „Haustür“ 11 `muted` · Zeit „10:12“ 11 `muted` tabellarisch.
   Beispiele: Klingel/Haustür 10:12 · Fahrzeug/Einfahrt 09:47 · Person/Garage 08:30 (max. 3).
3. Abschnitt Abstand 6: „Alle Kameras stummschalten“ 11/600 `muted`; zwei Buttons gleich breit,
   Abstand 6: Lautsprecher-durchgestrichen 13 (Strich 2) + 5 + „15 Min.“ bzw. „1 Std.“,
   12/600, Innenabstand 6/0, Radius 7, `accSoft`/`accText`.
4. Trennlinie 1 `mainBorder`.
5. Zeile verteilt, 12: „Einstellungen …“ · „⌘,“ `muted`.
```

---

### Task 1: Package `AppCore` mit Stumm-Logik, Erscheinungsbild, Verlauf und Anzeigetexten

**Files:**
- Create: `Packages/AppCore/Package.swift`
- Create: `Packages/AppCore/Sources/AppCore/MuteDuration.swift`, `MuteSchedule.swift`, `AppearanceMode.swift`, `EventHistory.swift`, `DisplayText.swift`
- Test: `Packages/AppCore/Tests/AppCoreTests/MuteDurationTests.swift`, `MuteScheduleTests.swift`, `AppearanceModeTests.swift`, `EventHistoryTests.swift`, `DisplayTextTests.swift`
- Modify: `UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj` (lokales Package einbinden)
- Modify: `UniFiCameraPopup/Services/SettingsStore.swift:1-4` (`import AppCore`)

**Interfaces:**
- Produces:
  - `public struct MuteDuration: Codable, Hashable, Sendable` – `enum Unit { minutes, hours; var label: String }`, `static let allowedValues = 1...999`, `static let defaultShort` (15 min), `static let defaultLong` (1 h), `private(set) var value: Int`, `var unit: Unit`, `init(value:unit:)`, `var seconds: TimeInterval`, `var shortLabel: String` („15 Min.“), `var longLabel: String` („15 Minuten“/„1 Stunde“), `func withValue(_:) -> MuteDuration`, `static func parseValue(_: String) -> Int?`
  - `public struct MuteSchedule: Codable, Equatable, Sendable` – `struct CameraMute { entry: String; until: Date }`, `private(set) var globalUntil: Date?`, `private(set) var cameras: [String: Date]`, `static func migrated(stored:legacyGlobalUntil:)`, `func globalEnd(at:) -> Date?`, `func isGloballyMuted(at:) -> Bool`, `func cameraMuteEnd(entry:at:) -> Date?`, `func isMuted(entry:at:) -> Bool`, `func activeCameraMutes(at:) -> [CameraMute]`, `func nextExpiry(after:) -> Date?`, `mutating muteAll(for:from:)`, `mute(entry:for:from:)`, `clearGlobal()`, `clear(entry:)`, `clearAll()`, `prune(at:validEntries:)`
  - `public enum AppearanceMode: String, Codable, CaseIterable, Sendable { system, light, dark }` – `label`, `appearanceName: NSAppearance.Name?`
  - `public struct EventRecord: Codable, Equatable, Identifiable, Sendable` – `id: UUID`, `entryId: String`, `kindLabel: String?`, `cameraName: String`, `date: Date`, `title: String`; `public struct EventHistory` – `static let capacity = 20`, `records`, `record(_:)`, `latest(_:)`, `lastTriggered(entry:)`, `removeEntries(notIn:)`
  - `public enum DisplayText` – `popupChip(kind:camera:date:timeZone:)`, `time(_:timeZone:)`, `shortTime(_:now:timeZone:)`, `dayAndTime(_:now:timeZone:)`, `until(_:now:timeZone:)`, `cameraState(triggerLabels:webhook:mutedUntil:timeZone:)`, `actionAddress(_:)`
  - App kann `import AppCore`.

- [ ] **Step 1: Package anlegen**

`Packages/AppCore/Package.swift`:
```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AppCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AppCore", targets: ["AppCore"])
    ],
    targets: [
        .target(name: "AppCore"),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore"])
    ]
)
```

- [ ] **Step 2: Failing tests schreiben**

`Packages/AppCore/Tests/AppCoreTests/MuteDurationTests.swift`:
```swift
import XCTest
@testable import AppCore

final class MuteDurationTests: XCTestCase {
    func testDefaultsMatchTemplate() {
        XCTAssertEqual(MuteDuration.defaultShort.shortLabel, "15 Min.")
        XCTAssertEqual(MuteDuration.defaultLong.shortLabel, "1 Std.")
        XCTAssertEqual(MuteDuration.defaultShort.longLabel, "15 Minuten")
        XCTAssertEqual(MuteDuration.defaultLong.longLabel, "1 Stunde")
        XCTAssertEqual(MuteDuration.defaultShort.seconds, 900)
        XCTAssertEqual(MuteDuration.defaultLong.seconds, 3600)
        XCTAssertEqual(MuteDuration.Unit.minutes.label, "Minuten")
        XCTAssertEqual(MuteDuration.Unit.hours.label, "Stunden")
    }

    func testSingularAndPlural() {
        XCTAssertEqual(MuteDuration(value: 1, unit: .minutes).longLabel, "1 Minute")
        XCTAssertEqual(MuteDuration(value: 2, unit: .hours).longLabel, "2 Stunden")
        XCTAssertEqual(MuteDuration(value: 2, unit: .hours).shortLabel, "2 Std.")
    }

    func testValuesAreClamped() {
        XCTAssertEqual(MuteDuration(value: 0, unit: .minutes).value, 1)
        XCTAssertEqual(MuteDuration(value: -3, unit: .minutes).value, 1)
        XCTAssertEqual(MuteDuration(value: 5000, unit: .hours).value, 999)
        XCTAssertEqual(MuteDuration.defaultShort.withValue(30), MuteDuration(value: 30, unit: .minutes))
    }

    // Review Focus 4
    func testParseRejectsGarbageAndClamps() {
        XCTAssertNil(MuteDuration.parseValue(""))
        XCTAssertNil(MuteDuration.parseValue("   "))
        XCTAssertNil(MuteDuration.parseValue("12a"))
        XCTAssertNil(MuteDuration.parseValue("-5"))
        XCTAssertNil(MuteDuration.parseValue("١٢"))
        XCTAssertEqual(MuteDuration.parseValue(" 30 "), 30)
        XCTAssertEqual(MuteDuration.parseValue("0"), 1)
        XCTAssertEqual(MuteDuration.parseValue("5000"), 999)
        XCTAssertEqual(MuteDuration.parseValue("99999999999999999999999"), 999)
    }

    func testLenientDecodingAndRoundTrip() throws {
        let broken = try JSONDecoder().decode(MuteDuration.self, from: Data(#"{"value":0,"unit":"weeks"}"#.utf8))
        XCTAssertEqual(broken, MuteDuration(value: 1, unit: .minutes))
        let roundTrip = try JSONDecoder().decode(MuteDuration.self, from: JSONEncoder().encode(MuteDuration.defaultLong))
        XCTAssertEqual(roundTrip, .defaultLong)
    }
}
```

`Packages/AppCore/Tests/AppCoreTests/MuteScheduleTests.swift`:
```swift
import XCTest
@testable import AppCore

final class MuteScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testGlobalMuteCoversEveryCamera() {
        var schedule = MuteSchedule()
        schedule.muteAll(for: 900, from: now)
        XCTAssertTrue(schedule.isGloballyMuted(at: now.addingTimeInterval(899)))
        XCTAssertTrue(schedule.isMuted(entry: "A", at: now.addingTimeInterval(899)))
        XCTAssertFalse(schedule.isMuted(entry: "A", at: now.addingTimeInterval(900)))
        XCTAssertEqual(schedule.globalEnd(at: now), now.addingTimeInterval(900))
    }

    func testCameraMuteOnlyAffectsThatCamera() {
        var schedule = MuteSchedule()
        schedule.mute(entry: "A", for: 3600, from: now)
        XCTAssertTrue(schedule.isMuted(entry: "A", at: now.addingTimeInterval(60)))
        XCTAssertFalse(schedule.isMuted(entry: "B", at: now.addingTimeInterval(60)))
        XCTAssertFalse(schedule.isGloballyMuted(at: now))
        XCTAssertEqual(schedule.cameraMuteEnd(entry: "A", at: now), now.addingTimeInterval(3600))
        XCTAssertNil(schedule.cameraMuteEnd(entry: "B", at: now))
    }

    func testNewLengthReplacesOldMute() {
        var schedule = MuteSchedule()
        schedule.mute(entry: "A", for: 3600, from: now)
        schedule.mute(entry: "A", for: 900, from: now)
        XCTAssertEqual(schedule.cameraMuteEnd(entry: "A", at: now), now.addingTimeInterval(900))
    }

    // Review Focus 2
    func testSurvivesRestartAndExpiresWhileQuit() throws {
        var schedule = MuteSchedule()
        schedule.muteAll(for: 900, from: now)
        schedule.mute(entry: "A", for: 3600, from: now)

        let reloaded = try JSONDecoder().decode(MuteSchedule.self, from: JSONEncoder().encode(schedule))
        XCTAssertEqual(reloaded, schedule)
        XCTAssertTrue(reloaded.isMuted(entry: "B", at: now.addingTimeInterval(600)))

        let later = now.addingTimeInterval(7200)
        XCTAssertFalse(reloaded.isMuted(entry: "A", at: later))
        XCTAssertFalse(reloaded.isGloballyMuted(at: later))
        XCTAssertTrue(reloaded.activeCameraMutes(at: later).isEmpty)
        XCTAssertNil(reloaded.nextExpiry(after: later))

        var pruned = reloaded
        pruned.prune(at: later)
        XCTAssertEqual(pruned, MuteSchedule())
    }

    // Review Focus 3
    func testPruneDropsRemovedCameras() {
        var schedule = MuteSchedule()
        schedule.mute(entry: "A", for: 3600, from: now)
        schedule.mute(entry: "B", for: 3600, from: now)
        schedule.prune(at: now, validEntries: ["B"])
        XCTAssertEqual(schedule.activeCameraMutes(at: now).map(\.entry), ["B"])
    }

    func testActiveMutesSortedByEnd() {
        var schedule = MuteSchedule()
        schedule.mute(entry: "A", for: 3600, from: now)
        schedule.mute(entry: "B", for: 900, from: now)
        XCTAssertEqual(schedule.activeCameraMutes(at: now).map(\.entry), ["B", "A"])
    }

    func testNextExpiryIsEarliestFutureEnd() {
        var schedule = MuteSchedule()
        schedule.muteAll(for: 3600, from: now)
        schedule.mute(entry: "A", for: 900, from: now)
        XCTAssertEqual(schedule.nextExpiry(after: now), now.addingTimeInterval(900))
        XCTAssertEqual(schedule.nextExpiry(after: now.addingTimeInterval(1000)), now.addingTimeInterval(3600))
    }

    func testClearing() {
        var schedule = MuteSchedule()
        schedule.muteAll(for: 900, from: now)
        schedule.mute(entry: "A", for: 900, from: now)
        schedule.mute(entry: "B", for: 900, from: now)
        schedule.clear(entry: "A")
        XCTAssertFalse(schedule.cameras.keys.contains("A"))
        schedule.clearGlobal()
        XCTAssertNil(schedule.globalUntil)
        schedule.clearAll()
        XCTAssertEqual(schedule, MuteSchedule())
    }

    // Review Focus 1
    func testLegacyMigrationKeepsGlobalMute() throws {
        let legacyEnd = now.addingTimeInterval(600)
        XCTAssertEqual(MuteSchedule.migrated(stored: nil, legacyGlobalUntil: legacyEnd).globalUntil, legacyEnd)
        XCTAssertEqual(MuteSchedule.migrated(stored: nil, legacyGlobalUntil: nil), MuteSchedule())
        let stored = MuteSchedule(cameras: ["A": legacyEnd])
        XCTAssertEqual(MuteSchedule.migrated(stored: stored, legacyGlobalUntil: legacyEnd), stored)
        let broken = try JSONDecoder().decode(MuteSchedule.self, from: Data(#"{"globalUntil":"kaputt","cameras":7}"#.utf8))
        XCTAssertEqual(broken, MuteSchedule())
    }
}
```

`Packages/AppCore/Tests/AppCoreTests/AppearanceModeTests.swift`:
```swift
import AppKit
import XCTest
@testable import AppCore

final class AppearanceModeTests: XCTestCase {
    func testLabelsAndAppearanceNames() {
        XCTAssertEqual(AppearanceMode.allCases.map(\.label), ["System", "Hell", "Dunkel"])
        XCTAssertNil(AppearanceMode.system.appearanceName)
        XCTAssertEqual(AppearanceMode.light.appearanceName, .aqua)
        XCTAssertEqual(AppearanceMode.dark.appearanceName, .darkAqua)
    }

    // Review Focus 1
    func testUnknownValueFallsBackToSystem() throws {
        struct Box: Codable { let mode: AppearanceMode }
        let box = try JSONDecoder().decode(Box.self, from: Data(#"{"mode":"sepia"}"#.utf8))
        XCTAssertEqual(box.mode, .system)
        let roundTrip = try JSONDecoder().decode(Box.self, from: JSONEncoder().encode(Box(mode: .dark)))
        XCTAssertEqual(roundTrip.mode, .dark)
    }
}
```

`Packages/AppCore/Tests/AppCoreTests/EventHistoryTests.swift`:
```swift
import XCTest
@testable import AppCore

final class EventHistoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(_ entry: String, _ offset: TimeInterval, kind: String? = "Person") -> EventRecord {
        EventRecord(entryId: entry, kindLabel: kind, cameraName: "Haustür", date: now.addingTimeInterval(offset))
    }

    func testNewestFirstAndCapped() {
        var history = EventHistory()
        for index in 0..<25 { history.record(record("A", Double(index))) }
        XCTAssertEqual(history.records.count, EventHistory.capacity)
        XCTAssertEqual(history.latest(3).map(\.date), [24, 23, 22].map { now.addingTimeInterval($0) })
        XCTAssertEqual(history.latest(0), [])
    }

    func testOutOfOrderEventIsSortedIn() {
        var history = EventHistory()
        history.record(record("A", 10))
        history.record(record("B", 5))
        history.record(record("C", 20))
        XCTAssertEqual(history.records.map(\.entryId), ["C", "A", "B"])
    }

    func testLastTriggeredPerCamera() {
        var history = EventHistory()
        history.record(record("A", 10))
        history.record(record("B", 20))
        XCTAssertEqual(history.lastTriggered(entry: "A"), now.addingTimeInterval(10))
        XCTAssertNil(history.lastTriggered(entry: "C"))
    }

    // Review Focus 3
    func testRemoveEntries() {
        var history = EventHistory()
        history.record(record("A", 10))
        history.record(record("B", 20))
        history.removeEntries(notIn: ["B"])
        XCTAssertEqual(history.records.map(\.entryId), ["B"])
    }

    func testTitleFallsBackToWebhook() {
        XCTAssertEqual(record("A", 0, kind: "Klingel").title, "Klingel")
        XCTAssertEqual(record("A", 0, kind: nil).title, "Webhook")
    }

    func testCodableRoundTripAndLenientDecode() throws {
        var history = EventHistory()
        history.record(record("A", 10))
        let decoded = try JSONDecoder().decode(EventHistory.self, from: JSONEncoder().encode(history))
        XCTAssertEqual(decoded, history)
        let broken = try JSONDecoder().decode(EventHistory.self, from: Data(#"{"records":"x"}"#.utf8))
        XCTAssertEqual(broken, EventHistory())
    }
}
```

`Packages/AppCore/Tests/AppCoreTests/DisplayTextTests.swift`:
```swift
import XCTest
@testable import AppCore

final class DisplayTextTests: XCTestCase {
    private let tz = TimeZone(identifier: "Europe/Berlin")!

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    func testPopupChip() {
        let at = date("2026-10-18T10:41:00+02:00")
        XCTAssertEqual(DisplayText.popupChip(kind: "Klingel", camera: "Haustür", date: at, timeZone: tz), "Klingel · Haustür · 10:41")
    }

    // Review Focus 5
    func testPopupChipWithoutKindOrName() {
        let at = date("2026-10-18T10:41:00+02:00")
        XCTAssertEqual(DisplayText.popupChip(kind: nil, camera: "Haustür", date: at, timeZone: tz), "Haustür · 10:41")
        XCTAssertEqual(DisplayText.popupChip(kind: " ", camera: " Garage ", date: at, timeZone: tz), "Garage · 10:41")
        XCTAssertEqual(DisplayText.popupChip(kind: nil, camera: "  ", date: at, timeZone: tz), "Kamera · 10:41")
    }

    func testDayAndTime() {
        let now = date("2026-10-18T12:00:00+02:00")
        XCTAssertEqual(DisplayText.dayAndTime(date("2026-10-18T10:12:00+02:00"), now: now, timeZone: tz), "heute, 10:12")
        XCTAssertEqual(DisplayText.dayAndTime(date("2026-10-17T18:22:00+02:00"), now: now, timeZone: tz), "gestern, 18:22")
        XCTAssertEqual(DisplayText.dayAndTime(date("2026-10-12T09:30:00+02:00"), now: now, timeZone: tz), "12.10., 09:30")
    }

    func testShortTime() {
        let now = date("2026-10-18T12:00:00+02:00")
        XCTAssertEqual(DisplayText.shortTime(date("2026-10-18T10:12:00+02:00"), now: now, timeZone: tz), "10:12")
        XCTAssertEqual(DisplayText.shortTime(date("2026-10-17T18:22:00+02:00"), now: now, timeZone: tz), "gestern")
        XCTAssertEqual(DisplayText.shortTime(date("2026-10-12T09:30:00+02:00"), now: now, timeZone: tz), "12.10.")
    }

    func testUntil() {
        let now = date("2026-10-18T10:41:00+02:00")
        XCTAssertEqual(DisplayText.until(date("2026-10-18T10:56:00+02:00"), now: now, timeZone: tz), "bis 10:56")
        XCTAssertEqual(DisplayText.until(date("2026-10-19T09:00:00+02:00"), now: now, timeZone: tz), "bis morgen, 09:00")
        XCTAssertEqual(DisplayText.until(date("2026-10-20T09:00:00+02:00"), now: now, timeZone: tz), "bis 20.10., 09:00")
    }

    func testCameraState() {
        let muted = date("2026-10-18T10:56:00+02:00")
        XCTAssertEqual(DisplayText.cameraState(triggerLabels: ["Klingel", "Person", "Paket"], webhook: false, mutedUntil: nil, timeZone: tz), "Klingel, Person, Paket")
        XCTAssertEqual(DisplayText.cameraState(triggerLabels: [], webhook: false, mutedUntil: nil, timeZone: tz), "aus")
        XCTAssertEqual(DisplayText.cameraState(triggerLabels: [], webhook: true, mutedUntil: nil, timeZone: tz), "Webhook")
        XCTAssertEqual(DisplayText.cameraState(triggerLabels: ["Fahrzeug"], webhook: true, mutedUntil: nil, timeZone: tz), "Fahrzeug, Webhook")
        XCTAssertEqual(DisplayText.cameraState(triggerLabels: ["Person"], webhook: false, mutedUntil: muted, timeZone: tz), "stumm bis 10:56")
    }

    func testActionAddress() {
        XCTAssertEqual(DisplayText.actionAddress("https://homeassistant.local/api/webhook/tuer-auf"), "homeassistant.local/api/webhook/tuer-auf")
        XCTAssertEqual(DisplayText.actionAddress("HTTP://shelly-eingang.local/relay/0?turn=on"), "shelly-eingang.local/relay/0?turn=on")
        XCTAssertEqual(DisplayText.actionAddress("  ftp://x  "), "ftp://x")
    }
}
```

- [ ] **Step 3: Tests laufen lassen, Fehlschlag prüfen**

Run: `(cd Packages/AppCore && swift test 2>&1 | tail -5)`
Expected: FAIL – Kompilierfehler „cannot find 'MuteDuration' in scope“ (Quellen fehlen noch).

- [ ] **Step 4: Implementierung schreiben**

`Packages/AppCore/Sources/AppCore/MuteDuration.swift`:
```swift
import Foundation

/// One offered mute length ("Kurz" / "Lang" in Einstellungen › Allgemein).
public struct MuteDuration: Codable, Hashable, Sendable {
    public enum Unit: String, Codable, CaseIterable, Sendable {
        case minutes
        case hours

        /// Unit label of the settings field. Always plural, as in the template ("1" + "Stunden").
        public var label: String {
            switch self {
            case .minutes: return "Minuten"
            case .hours: return "Stunden"
            }
        }
    }

    public static let allowedValues = 1...999
    public static let defaultShort = MuteDuration(value: 15, unit: .minutes)
    public static let defaultLong = MuteDuration(value: 1, unit: .hours)

    public private(set) var value: Int
    public var unit: Unit

    public init(value: Int, unit: Unit) {
        self.value = Self.clamped(value)
        self.unit = unit
    }

    private enum CodingKeys: String, CodingKey { case value, unit }

    /// Lenient: a broken or out-of-range value never fails the whole settings file.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = (try? container.decode(Int.self, forKey: .value)) ?? 15
        let unit = (try? container.decode(Unit.self, forKey: .unit)) ?? .minutes
        self.init(value: value, unit: unit)
    }

    public var seconds: TimeInterval {
        TimeInterval(value) * (unit == .minutes ? 60 : 3600)
    }

    /// Menu buttons: "15 Min.", "1 Std."
    public var shortLabel: String {
        "\(value) \(unit == .minutes ? "Min." : "Std.")"
    }

    /// Popup mute menu: "15 Minuten", "1 Minute", "1 Stunde", "2 Stunden".
    public var longLabel: String {
        switch unit {
        case .minutes: return value == 1 ? "1 Minute" : "\(value) Minuten"
        case .hours: return value == 1 ? "1 Stunde" : "\(value) Stunden"
        }
    }

    public func withValue(_ newValue: Int) -> MuteDuration {
        MuteDuration(value: newValue, unit: unit)
    }

    /// Text field input → value within `allowedValues`. nil for empty or non-numeric input;
    /// the field then keeps its previous value.
    public static func parseValue(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return clamped(Int(trimmed) ?? allowedValues.upperBound)
    }

    static func clamped(_ value: Int) -> Int {
        min(max(value, allowedValues.lowerBound), allowedValues.upperBound)
    }
}
```

`Packages/AppCore/Sources/AppCore/MuteSchedule.swift`:
```swift
import Foundation

/// Global and per-camera mutes. Ends are absolute dates, so a mute survives an app restart
/// and an end that passed while the app was quit simply no longer counts.
public struct MuteSchedule: Codable, Equatable, Sendable {
    public struct CameraMute: Equatable, Sendable {
        public let entry: String
        public let until: Date
    }

    public private(set) var globalUntil: Date?
    /// Mapping entry id (UUID string) → end of that camera's mute.
    public private(set) var cameras: [String: Date]

    public init(globalUntil: Date? = nil, cameras: [String: Date] = [:]) {
        self.globalUntil = globalUntil
        self.cameras = cameras
    }

    private enum CodingKeys: String, CodingKey { case globalUntil, cameras }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        globalUntil = (try? container.decodeIfPresent(Date.self, forKey: .globalUntil)) ?? nil
        cameras = (try? container.decodeIfPresent([String: Date].self, forKey: .cameras)) ?? [:]
    }

    /// Settings written before per-camera muting only stored a global `muteUntil`.
    public static func migrated(stored: MuteSchedule?, legacyGlobalUntil: Date?) -> MuteSchedule {
        stored ?? MuteSchedule(globalUntil: legacyGlobalUntil)
    }

    public func globalEnd(at now: Date) -> Date? {
        guard let globalUntil, globalUntil > now else { return nil }
        return globalUntil
    }

    public func isGloballyMuted(at now: Date) -> Bool {
        globalEnd(at: now) != nil
    }

    public func cameraMuteEnd(entry: String, at now: Date) -> Date? {
        guard let end = cameras[entry], end > now else { return nil }
        return end
    }

    /// True when the camera must not open a popup: muted on its own or globally.
    public func isMuted(entry: String, at now: Date) -> Bool {
        isGloballyMuted(at: now) || cameraMuteEnd(entry: entry, at: now) != nil
    }

    /// Active per-camera mutes, the one ending first first.
    public func activeCameraMutes(at now: Date) -> [CameraMute] {
        cameras
            .filter { $0.value > now }
            .map { CameraMute(entry: $0.key, until: $0.value) }
            .sorted { ($0.until, $0.entry) < ($1.until, $1.entry) }
    }

    /// The next moment a mute ends (refreshes the menu bar icon and menu).
    public func nextExpiry(after now: Date) -> Date? {
        (Array(cameras.values) + [globalUntil].compactMap { $0 })
            .filter { $0 > now }
            .min()
    }

    public mutating func muteAll(for seconds: TimeInterval, from now: Date) {
        globalUntil = now.addingTimeInterval(seconds)
    }

    /// Replaces an existing mute of that camera (the user picked a new length).
    public mutating func mute(entry: String, for seconds: TimeInterval, from now: Date) {
        cameras[entry] = now.addingTimeInterval(seconds)
    }

    public mutating func clearGlobal() {
        globalUntil = nil
    }

    public mutating func clear(entry: String) {
        cameras[entry] = nil
    }

    public mutating func clearAll() {
        globalUntil = nil
        cameras = [:]
    }

    /// Drops ended mutes and, when `validEntries` is given, mutes of removed cameras.
    public mutating func prune(at now: Date, validEntries: Set<String>? = nil) {
        if let globalUntil, globalUntil <= now {
            self.globalUntil = nil
        }
        cameras = cameras.filter { entry, end in
            end > now && (validEntries?.contains(entry) ?? true)
        }
    }
}
```

`Packages/AppCore/Sources/AppCore/AppearanceMode.swift`:
```swift
import AppKit

/// "Erscheinungsbild" in Einstellungen › Allgemein.
public enum AppearanceMode: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark

    /// Segment titles, in template order.
    public var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Hell"
        case .dark: return "Dunkel"
        }
    }

    /// Value for `NSApp.appearance`; nil follows the system.
    public var appearanceName: NSAppearance.Name? {
        switch self {
        case .system: return nil
        case .light: return .aqua
        case .dark: return .darkAqua
        }
    }

    /// Unknown values (written by a newer build) fall back to `.system`
    /// instead of failing the whole settings file.
    public init(from decoder: Decoder) throws {
        let raw = try? decoder.singleValueContainer().decode(String.self)
        self = raw.flatMap(AppearanceMode.init(rawValue:)) ?? .system
    }
}
```

`Packages/AppCore/Sources/AppCore/EventHistory.swift`:
```swift
import Foundation

/// One popup trigger as shown in the menu panel ("Klingel / Haustür / 10:12").
public struct EventRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    /// Mapping entry id (UUID string).
    public let entryId: String
    /// "Klingel", "Person" …; nil for webhook triggers.
    public let kindLabel: String?
    public let cameraName: String
    public let date: Date

    public init(id: UUID = UUID(), entryId: String, kindLabel: String?, cameraName: String, date: Date) {
        self.id = id
        self.entryId = entryId
        self.kindLabel = kindLabel
        self.cameraName = cameraName
        self.date = date
    }

    /// First line in the menu panel.
    public var title: String {
        kindLabel ?? "Webhook"
    }
}

/// The most recent triggers, newest first, capped at `capacity`.
public struct EventHistory: Codable, Equatable, Sendable {
    public static let capacity = 20

    public private(set) var records: [EventRecord]

    public init(records: [EventRecord] = []) {
        self.records = Array(records.sorted { $0.date > $1.date }.prefix(Self.capacity))
    }

    private enum CodingKeys: String, CodingKey { case records }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let records = (try? container.decodeIfPresent([EventRecord].self, forKey: .records)) ?? []
        self.init(records: records)
    }

    public mutating func record(_ record: EventRecord) {
        let index = records.firstIndex { $0.date <= record.date } ?? records.endIndex
        records.insert(record, at: index)
        if records.count > Self.capacity {
            records.removeLast(records.count - Self.capacity)
        }
    }

    public func latest(_ count: Int) -> [EventRecord] {
        Array(records.prefix(max(count, 0)))
    }

    public func lastTriggered(entry: String) -> Date? {
        records.first { $0.entryId == entry }?.date
    }

    public mutating func removeEntries(notIn validEntries: Set<String>) {
        records.removeAll { !validEntries.contains($0.entryId) }
    }
}
```

`Packages/AppCore/Sources/AppCore/DisplayText.swift`:
```swift
import Foundation

/// German UI strings built from data, kept here so they are testable.
public enum DisplayText {
    private static let locale = Locale(identifier: "de_DE")

    private static func formatter(_ format: String, _ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }

    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// "10:41"
    public static func time(_ date: Date, timeZone: TimeZone = .current) -> String {
        formatter("HH:mm", timeZone).string(from: date)
    }

    /// Popup chip: "Klingel · Haustür · 10:41"; without a kind "Haustür · 10:41";
    /// without a name "Kamera · 10:41".
    public static func popupChip(kind: String?, camera: String, date: Date, timeZone: TimeZone = .current) -> String {
        let name = camera.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKind = kind?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [
            trimmedKind?.isEmpty == false ? trimmedKind : nil,
            name.isEmpty ? "Kamera" : name,
            time(date, timeZone: timeZone),
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    /// Menu panel event time: "10:12" today, "gestern", otherwise "12.10.".
    public static func shortTime(_ date: Date, now: Date, timeZone: TimeZone = .current) -> String {
        let calendar = calendar(timeZone)
        if calendar.isDate(date, inSameDayAs: now) { return time(date, timeZone: timeZone) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "gestern"
        }
        return formatter("dd.MM.", timeZone).string(from: date)
    }

    /// "Zuletzt ausgelöst": "heute, 10:12" · "gestern, 18:22" · "12.10., 09:30".
    public static func dayAndTime(_ date: Date, now: Date, timeZone: TimeZone = .current) -> String {
        let calendar = calendar(timeZone)
        let clock = time(date, timeZone: timeZone)
        if calendar.isDate(date, inSameDayAs: now) { return "heute, \(clock)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "gestern, \(clock)"
        }
        return "\(formatter("dd.MM.", timeZone).string(from: date)), \(clock)"
    }

    /// Mute end: "bis 10:56" · "bis morgen, 09:00" · "bis 20.10., 09:00".
    public static func until(_ date: Date, now: Date, timeZone: TimeZone = .current) -> String {
        let calendar = calendar(timeZone)
        let clock = time(date, timeZone: timeZone)
        if calendar.isDate(date, inSameDayAs: now) { return "bis \(clock)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "bis morgen, \(clock)"
        }
        return "bis \(formatter("dd.MM.", timeZone).string(from: date)), \(clock)"
    }

    /// Second line of a camera in the Kameras sidebar.
    public static func cameraState(
        triggerLabels: [String],
        webhook: Bool,
        mutedUntil: Date?,
        timeZone: TimeZone = .current
    ) -> String {
        if let mutedUntil { return "stumm bis \(time(mutedUntil, timeZone: timeZone))" }
        var parts = triggerLabels
        if webhook { parts.append("Webhook") }
        return parts.isEmpty ? "aus" : parts.joined(separator: ", ")
    }

    /// Action rows show the address without scheme.
    public static func actionAddress(_ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        for scheme in ["https://", "http://"] where trimmed.lowercased().hasPrefix(scheme) {
            return String(trimmed.dropFirst(scheme.count))
        }
        return trimmed
    }
}
```

- [ ] **Step 5: Tests laufen lassen**

Run: `(cd Packages/AppCore && swift test 2>&1 | tail -5)`
Expected: PASS, „Executed 29 tests, with 0 failures“.

- [ ] **Step 6: Package ins Xcode-Projekt einbinden**

Vorher `grep -c "A10000000000000000000070\|AB0000000000000000000002\|A50000000000000000000003" UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj` → `0`.

In `UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj`:
1. In `/* Begin PBXBuildFile section */` nach der ProtectKit-Zeile:
```
		A10000000000000000000070 /* AppCore in Frameworks */ = {isa = PBXBuildFile; productRef = A50000000000000000000003 /* AppCore */; };
```
2. In der Frameworks-Phase `A30000000000000000000001` nach `A10000000000000000000015 /* ProtectKit in Frameworks */,`:
```
				A10000000000000000000070 /* AppCore in Frameworks */,
```
3. Im Target unter `packageProductDependencies = (` nach `A50000000000000000000002 /* ProtectKit */,`:
```
				A50000000000000000000003 /* AppCore */,
```
4. Im Projekt unter `packageReferences = (` nach der ProtectKit-Zeile:
```
				AB0000000000000000000002 /* XCLocalSwiftPackageReference "../Packages/AppCore" */,
```
5. In `/* Begin XCLocalSwiftPackageReference section */` nach dem ProtectKit-Eintrag:
```
		AB0000000000000000000002 /* XCLocalSwiftPackageReference "../Packages/AppCore" */ = {
			isa = XCLocalSwiftPackageReference;
			relativePath = ../Packages/AppCore;
		};
```
6. In `/* Begin XCSwiftPackageProductDependency section */` nach dem ProtectKit-Eintrag:
```
		A50000000000000000000003 /* AppCore */ = {
			isa = XCSwiftPackageProductDependency;
			productName = AppCore;
		};
```

In `UniFiCameraPopup/Services/SettingsStore.swift` die Importe ergänzen (Linker-Nachweis; die Nutzung folgt in Task 4):
```swift
import AppCore
import Combine
import Foundation
import ProtectKit
import ServiceManagement
```

- [ ] **Step 7: Lint und Build**

Run: `plutil -lint UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj` → `OK`
Run: Build-Befehl aus „Global Constraints“
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add Packages/AppCore UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj UniFiCameraPopup/Services/SettingsStore.swift
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "feat(core): AppCore package with mute schedule, durations, appearance and display texts" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: ProtectKit-Ergänzungen und Phase-1-Reste

**Files:**
- Modify: `Packages/ProtectKit/Sources/ProtectKit/TriggerKind.swift` (Anzeigereihenfolge, Chips)
- Modify: `Packages/ProtectKit/Sources/ProtectKit/ProtectClient.swift:128-163` (`sendRaw`, `snapshot`)
- Modify: `Packages/ProtectKit/Sources/ProtectKit/Discovery.swift:131-164` (`ConsoleProbe.probe`/`decide`)
- Modify: `UniFiCameraPopup/Views/Onboarding/OnboardingView.swift:221` (kanonische Adresse im Hinweis)
- Test: `Packages/ProtectKit/Tests/ProtectKitTests/TriggerKindTests.swift`, `ProtectClientTests.swift`, `DiscoveryTests.swift`

**Interfaces:**
- Produces:
  - `TriggerKind.displayOrder: [TriggerKind]`, `TriggerKind.alwaysShown: Set<TriggerKind>`, `public struct TriggerChipItem: Equatable, Sendable { kind: TriggerKind; isSupported: Bool }`, `TriggerKind.chips(supported: Set<TriggerKind>) -> [TriggerChipItem]`
  - `ProtectClient.snapshot(cameraId: String) async throws -> Data`
  - `ConsoleProbe.decide(systemStatus: Int?, systemData: Data?, metaStatus: Int?, candidate: DiscoveredConsole) -> DiscoveredConsole?` (intern, `@testable`)

- [ ] **Step 1: Failing tests schreiben**

An `Packages/ProtectKit/Tests/ProtectKitTests/TriggerKindTests.swift` (in der Klasse `TriggerKindTests`) anhängen:
```swift
    func testChipsFollowTemplateOrder() {
        let doorbell: Set<TriggerKind> = [.ring, .person, .package, .animal, .speak, .glassBreak, .motion]
        let chips = TriggerKind.chips(supported: doorbell)
        XCTAssertEqual(chips.map { $0.kind.label },
                       ["Klingel", "Person", "Paket", "Tier", "Sprache", "Glasbruch", "Bewegung", "Fahrzeug"])
        XCTAssertEqual(chips.map { $0.isSupported }, [true, true, true, true, true, true, true, false])
    }

    func testChipsAlwaysOfferCoreKinds() {
        let chips = TriggerKind.chips(supported: [.motion])
        XCTAssertEqual(chips.map { $0.kind }, [.motion, .ring, .person, .package, .animal, .vehicle])
        XCTAssertEqual(chips.filter { $0.isSupported }.map { $0.kind }, [.motion])
    }

    func testDisplayOrderCoversAllKindsOnce() {
        XCTAssertEqual(TriggerKind.displayOrder.count, TriggerKind.allCases.count)
        XCTAssertEqual(Set(TriggerKind.displayOrder), Set(TriggerKind.allCases))
    }
```

An `ProtectClientTests.swift` (in der Klasse) anhängen:
```swift
    func testSnapshotReturnsImageBytesAndSendsKey() async throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
        StubProtocol.responses["GET \(base)/cameras/cam1/snapshot"] = (200, jpeg)
        let data = try await client().snapshot(cameraId: "cam1")
        XCTAssertEqual(data, jpeg)
        XCTAssertEqual(StubProtocol.requests.last?.value(forHTTPHeaderField: "X-API-KEY"), "KEY")
    }

    func testSnapshotUnauthorized() async {
        StubProtocol.responses["GET \(base)/cameras/cam1/snapshot"] = (401, Data())
        do {
            _ = try await client().snapshot(cameraId: "cam1")
            XCTFail("401 must throw")
        } catch {
            XCTAssertEqual(error as? ProtectError, .unauthorized)
        }
    }
```

An `DiscoveryTests.swift` (in der Klasse) anhängen:
```swift
    func testProbeFallsBackToProtectEndpointWhenSystemNeedsLogin() throws {
        let candidate = DiscoveredConsole(ip: "10.0.0.1", mac: "aa:bb:cc:00:00:01", hostname: "UDM", model: nil)
        let console = try XCTUnwrap(ConsoleProbe.decide(systemStatus: 401, systemData: Data(), metaStatus: 401, candidate: candidate))
        XCTAssertEqual(console.ip, "10.0.0.1")
        XCTAssertEqual(console.displayName, "UDM")
        XCTAssertNotNil(ConsoleProbe.decide(systemStatus: 403, systemData: nil, metaStatus: 401, candidate: candidate))
    }

    func testProbeFallbackNeedsBothSignals() {
        let candidate = DiscoveredConsole(ip: "10.0.0.2", mac: nil, hostname: nil, model: "UVC G4 Bullet")
        XCTAssertNil(ConsoleProbe.decide(systemStatus: 401, systemData: Data(), metaStatus: 404, candidate: candidate))
        XCTAssertNil(ConsoleProbe.decide(systemStatus: 404, systemData: nil, metaStatus: 401, candidate: candidate))
        XCTAssertNil(ConsoleProbe.decide(systemStatus: 401, systemData: nil, metaStatus: nil, candidate: candidate))
        XCTAssertNil(ConsoleProbe.decide(systemStatus: nil, systemData: nil, metaStatus: nil, candidate: candidate))
    }

    func testProbeStillParsesSystemInfo() throws {
        let json = Data(#"{"hardware":{"shortname":"UDMPROSE"},"name":"snackbits","mac":"70A741B5EF8D"}"#.utf8)
        let candidate = DiscoveredConsole(ip: "172.2.4.1", mac: nil, hostname: nil, model: nil)
        let console = try XCTUnwrap(ConsoleProbe.decide(systemStatus: 200, systemData: json, metaStatus: nil, candidate: candidate))
        XCTAssertEqual(console.displayName, "snackbits (UDMPROSE)")
    }
```

- [ ] **Step 2: Tests laufen lassen, Fehlschlag prüfen**

Run: `(cd Packages/ProtectKit && swift test 2>&1 | tail -5)`
Expected: FAIL – „type 'TriggerKind' has no member 'chips'“ u. ä.

- [ ] **Step 3: TriggerKind ergänzen**

In `TriggerKind.swift` vor `/// Maps Protect smartDetectTypes …` einfügen:
```swift
    /// Chip order in settings and onboarding (template): specific detections first, motion last.
    public static let displayOrder: [TriggerKind] = [
        .ring, .person, .package, .animal, .vehicle, .licensePlate, .face,
        .speak, .bark, .babyCry, .glassBreak, .smoke, .carbonMonoxide, .siren, .carHorn, .burglar,
        .motion,
    ]

    /// Offered even when a camera cannot detect them (shown struck through).
    public static let alwaysShown: Set<TriggerKind> = [.ring, .person, .package, .animal, .vehicle]

    /// Chips for one camera: supported kinds in display order, then the unsupported core kinds.
    /// The order depends only on the camera, so chips never jump when toggled.
    public static func chips(supported: Set<TriggerKind>) -> [TriggerChipItem] {
        let shown = displayOrder.filter { supported.contains($0) || alwaysShown.contains($0) }
        return shown.filter { supported.contains($0) }.map { TriggerChipItem(kind: $0, isSupported: true) }
            + shown.filter { !supported.contains($0) }.map { TriggerChipItem(kind: $0, isSupported: false) }
    }
```
und am Dateiende:
```swift
public struct TriggerChipItem: Equatable, Sendable {
    public let kind: TriggerKind
    public let isSupported: Bool
}
```

- [ ] **Step 4: Schnappschuss im Client**

In `ProtectClient.swift` nach `rtspURL(cameraId:)` einfügen:
```swift
    /// Current still image of a camera (JPEG). Used for thumbnails in settings and the menu panel.
    public func snapshot(cameraId: String) async throws -> Data {
        try await sendRaw("GET", "/v1/cameras/\(cameraId)/snapshot", body: nil, accept: "image/jpeg")
    }
```
Die bestehende Funktion `send<T: Decodable>(_:_:body:)` (Zeilen 132–163) ersetzen durch:
```swift
    private func send<T: Decodable>(_ method: String, _ path: String, body: Data?) async throws -> T {
        let data = try await sendRaw(method, path, body: body, accept: "application/json")
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw ProtectError.decoding }
    }

    private func sendRaw(_ method: String, _ path: String, body: Data?, accept: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(String(path.dropFirst())))
        request.httpMethod = method
        if !apiKey.isEmpty { request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY") }
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // Creating a task on an invalidated session raises an NSException, so fail early.
        if lock.withLock({ isInvalidated }) { throw ProtectError.unreachable("Verbindung beendet") }

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
        case 200..<300: return data
        case 401, 403: throw ProtectError.unauthorized
        default: throw ProtectError.http(http.statusCode)
        }
    }
```

- [ ] **Step 5: Konsolensuche mit 401-Fallback**

In `Discovery.swift` die Funktion `ConsoleProbe.probe(_:)` (Zeilen 135–146) ersetzen durch:
```swift
    static func probe(_ candidate: DiscoveredConsole) async -> DiscoveredConsole? {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.httpCookieStorage = nil
        let delegate = AcceptAnyCertificate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let system = await fetch(session, "https://\(candidate.ip)/api/system")
        var metaStatus: Int?
        if let status = system?.status, status == 401 || status == 403 {
            // No API key is sent: a Protect console answers its integration endpoint with 401.
            metaStatus = await fetch(session, "https://\(candidate.ip)/proxy/protect/integration/v1/meta/info")?.status
        }
        return decide(systemStatus: system?.status, systemData: system?.data, metaStatus: metaStatus, candidate: candidate)
    }

    /// `/api/system` answered → parse it. Some consoles want a login there (401/403); then a 401
    /// from the Protect integration endpoint (requested without key) proves a Protect console.
    static func decide(systemStatus: Int?, systemData: Data?, metaStatus: Int?, candidate: DiscoveredConsole) -> DiscoveredConsole? {
        if systemStatus == 200, let systemData {
            return parse(systemData, candidate: candidate)
        }
        if let systemStatus, systemStatus == 401 || systemStatus == 403, metaStatus == 401 {
            return DiscoveredConsole(ip: candidate.ip, mac: candidate.mac, hostname: candidate.hostname, model: candidate.model)
        }
        return nil
    }

    private static func fetch(_ session: URLSession, _ address: String) async -> (status: Int, data: Data)? {
        guard let url = URL(string: address),
              let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse else { return nil }
        return (http.statusCode, data)
    }
```

- [ ] **Step 6: Tests laufen lassen**

Run: `(cd Packages/ProtectKit && swift test 2>&1 | tail -5)`
Expected: PASS, 0 failures.

- [ ] **Step 7: Geparkt aus Phase 1 – kanonische Adresse im Hinweis „andere Konsole“**

In `UniFiCameraPopup/Views/Onboarding/OnboardingView.swift` Zeile 221:
```swift
                Text("„\(model.host)“ ist eine andere Konsole als die bisher eingerichtete. …
```
ersetzen durch (Rest des Satzes unverändert):
```swift
                Text("„\(model.canonicalHost ?? model.host)“ ist eine andere Konsole als die bisher eingerichtete. Bestätige nur, wenn das wirklich deine Konsole ist – erst dann wird dein API-Schlüssel dorthin gesendet. Fingerabdruck der neuen Konsole:\n\n\(model.pendingFingerprint ?? "")")
```

- [ ] **Step 8: Build**

Run: Build-Befehl. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 9: Commit**

```bash
git add Packages/ProtectKit UniFiCameraPopup/Views/Onboarding/OnboardingView.swift
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "feat(protect): trigger chip order, camera snapshots, console probe fallback; canonical host in trust alert" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Design-Grundlagen – Spezifikation, Tokens, Symbole, Bausteine

**Files:**
- Create: `docs/design/tokens.md`, `einstellungen-allgemein.md`, `einstellungen-kameras.md`, `einstellungen-ton.md`, `einstellungen-unterwegs.md`, `popup.md`, `menue.md`
- Create: `Packages/AppCore/Sources/AppCore/DesignTokens.swift`; Test: `Packages/AppCore/Tests/AppCoreTests/DesignTokensTests.swift`
- Create: `UniFiCameraPopup/Assets.xcassets/Icons/` (17 Image-Sets, SVG)
- Create: `UniFiCameraPopup/Views/Design/DesignComponents.swift`, `UniFiCameraPopup/Views/Design/PopUpField.swift`
- Modify: `project.pbxproj` (Gruppe Design, zwei Dateien)

**Interfaces:**
- Consumes: nichts aus früheren Tasks außer `AppCore` (Task 1).
- Produces:
  - AppCore: `public struct RGBA` (`init(_ hex: UInt32, alpha: Double = 1)`, `nsColor`), `public struct ThemeColor` (`light`, `dark`, `init(_:_:)`, `init(light:dark:)`, `static func fixed(_:)`, `nsColor`, `color`), `public enum Tokens` (alle Tokens aus `tokens.md`, Namen exakt wie dort, plus `overlay`, `white`, `statusGreen`, `stripeA`, `stripeB`, `popupRing`)
  - App: `enum TemplateIcon: String` (`tabGeneral, tabCameras, tabSound, tabRemote, chevronUpDown, chevronRight, chevronDown, close, bellSlash, speakerMute, check, play, shieldCheck, actionDoor, actionBulb, actionHouse, actionBolt`; `image(size:) -> some View`, `nsImage(size:) -> NSImage?`)
  - App: `Card(radius:content:)`, `CardDivider()`, `CardRow(title:vertical:horizontal:trailing:)`, `CardToggleRow(title:subtitle:isOn:vertical:horizontal:)`, `FixedLabelRow(title:width:vertical:horizontal:content:)`, `FormLine(label:content:)`, `SectionLabel(text:)`, `FieldButtonStyle(fontSize:vertical:horizontal:)`, `AccentButtonStyle(fontSize:vertical:horizontal:)`, `SoftButtonStyle()`, `LinkButtonStyle(color:fontSize:)`, `TokenSwitch(isOn:label:)`, `TokenSegmented(selection:options:width:)`, `TokenTextField(placeholder:text:fontSize:vertical:horizontal:radius:secure:)`, `DurationField(duration:accessibilityLabel:)`, `DisclosureButton(title:expanded:)`, `StripePlaceholder(band:)`, `VolumeTrack()`
  - App: `PopUpField(selection:options:)`, `MenuPresenter.popUp(titles:selectedIndex:in:onSelect:)`, `ViewAnchor`, `AnchorView`

- [ ] **Step 1: Design-Spezifikation ablegen**

`mkdir -p docs/design` und den Inhalt jedes Codeblocks aus dem Abschnitt „Design-Spezifikation“ dieses Plans unverändert (ohne die umschließenden ```-Zeilen) in die gleichnamige Datei schreiben: `docs/design/tokens.md`, `docs/design/einstellungen-allgemein.md`, `docs/design/einstellungen-kameras.md`, `docs/design/einstellungen-ton.md`, `docs/design/einstellungen-unterwegs.md`, `docs/design/popup.md`, `docs/design/menue.md`.

Danach einmal gegen die Vorlage gegenlesen: `grep -o 'padding: [0-9]*px [0-9]*px' docs/superpowers/specs/phase2-4/design/Einstellungen.dc.html | sort | uniq -c` – jede dort vorkommende Kombination muss in den Spezifikationen auftauchen.

- [ ] **Step 2: Failing test für Tokens**

`Packages/AppCore/Tests/AppCoreTests/DesignTokensTests.swift`:
```swift
import AppKit
import XCTest
@testable import AppCore

final class DesignTokensTests: XCTestCase {
    func testValuesFromTemplate() {
        XCTAssertEqual(Tokens.accent, ThemeColor(0x4B3FD1, 0x5B4FE0))
        XCTAssertEqual(Tokens.win, ThemeColor(0xFBFBFD, 0x26262C))
        XCTAssertEqual(Tokens.tabOn, ThemeColor(0xE4E2F8, 0x3A3566))
        XCTAssertEqual(Tokens.chipOff, ThemeColor(0xFFFFFF, 0x34343C))
        XCTAssertEqual(Tokens.mainChipOff, ThemeColor(0xFFFFFF, 0x2E2E35))
        XCTAssertEqual(Tokens.pill.dark, RGBA(0x141518, alpha: 0.84))
        XCTAssertEqual(Tokens.overlay.light, RGBA(0x000000, alpha: 0.62))
        XCTAssertEqual(Tokens.overlay.light, Tokens.overlay.dark)
    }

    func testDynamicColorFollowsAppearance() throws {
        XCTAssertEqual(try resolvedRed(Tokens.win, .aqua), 0xFB)
        XCTAssertEqual(try resolvedRed(Tokens.win, .darkAqua), 0x26)
        XCTAssertEqual(try resolvedRed(Tokens.accent, .darkAqua), 0x5B)
    }

    private func resolvedRed(_ token: ThemeColor, _ name: NSAppearance.Name) throws -> Int {
        let appearance = try XCTUnwrap(NSAppearance(named: name))
        var red: CGFloat = -1
        appearance.performAsCurrentDrawingAppearance {
            red = token.nsColor.usingColorSpace(.sRGB)?.redComponent ?? -1
        }
        return Int((red * 255).rounded())
    }
}
```

Run: `(cd Packages/AppCore && swift test --filter DesignTokensTests 2>&1 | tail -3)` → FAIL („cannot find 'Tokens'“).

- [ ] **Step 3: Tokens implementieren**

`Packages/AppCore/Sources/AppCore/DesignTokens.swift`:
```swift
import AppKit
import SwiftUI

/// sRGB color with alpha as written in the template (`#RRGGBB`, `rgba(r,g,b,a)`).
public struct RGBA: Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public let alpha: Double

    public init(_ hex: UInt32, alpha: Double = 1) {
        red = UInt8((hex >> 16) & 0xFF)
        green = UInt8((hex >> 8) & 0xFF)
        blue = UInt8(hex & 0xFF)
        self.alpha = alpha
    }

    public var nsColor: NSColor {
        NSColor(
            srgbRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: CGFloat(alpha)
        )
    }
}

/// A template token with its light ("Hell") and dark ("Dunkel") value.
public struct ThemeColor: Equatable, Sendable {
    public let light: RGBA
    public let dark: RGBA

    public init(light: RGBA, dark: RGBA) {
        self.light = light
        self.dark = dark
    }

    public init(_ light: UInt32, _ dark: UInt32) {
        self.init(light: RGBA(light), dark: RGBA(dark))
    }

    public static func fixed(_ value: RGBA) -> ThemeColor {
        ThemeColor(light: value, dark: value)
    }

    /// Resolves at draw time against the current appearance (window, popup or `NSApp.appearance`).
    public var nsColor: NSColor {
        let light = light
        let dark = dark
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark.nsColor : light.nsColor
        }
    }

    public var color: Color {
        Color(nsColor: nsColor)
    }
}

/// Tokens of the template's `light` / `night` objects. Names and values: docs/design/tokens.md.
public enum Tokens {
    // Einstellungen.dc.html
    public static let page = ThemeColor(0xDCDDE6, 0x121318)
    public static let win = ThemeColor(0xFBFBFD, 0x26262C)
    public static let bar = ThemeColor(0xF3F3F7, 0x2C2C33)
    public static let side = ThemeColor(0xF2F2F6, 0x222227)
    public static let group = ThemeColor(0xFFFFFF, 0x2E2E35)
    public static let fg = ThemeColor(0x1D1D1F, 0xEDEDF2)
    public static let muted = ThemeColor(0x55555F, 0xABABB7)
    public static let accent = ThemeColor(0x4B3FD1, 0x5B4FE0)
    public static let accSoft = ThemeColor(0xECEAFB, 0x312C5C)
    public static let accText = ThemeColor(0x3528A8, 0xC3BDFF)
    public static let border = ThemeColor(0xDEDEE6, 0x3B3B45)
    public static let field = ThemeColor(0xFFFFFF, 0x1C1C21)
    public static let ok = ThemeColor(0x1C6B30, 0x86E3A6)
    public static let okBg = ThemeColor(0xE3F5E8, 0x1F3A2A)
    public static let segBg = ThemeColor(0xE8E8EE, 0x1C1C21)
    public static let segOn = ThemeColor(0xFFFFFF, 0x3E3E48)
    public static let segShadow = ThemeColor(light: RGBA(0x000000, alpha: 0.14), dark: RGBA(0x000000, alpha: 0.4))
    public static let chipOff = ThemeColor(0xFFFFFF, 0x34343C)
    public static let chipBorder = ThemeColor(0xC9C9D6, 0x4A4A55)
    public static let naFg = ThemeColor(0x7A7A86, 0x8A8A97)
    public static let toggleOff = ThemeColor(0xD1D1D8, 0x4A4A55)
    public static let btn2 = ThemeColor(0xEFEFF4, 0x34343C)
    public static let scrim = ThemeColor(light: RGBA(0x1E1E32, alpha: 0.18), dark: RGBA(0x000000, alpha: 0.42))
    public static let tabOn = ThemeColor(0xE4E2F8, 0x3A3566)

    // Main.dc.html (onboarding, menu panel, popup), where it differs from the settings
    public static let mainBorder = ThemeColor(0xD9D9E3, 0x3B3B45)
    public static let mainChipOff = ThemeColor(0xFFFFFF, 0x2E2E35)
    public static let menu = ThemeColor(0xFBFBFD, 0x2B2B31)
    public static let dotOff = ThemeColor(0xC9C9D6, 0x4A4A55)
    public static let dropBorder = ThemeColor(0xB8B2F2, 0x6D63D9)
    public static let pill = ThemeColor(light: RGBA(0xFAFAFC, alpha: 0.9), dark: RGBA(0x141518, alpha: 0.84))
    public static let pillRing = ThemeColor(light: RGBA(0x000000, alpha: 0.08), dark: RGBA(0xFFFFFF, alpha: 0.1))
    public static let pillBtn = ThemeColor(0xE6E6EE, 0x3A3B42)
    public static let pillFg = ThemeColor(0x1D1D1F, 0xEDEDF0)

    // Same in both appearances
    public static let overlay = ThemeColor.fixed(RGBA(0x000000, alpha: 0.62))
    public static let white = ThemeColor.fixed(RGBA(0xFFFFFF))
    public static let statusGreen = ThemeColor.fixed(RGBA(0x34C759))
    public static let stripeA = ThemeColor.fixed(RGBA(0x2A2D36))
    public static let stripeB = ThemeColor.fixed(RGBA(0x30343E))
    public static let popupRing = ThemeColor.fixed(RGBA(0xFFFFFF, alpha: 0.1))
}
```

Run: `(cd Packages/AppCore && swift test 2>&1 | tail -3)` → PASS.

- [ ] **Step 4: Symbole aus der Vorlage exportieren**

Die Pfade sind 1:1 die Inline-SVGs aus `Einstellungen.dc.html`/`Main.dc.html`; `currentColor` wird zu `#000000` (Template-Rendering färbt um). Aus dem Worktree-Wurzelverzeichnis ausführen:

```bash
ICONS=UniFiCameraPopup/Assets.xcassets/Icons
mkdir -p "$ICONS"
printf '{\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n' > "$ICONS/Contents.json"
while IFS='|' read -r name width body; do
  [ -z "$name" ] && continue
  dir="$ICONS/$name.imageset"
  mkdir -p "$dir"
  if [ "$width" = "fill" ]; then
    attrs='fill="#000000"'
  else
    attrs="fill=\"none\" stroke=\"#000000\" stroke-width=\"$width\" stroke-linecap=\"round\" stroke-linejoin=\"round\""
  fi
  printf '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" %s>%s</svg>\n' "$attrs" "$body" > "$dir/$name.svg"
  printf '{\n  "images" : [ { "filename" : "%s.svg", "idiom" : "universal" } ],\n  "info" : { "author" : "xcode", "version" : 1 },\n  "properties" : { "preserves-vector-representation" : true, "template-rendering-intent" : "template" }\n}\n' "$name" > "$dir/Contents.json"
done <<'EOF'
tabGeneral|1.7|<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M4.9 19.1L7 17M17 7l2.1-2.1"/>
tabCameras|1.7|<rect x="3" y="7" width="13" height="10" rx="2"/><path d="M16 11l5-3v8l-5-3"/>
tabSound|1.7|<path d="M4 9h4l5-4v14l-5-4H4z"/><path d="M16.5 8.5a5 5 0 0 1 0 7"/>
tabRemote|1.7|<path d="M12 3l7 3v5c0 4.5-3 8-7 10-4-2-7-5.5-7-10V6z"/>
chevronUpDown|2.6|<path d="M7 9l5-5 5 5M7 15l5 5 5-5"/>
chevronRight|2.8|<path d="M9 6l6 6-6 6"/>
chevronDown|2.8|<path d="M6 9l6 6 6-6"/>
close|2.6|<path d="M6 6l12 12M18 6L6 18"/>
bellSlash|2|<path d="M6 8a6 6 0 0 1 10.3-4.2M18 10v3l2 3H8M10 20a2 2 0 0 0 4 0"/><path d="M3 3l18 18"/>
speakerMute|2|<path d="M4 9h4l5-4v14l-5-4H4z"/><path d="M17 9l4 6M21 9l-4 6"/>
check|2.4|<path d="M5 12.5l4.5 4.5L19 7"/>
play|fill|<path d="M7 4l13 8-13 8z"/>
shieldCheck|1.8|<path d="M12 3l7 3v5c0 4.5-3 8-7 10-4-2-7-5.5-7-10V6z"/><path d="M9 12l2 2 4-4"/>
actionDoor|1.8|<path d="M6 21V4h12v17M4 21h16"/><path d="M14.5 12.5h.01"/>
actionBulb|1.8|<path d="M9 18h6M10 21h4M12 3a6 6 0 0 0-4 10.5V16h8v-2.5A6 6 0 0 0 12 3z"/>
actionHouse|1.8|<path d="M3 21V9l9-6 9 6v12"/><path d="M7 21v-8h10v8M7 17h10"/>
actionBolt|1.8|<path d="M13 3L5 14h6l-1 7 8-11h-6z"/>
EOF
ls "$ICONS" | wc -l   # Expected: 18 (17 Image-Sets + Contents.json)
```

Herkunft (zum Gegenprüfen): Reiter-Symbole `Einstellungen.dc.html` Zeile 25; Doppelpfeil Zeile 35; Pfeil rechts/unten Zeilen 78/100; Häkchen Zeile 137; Button-Symbole Zeilen 127–130; Play Zeile 156; Schild-Häkchen Zeile 186; Schließen, Glocke `Main.dc.html` Popup; Lautsprecher-durchgestrichen `Main.dc.html` Menü.

- [ ] **Step 5: Bausteine schreiben**

`UniFiCameraPopup/Views/Design/DesignComponents.swift`:
```swift
import AppCore
import AppKit
import SwiftUI

// MARK: - Icons

/// Template icons, exported 1:1 from the template's inline SVGs into `Assets.xcassets/Icons`
/// (vector, template rendering: tinted by the surrounding foreground color).
enum TemplateIcon: String, CaseIterable {
    case tabGeneral, tabCameras, tabSound, tabRemote
    case chevronUpDown, chevronRight, chevronDown
    case close, bellSlash, speakerMute, check, play, shieldCheck
    case actionDoor, actionBulb, actionHouse, actionBolt

    func image(size: CGFloat) -> some View {
        Image(rawValue)
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    /// AppKit variant for the popup overlays.
    func nsImage(size: CGFloat) -> NSImage? {
        guard let image = NSImage(named: rawValue)?.copy() as? NSImage else { return nil }
        image.size = NSSize(width: size, height: size)
        image.isTemplate = true
        return image
    }
}

// MARK: - Containers

/// Rounded group: radius 10 (Allgemein, Ton, Unterwegs) or 9 (Kameras), fill `group`, 1 pt `border`.
struct Card<Content: View>: View {
    var radius: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: radius).fill(Tokens.group.color))
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Tokens.border.color, lineWidth: 1))
    }
}

/// 1 pt separator between card rows (`border-bottom: 1px solid border`).
struct CardDivider: View {
    var color: ThemeColor = Tokens.border

    var body: some View {
        Rectangle().fill(color.color).frame(height: 1)
    }
}

/// Card row: title fills, trailing controls on the right (gap 10).
struct CardRow<Trailing: View>: View {
    let title: String
    var vertical: CGFloat = 10
    var horizontal: CGFloat = 14
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, vertical)
        .padding(.horizontal, horizontal)
    }
}

/// Card row with switch; optional 11 pt subtitle under the title (gap 2).
struct CardToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var vertical: CGFloat = 10
    var horizontal: CGFloat = 14

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Tokens.muted.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TokenSwitch(isOn: $isOn, label: title)
        }
        .padding(.vertical, vertical)
        .padding(.horizontal, horizontal)
    }
}

/// Card row with a fixed-width label (Kameras › Erweitert: 110, Unterwegs: 140).
struct FixedLabelRow<Content: View>: View {
    let title: String
    var width: CGFloat = 110
    var vertical: CGFloat = 9
    var horizontal: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) {
            Text(title).frame(width: width, alignment: .leading)
            content
        }
        .padding(.vertical, vertical)
        .padding(.horizontal, horizontal)
    }
}

/// Sheet grid line: 96 pt label column, gap 10.
struct FormLine<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) {
            Text(label).frame(width: 96, alignment: .leading)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Section heading: 11 pt semibold, `muted`.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Tokens.muted.color)
    }
}

// MARK: - Buttons

/// Pressed and disabled look shared by the token button styles (template has neither: 70 % / 45 %).
private struct StyledButtonBody<Content: View>: View {
    let configuration: ButtonStyleConfiguration
    @ViewBuilder var content: Content
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        content
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .contentShape(Rectangle())
    }
}

/// Bordered field button ("Ändern …", "Kopieren", "Testen").
struct FieldButtonStyle: ButtonStyle {
    var fontSize: CGFloat = 12
    var vertical: CGFloat = 3
    var horizontal: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        StyledButtonBody(configuration: configuration) {
            configuration.label
                .font(.system(size: fontSize))
                .foregroundStyle(Tokens.fg.color)
                .padding(.vertical, vertical)
                .padding(.horizontal, horizontal)
                .background(RoundedRectangle(cornerRadius: 6).fill(Tokens.field.color))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Tokens.chipBorder.color, lineWidth: 1))
        }
    }
}

/// Filled accent button ("Sichern", "Übernehmen").
struct AccentButtonStyle: ButtonStyle {
    var fontSize: CGFloat = 13
    var vertical: CGFloat = 5
    var horizontal: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        StyledButtonBody(configuration: configuration) {
            configuration.label
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.vertical, vertical)
                .padding(.horizontal, horizontal)
                .background(RoundedRectangle(cornerRadius: 6).fill(Tokens.accent.color))
        }
    }
}

/// Soft accent button filling its width (menu panel "15 Min." / "1 Std.").
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledButtonBody(configuration: configuration) {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Tokens.accText.color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(Tokens.accSoft.color))
        }
    }
}

/// Text link (`<a>` of the template: colored and underlined).
struct LinkButtonStyle: ButtonStyle {
    var color: ThemeColor = Tokens.accText
    var fontSize: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        StyledButtonBody(configuration: configuration) {
            configuration.label
                .font(.system(size: fontSize))
                .foregroundStyle(color.color)
                .underline()
        }
    }
}

// MARK: - Controls

/// Switch 32 × 19, radius 10, knob 15 white with 2 pt inset; on `accent`, off `toggleOff`.
struct TokenSwitch: View {
    @Binding var isOn: Bool
    let label: String
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isOn ? Tokens.accent.color : Tokens.toggleOff.color)
                    .frame(width: 32, height: 19)
                Circle()
                    .fill(Color.white)
                    .frame(width: 15, height: 15)
                    .padding(2)
            }
            .animation(.easeOut(duration: 0.15), value: isOn)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "Ein" : "Aus")
        .accessibilityAddTraits(.isButton)
    }
}

/// Segmented control: track `segBg` radius 7 padding 2, 12 pt; segment padding 3/12
/// (or equal widths in a fixed content `width`), active `segOn` radius 5 + shadow, semibold.
struct TokenSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    var width: CGFloat? = nil

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isOn = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.title)
                        .font(.system(size: 12, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Tokens.fg.color : Tokens.muted.color)
                        .lineLimit(1)
                        .padding(.vertical, 3)
                        .padding(.horizontal, width == nil ? 12 : 0)
                        .frame(maxWidth: width == nil ? nil : .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isOn ? Tokens.segOn.color : Color.clear)
                                .shadow(color: isOn ? Tokens.segShadow.color : .clear, radius: 1, y: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .frame(width: width)
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Tokens.segBg.color))
    }
}

/// Plain text field in a bordered `field` box (settings: 12 pt 4/7 r5; sheet: 13/12 pt 5/8 r6).
struct TokenTextField: View {
    let placeholder: String
    @Binding var text: String
    var fontSize: CGFloat = 12
    var vertical: CGFloat = 4
    var horizontal: CGFloat = 7
    var radius: CGFloat = 5
    var secure = false

    var body: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: fontSize))
        .foregroundStyle(Tokens.fg.color)
        .padding(.vertical, vertical)
        .padding(.horizontal, horizontal)
        .background(RoundedRectangle(cornerRadius: radius).fill(Tokens.field.color))
        .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Tokens.chipBorder.color, lineWidth: 1))
    }
}

/// "15 | Minuten ⌃⌄": number input (34 wide, right aligned, tabular) + unit pop-up in one box.
struct DurationField: View {
    @Binding var duration: MuteDuration
    let accessibilityLabel: String
    @State private var text = ""
    @FocusState private var focused: Bool
    @StateObject private var anchor = ViewAnchor()

    var body: some View {
        HStack(spacing: 0) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 12).monospacedDigit())
                .frame(width: 34)
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { isFocused in
                    if !isFocused { commit() }
                }
                .accessibilityLabel(accessibilityLabel)
            Rectangle().fill(Tokens.chipBorder.color).frame(width: 1)
            Button(action: chooseUnit) {
                HStack(spacing: 5) {
                    Text(duration.unit.label)
                    TemplateIcon.chevronUpDown.image(size: 9)
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
                .background(AnchorView(anchor: anchor))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(accessibilityLabel), Einheit")
            .accessibilityValue(duration.unit.label)
        }
        .font(.system(size: 12))
        .foregroundStyle(Tokens.fg.color)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: 6).fill(Tokens.field.color))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Tokens.chipBorder.color, lineWidth: 1))
        .onAppear { text = String(duration.value) }
        .onChange(of: duration) { newValue in
            if !focused { text = String(newValue.value) }
        }
    }

    private func commit() {
        if let value = MuteDuration.parseValue(text) {
            duration = duration.withValue(value)
        }
        text = String(duration.value)
    }

    private func chooseUnit() {
        guard let view = anchor.view else { return }
        let units = MuteDuration.Unit.allCases
        MenuPresenter.popUp(
            titles: units.map(\.label),
            selectedIndex: units.firstIndex(of: duration.unit),
            in: view
        ) { index in
            duration.unit = units[index]
        }
    }
}

/// "▸ Erweitert" / "▾ Erweitert": 12 pt, chevron 10, gap 5; collapsed `muted`, expanded `fg` semibold.
struct DisclosureButton: View {
    let title: String
    @Binding var expanded: Bool

    var body: some View {
        Button { expanded.toggle() } label: {
            HStack(spacing: 5) {
                (expanded ? TemplateIcon.chevronDown : TemplateIcon.chevronRight).image(size: 10)
                Text(title).font(.system(size: 12, weight: expanded ? .semibold : .regular))
            }
            .foregroundStyle(expanded ? Tokens.fg.color : Tokens.muted.color)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(expanded ? "aufgeklappt" : "zugeklappt")
    }
}

/// The template's striped stand-in for a camera picture:
/// `repeating-linear-gradient(135deg, #2A2D36 0 band, #30343E band 2·band)`.
struct StripePlaceholder: View {
    var band: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Tokens.stripeA.color))
            // Bands are measured along the 135° gradient line; lines of equal color satisfy x + y = c.
            let step = band * 2.squareRoot()
            var start = step
            while start < size.width + size.height {
                var path = Path()
                path.move(to: CGPoint(x: start, y: 0))
                path.addLine(to: CGPoint(x: start + step, y: 0))
                path.addLine(to: CGPoint(x: start + step - size.height, y: size.height))
                path.addLine(to: CGPoint(x: start - size.height, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .color(Tokens.stripeB.color))
                start += step * 2
            }
        }
        .accessibilityHidden(true)
    }
}

/// Static volume slider of the Ton scaffold: track 180 × 4, fill 120, knob 16 at x 112.
struct VolumeTrack: View {
    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(Tokens.toggleOff.color).frame(width: 180, height: 4)
            RoundedRectangle(cornerRadius: 2).fill(Tokens.accent.color).frame(width: 120, height: 4)
            Circle()
                .fill(Color.white)
                .frame(width: 16, height: 16)
                .shadow(color: Color.black.opacity(0.35), radius: 1.5, y: 1)
                .offset(x: 112)
        }
        .frame(width: 180, height: 16)
    }
}
```

`UniFiCameraPopup/Views/Design/PopUpField.swift`:
```swift
import AppCore
import AppKit
import SwiftUI

/// Template pop-up field ("Oben rechts ⌃⌄"): 12 pt, padding 3/10, radius 6, `chipBorder`, `field`.
/// The field is drawn 1:1; the list that opens is the native menu.
struct PopUpField<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    @StateObject private var anchor = ViewAnchor()

    private var title: String {
        options.first { $0.value == selection }?.title ?? ""
    }

    var body: some View {
        Button(action: present) {
            HStack(spacing: 6) {
                Text(title).lineLimit(1)
                TemplateIcon.chevronUpDown.image(size: 9)
            }
            .font(.system(size: 12))
            .foregroundStyle(Tokens.fg.color)
            .padding(.vertical, 3)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 6).fill(Tokens.field.color))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Tokens.chipBorder.color, lineWidth: 1))
            .contentShape(Rectangle())
            .background(AnchorView(anchor: anchor))
        }
        .buttonStyle(.plain)
        .accessibilityValue(title)
    }

    private func present() {
        guard let view = anchor.view else { return }
        MenuPresenter.popUp(
            titles: options.map { $0.title },
            selectedIndex: options.firstIndex { $0.value == selection },
            in: view
        ) { index in
            selection = options[index].value
        }
    }
}

/// Holds the AppKit view a menu is positioned at.
final class ViewAnchor: ObservableObject {
    weak var view: NSView?
}

struct AnchorView: NSViewRepresentable {
    let anchor: ViewAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}

@MainActor
enum MenuPresenter {
    /// Shows a native menu with the selected item over `view` (like a pop-up button).
    static func popUp(titles: [String], selectedIndex: Int?, in view: NSView, onSelect: @escaping (Int) -> Void) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let handler = MenuHandler(onSelect)
        for (index, title) in titles.enumerated() {
            let item = NSMenuItem(title: title, action: #selector(MenuHandler.pick(_:)), keyEquivalent: "")
            item.target = handler
            item.tag = index
            item.state = index == selectedIndex ? .on : .off
            menu.addItem(item)
        }
        let positioning = selectedIndex.flatMap { menu.item(at: $0) }
        let origin = NSPoint(x: 0, y: view.isFlipped ? 0 : view.bounds.height)
        menu.popUp(positioning: positioning, at: origin, in: view)
        withExtendedLifetime(handler) {}
    }
}

private final class MenuHandler: NSObject {
    private let onSelect: (Int) -> Void

    init(_ onSelect: @escaping (Int) -> Void) {
        self.onSelect = onSelect
    }

    @objc func pick(_ sender: NSMenuItem) {
        onSelect(sender.tag)
    }
}
```

- [ ] **Step 6: Dateien ins Projekt eintragen**

In `project.pbxproj`:
1. PBXBuildFile:
```
		A10000000000000000000071 /* DesignComponents.swift in Sources */ = {isa = PBXBuildFile; fileRef = A20000000000000000000071 /* DesignComponents.swift */; };
		A10000000000000000000072 /* PopUpField.swift in Sources */ = {isa = PBXBuildFile; fileRef = A20000000000000000000072 /* PopUpField.swift */; };
```
2. PBXFileReference:
```
		A20000000000000000000071 /* DesignComponents.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DesignComponents.swift; sourceTree = "<group>"; };
		A20000000000000000000072 /* PopUpField.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PopUpField.swift; sourceTree = "<group>"; };
```
3. PBXGroup-Abschnitt, neue Gruppe (nach der Onboarding-Gruppe):
```
		A40000000000000000000070 /* Design */ = {
			isa = PBXGroup;
			children = (
				A20000000000000000000071 /* DesignComponents.swift */,
				A20000000000000000000072 /* PopUpField.swift */,
			);
			path = Design;
			sourceTree = "<group>";
		};
```
4. In der Gruppe `A40000000000000000000006 /* Views */` nach `A40000000000000000000060 /* Onboarding */,`: `A40000000000000000000070 /* Design */,`
5. In `A60000000000000000000002 /* Sources */` am Ende der `files`:
```
				A10000000000000000000071 /* DesignComponents.swift in Sources */,
				A10000000000000000000072 /* PopUpField.swift in Sources */,
```
Der Ordner `Assets.xcassets` ist schon als Ganzes eingetragen; `Icons/` braucht keinen pbxproj-Eintrag.

- [ ] **Step 7: Lint, Build, Symbole im kompilierten Katalog prüfen**

Run: `plutil -lint UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj` → `OK`
Run: Build-Befehl → `** BUILD SUCCEEDED **`
Run: `xcrun --sdk macosx assetutil --info "$DD/Build/Products/Debug/UniFi Camera Popup.app/Contents/Resources/Assets.car" | grep -c '"Name" : "\(tab\|chevron\|close\|bell\|speaker\|check\|play\|shield\|action\)'`
Expected: Zahl ≥ 17 (jedes Symbol mindestens einmal).

- [ ] **Step 8: Commit**

```bash
git add docs/design Packages/AppCore UniFiCameraPopup/Assets.xcassets/Icons UniFiCameraPopup/Views/Design UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "feat(design): template spec, tokens, icons and SwiftUI building blocks" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Einstellungen speichern und anwenden – Stumm-Zeitplan, Dauern, Erscheinungsbild, Verlauf

**Files:**
- Modify: `UniFiCameraPopup/Services/SettingsStore.swift`
- Modify: `UniFiCameraPopup/Models/WebhookMapping.swift` (`chimeOnOpen`, `CameraAction.icon`/`confirmBeforeRun`, `ActionIcon`)
- Create: `UniFiCameraPopup/Services/EventLog.swift`
- Modify: `UniFiCameraPopup/Services/ProtectSession.swift` (Schnappschuss-Cache)
- Modify: `UniFiCameraPopup/Services/PopupController.swift` (ganze Datei)
- Modify: `UniFiCameraPopup/AppDelegate.swift` (Stumm-Ablauf, Menüeintrag, Erscheinungsbild, Verlauf aufräumen)
- Modify: `UniFiCameraPopup/Views/PopupWindow.swift:169-172` (Übergang bis Task 7)
- Modify: `UniFiCameraPopup/Views/Onboarding/OnboardingView.swift:161-166` (Konsolenname merken)
- Modify: `project.pbxproj` (EventLog.swift)

**Interfaces:**
- Consumes: `MuteSchedule`, `MuteDuration`, `AppearanceMode`, `EventHistory`, `EventRecord` (Task 1); `TriggerKind.displayOrder`, `ProtectClient.snapshot(cameraId:)` (Task 2); `TemplateIcon` (Task 3).
- Produces:
  - `SettingsStore`: `@Published private(set) var muteSchedule: MuteSchedule`, `@Published var muteShort: MuteDuration`, `@Published var muteLong: MuteDuration`, `var muteOptions: [MuteDuration]`, `@Published var appearance: AppearanceMode`, `@Published var protectConsoleName: String?`, `var isMuted: Bool` (global), `func isMuted(entryId: UUID) -> Bool`, `func muteAll(for: MuteDuration)`, `func mute(entryId: UUID, for: MuteDuration)`, `func clearGlobalMute()`, `func clearMute(entryId: UUID)`, `func clearMute()` (alles), `func pruneMutes()`. **Entfällt:** `muteUntil`, `mute(for:)`.
  - `WebhookMapping.chimeOnOpen: Bool`; `CameraAction.icon: ActionIcon`, `CameraAction.confirmBeforeRun: Bool`; `enum ActionIcon: String, Codable, CaseIterable, Identifiable { door, bulb, house, bolt }` mit `label: String`, `templateIcon: TemplateIcon`.
  - `EventLog.shared` (`@MainActor ObservableObject`): `@Published private(set) var history: EventHistory`, `@Published private(set) var thumbnails: [UUID: NSImage]`, `record(mapping:kindLabel:date:)`, `lastTriggered(entryId:) -> Date?`, `removeEntries(notIn: Set<UUID>)`.
  - `ProtectSession.snapshot(cameraId: String, maxAge: TimeInterval = 60) async -> NSImage?`
  - `PopupController.kindLabel(for: TriggerEvent, mapping: WebhookMapping) -> String?` (static)

- [ ] **Step 1: Modelle erweitern**

In `UniFiCameraPopup/Models/WebhookMapping.swift`:

1. Vor `struct CameraAction` einfügen:
```swift
/// Symbol of a popup button (template sheet: door, bulb, house, bolt).
enum ActionIcon: String, Codable, CaseIterable, Identifiable {
    case door
    case bulb
    case house
    case bolt

    var id: String { rawValue }

    var label: String {
        switch self {
        case .door: return "Tür"
        case .bulb: return "Licht"
        case .house: return "Haus"
        case .bolt: return "Blitz"
        }
    }

    var templateIcon: TemplateIcon {
        switch self {
        case .door: return .actionDoor
        case .bulb: return .actionBulb
        case .house: return .actionHouse
        case .bolt: return .actionBolt
        }
    }
}
```
2. In `CameraAction` nach `var bearerToken: String`:
```swift
    /// Symbol in the popup's button pill.
    var icon: ActionIcon
    /// Ask before calling the webhook (e.g. opening a door).
    var confirmBeforeRun: Bool
```
`CodingKeys` um `case icon` und `case confirmBeforeRun` ergänzen. Den `init(id:title:url:method:bearerToken:)` ersetzen durch:
```swift
    init(
        id: UUID = UUID(),
        title: String = "",
        url: String = "",
        method: Method = .post,
        bearerToken: String = "",
        icon: ActionIcon = .bolt,
        confirmBeforeRun: Bool = false
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.method = method
        self.bearerToken = bearerToken
        self.icon = icon
        self.confirmBeforeRun = confirmBeforeRun
    }
```
In `init(from:)` nach der `bearerToken`-Zeile:
```swift
        icon = (try? container.decodeIfPresent(ActionIcon.self, forKey: .icon)) ?? .bolt
        confirmBeforeRun = (try? container.decodeIfPresent(Bool.self, forKey: .confirmBeforeRun)) ?? false
```
In `encode(to:)` nach `try container.encode(method, forKey: .method)`:
```swift
        try container.encode(icon, forKey: .icon)
        try container.encode(confirmBeforeRun, forKey: .confirmBeforeRun)
```
3. In `WebhookMapping` nach `var webhookTriggerEnabled: Bool`:
```swift
    /// "Hinweiston beim Öffnen": system sound when a triggered popup opens.
    var chimeOnOpen: Bool
```
`CodingKeys` um `case chimeOnOpen` ergänzen; im `init(...)` nach `webhookTriggerEnabled: Bool = false` den Parameter `chimeOnOpen: Bool = false` und `self.chimeOnOpen = chimeOnOpen`; in `init(from:)` am Ende:
```swift
        chimeOnOpen = (try? container.decodeIfPresent(Bool.self, forKey: .chimeOnOpen)) ?? false
```
in `encode(to:)` am Ende: `try container.encode(chimeOnOpen, forKey: .chimeOnOpen)`.

- [ ] **Step 2: SettingsStore – neue Felder**

In `UniFiCameraPopup/Services/SettingsStore.swift`:

1. Im `didSet` von `protectHost` den Block
```swift
            if Self.normalizedHost(oldValue) != Self.normalizedHost(protectHost) {
                protectCertificateFingerprint = nil
            }
```
ersetzen durch:
```swift
            if Self.normalizedHost(oldValue) != Self.normalizedHost(protectHost) {
                protectCertificateFingerprint = nil
                protectConsoleName = nil
            }
```
und direkt nach `protectCertificateFingerprint` (vor `protectAPIKey`) ergänzen:
```swift
    /// Console name from discovery ("UDM Pro"); nil for a typed address.
    @Published var protectConsoleName: String? {
        didSet { persist() }
    }
```
2. Den Block von `/// When set to a future date, all popups are suppressed until then.` bis einschließlich `func clearMute() { muteUntil = nil }` (Zeilen 98–115) ersetzen durch:
```swift
    /// Global and per-camera mutes. Absolute dates: a mute survives a restart.
    @Published private(set) var muteSchedule: MuteSchedule {
        didSet { persist() }
    }

    /// The two offered mute lengths ("Kurz" / "Lang").
    @Published var muteShort: MuteDuration {
        didSet { persist() }
    }

    @Published var muteLong: MuteDuration {
        didSet { persist() }
    }

    var muteOptions: [MuteDuration] { [muteShort, muteLong] }

    /// "Erscheinungsbild": applied to `NSApp.appearance` by `AppDelegate`.
    @Published var appearance: AppearanceMode {
        didSet { persist() }
    }

    /// Whether all popups are muted right now (menu bar badge, global check).
    var isMuted: Bool {
        muteSchedule.isGloballyMuted(at: Date())
    }

    /// Whether this camera must not open a popup (own mute or global mute).
    func isMuted(entryId: UUID) -> Bool {
        muteSchedule.isMuted(entry: entryId.uuidString, at: Date())
    }

    func muteAll(for duration: MuteDuration) {
        muteSchedule.muteAll(for: duration.seconds, from: Date())
    }

    func mute(entryId: UUID, for duration: MuteDuration) {
        muteSchedule.mute(entry: entryId.uuidString, for: duration.seconds, from: Date())
    }

    func clearGlobalMute() {
        muteSchedule.clearGlobal()
    }

    func clearMute(entryId: UUID) {
        muteSchedule.clear(entry: entryId.uuidString)
    }

    /// Lifts every mute (menu "Stummschaltung aufheben").
    func clearMute() {
        muteSchedule.clearAll()
    }

    /// Drops ended mutes and mutes of removed cameras; writes only on change.
    func pruneMutes() {
        var pruned = muteSchedule
        pruned.prune(at: Date(), validEntries: Set(mappings.map(\.entryId.uuidString)))
        if pruned != muteSchedule {
            muteSchedule = pruned
        }
    }
```
3. In `PersistedSettings` nach `var protectCertificateFingerprint: String?`:
```swift
        var muteSchedule: MuteSchedule?
        var muteShort: MuteDuration?
        var muteLong: MuteDuration?
        var appearance: AppearanceMode?
        var protectConsoleName: String?
```
(`var muteUntil: Date?` bleibt: alte Dateien lesen, für ältere Builds weiter schreiben.)
4. Im Dekodier-Zweig von `init()` die Zeile `muteUntil = saved.muteUntil` ersetzen durch:
```swift
            var schedule = MuteSchedule.migrated(stored: saved.muteSchedule, legacyGlobalUntil: saved.muteUntil)
            schedule.prune(at: Date(), validEntries: Set(loaded.mappings.map(\.entryId.uuidString)))
            muteSchedule = schedule
            muteShort = saved.muteShort ?? .defaultShort
            muteLong = saved.muteLong ?? .defaultLong
            appearance = saved.appearance ?? .system
            protectConsoleName = saved.protectConsoleName
```
5. Im Standard-Zweig die Zeile `muteUntil = nil` ersetzen durch:
```swift
            muteSchedule = MuteSchedule()
            muteShort = .defaultShort
            muteLong = .defaultLong
            appearance = .system
            protectConsoleName = nil
```
6. `removeMapping(id:)` ersetzen durch:
```swift
    func removeMapping(id: UUID) {
        mappings.removeAll { $0.entryId == id }
        muteSchedule.clear(entry: id.uuidString)
    }
```
7. `currentPersistedSettings()` komplett ersetzen durch:
```swift
    private func currentPersistedSettings() -> PersistedSettings {
        PersistedSettings(
            installationId: installationId,
            mappings: mappings,
            defaultPosition: defaultPosition,
            defaultWidth: nil,
            defaultHeight: nil,
            edgeMargin: edgeMargin,
            autoCloseTimeout: autoCloseTimeout,
            screenTarget: screenTarget,
            showAllActiveCameras: showAllActiveCameras,
            launchAtLogin: launchAtLogin,
            autoUpdate: autoUpdate,
            disableDuringDND: disableDuringDND,
            // Still written so an older installed build keeps honoring a global mute.
            muteUntil: muteSchedule.globalUntil,
            protectHost: protectHost,
            protectCertificateFingerprint: protectCertificateFingerprint,
            muteSchedule: muteSchedule,
            muteShort: muteShort,
            muteLong: muteLong,
            appearance: appearance,
            protectConsoleName: protectConsoleName
        )
    }
```
8. In `apply(_:)` die Zeile `muteUntil = saved.muteUntil` ersetzen durch:
```swift
        var schedule = saved.muteSchedule ?? MuteSchedule(globalUntil: saved.muteUntil)
        schedule.prune(at: Date(), validEntries: Set(saved.mappings.map(\.entryId.uuidString)))
        muteSchedule = schedule
        muteShort = saved.muteShort ?? muteShort
        muteLong = saved.muteLong ?? muteLong
        appearance = saved.appearance ?? appearance
```
und ganz am Ende von `apply(_:)` (nach dem `protectHost`-Block, der den Namen bei Konsolenwechsel leert):
```swift
        if let name = saved.protectConsoleName {
            protectConsoleName = name
        }
```

- [ ] **Step 3: Schnappschüsse in ProtectSession**

In `UniFiCameraPopup/Services/ProtectSession.swift`: `import AppKit` ergänzen; nach `private var streamCache` einfügen:
```swift
    private var snapshotCache: [String: (image: NSImage, date: Date)] = [:]
```
in `reconnect()` nach `streamCache = [:]`: `snapshotCache = [:]`; am Klassenende:
```swift
    /// Camera still for thumbnails, cached for `maxAge` seconds (0 = always fresh).
    /// nil without Protect, for unknown cameras or on any error.
    func snapshot(cameraId: String, maxAge: TimeInterval = 60) async -> NSImage? {
        if let cached = snapshotCache[cameraId], Date().timeIntervalSince(cached.date) < maxAge {
            return cached.image
        }
        guard let client else { return nil }
        guard let data = try? await client.snapshot(cameraId: cameraId),
              let image = NSImage(data: data) else { return nil }
        if client === self.client {
            snapshotCache[cameraId] = (image, Date())
        }
        return image
    }
```

- [ ] **Step 4: Ereignis-Verlauf**

`UniFiCameraPopup/Services/EventLog.swift`:
```swift
import AppCore
import AppKit
import Foundation

/// Recent popup triggers for the menu panel and "Zuletzt ausgelöst". Persisted separately from
/// the settings (not part of the configuration export); snapshots stay in memory.
@MainActor
final class EventLog: ObservableObject {
    static let shared = EventLog()

    @Published private(set) var history: EventHistory
    /// Snapshot taken when the event arrived, keyed by `EventRecord.id`.
    @Published private(set) var thumbnails: [UUID: NSImage] = [:]

    private let defaults = UserDefaults.standard
    private static let storageKey = "unifi.camera.popup.events"

    private init() {
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(EventHistory.self, from: data) {
            history = saved
        } else {
            history = EventHistory()
        }
    }

    func record(mapping: WebhookMapping, kindLabel: String?, date: Date) {
        let name = mapping.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = EventRecord(
            entryId: mapping.entryId.uuidString,
            kindLabel: kindLabel,
            cameraName: name.isEmpty ? "Kamera" : name,
            date: date
        )
        history.record(record)
        persist()

        guard let cameraId = mapping.protectCameraId else { return }
        Task {
            if let image = await ProtectSession.shared.snapshot(cameraId: cameraId, maxAge: 0) {
                thumbnails[record.id] = image
            }
            let kept = Set(history.records.map(\.id))
            thumbnails = thumbnails.filter { kept.contains($0.key) }
        }
    }

    func lastTriggered(entryId: UUID) -> Date? {
        history.lastTriggered(entry: entryId.uuidString)
    }

    /// Forgets events of removed cameras; writes only on change.
    func removeEntries(notIn ids: Set<UUID>) {
        var updated = history
        updated.removeEntries(notIn: Set(ids.map(\.uuidString)))
        guard updated != history else { return }
        history = updated
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
```
pbxproj: PBXBuildFile `A10000000000000000000082 /* EventLog.swift in Sources */ = {isa = PBXBuildFile; fileRef = A20000000000000000000082 /* EventLog.swift */; };`, PBXFileReference `A20000000000000000000082 /* EventLog.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = EventLog.swift; sourceTree = "<group>"; };`, Kind der Gruppe `A40000000000000000000005 /* Services */` (`A20000000000000000000082 /* EventLog.swift */,`), Sources-Phase (`A10000000000000000000082 /* EventLog.swift in Sources */,`).

- [ ] **Step 5: PopupController – Pro-Kamera-Stumm, Verlauf, Hinweiston**

`UniFiCameraPopup/Services/PopupController.swift` komplett ersetzen:
```swift
import AppCore
import AppKit
import ProtectKit

@MainActor
final class PopupController {
    static let shared = PopupController()

    /// A popup that is currently on screen. The order of `activePopups` is the
    /// stacking order and is kept stable: a re-triggering camera only restarts
    /// its timeout, it is never moved within the stack.
    private struct ActivePopup {
        /// The mapping entry shown. Protect-only entries have no webhook slug,
        /// so popups are keyed by entry, never by webhook id.
        let entryId: UUID
        let window: PopupWindow
        let size: CGSize
        /// The position used when only a single popup is shown.
        let position: PopupPosition
    }

    private var activePopups: [ActivePopup] = []
    private let settings = SettingsStore.shared

    private init() {}

    /// Entry point for triggers (Protect events, relay webhooks). The event is recorded for the
    /// menu panel even when muted; then global mute, the camera's own mute and Focus are honored.
    func show(event: TriggerEvent) {
        let mapping = mapping(for: event)
        if let mapping {
            EventLog.shared.record(
                mapping: mapping,
                kindLabel: Self.kindLabel(for: event, mapping: mapping),
                date: event.timestamp
            )
        }

        if settings.isMuted {
            NSLog("Popups muted; skipping popup.")
            return
        }

        if let mapping, settings.isMuted(entryId: mapping.entryId) {
            NSLog("Camera muted; skipping popup.")
            return
        }

        if settings.disableDuringDND, DoNotDisturbChecker.isActive {
            NSLog("Do Not Disturb active; skipping popup.")
            return
        }

        present(event: event, isTrigger: true)
    }

    /// Event kind for the popup chip and the menu panel ("Klingel"); nil for webhook and manual popups.
    static func kindLabel(for event: TriggerEvent, mapping: WebhookMapping) -> String? {
        TriggerKind.displayOrder.first { event.kinds.contains($0) && mapping.triggers.contains($0) }?.label
    }

    private func mapping(for event: TriggerEvent) -> WebhookMapping? {
        event.mappingId.flatMap(settings.mapping(forEntry:)) ?? settings.mapping(for: event.webhookId)
    }

    private func present(event: TriggerEvent, isTrigger: Bool) {
        guard let mapping = mapping(for: event) else {
            NSLog("No mapping for event: \(event.webhookId) \(String(describing: event.mappingId))")
            return
        }

        // The same camera triggering again only restarts its auto-close timer.
        // The popup keeps its place in the stack so windows never jump around.
        if extendExistingPopup(for: mapping.entryId) { return }

        Task { @MainActor in
            guard let streamURL = await ProtectSession.shared.streamURL(for: mapping) else {
                NSLog("No stream URL for \(mapping.label)")
                return
            }
            // Another trigger for this entry may have opened it while the URL resolved.
            if extendExistingPopup(for: mapping.entryId) { return }

            // Without the "show all" option a new camera replaces the current popup.
            if !settings.showAllActiveCameras {
                dismiss()
            }

            let window = makeAlarmWindow(event: event, mapping: mapping, streamURL: streamURL)
            activePopups.append(
                ActivePopup(
                    entryId: mapping.entryId,
                    window: window,
                    size: CGSize(width: CGFloat(mapping.width), height: CGFloat(mapping.height)),
                    position: mapping.positionOverride ?? settings.defaultPosition
                )
            )

            relayout()
            // Show without stealing focus so the user can keep typing in other apps.
            window.orderFrontRegardless()
            window.startPlayback()
            if isTrigger, mapping.chimeOnOpen {
                NSSound(named: "Glass")?.play()
            }
        }
    }

    private func extendExistingPopup(for entryId: UUID) -> Bool {
        guard let existing = activePopups.first(where: { $0.entryId == entryId }) else { return false }
        existing.window.extendAutoClose(seconds: settings.autoCloseTimeout)
        return true
    }

    private func makeAlarmWindow(
        event: TriggerEvent,
        mapping: WebhookMapping,
        streamURL: String
    ) -> PopupWindow {
        let entryId = mapping.entryId
        return PopupWindow(
            frame: NSRect(x: 0, y: 0, width: CGFloat(mapping.width), height: CGFloat(mapping.height)),
            streamURL: streamURL,
            soundEnabled: mapping.soundEnabled,
            rememberZoom: mapping.rememberZoom,
            initialZoom: mapping.rememberZoom ? mapping.savedZoom : nil,
            cropRegion: mapping.crop,
            thumbnailDataURI: event.thumbnail,
            autoCloseSeconds: settings.autoCloseTimeout,
            actions: mapping.actions.filter(\.isConfigured),
            onWillClose: { [weak self] scale, panOffset in
                self?.settings.saveZoom(for: entryId, scale: scale, panOffset: panOffset)
            }
        ) { [weak self] in
            self?.removePopup(entryId: entryId)
        }
    }

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

    private func removePopup(entryId: UUID) {
        activePopups.removeAll { $0.entryId == entryId }
        relayout()
    }

    func showTestPopup(for mapping: WebhookMapping) {
        showManualPopup(for: mapping, alarmNameFallback: "Test")
    }

    func showCropSelection(for mapping: WebhookMapping) {
        Task { @MainActor in
            guard let streamURL = await ProtectSession.shared.streamURL(for: mapping) else {
                NSLog("Stream URL required to set crop.")
                return
            }
            openCropSelection(for: mapping, streamURL: streamURL)
        }
    }

    private func openCropSelection(for mapping: WebhookMapping, streamURL: String) {
        // Crop selection is a focused editing mode, so clear any open popups.
        dismiss()

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

        let window = PopupWindow(
            frame: frame,
            streamURL: streamURL,
            soundEnabled: false,
            thumbnailDataURI: nil,
            autoCloseSeconds: 0,
            cropSelectionMode: true,
            onCropSave: { [weak self] normalized, pixelSize in
                self?.settings.saveCrop(
                    for: entryId,
                    crop: normalized,
                    pixelWidth: Double(pixelSize.width),
                    pixelHeight: Double(pixelSize.height),
                    originalWidth: originalWidth,
                    originalHeight: originalHeight
                )
            },
            onCropCancel: nil
        ) { [weak self] in
            self?.removePopup(entryId: entryId)
        }

        activePopups.append(
            ActivePopup(
                entryId: entryId,
                window: window,
                size: CGSize(width: width, height: height),
                position: position
            )
        )
        window.orderFrontRegardless()
        window.startPlayback()
    }

    func showHotkeyPopup(for mapping: WebhookMapping) {
        showManualPopup(for: mapping, alarmNameFallback: "Hotkey")
    }

    /// Works for every entry, including Protect-only ones without a webhook slug.
    private func showManualPopup(for mapping: WebhookMapping, alarmNameFallback: String) {
        let alarmName = mapping.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let event = TriggerEvent(
            webhookId: mapping.webhookId,
            thumbnail: nil,
            alarmName: alarmName.isEmpty ? alarmNameFallback : alarmName,
            timestamp: Date(),
            mappingId: mapping.entryId
        )
        // Manual popups bypass mute / Do Not Disturb so they always appear.
        present(event: event, isTrigger: false)
    }

    func dismiss() {
        let popups = activePopups
        activePopups = []
        for popup in popups {
            popup.window.closePopup()
        }
    }
}
```

- [ ] **Step 6: PopupWindow-Übergang (bis Task 7)**

In `UniFiCameraPopup/Views/PopupWindow.swift` Zeile 170 `SettingsStore.shared.mute(for: duration)` ersetzen durch:
```swift
            let settings = SettingsStore.shared
            settings.muteAll(for: duration >= 3600 ? settings.muteLong : settings.muteShort)
```

- [ ] **Step 7: Onboarding merkt den Konsolennamen**

In `OnboardingView.swift`, `finish()`, direkt nach `settings.protectHost = canonicalHost ?? host`:
```swift
        if let name = consoles.first(where: { $0.ip == host })?.displayName {
            settings.protectConsoleName = name
        }
```

- [ ] **Step 8: AppDelegate – Ablauf, Menüeintrag, Erscheinungsbild, Aufräumen**

In `UniFiCameraPopup/AppDelegate.swift`:
1. `import AppCore` ergänzen.
2. In `applicationDidFinishLaunching` als erste Zeile: `settings.pruneMutes()`.
3. `observeHotkeyMappings()` ersetzen durch:
```swift
    private func observeHotkeyMappings() async {
        for await mappings in settings.$mappings.values {
            GlobalHotkeyManager.shared.sync(mappings: mappings)
            syncRelayConnection(mappings: mappings)
            EventLog.shared.removeEntries(notIn: Set(mappings.map(\.entryId)))
        }
    }
```
4. `observePopupSuppressionState()` ersetzen durch:
```swift
    private func observePopupSuppressionState() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                for await schedule in self.settings.$muteSchedule.values {
                    self.scheduleMuteExpiryRefresh(schedule)
                }
            }
            group.addTask { @MainActor in
                for await _ in self.settings.$disableDuringDND.values {
                    self.updateStatusBarIcon()
                }
            }
            group.addTask { @MainActor in
                for await mode in self.settings.$appearance.values {
                    NSApp.appearance = mode.appearanceName.flatMap { NSAppearance(named: $0) }
                }
            }
        }
    }
```
5. `scheduleMuteExpiryRefresh()` ersetzen durch:
```swift
    /// Refreshes the icon now and again when the next mute ends; then prunes ended mutes.
    private func scheduleMuteExpiryRefresh(_ schedule: MuteSchedule? = nil) {
        muteExpiryTimer?.invalidate()
        muteExpiryTimer = nil
        updateStatusBarIcon()

        guard let next = (schedule ?? settings.muteSchedule).nextExpiry(after: Date()) else { return }
        let timer = Timer(timeInterval: max(next.timeIntervalSinceNow, 0.5), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.settings.pruneMutes()
                self?.scheduleMuteExpiryRefresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        muteExpiryTimer = timer
    }
```
6. `updateMuteMenuItem()` ersetzen durch:
```swift
    private func updateMuteMenuItem() {
        guard let unmuteMenuItem else { return }

        let now = Date()
        let schedule = settings.muteSchedule
        let cameraCount = schedule.activeCameraMutes(at: now).count
        if let globalEnd = schedule.globalEnd(at: now) {
            let minutes = max(1, Int((globalEnd.timeIntervalSince(now) / 60).rounded(.up)))
            unmuteMenuItem.title = "Stummschaltung aufheben (noch \(minutes) Min.)"
        } else if cameraCount > 0 {
            unmuteMenuItem.title = cameraCount == 1
                ? "Stummschaltung aufheben (1 Kamera)"
                : "Stummschaltung aufheben (\(cameraCount) Kameras)"
        } else {
            unmuteMenuItem.isHidden = true
            return
        }
        unmuteMenuItem.isHidden = false
    }
```
`clearMute()` (`@objc`) bleibt unverändert; `settings.clearMute()` hebt jetzt alles auf.

- [ ] **Step 9: Lint, Build, Tests**

Run: `plutil -lint …/project.pbxproj` → OK; Build → `** BUILD SUCCEEDED **`; `(cd Packages/AppCore && swift test 2>&1 | tail -3)` → 0 failures.

- [ ] **Step 10: Sichtprüfung Stumm-Ablauf**

App starten (installierte vorher beenden). Test-Popup einer Kamera öffnen (bisherige Einstellungen › Test-Popup), im Popup „15m“ klicken. Erwartet: Menü (Rechts- oder Linksklick auf das Symbol, noch das alte Menü) zeigt „Stummschaltung aufheben (noch 15 Min.)“, Zzz-Abzeichen sichtbar. App beenden und neu starten → Eintrag und Abzeichen sind wieder da. „Stummschaltung aufheben“ → beides weg.

- [ ] **Step 11: Commit**

```bash
git add UniFiCameraPopup/Services/SettingsStore.swift UniFiCameraPopup/Models/WebhookMapping.swift UniFiCameraPopup/Services/EventLog.swift UniFiCameraPopup/Services/ProtectSession.swift UniFiCameraPopup/Services/PopupController.swift UniFiCameraPopup/AppDelegate.swift UniFiCameraPopup/Views/PopupWindow.swift UniFiCameraPopup/Views/Onboarding/OnboardingView.swift UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "feat(mute): per-camera mute schedule, configurable durations, appearance and event log" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Einstellungsfenster mit Reiterleiste, Reiter Allgemein, Gerüste Ton und Unterwegs

**Files:**
- Create: `UniFiCameraPopup/Views/Settings/SettingsWindow.swift`, `GeneralTab.swift`, `SoundAndRemoteTabs.swift`
- Modify: `UniFiCameraPopup/Views/Onboarding/OnboardingWindow.swift` (ganze Datei, `show(startAt:)`)
- Modify: `UniFiCameraPopup/AppDelegate.swift` (`openSettings`, `AppActions.openHelp`)
- Modify: `project.pbxproj` (Gruppe Settings, drei Dateien)

**Interfaces:**
- Consumes: alle Bausteine aus Task 3; `SettingsStore`-Felder aus Task 4; `ProtectEventService.status`, `WebSocketClient.status`.
- Produces:
  - `enum SettingsTab: Int, CaseIterable, Identifiable { general, cameras, sound, remote }` mit `label`, `windowTitle`, `icon`
  - `@MainActor final class SettingsNavigation: ObservableObject` – `@Published var tab: SettingsTab`, `@Published var selectedEntry: UUID?`
  - `@MainActor enum AppActions { static var openHelp: () -> Void }`
  - `SettingsWindowController.shared.show(webSocketClient:protectEvents:tab:)`, `SettingsWindowController.shared.navigation`
  - `SettingsRootView(navigation:)` – Reiter `.cameras` zeigt bis Task 6 die alte `SettingsView()`
  - `GeneralTab()`, `SoundTab()`, `RemoteTab()`
  - `OnboardingWindow.show(startAt: OnboardingModel.Step = .welcome)`

- [ ] **Step 1: Fenster, Navigation, Reiterleiste**

`UniFiCameraPopup/Views/Settings/SettingsWindow.swift`:
```swift
import AppCore
import AppKit
import Combine
import SwiftUI

enum SettingsTab: Int, CaseIterable, Identifiable {
    case general
    case cameras
    case sound
    case remote

    var id: Int { rawValue }

    /// Tab button text.
    var label: String {
        switch self {
        case .general: return "Allgemein"
        case .cameras: return "Kameras"
        case .sound: return "Ton"
        case .remote: return "Unterwegs"
        }
    }

    /// Window title while the tab is shown (template title bar).
    var windowTitle: String {
        switch self {
        case .general: return "Allgemein"
        case .cameras: return "Kameras"
        case .sound: return "Ton & Sprechen"
        case .remote: return "Unterwegs"
        }
    }

    var icon: TemplateIcon {
        switch self {
        case .general: return .tabGeneral
        case .cameras: return .tabCameras
        case .sound: return .tabSound
        case .remote: return .tabRemote
        }
    }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var tab: SettingsTab = .general
    /// Camera selected in the Kameras tab (mapping entry id).
    @Published var selectedEntry: UUID?
}

/// Entry points owned by `AppDelegate` that SwiftUI views call
/// (with `@NSApplicationDelegateAdaptor`, `NSApp.delegate` is not our instance).
@MainActor
enum AppActions {
    static var openHelp: () -> Void = {}
}

/// Fixed 760 × 540 window with transparent title bar; the tab bar is drawn below it.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    let navigation = SettingsNavigation()
    private var window: NSWindow?
    private var titleObserver: AnyCancellable?

    private init() {}

    func show(webSocketClient: WebSocketClient, protectEvents: ProtectEventService, tab: SettingsTab? = nil) {
        if let tab {
            navigation.tab = tab
        }
        if window == nil {
            let root = SettingsRootView(navigation: navigation)
                .environmentObject(SettingsStore.shared)
                .environmentObject(webSocketClient)
                .environmentObject(protectEvents)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: root)
            window.title = navigation.tab.windowTitle
            window.center()
            titleObserver = navigation.$tab.sink { [weak window] tab in
                window?.title = tab.windowTitle
            }
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsRootView: View {
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                // Native title bar (traffic lights + centered title) sits on top of this.
                Color.clear.frame(height: 28)
                SettingsTabBar(selection: $navigation.tab)
            }
            .background(Tokens.bar.color)
            CardDivider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 760, height: 540)
        .background(Tokens.win.color)
        .foregroundStyle(Tokens.fg.color)
        .font(.system(size: 13))
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var content: some View {
        switch navigation.tab {
        case .general: GeneralTab()
        case .cameras: SettingsView()
        case .sound: SoundTab()
        case .remote: RemoteTab()
        }
    }
}

/// Centered tab buttons: 78 wide, padding 5/0, radius 7, icon 20 + 3 + label 11.
struct SettingsTabBar: View {
    @Binding var selection: SettingsTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { tab in
                let isOn = tab == selection
                Button { selection = tab } label: {
                    VStack(spacing: 3) {
                        tab.icon.image(size: 20)
                        Text(tab.label).font(.system(size: 11))
                    }
                    .foregroundStyle(isOn ? Tokens.accText.color : Tokens.muted.color)
                    .frame(width: 78)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(isOn ? Tokens.tabOn.color : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }
}
```

- [ ] **Step 2: Einrichtung an beliebigem Schritt öffnen**

`UniFiCameraPopup/Views/Onboarding/OnboardingWindow.swift` komplett ersetzen:
```swift
import AppKit
import SwiftUI

@MainActor
enum OnboardingWindow {
    private static var window: NSWindow?

    /// `.console` / `.key` start an existing setup at that step ("Ändern …", "Ersetzen …");
    /// `.cameras` reuses host and key and continues at step 4 ("Kamera hinzufügen").
    static func show(startAt step: OnboardingModel.Step = .welcome) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let model = OnboardingModel()
        let settings = SettingsStore.shared
        switch step {
        case .welcome:
            break
        case .console:
            model.selectedHost = settings.protectHost
            model.step = .console
            model.scan()
        case .key:
            model.selectedHost = settings.protectHost
            model.step = .key
        case .cameras, .triggers:
            model.selectedHost = settings.protectHost
            model.apiKey = settings.protectAPIKey
            model.step = .key
            model.checkKey()
        }

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

- [ ] **Step 3: Reiter Allgemein**

`UniFiCameraPopup/Views/Settings/GeneralTab.swift` (Prüfgrundlage `docs/design/einstellungen-allgemein.md`; Funktionen aus der alten `SettingsView` übernommen):
```swift
import AppCore
import AppKit
import ProtectKit
import SwiftUI
import UniformTypeIdentifiers

/// Einstellungen › Allgemein (docs/design/einstellungen-allgemein.md).
struct GeneralTab: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var webSocketClient: WebSocketClient
    @EnvironmentObject private var protectEvents: ProtectEventService
    @ObservedObject private var protect = ProtectSession.shared

    @State private var advancedExpanded = false
    @State private var dndHasFullDiskAccess = true
    @State private var launchRequiresApproval = false
    @State private var pendingImportData: Data?
    @State private var transferError: String?
    @State private var probingCertificate = false
    @State private var trustProbeError: String?
    @State private var pendingFingerprint: String?
    @State private var showRegenerateConfirm = false
    @State private var copiedWebhookURL = false
    @State private var copiedBearerToken = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                connectionCard
                preferencesCard
                muteSection
                footer
                if advancedExpanded {
                    advanced
                }
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 40)
        }
        .onAppear {
            refreshDNDPermission()
            refreshLaunchApprovalState()
        }
        .onChange(of: settings.disableDuringDND) { _ in refreshDNDPermission() }
        .onChange(of: settings.launchAtLogin) { _ in refreshLaunchApprovalState() }
        .alert("Neuem Zertifikat vertrauen?", isPresented: Binding(
            get: { pendingFingerprint != nil },
            set: { if !$0 { pendingFingerprint = nil } }
        )) {
            Button("Vertrauen") { confirmPendingFingerprint() }
            Button("Abbrechen", role: .cancel) { pendingFingerprint = nil }
        } message: {
            Text("Das Zertifikat deiner Konsole hat sich geändert. Bestätige nur, wenn du es selbst geändert hast (z. B. nach einem Konsolen-Update). Neuer Fingerabdruck:\n\n\(pendingFingerprint ?? "")")
        }
        .alert("Neue ID generieren?", isPresented: $showRegenerateConfirm) {
            Button("Abbrechen", role: .cancel) {}
            Button("Neue ID", role: .destructive) { settings.regenerateInstallationId() }
        } message: {
            Text("Die Webhook-Adressen ändern sich. Du musst die Webhooks in UniFi Protect anschließend neu eintragen.")
        }
        .alert("Konfiguration importieren?", isPresented: Binding(
            get: { pendingImportData != nil },
            set: { if !$0 { pendingImportData = nil } }
        )) {
            Button("Abbrechen", role: .cancel) { pendingImportData = nil }
            Button("Importieren", role: .destructive) { confirmImport() }
        } message: {
            Text("Die aktuelle Konfiguration wird vollständig ersetzt – einschließlich der eindeutigen ID und aller Kameras.")
        }
        .alert("Import fehlgeschlagen", isPresented: Binding(
            get: { transferError != nil },
            set: { if !$0 { transferError = nil } }
        ), presenting: transferError) { _ in
            Button("OK", role: .cancel) { transferError = nil }
        } message: { message in
            Text(message)
        }
    }

    // MARK: Konsole

    private var connectionCard: some View {
        Card {
            CardRow(title: "Konsole", vertical: 11) {
                HStack(spacing: 6) {
                    Circle().fill(consoleDotColor).frame(width: 8, height: 8)
                    Text(consoleText).lineLimit(1).truncationMode(.middle)
                }
                .foregroundStyle(Tokens.muted.color)
                Button(settings.protectHost.isEmpty ? "Einrichten …" : "Ändern …") {
                    OnboardingWindow.show(startAt: settings.protectHost.isEmpty ? .welcome : .console)
                }
                .buttonStyle(FieldButtonStyle())
            }
            CardDivider()
            CardRow(title: "API-Schlüssel", vertical: 11) {
                Text(settings.protectAPIKey.isEmpty ? "nicht hinterlegt" : "im Schlüsselbund")
                    .foregroundStyle(Tokens.muted.color)
                Button("Ersetzen …") { OnboardingWindow.show(startAt: .key) }
                    .buttonStyle(FieldButtonStyle())
                    .disabled(settings.protectHost.isEmpty)
            }
            if let error = protect.lastError {
                CardDivider()
                connectionErrorRow(error)
            }
        }
    }

    private var consoleText: String {
        let host = settings.protectHost
        guard !host.isEmpty else { return "nicht eingerichtet" }
        if let name = settings.protectConsoleName, !name.isEmpty {
            return "\(name) · \(host)"
        }
        return host
    }

    private var consoleDotColor: Color {
        guard settings.isProtectConfigured else { return Tokens.toggleOff.color }
        if protect.lastError != nil { return Color(nsColor: .systemOrange) }
        switch protectEvents.status {
        case .connected: return Tokens.statusGreen.color
        case .connecting: return Color(nsColor: .systemOrange)
        case .disconnected, .outdated: return Color(nsColor: .systemRed)
        }
    }

    private func connectionErrorRow(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(error)
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: .systemOrange))
                .fixedSize(horizontal: false, vertical: true)
            if error == ProtectError.certificateChanged.errorDescription {
                HStack(spacing: 8) {
                    Button(probingCertificate ? "Prüfe …" : "Neuem Zertifikat vertrauen") {
                        probeNewCertificate()
                    }
                    .buttonStyle(FieldButtonStyle())
                    .disabled(probingCertificate)
                    if let trustProbeError {
                        Text(trustProbeError)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(nsColor: .systemRed))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
    }

    // MARK: Darstellung und Verhalten

    private var preferencesCard: some View {
        Card {
            CardRow(title: "Erscheinungsbild") {
                TokenSegmented(
                    selection: $settings.appearance,
                    options: AppearanceMode.allCases.map { (value: $0, title: $0.label) }
                )
            }
            CardDivider()
            CardRow(title: "Popup-Position") {
                PopUpField(
                    selection: $settings.defaultPosition,
                    options: PopupPosition.allCases.map { (value: $0, title: $0.label) }
                )
            }
            CardDivider()
            CardToggleRow(title: "Im Fokus-Modus keine Popups", isOn: $settings.disableDuringDND)
            if settings.disableDuringDND && !dndHasFullDiskAccess {
                CardDivider()
                hintRow(
                    "Ohne „Festplattenvollzugriff“ kann der Fokus-Status nicht erkannt werden. Aktiviere „UniFi Camera Popup“ in der Liste und starte die App danach neu.",
                    button: "Festplattenvollzugriff öffnen",
                    action: openFullDiskAccessSettings
                )
            }
            CardDivider()
            CardToggleRow(title: "Bei Anmeldung starten", isOn: $settings.launchAtLogin)
            if launchRequiresApproval {
                CardDivider()
                hintRow(
                    "„UniFi Camera Popup“ muss in den Anmeldeobjekten freigegeben werden, sonst startet die App nicht automatisch.",
                    button: "Anmeldeobjekte öffnen",
                    action: LaunchAtLoginHelper.openLoginItemsSettings
                )
            }
        }
    }

    private func hintRow(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Tokens.muted.color)
                .fixedSize(horizontal: false, vertical: true)
            Button(button, action: action).buttonStyle(FieldButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }

    // MARK: Stummschalten

    private var muteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Stummschalten (Menüleiste)")
            Card {
                CardRow(title: "Kurz", vertical: 9) {
                    DurationField(duration: $settings.muteShort, accessibilityLabel: "Kurze Dauer")
                }
                CardDivider()
                CardRow(title: "Lang", vertical: 9) {
                    DurationField(duration: $settings.muteLong, accessibilityLabel: "Lange Dauer")
                }
            }
        }
    }

    // MARK: Export / Erweitert

    private var footer: some View {
        HStack(spacing: 8) {
            DisclosureButton(title: "Erweitert", expanded: $advancedExpanded)
            Spacer()
            Button("Konfiguration exportieren …") { exportConfiguration() }
                .buttonStyle(FieldButtonStyle(vertical: 4, horizontal: 12))
                .help("Die Exportdatei enthält deine eindeutige ID und die Bearer-Tokens der Buttons – teile sie nur mit deinen eigenen Geräten. Der API-Schlüssel bleibt im Schlüsselbund.")
            Button("Importieren …") { chooseConfigurationToImport() }
                .buttonStyle(FieldButtonStyle(vertical: 4, horizontal: 12))
        }
    }

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Popup")
                Card {
                    CardRow(title: "Bildschirm") {
                        PopUpField(
                            selection: $settings.screenTarget,
                            options: ScreenTarget.allCases.map { (value: $0, title: $0.label) }
                        )
                    }
                    CardDivider()
                    sliderRow("Randabstand", value: $settings.edgeMargin, range: 0...120, step: 1,
                              text: "\(Int(settings.edgeMargin)) px")
                    CardDivider()
                    sliderRow("Automatisch schließen", value: $settings.autoCloseTimeout, range: 0...300, step: 5,
                              text: settings.autoCloseTimeout > 0 ? "\(Int(settings.autoCloseTimeout)) s" : "Aus")
                    CardDivider()
                    CardToggleRow(
                        title: "Alle aktiven Kameras zeigen",
                        subtitle: "Jede auslösende Kamera bekommt ein eigenes Popup, untereinander gestapelt. Ohne diese Option ersetzt eine neue Kamera das aktuelle Popup.",
                        isOn: $settings.showAllActiveCameras
                    )
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Updates")
                Card {
                    CardToggleRow(title: "Automatisch aktualisieren", isOn: $settings.autoUpdate)
                    CardDivider()
                    CardRow(title: "Version") {
                        Text("\(AppConfig.shortVersion) (\(AppConfig.buildNumber))")
                            .foregroundStyle(Tokens.muted.color)
                    }
                }
            }
            relaySection
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Hilfe")
                Card {
                    CardRow(title: "Anleitung und Problemlösung") {
                        Button("Hilfe öffnen") { AppActions.openHelp() }.buttonStyle(FieldButtonStyle())
                    }
                }
            }
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, text: String) -> some View {
        HStack(spacing: 10) {
            Text(title).frame(width: 170, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .controlSize(.small)
                .tint(Tokens.accent.color)
            Text(text)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Tokens.muted.color)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }

    private var relaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Webhooks (Relay-Server)")
            Card {
                FixedLabelRow(title: "Verbindung", width: 140, vertical: 10, horizontal: 14) {
                    HStack(spacing: 6) {
                        Circle().fill(relayDotColor).frame(width: 8, height: 8)
                        Text(webSocketClient.status == .outdated
                             ? "Veraltete App-Version. Bitte aktualisiere die App."
                             : webSocketClient.status.menuLabel)
                    }
                    .foregroundStyle(Tokens.muted.color)
                    Spacer(minLength: 0)
                }
                CardDivider()
                FixedLabelRow(title: "Eindeutige ID", width: 140, vertical: 10, horizontal: 14) {
                    monoText(settings.installationId)
                    Button("Neue ID …") { showRegenerateConfirm = true }.buttonStyle(FieldButtonStyle())
                }
                CardDivider()
                FixedLabelRow(title: "Webhook-Adresse", width: 140, vertical: 10, horizontal: 14) {
                    monoText(webhookURL)
                    Button(copiedWebhookURL ? "Kopiert" : "Kopieren") { copyWebhookURL() }.buttonStyle(FieldButtonStyle())
                }
                CardDivider()
                FixedLabelRow(title: "Bearer-Token", width: 140, vertical: 10, horizontal: 14) {
                    monoText(AppConfig.webhookToken)
                    Button(copiedBearerToken ? "Kopiert" : "Kopieren") { copyBearerToken() }.buttonStyle(FieldButtonStyle())
                }
                CardDivider()
                Text("\(AppConfig.webhookSlugPlaceholder) durch die Webhook-ID der Kamera ersetzen. Das Token gehört im UniFi Alarm Manager unter „Authentifizierung“ → „Bearer“.")
                    .font(.system(size: 11))
                    .foregroundStyle(Tokens.muted.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
            }
        }
    }

    private func monoText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Tokens.muted.color)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var relayDotColor: Color {
        switch webSocketClient.status {
        case .connected: return Tokens.statusGreen.color
        case .connecting: return Color(nsColor: .systemOrange)
        case .disconnected, .outdated: return Color(nsColor: .systemRed)
        }
    }

    // MARK: Actions (from the former SettingsView)

    private var webhookURL: String {
        AppConfig.webhookURL(installationId: settings.installationId)
    }

    private func copyWebhookURL() {
        copyToPasteboard(webhookURL)
        copiedWebhookURL = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copiedWebhookURL = false
        }
    }

    private func copyBearerToken() {
        copyToPasteboard(AppConfig.webhookToken)
        copiedBearerToken = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copiedBearerToken = false
        }
    }

    private func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private func exportConfiguration() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "unifi-camera-popup-config.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settings.exportedConfigurationData().write(to: url)
        } catch {
            transferError = error.localizedDescription
        }
    }

    private func chooseConfigurationToImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // Hold the file contents until the user confirms the overwrite.
            pendingImportData = try Data(contentsOf: url)
        } catch {
            transferError = error.localizedDescription
        }
    }

    private func confirmImport() {
        guard let data = pendingImportData else { return }
        pendingImportData = nil
        do {
            try settings.importConfiguration(from: data)
            // Host, key or pin may have changed; rebuild the client (and with it the event socket).
            ProtectSession.shared.reconnect()
        } catch {
            transferError = error.localizedDescription
        }
    }

    private func refreshDNDPermission() {
        dndHasFullDiskAccess = settings.disableDuringDND ? DoNotDisturbChecker.hasFullDiskAccess : true
    }

    private func refreshLaunchApprovalState() {
        launchRequiresApproval = settings.launchAtLogin && LaunchAtLoginHelper.requiresApproval
    }

    private func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Phase 1 of re-trust: read the presented fingerprint without sending the API key.
    private func probeNewCertificate() {
        probingCertificate = true
        trustProbeError = nil
        let host = settings.protectHost
        Task {
            defer { probingCertificate = false }
            do {
                pendingFingerprint = try await ProtectClient.probeFingerprint(host: host)
            } catch {
                trustProbeError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Phase 2: only after explicit confirmation is the pin replaced; reconnect then connects pinned to it.
    private func confirmPendingFingerprint() {
        guard let fingerprint = pendingFingerprint else { return }
        pendingFingerprint = nil
        settings.protectCertificateFingerprint = fingerprint
        ProtectSession.shared.reconnect()
    }
}
```

- [ ] **Step 4: Gerüste Ton und Unterwegs**

`UniFiCameraPopup/Views/Settings/SoundAndRemoteTabs.swift` (Prüfgrundlage `docs/design/einstellungen-ton.md`, `einstellungen-unterwegs.md`):
```swift
import AppCore
import SwiftUI

/// Einstellungen › Ton – layout of the template with its sample content, not interactive
/// until talkback and announcements exist (docs/design/einstellungen-ton.md).
struct SoundTab: View {
    private struct SampleSound: Identifiable {
        let id: String
        let length: String
        let tag: String
        let selected: Bool
        var isMP3: Bool { tag == "MP3" }
    }

    private let samples = [
        SampleSound(id: "Gong", length: "0:02", tag: "MP3", selected: false),
        SampleSound(id: "Bin gleich da", length: "0:03", tag: "KI-STIMME", selected: true),
        SampleSound(id: "Paket bitte abstellen", length: "0:05", tag: "KI-STIMME", selected: false),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                SectionLabel(text: "Ansagen für „Ton abspielen“")
                Card {
                    ForEach(samples) { sound in
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(Tokens.accSoft.color).frame(width: 22, height: 22)
                                TemplateIcon.play.image(size: 9).foregroundStyle(Tokens.accText.color)
                            }
                            Text(sound.id).fontWeight(.medium).frame(maxWidth: .infinity, alignment: .leading)
                            Text(sound.length)
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(Tokens.muted.color)
                            Text(sound.tag)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.vertical, 2)
                                .padding(.horizontal, 6)
                                .foregroundStyle(sound.isMP3 ? Tokens.muted.color : Tokens.accText.color)
                                .background(RoundedRectangle(cornerRadius: 4)
                                    .fill(sound.isMP3 ? Tokens.btn2.color : Tokens.accSoft.color))
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(sound.selected ? Tokens.accSoft.color : Color.clear)
                        CardDivider()
                    }
                    HStack(spacing: 14) {
                        Button("MP3 hinzufügen …") {}.buttonStyle(LinkButtonStyle())
                        Button("Ansage aus Text …") {}.buttonStyle(LinkButtonStyle())
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("„Bin gleich da“").fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading)
                    TokenSegmented(selection: .constant(1), options: [(value: 0, title: "MP3-Datei"), (value: 1, title: "KI-Stimme")])
                }
                TokenTextField(placeholder: "", text: .constant("Bin gleich da! Einen kleinen Moment, bitte."),
                               fontSize: 13, vertical: 5, horizontal: 8, radius: 6)
                HStack(spacing: 8) {
                    Text("Stimme").font(.system(size: 12)).foregroundStyle(Tokens.muted.color)
                    PopUpField(selection: .constant(0), options: [(value: 0, title: "Anna (Premium) · macOS")])
                    Spacer()
                    Button("Anhören") {}.buttonStyle(FieldButtonStyle())
                    Button("Übernehmen") {}.buttonStyle(AccentButtonStyle(fontSize: 12, vertical: 3, horizontal: 10))
                }
                Text("Wird auf diesem Mac erzeugt – ohne Internet, ohne Konto.")
                    .font(.system(size: 11))
                    .foregroundStyle(Tokens.muted.color)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Tokens.group.color))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Tokens.accent.color, lineWidth: 1))

            Card {
                CardRow(title: "Mikrofon") {
                    PopUpField(selection: .constant(0), options: [(value: 0, title: "MacBook Pro-Mikrofon")])
                }
                CardDivider()
                CardRow(title: "Sprechen") {
                    TokenSegmented(selection: .constant(0), options: [(value: 0, title: "Leertaste halten"), (value: 1, title: "Umschalten")])
                }
                CardDivider()
                CardRow(title: "Lautstärke an der Kamera") { VolumeTrack() }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 40)
        .allowsHitTesting(false)
    }
}

/// Einstellungen › Unterwegs – layout of the template with its sample content, not interactive
/// until the tunnel exists (docs/design/einstellungen-unterwegs.md).
struct RemoteTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Tokens.accent.color).frame(width: 40, height: 40)
                    TemplateIcon.shieldCheck.image(size: 20).foregroundStyle(Color.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bereit · gerade zu Hause").font(.system(size: 14, weight: .bold))
                    Text("Der Tunnel springt an, sobald die Konsole nicht direkt erreichbar ist.")
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.muted.color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Jetzt testen") {}.buttonStyle(FieldButtonStyle(vertical: 4, horizontal: 12))
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Tokens.accSoft.color))

            Card {
                FixedLabelRow(title: "Konfiguration", width: 140, vertical: 10, horizontal: 14) {
                    Text("macbook-camera-popup.conf").foregroundStyle(Tokens.muted.color).frame(maxWidth: .infinity, alignment: .leading)
                    Button("Ersetzen …") {}.buttonStyle(FieldButtonStyle())
                }
                CardDivider()
                FixedLabelRow(title: "Gegenstelle", width: 140, vertical: 10, horizontal: 14) {
                    Text("[DEINE-HEIM-ADRESSE]:51820").foregroundStyle(Tokens.muted.color).frame(maxWidth: .infinity, alignment: .leading)
                }
                CardDivider()
                FixedLabelRow(title: "Letzte Verbindung", width: 140, vertical: 10, horizontal: 14) {
                    Text("gestern, 18:22 · über Mobilfunk").foregroundStyle(Tokens.muted.color).frame(maxWidth: .infinity, alignment: .leading)
                }
                CardDivider()
                CardRow(title: "Tunnel verwenden") {
                    PopUpField(selection: .constant(0), options: [(value: 0, title: "Automatisch")])
                }
            }

            HStack {
                Button("Anleitung: WireGuard auf dem UniFi-Gateway einrichten") {}.buttonStyle(LinkButtonStyle())
                Spacer()
                Button("Tunnel entfernen") {}.buttonStyle(LinkButtonStyle(color: Tokens.muted))
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 40)
        .allowsHitTesting(false)
    }
}
```

- [ ] **Step 5: AppDelegate verdrahten**

In `UniFiCameraPopup/AppDelegate.swift`:
1. `private var settingsWindow: NSWindow?` löschen.
2. In `applicationDidFinishLaunching` nach `settings.pruneMutes()`:
```swift
        AppActions.openHelp = { [weak self] in self?.openHelp() }
```
3. `openSettings()` ersetzen durch:
```swift
    @objc private func openSettings() {
        SettingsWindowController.shared.show(webSocketClient: webSocketClient, protectEvents: protectEvents)
    }
```

- [ ] **Step 6: pbxproj**

PBXBuildFile:
```
		A10000000000000000000073 /* SettingsWindow.swift in Sources */ = {isa = PBXBuildFile; fileRef = A20000000000000000000073 /* SettingsWindow.swift */; };
		A10000000000000000000074 /* GeneralTab.swift in Sources */ = {isa = PBXBuildFile; fileRef = A20000000000000000000074 /* GeneralTab.swift */; };
		A10000000000000000000078 /* SoundAndRemoteTabs.swift in Sources */ = {isa = PBXBuildFile; fileRef = A20000000000000000000078 /* SoundAndRemoteTabs.swift */; };
```
PBXFileReference:
```
		A20000000000000000000073 /* SettingsWindow.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SettingsWindow.swift; sourceTree = "<group>"; };
		A20000000000000000000074 /* GeneralTab.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GeneralTab.swift; sourceTree = "<group>"; };
		A20000000000000000000078 /* SoundAndRemoteTabs.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SoundAndRemoteTabs.swift; sourceTree = "<group>"; };
```
Neue Gruppe nach der Design-Gruppe:
```
		A40000000000000000000071 /* Settings */ = {
			isa = PBXGroup;
			children = (
				A20000000000000000000073 /* SettingsWindow.swift */,
				A20000000000000000000074 /* GeneralTab.swift */,
				A20000000000000000000078 /* SoundAndRemoteTabs.swift */,
			);
			path = Settings;
			sourceTree = "<group>";
		};
```
In `A40000000000000000000006 /* Views */` nach `A40000000000000000000070 /* Design */,`: `A40000000000000000000071 /* Settings */,`. Sources-Phase: die drei `A1…73/74/78`-Zeilen ans Ende der `files`.

- [ ] **Step 7: Lint und Build**

`plutil -lint …` → OK; Build → `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Sichtprüfung gegen `docs/design/einstellungen-allgemein.md`, `-ton.md`, `-unterwegs.md`**

App starten, Menü › „Einstellungen…“. Prüfen (jeweils Hell und Dunkel über das eigene Segment „Erscheinungsbild“):
1. Fenster 760 × 540, nicht in der Größe veränderbar, Titel wechselt mit dem Reiter („Ton & Sprechen“ beim Reiter „Ton“).
2. Reiterleiste: vier Reiter, aktiver mit `tabOn`-Fläche und `accText`.
3. Allgemein in der Reihenfolge der Spezifikation; Segment schaltet das ganze Fenster sofort um; „System“ folgt dem macOS-Erscheinungsbild.
4. „Kurz“: „0“ eintippen + Return → „1“; „abc“ + Return → alter Wert bleibt; Einheit über das Menü auf „Stunden“ stellen.
5. „Erweitert“ klappt auf; alle früheren Einstellungen (Bildschirm, Randabstand, Auto-Schließen, Alle aktiven Kameras, Automatisch aktualisieren, Eindeutige ID, Webhook-Adresse, Bearer-Token, Hilfe) sind da und wirken.
6. Reiter Kameras zeigt vorerst die alte Liste (wird in Task 6 ersetzt).
7. Ton und Unterwegs entsprechen den Spezifikationen und reagieren nicht auf Klicks.

- [ ] **Step 9: Commit**

```bash
git add UniFiCameraPopup/Views/Settings UniFiCameraPopup/Views/Onboarding/OnboardingWindow.swift UniFiCameraPopup/AppDelegate.swift UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "feat(settings): template settings window with tab bar, Allgemein tab, Ton and Unterwegs scaffolds" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Reiter Kameras mit Erweitert und Button-Sheet; alte Einstellungsansicht entfällt

**Files:**
- Create: `UniFiCameraPopup/Views/Settings/CamerasTab.swift`, `CameraAdvancedSection.swift`, `ActionEditorSheet.swift`
- Modify: `UniFiCameraPopup/Views/HotkeyRecorderView.swift` (ganze Datei, Zeile im Vorlagenstil)
- Modify: `UniFiCameraPopup/Views/Onboarding/OnboardingView.swift:448-518` (`TriggerChips`, `FlowLayout`)
- Modify: `UniFiCameraPopup/Services/CameraActionService.swift` (HTTP-Status zurückgeben)
- Modify: `UniFiCameraPopup/Views/Settings/SettingsWindow.swift` (Reiter Kameras)
- Delete: `UniFiCameraPopup/Views/SettingsView.swift`
- Modify: `project.pbxproj` (drei Dateien neu, SettingsView raus)

**Interfaces:**
- Consumes: `SettingsNavigation`, Bausteine (Task 3), `EventLog.lastTriggered(entryId:)`, `ProtectSession.snapshot`, `SettingsStore.muteSchedule`/`removeMapping`, `ActionIcon`, `CameraAction.icon/confirmBeforeRun`, `WebhookMapping.chimeOnOpen` (Task 4), `TriggerKind.chips`/`displayOrder` (Task 2), `DisplayText` (Task 1), `OnboardingWindow.show(startAt:)` (Task 5).
- Produces:
  - `CamerasTab(navigation:)`, `CamerasTab.displayName(_: WebhookMapping) -> String` (static), `CameraDetail(mapping:onRemoved:)`, `CameraThumbnail(cameraId:band:)`, `ActionRowLayout`, `ActionEditorContext`
  - `CameraAdvancedSection(mapping:lastTriggered:onRemove:)`
  - `ActionEditorSheet(action:isNew:onSave:onDelete:)`
  - `HotkeyRecorderView(hotkey:conflictMessage:)` – zeichnet jetzt die Vorlagen-Zeile (einziger Aufrufer war die alte `SettingsView`)
  - `TriggerChips(camera:selection:size:)` mit `enum Size { regular, small }`; `FlowLayout(spacing:alignment:)`
  - `CameraActionService.trigger(_:) async throws -> Int` (`@discardableResult`)

- [ ] **Step 1: Chips und Umbruch nach Vorlage**

In `OnboardingView.swift` alles ab `/// Toggle chips for trigger kinds; shared with the settings view.` bis Dateiende ersetzen durch:
```swift
/// Toggle chips for trigger kinds; shared with the settings.
/// `.regular`: onboarding (13 pt, on 7/14, off 6/13, centered, gap 8).
/// `.small`: Einstellungen › Kameras (12 pt, on 4/11, off 3/10, leading, gap 6).
struct TriggerChips: View {
    enum Size {
        case regular
        case small
    }

    let camera: ProtectCamera
    @Binding var selection: Set<TriggerKind>
    var size: Size = .regular

    var body: some View {
        FlowLayout(spacing: size == .regular ? 8 : 6, alignment: size == .regular ? .center : .leading) {
            ForEach(TriggerKind.chips(supported: camera.supportedTriggers), id: \.kind) { chip in
                let isOn = chip.isSupported && selection.contains(chip.kind)
                Button {
                    if isOn { selection.remove(chip.kind) } else { selection.insert(chip.kind) }
                } label: {
                    label(chip.kind.label, isOn: isOn, isSupported: chip.isSupported)
                }
                .buttonStyle(.plain)
                .allowsHitTesting(chip.isSupported)
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                .accessibilityHint(chip.isSupported ? "" : "Kann diese Kamera nicht")
            }
        }
    }

    @ViewBuilder
    private func label(_ text: String, isOn: Bool, isSupported: Bool) -> some View {
        let fontSize: CGFloat = size == .regular ? 13 : 12
        if isOn {
            Text(text)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.vertical, size == .regular ? 7 : 4)
                .padding(.horizontal, size == .regular ? 14 : 11)
                .background(Capsule().fill(Tokens.accent.color))
        } else if isSupported {
            Text(text)
                .font(.system(size: fontSize))
                .foregroundStyle(Tokens.fg.color)
                .padding(.vertical, size == .regular ? 6 : 3)
                .padding(.horizontal, size == .regular ? 13 : 10)
                .background(Capsule().fill((size == .regular ? Tokens.mainChipOff : Tokens.chipOff).color))
                .overlay(Capsule().strokeBorder(Tokens.chipBorder.color, lineWidth: 1))
        } else {
            Text(text)
                .font(.system(size: fontSize))
                .strikethrough()
                .foregroundStyle(Tokens.naFg.color)
                .padding(.vertical, size == .regular ? 6 : 3)
                .padding(.horizontal, size == .regular ? 13 : 10)
                .overlay(Capsule().strokeBorder(Tokens.chipBorder.color, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
        }
    }
}

/// Minimal wrapping layout (macOS 13+).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var alignment: HorizontalAlignment = .center

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = alignment == .leading ? bounds.minX : bounds.minX + (bounds.width - row.width) / 2
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
Oben in `OnboardingView.swift` `import AppCore` ergänzen.

- [ ] **Step 2: Tastenkürzel als Vorlagen-Zeile**

`UniFiCameraPopup/Views/HotkeyRecorderView.swift` komplett ersetzen:
```swift
import AppCore
import AppKit
import SwiftUI

struct HotkeyRecorderView: View {
    @Binding var hotkey: CameraHotkey?
    var conflictMessage: String?

    @State private var isRecording = false
    @State private var recordedFirstStep: CameraHotkey.HotkeyStep?
    @State private var monitor: Any?
    @State private var hasAccessibilityAccess = AccessibilityHelper.isTrusted

    private var recordingHint: String {
        if recordedFirstStep != nil {
            return "Dann 1 drücken (⌘ kann gedrückt bleiben). Enter = nur ⌘K. Esc = Abbrechen."
        }
        return "Erst ⌘K, dann 1. Oder nur eine Kombination + Enter. Esc = Abbrechen, ⌫ = Löschen."
    }

    private var needsAccessibilityWarning: Bool {
        hotkey?.isSequence == true && !hasAccessibilityAccess
    }

    private var keyText: String {
        if isRecording {
            if let recordedFirstStep { return "\(stepLabel(recordedFirstStep)), …" }
            return "Taste drücken…"
        }
        return hotkey?.displayString ?? "Kein Shortcut"
    }

    /// Template row: "Tastenkürzel" left, key chip right (12 pt, padding 2/8, radius 5).
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            keyRow
            messages
        }
        .onAppear { refreshAccessibilityAccess() }
        .onDisappear { stopRecording() }
    }

    private var keyRow: some View {
        HStack(spacing: 10) {
            Text("Tastenkürzel").frame(maxWidth: .infinity, alignment: .leading)
            Button(action: toggleRecording) {
                Text(keyText)
                    .font(.system(size: 12))
                    .foregroundStyle(isRecording || hotkey == nil ? Tokens.muted.color : Tokens.fg.color)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Tokens.field.color))
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(isRecording ? Tokens.accent.color : Tokens.chipBorder.color, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tastenkürzel")
            .accessibilityValue(hotkey?.displayString ?? "keins")
        }
    }

    @ViewBuilder
    private var messages: some View {
        if let conflictMessage {
            Label(conflictMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if needsAccessibilityWarning {
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    "Sequenz-Shortcuts brauchen „Bedienungshilfen“, um im Hintergrund zu funktionieren.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                Button("Bedienungshilfen öffnen") { AccessibilityHelper.openSettings() }
                    .controlSize(.small)
            }
        } else if isRecording {
            Text(recordingHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func refreshAccessibilityAccess() {
        hasAccessibilityAccess = AccessibilityHelper.isTrusted
    }

    private func stepLabel(_ step: CameraHotkey.HotkeyStep) -> String {
        CameraHotkey(steps: [step]).displayString
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        recordedFirstStep = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .keyDown {
                if event.keyCode == 53 {
                    stopRecording()
                    return nil
                }
                if event.keyCode == 51 || event.keyCode == 117, recordedFirstStep == nil {
                    hotkey = nil
                    stopRecording()
                    return nil
                }
                if event.keyCode == 36 || event.keyCode == 76, let recordedFirstStep {
                    hotkey = CameraHotkey(steps: [recordedFirstStep])
                    stopRecording()
                    return nil
                }

                if recordedFirstStep == nil {
                    if let first = CameraHotkey(firstStep: event)?.steps.first {
                        recordedFirstStep = first
                    }
                } else if let second = CameraHotkey(secondStep: event)?.steps.first,
                          let first = recordedFirstStep {
                    hotkey = CameraHotkey(steps: [first, second]).normalized()
                    stopRecording()
                }
                return nil
            }
            return event
        }
    }

    private func stopRecording() {
        isRecording = false
        recordedFirstStep = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
```

- [ ] **Step 3: HTTP-Status beim Button-Test**

In `CameraActionService.swift` die Signatur `static func trigger(_ action: CameraAction) async throws {` ersetzen durch:
```swift
    /// Calls the webhook; returns the HTTP status (2xx) for the sheet's test result.
    @discardableResult
    static func trigger(_ action: CameraAction) async throws -> Int {
```
und nach dem letzten `guard (200..<300).contains(http.statusCode) else { … }` ergänzen: `return http.statusCode`.

- [ ] **Step 4: Sheet „Button bearbeiten“**

`UniFiCameraPopup/Views/Settings/ActionEditorSheet.swift` (Prüfgrundlage `einstellungen-kameras.md`, S4):
```swift
import AppCore
import AppKit
import SwiftUI

/// Edits one popup button (template "Button bearbeiten (Sheet)").
struct ActionEditorSheet: View {
    private enum TestState: Equatable {
        case idle
        case running
        case succeeded(Int)
        case failed(String)
    }

    @State private var draft: CameraAction
    private let originalTitle: String
    private let onSave: (CameraAction) -> Void
    private let onDelete: (() -> Void)?
    @State private var test: TestState = .idle
    @Environment(\.dismiss) private var dismiss

    init(action: CameraAction, isNew: Bool, onSave: @escaping (CameraAction) -> Void, onDelete: (() -> Void)?) {
        _draft = State(initialValue: action)
        originalTitle = isNew ? "" : action.trimmedTitle
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(originalTitle.isEmpty ? "Neuer Button" : "Button „\(originalTitle)“")
                .font(.system(size: 15, weight: .bold))
            FormLine(label: "Beschriftung") {
                TokenTextField(placeholder: "z. B. Tür öffnen", text: $draft.title,
                               fontSize: 13, vertical: 5, horizontal: 8, radius: 6)
            }
            FormLine(label: "Symbol") {
                HStack(spacing: 6) {
                    ForEach(ActionIcon.allCases) { icon in
                        let isOn = draft.icon == icon
                        Button { draft.icon = icon } label: {
                            icon.templateIcon.image(size: 16)
                                .foregroundStyle(isOn ? Color.white : Tokens.fg.color)
                                .frame(width: 30, height: 30)
                                .background(RoundedRectangle(cornerRadius: 7)
                                    .fill(isOn ? Tokens.accent.color : Tokens.btn2.color))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(icon.label)
                        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }
            FormLine(label: "Methode") {
                TokenSegmented(
                    selection: $draft.method,
                    options: CameraAction.Method.allCases.map { (value: $0, title: $0.rawValue) },
                    width: 120
                )
            }
            FormLine(label: "Adresse") {
                TokenTextField(placeholder: "https://…", text: $draft.url,
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
            if let urlWarning {
                FormLine(label: "") {
                    Text(urlWarning).font(.system(size: 11)).foregroundStyle(Color(nsColor: .systemOrange))
                }
            }
            HStack(spacing: 10) {
                Text("Vor dem Ausführen nachfragen").frame(maxWidth: .infinity, alignment: .leading)
                TokenSwitch(isOn: $draft.confirmBeforeRun, label: "Vor dem Ausführen nachfragen")
            }
            testResult
            HStack(spacing: 8) {
                Button(test == .running ? "Teste …" : "Testen", action: runTest)
                    .buttonStyle(FieldButtonStyle(fontSize: 13, vertical: 5, horizontal: 12))
                    .disabled(!draft.isConfigured || test == .running)
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
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(AccentButtonStyle(fontSize: 13, vertical: 5, horizontal: 14))
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.isConfigured)
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(width: 480)
        .background(Tokens.win.color)
        .foregroundStyle(Tokens.fg.color)
        .font(.system(size: 13))
    }

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

    private var urlWarning: String? {
        let trimmed = draft.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, draft.requestURL == nil else { return nil }
        return "Bitte eine gültige http:// oder https:// Adresse eintragen."
    }

    private func runTest() {
        let snapshot = draft
        test = .running
        Task {
            do {
                test = .succeeded(try await CameraActionService.trigger(snapshot))
            } catch {
                test = .failed(error.localizedDescription)
            }
        }
    }
}
```
Hinweis zur Breite: `.frame(width: 480)` nach dem Innenabstand = 440 Inhalt + 2 × 20 (content-box).

- [ ] **Step 5: Kameras › Erweitert**

`UniFiCameraPopup/Views/Settings/CameraAdvancedSection.swift` (Prüfgrundlage S3; Karte „Popup“ und „Kamera entfernen …“ = Abweichung 11):
```swift
import AppCore
import AppKit
import ProtectKit
import SwiftUI

/// Kameras › Erweitert (docs/design/einstellungen-kameras.md, S3) plus the camera's popup options.
struct CameraAdvancedSection: View {
    @Binding var mapping: WebhookMapping
    let lastTriggered: Date?
    let onRemove: () -> Void

    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var protect = ProtectSession.shared
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            webhookCard
            streamCard
            popupSection
            HStack {
                Button("Webhook jetzt testen") { PopupController.shared.showTestPopup(for: mapping) }
                    .buttonStyle(LinkButtonStyle())
                    .disabled(!mapping.hasStreamSource)
                Spacer()
                Text("Zuletzt ausgelöst: \(lastTriggered.map { DisplayText.dayAndTime($0, now: Date()) } ?? "noch nie")")
                    .font(.system(size: 11))
                    .foregroundStyle(Tokens.muted.color)
            }
            Button("Kamera entfernen …", action: onRemove)
                .buttonStyle(LinkButtonStyle(color: Tokens.muted))
        }
    }

    private var webhookCard: some View {
        Card(radius: 9) {
            CardToggleRow(
                title: "Zusätzlich per Webhook auslösen",
                subtitle: "Für Alarm Manager, Home Assistant oder andere Systeme.",
                isOn: $mapping.webhookTriggerEnabled,
                vertical: 10,
                horizontal: 12
            )
            if mapping.webhookTriggerEnabled {
                CardDivider()
                FixedLabelRow(title: "Webhook-ID") {
                    TokenTextField(placeholder: "z. B. haustuer-klingel", text: $mapping.webhookId)
                }
                CardDivider()
                FixedLabelRow(title: "Aufruf-Adresse") {
                    Text(callAddress)
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.muted.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(copied ? "Kopiert" : "Kopieren", action: copyAddress)
                        .buttonStyle(FieldButtonStyle())
                }
            }
        }
    }

    private var callAddress: String {
        AppConfig.webhookURL(
            installationId: settings.installationId,
            slug: mapping.webhookId.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private var streamCard: some View {
        Card(radius: 9) {
            FixedLabelRow(title: "Stream-Adresse") {
                TokenTextField(placeholder: "automatisch aus Protect", text: $mapping.rtspsURL)
                    .onChange(of: mapping.rtspsURL) { newValue in
                        let normalized = StreamURL.normalizedRTSP(newValue)
                        if normalized != newValue { mapping.rtspsURL = normalized }
                    }
            }
            CardDivider()
            Text("Nur ausfüllen, wenn der Stream nicht über die Protect-API kommen soll (rtsp://…:7447/…).")
                .font(.system(size: 11))
                .lineSpacing(3)
                .foregroundStyle(Tokens.muted.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            if let warning = streamURLWarning {
                CardDivider()
                Text(warning)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
            }
        }
    }

    private var popupSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Popup")
            Card(radius: 9) {
                FixedLabelRow(title: "Name") {
                    TokenTextField(placeholder: "z. B. Haustür", text: $mapping.label)
                }
                CardDivider()
                FixedLabelRow(title: "Protect-Kamera") {
                    PopUpField(selection: $mapping.protectCameraId, options: cameraOptions)
                    Spacer(minLength: 0)
                }
                .onChange(of: mapping.protectCameraId) { newId in applyDefaultTriggers(for: newId) }
                CardDivider()
                FixedLabelRow(title: "Position") {
                    PopUpField(selection: $mapping.positionOverride, options: positionOptions)
                    Spacer(minLength: 0)
                }
                CardDivider()
                FixedLabelRow(title: "Größe") {
                    TokenTextField(placeholder: "480", text: dimensionBinding($mapping.width)).frame(width: 64)
                    Text("×").foregroundStyle(Tokens.muted.color)
                    TokenTextField(placeholder: "270", text: dimensionBinding($mapping.height)).frame(width: 64)
                    Text("px").font(.system(size: 12)).foregroundStyle(Tokens.muted.color)
                    Spacer(minLength: 0)
                }
                CardDivider()
                CardToggleRow(title: "Ton des Livebilds", isOn: $mapping.soundEnabled, vertical: 9, horizontal: 12)
                CardDivider()
                HStack(spacing: 8) {
                    if mapping.crop != nil {
                        Button("Ausschnitt löschen") { settings.removeCrop(for: mapping.entryId) }
                    } else {
                        Button("Ausschnitt setzen …") { PopupController.shared.showCropSelection(for: mapping) }
                            .disabled(!mapping.hasStreamSource)
                    }
                    Button("Test-Popup") { PopupController.shared.showTestPopup(for: mapping) }
                        .disabled(!mapping.hasStreamSource)
                    Spacer(minLength: 0)
                }
                .buttonStyle(FieldButtonStyle())
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
            }
        }
    }

    private var cameraOptions: [(value: String?, title: String)] {
        var options: [(value: String?, title: String)] = [(value: nil, title: "Keine (nur Webhook)")]
        options += protect.cameras.map { (value: Optional($0.id), title: $0.name) }
        if let id = mapping.protectCameraId, !protect.cameras.contains(where: { $0.id == id }) {
            options.append((value: id, title: "Unbekannte Kamera"))
        }
        return options
    }

    private var positionOptions: [(value: PopupPosition?, title: String)] {
        [(value: nil, title: "Standard")] + PopupPosition.allCases.map { (value: Optional($0), title: $0.label) }
    }

    /// A newly linked camera without triggers starts with Klingel + Person where supported.
    private func applyDefaultTriggers(for cameraId: String?) {
        guard mapping.triggers.isEmpty,
              let cameraId,
              let camera = protect.cameras.first(where: { $0.id == cameraId }) else { return }
        mapping.triggers = Set<TriggerKind>([.ring, .person]).intersection(camera.supportedTriggers)
    }

    private var streamURLWarning: String? {
        let trimmed = mapping.rtspsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().contains("rtsps://") { return "RTSPS wird nicht unterstützt. Bitte rtsp:// verwenden." }
        if trimmed.contains(":7441") { return "Port 7441 wird nicht unterstützt. Bitte Port 7447 verwenden." }
        if trimmed.lowercased().contains("enablesrtp") { return "?enableSrtp wird nicht unterstützt. Bitte entfernen." }
        return nil
    }

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

    private func copyAddress() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(callAddress, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }
}
```

- [ ] **Step 6: Reiter Kameras**

`UniFiCameraPopup/Views/Settings/CamerasTab.swift` (Prüfgrundlage S2):
```swift
import AppCore
import AppKit
import ProtectKit
import SwiftUI

/// Einstellungen › Kameras (docs/design/einstellungen-kameras.md).
struct CamerasTab: View {
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject private var protect = ProtectSession.shared
    @StateObject private var addAnchor = ViewAnchor()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Tokens.border.color).frame(width: 1)
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await protect.refreshCameras() }
        .onAppear(perform: ensureSelection)
        .onChange(of: settings.mappings.map(\.entryId)) { _ in ensureSelection() }
    }

    // MARK: Sidebar (190 + 2 × 8 content-box, + 1 border = 207)

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(settings.mappings) { mapping in
                        sidebarItem(mapping)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
            }
            Button("Kamera hinzufügen …", action: addCamera)
                .buttonStyle(LinkButtonStyle())
                .background(AnchorView(anchor: addAnchor))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 206)
        .background(Tokens.side.color)
    }

    private func sidebarItem(_ mapping: WebhookMapping) -> some View {
        let selected = mapping.entryId == navigation.selectedEntry
        return Button { navigation.selectedEntry = mapping.entryId } label: {
            HStack(spacing: 8) {
                CameraThumbnail(cameraId: mapping.protectCameraId)
                    .frame(width: 34, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 0) {
                    Text(Self.displayName(mapping))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(stateText(mapping))
                        .font(.system(size: 10))
                        .opacity(0.85)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .foregroundStyle(selected ? Color.white : Tokens.fg.color)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Tokens.accent.color : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    static func displayName(_ mapping: WebhookMapping) -> String {
        let label = mapping.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty { return label }
        let slug = mapping.webhookId.trimmingCharacters(in: .whitespacesAndNewlines)
        return slug.isEmpty ? "Kamera" : slug
    }

    private func stateText(_ mapping: WebhookMapping) -> String {
        let labels = mapping.protectCameraId == nil
            ? []
            : TriggerKind.displayOrder.filter { mapping.triggers.contains($0) }.map(\.label)
        return DisplayText.cameraState(
            triggerLabels: labels,
            webhook: mapping.webhookTriggerEnabled,
            mutedUntil: settings.muteSchedule.cameraMuteEnd(entry: mapping.entryId.uuidString, at: Date())
        )
    }

    private func addCamera() {
        guard let view = addAnchor.view else { return }
        let fromProtect = "Aus Protect wählen …"
        let webhookOnly = "Nur per Webhook"
        let titles = settings.isProtectConfigured ? [fromProtect, webhookOnly] : [webhookOnly]
        MenuPresenter.popUp(titles: titles, selectedIndex: nil, in: view) { index in
            if titles[index] == fromProtect {
                OnboardingWindow.show(startAt: .cameras)
            } else {
                settings.addMapping()
                navigation.selectedEntry = settings.mappings.last?.entryId
            }
        }
    }

    private func ensureSelection() {
        let ids = settings.mappings.map(\.entryId)
        if let selected = navigation.selectedEntry, ids.contains(selected) { return }
        navigation.selectedEntry = ids.first
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let id = navigation.selectedEntry, let binding = binding(for: id) {
            CameraDetail(mapping: binding, onRemoved: ensureSelection)
                .id(id)
        } else {
            VStack(spacing: 10) {
                Text("Noch keine Kamera eingerichtet.").foregroundStyle(Tokens.muted.color)
                Button(settings.isProtectConfigured ? "Kameras aus Protect wählen …" : "Einrichtung starten …") {
                    OnboardingWindow.show(startAt: settings.isProtectConfigured ? .cameras : .welcome)
                }
                .buttonStyle(FieldButtonStyle())
            }
        }
    }

    /// Looks the entry up by id on every access, so removing it never indexes out of range.
    private func binding(for id: UUID) -> Binding<WebhookMapping>? {
        guard let current = settings.mappings.first(where: { $0.entryId == id }) else { return nil }
        return Binding(
            get: { settings.mappings.first { $0.entryId == id } ?? current },
            set: { updated in
                if let index = settings.mappings.firstIndex(where: { $0.entryId == id }) {
                    settings.mappings[index] = updated
                }
            }
        )
    }
}

struct ActionEditorContext: Identifiable {
    let id = UUID()
    let action: CameraAction
    let isNew: Bool
}

struct CameraDetail: View {
    @Binding var mapping: WebhookMapping
    let onRemoved: () -> Void

    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var protect = ProtectSession.shared
    @ObservedObject private var events = EventLog.shared
    @State private var advancedExpanded = false
    @State private var editor: ActionEditorContext?
    @State private var confirmRemoval = false

    private var camera: ProtectCamera? {
        guard let id = mapping.protectCameraId else { return nil }
        return protect.cameras.first { $0.id == id }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        header
                        triggersSection
                        optionsCard
                        buttonsSection
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
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 22)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .topLeading)
                }
                .onChange(of: advancedExpanded) { expanded in
                    guard expanded else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("advanced", anchor: .top) }
                    }
                }
            }
        }
        .sheet(item: $editor) { context in
            ActionEditorSheet(
                action: context.action,
                isNew: context.isNew,
                onSave: save,
                onDelete: context.isNew ? nil : { delete(context.action.id) }
            )
        }
        .alert("Kamera entfernen?", isPresented: $confirmRemoval) {
            Button("Abbrechen", role: .cancel) {}
            Button("Entfernen", role: .destructive) {
                settings.removeMapping(id: mapping.entryId)
                onRemoved()
            }
        } message: {
            Text("Möchtest du die Kamera „\(CamerasTab.displayName(mapping))“ wirklich entfernen?")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(CamerasTab.displayName(mapping))
                .font(.system(size: 16, weight: .bold))
                .lineLimit(1)
            Spacer()
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Tokens.muted.color)
                .lineLimit(1)
        }
    }

    private var subtitle: String {
        guard mapping.protectCameraId != nil else { return "nur Webhook" }
        guard let camera else { return "" }
        return [camera.modelName, camera.hasSpeaker ? "Lautsprecher" : nil]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var triggersSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: "Auslöser")
            if let camera {
                TriggerChips(camera: camera, selection: $mapping.triggers, size: .small)
            } else if mapping.protectCameraId != nil {
                Text(protect.lastError ?? "Kamera wird geladen …")
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.muted.color)
            } else {
                Text("Diese Kamera meldet sich nur per Webhook (siehe „Erweitert“).")
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.muted.color)
            }
        }
    }

    private var optionsCard: some View {
        Card(radius: 9) {
            HotkeyRecorderView(hotkey: $mapping.hotkey, conflictMessage: hotkeyConflictMessage)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            CardDivider()
            CardToggleRow(title: "Hinweiston beim Öffnen", isOn: $mapping.chimeOnOpen, vertical: 8, horizontal: 12)
            CardDivider()
            CardToggleRow(title: "Zoom und Ausschnitt merken", isOn: $mapping.rememberZoom, vertical: 8, horizontal: 12)
        }
    }

    private var buttonsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Buttons im Popup (max. \(WebhookMapping.maxActions))")
            Card(radius: 9) {
                ForEach(mapping.actions) { action in
                    ActionRowLayout {
                        Text(action.trimmedTitle.isEmpty ? "Ohne Titel" : action.trimmedTitle)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text(action.method.rawValue)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.vertical, 2)
                            .padding(.horizontal, 5)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(Tokens.accText.color)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Tokens.accSoft.color))
                        Text(DisplayText.actionAddress(action.url))
                            .foregroundStyle(Tokens.muted.color)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Button("Ändern") { editor = ActionEditorContext(action: action, isNew: false) }
                            .buttonStyle(LinkButtonStyle())
                    }
                    .font(.system(size: 12))
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    CardDivider()
                }
                if mapping.actions.count < WebhookMapping.maxActions {
                    Button("Button hinzufügen …") { editor = ActionEditorContext(action: CameraAction(), isNew: true) }
                        .buttonStyle(LinkButtonStyle())
                        .padding(.vertical, 7)
                        .padding(.horizontal, 12)
                } else {
                    Text("Höchstens drei Buttons.")
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.muted.color)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 12)
                }
            }
        }
    }

    private func save(_ action: CameraAction) {
        if let index = mapping.actions.firstIndex(where: { $0.id == action.id }) {
            mapping.actions[index] = action
        } else if mapping.actions.count < WebhookMapping.maxActions {
            mapping.actions.append(action)
        }
    }

    private func delete(_ id: UUID) {
        mapping.actions.removeAll { $0.id == id }
    }

    // From the former SettingsView.
    private var hotkeyConflictMessage: String? {
        guard let hotkey = mapping.hotkey else { return nil }

        let duplicates = settings.mappings.filter { $0.hotkey == hotkey }
        if duplicates.count > 1 {
            return conflictNamesMessage(prefix: "Dieses Tastenkürzel ist", mappings: duplicates)
        }
        if hotkey.isSequence, let prefix = hotkey.steps.first {
            let conflicts = settings.mappings.filter {
                guard mapping.entryId != $0.entryId, let other = $0.hotkey else { return false }
                return !other.isSequence && other.steps.first == prefix
            }
            if !conflicts.isEmpty {
                return conflictNamesMessage(prefix: "Die erste Taste kollidiert mit dem Einzel-Shortcut von", mappings: conflicts)
            }
        }
        if !hotkey.isSequence, let prefix = hotkey.steps.first {
            let conflicts = settings.mappings.filter {
                guard mapping.entryId != $0.entryId, let other = $0.hotkey else { return false }
                return other.isSequence && other.steps.first == prefix
            }
            if !conflicts.isEmpty {
                return conflictNamesMessage(prefix: "Dieser Shortcut blockiert die Sequenz von", mappings: conflicts)
            }
        }
        return nil
    }

    private func conflictNamesMessage(prefix: String, mappings: [WebhookMapping]) -> String {
        let names = mappings
            .map { $0.label.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return names.isEmpty ? "\(prefix) mehreren Kameras." : "\(prefix) \(names.joined(separator: ", "))."
    }
}

/// CSS grid `minmax(0,1fr) 46px minmax(0,1.6fr) 44px`, gap 8 (popup button rows).
struct ActionRowLayout: Layout {
    private static let gap: CGFloat = 8

    static func columnWidths(total: CGFloat) -> [CGFloat] {
        let flexible = max(total - 46 - 44 - gap * 3, 0)
        return [flexible / 2.6, 46, flexible * 1.6 / 2.6, 44]
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 480
        let widths = Self.columnWidths(total: width)
        let height = zip(subviews, widths)
            .map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
            .max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, Self.columnWidths(total: bounds.width)) {
            subview.place(
                at: CGPoint(x: x, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: width, height: nil)
            )
            x += width + Self.gap
        }
    }
}

/// Snapshot of a Protect camera, striped placeholder while loading or without picture.
struct CameraThumbnail: View {
    let cameraId: String?
    var band: CGFloat = 6
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            StripePlaceholder(band: band)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .task(id: cameraId) {
            image = nil
            guard let cameraId else { return }
            image = await ProtectSession.shared.snapshot(cameraId: cameraId)
        }
    }
}
```

- [ ] **Step 7: Reiter einhängen, alte Ansicht entfernen**

1. In `SettingsWindow.swift`, `SettingsRootView.content`: `case .cameras: SettingsView()` ersetzen durch `case .cameras: CamerasTab(navigation: navigation)`.
2. `git rm UniFiCameraPopup/Views/SettingsView.swift`
3. In `project.pbxproj` die vier Zeilen mit `A10000000000000000000012` bzw. `A20000000000000000000012` (BuildFile, FileReference, Kind der Views-Gruppe, Sources-Phase) löschen. Prüfen: `grep -c "SettingsView.swift" UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj` → `0`.
4. Neu eintragen – PBXBuildFile:
```
		A10000000000000000000075 /* CamerasTab.swift in Sources */ = {isa = PBXBuildFile; fileRef = A20000000000000000000075 /* CamerasTab.swift */; };
		A10000000000000000000076 /* CameraAdvancedSection.swift in Sources */ = {isa = PBXBuildFile; fileRef = A20000000000000000000076 /* CameraAdvancedSection.swift */; };
		A10000000000000000000077 /* ActionEditorSheet.swift in Sources */ = {isa = PBXBuildFile; fileRef = A20000000000000000000077 /* ActionEditorSheet.swift */; };
```
PBXFileReference:
```
		A20000000000000000000075 /* CamerasTab.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CamerasTab.swift; sourceTree = "<group>"; };
		A20000000000000000000076 /* CameraAdvancedSection.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CameraAdvancedSection.swift; sourceTree = "<group>"; };
		A20000000000000000000077 /* ActionEditorSheet.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ActionEditorSheet.swift; sourceTree = "<group>"; };
```
Kinder der Gruppe `A40000000000000000000071 /* Settings */` ergänzen (`A2…75`, `A2…76`, `A2…77`), Sources-Phase ergänzen (`A1…75`, `A1…76`, `A1…77`).

- [ ] **Step 8: Lint und Build**

`plutil -lint …` → OK; Build → `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Sichtprüfung gegen `docs/design/einstellungen-kameras.md`**

1. Seitenleiste: Einträge mit Schnappschuss (bzw. Streifen), Name 12/600, Zustand 10; Auswahl indigo, Text weiß; Breite inkl. Rand 207.
2. Detail: Kopf, Chips in der Regel-Reihenfolge (Doorbell: Klingel, Person, Paket, Tier, Sprache, Glasbruch, Bewegung, dann Fahrzeug gestrichelt/durchgestrichen); Chips toggeln, Reihenfolge bleibt.
3. Tastenkürzel-Chip aufnehmen/löschen (⌫), Konfliktmeldung erscheint unter der Zeile.
4. Buttons: „Ändern“ öffnet das Sheet mit Werten; „Button hinzufügen …“ öffnet „Neuer Button“; „Sichern“ übernimmt; „Testen“ gegen eine erreichbare Adresse → „Test erfolgreich · HTTP 200“; drei Buttons → Hinweis statt Link.
5. „Erweitert“ klappt auf und scrollt nach oben; Webhook-Schalter blendet ID/Adresse ein und aus; „Kopieren“ legt die Adresse in die Zwischenablage; Stream-Adresse mit `rtsps://` wird normalisiert bzw. warnt.
6. Popup-Karte: Name, Protect-Kamera, Position, Größe, Ton des Livebilds, Ausschnitt, Test-Popup wirken wie früher.
7. „Kamera entfernen …“ → Rückfrage → Eintrag weg, Auswahl springt auf den ersten.
8. „Kamera hinzufügen …“ → Menü; „Aus Protect wählen …“ öffnet die Einrichtung bei den Kameras.
9. Alles in Hell und Dunkel.

- [ ] **Step 10: Commit**

```bash
git add UniFiCameraPopup/Views/Settings UniFiCameraPopup/Views/HotkeyRecorderView.swift UniFiCameraPopup/Views/Onboarding/OnboardingView.swift UniFiCameraPopup/Services/CameraActionService.swift UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj
git add -u UniFiCameraPopup/Views/SettingsView.swift
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "feat(settings): Kameras tab with sidebar, trigger chips, button sheet and advanced section" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Popup nach Vorlage B – Chip, Stummschalten pro Kamera, Button-Leiste

**Files:**
- Create: `UniFiCameraPopup/Views/Popup/PopupOverlayViews.swift`
- Modify: `UniFiCameraPopup/Views/PopupWindow.swift` (MuteBar raus, Overlays rein)
- Modify: `UniFiCameraPopup/Services/PopupController.swift` (`makeAlarmWindow`)
- Modify: `project.pbxproj` (Gruppe Popup, eine Datei)

**Interfaces:**
- Consumes: `TemplateIcon.nsImage(size:)`, `Tokens`, `ThemeColor` (Task 3); `MuteDuration.longLabel`, `DisplayText.popupChip` (Task 1); `SettingsStore.muteOptions`, `mute(entryId:for:)`, `ActionIcon`, `CameraAction.confirmBeforeRun` (Task 4); `CamerasTab.displayName` (Task 6); `CameraActionService.trigger` (Task 6).
- Produces:
  - `struct PopupOverlayContent { chipText: String; cameraName: String; muteOptions: [MuteDuration]; onMute: (MuteDuration) -> Void }`
  - `OverlayChipView(text:)`, `CircleIconButton(icon:iconSize:diameter:fill:tint:label:)` mit `showRunning()`, `showResult(error:)`, `PopupMuteMenuView(cameraName:options:)` mit `onPick`, `MuteMenuRow`, `PaddedLabel`, `ActionPillView(actions:)` mit `onAction`
  - `extension NSView { func cgColor(_ token: ThemeColor) -> CGColor }`
  - `PopupWindow(…, actions:, overlay: PopupOverlayContent? = nil, onWillClose: …)`; `FirstMouseButton` ist jetzt `internal class` (nicht `final`)

- [ ] **Step 1: Overlay-Ansichten**

`UniFiCameraPopup/Views/Popup/PopupOverlayViews.swift` (Prüfgrundlage `docs/design/popup.md`):
```swift
import AppCore
import AppKit

/// What the popup chrome shows (template B). nil in crop selection mode.
struct PopupOverlayContent {
    let chipText: String
    let cameraName: String
    let muteOptions: [MuteDuration]
    let onMute: (MuteDuration) -> Void
}

extension NSView {
    /// Resolves a token for this view's appearance; layers keep plain CGColors.
    func cgColor(_ token: ThemeColor) -> CGColor {
        var result = token.light.nsColor.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            result = token.nsColor.cgColor
        }
        return result
    }
}

/// "Klingel · Haustür · 10:41": capsule `overlay`, padding 4/9, 11 pt semibold, white. Click-through.
final class OverlayChipView: NSView {
    private let label = NSTextField(labelWithString: "")

    init(text: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = Tokens.overlay.light.nsColor.cgColor

        label.stringValue = text
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
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(text)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    /// Clicks fall through to the video (click closes, drag pans).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Round icon button: close 24/11, mute 24/13, pill buttons 34/16.
final class CircleIconButton: FirstMouseButton {
    private let fill: ThemeColor
    private let tint: ThemeColor
    private let label: String

    init(icon: TemplateIcon, iconSize: CGFloat, diameter: CGFloat, fill: ThemeColor, tint: ThemeColor, label: String) {
        self.fill = fill
        self.tint = tint
        self.label = label
        super.init(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        bezelStyle = .regularSquare
        isBordered = false
        title = ""
        image = icon.nsImage(size: iconSize)
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        wantsLayer = true
        layer?.cornerRadius = diameter / 2
        toolTip = label
        setAccessibilityLabel(label)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: diameter),
            heightAnchor.constraint(equalToConstant: diameter),
        ])
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    /// While the webhook runs: half transparent, no second click.
    func showRunning() {
        isEnabled = false
        alphaValue = 0.5
    }

    /// 1.5 s green (ok) or orange (error, message in the tooltip), then back to normal.
    func showResult(error: String?) {
        alphaValue = 1
        contentTintColor = error == nil ? .systemGreen : .systemOrange
        if let error { toolTip = "\(label): \(error)" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            self.contentTintColor = self.tint.nsColor
            self.toolTip = self.label
            self.isEnabled = true
        }
    }

    private func applyColors() {
        layer?.backgroundColor = cgColor(fill)
        contentTintColor = tint.nsColor
    }
}

/// Text with template padding (menu header 4/8, menu item 5/8).
final class PaddedLabel: NSView {
    let label = NSTextField(labelWithString: "")

    init(text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: ThemeColor, vertical: CGFloat = 4, horizontal: CGFloat = 8) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        label.stringValue = text
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color.nsColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontal),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -horizontal),
            label.topAnchor.constraint(equalTo: topAnchor, constant: vertical),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -vertical),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// One mute option; `accent` with white text while the mouse is over it.
final class MuteMenuRow: NSView {
    var onClick: (() -> Void)?
    private let content: PaddedLabel
    private var hovering = false {
        didSet { applyColors() }
    }

    init(title: String) {
        content = PaddedLabel(text: title, size: 12, color: Tokens.fg, vertical: 5, horizontal: 8)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 5
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(title)
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
        content.label.textColor = hovering ? .white : Tokens.fg.nsColor
    }
}

/// Mute dropdown: 190 + 2 × 5 wide, radius 9, `menu`, ring `mainBorder`, shadow 0 10 24 rgba(0,0,0,.4).
final class PopupMuteMenuView: NSView {
    var onPick: ((MuteDuration) -> Void)?

    init(cameraName: String, options: [MuteDuration]) {
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

        let stack = NSStackView()
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

        let header = PaddedLabel(text: "\(cameraName) stummschalten", size: 11, weight: .semibold, color: Tokens.muted)
        stack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalToConstant: 190).isActive = true
        for option in options {
            let row = MuteMenuRow(title: "für \(option.longLabel)")
            row.onClick = { [weak self] in self?.onPick?(option) }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalToConstant: 190).isActive = true
        }

        setAccessibilityElement(true)
        setAccessibilityRole(.menu)
        setAccessibilityLabel("\(cameraName) stummschalten")
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        layer?.backgroundColor = cgColor(Tokens.menu)
        layer?.borderColor = cgColor(Tokens.mainBorder)
    }
}

/// Bottom pill: padding 6, gap 8, `pill`, ring `pillRing`, shadow 0 6 18 rgba(0,0,0,.3).
final class ActionPillView: NSView {
    var onAction: ((CameraAction, CircleIconButton) -> Void)?
    private var buttons: [(button: CircleIconButton, action: CameraAction)] = []

    init(actions: [CameraAction]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.borderWidth = 1
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.3
        layer?.shadowRadius = 9
        layer?.shadowOffset = CGSize(width: 0, height: -6)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        for action in actions.prefix(WebhookMapping.maxActions) {
            let button = CircleIconButton(
                icon: action.icon.templateIcon,
                iconSize: 16,
                diameter: 34,
                fill: Tokens.pillBtn,
                tint: Tokens.pillFg,
                label: action.trimmedTitle
            )
            button.target = self
            button.action = #selector(tapped(_:))
            stack.addArrangedSubview(button)
            buttons.append((button, action))
        }
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    @objc private func tapped(_ sender: NSButton) {
        guard let entry = buttons.first(where: { $0.button === sender }) else { return }
        onAction?(entry.action, entry.button)
    }

    private func applyColors() {
        layer?.backgroundColor = cgColor(Tokens.pill)
        layer?.borderColor = cgColor(Tokens.pillRing)
    }
}
```

- [ ] **Step 2: PopupWindow umbauen**

In `UniFiCameraPopup/Views/PopupWindow.swift`:
1. Oben `import AppCore` ergänzen.
2. `private let muteBar = MuteBarView()` ersetzen durch `private var muteMenu: PopupMuteMenuView?`.
3. Nach `private let actions: [CameraAction]` einfügen: `private let overlay: PopupOverlayContent?`.
4. Im `init` nach `actions: [CameraAction] = [],` den Parameter `overlay: PopupOverlayContent? = nil,` einfügen und nach `self.actions = cropSelectionMode ? [] : actions` die Zeile `self.overlay = cropSelectionMode ? nil : overlay`.
5. In `setupContent` den `clickCatcher.onClick`-Block ersetzen durch:
```swift
            clickCatcher.onClick = { [weak self] in
                guard let self else { return }
                // An open mute menu takes the first click away from the video.
                if self.muteMenu?.isHidden == false {
                    self.muteMenu?.isHidden = true
                    return
                }
                if !self.playerView.isZoomedIn {
                    self.closePopup()
                }
            }
```
und in `onMouseEnter`/`onMouseExit` die Zeilen `self?.muteBar.setHovering(true)` bzw. `(false)` löschen.
6. Den Block von `muteBar.translatesAutoresizingMaskIntoConstraints = false` bis einschließlich dem schließenden `}` von `muteBar.onAction = { … }` (Zeilen 167–185) löschen.
7. `content.addSubview(muteBar)` und die zwei Constraints `muteBar.trailingAnchor…` / `muteBar.topAnchor…` löschen.
8. Am Ende von `setupContent`, nach dem `thumbnailDataURI`-Block: `setupOverlay(in: content)`.
9. Nach `setupContent` einfügen:
```swift
    /// Template B chrome (docs/design/popup.md): event chip, mute + close, mute menu, button pill.
    private func setupOverlay(in content: NSView) {
        content.layer?.borderWidth = 1
        content.layer?.borderColor = Tokens.popupRing.light.nsColor.cgColor
        guard let overlay else { return }

        let chip = OverlayChipView(text: overlay.chipText)
        let close = CircleIconButton(icon: .close, iconSize: 11, diameter: 24,
                                     fill: Tokens.overlay, tint: Tokens.white, label: "Schließen")
        close.target = self
        close.action = #selector(closeTapped)
        let mute = CircleIconButton(icon: .bellSlash, iconSize: 13, diameter: 24,
                                    fill: Tokens.overlay, tint: Tokens.white, label: "\(overlay.cameraName) stummschalten")
        mute.target = self
        mute.action = #selector(muteTapped)
        let menu = PopupMuteMenuView(cameraName: overlay.cameraName, options: overlay.muteOptions)
        menu.isHidden = true
        menu.onPick = { [weak self] duration in
            overlay.onMute(duration)
            self?.closePopup()
        }

        content.addSubview(chip)
        content.addSubview(close)
        content.addSubview(mute)
        var constraints = [
            chip.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            chip.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            chip.trailingAnchor.constraint(lessThanOrEqualTo: mute.leadingAnchor, constant: -8),
            close.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            close.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            mute.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -40),
            mute.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
        ]
        if !actions.isEmpty {
            let pill = ActionPillView(actions: actions)
            pill.onAction = { [weak self] action, button in
                self?.run(action, from: button)
            }
            content.addSubview(pill)
            constraints += [
                pill.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                pill.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            ]
        }
        // Last, so the open menu lies above the pill and the chip.
        content.addSubview(menu)
        constraints += [
            menu.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            menu.topAnchor.constraint(equalTo: content.topAnchor, constant: 40),
        ]
        NSLayoutConstraint.activate(constraints)
        muteMenu = menu
    }

    @objc private func closeTapped() {
        closePopup()
    }

    @objc private func muteTapped() {
        muteMenu?.isHidden.toggle()
    }

    /// Calls the button's webhook; the popup stays open. Optional confirmation first.
    private func run(_ action: CameraAction, from button: CircleIconButton) {
        if action.confirmBeforeRun {
            let alert = NSAlert()
            alert.messageText = "„\(action.trimmedTitle)“ ausführen?"
            alert.addButton(withTitle: "Ausführen")
            alert.addButton(withTitle: "Abbrechen")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        button.showRunning()
        Task {
            do {
                try await CameraActionService.trigger(action)
                button.showResult(error: nil)
            } catch {
                NSLog("Camera action \"\(action.trimmedTitle)\" failed: \(error.localizedDescription)")
                button.showResult(error: error.localizedDescription)
            }
        }
    }
```
10. Die ganze Klasse `MuteBarView` (Kommentar `/// Icon buttons (top-right of the popup)…` bis zu ihrer schließenden Klammer) löschen.
11. `private final class FirstMouseButton: NSButton {` ersetzen durch `class FirstMouseButton: NSButton {`.

- [ ] **Step 3: PopupController reicht den Overlay-Inhalt durch**

In `PopupController.swift` `makeAlarmWindow(event:mapping:streamURL:)` ersetzen durch:
```swift
    private func makeAlarmWindow(
        event: TriggerEvent,
        mapping: WebhookMapping,
        streamURL: String
    ) -> PopupWindow {
        let entryId = mapping.entryId
        let cameraName = CamerasTab.displayName(mapping)
        let overlay = PopupOverlayContent(
            chipText: DisplayText.popupChip(
                kind: Self.kindLabel(for: event, mapping: mapping),
                camera: cameraName,
                date: event.timestamp
            ),
            cameraName: cameraName,
            muteOptions: settings.muteOptions,
            onMute: { [weak self] duration in
                self?.settings.mute(entryId: entryId, for: duration)
            }
        )
        return PopupWindow(
            frame: NSRect(x: 0, y: 0, width: CGFloat(mapping.width), height: CGFloat(mapping.height)),
            streamURL: streamURL,
            soundEnabled: mapping.soundEnabled,
            rememberZoom: mapping.rememberZoom,
            initialZoom: mapping.rememberZoom ? mapping.savedZoom : nil,
            cropRegion: mapping.crop,
            thumbnailDataURI: event.thumbnail,
            autoCloseSeconds: settings.autoCloseTimeout,
            actions: mapping.actions.filter(\.isConfigured),
            overlay: overlay,
            onWillClose: { [weak self] scale, panOffset in
                self?.settings.saveZoom(for: entryId, scale: scale, panOffset: panOffset)
            }
        ) { [weak self] in
            self?.removePopup(entryId: entryId)
        }
    }
```

- [ ] **Step 4: pbxproj**

PBXBuildFile `A10000000000000000000080 /* PopupOverlayViews.swift in Sources */ = {isa = PBXBuildFile; fileRef = A20000000000000000000080 /* PopupOverlayViews.swift */; };`
PBXFileReference `A20000000000000000000080 /* PopupOverlayViews.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PopupOverlayViews.swift; sourceTree = "<group>"; };`
Gruppe:
```
		A40000000000000000000072 /* Popup */ = {
			isa = PBXGroup;
			children = (
				A20000000000000000000080 /* PopupOverlayViews.swift */,
			);
			path = Popup;
			sourceTree = "<group>";
		};
```
In `Views`-Gruppe `A40000000000000000000072 /* Popup */,` ergänzen; Sources-Phase `A10000000000000000000080 /* PopupOverlayViews.swift in Sources */,`.

- [ ] **Step 5: Lint und Build**

`plutil -lint …` → OK; Build → `** BUILD SUCCEEDED **`. Zusätzlich `grep -n "MuteBarView\|muteBar" UniFiCameraPopup/Views/PopupWindow.swift` → keine Treffer.

- [ ] **Step 6: Sichtprüfung gegen `docs/design/popup.md`**

Kamera mit zwei Buttons (einer mit „Vor dem Ausführen nachfragen“). Test-Popup (Kameras › Erweitert › Test-Popup):
1. Chip oben links „Haustür · HH:mm“ (ohne Ereignis-Art), Schließen und Glocke oben rechts in den Maßen der Spezifikation; Ring 1 pt sichtbar am Rand.
2. Glocke → Menü „Haustür stummschalten“, „für 15 Minuten“, „für 1 Stunde“ (eigene Dauern aus Allgemein); Eintrag unter der Maus indigo. Klick neben das Menü schließt nur das Menü.
3. „für 15 Minuten“ → Popup schließt; Kameras-Seitenleiste zeigt „stumm bis …“; ein echtes Ereignis dieser Kamera öffnet kein Popup, eine andere Kamera schon; Test-Popup erscheint trotzdem (manuell).
4. Button-Leiste unten mittig, Symbole wie im Sheet gewählt; Button mit Nachfrage zeigt den Dialog; Ergebnis färbt das Symbol 1,5 s grün bzw. orange.
5. Ohne Buttons keine Leiste. Hell/Dunkel: Leiste und Menü wechseln, Chip und Rund-Buttons bleiben dunkel.
6. Ausschnitt setzen (Crop-Modus) zeigt keine Overlays, nur „Abbrechen“/„Speichern“.

- [ ] **Step 7: Commit**

```bash
git add UniFiCameraPopup/Views/Popup UniFiCameraPopup/Views/PopupWindow.swift UniFiCameraPopup/Services/PopupController.swift UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "feat(popup): template B chrome with per-camera mute menu and icon button pill" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Menüleisten-Panel nach Vorlage mit Stumm-Status und „Aufheben“

**Files:**
- Create: `UniFiCameraPopup/Views/StatusPanel/StatusPanel.swift`
- Modify: `UniFiCameraPopup/AppDelegate.swift` (Linksklick → Panel, Rechtsklick → bisheriges Menü)
- Modify: `project.pbxproj` (Gruppe StatusPanel, eine Datei)

**Interfaces:**
- Consumes: `SettingsStore.muteSchedule/muteOptions/muteAll/clearGlobalMute/clearMute(entryId:)/mapping(forEntry:)`, `EventLog.shared.history/thumbnails` (Task 4); `DisplayText.shortTime/until` (Task 1); Bausteine (Task 3); `CamerasTab.displayName` (Task 6); `ProtectEventService.status`, `WebSocketClient.status`, `ProtectSession.client`.
- Produces:
  - `struct StatusPanelActions { openSettings, openHelp, quit: () -> Void; openCamera: (UUID) -> Void; close: () -> Void; resize: (CGSize) -> Void }`
  - `final class StatusPanelClock: ObservableObject { @Published var now: Date }`
  - `StatusPanelView(settings:events:protectEvents:relay:protect:clock:actions:)`
  - `StatusPanelController(makeContent: (StatusPanelClock) -> AnyView)` mit `toggle(from:)`, `show(from:)`, `close()`, `resize(to:)`, `isShown`

- [ ] **Step 1: Panel schreiben**

`UniFiCameraPopup/Views/StatusPanel/StatusPanel.swift` (Prüfgrundlage `docs/design/menue.md`; Stumm-Bereich, Hilfe, Beenden = Abweichung 15):
```swift
import AppCore
import AppKit
import SwiftUI

/// Callbacks the panel needs from `AppDelegate`.
struct StatusPanelActions {
    let openSettings: () -> Void
    let openHelp: () -> Void
    let quit: () -> Void
    let openCamera: (UUID) -> Void
    let close: () -> Void
    let resize: (CGSize) -> Void
}

/// "Now" for the panel: refreshed on every show and every 15 s while shown.
@MainActor
final class StatusPanelClock: ObservableObject {
    @Published var now = Date()
}

private struct PanelSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

/// Menu bar panel (docs/design/menue.md): 310 + 2 × 14 wide, radius 14, padding 14, gap 10.
struct StatusPanelView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var events: EventLog
    @ObservedObject var protectEvents: ProtectEventService
    @ObservedObject var relay: WebSocketClient
    @ObservedObject var protect: ProtectSession
    @ObservedObject var clock: StatusPanelClock
    let actions: StatusPanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            let recent = events.history.latest(3)
            if !recent.isEmpty {
                eventList(recent)
            }
            if hasMutes {
                mutedSection
            }
            muteButtons
            CardDivider(color: Tokens.mainBorder)
            footerRow("Einstellungen …", shortcut: "⌘,", action: actions.openSettings)
                .keyboardShortcut(",", modifiers: .command)
            footerRow("Hilfe", shortcut: nil, action: actions.openHelp)
            footerRow("Beenden", shortcut: "⌘Q", action: actions.quit)
                .keyboardShortcut("q", modifiers: .command)
        }
        .padding(14)
        .frame(width: 338, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Tokens.win.color))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Tokens.mainBorder.color, lineWidth: 1))
        .foregroundStyle(Tokens.fg.color)
        .font(.system(size: 13))
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: PanelSizeKey.self, value: proxy.size)
        })
        .onPreferenceChange(PanelSizeKey.self) { size in actions.resize(size) }
    }

    // MARK: Kopf

    private var header: some View {
        let chip = statusChip
        return HStack {
            Text("Camera Popup").font(.system(size: 14, weight: .bold))
            Spacer()
            Text(chip.text)
                .font(.system(size: 11, weight: .semibold))
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .foregroundStyle(chip.foreground.color)
                .background(Capsule().fill(chip.background.color))
        }
    }

    private var statusChip: (text: String, foreground: ThemeColor, background: ThemeColor) {
        let status: ConnectionStatus
        if protect.client != nil {
            status = protectEvents.status
        } else if settings.mappings.contains(where: \.webhookTriggerEnabled) {
            status = relay.status
        } else {
            return ("Nicht eingerichtet", Tokens.muted, Tokens.btn2)
        }
        switch status {
        case .connected: return ("Zu Hause", Tokens.ok, Tokens.okBg)
        case .connecting: return ("Verbinde …", Tokens.accText, Tokens.accSoft)
        case .disconnected, .outdated: return ("Getrennt", Tokens.muted, Tokens.btn2)
        }
    }

    // MARK: Ereignisse

    private func eventList(_ records: [EventRecord]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(records) { record in
                Button {
                    if let id = UUID(uuidString: record.entryId) { actions.openCamera(id) }
                } label: {
                    HStack(spacing: 10) {
                        thumbnail(record)
                            .frame(width: 54, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(record.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Text(record.cameraName)
                                .font(.system(size: 11))
                                .foregroundStyle(Tokens.muted.color)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text(DisplayText.shortTime(record.date, now: clock.now))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Tokens.muted.color)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func thumbnail(_ record: EventRecord) -> some View {
        if let image = events.thumbnails[record.id] {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            StripePlaceholder(band: 8)
        }
    }

    // MARK: Stummschalten

    private var globalEnd: Date? {
        settings.muteSchedule.globalEnd(at: clock.now)
    }

    private var cameraMutes: [MuteSchedule.CameraMute] {
        settings.muteSchedule.activeCameraMutes(at: clock.now)
    }

    private var hasMutes: Bool {
        globalEnd != nil || !cameraMutes.isEmpty
    }

    private var mutedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Stummgeschaltet")
            if let end = globalEnd {
                muteRow("Alle Kameras", until: end) { settings.clearGlobalMute() }
            }
            ForEach(cameraMutes, id: \.entry) { mute in
                if let id = UUID(uuidString: mute.entry), let mapping = settings.mapping(forEntry: id) {
                    muteRow(CamerasTab.displayName(mapping), until: mute.until) { settings.clearMute(entryId: id) }
                }
            }
        }
    }

    private func muteRow(_ title: String, until: Date, clear: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            TemplateIcon.speakerMute.image(size: 13).foregroundStyle(Tokens.accText.color)
            Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Text(DisplayText.until(until, now: clock.now))
                .font(.system(size: 11))
                .foregroundStyle(Tokens.muted.color)
            Spacer(minLength: 0)
            Button("Aufheben", action: clear).buttonStyle(LinkButtonStyle())
        }
    }

    private var muteButtons: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Alle Kameras stummschalten")
            HStack(spacing: 6) {
                // Indexed: two equal durations must not collide as identifiers.
                ForEach(Array(settings.muteOptions.enumerated()), id: \.offset) { _, duration in
                    Button {
                        settings.muteAll(for: duration)
                        actions.close()
                    } label: {
                        HStack(spacing: 5) {
                            TemplateIcon.speakerMute.image(size: 13)
                            Text(duration.shortLabel)
                        }
                    }
                    .buttonStyle(SoftButtonStyle())
                }
            }
        }
    }

    // MARK: Fuß

    private func footerRow(_ title: String, shortcut: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut).foregroundStyle(Tokens.muted.color)
                }
            }
            .font(.system(size: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Borderless panel under the status item. Closes on outside clicks and when it loses key.
@MainActor
final class StatusPanelController: NSObject, NSWindowDelegate {
    private let makeContent: (StatusPanelClock) -> AnyView
    private let clock = StatusPanelClock()
    private var panel: NSPanel?
    private weak var anchor: NSStatusBarButton?
    private var outsideClickMonitor: Any?
    private var clockTimer: Timer?
    private var lastClose = Date.distantPast

    init(makeContent: @escaping (StatusPanelClock) -> AnyView) {
        self.makeContent = makeContent
    }

    var isShown: Bool {
        panel?.isVisible == true
    }

    func toggle(from button: NSStatusBarButton) {
        if isShown {
            close()
            return
        }
        // Clicking the status item while open first resigns key (closing it); do not reopen.
        guard Date().timeIntervalSince(lastClose) > 0.3 else { return }
        show(from: button)
    }

    func show(from button: NSStatusBarButton) {
        anchor = button
        clock.now = Date()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let content = panel.contentView {
            resize(to: content.fittingSize)
        }
        panel.makeKeyAndOrderFront(nil)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        clockTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.clock.now = Date() }
        }
    }

    func close() {
        guard isShown else { return }
        panel?.orderOut(nil)
        lastClose = Date()
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        clockTimer?.invalidate()
        clockTimer = nil
    }

    /// Top edge 8 pt under the menu bar, right edge flush with the status item, kept on screen.
    func resize(to size: CGSize) {
        guard let panel, size.width > 0, size.height > 0,
              let button = anchor, let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var x = buttonFrame.maxX - size.width
        if let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame {
            x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        }
        let y = buttonFrame.minY - 8 - size.height
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 338, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: makeContent(clock))
        return panel
    }
}

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
```

- [ ] **Step 2: AppDelegate – Klickverhalten**

In `UniFiCameraPopup/AppDelegate.swift`:
1. Neben den anderen Properties:
```swift
    /// The former status menu; shown on right-click / ⌃-click.
    private var classicMenu: NSMenu?
    private lazy var statusPanel: StatusPanelController = StatusPanelController { [unowned self] clock in
        AnyView(StatusPanelView(
            settings: settings,
            events: EventLog.shared,
            protectEvents: protectEvents,
            relay: webSocketClient,
            protect: ProtectSession.shared,
            clock: clock,
            actions: StatusPanelActions(
                openSettings: { [weak self] in
                    self?.statusPanel.close()
                    self?.openSettings()
                },
                openHelp: { [weak self] in
                    self?.statusPanel.close()
                    self?.openHelp()
                },
                quit: { NSApp.terminate(nil) },
                openCamera: { [weak self] id in
                    self?.statusPanel.close()
                    self?.openCamera(entryId: id)
                },
                close: { [weak self] in self?.statusPanel.close() },
                resize: { [weak self] size in self?.statusPanel.resize(to: size) }
            )
        ))
    }
```
2. In `setupStatusItem()` die Zeile `statusItem?.menu = menu` ersetzen durch:
```swift
        classicMenu = menu
        if let button = statusItem?.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
```
3. Neue Methoden (z. B. nach `openOnboarding()`):
```swift
    /// Left click: template panel. Right click or ⌃-click: the former menu (version, update, cameras …).
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsClassicMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsClassicMenu {
            statusPanel.close()
            statusItem?.menu = classicMenu
            sender.performClick(nil)
            statusItem?.menu = nil
        } else {
            statusPanel.toggle(from: sender)
        }
    }

    private func openCamera(entryId: UUID) {
        guard let mapping = settings.mappings.first(where: { $0.entryId == entryId }) else { return }
        PopupController.shared.showHotkeyPopup(for: mapping)
    }
```

- [ ] **Step 3: pbxproj**

PBXBuildFile `A10000000000000000000081 /* StatusPanel.swift in Sources */ = {isa = PBXBuildFile; fileRef = A20000000000000000000081 /* StatusPanel.swift */; };`
PBXFileReference `A20000000000000000000081 /* StatusPanel.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = StatusPanel.swift; sourceTree = "<group>"; };`
Gruppe:
```
		A40000000000000000000073 /* StatusPanel */ = {
			isa = PBXGroup;
			children = (
				A20000000000000000000081 /* StatusPanel.swift */,
			);
			path = StatusPanel;
			sourceTree = "<group>";
		};
```
In `Views`-Gruppe `A40000000000000000000073 /* StatusPanel */,`; Sources-Phase `A10000000000000000000081 /* StatusPanel.swift in Sources */,`.

- [ ] **Step 4: Lint und Build**

`plutil -lint …` → OK; Build → `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Sichtprüfung gegen `docs/design/menue.md`**

1. Linksklick aufs Symbol: Panel 338 breit, 8 pt unter der Menüleiste, rechts bündig mit dem Symbol; Reihenfolge Kopf · Ereignisse · Stumm-Buttons · Linie · Einstellungen.
2. Chip „Zu Hause“ bei verbundener Konsole; Konsole trennen (WLAN aus) → „Getrennt“.
3. Nach einem Ereignis erscheint es oben (Schnappschuss oder Streifen, „Klingel“ / „Haustür“ / Uhrzeit); Klick öffnet die Kamera.
4. „15 Min.“ → Panel schließt; erneut öffnen: Bereich „Stummgeschaltet“ mit „Alle Kameras bis …“ und „Aufheben“; Zzz-Abzeichen am Symbol. „Aufheben“ → Zeile weg, Abzeichen weg.
5. Pro-Kamera-Stumm aus dem Popup erscheint dort als eigene Zeile mit Kameranamen.
6. Dauern in Allgemein auf 30 Minuten / 2 Stunden ändern → Buttons zeigen „30 Min.“ / „2 Std.“.
7. ⌘, öffnet Einstellungen, ⌘Q beendet; Klick außerhalb schließt das Panel; Klick aufs Symbol bei offenem Panel schließt es.
8. Rechtsklick zeigt das bisherige Menü mit Version, Update, Kameras, Einrichtung, „Stummschaltung aufheben (…)“.
9. Hell/Dunkel.

- [ ] **Step 6: Commit**

```bash
git add UniFiCameraPopup/Views/StatusPanel UniFiCameraPopup/AppDelegate.swift UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "feat(menu): template menu bar panel with recent events, mute status and unmute" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: „Was ist neu“, Bildvergleich mit der Vorlage, Ende-zu-Ende-Prüfung

**Files:**
- Modify: `UniFiCameraPopup/Services/WhatsNewService.swift:25-29` (1.2.0-Eintrag ergänzen)

**Interfaces:**
- Consumes: alles aus Task 1–8.
- Produces: geprüfter Stand, Vergleichsbilder (nur lokal, nicht im Repo).

- [ ] **Step 1: „Was ist neu“ ergänzen**

In `WhatsNewService.swift` den 1.2.0-Eintrag ersetzen durch:
```swift
        ChangelogEntry(version: "1.2.0", items: [
            "Einrichtung in wenigen Schritten: Die Konsole wird im Netzwerk gefunden, ein API-Schlüssel genügt.",
            "Popups bei Klingel, Person, Tier, Fahrzeug, Sprache und mehr – direkt aus Protect.",
            "Stream-Adressen holt die App selbst. Webhooks gibt es weiterhin unter „Erweitert“.",
            "Neue Einstellungen mit den Reitern Allgemein, Kameras, Ton und Unterwegs – hell, dunkel oder wie das System.",
            "Stummschalten pro Kamera direkt im Popup und für alle Kameras im Menü; die Dauern legst du selbst fest, und eine Stummschaltung bleibt auch nach einem Neustart bestehen.",
            "Das Popup zeigt Ereignis, Kamera und Uhrzeit, deine Buttons (z. B. „Tür öffnen“) haben jetzt Symbole.",
        ]),
```

- [ ] **Step 2: Alle Tests und Build**

Run: `(cd Packages/AppCore && swift test 2>&1 | tail -3)` → 0 failures
Run: `(cd Packages/ProtectKit && swift test 2>&1 | tail -3)` → 0 failures
Run: Build-Befehl → `** BUILD SUCCEEDED **`

- [ ] **Step 3: Bildvergleich (Pflicht vor „fertig“, ~/Projects/snackbits/CLAUDE.md)**

Vorlage aufnehmen: Das veröffentlichte Artefakt https://claude.ai/artifact/Q9JCg1b1gu5stRG2SxaKsP im angemeldeten Browser (Chrome DevTools MCP / Playwright MCP) öffnen, Zoom 100 %, je Board einen Screenshot sichern und die Fenster ausschneiden. Koordinaten im Board (1×, aus dem Grid der Vorlage berechnet: Innenabstand 64, Abstand 56, Beschriftung 16 + 12 über jedem Fenster; bei ±2 pt Versatz am Fensterrand nachjustieren):

| Bild | Board | x | y | Breite × Höhe |
|---|---|---|---|---|
| S1 Allgemein | Einstellungen | 64 | 92 | 760 × 540 |
| S2 Kameras | Einstellungen | 887 | 92 | 760 × 540 |
| S3 Kameras Erweitert | Einstellungen | 1709 | 92 | 760 × 540 |
| S4 Button-Sheet | Einstellungen | 64 | 716 | 760 × 540 |
| S5 Ton | Einstellungen | 887 | 716 | 760 × 540 |
| S6 Unterwegs | Einstellungen | 1709 | 716 | 760 × 540 |
| 7 Menü-Panel | Main | 1298 + 142 | 596 + 34 | 338 × Panelhöhe |
| 8 Popup | Main | 1915 + 45 | 596 + 60 | 470 × 300 |

Ausschneiden z. B. mit `sips -c <höhe> <breite> --cropOffset <y> <x> board.png --out S1.png`. Dasselbe für „Einstellungen · Dunkel“ und „Einrichtung & Alltag · Dunkel“.

App aufnehmen (Terminal braucht „Bildschirmaufnahme“ in den Datenschutz-Einstellungen):
```bash
OUT="${TMPDIR:-/tmp}/ucp-phase2-compare"; mkdir -p "$OUT"
cat > "$OUT/windows.swift" <<'EOF'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in list where (window["kCGWindowOwnerName"] as? String) == "UniFi Camera Popup" {
    let bounds = window["kCGWindowBounds"] as? [String: Any] ?? [:]
    print(window["kCGWindowNumber"] ?? "?", window["kCGWindowName"] ?? "", bounds["Width"] ?? "", bounds["Height"] ?? "")
}
EOF
swift "$OUT/windows.swift"               # listet ID, Titel, Größe aller App-Fenster
screencapture -o -x -l <ID> "$OUT/app-S1.png"   # je Bildschirm; -o ohne Fensterschatten
```
Einstellungsfenster: Titel „Allgemein“/„Kameras“/„Ton & Sprechen“/„Unterwegs“; Popup und Panel haben keinen Titel – an der Größe erkennen. Retina-Aufnahmen sind 2×: `sips -Z` auf 1× verkleinern oder die Vorlage mit Zoom 200 % aufnehmen.

Je Bildschirm Vorlage und App nebeneinander ansehen (beide PNGs öffnen) und gegen `docs/design/*.md` abhaken: Reihenfolge, Texte, Abstände, Schriftgrößen/-schnitte, Farben hell und dunkel. Jede Differenz, die nicht unter „Abweichungen von der Vorlage“ steht, wird behoben (zurück in den betreffenden Task) oder als neue Frage gemeldet – nicht still akzeptiert.

- [ ] **Step 4: Ende-zu-Ende-Prüfung** (Ergebnis je Punkt notieren)

Vorher Sicherung: `defaults export com.snackbits.UniFiCameraPopup "$OUT/defaults-before.plist"`.
1. Erster Start der neuen Build über bestehenden Einstellungen: alle Kameras, Tastenkürzel, Buttons (inkl. Token) sind da; Buttons haben das Blitz-Symbol; eine vorher laufende globale Stummschaltung gilt weiter.
2. Erscheinungsbild System/Hell/Dunkel wirkt auf Einstellungen, Panel, Popup-Leiste und Stumm-Menü; „System“ folgt einem Wechsel in den macOS-Einstellungen live.
3. Stumm pro Kamera aus dem Popup: diese Kamera bleibt still, andere melden sich; App beenden, neu starten → weiter stumm; nach Ablauf meldet sie sich wieder, Panel-Zeile ist weg (ohne Neustart).
4. Global stumm aus dem Panel, „Aufheben“ im Panel und „Stummschaltung aufheben“ im Rechtsklick-Menü heben auf.
5. Stumme Kamera entfernen → keine Panel-Zeile, kein Eintrag im Rechtsklick-Menü.
6. Dauer-Felder: „0“, „abc“, „5000“ → 1 / alter Wert / 999; Einheitenwechsel ändert Panel-Buttons und Popup-Menü.
7. Klingel an der Türklingel: Popup-Chip „Klingel · Haustür · HH:mm“, Ereignis oben im Panel, „Zuletzt ausgelöst: heute, …“ unter Kameras › Erweitert; „Hinweiston beim Öffnen“ an → Ton „Glass“ beim Popup.
8. Webhook-Eintrag (Relay) löst weiter aus; Panel zeigt „Webhook“ als Ereignis.
9. Konfiguration exportieren → Datei enthält keinen API-Schlüssel (`grep -c X-API-KEY` und Suche nach dem Schlüssel → 0); Import auf demselben Mac stellt alles wieder her.
10. Alle früheren Einstellungen auffindbar: Popup-Position (Allgemein), Bildschirm/Randabstand/Auto-Schließen/Alle aktiven Kameras/Updates/Relay/Hilfe (Allgemein › Erweitert), Größe/Position/Ausschnitt/Test-Popup/Stream-Adresse/Webhook-ID (Kameras › Erweitert), Tastenkürzel, Zoom merken, Buttons (Kameras).
11. Konsolensuche (Einrichtung › „Ändern …“) findet die Konsole weiterhin; der neue 401-Fallback ist nur mit einer Konsole prüfbar, die `/api/system` mit Login schützt – sonst als „nicht prüfbar“ notieren.

- [ ] **Step 5: Commit**

```bash
git add UniFiCameraPopup/Services/WhatsNewService.swift
git diff --cached --name-only | grep AppConfig && echo "STOP: AppConfig staged" || true
git commit -m "chore: extend 1.2.0 release notes for settings, popup and mute" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
Kein Push, kein Merge, kein Release-Build (Release-Ablauf erst nach Phase 3/4 und Rückfrage).
