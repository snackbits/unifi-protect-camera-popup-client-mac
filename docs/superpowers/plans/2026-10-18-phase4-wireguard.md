# Phase 4 – Unterwegs: WireGuard-Tunnel nur für die App – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ist die Konsole nicht direkt erreichbar (unterwegs), baut die App automatisch einen eigenen WireGuard-Tunnel nur für ihren eigenen Verkehr auf und leitet Protect-HTTPS/WebSocket (URLSession, Zertifikats-Pin bleibt gültig) und RTSP (VLC) darüber; eingerichtet wird er per `.conf`-Datei in Einrichtungsschritt 6 und im Reiter „Unterwegs“.

**Architecture:** Der Prototyp wird zum Go-Modul `wgtunnel/` (wireguard-go + gVisor-netstack, `-buildmode=c-archive`, universal arm64 + x86_64, Go-Toolchain gepinnt in einem gitignorierten Ordner). Das Archiv öffnet pro Ziel einen lokalen TCP-Forwarder `127.0.0.1:<port>` → `<host>:<port>` durch den Tunnel; `ProtectClient` spricht dann `https://127.0.0.1:<port>` an (der Pin vergleicht nur den Fingerabdruck des Leaf-Zertifikats, nie den Namen) und VLC bekommt `rtsp://127.0.0.1:<port>/<alias>`. Ein `ConnectionRouter` entscheidet per kurzem TLS-Test der Konsolenadresse (nur das gepinnte Zertifikat zählt als „zu Hause“), ob direkt oder über den Tunnel verbunden wird; ein Liveness-Wächter erkennt Ausfall und Wiederkehr des Tunnels und baut danach alle durchgereichten Verbindungen neu auf. Reine Logik liegt in `ProtectKit` (`swift test`), die App ist dünne Verdrahtung.

**Tech Stack:** Go 1.27.2 (wireguard-go `v0.0.0-20261006164505-2631ce99a06f`, gVisor `v0.0.0-20250503011706-39ed1f5ac29c`), cgo c-archive + Clang-Modul `WGTunnelC`, Swift 5.9 Tools / Xcode 27, SwiftUI + AppKit (macOS 13.0), `Network.framework` (`NWPathMonitor`), XCTest über `swift test` (ProtectKit), `go test`.

**Spec:** `docs/superpowers/specs/2026-10-18-phases-2-4.md` – Abschnitte „Phase 4“, „Querschnitt“, „Verbindliche Vorlage“. Vorlage: `docs/superpowers/specs/phase2-4/design/Main.dc.html` (Board 6 „Unterwegs (WireGuard)“) und `.../Einstellungen.dc.html` (S6 „Unterwegs“), veröffentlicht als https://claude.ai/artifact/Q9JCg1b1gu5stRG2SxaKsP. Prototyp: `docs/superpowers/specs/phase2-4/wgtest-prototype/`. Phase 2 (Voraussetzung): `docs/superpowers/plans/2026-10-18-phase2-design-mute.md`.

## Voraussetzung: Phase 2 ist umgesetzt

Dieser Plan baut auf dem Stand nach Phase 2 auf und benutzt deren Bausteine mit den Namen aus dem Phase-2-Plan (Task 3, Abschnitt „Interfaces → Produces“). Vor Task 1 prüfen (alle Treffer > 0):

```bash
grep -c "public enum Tokens" Packages/AppCore/Sources/AppCore/DesignTokens.swift
grep -c "public static func dayAndTime" Packages/AppCore/Sources/AppCore/DisplayText.swift
grep -c "enum TemplateIcon" UniFiCameraPopup/Views/Design/DesignComponents.swift
grep -c "struct FixedLabelRow\|struct CardRow\|struct CardDivider\|struct Card<\|struct FieldButtonStyle\|struct LinkButtonStyle" UniFiCameraPopup/Views/Design/DesignComponents.swift
grep -c "struct PopUpField\|enum MenuPresenter\|final class ViewAnchor\|struct AnchorView" UniFiCameraPopup/Views/Design/PopUpField.swift
grep -rln "Bereit · gerade zu Hause" UniFiCameraPopup/Views    # Gerüst des Reiters „Unterwegs“
ls docs/design/einstellungen-unterwegs.md docs/design/tokens.md
```

Weicht ein Name ab, gilt der tatsächliche Name aus dem Phase-2-Code; die Stelle im Code dieses Plans wird entsprechend angepasst (nur der Name, nicht das Verhalten). Es gibt **kein** Test-Bundle im Xcode-Projekt (Phase-2-Entscheidung „Test-Target als lokales Package“): Alles Testbare liegt hier in `ProtectKit` und im Go-Modul.

## Global Constraints

- macOS-Deployment-Target **13.0**; keine Sandbox; Hardened Runtime bleibt aus; kein bezahlter Developer-Account – also **keine Network Extension, kein System-VPN**: der Tunnel lebt nur im App-Prozess (wireguard-go + gVisor-netstack, gelinkt als `c-archive`).
- Go-Toolchain **go1.27.2**, gepinnt (Spezifikation verlangt ≥ 1.22; das Prototyp-`go.mod` verlangt 1.27.2). Download nach `wgtunnel/.toolchain/` (gitignoriert), SHA-256 `darwin-arm64` = `76812b213b1b2302c978d28fa52fa92d541704b9e7d9d5db8002c50e4018c4c5`, `darwin-amd64` = `587b59182488b23aa6e5fc25110405a3e0e5b38ed2f5b2f46ed13c32aee356fe` (Quelle: `https://go.dev/dl/?mode=json`). Das System-Go 1.19 amd64 wird nie benutzt (`GOTOOLCHAIN=local`, sauberes `env -i`).
- Archiv `wgtunnel/build/libwgtunnel.a` ist immer **universal (arm64 + x86_64)**, gebaut von der Xcode-Build-Phase „Build WireGuard tunnel“. `build-release.sh` baut die App universal (`-destination 'generic/platform=macOS'`) – Befund: die bisherigen Releases (`server/public/app.zip`, Build 27/28) sind nur arm64.
- WireGuard-Konfiguration (enthält den privaten Schlüssel) **nur im Schlüsselbund** (Dienst `com.snackbits.UniFiCameraPopup.wireguard-config`); nie in `UserDefaults`, `settings`, Konfigurations-Export oder Log.
- Tunnel nur, wenn die Konsole nicht direkt erreichbar ist (Einstellung „Tunnel verwenden: Automatisch“, Standard); „Immer“/„Nie“ als Zusatz (Abweichung 3).
- Zertifikats-Pin bleibt auf das Konsolen-Zertifikat bezogen: `ProtectClient` vergleicht den SHA-256 des Leaf-Zertifikats, unabhängig davon, ob er `192.168.1.1` oder `127.0.0.1:<port>` anspricht.
- Lizenzen: wireguard-go **MIT**, gVisor **Apache-2.0**, Go + golang.org/x **BSD-3-Clause**, google/btree **Apache-2.0** → `UniFiCameraPopup/ThirdPartyNotices.txt` (generiert) und Hilfe › „Über“.
- UI-Sprache Deutsch, Du-Form, typografische Anführungszeichen „…“; Code und Bezeichner Englisch. Vorlage ist **Vorgabe, keine Anregung**: Maße/Texte/Farben 1:1 aus `docs/design/*.md` (Task 8/9 schreiben die Unterwegs-Dateien); Abweichungen nur die unten genannten.
- Version bleibt **1.2.0**, Build-Nummer unangetastet; nur der bestehende 1.2.0-Eintrag in `WhatsNewService` wird ergänzt. `build-release.sh` wird in diesem Plan **nie ausgeführt** (es zählt `AppConfig.swift` hoch).
- `UniFiCameraPopup/AppConfig.swift` hat lokale Änderungen des Nutzers: **nie ändern, nie stagen, nie zurücksetzen**. Nur explizite Pfade `git add`; nie `git add -A`/`.`/`commit -a`. Vor jedem Commit: `git diff --cached --name-only | grep AppConfig` → leer.
- Kein Merge, kein Push. Jeder Task endet mit grünem Build. Commit-Nachrichten enden mit `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Neue pbxproj-IDs: Präfix **D4** (`D41…` BuildFile, `D42…` FileRef, `D44…` Gruppe, `D46…` Build-Phase). Vorher `grep -c "D41000000000000000000001\|D46000000000000000000001" UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj` → `0`.
- Debug-Build und installierte App teilen Bundle-ID, `UserDefaults` und Schlüsselbund: vor Sichtprüfungen die installierte App beenden.

**Befehle** (aus dem Worktree-Wurzelverzeichnis `app-protect/`):

```bash
# Go (lädt beim ersten Mal go1.27.2 und die Module; braucht Netz)
wgtunnel/scripts/go.sh vet ./... && wgtunnel/scripts/go.sh test -count=1 ./...
"$(wgtunnel/scripts/fetch-go.sh)/bin/gofmt" -l wgtunnel/tunnel wgtunnel/wgconf wgtunnel/capi wgtunnel/cmd   # Erwartet: keine Ausgabe

# Archiv + Swift-Ende-zu-Ende über Loopback (ab Task 3)
wgtunnel/scripts/smoke.sh                     # Erwartet: letzte Zeile „SMOKE OK“

# ProtectKit
(cd Packages/ProtectKit && swift test 2>&1 | tail -3)

# App bauen
DD="${TMPDIR:-/tmp}/ucp-phase4-dd"
xcodebuild -project UniFiCameraPopup/UniFiCameraPopup.xcodeproj -scheme UniFiCameraPopup \
  -configuration Debug -derivedDataPath "$DD" build 2>&1 | grep -E "error:|\*\* BUILD" | tail -20
# Erwartet: ** BUILD SUCCEEDED **

# pbxproj nach Änderung prüfen
plutil -lint UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj

# Log der laufenden App (Route, Tunnel, VLC)
log stream --style compact --predicate 'process == "UniFi Camera Popup" AND (eventMessage CONTAINS "Route" OR eventMessage CONTAINS "Tunnel" OR eventMessage CONTAINS "VLC")'
```

## Review Focus

1. **Fremdes Netz mit derselben Konsolenadresse** (Hotel-Router auf 192.168.1.1 antwortet auf 443): Das zählt **nicht** als „zu Hause“ – kein API-Schlüssel geht dorthin, keine „Zertifikat geändert“-Warnung, die App nimmt den Tunnel. → `TunnelRoutingTests.testForeignDeviceOnSameAddressUsesTunnel`, `testReachabilityFromPin`, `ProtectClientTests.testProbeWithShortTimeoutSendsNoKey` (Task 4).
2. **Ausfall länger als 120 s, dann kommt der Tunnel wieder** (WLAN weg, Zug im Tunnel): Ereignisse und ein offenes Livebild laufen ohne Zutun weiter; keine hängende Verbindung. → `TunnelLivenessTests.testStallThenRecovery` (Task 4), Go `TestResetConnectionsClosesRelaysButKeepsPort` (Task 2), manueller Prüfpunkt Task 10.
3. **Falsche Datei abgelegt oder eingefügt** (PDF, 10-GB-Video, leere Zwischenablage, Tippfehler in der `.conf`): verständliche deutsche Meldung mit Zeilennummer, nichts wird gespeichert, eine vorhandene funktionierende Konfiguration bleibt. → `WireGuardFileTests`, `TunnelModelsTests.testParseInvalidCarriesGoMessage` (Task 4/5), Go `TestErrors` (Prototyp, Task 1), manueller Prüfpunkt Task 10.
4. **Konfiguration, deren `AllowedIPs` die Konsole nicht enthält** (z. B. nur `192.168.3.0/24`, Konsole auf 192.168.1.1): Import klappt, aber mit Hinweis statt späterer stiller Funkstille. → `TunnelRecordTests.testImportWarning` (Task 5).
5. **Schlüssel landet nie außerhalb des Schlüsselbunds; Schlüsselbund und Einstellungen laufen auseinander** (Schlüsselbund zurückgesetzt, Backup eingespielt, neuere App-Version schrieb einen unbekannten Modus): kein Schlüssel in `UserDefaults`/Export; ohne Schlüsselbund-Eintrag gilt „kein Tunnel“, unbekannter Modus → „Automatisch“. → `TunnelRecordTests.testStoredFormHasNoRoomForKeys`, `testWithoutKeychainItemOnlyModeSurvives`, `testUnknownModeFromNewerBuildFallsBackToAutomatic`, `wgconf.TestSummaryHasNoKeysAndEmptyListsAreArrays` (Task 1/5), Export-Prüfung Task 10.

---

## Abweichungen von der Vorlage

Stellen, an denen die Vorlage keine Antwort hat oder SwiftUI/AppKit sie nicht 1:1 kann. Umgesetzt wird der genannte Vorschlag; alle stehen unter „Offene Fragen“ zur Bestätigung.

1. **Reiter „Unterwegs“ ohne Datei:** Die Vorlage zeigt nur den eingerichteten Zustand. Vorschlag: „Noch nicht eingerichtet“ 14/700, darunter 12 `muted` „Lege die WireGuard-Datei deines Gateways hier ab. Die App nutzt den Tunnel nur für sich.“, darunter das Ablagefeld aus Einrichtungsschritt 6; in der Fußzeile nur der Anleitungs-Link.
2. **Weitere Zustände der Statusfläche** (Vorlage: nur „Bereit · gerade zu Hause“): „Aus“ / „Die App verbindet sich nur direkt mit der Konsole.“ · „Verbinde · unterwegs“ / „Der Tunnel wird aufgebaut …“ · „Verbunden · unterwegs“ / „Die App erreicht deine Konsole über den Tunnel.“ · „Keine Verbindung · unterwegs“ / „Die Gegenstelle antwortet nicht. Prüfe Internet und Port-Weiterleitung.“ · „Tunnel startet nicht“ / Fehlermeldung. Symbol bleibt immer das Schild-Häkchen (die Vorlage hat kein Warnsymbol).
3. **„Tunnel verwenden“:** Vorlage zeigt nur „Automatisch“. Vorschlag: Auswahl „Automatisch“ (Standard) / „Immer“ / „Nie“.
4. **„Letzte Verbindung“:** Datum wie im ganzen Programm über `DisplayText.dayAndTime` („heute, 08:05“ · „gestern, 18:22“ · „12.10., 18:22“), dann „ · über WLAN | Ethernet | Mobilfunk | Netzwerk“; ein iPhone-Hotspot (WLAN, aber „teuer“) zählt als „Mobilfunk“. Nie verbunden → „noch nie“.
5. **„Ersetzen …“ und Einfügen:** Die Spezifikation verlangt „importieren oder einfügen“, die Vorlage zeigt keinen Ort fürs Einfügen. Vorschlag: „Ersetzen …“ öffnet ein natives Menü „Datei auswählen …“ / „Aus Zwischenablage einfügen“; das Ablagefeld nimmt Dateien per Ziehen an, Klick öffnet die Dateiauswahl, Rechtsklick bietet beide Einträge.
6. **Rückmeldung nach dem Import:** eine Zeile unter dem Ablagefeld im Stil von Schritt 3 („Passt. 4 Kameras gefunden.“): „Passt. Gegenstelle: home.example.org:51820“ in `ok` mit Häkchen 14. Hinweise (z. B. „Achtung: Konsole 192.168.1.1 liegt nicht in „AllowedIPs“.“) und Fehler einzeilig in System-Orange (wie Phase 2 für Testfehler), voller Text als Tooltip. So passt Schritt 6 sicher in 560 × 420 (gemessen: 356 von 370 pt mit Rückmeldezeile).
7. **„Jetzt testen“:** Während des Tests heißt der Button „Teste …“; das Ergebnis steht als Zeile 12 pt unter der Karte (`ok` bzw. System-Orange). Texte: siehe `TunnelTestOutcome` (Task 5).
8. **„Tunnel entfernen“** fragt per nativem Bestätigungsdialog nach.
9. **Anleitung:** eigenes Sheet „WireGuard einrichten“ (5 Schritte + Hinweis), erreichbar über „Ausführliche Anleitung öffnen“ und „Anleitung: WireGuard auf dem UniFi-Gateway einrichten“. Weder Layout noch Text stehen in der Vorlage.
10. **Status unterwegs im Menü:** Chip im Menüleisten-Panel „Unterwegs“ statt „Zu Hause“, wenn über den Tunnel verbunden (gleiche Farben `okBg`/`ok`); Statuszeile im Rechtsklick-Menü „Protect: verbunden · unterwegs“.
11. **Einrichtungsschritt 6:** Überschrift 20/700 und Text 12 mit Zeilenhöhe 1,5 exakt nach Vorlage; die Schritte 2–5 aus Phase 1 nutzen `.title3`/`.callout` und weichen damit ab (nicht Teil dieses Plans). Buttons „Später“/„Fertig“ native große Buttons wie in den Schritten 1–5 (Breite 150 → Text 126 + Systemrand).
12. **„Über“:** Die App hat bisher kein „Über“. Vorschlag: neuer Eintrag „Über“ in der Hilfe (Version, Lizenzhinweis, vollständige Lizenztexte).

## Offene Fragen

1. Abweichungen 1–12 bestätigen (besonders: Zustandstexte 2, Optionen „Immer/Nie“ 3, Einfügen über das Menü 5, „Über“ in der Hilfe 12).
2. **Webhook-Buttons im Popup** („Tür öffnen“ → z. B. Home Assistant im LAN) laufen unterwegs **nicht** über den Tunnel – nur Protect (HTTPS/WebSocket) und RTSP tun das. Sollen sie mit? (Machbar über denselben Forwarder; Host-Header/TLS-Name dieser Ziele ändern sich dann.)
3. **Sprechen (Phase 3) unterwegs:** `TunnelBridge.addUDPForward(ip:port:)` liegt bereit (UDP 127.0.0.1 → Kamera:7004, im Prototyp 0 % Verlust). Der Einbau hängt am Phase-3-Code – in diesem Plan nicht enthalten. Nachziehen, sobald Phase 3 steht?
4. **Schritte 2–5 typografisch an die Vorlage angleichen** (20/700, 12 mit Zeilenhöhe 1,5)? Sonst wirkt Schritt 6 größer als seine Vorgänger.
5. **Host-Header:** Über den Tunnel sieht die Konsole `Host: 127.0.0.1:<port>` (TLS ist Ende-zu-Ende, der Forwarder sieht nur Bytes). UniFi OS antwortet erfahrungsgemäß auf jede Adresse, an echter Hardware ist das aber ungeprüft (manueller Prüfpunkt Task 10, Schritt 4). Plan B, falls die Konsole ablehnt: lokaler HTTP-CONNECT-Proxy im Go-Modul und `URLSessionConfiguration.connectionProxyDictionary` (dann stimmen Host und SNI) – RTSP bleibt beim Forwarder.

---

## File Structure

```
wgtunnel/                                   (neu – Go-Modul, aus dem Prototyp)
  go.mod, go.sum                            unverändert aus dem Prototyp
  wgconf/wgconf.go, wgconf_test.go          unverändert (Parser für wg-quick/UniFi-Export)
  wgconf/summary.go, summary_test.go        nicht-geheime Zusammenfassung (Endpoint, AllowedIPs …)
  tunnel/tunnel.go                          + idempotente Forwards, ResetConnections, Rebind, Keepalive-Standard
  tunnel/tunnel_test.go                     Loopback-Tunnel gegen eine Test-„Heimat“ (netstack)
  capi/capi.go                              C-API: + WgParse, WgResetConnections, WgRebind
  include/wgtunnel.h, module.modulemap      handgeschriebener Header, Clang-Modul WGTunnelC
  cmd/home, cmd/udprelay                    Test-Heimat und Ausfall-Simulator (aus dem Prototyp)
  scripts/fetch-go.sh                       lädt go1.27.2 (SHA-256 gepinnt) nach .toolchain/
  scripts/go.sh                             Go mit sauberer Umgebung
  scripts/build-archive.sh                  universal libwgtunnel.a (Xcode-Build-Phase)
  scripts/collect-notices.sh                erzeugt UniFiCameraPopup/ThirdPartyNotices.txt
  scripts/smoke.sh, smoke/main.swift        Swift-Ende-zu-Ende über Loopback
  .toolchain/, build/                       gitignoriert

Packages/ProtectKit/
  Sources/ProtectKit/ProtectClient.swift    + requestTimeout, probeFingerprint(host:timeout:)
  Sources/ProtectKit/Tunnel/                (neu)
    TunnelModels.swift      TunnelConfigSummary, TunnelParseResult, TunnelStatus (JSON der C-API)
    TunnelRouting.swift     TunnelMode, ProtectRoute, DirectReachability, RouteDecision
    TunnelLiveness.swift    Ausfall/Wiederkehr aus Rx-Zählern
    ForwardURL.swift        ForwardTarget, API-Host/RTSP-URL ↔ 127.0.0.1:<port>
    AllowedIPs.swift        liegt eine IP in den AllowedIPs?
    WireGuardFile.swift     Datei-Vorprüfung (leer, zu groß, kein Text)
    TunnelRecord.swift      gespeicherte Nicht-Geheimnisse, TunnelImportCheck
    TunnelText.swift        NetworkKind, TunnelRunState, TunnelPhase, TunnelTestOutcome, Texte
  Tests/ProtectKitTests/Tunnel/*Tests.swift  je Quelldatei
  Tests/ProtectKitTests/ProtectClientTests.swift, PinEnforcementTests.swift   + Timeout-, Pin-über-Forward-Test

UniFiCameraPopup/
  UniFiCameraPopup.xcodeproj/project.pbxproj   + Build-Phase, Linker, Modulpfad, neue Dateien
  scripts/pbxproj-add-files.py (neu)            trägt Dateien ins App-Target ein
  scripts/build-release.sh                      universal + Prüfungen
  ThirdPartyNotices.txt (neu, generiert)        Lizenztexte (Ressource)
  Assets.xcassets/Icons/fileDownload.imageset   Symbol des Ablagefelds (aus Main 6)
  Services/KeychainStore.swift                  + wireGuardConfigService
  Services/Tunnel/TunnelBridge.swift (neu)      Swift-Hülle um die C-API
  Services/Tunnel/TunnelStore.swift (neu)       Schlüsselbund + TunnelRecord
  Services/Tunnel/TunnelImporter.swift (neu)    Prüfen und Speichern einer .conf
  Services/Tunnel/TunnelController.swift (neu)  Start/Stopp, Forwards, Liveness
  Services/Tunnel/ConnectionRouter.swift (neu)  direkt oder Tunnel, Auslöser, „Jetzt testen“
  Services/ProtectSession.swift                 API-Host über den Router
  Services/ProtectEventService.swift            Neuaufbau nach Tunnel-Reset, meldet Abbrüche
  Services/WhatsNewService.swift                1.2.0-Eintrag ergänzt
  Views/VLCPlayerView.swift                     RTSP über den Router, Neustart bei Routen-/Tunnelwechsel
  Views/Design/DesignComponents.swift           TemplateIcon + fileDownload
  Views/Tunnel/WireGuardImport.swift (neu)      Ablagefeld, Dateiauswahl, Zwischenablage, Rückmeldung
  Views/Tunnel/WireGuardGuideView.swift (neu)   Anleitung (Sheet)
  Views/Tunnel/OnboardingTunnelStep.swift (neu) Einrichtung Schritt 6
  Views/Tunnel/TunnelSettingsView.swift (neu)   Inhalt Reiter „Unterwegs“
  Views/Onboarding/OnboardingView.swift         Schritt .travel, Prüfaufrufe über den Router
  Views/Settings/SoundAndRemoteTabs.swift       Gerüst „Unterwegs“ → TunnelSettingsView
  Views/HelpView.swift                          Eintrag „Über“ mit Lizenzen
  AppDelegate.swift                             Router starten, „· unterwegs“ in der Statuszeile
  (Menüleisten-Panel aus Phase 2)               Chip „Unterwegs“

docs/design/einrichtung-unterwegs.md (neu), docs/design/einstellungen-unterwegs.md (Phase-4-Fassung)
README.md, .gitignore
```

---

## Design-Spezifikation

Task 8 und Task 9 legen diese Dateien unverändert unter `docs/design/` ab (die zweite ersetzt die Phase-2-Gerüstfassung). Der Code wird gegen sie geprüft. Maße in pt (= CSS-px der Vorlage, 1×), Farben = Tokens aus `docs/design/tokens.md`.

### `docs/design/einrichtung-unterwegs.md`

```markdown
# Einrichtung › Schritt 6 „Unterwegs (WireGuard)“ (Vorlage Main 6)

Fenster 560 × 420 wie Schritte 1–5, Inhalt zentriert, Innenabstand 18/44/22 (oben inkl. Ampelzeile),
senkrechter Abstand 11, Text zentriert.
1. Kreis 64, Fläche `accSoft`, Symbol Schild (Pfad wie Reiter-Symbol „Unterwegs“, `tabRemote`) 30,
   Strich 1,7, Farbe `accText`.
2. „Auch unterwegs?“ 20/700.
3. „Lege auf deinem UniFi-Gateway einen WireGuard-Server an, füge einen Client für diesen Mac hinzu
   und lade dessen Datei herunter. Die App nutzt den Tunnel nur für sich.“ 12, Zeilenhöhe 1,5, `muted`.
4. Ablagefeld, volle Breite, Höhe 74, Radius 12, Rand 2 gestrichelt `dropBorder`, Fläche `accSoft`,
   Inhalt mittig, Abstand 10: Symbol Dokument-mit-Pfeil (`fileDownload`) 22, Strich 1,7 ·
   „WireGuard-Datei hier ablegen“ 13/600 · beides `accText`.
   (Abw. 5) Ziehen einer Datei; Klick = Dateiauswahl; Rechtsklick = „Datei auswählen …“ / „Aus Zwischenablage einfügen“.
   Beim Darüberziehen Rand `accent`.
5. (Abw. 6) Rückmeldezeile, nur nach einem Import oder wenn schon eingerichtet: Häkchen 14 + 6 +
   „Passt. Gegenstelle: <host:port>“ 12 `ok`; Hinweis/Fehler 12 System-Orange; einzeilig, Tooltip mit Volltext.
6. Link „Ausführliche Anleitung öffnen“ 12 `accText`, unterstrichen → Sheet „WireGuard einrichten“ (Abw. 9).
7. Freiraum.
8. Zwei Buttons, Abstand 10: „Später“ (14, Breite 150, Rand `chipBorder`, Fläche `field`) ·
   „Fertig“ (14/600, Breite 150, `accent`, weiß). (Abw. 11: native große Buttons, Text 126 breit.)
   Beide beenden die Einrichtung; eine abgelegte Datei ist dann schon gespeichert.
9. Punkte 7 × 7, Abstand 6, sechs Stück, der sechste `accent`, sonst `dotOff`.
Schritt 5 bekommt statt „Fertig“ den Button „Weiter“ (Vorlage Main 5).
```

### `docs/design/einstellungen-unterwegs.md` (Phase-4-Fassung)

```markdown
# Einstellungen › Unterwegs (Vorlage S6)

Kopf wie Allgemein, Titel „Unterwegs“, Reiter „Unterwegs“ aktiv.
Inhalt Innenabstand 20/40, Abstand 14, Schrift 13, Text `fg`.
1. Statusfläche: Abstand 14, Innenabstand 14/16, Radius 12, `accSoft`. Kreis 40 `accent` mit
   Schild-Häkchen 20 (Strich 1,8) weiß · Text senkrecht Abstand 2: Titel 14/700, Untertitel 12 `muted`
   · Feld-Button „Jetzt testen“ (12, 4/12). Während des Tests „Teste …“, deaktiviert (Abw. 7).
   Texte je Zustand (Abw. 2):
   - zu Hause: „Bereit · gerade zu Hause“ / „Der Tunnel springt an, sobald die Konsole nicht direkt erreichbar ist.“ (Vorlage)
   - „Nie“: „Aus“ / „Die App verbindet sich nur direkt mit der Konsole.“
   - Aufbau: „Verbinde · unterwegs“ / „Der Tunnel wird aufgebaut …“
   - verbunden: „Verbunden · unterwegs“ / „Die App erreicht deine Konsole über den Tunnel.“
   - Ausfall: „Keine Verbindung · unterwegs“ / „Die Gegenstelle antwortet nicht. Prüfe Internet und Port-Weiterleitung.“
   - Startfehler: „Tunnel startet nicht“ / Fehlermeldung des Tunnels
2. Karte Radius 10, Fläche `group`, Rand 1 `border`, Zeilen 10/14, Trennlinie 1 `border`, Beschriftung 140 breit:
   „Konfiguration“ | Dateiname `muted` (Mitte gekürzt) | Feld-Button „Ersetzen …“ (12, 3/10) →
     Menü „Datei auswählen …“ / „Aus Zwischenablage einfügen“ (Abw. 5) ·
   „Gegenstelle“ | Endpoint der Datei `muted` (auswählbar) ·
   „Letzte Verbindung“ | „gestern, 18:22 · über Mobilfunk“ `muted`, sonst „noch nie“ (Abw. 4) ·
   „Tunnel verwenden“ (füllt) | Auswahlfeld „Automatisch“ / „Immer“ / „Nie“ (Abw. 3).
3. Zeile verteilt: Link „Anleitung: WireGuard auf dem UniFi-Gateway einrichten“ 12 `accText` ·
   Link „Tunnel entfernen“ 12 `muted` → Bestätigung (Abw. 8).
Darunter bei Bedarf eine Zeile 12: Import-Rückmeldung (Abw. 6), Testergebnis (Abw. 7).
Ohne Datei (Abw. 1): „Noch nicht eingerichtet“ 14/700, Abstand 2, Text 12 `muted`
„Lege die WireGuard-Datei deines Gateways hier ab. Die App nutzt den Tunnel nur für sich.“,
Abstand 10, Ablagefeld wie Einrichtung Schritt 6; Fußzeile nur mit dem Anleitungs-Link.
```

---

### Task 1: Go-Modul `wgtunnel/` mit gepinnter Toolchain

**Files:**
- Create: `wgtunnel/` (Kopie von `docs/superpowers/specs/phase2-4/wgtest-prototype/src/` ohne `cmd/app`)
- Create: `wgtunnel/scripts/fetch-go.sh`, `wgtunnel/scripts/go.sh`
- Create: `wgtunnel/wgconf/summary.go`; Test: `wgtunnel/wgconf/summary_test.go`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: Prototyp (`wgconf.Parse`, `wgconf.Config`, Testkonstanten `unifiExport`, `k1`–`k3` aus `wgconf_test.go`).
- Produces: `wgtunnel/scripts/fetch-go.sh` (druckt GOROOT), `wgtunnel/scripts/go.sh [VAR=wert …] <go-args>` (läuft in `wgtunnel/`), Go: `type wgconf.Summary struct { Endpoint string; Addresses, AllowedIPs, DNS, Warnings []string }` (JSON `endpoint`, `addresses`, `allowedIPs`, `dns`, `warnings`; leere Listen als `[]`), `func (c *Config) Summary() Summary`.

- [ ] **Step 1: Prototyp übernehmen, Ordner ignorieren**

```bash
mkdir -p wgtunnel
cp -R docs/superpowers/specs/phase2-4/wgtest-prototype/src/. wgtunnel/
rm -rf wgtunnel/cmd/app      # Messprogramm des Prototyps; nutzt die HTTPClient-Hilfe, die Task 2 entfernt
ls wgtunnel wgtunnel/cmd     # Erwartet: capi cmd go.mod go.sum tunnel wgconf / home udprelay
```

An `.gitignore` anhängen:

```
# WireGuard tunnel: pinned Go toolchain, module cache and the built archive.
wgtunnel/.toolchain/
wgtunnel/build/
```

- [ ] **Step 2: Toolchain-Skripte anlegen**

`wgtunnel/scripts/fetch-go.sh`:
```bash
#!/bin/bash
# Downloads the pinned Go toolchain into wgtunnel/.toolchain (gitignored) and
# prints its GOROOT. The system Go (1.19 amd64) is too old for wireguard-go.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GO_VERSION="1.27.2"

case "$(uname -m)" in
  arm64)  GO_ARCH="arm64"; GO_SHA256="76812b213b1b2302c978d28fa52fa92d541704b9e7d9d5db8002c50e4018c4c5" ;;
  x86_64) GO_ARCH="amd64"; GO_SHA256="587b59182488b23aa6e5fc25110405a3e0e5b38ed2f5b2f46ed13c32aee356fe" ;;
  *) echo "fetch-go: unbekannte Architektur $(uname -m)" >&2; exit 1 ;;
esac

DEST="${ROOT}/.toolchain/go${GO_VERSION}-${GO_ARCH}"
if [[ -x "${DEST}/go/bin/go" ]] && [[ "$("${DEST}/go/bin/go" env GOVERSION 2>/dev/null)" == "go${GO_VERSION}" ]]; then
  echo "${DEST}/go"
  exit 0
fi

mkdir -p "${ROOT}/.toolchain"
TMP="$(mktemp -d "${ROOT}/.toolchain/download.XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT

URL="https://go.dev/dl/go${GO_VERSION}.darwin-${GO_ARCH}.tar.gz"
echo "fetch-go: lade ${URL}" >&2
curl -fsSL --retry 3 -o "${TMP}/go.tar.gz" "${URL}"
echo "${GO_SHA256}  ${TMP}/go.tar.gz" | shasum -a 256 -c - >&2
tar -xzf "${TMP}/go.tar.gz" -C "${TMP}"
rm -rf "${DEST}"
mkdir -p "${DEST}"
mv "${TMP}/go" "${DEST}/go"
echo "${DEST}/go"
```

`wgtunnel/scripts/go.sh`:
```bash
#!/bin/bash
# Runs the pinned Go toolchain inside wgtunnel/ with a clean environment: Xcode
# build phases export SDKROOT, ARCHS, LD … which Go must not see, and the system
# Go (1.19) must never be used. Extra variables go before the Go arguments:
#   scripts/go.sh test ./...
#   scripts/go.sh GOARCH=amd64 CGO_ENABLED=1 build ./capi
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GOROOT_DIR="$("${ROOT}/scripts/fetch-go.sh")"

EXTRA=()
if [[ -n "${DEVELOPER_DIR:-}" ]]; then EXTRA+=("DEVELOPER_DIR=${DEVELOPER_DIR}"); fi
while [[ $# -gt 0 && "$1" =~ ^[A-Z_][A-Z0-9_]*= ]]; do
  EXTRA+=("$1")
  shift
done

cd "${ROOT}"
exec env -i \
  PATH="${GOROOT_DIR}/bin:/usr/bin:/bin" \
  HOME="${HOME}" \
  GOROOT="${GOROOT_DIR}" \
  GOPATH="${ROOT}/.toolchain/gopath" \
  GOCACHE="${ROOT}/.toolchain/gocache" \
  GOMODCACHE="${ROOT}/.toolchain/gomodcache" \
  GOTOOLCHAIN=local \
  GOFLAGS="-mod=readonly -modcacherw" \
  ${EXTRA[@]+"${EXTRA[@]}"} \
  go "$@"
```

```bash
chmod +x wgtunnel/scripts/fetch-go.sh wgtunnel/scripts/go.sh
```

- [ ] **Step 3: Prototyp-Tests mit der gepinnten Toolchain laufen lassen**

Run: `wgtunnel/scripts/go.sh version && wgtunnel/scripts/go.sh test -count=1 ./...`
Expected: beim ersten Lauf `fetch-go: lade https://go.dev/dl/go1.27.2.darwin-arm64.tar.gz` und `…/go.tar.gz: OK` (SHA-256-Prüfung), dann `go version go1.27.2 darwin/arm64` und `ok  wgtunnel/wgconf`. Schlägt die SHA-Prüfung fehl, bricht das Skript ab – dann nicht den Hash ändern, sondern nachfragen.

- [ ] **Step 4: Failing test für die Zusammenfassung**

`wgtunnel/wgconf/summary_test.go`:
```go
package wgconf

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestSummaryHasNoKeysAndEmptyListsAreArrays(t *testing.T) {
	c, err := Parse(unifiExport)
	if err != nil {
		t.Fatal(err)
	}
	s := c.Summary()
	if s.Endpoint != "home.example.org:51820" {
		t.Errorf("endpoint %q", s.Endpoint)
	}
	if len(s.AllowedIPs) != 2 || s.AllowedIPs[0] != "0.0.0.0/0" || s.Addresses[0] != "192.168.3.2/32" || s.DNS[0] != "192.168.3.1" {
		t.Errorf("summary %+v", s)
	}
	b, _ := json.Marshal(s)
	for _, k := range []string{k1, k2, k3} {
		if strings.Contains(string(b), k) {
			t.Fatalf("summary leaks a key: %s", b)
		}
	}
	if !strings.Contains(string(b), `"warnings":[]`) {
		t.Errorf("empty warnings must encode as [], got %s", b)
	}
}
```

- [ ] **Step 5: Test laufen lassen**

Run: `wgtunnel/scripts/go.sh test ./wgconf`
Expected: FAIL – `c.Summary undefined (type *Config has no field or method Summary)`.

- [ ] **Step 6: Zusammenfassung implementieren**

`wgtunnel/wgconf/summary.go`:
```go
package wgconf

// Summary is the non-secret part of a config: what the app shows and stores
// outside the keychain. It never contains a key.
type Summary struct {
	Endpoint   string   `json:"endpoint"`
	Addresses  []string `json:"addresses"`
	AllowedIPs []string `json:"allowedIPs"`
	DNS        []string `json:"dns"`
	Warnings   []string `json:"warnings"`
}

func (c *Config) Summary() Summary {
	s := Summary{Addresses: []string{}, AllowedIPs: []string{}, DNS: []string{}, Warnings: []string{}}
	if len(c.Peers) > 0 {
		s.Endpoint = c.Peers[0].Endpoint()
	}
	for _, a := range c.Interface.Addresses {
		s.Addresses = append(s.Addresses, a.String())
	}
	for _, p := range c.Peers {
		for _, a := range p.AllowedIPs {
			s.AllowedIPs = append(s.AllowedIPs, a.String())
		}
	}
	for _, d := range c.Interface.DNS {
		s.DNS = append(s.DNS, d.String())
	}
	s.Warnings = append(s.Warnings, c.Warnings...)
	return s
}
```

- [ ] **Step 7: Tests, vet, gofmt**

Run: `wgtunnel/scripts/go.sh vet ./... && wgtunnel/scripts/go.sh test -count=1 ./... && "$(wgtunnel/scripts/fetch-go.sh)/bin/gofmt" -l wgtunnel/tunnel wgtunnel/wgconf wgtunnel/capi wgtunnel/cmd`
Expected: `ok  wgtunnel/wgconf`, keine gofmt-Ausgabe. `git status --short` zeigt keine Datei unter `wgtunnel/.toolchain`.

- [ ] **Step 8: Commit**

```bash
git add .gitignore wgtunnel/go.mod wgtunnel/go.sum wgtunnel/wgconf wgtunnel/tunnel wgtunnel/capi wgtunnel/cmd wgtunnel/scripts/fetch-go.sh wgtunnel/scripts/go.sh
git diff --cached --name-only | grep AppConfig   # Erwartet: leer
git commit -m "feat(tunnel): Go module from the WireGuard prototype with pinned go1.27.2" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Tunnel – idempotente Weiterleitungen, Neuaufbau, Rebind, C-API

**Files:**
- Modify (ersetzen): `wgtunnel/tunnel/tunnel.go`; Test: `wgtunnel/tunnel/tunnel_test.go`
- Modify (ersetzen): `wgtunnel/capi/capi.go`
- Create: `wgtunnel/include/wgtunnel.h`, `wgtunnel/include/module.modulemap`

**Interfaces:**
- Consumes: `wgconf.Parse`, `(*Config).Summary()`, `(*Config).UAPI`, `MTUOrDefault` (Task 1).
- Produces (Go): `const tunnel.DefaultKeepalive = 25`, `var tunnel.Resolver func(string) (netip.Addr, error)`, `(*Tunnel).AddForward(localPort int, host string, port int) (int, error)` (gleiches Ziel → gleicher Port), `(*Tunnel).AddUDPForward(...)` (ebenso), `(*Tunnel).ResetConnections() int`, `(*Tunnel).Rebind() error`, `Status()` mit `Peers` nie `nil`.
- Produces (C, Header `wgtunnel.h`, Modul `WGTunnelC`): `char *WgParse(const char *config)` (`{"ok":true,"summary":{…}}` | `{"ok":false,"error":"…"}`), `char *WgStart(const char *config)` (NULL = ok), `void WgStop(void)`, `int WgAddForward(int localPort, const char *remoteHost, int remotePort)`, `int WgAddUDPForward(int, const char *, int)` (Port oder −1), `int WgResetConnections(void)`, `char *WgRebind(void)` (NULL = ok), `char *WgStatus(void)` (`{"up":false}` gestoppt), `char *WgLastError(void)`, `void WgFree(char *)`.

Hintergrund „120-s-Problem“: Im Prototyp blieb eine TCP-Verbindung nach 120 s Funkstille dauerhaft bei 0 Mbit/s hängen, obwohl der Tunnel wieder lief (`run/reader.txt`). Die Lösung ist zweiteilig: Go schließt auf Anforderung alle durchgereichten Verbindungen, die lokalen Ports bleiben (`ResetConnections`); die App erkennt Ausfall und Wiederkehr (Task 4/7) und baut dann WebSocket und Streams neu auf. `PersistentKeepalive` fehlt in vielen Exporten – ohne Keepalive verfällt das NAT-Mapping unterwegs; Standard daher 25 s.

- [ ] **Step 1: Failing tests**

`wgtunnel/tunnel/tunnel_test.go`:
```go
package tunnel

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"io"
	"net"
	"net/netip"
	"strconv"
	"strings"
	"testing"
	"time"

	"golang.org/x/crypto/curve25519"
	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun/netstack"
)

var consoleIP = netip.MustParseAddr("192.168.1.1")

func keypair(t *testing.T) (priv, pub [32]byte) {
	t.Helper()
	if _, err := rand.Read(priv[:]); err != nil {
		t.Fatal(err)
	}
	priv[0] &= 248
	priv[31] = (priv[31] & 127) | 64
	p, err := curve25519.X25519(priv[:], curve25519.Basepoint)
	if err != nil {
		t.Fatal(err)
	}
	copy(pub[:], p)
	return
}

func b64(k [32]byte) string { return base64.StdEncoding.EncodeToString(k[:]) }

// startHome brings up the "home" side: a WireGuard peer on 127.0.0.1 whose LAN
// (console 192.168.1.1) exists only inside its own netstack. Port 7448 echoes,
// port 7447 streams bytes endlessly. Returns a client config for the app side.
func startHome(t *testing.T, keepalive string) string {
	t.Helper()
	hPriv, hPub := keypair(t)
	aPriv, aPub := keypair(t)
	tdev, tnet, err := netstack.CreateNetTUN([]netip.Addr{consoleIP}, nil, 1420)
	if err != nil {
		t.Fatal(err)
	}
	dev := device.NewDevice(tdev, conn.NewDefaultBind(), device.NewLogger(device.LogLevelSilent, ""))
	uapi := fmt.Sprintf("private_key=%s\nlisten_port=0\npublic_key=%s\nallowed_ip=192.168.2.2/32\n",
		hex.EncodeToString(hPriv[:]), hex.EncodeToString(aPub[:]))
	if err := dev.IpcSet(uapi); err != nil {
		t.Fatal(err)
	}
	if err := dev.Up(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(dev.Close)
	raw, err := dev.IpcGet()
	if err != nil {
		t.Fatal(err)
	}
	port := 0
	for _, line := range strings.Split(raw, "\n") {
		if v, ok := strings.CutPrefix(line, "listen_port="); ok {
			port, _ = strconv.Atoi(v)
		}
	}
	if port == 0 {
		t.Fatalf("no listen port in %q", raw)
	}

	echo, err := tnet.ListenTCP(&net.TCPAddr{IP: consoleIP.AsSlice(), Port: 7448})
	if err != nil {
		t.Fatal(err)
	}
	go func() {
		for {
			c, err := echo.Accept()
			if err != nil {
				return
			}
			go func() { defer c.Close(); io.Copy(c, c) }()
		}
	}()
	stream, err := tnet.ListenTCP(&net.TCPAddr{IP: consoleIP.AsSlice(), Port: 7447})
	if err != nil {
		t.Fatal(err)
	}
	go func() {
		buf := make([]byte, 16*1024)
		for {
			c, err := stream.Accept()
			if err != nil {
				return
			}
			go func() {
				defer c.Close()
				for {
					if _, err := c.Write(buf); err != nil {
						return
					}
				}
			}()
		}
	}()
	t.Cleanup(func() { echo.Close(); stream.Close() })

	return fmt.Sprintf("[Interface]\nPrivateKey = %s\nAddress = 192.168.2.2/32\n\n[Peer]\nPublicKey = %s\nAllowedIPs = 192.168.1.0/24\nEndpoint = 127.0.0.1:%d\n%s",
		b64(aPriv), b64(hPub), port, keepalive)
}

func startApp(t *testing.T, cfg string) *Tunnel {
	t.Helper()
	tun, err := Start(cfg, device.LogLevelSilent)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(tun.Close)
	return tun
}

func echoOnce(t *testing.T, port int) {
	t.Helper()
	c, err := net.DialTimeout("tcp", "127.0.0.1:"+strconv.Itoa(port), 5*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	c.SetDeadline(time.Now().Add(10 * time.Second))
	if _, err := c.Write([]byte("ping")); err != nil {
		t.Fatal(err)
	}
	got := make([]byte, 4)
	if _, err := io.ReadFull(c, got); err != nil {
		t.Fatal(err)
	}
	if string(got) != "ping" {
		t.Fatalf("echo %q", got)
	}
}

func TestForwardIsIdempotentPerRemote(t *testing.T) {
	tun := startApp(t, startHome(t, ""))
	p1, err := tun.AddForward(0, "192.168.1.1", 7448)
	if err != nil {
		t.Fatal(err)
	}
	p2, err := tun.AddForward(0, "192.168.1.1", 7448)
	if err != nil {
		t.Fatal(err)
	}
	if p1 != p2 {
		t.Fatalf("second AddForward bound a new port: %d vs %d", p1, p2)
	}
	p3, err := tun.AddForward(0, "192.168.1.1", 7447)
	if err != nil {
		t.Fatal(err)
	}
	if p3 == p1 {
		t.Fatal("different remote must get its own port")
	}
	echoOnce(t, p1)
}

func TestDefaultKeepaliveWhenConfigHasNone(t *testing.T) {
	tun := startApp(t, startHome(t, ""))
	st, err := tun.Status()
	if err != nil {
		t.Fatal(err)
	}
	if len(st.Peers) != 1 || st.Peers[0].KeepaliveSecs != DefaultKeepalive {
		t.Fatalf("keepalive %+v", st.Peers)
	}
}

func TestExplicitKeepaliveIsKept(t *testing.T) {
	tun := startApp(t, startHome(t, "PersistentKeepalive = 10\n"))
	st, _ := tun.Status()
	if st.Peers[0].KeepaliveSecs != 10 {
		t.Fatalf("keepalive %d", st.Peers[0].KeepaliveSecs)
	}
}

func TestResetConnectionsClosesRelaysButKeepsPort(t *testing.T) {
	tun := startApp(t, startHome(t, ""))
	port, err := tun.AddForward(0, "192.168.1.1", 7447)
	if err != nil {
		t.Fatal(err)
	}
	c, err := net.DialTimeout("tcp", "127.0.0.1:"+strconv.Itoa(port), 5*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	c.SetReadDeadline(time.Now().Add(10 * time.Second))
	buf := make([]byte, 4096)
	if _, err := io.ReadFull(c, buf); err != nil {
		t.Fatalf("stream before reset: %v", err)
	}
	if n := tun.ResetConnections(); n != 1 {
		t.Fatalf("closed %d relays, want 1", n)
	}
	// The local side must end promptly (EOF or reset), not hang.
	c.SetReadDeadline(time.Now().Add(3 * time.Second))
	for {
		if _, err := c.Read(buf); err != nil {
			if ne, ok := err.(net.Error); ok && ne.Timeout() {
				t.Fatal("local connection still open after ResetConnections")
			}
			break
		}
	}
	// Same port works again.
	c2, err := net.DialTimeout("tcp", "127.0.0.1:"+strconv.Itoa(port), 5*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer c2.Close()
	c2.SetReadDeadline(time.Now().Add(10 * time.Second))
	if _, err := io.ReadFull(c2, buf); err != nil {
		t.Fatalf("stream after reset: %v", err)
	}
}

func TestRebindKeepsTunnelWorking(t *testing.T) {
	tun := startApp(t, startHome(t, ""))
	port, err := tun.AddForward(0, "192.168.1.1", 7448)
	if err != nil {
		t.Fatal(err)
	}
	echoOnce(t, port)
	if err := tun.Rebind(); err != nil {
		t.Fatal(err)
	}
	echoOnce(t, port)
}

func TestForwardAfterCloseFails(t *testing.T) {
	tun := startApp(t, startHome(t, ""))
	tun.Close()
	if _, err := tun.AddForward(0, "192.168.1.1", 7448); err == nil {
		t.Fatal("AddForward on a closed tunnel must fail")
	}
}
```

- [ ] **Step 2: Tests laufen lassen**

Run: `wgtunnel/scripts/go.sh test ./tunnel`
Expected: FAIL beim Kompilieren – `undefined: DefaultKeepalive`, `tun.ResetConnections undefined`, `tun.Rebind undefined`.

- [ ] **Step 3: `tunnel.go` ersetzen**

`wgtunnel/tunnel/tunnel.go` (komplett):
```go
// Package tunnel runs a userspace WireGuard peer (wireguard-go + gVisor netstack)
// that is visible only to this process, and exposes local TCP/UDP port forwards
// on 127.0.0.1 so other code (URLSession, libVLC) can reach hosts behind it.
package tunnel

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/netip"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun/netstack"

	"wgtunnel/wgconf"
)

// DefaultKeepalive is used for peers whose config has no PersistentKeepalive.
// The app sits behind NAT on foreign networks; without keepalives the mapping
// expires and an idle tunnel only notices that on the next request.
const DefaultKeepalive = 25

type Tunnel struct {
	Config *wgconf.Config
	Net    *netstack.Net
	dev    *device.Device

	mu        sync.Mutex
	listeners []io.Closer
	byRemote  map[string]int      // "tcp/host:port" or "udp/ip:port" -> local port
	active    map[*relay]struct{} // relayed TCP connections currently open
	closed    bool

	FwdConns   atomic.Int64
	FwdBytesUp atomic.Int64 // local -> remote
	FwdBytesDn atomic.Int64 // remote -> local
}

// relay is one accepted local connection and its tunnel-side counterpart.
type relay struct {
	local, remote net.Conn
}

func (r *relay) close() {
	r.local.Close()
	r.remote.Close()
}

// Resolver maps an endpoint host name to an IP (outside the tunnel).
var Resolver = func(host string) (netip.Addr, error) {
	ips, err := net.DefaultResolver.LookupNetIP(context.Background(), "ip", host)
	if err != nil {
		return netip.Addr{}, err
	}
	for _, ip := range ips { // prefer IPv4
		if ip.Unmap().Is4() {
			return ip.Unmap(), nil
		}
	}
	if len(ips) == 0 {
		return netip.Addr{}, errors.New("keine Adresse")
	}
	return ips[0], nil
}

// Start parses a wg-quick config and brings the userspace device up.
// logLevel: device.LogLevelSilent / Error / Verbose.
func Start(configText string, logLevel int) (*Tunnel, error) {
	cfg, err := wgconf.Parse(configText)
	if err != nil {
		return nil, err
	}
	return StartConfig(cfg, logLevel)
}

func StartConfig(cfg *wgconf.Config, logLevel int) (*Tunnel, error) {
	for i := range cfg.Peers {
		if cfg.Peers[i].PersistentKeepalive == 0 {
			cfg.Peers[i].PersistentKeepalive = DefaultKeepalive
		}
	}
	var local []netip.Addr
	for _, p := range cfg.Interface.Addresses {
		local = append(local, p.Addr())
	}
	tdev, tnet, err := netstack.CreateNetTUN(local, cfg.Interface.DNS, cfg.MTUOrDefault())
	if err != nil {
		return nil, fmt.Errorf("netstack: %w", err)
	}
	dev := device.NewDevice(tdev, conn.NewDefaultBind(), device.NewLogger(logLevel, "wg: "))
	uapi, err := cfg.UAPI(Resolver)
	if err != nil {
		dev.Close()
		return nil, err
	}
	if err := dev.IpcSet(uapi); err != nil {
		dev.Close()
		return nil, fmt.Errorf("IpcSet: %w", err)
	}
	if err := dev.Up(); err != nil {
		dev.Close()
		return nil, fmt.Errorf("Up: %w", err)
	}
	return &Tunnel{
		Config: cfg, Net: tnet, dev: dev,
		byRemote: map[string]int{}, active: map[*relay]struct{}{},
	}, nil
}

func (t *Tunnel) Close() {
	t.mu.Lock()
	if t.closed {
		t.mu.Unlock()
		return
	}
	t.closed = true
	ls := t.listeners
	t.listeners = nil
	rs := t.active
	t.active = map[*relay]struct{}{}
	t.mu.Unlock()
	for _, c := range ls {
		c.Close()
	}
	for r := range rs {
		r.close()
	}
	t.dev.Close()
}

// DialContext dials through the tunnel.
func (t *Tunnel) DialContext(ctx context.Context, network, addr string) (net.Conn, error) {
	return t.Net.DialContext(ctx, network, addr)
}

// lookup returns the existing local port for key, or registers the listeners
// produced by open. Holding mu across open keeps two callers from binding twice.
func (t *Tunnel) lookup(key string, open func() (int, []io.Closer, error)) (int, error) {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.closed {
		return 0, errors.New("Tunnel geschlossen")
	}
	if p, ok := t.byRemote[key]; ok {
		return p, nil
	}
	p, cs, err := open()
	if err != nil {
		return 0, err
	}
	t.byRemote[key] = p
	t.listeners = append(t.listeners, cs...)
	return p, nil
}

// AddForward listens on 127.0.0.1:localPort (0 = ephemeral) with a normal macOS
// socket and relays every accepted connection to remoteHost:remotePort via the tunnel.
// Asking again for the same remote returns the port bound the first time.
func (t *Tunnel) AddForward(localPort int, remoteHost string, remotePort int) (int, error) {
	remote := net.JoinHostPort(remoteHost, strconv.Itoa(remotePort))
	return t.lookup("tcp/"+remote, func() (int, []io.Closer, error) {
		ln, err := net.Listen("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(localPort)))
		if err != nil {
			return 0, nil, err
		}
		go func() {
			for {
				c, err := ln.Accept()
				if err != nil {
					return
				}
				go t.relayTCP(c, remote)
			}
		}()
		return ln.Addr().(*net.TCPAddr).Port, []io.Closer{ln}, nil
	})
}

func (t *Tunnel) track(r *relay) bool {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.closed {
		return false
	}
	t.active[r] = struct{}{}
	return true
}

func (t *Tunnel) untrack(r *relay) {
	t.mu.Lock()
	delete(t.active, r)
	t.mu.Unlock()
}

func (t *Tunnel) relayTCP(local net.Conn, remote string) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	rc, err := t.Net.DialContext(ctx, "tcp", remote)
	cancel()
	if err != nil {
		log.Printf("forward %s: %v", remote, err)
		local.Close()
		return
	}
	r := &relay{local: local, remote: rc}
	if !t.track(r) {
		r.close()
		return
	}
	defer t.untrack(r)
	defer r.close()
	t.FwdConns.Add(1)
	done := make(chan struct{}, 2)
	go func() {
		n, _ := io.Copy(rc, local)
		t.FwdBytesUp.Add(n)
		if cw, ok := rc.(interface{ CloseWrite() error }); ok {
			cw.CloseWrite()
		}
		done <- struct{}{}
	}()
	go func() {
		n, _ := io.Copy(local, rc)
		t.FwdBytesDn.Add(n)
		if cw, ok := local.(*net.TCPConn); ok {
			cw.CloseWrite()
		}
		done <- struct{}{}
	}()
	<-done
	<-done
}

// ResetConnections closes every relayed TCP connection but keeps the listeners,
// so clients reconnect to the same 127.0.0.1 ports. Needed after an outage:
// a gVisor TCP connection that lived through a long blackout can stay stuck
// forever although the tunnel itself works again. Returns how many were closed.
func (t *Tunnel) ResetConnections() int {
	t.mu.Lock()
	rs := t.active
	t.active = map[*relay]struct{}{}
	t.mu.Unlock()
	for r := range rs {
		r.close()
	}
	return len(rs)
}

// Rebind re-resolves endpoint host names and rebinds the UDP socket. Call after
// the Mac changed networks (new Wi-Fi, wake from sleep, hotspot).
func (t *Tunnel) Rebind() error {
	var b strings.Builder
	for _, p := range t.Config.Peers {
		addr, err := netip.ParseAddr(p.EndpointHost)
		if err != nil {
			addr, err = Resolver(p.EndpointHost)
			if err != nil {
				return fmt.Errorf("Endpoint %q nicht auflösbar: %v", p.EndpointHost, err)
			}
		}
		fmt.Fprintf(&b, "public_key=%s\nupdate_only=true\nendpoint=%s\n",
			p.PublicKey.Hex(), netip.AddrPortFrom(addr.Unmap(), p.EndpointPort))
	}
	if err := t.dev.IpcSet(b.String()); err != nil {
		return fmt.Errorf("IpcSet: %w", err)
	}
	return t.dev.BindUpdate()
}

// AddUDPForward listens on 127.0.0.1:localPort (UDP). Datagrams from the most
// recent local sender are relayed to remoteHost:remotePort through the tunnel;
// replies go back to that sender. Enough for talkback (one sender).
func (t *Tunnel) AddUDPForward(localPort int, remoteHost string, remotePort int) (int, error) {
	raddr, err := netip.ParseAddrPort(net.JoinHostPort(remoteHost, strconv.Itoa(remotePort)))
	if err != nil {
		return 0, fmt.Errorf("UDP-Ziel muss IP sein: %w", err)
	}
	return t.lookup("udp/"+raddr.String(), func() (int, []io.Closer, error) {
		lc, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: localPort})
		if err != nil {
			return 0, nil, err
		}
		rc, err := t.Net.DialUDPAddrPort(netip.AddrPort{}, raddr)
		if err != nil {
			lc.Close()
			return 0, nil, err
		}
		var peer atomic.Pointer[net.UDPAddr]
		go func() {
			buf := make([]byte, 65535)
			for {
				n, from, err := lc.ReadFromUDP(buf)
				if err != nil {
					return
				}
				peer.Store(from)
				rc.Write(buf[:n])
			}
		}()
		go func() {
			buf := make([]byte, 65535)
			for {
				n, err := rc.Read(buf)
				if err != nil {
					return
				}
				if p := peer.Load(); p != nil {
					lc.WriteToUDP(buf[:n], p)
				}
			}
		}()
		return lc.LocalAddr().(*net.UDPAddr).Port, []io.Closer{lc, rc}, nil
	})
}

type PeerStatus struct {
	PublicKey     string `json:"publicKey"`
	Endpoint      string `json:"endpoint"`
	LastHandshake int64  `json:"lastHandshakeUnix"`
	HandshakeAgeS int64  `json:"handshakeAgeSeconds"` // -1 = never
	RxBytes       int64  `json:"rxBytes"`
	TxBytes       int64  `json:"txBytes"`
	KeepaliveSecs int    `json:"keepaliveSeconds"`
}

type Status struct {
	Up           bool         `json:"up"`
	Peers        []PeerStatus `json:"peers"`
	FwdConns     int64        `json:"forwardConnections"`
	FwdBytesUp   int64        `json:"forwardBytesUp"`
	FwdBytesDown int64        `json:"forwardBytesDown"`
}

func (t *Tunnel) Status() (Status, error) {
	s := Status{Up: true, Peers: []PeerStatus{}, FwdConns: t.FwdConns.Load(), FwdBytesUp: t.FwdBytesUp.Load(), FwdBytesDown: t.FwdBytesDn.Load()}
	raw, err := t.dev.IpcGet()
	if err != nil {
		return s, err
	}
	var cur *PeerStatus
	var sec, nsec int64
	flush := func() {
		if cur != nil {
			cur.LastHandshake = sec
			cur.HandshakeAgeS = -1
			if sec > 0 {
				cur.HandshakeAgeS = int64(time.Since(time.Unix(sec, nsec)).Seconds())
			}
			s.Peers = append(s.Peers, *cur)
		}
	}
	for _, line := range strings.Split(raw, "\n") {
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		switch k {
		case "public_key":
			flush()
			cur, sec, nsec = &PeerStatus{PublicKey: v}, 0, 0
		case "endpoint":
			cur.Endpoint = v
		case "last_handshake_time_sec":
			sec, _ = strconv.ParseInt(v, 10, 64)
		case "last_handshake_time_nsec":
			nsec, _ = strconv.ParseInt(v, 10, 64)
		case "rx_bytes":
			cur.RxBytes, _ = strconv.ParseInt(v, 10, 64)
		case "tx_bytes":
			cur.TxBytes, _ = strconv.ParseInt(v, 10, 64)
		case "persistent_keepalive_interval":
			cur.KeepaliveSecs, _ = strconv.Atoi(v)
		}
	}
	flush()
	return s, nil
}
```

- [ ] **Step 4: Tests laufen lassen**

Run: `wgtunnel/scripts/go.sh test -count=1 -v ./tunnel 2>&1 | grep -E "^(=== RUN|--- |ok|FAIL)"`
Expected: sechs Tests `--- PASS` (`TestForwardIsIdempotentPerRemote`, `TestDefaultKeepaliveWhenConfigHasNone`, `TestExplicitKeepaliveIsKept`, `TestResetConnectionsClosesRelaysButKeepsPort`, `TestRebindKeepsTunnelWorking`, `TestForwardAfterCloseFails`), `ok  wgtunnel/tunnel`.

- [ ] **Step 5: C-API ersetzen, Header und Modul anlegen**

`wgtunnel/capi/capi.go` (komplett):
```go
// Package main is the C API exported via -buildmode=c-archive.
// The hand-written header wgtunnel/include/wgtunnel.h declares these functions
// for Swift; keep both in sync. All returned char* must be released with WgFree.
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"encoding/json"
	"errors"
	"sync"
	"unsafe"

	"golang.zx2c4.com/wireguard/device"

	"wgtunnel/tunnel"
	"wgtunnel/wgconf"
)

var (
	mu      sync.Mutex
	cur     *tunnel.Tunnel
	lastErr string
)

func setErr(err error) {
	if err != nil {
		lastErr = err.Error()
	} else {
		lastErr = ""
	}
}

func jsonString(v any) *C.char {
	b, _ := json.Marshal(v)
	return C.CString(string(b))
}

// WgParse validates a wg-quick config without starting anything.
// Returns {"ok":true,"summary":{...}} or {"ok":false,"error":"Zeile 3: ..."}.
//
//export WgParse
func WgParse(config *C.char) *C.char {
	cfg, err := wgconf.Parse(C.GoString(config))
	if err != nil {
		return jsonString(map[string]any{"ok": false, "error": err.Error()})
	}
	return jsonString(map[string]any{"ok": true, "summary": cfg.Summary()})
}

// WgStart parses a wg-quick config and starts the tunnel.
// Returns NULL on success, otherwise an error message.
//
//export WgStart
func WgStart(config *C.char) *C.char {
	mu.Lock()
	defer mu.Unlock()
	if cur != nil {
		return C.CString("Tunnel läuft bereits")
	}
	t, err := tunnel.Start(C.GoString(config), device.LogLevelError)
	setErr(err)
	if err != nil {
		return C.CString(err.Error())
	}
	cur = t
	return nil
}

//export WgStop
func WgStop() {
	mu.Lock()
	defer mu.Unlock()
	if cur != nil {
		cur.Close()
		cur = nil
	}
}

func withTunnel(f func(t *tunnel.Tunnel) (int, error)) C.int {
	mu.Lock()
	defer mu.Unlock()
	if cur == nil {
		setErr(errors.New("Tunnel nicht gestartet"))
		return -1
	}
	p, err := f(cur)
	setErr(err)
	if err != nil {
		return -1
	}
	return C.int(p)
}

// WgAddForward opens 127.0.0.1:localPort (0 = pick free port) -> remoteHost:remotePort (TCP).
// The same remote always gets the same port while the tunnel runs.
// Returns the bound local port or -1 (see WgLastError).
//
//export WgAddForward
func WgAddForward(localPort C.int, remoteHost *C.char, remotePort C.int) C.int {
	h := C.GoString(remoteHost)
	return withTunnel(func(t *tunnel.Tunnel) (int, error) { return t.AddForward(int(localPort), h, int(remotePort)) })
}

// WgAddUDPForward: same for UDP (remoteHost must be an IP literal).
//
//export WgAddUDPForward
func WgAddUDPForward(localPort C.int, remoteHost *C.char, remotePort C.int) C.int {
	h := C.GoString(remoteHost)
	return withTunnel(func(t *tunnel.Tunnel) (int, error) { return t.AddUDPForward(int(localPort), h, int(remotePort)) })
}

// WgResetConnections closes all relayed TCP connections (listeners stay).
// Returns the number closed, 0 when the tunnel is not running.
//
//export WgResetConnections
func WgResetConnections() C.int {
	mu.Lock()
	defer mu.Unlock()
	if cur == nil {
		return 0
	}
	return C.int(cur.ResetConnections())
}

// WgRebind re-resolves endpoints and rebinds the UDP socket after a network change.
// Returns NULL on success, otherwise an error message.
//
//export WgRebind
func WgRebind() *C.char {
	mu.Lock()
	t := cur
	mu.Unlock()
	if t == nil {
		return C.CString("Tunnel nicht gestartet")
	}
	// Outside the lock: the DNS lookup may take seconds, forwards must not wait for it.
	if err := t.Rebind(); err != nil {
		return C.CString(err.Error())
	}
	return nil
}

// WgStatus returns a JSON document ({"up":false} when stopped).
//
//export WgStatus
func WgStatus() *C.char {
	mu.Lock()
	defer mu.Unlock()
	if cur == nil {
		return C.CString(`{"up":false}`)
	}
	st, err := cur.Status()
	if err != nil {
		return jsonString(map[string]any{"up": true, "error": err.Error()})
	}
	return jsonString(st)
}

//export WgLastError
func WgLastError() *C.char {
	mu.Lock()
	defer mu.Unlock()
	if lastErr == "" {
		return nil
	}
	return C.CString(lastErr)
}

//export WgFree
func WgFree(p *C.char) { C.free(unsafe.Pointer(p)) }

func main() {}
```

`wgtunnel/include/wgtunnel.h` (handgeschrieben, damit Swift auch ohne gebautes Archiv kompiliert; `const char *` statt cgo-`char *` – ABI-gleich, Swift übergibt dann `String` direkt):
```c
// C API of the Go c-archive built from wgtunnel/capi (see capi.go).
// Hand-written so Swift compiles before the archive exists; keep in sync with capi.go.
// Every returned char* is owned by the caller and must be released with WgFree.
#ifndef WGTUNNEL_H
#define WGTUNNEL_H

#ifdef __cplusplus
extern "C" {
#endif

/// {"ok":true,"summary":{...}} or {"ok":false,"error":"..."}.
char *WgParse(const char *config);
/// NULL on success, otherwise an error message.
char *WgStart(const char *config);
void WgStop(void);
/// Local port on 127.0.0.1, or -1 (see WgLastError). Same remote -> same port.
int WgAddForward(int localPort, const char *remoteHost, int remotePort);
int WgAddUDPForward(int localPort, const char *remoteHost, int remotePort);
/// Number of relayed TCP connections closed (listeners stay open).
int WgResetConnections(void);
/// NULL on success, otherwise an error message.
char *WgRebind(void);
/// JSON status, {"up":false} when stopped.
char *WgStatus(void);
/// Last error of WgAddForward/WgAddUDPForward, or NULL.
char *WgLastError(void);
void WgFree(char *p);

#ifdef __cplusplus
}
#endif

#endif
```

`wgtunnel/include/module.modulemap`:
```
module WGTunnelC {
    header "wgtunnel.h"
    export *
}
```

- [ ] **Step 6: c-archive bauen, Exporte gegen den Header prüfen**

```bash
OUT="${TMPDIR:-/tmp}/wgcheck"; mkdir -p "$OUT"
wgtunnel/scripts/go.sh CGO_ENABLED=1 build -buildmode=c-archive -o "$OUT/libwgtunnel.a" ./capi
grep -o 'extern [^;]*Wg[A-Za-z]*(' "$OUT/libwgtunnel.h" | sed 's/.* \**\(Wg[A-Za-z]*\)(/\1/' | sort > "$OUT/go.txt"
grep -o 'Wg[A-Za-z]*(' wgtunnel/include/wgtunnel.h | tr -d '(' | sort > "$OUT/h.txt"
diff "$OUT/go.txt" "$OUT/h.txt" && echo "Header vollständig"
```
Expected: `Header vollständig` (zehn Funktionen: WgAddForward, WgAddUDPForward, WgFree, WgLastError, WgParse, WgRebind, WgResetConnections, WgStart, WgStatus, WgStop).

- [ ] **Step 7: vet, alle Tests, gofmt**

Run: `wgtunnel/scripts/go.sh vet ./... && wgtunnel/scripts/go.sh test -count=1 ./... && "$(wgtunnel/scripts/fetch-go.sh)/bin/gofmt" -l wgtunnel/tunnel wgtunnel/wgconf wgtunnel/capi wgtunnel/cmd`
Expected: `ok` für `tunnel` und `wgconf`, keine gofmt-Ausgabe.

- [ ] **Step 8: Commit**

```bash
git add wgtunnel/tunnel wgtunnel/capi wgtunnel/include
git diff --cached --name-only | grep AppConfig   # Erwartet: leer
git commit -m "feat(tunnel): idempotent forwards, connection reset, rebind and C API" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Universal-Archiv, Lizenztexte, Swift-Ende-zu-Ende über Loopback

**Files:**
- Create: `wgtunnel/scripts/build-archive.sh`, `wgtunnel/scripts/collect-notices.sh`, `wgtunnel/scripts/smoke.sh`, `wgtunnel/smoke/main.swift`
- Create (generiert): `UniFiCameraPopup/ThirdPartyNotices.txt`

**Interfaces:**
- Consumes: C-API, Header, Modul (Task 2); `cmd/home` (Prototyp: Heimat mit Konsole 192.168.1.1, HTTPS 443 mit selbst signiertem Zertifikat, 2 Kameras unter `/proxy/protect/integration/v1/cameras`).
- Produces: `wgtunnel/build/libwgtunnel.a` (arm64 + x86_64, macOS ≥ 13.0), Aufruf `"$PROJECT_DIR/../wgtunnel/scripts/build-archive.sh"` für die Xcode-Build-Phase (Task 6), `UniFiCameraPopup/ThirdPartyNotices.txt` (Task 6 Ressource, Task 9 Anzeige).

- [ ] **Step 1: Smoke-Test zuerst**

`wgtunnel/smoke/main.swift`:
```swift
// End-to-end check of the C API as the app uses it: start the tunnel against the
// fake home (cmd/home), reach the "console" through a local forward with URLSession,
// reset and rebind, stop. Run via wgtunnel/scripts/smoke.sh.
import Foundation
import WGTunnelC

func take(_ p: UnsafeMutablePointer<CChar>?) -> String? {
    guard let p else { return nil }
    defer { WgFree(p) }
    return String(cString: p)
}

func check(_ ok: Bool, _ what: String) {
    print(ok ? "ok    \(what)" : "FAIL  \(what)")
    if !ok { exit(1) }
}

/// The fake home uses a throwaway self-signed certificate; the app pins instead.
final class TrustAll: NSObject, URLSessionDelegate {
    func urlSession(_ s: URLSession, didReceive c: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let t = c.protectionSpace.serverTrust { completionHandler(.useCredential, URLCredential(trust: t)) }
        else { completionHandler(.performDefaultHandling, nil) }
    }
}

let path = CommandLine.arguments[1]
let config = try! String(contentsOfFile: path, encoding: .utf8)

check(take(WgParse("kaputt"))?.contains("\"ok\":false") == true, "WgParse lehnt Unsinn ab")
check(take(WgParse(config))?.contains("\"ok\":true") == true, "WgParse akzeptiert die Home-Konfiguration")
check(take(WgStart(config)) == nil, "WgStart")
let port = WgAddForward(0, "192.168.1.1", 443)
check(port > 0, "WgAddForward -> 127.0.0.1:\(port)")
check(WgAddForward(0, "192.168.1.1", 443) == port, "gleiches Ziel, gleicher Port")

var request = URLRequest(url: URL(string: "https://127.0.0.1:\(port)/proxy/protect/integration/v1/cameras")!)
request.setValue("test", forHTTPHeaderField: "X-API-KEY")
let session = URLSession(configuration: .ephemeral, delegate: TrustAll(), delegateQueue: nil)
let done = DispatchSemaphore(value: 0)
var cameras = -1
session.dataTask(with: request) { data, response, _ in
    if (response as? HTTPURLResponse)?.statusCode == 200,
       let list = (try? JSONSerialization.jsonObject(with: data ?? Data())) as? [[String: Any]] {
        cameras = list.count
    }
    done.signal()
}.resume()
_ = done.wait(timeout: .now() + 15)
check(cameras == 2, "HTTPS über den Tunnel: \(cameras) Kameras")

let status = take(WgStatus()) ?? ""
check(status.contains("\"up\":true") && !status.contains("\"lastHandshakeUnix\":0"), "Handshake im Status")
check(WgResetConnections() >= 0, "WgResetConnections")
check(take(WgRebind()) == nil, "WgRebind")
WgStop()
check(take(WgStatus()) == "{\"up\":false}", "WgStop")
print("SMOKE OK")
```

`wgtunnel/scripts/smoke.sh`:
```bash
#!/bin/bash
# Loopback end-to-end check of libwgtunnel.a from Swift – no app, no real network:
# builds the archive, starts the fake home (cmd/home), runs smoke/main.swift against it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"${ROOT}/scripts/build-archive.sh" >/dev/null
WORK="$(mktemp -d "${TMPDIR:-/tmp}/wgsmoke.XXXXXX")"
HOME_PID=""
cleanup() {
  if [[ -n "${HOME_PID}" ]]; then
    kill "${HOME_PID}" 2>/dev/null || true
    wait "${HOME_PID}" 2>/dev/null || true
  fi
  rm -rf "${WORK}"
}
trap cleanup EXIT

"${ROOT}/scripts/go.sh" build -o "${WORK}/home" ./cmd/home
PORT=$((40000 + RANDOM % 20000))
"${WORK}/home" -port "${PORT}" -out "${WORK}/app.conf" > "${WORK}/home.log" 2>&1 &
HOME_PID=$!
for _ in $(seq 1 50); do
  [[ -s "${WORK}/app.conf" ]] && break
  sleep 0.1
done

xcrun swiftc -O -I "${ROOT}/include" "${ROOT}/smoke/main.swift" "${ROOT}/build/libwgtunnel.a" \
  -lresolv -framework Security -framework CoreFoundation -o "${WORK}/smoke"
"${WORK}/smoke" "${WORK}/app.conf"
```

- [ ] **Step 2: Smoke laufen lassen**

Run: `chmod +x wgtunnel/scripts/smoke.sh && wgtunnel/scripts/smoke.sh`
Expected: FAIL – `wgtunnel/scripts/build-archive.sh: No such file or directory`.

- [ ] **Step 3: Archiv-Skript**

`wgtunnel/scripts/build-archive.sh`:
```bash
#!/bin/bash
# Builds wgtunnel/build/libwgtunnel.a as a universal (arm64 + x86_64) static
# library from the Go c-archive in wgtunnel/capi. Called by the Xcode build phase
# "Build WireGuard tunnel" (and so by build-release.sh). Skips the build when the
# archive is newer than every Go source, go.mod, go.sum and the build scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${ROOT}/build"
LIB="${OUT}/libwgtunnel.a"

if [[ -f "${LIB}" ]]; then
  NEWER="$(find "${ROOT}" \( -path "${ROOT}/.toolchain" -o -path "${ROOT}/build" \) -prune -o \
    \( -name '*.go' -o -name 'go.mod' -o -name 'go.sum' -o -name '*.sh' \) -newer "${LIB}" -print -quit)"
  if [[ -z "${NEWER}" ]]; then
    echo "build-archive: ${LIB} ist aktuell"
    exit 0
  fi
fi

SDK="$(xcrun --sdk macosx --show-sdk-path)"
CLANG="$(xcrun --sdk macosx -f clang)"
MIN="13.0"

mkdir -p "${OUT}"
for GOARCH in arm64 amd64; do
  if [[ "${GOARCH}" == "amd64" ]]; then CARCH="x86_64"; else CARCH="arm64"; fi
  echo "build-archive: baue ${GOARCH}"
  "${ROOT}/scripts/go.sh" \
    GOOS=darwin GOARCH="${GOARCH}" CGO_ENABLED=1 \
    CC="${CLANG} -arch ${CARCH}" \
    CGO_CFLAGS="-isysroot ${SDK} -mmacosx-version-min=${MIN} -O2" \
    CGO_LDFLAGS="-isysroot ${SDK} -mmacosx-version-min=${MIN}" \
    MACOSX_DEPLOYMENT_TARGET="${MIN}" \
    build -trimpath -buildmode=c-archive -o "${OUT}/${GOARCH}/libwgtunnel.a" ./capi
done

lipo -create -output "${LIB}.tmp" "${OUT}/arm64/libwgtunnel.a" "${OUT}/amd64/libwgtunnel.a"
mv "${LIB}.tmp" "${LIB}"
lipo -info "${LIB}"
```

Run: `chmod +x wgtunnel/scripts/build-archive.sh && wgtunnel/scripts/build-archive.sh && wgtunnel/scripts/build-archive.sh`
Expected: erster Lauf `build-archive: baue arm64`, `build-archive: baue amd64`, `Architectures in the fat file: …/libwgtunnel.a are: x86_64 arm64`; zweiter Lauf `build-archive: …/libwgtunnel.a ist aktuell`.

- [ ] **Step 4: Smoke erneut**

Run: `wgtunnel/scripts/smoke.sh`
Expected:
```
ok    WgParse lehnt Unsinn ab
ok    WgParse akzeptiert die Home-Konfiguration
ok    WgStart
ok    WgAddForward -> 127.0.0.1:<port>
ok    gleiches Ziel, gleicher Port
ok    HTTPS über den Tunnel: 2 Kameras
ok    Handshake im Status
ok    WgResetConnections
ok    WgRebind
ok    WgStop
SMOKE OK
```

- [ ] **Step 5: Lizenztexte erzeugen**

`wgtunnel/scripts/collect-notices.sh`:
```bash
#!/bin/bash
# Writes UniFiCameraPopup/ThirdPartyNotices.txt: license texts of the Go runtime and
# of every module linked into libwgtunnel.a (shown in Hilfe › „Über“).
# Re-run after every change to go.mod and commit the result.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${ROOT}/../UniFiCameraPopup/ThirdPartyNotices.txt"
GOROOT_DIR="$("${ROOT}/scripts/fetch-go.sh")"
GO="${ROOT}/scripts/go.sh"

"${GO}" mod download
{
  echo "Camera Popup – Software von Dritten im WireGuard-Tunnel"
  echo "========================================================"
  echo
  echo "--- Go $("${GO}" env GOVERSION) (Laufzeit und Standardbibliothek) ---"
  echo
  cat "${GOROOT_DIR}/LICENSE"
  "${GO}" GOOS=darwin CGO_ENABLED=1 list -deps \
    -f '{{if and .Module (not .Module.Main)}}{{.Module.Path}}	{{.Module.Version}}	{{.Module.Dir}}{{end}}' ./capi \
    | sort -u | while IFS=$'\t' read -r path version dir; do
      echo
      echo "--- ${path} ${version} ---"
      echo
      cat "${dir}/LICENSE"
      for extra in NOTICE AUTHORS; do
        if [[ -f "${dir}/${extra}" ]]; then
          echo
          cat "${dir}/${extra}"
        fi
      done
    done
} > "${OUT}"
echo "collect-notices: ${OUT}"
```

Run: `chmod +x wgtunnel/scripts/collect-notices.sh && wgtunnel/scripts/collect-notices.sh && grep "^--- " UniFiCameraPopup/ThirdPartyNotices.txt`
Expected (acht Abschnitte):
```
--- Go go1.27.2 (Laufzeit und Standardbibliothek) ---
--- github.com/google/btree v1.1.2 ---
--- golang.org/x/crypto v0.37.0 ---
--- golang.org/x/net v0.39.0 ---
--- golang.org/x/sys v0.32.0 ---
--- golang.org/x/time v0.7.0 ---
--- golang.zx2c4.com/wireguard v0.0.0-20261006164505-2631ce99a06f ---
--- gvisor.dev/gvisor v0.0.0-20250503011706-39ed1f5ac29c ---
```
Stichprobe: `grep -c "Permission is hereby granted" UniFiCameraPopup/ThirdPartyNotices.txt` ≥ 1 (MIT, wireguard-go), `grep -c "Apache License" …` ≥ 2 (gVisor, btree).

- [ ] **Step 6: Commit**

```bash
git add wgtunnel/scripts/build-archive.sh wgtunnel/scripts/collect-notices.sh wgtunnel/scripts/smoke.sh wgtunnel/smoke/main.swift UniFiCameraPopup/ThirdPartyNotices.txt
git diff --cached --name-only | grep AppConfig   # Erwartet: leer
git commit -m "feat(tunnel): universal c-archive, license notices and Swift loopback smoke test" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: ProtectKit – Modelle der C-API, Routenentscheidung, Liveness, Prüf-Timeout

**Files:**
- Create: `Packages/ProtectKit/Sources/ProtectKit/Tunnel/TunnelModels.swift`, `TunnelRouting.swift`, `TunnelLiveness.swift`
- Test: `Packages/ProtectKit/Tests/ProtectKitTests/Tunnel/TunnelModelsTests.swift`, `TunnelRoutingTests.swift`, `TunnelLivenessTests.swift`
- Modify: `Packages/ProtectKit/Sources/ProtectKit/ProtectClient.swift` (init + probe)
- Modify: `Packages/ProtectKit/Tests/ProtectKitTests/ProtectClientTests.swift`, `PinEnforcementTests.swift`

**Interfaces:**
- Consumes: JSON-Formate von `WgParse`/`WgStatus` (Task 2), `CertificatePinning`, `ProtectClient` (Phase 1).
- Produces: `struct TunnelConfigSummary: Codable, Equatable, Sendable { endpoint, addresses, allowedIPs, dns, warnings }`, `enum TunnelParseResult { case valid(TunnelConfigSummary), invalid(String); static func decode(_ json: String) }`, `struct TunnelStatus: Decodable { up, peers: [Peer], error; static let stopped; static func decode(_:); var rxBytes: Int64; var lastHandshake: Date? }`, `enum TunnelMode: String, Codable, CaseIterable { automatic, always, off; var label }`, `enum ProtectRoute { direct, tunnel }`, `enum DirectReachability { console, otherDevice, unreachable; static func from(presentedFingerprint:pinned:) }`, `enum RouteDecision { static func needsProbe(mode:hasTunnel:) -> Bool; static func decide(mode:hasTunnel:direct:) -> ProtectRoute }`, `struct TunnelLiveness { init(stallAfter: TimeInterval = 75); var isDown; mutating func observe(rxBytes: Int64, at: Date) -> Event }` mit `enum Event { none, wentDown, recovered }`, `ProtectClient.init(…, protocolClasses:, requestTimeout: TimeInterval = 10)`, `static func ProtectClient.probeFingerprint(host: String, timeout: TimeInterval) async throws -> String`.

- [ ] **Step 1: Failing tests**

`Packages/ProtectKit/Tests/ProtectKitTests/Tunnel/TunnelModelsTests.swift`:
```swift
import XCTest
@testable import ProtectKit

final class TunnelModelsTests: XCTestCase {
    func testParseValid() {
        let json = #"{"ok":true,"summary":{"endpoint":"home.example.org:51820","addresses":["192.168.3.2/32"],"allowedIPs":["0.0.0.0/0","::/0"],"dns":["192.168.3.1"],"warnings":[]}}"#
        XCTAssertEqual(TunnelParseResult.decode(json), .valid(TunnelConfigSummary(
            endpoint: "home.example.org:51820", addresses: ["192.168.3.2/32"],
            allowedIPs: ["0.0.0.0/0", "::/0"], dns: ["192.168.3.1"], warnings: [])))
    }

    func testParseInvalidCarriesGoMessage() {
        XCTAssertEqual(TunnelParseResult.decode(#"{"ok":false,"error":"Zeile 3: Address \"x\" ungültig"}"#),
                       .invalid("Zeile 3: Address \"x\" ungültig"))
    }

    func testParseGarbageIsInvalidNotCrash() {
        XCTAssertEqual(TunnelParseResult.decode("nicht json"), .invalid("Unerwartete Antwort des Tunnel-Moduls."))
    }

    func testStatusStopped() {
        XCTAssertEqual(TunnelStatus.decode(#"{"up":false}"#), .stopped)
    }

    func testStatusRunning() {
        let json = #"{"up":true,"peers":[{"publicKey":"x","endpoint":"203.0.113.5:51820","lastHandshakeUnix":1760000000,"handshakeAgeSeconds":12,"rxBytes":4096,"txBytes":2048,"keepaliveSeconds":25}],"forwardConnections":2,"forwardBytesUp":10,"forwardBytesDown":20}"#
        let s = TunnelStatus.decode(json)
        XCTAssertTrue(s.up)
        XCTAssertEqual(s.rxBytes, 4096)
        XCTAssertEqual(s.lastHandshake, Date(timeIntervalSince1970: 1_760_000_000))
    }

    func testStatusWithoutHandshake() {
        let json = #"{"up":true,"peers":[{"publicKey":"x","endpoint":"","lastHandshakeUnix":0,"handshakeAgeSeconds":-1,"rxBytes":0,"txBytes":148,"keepaliveSeconds":25}]}"#
        XCTAssertNil(TunnelStatus.decode(json).lastHandshake)
    }
}
```

`Packages/ProtectKit/Tests/ProtectKitTests/Tunnel/TunnelRoutingTests.swift`:
```swift
import XCTest
@testable import ProtectKit

final class TunnelRoutingTests: XCTestCase {
    func testWithoutTunnelAlwaysDirect() {
        for mode in TunnelMode.allCases {
            XCTAssertEqual(RouteDecision.decide(mode: mode, hasTunnel: false, direct: .unreachable), .direct)
            XCTAssertFalse(RouteDecision.needsProbe(mode: mode, hasTunnel: false))
        }
    }

    func testAutomatic() {
        XCTAssertTrue(RouteDecision.needsProbe(mode: .automatic, hasTunnel: true))
        XCTAssertEqual(RouteDecision.decide(mode: .automatic, hasTunnel: true, direct: .console), .direct)
        XCTAssertEqual(RouteDecision.decide(mode: .automatic, hasTunnel: true, direct: .unreachable), .tunnel)
    }

    func testForeignDeviceOnSameAddressUsesTunnel() {
        XCTAssertEqual(RouteDecision.decide(mode: .automatic, hasTunnel: true, direct: .otherDevice), .tunnel)
    }

    func testAlwaysAndOff() {
        XCTAssertEqual(RouteDecision.decide(mode: .always, hasTunnel: true, direct: .console), .tunnel)
        XCTAssertEqual(RouteDecision.decide(mode: .off, hasTunnel: true, direct: .unreachable), .direct)
        XCTAssertFalse(RouteDecision.needsProbe(mode: .always, hasTunnel: true))
    }

    func testReachabilityFromPin() {
        XCTAssertEqual(DirectReachability.from(presentedFingerprint: nil, pinned: "AA"), .unreachable)
        XCTAssertEqual(DirectReachability.from(presentedFingerprint: "AA", pinned: nil), .console)
        XCTAssertEqual(DirectReachability.from(presentedFingerprint: "AA", pinned: "AA"), .console)
        XCTAssertEqual(DirectReachability.from(presentedFingerprint: "BB", pinned: "AA"), .otherDevice)
    }

    func testModeLabels() {
        XCTAssertEqual(TunnelMode.allCases.map(\.label), ["Automatisch", "Immer", "Nie"])
    }
}
```

`Packages/ProtectKit/Tests/ProtectKitTests/Tunnel/TunnelLivenessTests.swift`:
```swift
import XCTest
@testable import ProtectKit

final class TunnelLivenessTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testSteadyTrafficStaysUp() {
        var l = TunnelLiveness(stallAfter: 75)
        for i in 0..<20 {
            XCTAssertEqual(l.observe(rxBytes: Int64(i * 100), at: t0 + TimeInterval(i * 5)), .none)
        }
        XCTAssertFalse(l.isDown)
    }

    func testStallThenRecovery() {
        var l = TunnelLiveness(stallAfter: 75)
        XCTAssertEqual(l.observe(rxBytes: 500, at: t0), .none)
        XCTAssertEqual(l.observe(rxBytes: 500, at: t0 + 74), .none)
        XCTAssertEqual(l.observe(rxBytes: 500, at: t0 + 75), .wentDown)
        XCTAssertTrue(l.isDown)
        // An outage is reported once, not on every sample.
        XCTAssertEqual(l.observe(rxBytes: 500, at: t0 + 200), .none)
        XCTAssertEqual(l.observe(rxBytes: 700, at: t0 + 205), .recovered)
        XCTAssertFalse(l.isDown)
        XCTAssertEqual(l.observe(rxBytes: 900, at: t0 + 210), .none)
    }

    func testNeverAnsweringPeerGoesDown() {
        var l = TunnelLiveness(stallAfter: 75)
        XCTAssertEqual(l.observe(rxBytes: 0, at: t0), .none)
        XCTAssertEqual(l.observe(rxBytes: 0, at: t0 + 80), .wentDown)
    }

    func testCounterResetCountsAsTraffic() {
        var l = TunnelLiveness(stallAfter: 75)
        _ = l.observe(rxBytes: 9000, at: t0)
        XCTAssertEqual(l.observe(rxBytes: 10, at: t0 + 5), .none)
        XCTAssertFalse(l.isDown)
    }
}
```

In `Packages/ProtectKit/Tests/ProtectKitTests/PinEnforcementTests.swift` vor `    func testRequestFailsAfterInvalidate() async {` einfügen:
```swift
    /// Through the tunnel the client talks to 127.0.0.1:<forward>. The pin is the
    /// console's certificate, not a host name, so it must hold unchanged.
    func testPinHoldsForLocalForwardHost() throws {
        let data = try der("selfsigned"); let rec = Recorder()
        let c = ProtectClient(host: "127.0.0.1:50123", apiKey: "K",
                              pinnedFingerprint: CertificatePinning.fingerprint(of: data),
                              onNewFingerprint: { rec.add($0) }, protocolClasses: [FailingProtocol.self])
        XCTAssertEqual(c.baseURL.absoluteString, "https://127.0.0.1:50123/proxy/protect/integration")
        XCTAssertEqual(c.evaluate(trust: try trust(data)).0, .useCredential)
        XCTAssertEqual(c.evaluate(trust: try trust(try der("selfsigned2"))).0, .cancelAuthenticationChallenge)
        XCTAssertTrue(rec.all.isEmpty)
    }

```

In `Packages/ProtectKit/Tests/ProtectKitTests/ProtectClientTests.swift` vor `    func testProbeRejectsInvalidHost() async {` einfügen:
```swift
    func testProbeWithShortTimeoutSendsNoKey() async {
        StubProtocol.responses["GET \(base)/meta/info"] = (401, Data())
        do {
            _ = try await ProtectClient.probeFingerprint(host: "192.168.1.1", protocolClasses: [StubProtocol.self], timeout: 2)
            XCTFail()
        } catch {
            XCTAssertEqual(StubProtocol.requests.count, 1)
            XCTAssertNil(StubProtocol.requests.first?.value(forHTTPHeaderField: "X-API-KEY"))
        }
    }

    func testRequestTimeoutIsConfigurable() {
        XCTAssertEqual(client().requestTimeout, 10)
        let quick = ProtectClient(host: "192.168.1.1", apiKey: "", pinnedFingerprint: nil, onNewFingerprint: { _ in },
                                  protocolClasses: [StubProtocol.self], requestTimeout: 2)
        XCTAssertEqual(quick.requestTimeout, 2)
    }

```

- [ ] **Step 2: Tests laufen lassen**

Run: `(cd Packages/ProtectKit && swift test 2>&1 | grep -E "error:" | head -5)`
Expected: FAIL beim Kompilieren – `cannot find 'TunnelParseResult' in scope`, `extra argument 'timeout' in call`, `extra argument 'requestTimeout' in call`.

- [ ] **Step 3: Implementieren**

`Packages/ProtectKit/Sources/ProtectKit/Tunnel/TunnelModels.swift`:
```swift
import Foundation

/// Non-secret part of a WireGuard config as reported by the Go parser (`WgParse`).
/// Safe to keep outside the keychain: it never contains a key.
public struct TunnelConfigSummary: Codable, Equatable, Sendable {
    public var endpoint: String
    public var addresses: [String]
    public var allowedIPs: [String]
    public var dns: [String]
    public var warnings: [String]

    public init(endpoint: String, addresses: [String] = [], allowedIPs: [String] = [],
                dns: [String] = [], warnings: [String] = []) {
        self.endpoint = endpoint
        self.addresses = addresses
        self.allowedIPs = allowedIPs
        self.dns = dns
        self.warnings = warnings
    }
}

/// Result of `WgParse`: `{"ok":true,"summary":{…}}` or `{"ok":false,"error":"…"}`.
public enum TunnelParseResult: Equatable, Sendable {
    case valid(TunnelConfigSummary)
    case invalid(String)

    public static func decode(_ json: String) -> TunnelParseResult {
        struct Wire: Decodable {
            let ok: Bool
            let summary: TunnelConfigSummary?
            let error: String?
        }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: Data(json.utf8)) else {
            return .invalid("Unerwartete Antwort des Tunnel-Moduls.")
        }
        if wire.ok, let summary = wire.summary { return .valid(summary) }
        return .invalid(wire.error ?? "Die Datei ist keine gültige WireGuard-Konfiguration.")
    }
}

/// `WgStatus` JSON. `{"up":false}` when the tunnel is stopped.
public struct TunnelStatus: Decodable, Equatable, Sendable {
    public struct Peer: Decodable, Equatable, Sendable {
        public var endpoint: String
        public var lastHandshakeUnix: Int64
        public var handshakeAgeSeconds: Int64
        public var rxBytes: Int64
        public var txBytes: Int64

        public init(endpoint: String, lastHandshakeUnix: Int64, handshakeAgeSeconds: Int64,
                    rxBytes: Int64, txBytes: Int64) {
            self.endpoint = endpoint
            self.lastHandshakeUnix = lastHandshakeUnix
            self.handshakeAgeSeconds = handshakeAgeSeconds
            self.rxBytes = rxBytes
            self.txBytes = txBytes
        }
    }

    public var up: Bool
    public var peers: [Peer]
    public var error: String?

    public static let stopped = TunnelStatus(up: false, peers: [], error: nil)

    public init(up: Bool, peers: [Peer], error: String?) {
        self.up = up
        self.peers = peers
        self.error = error
    }

    private enum CodingKeys: String, CodingKey { case up, peers, error }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        up = try c.decode(Bool.self, forKey: .up)
        peers = try c.decodeIfPresent([Peer].self, forKey: .peers) ?? []
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }

    public static func decode(_ json: String) -> TunnelStatus {
        (try? JSONDecoder().decode(TunnelStatus.self, from: Data(json.utf8))) ?? .stopped
    }

    /// Received bytes over all peers (the app uses exactly one).
    public var rxBytes: Int64 { peers.reduce(0) { $0 + $1.rxBytes } }

    /// Most recent completed handshake, nil when there was none yet.
    public var lastHandshake: Date? {
        guard let newest = peers.map(\.lastHandshakeUnix).max(), newest > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(newest))
    }
}
```

`Packages/ProtectKit/Sources/ProtectKit/Tunnel/TunnelRouting.swift`:
```swift
import Foundation

/// Setting „Tunnel verwenden“.
public enum TunnelMode: String, Codable, CaseIterable, Sendable {
    case automatic, always, off

    public var label: String {
        switch self {
        case .automatic: return "Automatisch"
        case .always: return "Immer"
        case .off: return "Nie"
        }
    }
}

/// How the app reaches the console right now.
public enum ProtectRoute: Equatable, Sendable {
    case direct
    case tunnel
}

/// Outcome of a direct TLS probe of the configured console address.
public enum DirectReachability: Equatable, Sendable {
    /// Answered with the pinned certificate (or any certificate while nothing is pinned yet).
    case console
    /// Something answered, but with another certificate: a foreign network that happens
    /// to use the same address (hotel router on 192.168.1.1). Never send the key there.
    case otherDevice
    case unreachable

    public static func from(presentedFingerprint: String?, pinned: String?) -> DirectReachability {
        guard let presented = presentedFingerprint else { return .unreachable }
        guard let pinned else { return .console }
        return presented == pinned ? .console : .otherDevice
    }
}

public enum RouteDecision {
    /// Only automatic mode with a configured tunnel needs a direct probe.
    public static func needsProbe(mode: TunnelMode, hasTunnel: Bool) -> Bool {
        hasTunnel && mode == .automatic
    }

    /// `direct` is ignored unless `needsProbe` is true.
    public static func decide(mode: TunnelMode, hasTunnel: Bool, direct: DirectReachability) -> ProtectRoute {
        guard hasTunnel else { return .direct }
        switch mode {
        case .off: return .direct
        case .always: return .tunnel
        case .automatic: return direct == .console ? .direct : .tunnel
        }
    }
}
```

`Packages/ProtectKit/Sources/ProtectKit/Tunnel/TunnelLiveness.swift`:
```swift
import Foundation

/// Detects a tunnel outage and its end from periodic `WgStatus` samples.
///
/// While the app runs, the events WebSocket pings every 30 s, so the tunnel
/// receives something at least that often. No received byte for `stallAfter`
/// seconds counts as an outage. The first received byte afterwards is the
/// recovery: then every relayed TCP connection must be rebuilt, because a
/// gVisor TCP connection that lived through a long blackout can stay stuck.
public struct TunnelLiveness: Sendable {
    public enum Event: Equatable, Sendable {
        case none
        case wentDown
        case recovered
    }

    public let stallAfter: TimeInterval
    public private(set) var isDown = false
    private var lastRx: Int64?
    private var lastChange: Date?

    public init(stallAfter: TimeInterval = 75) {
        self.stallAfter = stallAfter
    }

    public mutating func observe(rxBytes: Int64, at now: Date) -> Event {
        guard let previous = lastRx, let changed = lastChange else {
            lastRx = rxBytes
            lastChange = now
            return .none
        }
        if rxBytes != previous {
            lastRx = rxBytes
            lastChange = now
            if isDown {
                isDown = false
                return .recovered
            }
            return .none
        }
        if !isDown, now.timeIntervalSince(changed) >= stallAfter {
            isDown = true
            return .wentDown
        }
        return .none
    }
}
```

`Packages/ProtectKit/Sources/ProtectKit/ProtectClient.swift` – vier Änderungen:

1. Init-Signatur:
```swift
// alt
        onNewFingerprint: @escaping @Sendable (String) -> Void,
        protocolClasses: [AnyClass]? = nil
    ) {
// neu
        onNewFingerprint: @escaping @Sendable (String) -> Void,
        protocolClasses: [AnyClass]? = nil,
        requestTimeout: TimeInterval = 10
    ) {
```
2. `config.timeoutIntervalForRequest = 10` → `config.timeoutIntervalForRequest = requestTimeout`
3. Kopf der internen Probe-Funktion:
```swift
// alt
    static func probeFingerprint(host: String, protocolClasses: [AnyClass]?) async throws -> String {
        guard baseURL(for: host) != nil else { throw ProtectError.invalidHost }
        let box = FingerprintBox()
        let client = ProtectClient(
            host: host, apiKey: "", pinnedFingerprint: nil,
            onNewFingerprint: { box.set($0) }, protocolClasses: protocolClasses
        )
// neu
    /// Same with a short timeout, for the route check (direct or tunnel) that must not
    /// hang for the default 10 s on a foreign network.
    public static func probeFingerprint(host: String, timeout: TimeInterval) async throws -> String {
        try await probeFingerprint(host: host, protocolClasses: nil, timeout: timeout)
    }

    static func probeFingerprint(host: String, protocolClasses: [AnyClass]?, timeout: TimeInterval = 10) async throws -> String {
        guard baseURL(for: host) != nil else { throw ProtectError.invalidHost }
        let box = FingerprintBox()
        let client = ProtectClient(
            host: host, apiKey: "", pinnedFingerprint: nil,
            onNewFingerprint: { box.set($0) }, protocolClasses: protocolClasses,
            requestTimeout: timeout
        )
```
(der Rest der Funktion – `defer { client.invalidate() }` usw. – bleibt).
4. Vor `    // MARK: API` einfügen:
```swift
    /// Effective per-request timeout (tests).
    var requestTimeout: TimeInterval { session.configuration.timeoutIntervalForRequest }

```

- [ ] **Step 4: Tests laufen lassen**

Run: `(cd Packages/ProtectKit && swift test 2>&1 | tail -3)`
Expected: PASS, „with 0 failures“.

- [ ] **Step 5: App baut weiter**

Run: Build-Befehl → `** BUILD SUCCEEDED **` (die App nutzt die neuen Parameter noch nicht; Standardwerte halten alte Aufrufe gültig).

- [ ] **Step 6: Commit**

```bash
git add Packages/ProtectKit/Sources/ProtectKit/Tunnel Packages/ProtectKit/Tests/ProtectKitTests/Tunnel Packages/ProtectKit/Sources/ProtectKit/ProtectClient.swift Packages/ProtectKit/Tests/ProtectKitTests/ProtectClientTests.swift Packages/ProtectKit/Tests/ProtectKitTests/PinEnforcementTests.swift
git diff --cached --name-only | grep AppConfig   # Erwartet: leer
git commit -m "feat(protectkit): tunnel models, route decision, liveness and probe timeout" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: ProtectKit – Adressen über Forwards, AllowedIPs, Datei-Prüfung, gespeicherter Zustand, Texte

**Files:**
- Create: `Packages/ProtectKit/Sources/ProtectKit/Tunnel/ForwardURL.swift`, `AllowedIPs.swift`, `WireGuardFile.swift`, `TunnelRecord.swift`, `TunnelText.swift`
- Test: `Packages/ProtectKit/Tests/ProtectKitTests/Tunnel/ForwardURLTests.swift`, `AllowedIPsTests.swift`, `WireGuardFileTests.swift`, `TunnelRecordTests.swift`, `TunnelTextTests.swift`

**Interfaces:**
- Consumes: `ProtectClient.baseURL(for:)`, `TunnelMode`, `ProtectRoute`, `TunnelConfigSummary` (Task 4).
- Produces: `struct ForwardTarget: Hashable { host: String; port: Int }`, `enum ForwardURL { static func apiTarget(consoleHost:) -> ForwardTarget?; static func localHost(port:) -> String; static func streamTarget(_:) -> ForwardTarget?; static func rewrite(_:localPort:) -> String? }`, `enum AllowedIPs { static func covers(host:prefixes:) -> Bool? }`, `enum WireGuardFile { static let maxBytes = 65536; enum Problem: LocalizedError { empty, tooLarge, notText }; static func text(from: Data) -> Result<String, Problem> }`, `struct TunnelLastConnection: Codable, Equatable { date: Date; via: NetworkKind }`, `struct TunnelRecord: Codable, Equatable { mode, fileName, summary, lastConnection; static func decode(_: Data?); func encoded() -> Data; var hasConfiguration; func reconciled(hasKeychainItem:) }`, `enum TunnelImportCheck { static func warning(consoleHost:summary:) -> String? }`, `enum NetworkKind: String, Codable { wifi, ethernet, cellular, other; var label }`, `enum TunnelRunState: Equatable { stopped, starting, up, down, failed(String) }`, `enum TunnelPhase: Equatable { off, home, connecting, connected, down, failed(String); static func from(mode:route:state:) }`, `enum TunnelTestOutcome: Equatable { ok, startFailed(String), noHandshake(endpoint:), consoleSilent(host:), otherDevice, noConsole; var message }`, `enum TunnelText { static func lastConnection(dayAndTime:via:); static func connectedChip(viaTunnel:); static func status(_:) -> (title:, subtitle:); static func consoleNotRouted(_:) }`.

- [ ] **Step 1: Failing tests**

`Packages/ProtectKit/Tests/ProtectKitTests/Tunnel/ForwardURLTests.swift`:
```swift
import XCTest
@testable import ProtectKit

final class ForwardURLTests: XCTestCase {
    func testAPITarget() {
        XCTAssertEqual(ForwardURL.apiTarget(consoleHost: "192.168.1.1"), ForwardTarget(host: "192.168.1.1", port: 443))
        XCTAssertEqual(ForwardURL.apiTarget(consoleHost: "konsole.local:8443"), ForwardTarget(host: "konsole.local", port: 8443))
        XCTAssertEqual(ForwardURL.apiTarget(consoleHost: "[fd00::1]:8443"), ForwardTarget(host: "fd00::1", port: 8443))
        XCTAssertNil(ForwardURL.apiTarget(consoleHost: " "))
    }

    func testLocalHostIsAValidConsoleHost() {
        let host = ForwardURL.localHost(port: 50123)
        XCTAssertEqual(host, "127.0.0.1:50123")
        XCTAssertEqual(ProtectClient.baseURL(for: host)?.absoluteString,
                       "https://127.0.0.1:50123/proxy/protect/integration")
    }

    func testStreamTarget() {
        XCTAssertEqual(ForwardURL.streamTarget("rtsp://192.168.1.1:7447/AbCdEf"), ForwardTarget(host: "192.168.1.1", port: 7447))
        XCTAssertEqual(ForwardURL.streamTarget("rtsp://cam.local/x"), ForwardTarget(host: "cam.local", port: 554))
        XCTAssertNil(ForwardURL.streamTarget("https://192.168.1.1/x"))
        XCTAssertNil(ForwardURL.streamTarget("kein url"))
    }

    func testRewriteKeepsPathAndQuery() {
        XCTAssertEqual(ForwardURL.rewrite("rtsp://192.168.1.1:7447/AbCdEf?x=1", localPort: 50200),
                       "rtsp://127.0.0.1:50200/AbCdEf?x=1")
        XCTAssertEqual(ForwardURL.rewrite("rtsp://[fd00::1]:7447/A", localPort: 50201),
                       "rtsp://127.0.0.1:50201/A")
    }
}
```

`Packages/ProtectKit/Tests/ProtectKitTests/Tunnel/AllowedIPsTests.swift`:
```swift
import XCTest
@testable import ProtectKit

final class AllowedIPsTests: XCTestCase {
    func testIPv4() {
        XCTAssertEqual(AllowedIPs.covers(host: "192.168.1.1", prefixes: ["192.168.1.0/24"]), true)
        XCTAssertEqual(AllowedIPs.covers(host: "192.168.2.1", prefixes: ["192.168.1.0/24"]), false)
        XCTAssertEqual(AllowedIPs.covers(host: "10.1.2.3", prefixes: ["0.0.0.0/0"]), true)
        XCTAssertEqual(AllowedIPs.covers(host: "192.168.1.7", prefixes: ["192.168.1.7/32"]), true)
        XCTAssertEqual(AllowedIPs.covers(host: "192.168.1.1", prefixes: ["10.0.0.0/8", "192.168.0.0/16"]), true)
    }

    func testIPv6AndFamilyMismatch() {
        XCTAssertEqual(AllowedIPs.covers(host: "fd00::1", prefixes: ["::/0"]), true)
        XCTAssertEqual(AllowedIPs.covers(host: "fd00::1", prefixes: ["0.0.0.0/0"]), false)
        XCTAssertEqual(AllowedIPs.covers(host: "192.168.1.1", prefixes: ["::/0"]), false)
    }

    func testHostNameIsUnknown() {
        XCTAssertNil(AllowedIPs.covers(host: "konsole.local", prefixes: ["0.0.0.0/0"]))
    }

    func testBrokenPrefixIsIgnored() {
        XCTAssertEqual(AllowedIPs.covers(host: "192.168.1.1", prefixes: ["192.168.1.0/99", "x/8"]), false)
    }
}
```

`Packages/ProtectKit/Tests/ProtectKitTests/Tunnel/WireGuardFileTests.swift`:
```swift
import XCTest
@testable import ProtectKit

final class WireGuardFileTests: XCTestCase {
    func testText() {
        XCTAssertEqual(WireGuardFile.text(from: Data("[Interface]\n".utf8)), .success("[Interface]\n"))
    }

    func testRejectsEmptyBinaryAndHuge() {
        XCTAssertEqual(WireGuardFile.text(from: Data()), .failure(.empty))
        XCTAssertEqual(WireGuardFile.text(from: Data(" \n".utf8)), .failure(.empty))
        XCTAssertEqual(WireGuardFile.text(from: Data([0x25, 0x50, 0x44, 0x46, 0xFF, 0xFE, 0x00])), .failure(.notText))
        XCTAssertEqual(WireGuardFile.text(from: Data(repeating: 0x41, count: WireGuardFile.maxBytes + 1)), .failure(.tooLarge))
    }
}
```

`Packages/ProtectKit/Tests/ProtectKitTests/Tunnel/TunnelRecordTests.swift`:
```swift
import XCTest
@testable import ProtectKit

final class TunnelRecordTests: XCTestCase {
    private let summary = TunnelConfigSummary(endpoint: "home.example.org:51820", addresses: ["192.168.3.2/32"],
                                              allowedIPs: ["192.168.1.0/24"], dns: ["192.168.3.1"])

    func testDefaultsWhenNothingStored() {
        XCTAssertEqual(TunnelRecord.decode(nil), TunnelRecord(mode: .automatic))
        XCTAssertEqual(TunnelRecord.decode(Data("kaputt".utf8)), TunnelRecord(mode: .automatic))
    }

    func testRoundTrip() {
        let record = TunnelRecord(mode: .always, fileName: "mac.conf", summary: summary,
                                  lastConnection: TunnelLastConnection(date: Date(timeIntervalSince1970: 1_760_000_000), via: .cellular))
        XCTAssertEqual(TunnelRecord.decode(record.encoded()), record)
    }

    func testUnknownModeFromNewerBuildFallsBackToAutomatic() {
        let json = #"{"mode":"onlyAtNight","fileName":"mac.conf"}"#
        let record = TunnelRecord.decode(Data(json.utf8))
        XCTAssertEqual(record.mode, .automatic)
        XCTAssertEqual(record.fileName, "mac.conf")
    }

    func testStoredFormHasNoRoomForKeys() {
        let text = String(decoding: TunnelRecord(mode: .automatic, fileName: "mac.conf", summary: summary).encoded(), as: UTF8.self)
        XCTAssertFalse(text.contains("PrivateKey"))
        XCTAssertFalse(text.lowercased().contains("key"))
    }

    func testWithoutKeychainItemOnlyModeSurvives() {
        let record = TunnelRecord(mode: .off, fileName: "mac.conf", summary: summary)
        XCTAssertEqual(record.reconciled(hasKeychainItem: false), TunnelRecord(mode: .off))
        XCTAssertEqual(record.reconciled(hasKeychainItem: true), record)
    }

    func testImportWarning() {
        XCTAssertNil(TunnelImportCheck.warning(consoleHost: "192.168.1.1", summary: summary))
        XCTAssertEqual(TunnelImportCheck.warning(consoleHost: "10.0.0.1", summary: summary),
                       TunnelText.consoleNotRouted("10.0.0.1"))
        XCTAssertNil(TunnelImportCheck.warning(consoleHost: "konsole.local", summary: summary))
        XCTAssertNil(TunnelImportCheck.warning(consoleHost: "192.168.1.1:8443",
                                               summary: TunnelConfigSummary(endpoint: "x:1", allowedIPs: ["0.0.0.0/0"])))
    }
}
```

`Packages/ProtectKit/Tests/ProtectKitTests/Tunnel/TunnelTextTests.swift`:
```swift
import XCTest
@testable import ProtectKit

final class TunnelTextTests: XCTestCase {
    func testLastConnection() {
        XCTAssertEqual(TunnelText.lastConnection(dayAndTime: "gestern, 18:22", via: .cellular),
                       "gestern, 18:22 · über Mobilfunk")
        XCTAssertEqual(TunnelText.lastConnection(dayAndTime: "heute, 08:05", via: .wifi), "heute, 08:05 · über WLAN")
        XCTAssertEqual(TunnelText.lastConnection(dayAndTime: "12.10., 18:22", via: .other), "12.10., 18:22 · über Netzwerk")
    }

    func testConnectedChip() {
        XCTAssertEqual(TunnelText.connectedChip(viaTunnel: false), "Zu Hause")
        XCTAssertEqual(TunnelText.connectedChip(viaTunnel: true), "Unterwegs")
    }

    func testHomeStatusMatchesTemplate() {
        let s = TunnelText.status(.home)
        XCTAssertEqual(s.title, "Bereit · gerade zu Hause")
        XCTAssertEqual(s.subtitle, "Der Tunnel springt an, sobald die Konsole nicht direkt erreichbar ist.")
    }

    func testFailedShowsMessage() {
        XCTAssertEqual(TunnelText.status(.failed("Endpoint nicht auflösbar")).subtitle, "Endpoint nicht auflösbar")
    }

    func testPhaseMapping() {
        XCTAssertEqual(TunnelPhase.from(mode: .off, route: .direct, state: .up), .off)
        XCTAssertEqual(TunnelPhase.from(mode: .automatic, route: .direct, state: .stopped), .home)
        XCTAssertEqual(TunnelPhase.from(mode: .automatic, route: .tunnel, state: .starting), .connecting)
        XCTAssertEqual(TunnelPhase.from(mode: .automatic, route: .tunnel, state: .up), .connected)
        XCTAssertEqual(TunnelPhase.from(mode: .always, route: .tunnel, state: .down), .down)
        // A tunnel that is wanted but fails to start shows why, even while the route fell back to direct.
        XCTAssertEqual(TunnelPhase.from(mode: .automatic, route: .direct, state: .failed("DNS")), .failed("DNS"))
    }

    func testTestOutcomeMessages() {
        XCTAssertEqual(TunnelTestOutcome.noHandshake(endpoint: "home.example.org:51820").message,
                       "Keine Antwort von home.example.org:51820. Prüfe Adresse und Port-Weiterleitung.")
        XCTAssertEqual(TunnelTestOutcome.ok.message, "Tunnel funktioniert – deine Konsole antwortet.")
    }
}
```

- [ ] **Step 2: Tests laufen lassen**

Run: `(cd Packages/ProtectKit && swift test 2>&1 | grep -E "error:" | head -5)`
Expected: FAIL beim Kompilieren – `cannot find 'ForwardURL' in scope` u. a.

- [ ] **Step 3: Implementieren**

`Packages/ProtectKit/Sources/ProtectKit/Tunnel/ForwardURL.swift`:
```swift
import Foundation

/// A TCP destination behind the tunnel.
public struct ForwardTarget: Hashable, Sendable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }
}

/// Maps console and camera addresses onto local forwards (127.0.0.1:<port>).
/// The certificate pin is unaffected: `ProtectClient` compares the leaf
/// certificate's fingerprint and never the host name.
public enum ForwardURL {
    /// Where the Protect API lives for a configured console address ("h", "h:8443", "[fd00::1]").
    public static func apiTarget(consoleHost: String) -> ForwardTarget? {
        guard let url = ProtectClient.baseURL(for: consoleHost),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = comps.host.map(unbracketed), !host.isEmpty else { return nil }
        return ForwardTarget(host: host, port: comps.port ?? 443)
    }

    /// The host string handed to `ProtectClient` for a forward.
    public static func localHost(port: Int) -> String {
        "127.0.0.1:\(port)"
    }

    /// rtsp://h:7447/x → (h, 7447). Port defaults to 554 (RTSP) when missing.
    public static func streamTarget(_ url: String) -> ForwardTarget? {
        guard let comps = URLComponents(string: url),
              comps.scheme?.lowercased() == "rtsp",
              let host = comps.host.map(unbracketed), !host.isEmpty else { return nil }
        return ForwardTarget(host: host, port: comps.port ?? 554)
    }

    /// Same URL with host and port replaced by 127.0.0.1:<localPort>; path and query stay.
    public static func rewrite(_ url: String, localPort: Int) -> String? {
        guard var comps = URLComponents(string: url), comps.host != nil else { return nil }
        comps.host = "127.0.0.1"
        comps.port = localPort
        return comps.string
    }

    private static func unbracketed(_ host: String) -> String {
        host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
    }
}
```

`Packages/ProtectKit/Sources/ProtectKit/Tunnel/AllowedIPs.swift`:
```swift
import Foundation

public enum AllowedIPs {
    /// Whether `host` lies inside one of the CIDR `prefixes` (e.g. "192.168.1.0/24", "::/0").
    /// nil when `host` is a name: whether it is routed only shows once it resolves.
    public static func covers(host: String, prefixes: [String]) -> Bool? {
        guard let address = bytes(of: host) else { return nil }
        for prefix in prefixes {
            let parts = prefix.split(separator: "/", maxSplits: 1).map(String.init)
            guard let net = bytes(of: parts[0]), net.count == address.count else { continue }
            let bits = parts.count == 2 ? Int(parts[1]) ?? -1 : net.count * 8
            guard bits >= 0, bits <= net.count * 8 else { continue }
            if matches(address, net, bits: bits) { return true }
        }
        return false
    }

    private static func bytes(of literal: String) -> [UInt8]? {
        var v4 = in_addr()
        if inet_pton(AF_INET, literal, &v4) == 1 {
            return withUnsafeBytes(of: &v4) { Array($0) }
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, literal, &v6) == 1 {
            return withUnsafeBytes(of: &v6) { Array($0) }
        }
        return nil
    }

    private static func matches(_ a: [UInt8], _ b: [UInt8], bits: Int) -> Bool {
        var remaining = bits
        for i in 0..<a.count where remaining > 0 {
            let take = min(8, remaining)
            let mask: UInt8 = take == 8 ? 0xFF : ~(UInt8(0xFF) >> UInt8(take))
            if a[i] & mask != b[i] & mask { return false }
            remaining -= take
        }
        return true
    }
}
```

`Packages/ProtectKit/Sources/ProtectKit/Tunnel/WireGuardFile.swift`:
```swift
import Foundation

/// Checks dropped/pasted data before it reaches the Go parser.
public enum WireGuardFile {
    public static let maxBytes = 64 * 1024

    public enum Problem: Error, Equatable, LocalizedError {
        case empty
        case tooLarge
        case notText

        public var errorDescription: String? {
            switch self {
            case .empty: return "Die Datei ist leer."
            case .tooLarge: return "Die Datei ist zu groß für eine WireGuard-Konfiguration."
            case .notText: return "Die Datei ist keine Textdatei."
            }
        }
    }

    public static func text(from data: Data) -> Result<String, Problem> {
        guard !data.isEmpty else { return .failure(.empty) }
        guard data.count <= maxBytes else { return .failure(.tooLarge) }
        guard let text = String(data: data, encoding: .utf8), !text.contains("\u{0}") else {
            return .failure(.notText)
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failure(.empty) }
        return .success(text)
    }
}
```

`Packages/ProtectKit/Sources/ProtectKit/Tunnel/TunnelRecord.swift`:
```swift
import Foundation

/// When and over which kind of network the tunnel last had a handshake.
public struct TunnelLastConnection: Codable, Equatable, Sendable {
    public var date: Date
    public var via: NetworkKind

    public init(date: Date, via: NetworkKind) {
        self.date = date
        self.via = via
    }
}

/// The non-secret tunnel settings as stored in UserDefaults. There is no field for
/// the config text: the private key exists only in the keychain.
public struct TunnelRecord: Codable, Equatable, Sendable {
    public var mode: TunnelMode
    public var fileName: String?
    public var summary: TunnelConfigSummary?
    public var lastConnection: TunnelLastConnection?

    public init(mode: TunnelMode = .automatic, fileName: String? = nil,
                summary: TunnelConfigSummary? = nil, lastConnection: TunnelLastConnection? = nil) {
        self.mode = mode
        self.fileName = fileName
        self.summary = summary
        self.lastConnection = lastConnection
    }

    private enum CodingKeys: String, CodingKey { case mode, fileName, summary, lastConnection }

    /// Tolerant: an unknown mode (newer build) becomes `.automatic`, broken parts are dropped.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? c.decode(TunnelMode.self, forKey: .mode)) ?? .automatic
        fileName = try? c.decodeIfPresent(String.self, forKey: .fileName)
        summary = try? c.decodeIfPresent(TunnelConfigSummary.self, forKey: .summary)
        lastConnection = try? c.decodeIfPresent(TunnelLastConnection.self, forKey: .lastConnection)
    }

    public static func decode(_ data: Data?) -> TunnelRecord {
        guard let data, let record = try? JSONDecoder().decode(TunnelRecord.self, from: data) else { return TunnelRecord() }
        return record
    }

    public func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    public var hasConfiguration: Bool { summary != nil }

    /// Metadata without the keychain item (keychain reset, restored backup) is no tunnel;
    /// the mode stays.
    public func reconciled(hasKeychainItem: Bool) -> TunnelRecord {
        guard !hasKeychainItem, hasConfiguration || fileName != nil else { return self }
        return TunnelRecord(mode: mode)
    }
}

public enum TunnelImportCheck {
    /// Non-blocking hint after an import: the console's address lies outside AllowedIPs.
    /// nil when it is inside, or when the console is a name (cannot be checked).
    public static func warning(consoleHost: String, summary: TunnelConfigSummary) -> String? {
        guard let host = ForwardURL.apiTarget(consoleHost: consoleHost)?.host,
              AllowedIPs.covers(host: host, prefixes: summary.allowedIPs) == false else { return nil }
        return TunnelText.consoleNotRouted(host)
    }
}
```

`Packages/ProtectKit/Sources/ProtectKit/Tunnel/TunnelText.swift`:
```swift
import Foundation

/// Kind of network the Mac used for the last tunnel connection.
public enum NetworkKind: String, Codable, Sendable {
    case wifi, ethernet, cellular, other

    public var label: String {
        switch self {
        case .wifi: return "WLAN"
        case .ethernet: return "Ethernet"
        case .cellular: return "Mobilfunk"
        case .other: return "Netzwerk"
        }
    }
}

/// Lifecycle of the in-app tunnel (`TunnelController.state`).
public enum TunnelRunState: Equatable, Sendable {
    case stopped
    /// Device is up, no handshake yet.
    case starting
    case up
    /// No traffic for `TunnelLiveness.stallAfter`.
    case down
    case failed(String)
}

/// Everything the „Unterwegs“ status card can show.
public enum TunnelPhase: Equatable, Sendable {
    case off
    case home
    case connecting
    case connected
    case down
    case failed(String)

    public static func from(mode: TunnelMode, route: ProtectRoute, state: TunnelRunState) -> TunnelPhase {
        if mode == .off { return .off }
        if case .failed(let message) = state { return .failed(message) }
        guard route == .tunnel else { return .home }
        switch state {
        case .stopped, .starting: return .connecting
        case .up: return .connected
        case .down: return .down
        case .failed(let message): return .failed(message)
        }
    }
}

/// Result of „Jetzt testen“.
public enum TunnelTestOutcome: Equatable, Sendable {
    case ok
    case startFailed(String)
    case noHandshake(endpoint: String)
    case consoleSilent(host: String)
    case otherDevice
    case noConsole

    public var message: String {
        switch self {
        case .ok:
            return "Tunnel funktioniert – deine Konsole antwortet."
        case .startFailed(let reason):
            return "Der Tunnel startet nicht: \(reason)"
        case .noHandshake(let endpoint):
            return "Keine Antwort von \(endpoint). Prüfe Adresse und Port-Weiterleitung."
        case .consoleSilent(let host):
            return "Der Tunnel steht, aber die Konsole (\(host)) antwortet nicht. Liegt sie in „AllowedIPs“?"
        case .otherDevice:
            return "Hinter dem Tunnel antwortet ein anderes Gerät als deine Konsole."
        case .noConsole:
            return "Es ist noch keine Konsole eingerichtet."
        }
    }
}

public enum TunnelText {
    /// „gestern, 18:22 · über Mobilfunk“ (Vorlage, Reiter „Unterwegs“). `dayAndTime` comes
    /// from `AppCore.DisplayText.dayAndTime` so all dates in the app read the same.
    public static func lastConnection(dayAndTime: String, via kind: NetworkKind) -> String {
        "\(dayAndTime) · über \(kind.label)"
    }

    /// Status chip of the menu panel while connected: „Zu Hause“ (Vorlage) or „Unterwegs“.
    public static func connectedChip(viaTunnel: Bool) -> String {
        viaTunnel ? "Unterwegs" : "Zu Hause"
    }

    /// Title and subtitle of the status card.
    public static func status(_ phase: TunnelPhase) -> (title: String, subtitle: String) {
        switch phase {
        case .off:
            return ("Aus", "Die App verbindet sich nur direkt mit der Konsole.")
        case .home:
            return ("Bereit · gerade zu Hause", "Der Tunnel springt an, sobald die Konsole nicht direkt erreichbar ist.")
        case .connecting:
            return ("Verbinde · unterwegs", "Der Tunnel wird aufgebaut …")
        case .connected:
            return ("Verbunden · unterwegs", "Die App erreicht deine Konsole über den Tunnel.")
        case .down:
            return ("Keine Verbindung · unterwegs", "Die Gegenstelle antwortet nicht. Prüfe Internet und Port-Weiterleitung.")
        case .failed(let message):
            return ("Tunnel startet nicht", message)
        }
    }

    /// Hint shown after an import when the console address is not routed through the tunnel.
    public static func consoleNotRouted(_ host: String) -> String {
        "Achtung: Konsole \(host) liegt nicht in „AllowedIPs“."
    }
}
```

- [ ] **Step 4: Tests laufen lassen**

Run: `(cd Packages/ProtectKit && swift test 2>&1 | tail -3)`
Expected: PASS, „with 0 failures“.

- [ ] **Step 5: App baut weiter**

Run: Build-Befehl → `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Packages/ProtectKit/Sources/ProtectKit/Tunnel Packages/ProtectKit/Tests/ProtectKitTests/Tunnel
git diff --cached --name-only | grep AppConfig   # Erwartet: leer
git commit -m "feat(protectkit): forward URLs, AllowedIPs check, tunnel record and texts" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Xcode – Build-Phase, Linken, Modul `WGTunnelC`, `TunnelBridge`, Release universal

**Files:**
- Create: `UniFiCameraPopup/scripts/pbxproj-add-files.py`
- Modify: `UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj`
- Create: `UniFiCameraPopup/Services/Tunnel/TunnelBridge.swift`
- Modify: `UniFiCameraPopup/Services/KeychainStore.swift`, `UniFiCameraPopup/scripts/build-release.sh`, `README.md`

**Interfaces:**
- Consumes: `wgtunnel/scripts/build-archive.sh`, `wgtunnel/include` (Task 2/3), `UniFiCameraPopup/ThirdPartyNotices.txt` (Task 3), `TunnelParseResult`, `TunnelStatus`, `ForwardTarget` (Task 4/5).
- Produces: `python3 UniFiCameraPopup/scripts/pbxproj-add-files.py <Services/Tunnel|Views/Tunnel|Source> <erste-ID-hex> <Datei …>`; `enum TunnelBridge { struct Failure: LocalizedError, Equatable { message }; static func parse(_:) -> TunnelParseResult; static func start(_:) throws; static func stop(); static func addForward(_: ForwardTarget) throws -> Int; static func addUDPForward(ip:port:) throws -> Int; static func resetConnections() -> Int; static func rebind() throws; static func status() -> TunnelStatus }`; `KeychainStore.wireGuardConfigService`.

Linker-Entscheidungen (geprüft im Probe-Build): `OTHER_LDFLAGS` nur am App-Target (`libwgtunnel.a`, `-lresolv`, `Security`, `CoreFoundation`); `SWIFT_INCLUDE_PATHS` am Projekt, damit auch spätere Targets das Modul finden; `ENABLE_USER_SCRIPT_SANDBOXING = NO`, weil die Build-Phase nach `wgtunnel/` schreibt und beim ersten Lauf Go lädt. Die Build-Phase läuft vor „Sources“ und ist `alwaysOutOfDate` – das Skript prüft selbst, ob etwas zu tun ist.

- [ ] **Step 1: IDs frei?**

Run: `grep -c "D41000000000000000000001\|D46000000000000000000001\|D44000000000000000000001" UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj`
Expected: `0`.

- [ ] **Step 2: pbxproj-Helfer anlegen**

`UniFiCameraPopup/scripts/pbxproj-add-files.py`:
```python
#!/usr/bin/env python3
"""Adds files to the app target of UniFiCameraPopup.xcodeproj (hand-maintained pbxproj).

usage: scripts/pbxproj-add-files.py <group> <first-id> <file> [<file> ...]

  group     Services/Tunnel | Views/Tunnel | Source (top-level group, for resources)
  first-id  two hex digits; file n gets PBXBuildFile D41…<id+n> and PBXFileReference D42…<id+n>
  file      file name inside the group's folder

*.swift goes to the Sources phase, everything else to Resources. The groups
Services/Tunnel and Views/Tunnel are created on first use. A file already in the
project is skipped, so a second run changes nothing.
"""
import os
import re
import sys

PROJECT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                       "UniFiCameraPopup.xcodeproj", "project.pbxproj")
APP_SOURCES = "A60000000000000000000002 /* Sources */"
APP_RESOURCES = "A60000000000000000000003 /* Resources */"
# group name -> (own id, parent id, child line in the parent after which it is inserted)
GROUPS = {
    "Services/Tunnel": ("D44000000000000000000001", "A40000000000000000000005",
                        "A20000000000000000000020 /* FocusMonitor.swift */"),
    "Views/Tunnel": ("D44000000000000000000002", "A40000000000000000000006",
                     "A40000000000000000000060 /* Onboarding */"),
    "Source": ("A40000000000000000000002", None, None),
}


def main():
    group, first, *files = sys.argv[1:]
    s = open(PROJECT, encoding="utf-8").read()
    group_id, parent_id, after_child = GROUPS[group]

    def unique(anchor):
        count = s.count(anchor)
        if count != 1:
            sys.exit(f"anchor found {count}x, expected once: {anchor!r}")

    def block_start(object_id):
        m = re.search(r"\n\t\t" + object_id + r" /\* [^*]+ \*/ = \{", s)
        if not m:
            sys.exit(f"object {object_id} not found")
        return m.start()

    def insert_into_list(object_id, list_key, line):
        nonlocal s
        start = block_start(object_id)
        key = f"\t\t\t{list_key} = (\n"
        pos = s.index(key, start) + len(key)
        s = s[:pos] + line + s[pos:]

    if parent_id and f"\t\t{group_id} /* Tunnel */ = {{" not in s:
        child_line = f"\t\t\t\t{after_child},\n"
        unique(child_line)
        s = s.replace(child_line, child_line + f"\t\t\t\t{group_id} /* Tunnel */,\n", 1)
        anchor = "/* End PBXGroup section */"
        unique(anchor)
        s = s.replace(anchor, (
            f"\t\t{group_id} /* Tunnel */ = {{\n"
            "\t\t\tisa = PBXGroup;\n"
            "\t\t\tchildren = (\n"
            "\t\t\t);\n"
            "\t\t\tpath = Tunnel;\n"
            "\t\t\tsourceTree = \"<group>\";\n"
            "\t\t};\n"
        ) + anchor, 1)

    n = int(first, 16)
    for name in files:
        if re.search(r"path = \"?" + re.escape(name) + r"\"?;", s):
            print("already in project:", name)
            n += 1
            continue
        build_id = f"D41{n:021X}"
        ref_id = f"D42{n:021X}"
        if build_id in s or ref_id in s:
            sys.exit(f"id {build_id}/{ref_id} already used – pick another first-id")
        n += 1
        swift = name.endswith(".swift")
        phase_name = "Sources" if swift else "Resources"
        file_type = "sourcecode.swift" if swift else "text"
        for marker, line in (
            ("/* End PBXBuildFile section */",
             f"\t\t{build_id} /* {name} in {phase_name} */ = {{isa = PBXBuildFile; fileRef = {ref_id} /* {name} */; }};\n"),
            ("/* End PBXFileReference section */",
             f"\t\t{ref_id} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {file_type}; path = {name}; sourceTree = \"<group>\"; }};\n"),
        ):
            unique(marker)
            s = s.replace(marker, line + marker, 1)
        insert_into_list(group_id, "children", f"\t\t\t\t{ref_id} /* {name} */,\n")
        phase = (APP_SOURCES if swift else APP_RESOURCES).split(" ")[0]
        insert_into_list(phase, "files", f"\t\t\t\t{build_id} /* {name} in {phase_name} */,\n")
        print("added", name, build_id, ref_id)

    open(PROJECT, "w", encoding="utf-8").write(s)


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Build-Phase und Build-Einstellungen eintragen**

Aus dem Worktree-Wurzelverzeichnis:
```bash
python3 - <<'EOF'
import re
import sys

path = "UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj"
s = open(path, encoding="utf-8").read()
if "D46000000000000000000001" in s:
    sys.exit("already patched")


def block(object_id):
    m = re.search(r"\n\t\t" + object_id + r" /\* [^*]+ \*/ = \{", s)
    if not m:
        sys.exit(f"object {object_id} not found")
    return m.start()


def insert_after_in_block(object_id, anchor, text):
    global s
    start = block(object_id)
    pos = s.index(anchor, start) + len(anchor)
    s = s[:pos] + text + s[pos:]


# 1. Build phase "Build WireGuard tunnel" runs first in the app target.
insert_after_in_block("A60000000000000000000001", "\t\t\tbuildPhases = (\n",
                      "\t\t\t\tD46000000000000000000001 /* Build WireGuard tunnel */,\n")
anchor = "/* Begin PBXSourcesBuildPhase section */"
assert s.count(anchor) == 1
s = s.replace(anchor, (
    "/* Begin PBXShellScriptBuildPhase section */\n"
    "\t\tD46000000000000000000001 /* Build WireGuard tunnel */ = {\n"
    "\t\t\tisa = PBXShellScriptBuildPhase;\n"
    "\t\t\talwaysOutOfDate = 1;\n"
    "\t\t\tbuildActionMask = 2147483647;\n"
    "\t\t\tfiles = (\n"
    "\t\t\t);\n"
    "\t\t\tinputPaths = (\n"
    "\t\t\t);\n"
    "\t\t\tname = \"Build WireGuard tunnel\";\n"
    "\t\t\toutputPaths = (\n"
    "\t\t\t);\n"
    "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
    "\t\t\tshellPath = /bin/bash;\n"
    "\t\t\tshellScript = \"\\\"$PROJECT_DIR/../wgtunnel/scripts/build-archive.sh\\\"\\n\";\n"
    "\t\t\tshowEnvVarsInLog = 0;\n"
    "\t\t};\n"
    "/* End PBXShellScriptBuildPhase section */\n\n"
) + anchor, 1)

# 2. Project level: Swift finds the Clang module WGTunnelC.
for cfg in ("A80000000000000000000002", "A80000000000000000000004"):
    insert_after_in_block(cfg, "\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 13.0;\n",
                          "\t\t\t\tSWIFT_INCLUDE_PATHS = \"$(PROJECT_DIR)/../wgtunnel/include\";\n")

# 3. App target only: link the archive; the build phase writes outside DerivedData.
for cfg in ("A80000000000000000000005", "A80000000000000000000006"):
    insert_after_in_block(cfg, "\t\t\t\tENABLE_HARDENED_RUNTIME = NO;\n",
                          "\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = NO;\n")
    insert_after_in_block(cfg, "\t\t\t\tMARKETING_VERSION = 1.2.0;\n", (
        "\t\t\t\tOTHER_LDFLAGS = (\n"
        "\t\t\t\t\t\"$(inherited)\",\n"
        "\t\t\t\t\t\"$(PROJECT_DIR)/../wgtunnel/build/libwgtunnel.a\",\n"
        "\t\t\t\t\t\"-lresolv\",\n"
        "\t\t\t\t\t\"-framework\",\n"
        "\t\t\t\t\tSecurity,\n"
        "\t\t\t\t\t\"-framework\",\n"
        "\t\t\t\t\tCoreFoundation,\n"
        "\t\t\t\t);\n"))

open(path, "w", encoding="utf-8").write(s)
print("patched", path)
EOF
plutil -lint UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj
```
Expected: `patched …`, `OK`.

- [ ] **Step 4: `TunnelBridge` und Schlüsselbund-Dienst**

`UniFiCameraPopup/Services/Tunnel/TunnelBridge.swift`:
```swift
import Foundation
import ProtectKit
import WGTunnelC

/// Synchronous wrapper around the Go c-archive (`wgtunnel/capi`). The Go side
/// serializes calls with its own mutex. `start` and `rebind` resolve DNS and may
/// block for seconds – call them off the main thread.
enum TunnelBridge {
    struct Failure: LocalizedError, Equatable {
        let message: String
        var errorDescription: String? { message }
    }

    static func parse(_ config: String) -> TunnelParseResult {
        TunnelParseResult.decode(take(WgParse(config)) ?? "")
    }

    static func start(_ config: String) throws {
        if let message = take(WgStart(config)) { throw Failure(message: message) }
    }

    static func stop() {
        WgStop()
    }

    /// Local TCP port on 127.0.0.1 that leads to `target` through the tunnel.
    static func addForward(_ target: ForwardTarget) throws -> Int {
        let port = WgAddForward(0, target.host, Int32(target.port))
        guard port > 0 else { throw Failure(message: take(WgLastError()) ?? "Weiterleitung fehlgeschlagen") }
        return Int(port)
    }

    /// Local UDP port on 127.0.0.1 that leads to `ip:port` through the tunnel (talkback).
    static func addUDPForward(ip: String, port: Int) throws -> Int {
        let local = WgAddUDPForward(0, ip, Int32(port))
        guard local > 0 else { throw Failure(message: take(WgLastError()) ?? "Weiterleitung fehlgeschlagen") }
        return Int(local)
    }

    /// Closes all relayed TCP connections; the local ports stay valid.
    @discardableResult
    static func resetConnections() -> Int {
        Int(WgResetConnections())
    }

    static func rebind() throws {
        if let message = take(WgRebind()) { throw Failure(message: message) }
    }

    static func status() -> TunnelStatus {
        TunnelStatus.decode(take(WgStatus()) ?? "")
    }

    private static func take(_ pointer: UnsafeMutablePointer<CChar>?) -> String? {
        guard let pointer else { return nil }
        defer { WgFree(pointer) }
        return String(cString: pointer)
    }
}
```

In `UniFiCameraPopup/Services/KeychainStore.swift` nach `    static let protectAPIKeyService = "com.snackbits.UniFiCameraPopup.protect-api-key"` einfügen:
```swift
    /// Full wg-quick text of the WireGuard tunnel (contains the private key).
    static let wireGuardConfigService = "com.snackbits.UniFiCameraPopup.wireguard-config"
```

```bash
python3 UniFiCameraPopup/scripts/pbxproj-add-files.py Services/Tunnel 01 TunnelBridge.swift
python3 UniFiCameraPopup/scripts/pbxproj-add-files.py Source 30 ThirdPartyNotices.txt
plutil -lint UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj
```
Expected: `added TunnelBridge.swift D41000000000000000000001 D42000000000000000000001`, `added ThirdPartyNotices.txt D41000000000000000000030 D42000000000000000000030`, `OK`.

- [ ] **Step 5: Build und gelinkte Symbole prüfen**

Run: Build-Befehl, danach
```bash
grep -c "build-archive:" <(xcodebuild -project UniFiCameraPopup/UniFiCameraPopup.xcodeproj -scheme UniFiCameraPopup -configuration Debug -derivedDataPath "$DD" build 2>&1)
nm -gU "$DD/Build/Products/Debug/UniFi Camera Popup.app/Contents/MacOS/UniFi Camera Popup" | grep -c " _Wg"
ls "$DD/Build/Products/Debug/UniFi Camera Popup.app/Contents/Resources/ThirdPartyNotices.txt"
```
Expected: `** BUILD SUCCEEDED **`; `1` (die Phase lief); `10`; die Datei existiert.

- [ ] **Step 6: Release universal bauen**

In `UniFiCameraPopup/scripts/build-release.sh` den Block
```bash
xcodebuild \
  -project UniFiCameraPopup.xcodeproj \
  -scheme UniFiCameraPopup \
  -configuration Release \
  -derivedDataPath .build \
  build

APP_PATH=".build/Build/Products/Release/UniFi Camera Popup.app"
"${SCRIPT_DIR}/resign-app.sh" "$APP_PATH"
```
ersetzen durch:
```bash
# generic/platform=macOS builds every architecture in ARCHS (arm64 + x86_64);
# without it xcodebuild only builds for this Mac. The build phase
# "Build WireGuard tunnel" produces the universal libwgtunnel.a first.
xcodebuild \
  -project UniFiCameraPopup.xcodeproj \
  -scheme UniFiCameraPopup \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath .build \
  build

APP_PATH=".build/Build/Products/Release/UniFi Camera Popup.app"

# The release must run on Apple silicon and Intel Macs.
BINARY_ARCHS="$(lipo -archs "${APP_PATH}/Contents/MacOS/UniFi Camera Popup")"
for arch in arm64 x86_64; do
  if [[ " ${BINARY_ARCHS} " != *" ${arch} "* ]]; then
    echo "ERROR: App binary lacks ${arch} (has: ${BINARY_ARCHS})." >&2
    exit 1
  fi
done
if [[ ! -s "${APP_PATH}/Contents/Resources/ThirdPartyNotices.txt" ]]; then
  echo "ERROR: ThirdPartyNotices.txt missing from the app bundle." >&2
  exit 1
fi

"${SCRIPT_DIR}/resign-app.sh" "$APP_PATH"
```

Prüfen, **ohne** `build-release.sh` auszuführen (es würde `AppConfig.swift` hochzählen):
```bash
bash -n UniFiCameraPopup/scripts/build-release.sh && echo "Syntax ok"
REL="${TMPDIR:-/tmp}/ucp-phase4-release"
xcodebuild -project UniFiCameraPopup/UniFiCameraPopup.xcodeproj -scheme UniFiCameraPopup -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$REL" build 2>&1 | grep -E "error:|\*\* BUILD" | tail -5
lipo -archs "$REL/Build/Products/Release/UniFi Camera Popup.app/Contents/MacOS/UniFi Camera Popup"
lipo -archs "$REL/Build/Products/Release/UniFi Camera Popup.app/Contents/Frameworks/VLCKit.framework/VLCKit"
```
Expected: `Syntax ok`, `** BUILD SUCCEEDED **`, zweimal `x86_64 arm64`.

- [ ] **Step 7: README – Build-Voraussetzung**

In `README.md` unter `### Mit Xcode` die Liste ersetzen durch:
```markdown
1. Open `UniFiCameraPopup.xcodeproj` in Xcode (inside the `UniFiCameraPopup` folder)
2. Wait for Swift Package `VLCKitSPM` to resolve
3. Build and run (⌘R). The first build downloads the pinned Go toolchain (go1.27.2, ~70 MB, SHA-256 checked) into `wgtunnel/.toolchain/` and builds the WireGuard tunnel (`wgtunnel/build/libwgtunnel.a`, arm64 + x86_64). Network access is needed once; the system Go is never used.
```

- [ ] **Step 8: Commit**

```bash
git add UniFiCameraPopup/scripts/pbxproj-add-files.py UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj UniFiCameraPopup/Services/Tunnel/TunnelBridge.swift UniFiCameraPopup/Services/KeychainStore.swift UniFiCameraPopup/scripts/build-release.sh README.md
git diff --cached --name-only | grep AppConfig   # Erwartet: leer
git commit -m "build: link the WireGuard c-archive, universal release build" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Tunnel-Steuerung und automatische Umschaltung in der App

**Files:**
- Create: `UniFiCameraPopup/Services/Tunnel/TunnelStore.swift`, `TunnelImporter.swift`, `TunnelController.swift`, `ConnectionRouter.swift`
- Modify: `UniFiCameraPopup/Services/ProtectSession.swift`, `UniFiCameraPopup/Services/ProtectEventService.swift`, `UniFiCameraPopup/Views/VLCPlayerView.swift`, `UniFiCameraPopup/AppDelegate.swift`, `UniFiCameraPopup/Views/Onboarding/OnboardingView.swift`, die Datei mit dem Zertifikats-Neuvertrauen in den Einstellungen (Phase 2: Reiter Allgemein), `project.pbxproj`

**Interfaces:**
- Consumes: `TunnelBridge` (Task 6), ProtectKit-Typen (Task 4/5), `SettingsStore.protectHost`, `.protectCertificateFingerprint`, `.isProtectConfigured`, `ProtectSession.reconnect()`.
- Produces:
  - `@MainActor final class TunnelStore: ObservableObject` – `static let shared`, `static let defaultsKey = "unifi.camera.popup.tunnel"`, `@Published private(set) var record: TunnelRecord`, `var mode: TunnelMode { get set }`, `fileName`, `summary`, `lastConnection`, `hasConfiguration`, `configText: String?`, `save(config:fileName:summary:) -> Bool`, `recordConnection(at:via:)`, `remove()`.
  - `@MainActor enum TunnelImporter` – `struct Outcome { summary; warning: String? }`, `enum Failure: LocalizedError, Equatable { file(WireGuardFile.Problem), invalid(String), keychain }`, `static let pastedFileName`, `static func importData(_:fileName:) -> Result<Outcome, Failure>`.
  - `@MainActor final class TunnelController: ObservableObject` – `static let shared`, `static let connectionsResetNotification`, `@Published state: TunnelRunState`, `@Published lastHandshake: Date?`, `var networkKind: () -> NetworkKind`, `isStarted`, `start() async -> Bool`, `stop()`, `localPort(for: ForwardTarget) -> Int?`, `resetConnections(reason:)`, `networkChanged() async`, `waitForHandshake(timeout:) async -> Bool`.
  - `@MainActor final class ConnectionRouter: ObservableObject` – `static let shared`, `static let routeDidChangeNotification`, `@Published route: ProtectRoute`, `@Published isTesting`, `@Published testOutcome: TunnelTestOutcome?`, `start()`, `apiHost(for consoleHost: String) -> String`, `playableStreamURL(_:) -> String`, `noteConnectionFailure()`, `configurationChanged()`, `importTunnel(data:fileName:)`, `importTunnel(text:)`, `removeTunnel()`, `testNow() async`.

Ablauf (zur Orientierung): Auslöser sind App-Start, Netzwechsel (`NWPathMonitor`, 2 s Ruhe), Aufwachen, Abbruch des Ereignis-Sockets (höchstens alle 30 s), Einstellungsänderung und – nur unterwegs im Modus „Automatisch“ – alle 5 Minuten. Dann: im Modus „Automatisch“ mit eingerichtetem Tunnel prüft `probeFingerprint(host:timeout: 3)` die Konsolenadresse direkt (ohne API-Schlüssel); nur das gepinnte Zertifikat heißt „zu Hause“. Unterwegs startet der Tunnel, `ProtectSession.reconnect()` baut den Client auf `127.0.0.1:<forward>` neu (der Ereignisdienst folgt über `$client`), offene Livebilder starten mit der umgeschriebenen RTSP-URL neu. Alle 5 s liest der Controller `WgStatus`; 75 s ohne empfangenes Byte (der WebSocket pingt alle 30 s) gilt als Ausfall, das nächste Byte als Wiederkehr → `WgResetConnections` + Benachrichtigung → Ereignis-Socket und Streams verbinden sofort neu. Startet der Tunnel nicht (offline, Name nicht auflösbar), bleibt die Route direkt und der Router versucht es alle 30 s erneut.

- [ ] **Step 1: Neue Dateien**

`UniFiCameraPopup/Services/Tunnel/TunnelStore.swift`:
```swift
import Foundation
import ProtectKit

/// WireGuard setup of this Mac. The config text (it contains the private key) lives
/// only in the keychain; UserDefaults keep the non-secret `TunnelRecord`. Deliberately
/// outside `SettingsStore`: the configuration export must never carry any of it.
@MainActor
final class TunnelStore: ObservableObject {
    static let shared = TunnelStore()
    static let defaultsKey = "unifi.camera.popup.tunnel"

    @Published private(set) var record: TunnelRecord

    private let defaults = UserDefaults.standard
    private let keychainService = KeychainStore.wireGuardConfigService
    private let account = "default"

    private init() {
        let stored = TunnelRecord.decode(defaults.data(forKey: Self.defaultsKey))
        let hasItem = KeychainStore.string(service: keychainService, account: account) != nil
        record = stored.reconciled(hasKeychainItem: hasItem)
        if record != stored { persist() }
    }

    var mode: TunnelMode {
        get { record.mode }
        set { record.mode = newValue; persist() }
    }
    var fileName: String? { record.fileName }
    var summary: TunnelConfigSummary? { record.summary }
    var lastConnection: TunnelLastConnection? { record.lastConnection }
    var hasConfiguration: Bool { record.hasConfiguration }

    /// The full wg-quick text including the private key.
    var configText: String? {
        KeychainStore.string(service: keychainService, account: account)
    }

    /// Stores a config the Go parser accepted. False when the keychain refused it.
    @discardableResult
    func save(config: String, fileName: String, summary: TunnelConfigSummary) -> Bool {
        guard KeychainStore.set(config, service: keychainService, account: account) else { return false }
        record = TunnelRecord(mode: record.mode, fileName: fileName, summary: summary, lastConnection: nil)
        persist()
        return true
    }

    func recordConnection(at date: Date, via kind: NetworkKind) {
        record.lastConnection = TunnelLastConnection(date: date, via: kind)
        persist()
    }

    func remove() {
        KeychainStore.delete(service: keychainService, account: account)
        record = TunnelRecord(mode: record.mode)
        persist()
    }

    private func persist() {
        defaults.set(record.encoded(), forKey: Self.defaultsKey)
    }
}
```

`UniFiCameraPopup/Services/Tunnel/TunnelImporter.swift`:
```swift
import Foundation
import ProtectKit

/// Validates a dropped, picked or pasted WireGuard config and stores it.
@MainActor
enum TunnelImporter {
    struct Outcome: Equatable {
        let summary: TunnelConfigSummary
        /// Non-blocking hint, e.g. the console is not inside AllowedIPs.
        let warning: String?
    }

    enum Failure: LocalizedError, Equatable {
        case file(WireGuardFile.Problem)
        case invalid(String)
        case keychain

        var errorDescription: String? {
            switch self {
            case .file(let problem): return problem.errorDescription
            case .invalid(let message): return "Keine gültige WireGuard-Datei: \(message)"
            case .keychain: return "Der Schlüsselbund hat die Konfiguration nicht angenommen."
            }
        }
    }

    static let pastedFileName = "Eingefügte Konfiguration"

    static func importData(_ data: Data, fileName: String) -> Result<Outcome, Failure> {
        switch WireGuardFile.text(from: data) {
        case .failure(let problem):
            return .failure(.file(problem))
        case .success(let text):
            switch TunnelBridge.parse(text) {
            case .invalid(let message):
                return .failure(.invalid(message))
            case .valid(let summary):
                // Saved only after the parser accepted it: a broken file never replaces a working one.
                guard TunnelStore.shared.save(config: text, fileName: fileName, summary: summary) else {
                    return .failure(.keychain)
                }
                let warning = TunnelImportCheck.warning(consoleHost: SettingsStore.shared.protectHost, summary: summary)
                return .success(Outcome(summary: summary, warning: warning))
            }
        }
    }
}
```

`UniFiCameraPopup/Services/Tunnel/TunnelController.swift`:
```swift
import Foundation
import ProtectKit

/// Runs the in-app WireGuard tunnel: start/stop, local forwards, liveness.
/// Only `ConnectionRouter` decides *when* the tunnel is needed.
@MainActor
final class TunnelController: ObservableObject {
    static let shared = TunnelController()
    /// Posted after all relayed connections were closed (tunnel back after an outage,
    /// wake from sleep). Owners of long-lived connections reconnect on it.
    static let connectionsResetNotification = Notification.Name("TunnelController.connectionsReset")

    @Published private(set) var state: TunnelRunState = .stopped
    @Published private(set) var lastHandshake: Date?

    /// Supplied by `ConnectionRouter` (NWPathMonitor), used for „Letzte Verbindung“.
    var networkKind: () -> NetworkKind = { .other }

    private let store = TunnelStore.shared
    private(set) var isStarted = false
    private var forwards: [ForwardTarget: Int] = [:]
    private var liveness = TunnelLiveness()
    private var poller: Task<Void, Never>?
    private var startTask: Task<Bool, Never>?

    private init() {}

    /// Starts the tunnel from the stored config. True when the device is up; whether
    /// the peer answers shows in `state` (`.starting` until the first handshake).
    func start() async -> Bool {
        if isStarted { return true }
        if let startTask { return await startTask.value }
        guard let config = store.configText else {
            state = .failed("Keine WireGuard-Konfiguration gespeichert.")
            return false
        }
        state = .starting
        let task = Task<Bool, Never> { @MainActor in
            let failure = await Task.detached { () -> String? in
                do {
                    try TunnelBridge.start(config)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            self.startTask = nil
            if let failure {
                NSLog("Tunnel: Start fehlgeschlagen – \(failure)")
                self.state = .failed(failure)
                return false
            }
            self.isStarted = true
            self.forwards = [:]
            self.liveness = TunnelLiveness()
            self.startPolling()
            NSLog("Tunnel: gestartet")
            return true
        }
        startTask = task
        return await task.value
    }

    func stop() {
        poller?.cancel()
        poller = nil
        if isStarted {
            TunnelBridge.stop()
            NSLog("Tunnel: gestoppt")
        }
        isStarted = false
        forwards = [:]
        state = .stopped
    }

    /// Local port on 127.0.0.1 for `target`, created on first use. nil while stopped.
    func localPort(for target: ForwardTarget) -> Int? {
        guard isStarted else { return nil }
        if let port = forwards[target] { return port }
        do {
            let port = try TunnelBridge.addForward(target)
            forwards[target] = port
            return port
        } catch {
            NSLog("Tunnel: Weiterleitung \(target.host):\(target.port) – \(error.localizedDescription)")
            return nil
        }
    }

    /// Closes every relayed connection and tells their owners to reconnect.
    func resetConnections(reason: String) {
        guard isStarted else { return }
        let closed = TunnelBridge.resetConnections()
        NSLog("Tunnel: \(reason) – \(closed) Verbindung(en) neu aufbauen")
        NotificationCenter.default.post(name: Self.connectionsResetNotification, object: nil)
    }

    /// New network: re-resolve the endpoint and rebind the UDP socket.
    /// TCP connections inside the tunnel survive this (WireGuard roams).
    func networkChanged() async {
        guard isStarted else { return }
        let failure = await Task.detached { () -> String? in
            do {
                try TunnelBridge.rebind()
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
        if let failure { NSLog("Tunnel: Rebind – \(failure)") }
    }

    /// Waits until a handshake completed, polling the status.
    func waitForHandshake(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if TunnelBridge.status().lastHandshake != nil { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return false
    }

    private func startPolling() {
        poller?.cancel()
        poller = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func sample() {
        guard isStarted else { return }
        let status = TunnelBridge.status()
        guard status.up else { return }
        if let handshake = status.lastHandshake {
            lastHandshake = handshake
            if state == .starting { state = .up }
            if store.lastConnection.map({ handshake.timeIntervalSince($0.date) > 60 }) ?? true {
                store.recordConnection(at: handshake, via: networkKind())
            }
        }
        switch liveness.observe(rxBytes: status.rxBytes, at: Date()) {
        case .wentDown:
            NSLog("Tunnel: keine Antwort mehr")
            state = .down
        case .recovered:
            state = .up
            resetConnections(reason: "Tunnel wieder da")
        case .none:
            break
        }
    }
}
```

`UniFiCameraPopup/Services/Tunnel/ConnectionRouter.swift`:
```swift
import AppKit
import Foundation
import Network
import ProtectKit

/// Decides whether the app reaches the console directly or through the in-app
/// tunnel, and maps API host and stream URLs accordingly.
///
/// Automatic mode: a short TLS probe of the configured console address. Only an
/// answer with the pinned certificate counts as "at home" – a foreign router on
/// the same address (192.168.1.1 in a hotel) does not.
@MainActor
final class ConnectionRouter: ObservableObject {
    static let shared = ConnectionRouter()
    /// Posted after the route changed; `ProtectSession` is already reconnected then.
    static let routeDidChangeNotification = Notification.Name("ConnectionRouter.routeDidChange")

    @Published private(set) var route: ProtectRoute = .direct
    @Published private(set) var isTesting = false
    @Published private(set) var testOutcome: TunnelTestOutcome?

    private let settings = SettingsStore.shared
    private let store = TunnelStore.shared
    private let tunnel = TunnelController.shared
    private let pathMonitor = NWPathMonitor()
    private var networkKind: NetworkKind = .other
    private var lastPathSignature: String?
    private var pending: Task<Void, Never>?
    private var recheck: Task<Void, Never>?
    private var evaluatedHost: String?
    private var lastFailureEvaluation = Date.distantPast
    private var wakeObserver: NSObjectProtocol?
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        tunnel.networkKind = { [weak self] in self?.networkKind ?? .other }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let kind = Self.kind(of: path)
            let signature = "\(path.status)|\(path.availableInterfaces.map(\.name).joined(separator: ","))|\(path.isExpensive)"
            Task { @MainActor in self?.pathChanged(kind: kind, signature: signature) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "ConnectionRouter.path"))
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.tunnel.resetConnections(reason: "Ruhezustand beendet")
                self?.scheduleEvaluation(reason: "Aufwachen", delay: 2)
            }
        }
        scheduleEvaluation(reason: "Start", delay: 0)
    }

    // MARK: Mapping

    /// The host `ProtectClient` connects to for the configured console.
    func apiHost(for consoleHost: String) -> String {
        if consoleHost == settings.protectHost, consoleHost != evaluatedHost {
            scheduleEvaluation(reason: "Konsole geändert", delay: 0)
        }
        guard route == .tunnel,
              let target = ForwardURL.apiTarget(consoleHost: consoleHost),
              let port = tunnel.localPort(for: target) else { return consoleHost }
        return ForwardURL.localHost(port: port)
    }

    /// The URL VLC opens for a stream URL from Protect (or a manual one).
    func playableStreamURL(_ original: String) -> String {
        guard route == .tunnel,
              let target = ForwardURL.streamTarget(original),
              let port = tunnel.localPort(for: target),
              let local = ForwardURL.rewrite(original, localPort: port) else { return original }
        return local
    }

    // MARK: Triggers

    /// The events socket dropped. Rate-limited: the console may simply be rebooting.
    func noteConnectionFailure() {
        guard Date().timeIntervalSince(lastFailureEvaluation) > 30 else { return }
        lastFailureEvaluation = Date()
        scheduleEvaluation(reason: "Verbindung verloren", delay: 0)
    }

    /// Tunnel imported, replaced or removed, or „Tunnel verwenden“ changed.
    func configurationChanged() {
        scheduleEvaluation(reason: "Einstellung geändert", delay: 0)
    }

    /// Imports a dropped or picked file and re-evaluates the route on success.
    func importTunnel(data: Data, fileName: String) -> Result<TunnelImporter.Outcome, TunnelImporter.Failure> {
        let result = TunnelImporter.importData(data, fileName: fileName)
        if case .success = result { tunnel.stop(); configurationChanged() }
        return result
    }

    /// Imports pasted text and re-evaluates the route on success.
    func importTunnel(text: String) -> Result<TunnelImporter.Outcome, TunnelImporter.Failure> {
        let result = TunnelImporter.importData(Data(text.utf8), fileName: TunnelImporter.pastedFileName)
        if case .success = result { tunnel.stop(); configurationChanged() }
        return result
    }

    func removeTunnel() {
        store.remove()
        testOutcome = nil
        configurationChanged()
    }

    /// „Jetzt testen“: tunnel up, handshake, console answers with the pinned certificate.
    func testNow() async {
        guard !isTesting else { return }
        isTesting = true
        testOutcome = nil
        defer {
            isTesting = false
            if route == .direct { tunnel.stop() }
        }
        guard let target = ForwardURL.apiTarget(consoleHost: settings.protectHost) else {
            testOutcome = .noConsole
            return
        }
        guard await tunnel.start() else {
            if case .failed(let reason) = tunnel.state { testOutcome = .startFailed(reason) }
            else { testOutcome = .startFailed("unbekannter Fehler") }
            return
        }
        guard await tunnel.waitForHandshake(timeout: 10) else {
            testOutcome = .noHandshake(endpoint: store.summary?.endpoint ?? "der Gegenstelle")
            return
        }
        guard let port = tunnel.localPort(for: target) else {
            testOutcome = .consoleSilent(host: target.host)
            return
        }
        do {
            let fingerprint = try await ProtectClient.probeFingerprint(host: ForwardURL.localHost(port: port), timeout: 5)
            switch DirectReachability.from(presentedFingerprint: fingerprint, pinned: settings.protectCertificateFingerprint) {
            case .console: testOutcome = .ok
            case .otherDevice, .unreachable: testOutcome = .otherDevice
            }
        } catch {
            testOutcome = .consoleSilent(host: target.host)
        }
    }

    // MARK: Evaluation

    private nonisolated static func kind(of path: NWPath) -> NetworkKind {
        // An iPhone hotspot is Wi-Fi but "expensive": show it as Mobilfunk.
        if path.usesInterfaceType(.cellular) || path.isExpensive { return .cellular }
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.wiredEthernet) { return .ethernet }
        return .other
    }

    private func pathChanged(kind: NetworkKind, signature: String) {
        networkKind = kind
        guard signature != lastPathSignature else { return }
        let first = lastPathSignature == nil
        lastPathSignature = signature
        guard !first else { return }  // start() evaluates already
        Task { await tunnel.networkChanged() }
        // Give DHCP and DNS a moment before probing the console.
        scheduleEvaluation(reason: "Netzwerkwechsel", delay: 2)
    }

    private func scheduleEvaluation(reason: String, delay: TimeInterval) {
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            await self?.evaluate(reason: reason)
        }
    }

    private func evaluate(reason: String) async {
        let consoleHost = settings.protectHost
        evaluatedHost = consoleHost
        guard settings.isProtectConfigured else {
            await apply(.direct)
            return
        }
        let mode = store.mode
        let hasTunnel = store.hasConfiguration
        var direct = DirectReachability.console
        if RouteDecision.needsProbe(mode: mode, hasTunnel: hasTunnel) {
            let fingerprint = try? await ProtectClient.probeFingerprint(host: consoleHost, timeout: 3)
            direct = DirectReachability.from(presentedFingerprint: fingerprint,
                                             pinned: settings.protectCertificateFingerprint)
        }
        // A newer evaluation or another console replaced this one meanwhile.
        guard !Task.isCancelled, consoleHost == settings.protectHost else { return }
        let wanted = RouteDecision.decide(mode: mode, hasTunnel: hasTunnel, direct: direct)
        NSLog("Route (\(reason)): \(wanted), direkt: \(direct)")
        await apply(wanted)
    }

    private func apply(_ wanted: ProtectRoute) async {
        if wanted == .tunnel {
            let wasRunning = tunnel.isStarted
            guard await tunnel.start() else {
                if route != .direct { setRoute(.direct) }
                // Keep trying while the tunnel is wanted (offline, endpoint not resolvable).
                scheduleEvaluation(reason: "Tunnel-Neustart", delay: 30)
                return
            }
            // A (re)started tunnel has new local ports: the client must reconnect.
            if route != .tunnel || !wasRunning { setRoute(.tunnel) }
            scheduleRecheck()
            return
        }
        if route != .direct { setRoute(.direct) }
        if !isTesting { tunnel.stop() }
        scheduleRecheck()
    }

    /// On the tunnel in automatic mode, look for the console directly every 5 minutes:
    /// a short console outage at home must not leave the app on the tunnel for good.
    private func scheduleRecheck() {
        recheck?.cancel()
        recheck = nil
        guard route == .tunnel, store.mode == .automatic else { return }
        recheck = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000_000)
            guard !Task.isCancelled else { return }
            self?.scheduleEvaluation(reason: "Regelmäßige Prüfung", delay: 0)
        }
    }

    private func setRoute(_ new: ProtectRoute) {
        route = new
        NSLog("Route jetzt: \(new == .tunnel ? "Tunnel" : "direkt")")
        ProtectSession.shared.reconnect()
        NotificationCenter.default.post(name: Self.routeDidChangeNotification, object: nil)
    }
}
```

```bash
python3 UniFiCameraPopup/scripts/pbxproj-add-files.py Services/Tunnel 10 TunnelStore.swift TunnelImporter.swift TunnelController.swift ConnectionRouter.swift
```
Expected: vier Zeilen `added … D41000000000000000000010` … `…13`.

- [ ] **Step 2: `ProtectSession` – API-Host über den Router**

In `UniFiCameraPopup/Services/ProtectSession.swift` in `reconnect()`:
```swift
// alt
        let host = settings.protectHost
        client = ProtectClient(
            host: host,
// neu
        let host = settings.protectHost
        client = ProtectClient(
            // Unterwegs: 127.0.0.1:<forward>. The pin below stays the console's.
            host: ConnectionRouter.shared.apiHost(for: host),
```
Die Prüfung im `onNewFingerprint`-Block vergleicht weiter mit `host` (der Konsolenadresse) – so bleibt der Pin der Konsole zugeordnet, nie dem Forward.

- [ ] **Step 3: `ProtectEventService` – Neuaufbau nach Tunnel-Reset, Abbrüche melden**

In `UniFiCameraPopup/Services/ProtectEventService.swift`:
1. Nach `    private var wakeObserver: NSObjectProtocol?` einfügen:
```swift
    private var tunnelResetObserver: NSObjectProtocol?
```
2. In `start()` direkt vor dem abschließenden `startLoop()` einfügen:
```swift
        // After a tunnel outage the old socket may hang forever: reconnect at once.
        tunnelResetObserver = NotificationCenter.default.addObserver(
            forName: TunnelController.connectionsResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.restartLoop() }
        }
```
3. In `stop()` nach dem Block, der `wakeObserver` entfernt, einfügen:
```swift
        if let tunnelResetObserver {
            NotificationCenter.default.removeObserver(tunnelResetObserver)
            self.tunnelResetObserver = nil
        }
```
4. In `run()`:
```swift
// alt
            ws.cancel(with: .goingAway, reason: nil)
            status = .disconnected
            let delay = backoff.next()
// neu
            ws.cancel(with: .goingAway, reason: nil)
            status = .disconnected
            // Maybe the Mac left home (or came back): let the router check the route.
            ConnectionRouter.shared.noteConnectionFailure()
            let delay = backoff.next()
```

- [ ] **Step 4: VLC – RTSP über den Router, Neustart bei Routen- oder Tunnelwechsel**

In `UniFiCameraPopup/Views/VLCPlayerView.swift` (`VLCPlayerContainerView`):
1. Nach `    private var pendingURL: String?` einfügen:
```swift
    /// URL as handed in (direct console address); mapped per playback start, so a
    /// route change or a tunnel reset can replay the same stream on the new path.
    private var originalURL: String?
    private var routeObservers: [NSObjectProtocol] = []
```
2. `setup()` endet bisher mit `addSubview(videoView)\n    }`. Ersetzen durch:
```swift
        addSubview(videoView)
        for name in [ConnectionRouter.routeDidChangeNotification, TunnelController.connectionsResetNotification] {
            routeObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.replay() }
            })
        }
    }

    deinit {
        routeObservers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Restarts the current stream (new route, or relayed connections were reset).
    private func replay() {
        guard let originalURL, window != nil else { return }
        NSLog("VLC: Stream neu verbinden")
        beginPlayback(urlString: originalURL)
    }
```
3. In `play(urlString:soundEnabled:onFirstFrame:)` nach `        hasNotifiedFirstFrame = false` einfügen: `        originalURL = urlString`
4. In `beginPlayback(urlString:)`: `guard let url = URL(string: urlString) else {` → `guard let url = URL(string: ConnectionRouter.shared.playableStreamURL(urlString)) else {`
5. In `stop()` nach `        pendingURL = nil` einfügen: `        originalURL = nil`

- [ ] **Step 5: Prüfaufrufe beim Einrichten und Neuvertrauen über den Router**

```bash
grep -rn "ProtectClient.probeFingerprint(host:\|ProtectClient(host: host" UniFiCameraPopup/Views
```
Expected: drei Treffer – `OnboardingView.swift` (`probeNewCertificate`, `checkKey`) und eine Stelle in den Einstellungen (Phase 1: `SettingsView.swift`, nach Phase 2 der Reiter Allgemein). Jeweils:
- `ProtectClient.probeFingerprint(host: host)` → `ProtectClient.probeFingerprint(host: ConnectionRouter.shared.apiHost(for: host))`
- `let client = ProtectClient(host: host, apiKey: apiKey,` → `let client = ProtectClient(host: ConnectionRouter.shared.apiHost(for: host), apiKey: apiKey,`

Alle drei laufen schon auf dem MainActor (`@MainActor`-Modell bzw. View). Unterwegs gehen Neuvertrauen und Schlüsselprüfung damit durch den Tunnel; zu Hause ändert sich nichts.

- [ ] **Step 6: Router beim App-Start**

In `UniFiCameraPopup/AppDelegate.swift`, `setupWebSocket()`:
```swift
// alt
        ProtectSession.shared.reconnect()
        protectEvents.start()
// neu
        // Route first: it decides whether ProtectSession talks to the console directly or via the tunnel.
        ConnectionRouter.shared.start()
        ProtectSession.shared.reconnect()
        protectEvents.start()
```

- [ ] **Step 7: Lint, Build**

Run: `plutil -lint …` → `OK`; Build-Befehl → `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Sichtprüfung zu Hause (noch ohne Tunnel)**

Installierte App beenden, `open "$DD/Build/Products/Debug/UniFi Camera Popup.app"`, Log-Befehl starten.
Expected: `Route (Start): direct, direkt: console`; Ereignisse kommen wie bisher („Protect: verbunden“); ein Test-Popup spielt (`VLC: starting playback for 192.168.…`). Kein Eintrag `Tunnel:`.

- [ ] **Step 9: Commit**

```bash
git add UniFiCameraPopup/Services/Tunnel UniFiCameraPopup/Services/ProtectSession.swift UniFiCameraPopup/Services/ProtectEventService.swift UniFiCameraPopup/Views/VLCPlayerView.swift UniFiCameraPopup/AppDelegate.swift UniFiCameraPopup/Views/Onboarding/OnboardingView.swift UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj
git add $(grep -rln "ConnectionRouter.shared.apiHost(for: host)" UniFiCameraPopup/Views)   # Onboarding + Einstellungsdatei aus Step 5
git diff --cached --name-only | grep AppConfig   # Erwartet: leer
git commit -m "feat(tunnel): automatic route, tunnel lifecycle and reconnect after outages" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Einrichtung Schritt 6, Ablagefeld, Anleitung

**Files:**
- Create: `docs/design/einrichtung-unterwegs.md`
- Create: `UniFiCameraPopup/Assets.xcassets/Icons/fileDownload.imageset/` (SVG + `Contents.json`)
- Modify: `UniFiCameraPopup/Views/Design/DesignComponents.swift` (`TemplateIcon` + `fileDownload`)
- Create: `UniFiCameraPopup/Views/Tunnel/WireGuardImport.swift`, `WireGuardGuideView.swift`, `OnboardingTunnelStep.swift`
- Modify: `UniFiCameraPopup/Views/Onboarding/OnboardingView.swift`, `project.pbxproj`

**Interfaces:**
- Consumes: `ConnectionRouter.importTunnel(data:fileName:)`, `.importTunnel(text:)`, `TunnelStore.shared` (Task 7); `Tokens`, `TemplateIcon`, `LinkButtonStyle` (Phase 2); `WireGuardFile` (Task 5).
- Produces: `enum ImportFeedback: Equatable { imported(endpoint: String, warning: String?), failed(String); init(_ result:) }`, `@MainActor enum WireGuardImport { static let menuTitles; static func run(menuIndex:) -> ImportFeedback?; static func pickFile() -> ImportFeedback?; static func importFile(_: URL) -> ImportFeedback; static func importClipboard() -> ImportFeedback }`, `struct WireGuardDropZone: View { let onFeedback: (ImportFeedback) -> Void }`, `struct ImportFeedbackView: View { let feedback: ImportFeedback }`, `struct WireGuardGuideView: View`, `struct OnboardingTunnelStep: View { let onLater, onDone: () -> Void }`, `OnboardingModel.Step.travel`.

- [ ] **Step 1: Spezifikation ablegen**

Den Codeblock `docs/design/einrichtung-unterwegs.md` aus dem Abschnitt „Design-Spezifikation“ dieses Plans unverändert (ohne die ```-Zeilen) nach `docs/design/einrichtung-unterwegs.md` schreiben. Gegenlesen: `grep -n "6 Unterwegs" -A12 docs/superpowers/specs/phase2-4/design/Main.dc.html` – jede Zahl (64, 20px, 12px, 1.5, 74, 12, 2px dashed, 10, 22, 13px 600, 150, 9px) steht in der Datei.

- [ ] **Step 2: Symbol aus der Vorlage exportieren**

```bash
ICONS=UniFiCameraPopup/Assets.xcassets/Icons
mkdir -p "$ICONS/fileDownload.imageset"
printf '%s\n' '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#000000" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3H6v18h12V7z"/><path d="M14 3v4h4"/><path d="M12 11v6M9.5 14.5L12 17l2.5-2.5"/></svg>' > "$ICONS/fileDownload.imageset/fileDownload.svg"
printf '{\n  "images" : [ { "filename" : "fileDownload.svg", "idiom" : "universal" } ],\n  "info" : { "author" : "xcode", "version" : 1 },\n  "properties" : { "preserves-vector-representation" : true, "template-rendering-intent" : "template" }\n}\n' > "$ICONS/fileDownload.imageset/Contents.json"
```

In `UniFiCameraPopup/Views/Design/DesignComponents.swift`, `enum TemplateIcon`, nach `    case actionDoor, actionBulb, actionHouse, actionBolt` die Zeile `    case fileDownload` einfügen.

- [ ] **Step 3: Ablagefeld, Datei-/Zwischenablage-Import, Rückmeldung**

`UniFiCameraPopup/Views/Tunnel/WireGuardImport.swift`:
```swift
import AppCore
import AppKit
import ProtectKit
import SwiftUI
import UniformTypeIdentifiers

/// What the last import attempt showed to the user.
enum ImportFeedback: Equatable {
    case imported(endpoint: String, warning: String?)
    case failed(String)

    init(_ result: Result<TunnelImporter.Outcome, TunnelImporter.Failure>) {
        switch result {
        case .success(let outcome): self = .imported(endpoint: outcome.summary.endpoint, warning: outcome.warning)
        case .failure(let failure): self = .failed(failure.localizedDescription)
        }
    }
}

/// File picker, drop and clipboard paths into `ConnectionRouter.importTunnel`.
@MainActor
enum WireGuardImport {
    static let menuTitles = ["Datei auswählen …", "Aus Zwischenablage einfügen"]

    /// Runs the entry of `menuTitles` at `index`.
    static func run(menuIndex index: Int) -> ImportFeedback? {
        index == 0 ? pickFile() : importClipboard()
    }

    static func pickFile() -> ImportFeedback? {
        let panel = NSOpenPanel()
        panel.message = "WireGuard-Datei (.conf) auswählen"
        panel.allowedContentTypes = [UTType(filenameExtension: "conf") ?? .plainText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return importFile(url)
    }

    static func importFile(_ url: URL) -> ImportFeedback {
        // Never read a huge file into memory just to reject it.
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= WireGuardFile.maxBytes else {
            return .failed(WireGuardFile.Problem.tooLarge.localizedDescription)
        }
        guard let data = try? Data(contentsOf: url) else {
            return .failed("Die Datei lässt sich nicht lesen.")
        }
        return ImportFeedback(ConnectionRouter.shared.importTunnel(data: data, fileName: url.lastPathComponent))
    }

    static func importClipboard() -> ImportFeedback {
        ImportFeedback(ConnectionRouter.shared.importTunnel(text: NSPasteboard.general.string(forType: .string) ?? ""))
    }
}

/// „WireGuard-Datei hier ablegen“ (Vorlage Main 6): 74 hoch, Radius 12, 2 pt gestrichelt
/// `dropBorder`, Fläche `accSoft`, Symbol 22 + Abstand 10 + Text 13/600 `accText`.
/// Click opens the file picker; right click also offers the clipboard.
struct WireGuardDropZone: View {
    let onFeedback: (ImportFeedback) -> Void
    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 10) {
            TemplateIcon.fileDownload.image(size: 22)
            Text("WireGuard-Datei hier ablegen")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(Tokens.accText.color)
        .frame(maxWidth: .infinity)
        .frame(height: 74)
        .background(RoundedRectangle(cornerRadius: 12).fill(Tokens.accSoft.color))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isTargeted ? Tokens.accent.color : Tokens.dropBorder.color,
                              style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            if let feedback = WireGuardImport.pickFile() { onFeedback(feedback) }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in onFeedback(WireGuardImport.importFile(url)) }
            }
            return true
        }
        .contextMenu {
            ForEach(Array(WireGuardImport.menuTitles.enumerated()), id: \.offset) { index, title in
                Button(title) {
                    if let feedback = WireGuardImport.run(menuIndex: index) { onFeedback(feedback) }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Öffnet die Dateiauswahl. Rechtsklick: aus der Zwischenablage einfügen.")
    }
}

/// One line under the drop zone, styled like „Passt. 4 Kameras gefunden.“ (Main 3):
/// 12 pt, Häkchen 14, Abstand 6, `ok`. Hints and errors in system orange (as in Phase 2).
/// Always a single line, so Einrichtung step 6 keeps fitting into 560 × 420.
struct ImportFeedbackView: View {
    let feedback: ImportFeedback

    var body: some View {
        Group {
            switch feedback {
            case .imported(let endpoint, nil):
                HStack(spacing: 6) {
                    TemplateIcon.check.image(size: 14)
                    Text("Passt. Gegenstelle: \(endpoint)")
                }
                .foregroundStyle(Tokens.ok.color)
            case .imported(_, let warning?):
                Text(warning).foregroundStyle(Color(nsColor: .systemOrange))
            case .failed(let message):
                Text(message).foregroundStyle(Color(nsColor: .systemOrange))
            }
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .truncationMode(.middle)
        .help(helpText)
    }

    /// Full text on hover, in case the line is truncated.
    private var helpText: String {
        switch feedback {
        case .imported(let endpoint, let warning): return warning ?? "Gegenstelle: \(endpoint)"
        case .failed(let message): return message
        }
    }
}
```

- [ ] **Step 4: Anleitung**

`UniFiCameraPopup/Views/Tunnel/WireGuardGuideView.swift`:
```swift
import AppCore
import SwiftUI

/// General WireGuard guide, opened from „Ausführliche Anleitung öffnen“ (Einrichtung)
/// and „Anleitung: WireGuard auf dem UniFi-Gateway einrichten“ (Reiter „Unterwegs“).
struct WireGuardGuideView: View {
    @Environment(\.dismiss) private var dismiss

    static let steps: [(title: String, text: String)] = [
        ("WireGuard-Server anlegen",
         "Öffne in der UniFi-Network-Oberfläche Einstellungen → VPN → VPN-Server und lege einen Server vom Typ „WireGuard“ an. "
            + "Andere Router (z. B. FRITZ!Box) bieten das meist unter „VPN“ oder „Fernzugang“."),
        ("Client für diesen Mac hinzufügen",
         "Füge dem Server einen Client (Peer) hinzu, etwa „MacBook Camera Popup“. Lege für jedes Gerät einen eigenen Client an."),
        ("Von außen erreichbar machen",
         "Der Server braucht eine feste öffentliche Adresse oder einen DynDNS-Namen. Ein UniFi-Gateway öffnet seinen Port "
            + "(Standard: UDP 51820) selbst. Sitzt davor ein weiterer Router, leite dort UDP 51820 an das Gateway weiter."),
        ("Datei herunterladen",
         "Lade die Konfiguration des Clients als .conf-Datei herunter – bei UniFi über „Herunterladen“ beim Client."),
        ("In der App ablegen",
         "Zieh die Datei auf „WireGuard-Datei hier ablegen“ oder wähle sie über „Ersetzen …“ aus. Der Schlüssel liegt danach "
            + "im Schlüsselbund dieses Macs und nie im Konfigurations-Export."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("WireGuard einrichten")
                .font(.system(size: 20, weight: .bold))
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Tokens.accent.color))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(step.title).font(.system(size: 13, weight: .semibold))
                                Text(step.text)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Tokens.muted.color)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Text("Die App nutzt den Tunnel nur für ihre eigenen Verbindungen zur Konsole. Dein übriger Datenverkehr bleibt, "
                         + "wie er ist – ein VPN in den Systemeinstellungen ist nicht nötig. Zu Hause verbindet sich die App direkt.")
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.muted.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .padding(24)
            }
            Divider()
            HStack {
                Spacer()
                Button("Schließen") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 500)
    }
}
```

- [ ] **Step 5: Schritt 6**

`UniFiCameraPopup/Views/Tunnel/OnboardingTunnelStep.swift`:
```swift
import AppCore
import SwiftUI

/// Einrichtung, Schritt 6 „Auch unterwegs?“ (Vorlage Main 6). Abstand 11 wie in der Vorlage.
struct OnboardingTunnelStep: View {
    let onLater: () -> Void
    let onDone: () -> Void
    @ObservedObject private var store = TunnelStore.shared
    @State private var feedback: ImportFeedback?
    @State private var showGuide = false

    var body: some View {
        VStack(spacing: 11) {
            TemplateIcon.tabRemote.image(size: 30)
                .foregroundStyle(Tokens.accText.color)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Tokens.accSoft.color))
            Text("Auch unterwegs?")
                .font(.system(size: 20, weight: .bold))
            Text("Lege auf deinem UniFi-Gateway einen WireGuard-Server an, füge einen Client für diesen Mac hinzu und lade dessen Datei herunter. Die App nutzt den Tunnel nur für sich.")
                .font(.system(size: 12))
                .lineSpacing(3)
                .foregroundStyle(Tokens.muted.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            WireGuardDropZone { feedback = $0 }
            if let feedback {
                ImportFeedbackView(feedback: feedback)
            } else if let endpoint = store.summary?.endpoint {
                ImportFeedbackView(feedback: .imported(endpoint: endpoint, warning: nil))
            }
            Button("Ausführliche Anleitung öffnen") { showGuide = true }
                .buttonStyle(LinkButtonStyle())
            Spacer()
            HStack(spacing: 10) {
                Button(action: onLater) { Text("Später").frame(width: 126) }
                    .controlSize(.large)
                Button(action: onDone) { Text("Fertig").frame(width: 126) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .sheet(isPresented: $showGuide) { WireGuardGuideView() }
    }
}
```

In `UniFiCameraPopup/Views/Onboarding/OnboardingView.swift`:
1. `enum Step: Int, CaseIterable { case welcome, console, key, cameras, triggers }` → `enum Step: Int, CaseIterable { case welcome, console, key, cameras, triggers, travel }`
2. Im `switch model.step` nach `            case .triggers: triggersStep` einfügen:
```swift
            case .travel: OnboardingTunnelStep(onLater: { model.finish() }, onDone: { model.finish() })
```
3. In `triggersStep`: `primary("Fertig") { model.finish() }` → `primary("Weiter") { model.step = .travel }`

Die Punkte unter den Schritten zählen automatisch sechs (`Step.allCases`).

```bash
python3 UniFiCameraPopup/scripts/pbxproj-add-files.py Views/Tunnel 20 WireGuardImport.swift WireGuardGuideView.swift OnboardingTunnelStep.swift
```

- [ ] **Step 6: Lint, Build, Symbol im Katalog**

Run: `plutil -lint …` → `OK`; Build-Befehl → `** BUILD SUCCEEDED **`;
`xcrun --sdk macosx assetutil --info "$DD/Build/Products/Debug/UniFi Camera Popup.app/Contents/Resources/Assets.car" | grep -c '"Name" : "fileDownload"'` → `≥ 1`.

- [ ] **Step 7: Sichtprüfung und Bildvergleich Schritt 6**

Test-Datei erzeugen (die Test-Heimat schreibt sie beim Start und wird gleich wieder beendet):
```bash
wgtunnel/scripts/go.sh build -o "${TMPDIR:-/tmp}/wghome" ./cmd/home
"${TMPDIR:-/tmp}/wghome" -port 51999 -out "${TMPDIR:-/tmp}/test-unterwegs.conf" & HP=$!; sleep 1; kill "$HP"
grep -c "PrivateKey" "${TMPDIR:-/tmp}/test-unterwegs.conf"   # Erwartet: 1
```
Installierte App beenden, Debug-App starten, Menü (Rechtsklick) „Einrichtung …“, bis Schritt 6 („Weiter“ in Schritt 5).
Expected:
- Schritt 5 zeigt „Weiter“, Schritt 6 sechs Punkte, der sechste in Akzentfarbe.
- `test-unterwegs.conf` auf das Feld ziehen → Rand beim Darüberziehen `accent`, danach „Passt. Gegenstelle: 127.0.0.1:51999“ in Grün (liegt die eingerichtete Konsole nicht in 192.168.1.0/24, stattdessen orange „Achtung: Konsole … liegt nicht in „AllowedIPs“.“ – beides richtig).
- Ein PNG ablegen → einzeilig orange „Keine gültige WireGuard-Datei: …“ bzw. „Die Datei ist keine Textdatei.“; die vorher abgelegte Datei bleibt (Reiter „Unterwegs“ zeigt sie weiter).
- Rechtsklick → „Aus Zwischenablage einfügen“ mit leerer Zwischenablage → „Die Datei ist leer.“
- „Ausführliche Anleitung öffnen“ → Sheet „WireGuard einrichten“, „Schließen“ schließt.
- Bildvergleich (CLAUDE.md, Regel 2): Board 6 des veröffentlichten Artefakts im angemeldeten Browser bei 100 % aufnehmen (Phase 2 klärt den Weg, `support.js` fehlt lokal), das Fenster mit `screencapture -o -l "$(osascript -e 'tell application "System Events" to get id of window 1 of process "UniFi Camera Popup"' 2>/dev/null)" "${TMPDIR:-/tmp}/schritt6.png"` (falls die Fenster-ID so nicht kommt: `screencapture -w`) aufnehmen, beide nebeneinander gegen `docs/design/einrichtung-unterwegs.md` prüfen (Abstände, Größen, Farben hell und dunkel). Abweichungen außerhalb der Liste „Abweichungen“ beheben.
- Aufräumen: den Test-Tunnel im Reiter „Unterwegs“ (Task 9) bzw. jetzt mit `security delete-generic-password -s com.snackbits.UniFiCameraPopup.wireguard-config; defaults delete com.snackbits.UniFiCameraPopup unifi.camera.popup.tunnel` entfernen.

- [ ] **Step 8: Commit**

```bash
git add docs/design/einrichtung-unterwegs.md UniFiCameraPopup/Assets.xcassets/Icons/fileDownload.imageset UniFiCameraPopup/Views/Design/DesignComponents.swift UniFiCameraPopup/Views/Tunnel UniFiCameraPopup/Views/Onboarding/OnboardingView.swift UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj
git diff --cached --name-only | grep AppConfig   # Erwartet: leer
git commit -m "feat(onboarding): step 6 – WireGuard file import and guide" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Reiter „Unterwegs“, Status im Menü, „Über“ mit Lizenzen, „Was ist neu“

**Files:**
- Modify: `docs/design/einstellungen-unterwegs.md` (Phase-4-Fassung)
- Create: `UniFiCameraPopup/Views/Tunnel/TunnelSettingsView.swift`
- Modify: `UniFiCameraPopup/Views/Settings/SoundAndRemoteTabs.swift` (Gerüst „Unterwegs“, Phase 2)
- Modify: Menüleisten-Panel aus Phase 2 (Chip „Zu Hause“), `UniFiCameraPopup/AppDelegate.swift` (Statuszeile)
- Modify: `UniFiCameraPopup/Views/HelpView.swift`, `UniFiCameraPopup/Services/WhatsNewService.swift`, `project.pbxproj`

**Interfaces:**
- Consumes: `TunnelStore`, `ConnectionRouter`, `TunnelController` (Task 7); `WireGuardDropZone`, `ImportFeedbackView`, `WireGuardImport`, `WireGuardGuideView` (Task 8); `Card`, `CardDivider`, `CardRow`, `FixedLabelRow`, `FieldButtonStyle`, `LinkButtonStyle`, `PopUpField`, `MenuPresenter`, `ViewAnchor`, `AnchorView`, `TemplateIcon.shieldCheck`, `Tokens`, `DisplayText.dayAndTime` (Phase 2); `TunnelText`, `TunnelPhase` (Task 5); `ThirdPartyNotices.txt` (Task 3/6).
- Produces: `struct TunnelSettingsView: View` (Inhalt des Reiters, füllt die Fläche unter der Reiterleiste).

- [ ] **Step 1: Spezifikation aktualisieren**

`docs/design/einstellungen-unterwegs.md` vollständig durch den Codeblock „`docs/design/einstellungen-unterwegs.md` (Phase-4-Fassung)“ aus dem Abschnitt „Design-Spezifikation“ ersetzen.

- [ ] **Step 2: Reiter-Inhalt**

`UniFiCameraPopup/Views/Tunnel/TunnelSettingsView.swift`:
```swift
import AppCore
import ProtectKit
import SwiftUI

/// Content of the settings tab „Unterwegs“ (Vorlage S6, docs/design/einstellungen-unterwegs.md).
struct TunnelSettingsView: View {
    @ObservedObject private var store = TunnelStore.shared
    @ObservedObject private var router = ConnectionRouter.shared
    @ObservedObject private var tunnel = TunnelController.shared
    @StateObject private var replaceAnchor = ViewAnchor()
    @State private var feedback: ImportFeedback?
    @State private var showGuide = false
    @State private var confirmRemove = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.hasConfiguration {
                statusCard
                details
            } else {
                emptyState
            }
            if let feedback {
                ImportFeedbackView(feedback: feedback)
            }
            if let outcome = router.testOutcome {
                Text(outcome.message)
                    .font(.system(size: 12))
                    .foregroundStyle(outcome == .ok ? Tokens.ok.color : Color(nsColor: .systemOrange))
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .foregroundStyle(Tokens.fg.color)
        .padding(.horizontal, 40)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showGuide) { WireGuardGuideView() }
        .confirmationDialog("Tunnel entfernen?", isPresented: $confirmRemove) {
            Button("Entfernen", role: .destructive) {
                router.removeTunnel()
                feedback = nil
            }
        } message: {
            Text("Die WireGuard-Datei wird aus dem Schlüsselbund gelöscht. Unterwegs ist die Konsole dann nicht mehr erreichbar.")
        }
    }

    private var phase: TunnelPhase {
        TunnelPhase.from(mode: store.mode, route: router.route, state: tunnel.state)
    }

    /// 1. Statusfläche: Abstand 14, Innenabstand 14/16, Radius 12, `accSoft`.
    private var statusCard: some View {
        let text = TunnelText.status(phase)
        return HStack(spacing: 14) {
            TemplateIcon.shieldCheck.image(size: 20)
                .foregroundStyle(Color.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Tokens.accent.color))
            VStack(alignment: .leading, spacing: 2) {
                Text(text.title).font(.system(size: 14, weight: .bold))
                Text(text.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.muted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(router.isTesting ? "Teste …" : "Jetzt testen") {
                Task { await router.testNow() }
            }
            .buttonStyle(FieldButtonStyle(fontSize: 12, vertical: 4, horizontal: 12))
            .disabled(router.isTesting)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Tokens.accSoft.color))
    }

    /// 2. Karte Radius 10, Zeilen 10/14, Beschriftung 140 breit.
    private var details: some View {
        Card {
            FixedLabelRow(title: "Konfiguration", width: 140, vertical: 10, horizontal: 14) {
                Text(store.fileName ?? "–")
                    .foregroundStyle(Tokens.muted.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Ersetzen …") {
                    guard let view = replaceAnchor.view else { return }
                    MenuPresenter.popUp(titles: WireGuardImport.menuTitles, selectedIndex: nil, in: view) { index in
                        if let result = WireGuardImport.run(menuIndex: index) { feedback = result }
                    }
                }
                .buttonStyle(FieldButtonStyle())
                .background(AnchorView(anchor: replaceAnchor))
            }
            CardDivider()
            FixedLabelRow(title: "Gegenstelle", width: 140, vertical: 10, horizontal: 14) {
                Text(store.summary?.endpoint ?? "–")
                    .foregroundStyle(Tokens.muted.color)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            CardDivider()
            FixedLabelRow(title: "Letzte Verbindung", width: 140, vertical: 10, horizontal: 14) {
                Text(lastConnectionText)
                    .foregroundStyle(Tokens.muted.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            CardDivider()
            CardRow(title: "Tunnel verwenden") {
                PopUpField(
                    selection: Binding(
                        get: { store.mode },
                        set: { store.mode = $0; router.configurationChanged() }
                    ),
                    options: TunnelMode.allCases.map { (value: $0, title: $0.label) }
                )
            }
        }
    }

    private var lastConnectionText: String {
        guard let last = store.lastConnection else { return "noch nie" }
        return TunnelText.lastConnection(dayAndTime: DisplayText.dayAndTime(last.date, now: Date()), via: last.via)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Noch nicht eingerichtet").font(.system(size: 14, weight: .bold))
                Text("Lege die WireGuard-Datei deines Gateways hier ab. Die App nutzt den Tunnel nur für sich.")
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.muted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            WireGuardDropZone { feedback = $0 }
        }
    }

    /// 3. Zeile verteilt: Anleitung (12, `accText`) · Tunnel entfernen (12, `muted`).
    private var footer: some View {
        HStack {
            Button("Anleitung: WireGuard auf dem UniFi-Gateway einrichten") { showGuide = true }
                .buttonStyle(LinkButtonStyle())
            Spacer()
            if store.hasConfiguration {
                Button("Tunnel entfernen") { confirmRemove = true }
                    .buttonStyle(LinkButtonStyle(color: Tokens.muted))
            }
        }
    }
}
```

```bash
python3 UniFiCameraPopup/scripts/pbxproj-add-files.py Views/Tunnel 23 TunnelSettingsView.swift
```

- [ ] **Step 3: Gerüst aus Phase 2 ersetzen**

```bash
grep -rn "Bereit · gerade zu Hause" UniFiCameraPopup/Views/Settings
grep -n "struct .*: View" UniFiCameraPopup/Views/Settings/SoundAndRemoteTabs.swift
```
Der Treffer liegt im `struct`, das Phase 2 als Gerüst des Reiters „Unterwegs“ angelegt hat (Inhalt unter der Reiterleiste). Dessen `body` wird zu `TunnelSettingsView()`, alle nur von diesem Gerüst benutzten Unteransichten und Beispielwerte („macbook-camera-popup.conf“, „[DEINE-HEIM-ADRESSE]:51820“ …) werden gelöscht. Beispiel, wenn das Gerüst `RemoteTab` heißt:
```swift
/// Reiter „Unterwegs“ (Vorlage S6) – Inhalt in Views/Tunnel/TunnelSettingsView.swift.
struct RemoteTab: View {
    var body: some View {
        TunnelSettingsView()
    }
}
```
Danach: `grep -rn "DEINE-HEIM-ADRESSE\|macbook-camera-popup.conf" UniFiCameraPopup` → keine Treffer.

- [ ] **Step 4: Status „unterwegs“ im Menü**

1. Menüleisten-Panel (Phase 2): `grep -rn '"Zu Hause"' UniFiCameraPopup Packages/AppCore/Sources`
   - Liegt der Treffer in einer SwiftUI-View der App: dort `@ObservedObject private var router = ConnectionRouter.shared` ergänzen und das Literal `"Zu Hause"` durch `TunnelText.connectedChip(viaTunnel: router.route == .tunnel)` ersetzen (`import ProtectKit` ergänzen, falls nötig).
   - Liegt er in `Packages/AppCore` (Funktion, die den Chip-Text aus dem Status bildet): der Funktion einen Parameter `viaTunnel: Bool = false` geben, im verbundenen Fall `viaTunnel ? "Unterwegs" : "Zu Hause"` zurückgeben, in ihrem AppCore-Test `XCTAssertEqual(<Funktion>(<verbunden-Fall>, viaTunnel: true), "Unterwegs")` ergänzen und an der Aufrufstelle in der App `viaTunnel: ConnectionRouter.shared.route == .tunnel` übergeben; die View, die den Chip zeigt, bekommt `@ObservedObject private var router = ConnectionRouter.shared`, damit sie bei Routenwechsel neu zeichnet.
2. Rechtsklick-Menü in `UniFiCameraPopup/AppDelegate.swift`:
   - Nach `    private var isProtectConfigured = false` einfügen:
```swift
    /// Mirrors `ConnectionRouter.shared.route == .tunnel` for the status line.
    private var isViaTunnel = false
```
   - `protectStatusLabel` ersetzen durch:
```swift
    private var protectStatusLabel: String {
        let base = switch protectStatus {
        case .connected: "Protect: verbunden"
        case .connecting: "Protect: verbinde …"
        case .disconnected, .outdated: "Protect: getrennt"
        }
        return isViaTunnel ? "\(base) · unterwegs" : base
    }
```
   - Vor `    private func observeProtectClient() async {` einfügen:
```swift
    private func observeRoute() async {
        // `@Published` emits in `willSet`: use the emitted value, not the property.
        for await route in ConnectionRouter.shared.$route.values {
            isViaTunnel = route == .tunnel
            updateStatusMenu()
        }
    }

```
   - Dort, wo `observeProtectClient()` in einem `Task { … }` gestartet wird, direkt danach ergänzen:
```swift
        Task {
            await observeRoute()
        }
```
   (Hat Phase 2 `protectStatusLabel` umbenannt: die Stelle mit `"Protect: verbunden"` suchen und dort genauso das Suffix anhängen.)

- [ ] **Step 5: Hilfe › „Über“ mit Lizenzen**

In `UniFiCameraPopup/Views/HelpView.swift`:
1. `enum Topic`: nach `        case troubleshooting = "Problemlösung"` → `        case about = "Über"`
2. `icon`: nach `            case .troubleshooting: return "stethoscope"` → `            case .about: return "info.circle"`
3. Im `switch selection` des Inhalts: nach `                        case .troubleshooting: troubleshootingBody` → `                        case .about: aboutBody`
4. `detailHeader`: nach `            header("Problemlösung", subtitle: "Wenn das App-Symbol rot ist.")` einfügen:
```swift
        case .about:
            header("Über", subtitle: "Version und Lizenzen.")
```
5. Vor `    // MARK: - Building blocks` einfügen:
```swift
    // MARK: - Über

    private var aboutBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Camera Popup \(AppConfig.shortVersion) (Build \(AppConfig.buildNumber))")
                .font(.headline)
            Text("Der Tunnel für unterwegs verwendet freie Software: wireguard-go (MIT-Lizenz, © WireGuard LLC), "
                 + "gVisor (Apache-Lizenz 2.0, © The gVisor Authors) und die Go-Laufzeit samt golang.org/x-Bibliotheken "
                 + "(BSD-3-Clause, © The Go Authors) sowie google/btree (Apache-Lizenz 2.0). "
                 + "„WireGuard“ ist eine eingetragene Marke von Jason A. Donenfeld.")
                .fixedSize(horizontal: false, vertical: true)
            Text(Self.thirdPartyNotices)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Full license texts, generated by `wgtunnel/scripts/collect-notices.sh`.
    private static let thirdPartyNotices: String = {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "Lizenztexte fehlen im App-Paket."
        }
        return text
    }()

```
(`AppConfig` wird nur gelesen, nicht geändert.)

- [ ] **Step 6: „Was ist neu“**

In `UniFiCameraPopup/Services/WhatsNewService.swift` im Eintrag `ChangelogEntry(version: "1.2.0", items: [` als letztes Element vor `        ]),` anhängen:
```swift
            "Unterwegs: Mit der WireGuard-Datei deines Gateways erreicht die App deine Kameras auch außer Haus – "
                + "über einen eigenen Tunnel nur für die App, ganz ohne VPN in den Systemeinstellungen.",
```

- [ ] **Step 7: Lint, Build, Tests**

Run: `plutil -lint …` → `OK`; Build-Befehl → `** BUILD SUCCEEDED **`; `(cd Packages/ProtectKit && swift test 2>&1 | tail -1)` und `(cd Packages/AppCore && swift test 2>&1 | tail -1)` → 0 failures.

- [ ] **Step 8: Sichtprüfung und Bildvergleich Reiter „Unterwegs“**

Debug-App (installierte beenden), Einstellungen › „Unterwegs“.
Expected:
- Ohne Datei: „Noch nicht eingerichtet“ + Ablagefeld; Fußzeile nur „Anleitung: …“.
- `test-unterwegs.conf` (Task 8 Step 7) ablegen → Statusfläche „Bereit · gerade zu Hause“, Karte „Konfiguration | test-unterwegs.conf | Ersetzen …“, „Gegenstelle | 127.0.0.1:51999“, „Letzte Verbindung | noch nie“, „Tunnel verwenden | Automatisch ⌃⌄“.
- „Tunnel verwenden“ → „Nie“ → Titel „Aus“; zurück auf „Automatisch“.
- „Jetzt testen“ (ohne laufende Test-Heimat) → „Teste …“, nach ≈ 10 s orange „Keine Antwort von 127.0.0.1:51999. Prüfe Adresse und Port-Weiterleitung.“
- „Ersetzen …“ → Menü mit „Datei auswählen …“ / „Aus Zwischenablage einfügen“.
- Hilfe › „Über“ zeigt Version und die acht Lizenzabschnitte.
- Bildvergleich wie Task 8 Step 7 gegen Board S6 und `docs/design/einstellungen-unterwegs.md`, hell und dunkel (Erscheinungsbild-Einstellung aus Phase 2).
- „Tunnel entfernen“ → Bestätigung → „Noch nicht eingerichtet“; `security find-generic-password -s com.snackbits.UniFiCameraPopup.wireguard-config` → „could not be found“.

- [ ] **Step 9: Commit**

```bash
git add docs/design/einstellungen-unterwegs.md UniFiCameraPopup/Views/Tunnel/TunnelSettingsView.swift UniFiCameraPopup/Views/Settings/SoundAndRemoteTabs.swift UniFiCameraPopup/AppDelegate.swift UniFiCameraPopup/Views/HelpView.swift UniFiCameraPopup/Services/WhatsNewService.swift UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj
git add $(grep -rln "connectedChip\|viaTunnel" UniFiCameraPopup Packages/AppCore)   # Menüleisten-Panel bzw. AppCore-Funktion + Test aus Step 4
git diff --cached --name-only | grep AppConfig   # Erwartet: leer
git commit -m "feat(settings): Unterwegs tab, tunnel status in the menu, licenses in Help" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Ende-zu-Ende-Prüfung mit echter Hardware

**Files:**
- keine Codeänderung, außer Korrekturen aus den Befunden (je Befund eigener Commit mit Test, wo testbar).

**Interfaces:**
- Consumes: alles aus Task 1–9; WireGuard-Server auf dem UniFi-Gateway, ein Client für diesen Mac, ein iPhone-Hotspot.
- Produces: bestätigte Prüfpunkte (Liste unten abhaken), ggf. Fix-Commits.

- [ ] **Step 1: Automatische Prüfungen**

Run:
```bash
wgtunnel/scripts/go.sh vet ./... && wgtunnel/scripts/go.sh test -count=1 ./...
wgtunnel/scripts/smoke.sh | tail -1
(cd Packages/ProtectKit && swift test 2>&1 | tail -1)
(cd Packages/AppCore && swift test 2>&1 | tail -1)
```
Expected: alles grün, `SMOKE OK`; Build-Befehl → `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Einrichten**

Auf dem Gateway (Einstellungen › VPN › VPN-Server) einen WireGuard-Server mit einem Client „MacBook Camera Popup“ anlegen, Datei herunterladen. Installierte App beenden, Debug-App starten, Einrichtung bis Schritt 6, Datei ablegen.
Expected: „Passt. Gegenstelle: <öffentliche Adresse>:51820“ ohne AllowedIPs-Hinweis (UniFi-Export: `0.0.0.0/0`).

- [ ] **Step 3: Zu Hause**

Expected im Log: `Route (Einstellung geändert): direct, direkt: console`; kein `Tunnel: gestartet`. Reiter „Unterwegs“: „Bereit · gerade zu Hause“. „Jetzt testen“: „Tunnel funktioniert – deine Konsole antwortet.“ – kann der Router kein NAT-Loopback, kommt zu Hause „Keine Antwort …“; dann diesen Punkt in Step 4 auf dem Hotspot wiederholen.

- [ ] **Step 4: Unterwegs (iPhone-Hotspot)**

Mac ins Hotspot-WLAN.
Expected innerhalb von ≈ 10 s: `Route (Netzwerkwechsel): tunnel, direkt: unreachable`, `Tunnel: gestartet`, `Route jetzt: Tunnel`; Rechtsklick-Menü „Protect: verbunden · unterwegs“, Panel-Chip „Unterwegs“; Reiter: „Verbunden · unterwegs“, „Letzte Verbindung | heute, hh:mm · über Mobilfunk“. Test-Popup bzw. Klingeln → Livebild läuft, Log `VLC: starting playback for 127.0.0.1`. **Host-Header-Prüfpunkt (Offene Frage 5):** Kommen Kameraliste und Ereignisse über `127.0.0.1:<port>` an, ist er erledigt; antwortet die Konsole mit 4xx, Arbeit stoppen und Plan B besprechen.

- [ ] **Step 5: Ausfall > 120 s**

Ein Test-Popup mit langer Schließzeit offen lassen, dann am Mac WLAN aus, 150 s warten, WLAN wieder an (Hotspot).
Expected: während des Ausfalls nach ≈ 75 s `Tunnel: keine Antwort mehr`, Reiter „Keine Verbindung · unterwegs“; nach Wiederkehr innerhalb von ≈ 20 s `Tunnel: Tunnel wieder da – n Verbindung(en) neu aufbauen`, `VLC: Stream neu verbinden`, Livebild läuft weiter, Menü wieder „Protect: verbunden · unterwegs“; ein neues Ereignis erzeugt ein Popup.

- [ ] **Step 6: Ruhezustand unterwegs**

Deckel zu, 2 Minuten, Deckel auf.
Expected: `Tunnel: Ruhezustand beendet – …`, kurz darauf wieder verbunden; Ereignisse kommen.

- [ ] **Step 7: Zurück nach Hause**

Mac ins Heim-WLAN.
Expected: `Route (Netzwerkwechsel): direct, direkt: console`, `Route jetzt: direkt`, `Tunnel: gestoppt`; Livebild/Ereignisse laufen direkt (`VLC: starting playback for 192.168.…`).

- [ ] **Step 8: Falsche Dateien, Schlüssel und Export**

- Im Reiter „Ersetzen …“ › „Datei auswählen …“ ein PDF, dann eine `.conf` mit Tippfehler (`AllowedIP = …`) wählen → orange Meldung (mit „Zeile n“), „Konfiguration“ zeigt weiter die echte Datei, unterwegs funktioniert der Tunnel weiter.
- Export prüfen (Allgemein › „Konfiguration exportieren …“ nach `${TMPDIR:-/tmp}/export.json`):
```bash
grep -ci "privatekey\|wireguard\|tunnel\|51820" "${TMPDIR:-/tmp}/export.json"      # Erwartet: 0
defaults export com.snackbits.UniFiCameraPopup - | python3 -c "import plistlib,sys; d=plistlib.load(sys.stdin.buffer); print(d['unifi.camera.popup.tunnel'].decode())" | grep -c -i "privatekey"   # Erwartet: 0
security find-generic-password -s com.snackbits.UniFiCameraPopup.wireguard-config >/dev/null && echo "im Schlüsselbund"
```
Expected: `0`, `0`, `im Schlüsselbund`.

- [ ] **Step 9: Release-Probe (ohne `build-release.sh`)**

Universal-Build wie Task 6 Step 6 wiederholen; die gebaute App auf einem Intel-Mac (oder unter Rosetta: `arch -x86_64 "…/MacOS/UniFi Camera Popup"`) starten → Menüleisten-Symbol erscheint, Hilfe › „Über“ zeigt die Lizenzen.

- [ ] **Step 10: Abschluss**

Alle Prüfpunkte abgehakt, Befunde behoben und committet. `git status --short` zeigt nur ` M UniFiCameraPopup/AppConfig.swift` (lokale Änderung des Nutzers) und keine unversionierten Dateien außer gitignorierten. Kein Merge, kein Push.
