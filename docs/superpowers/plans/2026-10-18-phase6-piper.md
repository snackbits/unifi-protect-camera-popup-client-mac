# Phase 6 – Piper-Stimmen statt macOS-Stimme – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ansagen aus Text spricht Piper statt `AVSpeechSynthesizer`: Piper liegt universal im App-Paket (Thorsten · mittel mitgeliefert), alle anderen deutschen Piper-Stimmen mit erlaubter Lizenz werden beim ersten Gebrauch geprüft heruntergeladen, Anna/macOS-Stimmen entfallen, die Lizenztexte nennen Piper, espeak-ng, onnxruntime und jede Stimme.

**Architecture:** Ein neuer Ordner `piper/` neben `wgtunnel/` lädt gepinnte Quellen samt CMake (SHA-256), baut Piper 2023.11.14-2 in einem CMake-Durchgang für arm64 + x86_64 und legt `piper/build/dist` an; die Xcode-Phase „Build and embed Piper“ kopiert das nach `Contents/Helpers/piper` und `Contents/Resources/piper` und signiert die Mach-O-Dateien. Reine Logik liegt in `AppCore` (Stimmenkatalog, Stimmenwahl/Migration, Aufrufparameter, Prozess mit Zeitlimit, WAV-Prüfung, Prüfsumme); die App hat einen `PiperVoiceStore` (Laden, Entfernen, Erzeugen per `Process`) und einen neuen Stimmen-Teil im Reiter „Ton“.

**Tech Stack:** Swift 5.9 Tools / Xcode 27, SwiftUI + AppKit (macOS 13.0), Foundation `Process`/`URLSession`, CryptoKit (`SHA256`), AVFoundation (`AVAudioFile`), XCTest über `swift test` (AppCore); Bash + CMake 3.31.8 (gepinnt) für den Piper-Build.

**Spec:** `docs/superpowers/specs/2026-10-18-phase6-piper.md` (verbindlich; Querschnitt-Regeln aus `docs/superpowers/specs/2026-10-18-phases-2-4.md` gelten weiter). Baut auf dem Stand nach Phase 5 auf (`docs/superpowers/plans/2026-10-18-phase5-feedback.md`, Commit `320553d` „version 2.0.0“); Format und Befehle wie dort.

> **Vorab geprüft (18.10.2026, macOS 27.0.1, Xcode 27.0, arm64):** Die Skripte aus Task 1, 4 und 5 und alle Swift-Dateien dieses Plans wurden in einer Kopie des Worktrees (Stand `320553d`) angewendet – die Code-Blöcke wurden maschinell aus den geprüften Dateien in diesen Plan eingesetzt. Ergebnis: `build-piper.sh` baut in 54 s aus den gepinnten Quellen (inkl. CMake-Download), alle Mach-O-Dateien `x86_64 arm64`, minos 13.0; `swift test` AppCore 160/160 (41 neu, 6 entfernt; der Integrationstest lief echt mit Piper); `xcodebuild` Debug `** BUILD SUCCEEDED **` mit „piper-smoke: ok (2.6 s Ton in 1 s)“; `codesign --verify --deep --strict` ok, auch nach `codesign --deep` mit der Self-Signed-Identität; DEBUG-Renderer-Bilder `S5-ton-*` angesehen (Stimme nicht geladen, lädt, Sprecher, macOS-alt + Fehler, „Geladene Stimmen“). **Nicht geprüft:** echter Download im laufenden App-Prozess (App wird nie normal gestartet), Intel-Mac (x86_64 nur unter Rosetta), Erststart einer heruntergeladenen ZIP (Gatekeeper-Dialog) – manuelle Prüfpunkte in Task 7.

## Forschungsergebnisse (Grundlage der Entscheidungen)

**Offizielle Piper-Binärdateien für macOS sind unbrauchbar.** `rhasspy/piper` Release `2023.11.14-2` hat `piper_macos_aarch64.tar.gz` (SHA-256 `6b1eb03b…f1cdcb0cc`) und `piper_macos_x64.tar.gz` (`ced85c0a…51deaf8b`, je 19 MB). Beide enthalten **dieselbe** Datei `piper` (`cmp` identisch), beide **nur x86_64**, minos 12.6, und **keine** der drei Bibliotheken (`libespeak-ng.1.dylib`, `libpiper_phonemize.1.dylib`, `libonnxruntime.1.14.1.dylib` – nur ein dSYM-Ordner). Start: `dyld: Library not loaded: @rpath/libespeak-ng.1.dylib`. Ursache: Piper's `CMakeLists.txt` installiert nur `*.so*`/`*.dll`, nie `*.dylib`, und der CI-Runner war Intel. `rhasspy/piper` ist archiviert (Nachfolger `OHF-Voice/piper1-gpl`, GPL-3.0, Python-zentriert).

**Selbst gebaut funktioniert es.** Aus den gepinnten Quellen (Tabelle in Task 1) baut ein einziger CMake-Durchgang mit `CMAKE_OSX_ARCHITECTURES="arm64;x86_64"` und dem fertigen `onnxruntime-osx-universal2-1.14.1` alles universal (kein `lipo -create` nötig, geprüft wird mit `lipo -archs`). Lauf hier (arm64, de_DE-thorsten-medium, „Achtung: An der Haustür hat jemand geklingelt.“): erster Start 1,35 s gesamt (Stimme laden 0,13 s, Rechnen 0,10 s für 2,53 s Ton, Echtzeitfaktor 0,04), danach 0,23 s; dieselbe Datei unter Rosetta (x86_64) 2,7 s. Ausgabe: RIFF/WAVE PCM 16 Bit mono 22 050 Hz, Spitze 0 dBFS (Piper normalisiert auf Vollaussteuerung), RMS −15,8 dBFS. Die Ausgabe ist nicht bit-gleich zwischen Läufen (Rauschanteil des Modells) – Tests prüfen Format/Länge/Pegel, nie Bytes.

**Randfälle (gemessen):** leerer Text oder „!!!“ → Exit 0 und 0,2 s Stille (8 864 Bytes); fehlendes `espeak-ng-data` → Exit 1; fehlendes Modell → `libc++abi: terminating … Model file doesn't exist` (SIGABRT); Emoji/englische Wörter lassen espeak auf Englisch umschalten („Can't read dictionary file: en_dict“, wenn es fehlt). Mit `--output_file` liest Piper das ganze stdin und fügt Zeilen mit Leerzeichen zusammen.

**espeak-ng-data reicht für Deutsch + Englisch:** `phontab`, `phonindex`, `phondata`, `intonations`, `de_dict`, `en_dict`, `lang/gmw/de`, `lang/gmw/en` = 880 KB statt 18 MB; Phoneme für „Achtung: An der Haustür … Bin gleich da, 5 Minuten!“ und „Hallo, das ist ein Computer-Update 🙂 for you, okay? Wi-Fi und E-Mail.“ identisch zum vollen Datensatz (`--debug`-Ausgabe verglichen).

**Signatur und Quarantäne:** Mach-O-Dateien in `Contents/Helpers/piper/` (Programm) und `…/lib/` (rpath `@executable_path/lib`), einzeln signiert vor dem Siegel der App: `codesign --verify --deep --strict` ok, mit ad-hoc und mit „UniFi Camera Popup (Self-Signed)“, auch nach `resign-app.sh` (`codesign --force --deep`). Hardened Runtime ist aus → keine Library-Validation-Probleme. Versuch Quarantäne: ein Helfer mit `com.apple.quarantine`, gestartet von einem nicht unter Quarantäne stehenden Prozess, lief normal; steht die ganze App unter Quarantäne, wird schon die App selbst beim Start ohne Freigabe beendet (wie heute). `UpdateService` entfernt die Quarantäne nach jedem Update ohnehin (`xattr -dr com.apple.quarantine`).

**Stimmen** (`rhasspy/piper-voices`, Hugging Face, Revision `c10ece1aade47bb51c153c893d14e5bf8e5b7117` vom 17.09.2026, `voices.json` SHA-256 `b63d7a86…183eed`): zehn deutsche Stimmen, alle `de_DE` (kein `de_AT`/`de_CH`). Modell-SHA-256 = Git-LFS-OID der Revision, Konfig-SHA-256 hier berechnet (MD5 stimmt mit `voices.json` überein). Lizenzen aus der jeweiligen `MODEL_CARD`; „See URL“ (M-AILABS) auf der Datensatz-Seite nachgelesen: „Redistribution and use in any form, including any commercial use … permitted provided … retain the above copyright notice“.

| ID | Name · Qualität | Sprecher | Hz | Modell (Bytes) | Lizenz Datensatz | angeboten |
|---|---|---|---|---|---|---|
| de_DE-eva_k-x_low | Eva K. · sehr niedrig | 1 | 16 000 | 20 628 813 | M-AILABS (BSD-artig, kommerziell erlaubt) | ja |
| de_DE-karlsson-low | Karlsson · niedrig | 1 | 16 000 | 63 104 526 | M-AILABS | ja |
| de_DE-kerstin-low | Kerstin · niedrig | 1 | 16 000 | 63 104 526 | CC0 1.0 | ja |
| de_DE-mls-medium | MLS · mittel | 236 | 22 050 | 76 961 079 | CC BY 4.0 (Multilingual LibriSpeech) | ja |
| de_DE-pavoque-low | Pavoque · niedrig | 1 | 16 000 | 63 104 526 | **CC BY-NC-SA 4.0** | **nein – keine kommerzielle Nutzung** |
| de_DE-ramona-low | Ramona · niedrig | 1 | 16 000 | 63 104 526 | M-AILABS | ja |
| de_DE-thorsten-low | Thorsten · niedrig | 1 | 16 000 | 63 104 526 | CC0 1.0 (Thorsten-Voice) | ja |
| de_DE-thorsten-medium | Thorsten · mittel | 1 | 22 050 | 63 201 294 | CC0 1.0 | ja, **mitgeliefert** |
| de_DE-thorsten-high | Thorsten · hoch | 1 | 22 050 | 113 895 201 | CC0 1.0 | ja |
| de_DE-thorsten_emotional-medium | Thorsten emotional · mittel | 8 (amüsiert, wütend, angewidert, betrunken, neutral, schläfrig, überrascht, flüsternd) | 22 050 | 76 745 905 | CC0 1.0 | ja |

Prüfsummen stehen vollständig in `PiperVoiceCatalog.swift` (Task 2). Die Modelle selbst stehen im Repository unter MIT (`cardData.license: mit`).

**Größe:** +107 MB im App-Paket (Helpers 46 MB, davon onnxruntime universal 43 MB; Resources/piper 61 MB, davon Thorsten 60,3 MB); die ZIP wächst um ≈ 69 MB. Erster Build lädt ≈ 200 MB (CMake 78 MB, Quellen 60 MB, onnxruntime 14 MB, Thorsten 63 MB) und baut ≈ 1 min; danach überspringt der Stempel den Build (< 1 s).

## Voraussetzung: Phase 5 ist umgesetzt

Vor Task 1 prüfen (jede Zeile > 0, die letzten zwei = 0):

```bash
grep -c "public enum VoiceChoice" Packages/AppCore/Sources/AppCore/Sound/VoiceChoice.swift
grep -c "public static func normalizationGain" Packages/AppCore/Sources/AppCore/Sound/Loudness.swift
grep -c "func applySpeech(id: UUID, text: String) async throws" UniFiCameraPopup/Services/SoundStore.swift
grep -c "ChangelogEntry(version: \"2.0.0\"" UniFiCameraPopup/Services/WhatsNewService.swift
grep -c "Build WireGuard tunnel" UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj
test -f docs/superpowers/manual-checks-2.0.0.md && echo 1
grep -c "E61000000000000000000001\|E66000000000000000000001" UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj   # → 0
test -d piper && echo 1 || echo 0   # → 0
```

Werkzeuge: `curl`, `shasum`, `tar`, `xcrun`, `lipo`, `install_name_tool`, `codesign`, `rsync`, `afinfo` (alle in macOS/Xcode). CMake kommt gepinnt aus `fetch.sh` – ein Homebrew-CMake wird **nicht** benutzt. Es gibt **kein** Test-Bundle im Xcode-Projekt (Phase-2-Entscheidung): Testbares liegt in `AppCore`.

## Global Constraints

- macOS-Deployment-Target **13.0** (auch für Piper: `CMAKE_OSX_DEPLOYMENT_TARGET=13.0`); keine API neuer als macOS 13 ohne `#available` (geplant: keine). Keine Sandbox, Hardened Runtime aus, kein bezahlter Developer-Account; Signatur über `create-signing-identity.sh`/`resign-app.sh`.
- „Piper als eigenständige ausführbare Datei samt Bibliotheken (onnxruntime, espeak-ng, piper-phonemize) und `espeak-ng-data` … **universal (arm64 + x86_64)**, macOS 13.0 … gepinnt mit SHA-256, Build-Skript im Repo wie bei `wgtunnel/` … Die App ruft Piper nur über `Process` auf …, nie durch Linken.“
- „Mitgeliefert: genau eine Stimme, **Thorsten (medium)**“; alle anderen „beim ersten Gebrauch **herunterladen** (Hugging Face, feste Revision/Commit-URL), mit Fortschritt, Größe vorher anzeigen, Prüfsumme aus einer in der App gepinnten Liste prüfen, Ablage unter Application Support; „Entfernen“ für heruntergeladene Stimmen.“
- „Stimmen, deren Lizenz kommerzielle Nutzung oder Weitergabe ausschließt (z. B. „NC“), werden **nicht angeboten**.“
- „Piper fehlt/stürzt ab/Zeitüberschreitung (z. B. 20 s) → klare Meldung im Reiter „Ton“, kein Absturz, kein Rückfall auf macOS-Stimmen. Erzeugen läuft nie auf dem Main Thread.“
- „erzeugte Piper-Audios laufen durch dieselbe Lautheitsmessung wie in Phase 5.“
- „Stimmenwahl einer Ansage bleibt im Ton-Speicher (nicht im Export, wie bisher). Heruntergeladene Stimmen sind nicht im Export.“
- UI-Sprache Deutsch, Du-Form, typografische Anführungszeichen „…“; Code und Bezeichner Englisch.
- Version **2.0.0**, Build-Nummer unangetastet; nur der bestehende 2.0.0-Eintrag in `WhatsNewService` wird geändert. `build-release.sh` wird **nie** ausgeführt (nur bearbeitet).
- `UniFiCameraPopup/AppConfig.swift` hat lokale Änderungen des Nutzers: **nie ändern, nie stagen, nie zurücksetzen**. Nur explizite Pfade `git add`; nie `git add -A`, `git add .` oder `git commit -a`. Vor jedem Commit: `git diff --cached --name-only | grep AppConfig` muss leer sein.
- Die App wird **nie normal gestartet**. Sichtprüfung nur über den DEBUG-Renderer `--render-snapshots` (eigene `UserDefaults`-Suite, temporäre Ordner, beendet sich selbst).
- Große Dateien nie ins Git: `piper/.cache/` und `piper/build/` sind ignoriert; ins Git kommen nur Skripte, `piper/NOTICES.txt` (generiert, 49 KB) und Swift-Code.
- Kein Merge, kein Push. Jeder Task endet mit grünem Build bzw. grünen Tests. Commit-Nachrichten enden mit Leerzeile + `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Neue pbxproj-IDs: Präfix **E6** (`E61…` BuildFile, `E62…` FileRef) über `UniFiCameraPopup/scripts/pbxproj-add-files.py --prefix E6`; die neue Shell-Phase bekommt `E66000000000000000000001`.

**Befehle** (aus dem Worktree-Wurzelverzeichnis `app-protect/`):

```bash
# App bauen (die Phase „Build and embed Piper“ baut Piper beim ersten Mal, ≈ 1 min + Downloads)
DD="${TMPDIR:-/tmp}/ucp-phase6-dd"
xcodebuild -project UniFiCameraPopup/UniFiCameraPopup.xcodeproj -scheme UniFiCameraPopup \
  -configuration Debug -derivedDataPath "$DD" build 2>&1 | grep -E "error:|piper-smoke|\*\* BUILD" | tail -20
# Erwartet: piper-smoke: ok (… s Ton in … s) und ** BUILD SUCCEEDED **

# Tests
(cd Packages/AppCore && swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -3)
(cd Packages/ProtectKit && swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -3)

# Piper allein
piper/scripts/build-piper.sh && piper/scripts/smoke.sh
piper/scripts/check-app.sh "$DD/Build/Products/Debug/UniFi Camera Popup.app"

# Sichtprüfung ohne normalen Start (DEBUG-Renderer, schreibt PNGs 2×, hell + dunkel, und beendet sich)
OUT="${TMPDIR:-/tmp}/ucp-phase6-snap"; rm -rf "$OUT"; mkdir -p "$OUT"
"$DD/Build/Products/Debug/UniFi Camera Popup.app/Contents/MacOS/UniFi Camera Popup" --render-snapshots "$OUT" > /dev/null
open "$OUT"

# pbxproj nach Änderung prüfen
plutil -lint UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj
```

**Schreibweise der Code-Schritte:** „In `Pfad` ersetzen:“ + Block + „durch:“ + Block = genau dieser Text kommt genau einmal in der Datei vor und wird ersetzt (Edit-Werkzeug). „Datei `Pfad` neu anlegen:“ / „Datei `Pfad` ganz ersetzen:“ = ganze Datei. „An `Pfad` anhängen:“ = ans Dateiende.

## Review Focus

1. **Kein Internet, Abbruch oder falsche Antwort beim Laden einer Stimme** (WLAN weg mitten im Download, „Abbrechen“, Hugging Face liefert eine HTML-Fehlerseite, 404 oder eine abgeschnittene Datei; Platte voll): Es bleibt keine halbe Stimme liegen, die Stimme gilt weiter als „… MB laden“, es gibt eine klare Meldung (bei „Abbrechen“ keine), Thorsten · mittel spricht ohne Netz weiter. → `FileChecksumTests.testMatchesNeedsSizeAndHash`, `testMoreThanOneChunk` (Task 3); `.partial`-Ordner und Umbenennen erst nach Prüfung in `PiperVoiceStore.download` (Task 6); manueller Prüfpunkt (Task 7).
2. **Ungewöhnlicher Text** (nur Satzzeichen, Emoji, Zeilenumbrüche/Tabs, 5 000 Zeichen, englische Wörter, Zahlen/„€“/„„Zitat““): Piper hängt nie, es wird keine stumme Datei gespeichert, englische Wörter klingen wie mit vollem espeak-Datensatz. → `PiperCommandTests.testInputIsOneLine`, `testLongInputIsCutAtAWord`, `WAVFileTests.testSilenceIsNoSpeech`, `PiperIntegrationTests.testEmptyTextGivesNoSpeech`, `testBundledPiperSpeaksGerman` (mit „Okay, Computer-Update!“) (Task 3).
3. **Piper fehlt, stürzt ab, hängt oder liest stdin nicht** (beschädigtes App-Paket, fehlendes Modell → SIGABRT, Zeitüberschreitung, Programm beendet sich vor dem Lesen): App stürzt nicht ab (kein SIGPIPE), Meldung im Reiter „Ton“, nach spätestens 20 s + 1 s ist der Prozess weg, kein Rückfall auf macOS. → `PiperRunnerTests` (alle, Task 3).
4. **Alte und verwaiste Stimmenbezüge** (Ansage mit Anna von vor Phase 6, mitgelieferte Aufnahme, Ansage mit einer Stimme, die später entfernt wurde, ausgeschlossene/unbekannte ID, Sprecher außerhalb des Bereichs, alter Ton-Speicher ohne Piper-Feld): spielt weiter, Hinweis „macOS (alt) – mit „Übernehmen“ neu erzeugen“, „Übernehmen“ aktiv, Auswahl fällt auf Thorsten bzw. den Standard-Sprecher. → `VoiceSelectionTests` (alle, Task 2); Bild `S5-ton-macos-alt-*` (Task 7).
5. **Fremder Mac** (Intel-Mac, App aus der ZIP unter Quarantäne, Update über `UpdateService`, Self-Signed- statt ad-hoc-Signatur): Piper startet und spricht. → `check-app.sh` (lipo `arm64 x86_64`, `codesign --verify --deep --strict`) in Task 4 und in `build-release.sh`; `smoke.sh` nach `resign-app.sh` in `build-release.sh` (Task 4); manueller Prüfpunkt Intel/Quarantäne (Task 7).

---

## Bewusste Abweichungen von Vorlage/Spezifikation

1. **Stimmenfeld einer alten macOS-Ansage** zeigt die Stimme, mit der „Übernehmen“ neu erzeugt (Thorsten · mittel), und darunter orange „macOS (alt) – mit „Übernehmen“ neu erzeugen“ (Spezifikation: Feld zeigt diesen Text „o. ä.“). Grund: Das Feld ist jetzt eine echte Auswahl; ein Eintrag „macOS (alt)“ darin wäre eine Stimme, die man nicht wählen kann.
2. **Vorlage S5** listet „Thorsten · mitgeliefert“ und macOS-Stimmen; jetzt: „Thorsten · mittel – mitgeliefert“, danach die acht weiteren Stimmen mit „– geladen“ bzw. „– NN MB laden“, bei Mehrsprecher-Stimmen ein zweites Feld „Sprecher“; unter dem Feld eine Lizenzzeile; neue Karte „Geladene Stimmen“ (nur wenn mindestens eine geladen ist).

## Entscheidungen (wo die Spezifikation offen ist)

1. **Entscheidung:** Engine = `rhasspy/piper` **2023.11.14-2** (Piper-Code MIT), aus dem Quellcode gebaut, nicht die Release-Tarballs (x86_64-only, ohne Bibliotheken – siehe Forschung) und nicht `OHF-Voice/piper1-gpl` (Python-zentriert, Piper-Code dort selbst GPL). Bestandteile gepinnt: piper-phonemize `bfc2e75` (MIT; Piper zieht sonst `master`), espeak-ng-Fork `rhasspy/espeak-ng@0f65aa3` (GPL-3.0-or-later; genau der Stand, den piper-phonemize vorgibt), onnxruntime 1.14.1 universal2 (MIT, Microsoft-Release), fmt 10.0.0, spdlog 1.12.0 (MIT, statisch in `piper`).
2. **Entscheidung:** Universal in **einem** CMake-Durchgang (`CMAKE_OSX_ARCHITECTURES="arm64;x86_64"`), keine zwei Architektur-Ordner und kein Auswählen zur Laufzeit; `build-piper.sh` und `check-app.sh` prüfen jede Mach-O-Datei mit `lipo -archs`.
3. **Entscheidung:** CMake **3.31.8** wird wie die Go-Toolchain gepinnt geladen (`cmake-3.31.8-macos-universal.tar.gz`, SHA-256 aus Kitwares `cmake-3.31.8-SHA-256.txt`). Grund: Xcode-Phasen haben kein `/opt/homebrew/bin` im `PATH`, und CMake 4 lehnt das `cmake_minimum_required(VERSION 3.5)` von espeak-ng ab.
4. **Entscheidung:** Binärdateien, Quellen und Modell **nicht ins Git** (≈ 200 MB Downloads, 107 MB im Paket): `piper/.cache/` (Downloads, je SHA-256 geprüft, idempotent) und `piper/build/` (Build, Stempel = SHA-256 der beiden Build-Skripte) sind ignoriert – genau wie `wgtunnel/.toolchain`/`wgtunnel/build`. Der erste Build braucht Netz.
5. **Entscheidung:** Ablage im Paket: `Contents/Helpers/piper/piper` + `Contents/Helpers/piper/lib/*.dylib` (rpath `@executable_path/lib`, Build-rpaths entfernt), `Contents/Resources/piper/{espeak-ng-data, voices/de_DE-thorsten-medium.onnx(.json), ThirdPartyNotices-onnxruntime.txt, build-scripts/}`. Code nur in `Helpers` (codesign versiegelt `Resources` als Daten).
6. **Entscheidung:** `espeak-ng-data` nur Deutsch + Englisch (880 KB statt 18 MB); alle angebotenen Stimmen sind `de_DE` mit `espeak.voice = de`. Phoneme geprüft identisch (Forschung).
7. **Entscheidung:** Signatur: `embed.sh` signiert die drei Bibliotheken und `piper` mit `$EXPANDED_CODE_SIGN_IDENTITY` (leer → ad-hoc `-`), bevor Xcodes eigener CodeSign-Schritt die App versiegelt; `resign-app.sh` (`--deep`) bleibt unverändert und signiert sie bei Releases mit. `build-release.sh` prüft danach `codesign --verify --deep --strict` und lässt Piper einmal sprechen.
8. **Entscheidung:** Aufruf: `piper --quiet --model <onnx> --config <json> --espeak_data <dir> --output_file <tmp>.wav [--speaker n]`, Text als **eine** Zeile auf stdin (Zeilenumbrüche/Tabs → Leerzeichen, höchstens 1 000 Zeichen, an einer Wortgrenze gekürzt), Umgebung nur `PATH=/usr/bin:/bin`, `LANG=de_DE.UTF-8`, Arbeitsordner = temporärer Ordner. `--speaker` nur bei Mehrsprecher-Stimmen. Zeitlimit **20 s** für den Prozess (Laden der Stimme eingeschlossen; gemessen 1,4 s kalt), dann SIGTERM, nach 1 s SIGKILL. stdin-Schreibende mit `F_SETNOSIGPIPE` (sonst beendet SIGPIPE die App, wenn Piper vorher endet). Abbruch der Swift-Task beendet den Prozess.
9. **Entscheidung:** Ergebnis: die WAV bleibt, wie Piper sie schreibt (PCM 16 Bit mono 16/22,05 kHz), und wird als `<UUID>.wav` in den Ton-Ordner verschoben (keine Umwandlung in CAF). Vorher: WAV-Kopf gültig und mindestens ein 50-ms-Block über −50 dBFS (`Loudness.gateDBFS`), sonst „Piper hat keinen Ton erzeugt …“ und nichts wird gespeichert. Danach `AnnouncementAudio.loudnessGain` wie in Phase 5 (Piper-Spitze 0 dBFS → Faktor < 1).
10. **Entscheidung:** Gespeichert wird die Stimme im vorhandenen Feld `Announcement.voiceIdentifier` als `piper:<voice-id>#<sprecher>` (z. B. `piper:de_DE-thorsten_emotional-medium#4`) – kein neues Feld, Ton-Speicher-Schema bleibt (Schlüssel `unifi.camera.popup.sound`, nicht im Export). Die alte 1.x-Version kennt die ID nicht und spielt die Datei trotzdem (sie erzeugt nur beim eigenen „Übernehmen“ neu).
11. **Entscheidung:** Der Katalog ist Swift-Quellcode in `AppCore` (`PiperVoiceCatalog.all`, kein Resource-Bundle, testbar), erzeugt aus `voices.json`/LFS-Baum der Revision `c10ece1…`. Ausgeschlossene Stimmen bleiben im Katalog (`license.allowsRedistribution == false`), damit der Filter getestet ist; angeboten wird nur `PiperVoiceCatalog.offered` (9 Stimmen).
12. **Entscheidung:** Ausgeschlossen: **Pavoque** (CC BY-NC-SA 4.0). Eva K., Karlsson, Ramona (M-AILABS, Model Card „See URL“) werden angeboten – die Datensatzlizenz erlaubt kommerzielle Weitergabe mit Copyright-Hinweis, der in `ThirdPartyNotices.txt` steht. MLS (CC BY 4.0) mit Namensnennung in den Hinweisen.
13. **Entscheidung:** Sprecher: Thorsten emotional mit deutschen Namen der acht Stimmungen in Modell-Reihenfolge, Standard „neutral“ (Index 4); MLS „Sprecher 1 … 236“ (Index + 1, MLS-IDs nicht angezeigt), Standard Sprecher 1. Ein gespeicherter Sprecher außerhalb des Bereichs fällt auf den Standard zurück.
14. **Entscheidung:** Stimmenfeld: „Name · Qualität – mitgeliefert“ / „– geladen“ / „– NN MB laden“ (MB = 10⁶, gerundet, wie der Finder), Thorsten · mittel zuerst, dann Katalog-Reihenfolge. Qualitäten: sehr niedrig, niedrig, mittel, hoch. Wechsel der Stimme setzt deren Standard-Sprecher.
15. **Entscheidung:** „Beim ersten Gebrauch“ = beim ersten „Anhören“ oder „Übernehmen“ mit einer nicht geladenen Stimme; kein zusätzlicher Dialog (die Größe steht im Feld und in der Hinweiszeile „Wird beim ersten Anhören oder Übernehmen geladen (63 MB, einmalig) – …“). Während des Ladens ersetzt eine Zeile mit Fortschrittsbalken, „Lade „Kerstin · niedrig“ … 23 von 63 MB“ und „Abbrechen“ die Hinweiszeile. Eine Stimme lädt höchstens einmal gleichzeitig.
16. **Entscheidung:** Ablage `~/Library/Application Support/UniFi Camera Popup/Voices/<id>/` (eigener Ordner – der Ton-Ordner `Sounds` löscht unbekannte Dateien beim Start). Download erst nach `Voices/<id>.partial/`, Größe + SHA-256 je Datei prüfen, dann umbenennen; Fehler/Abbruch löschen `.partial`. Als „geladen“ zählt eine Stimme, wenn beide Dateien die gepinnte Größe haben (der Hash wurde vor dem Umbenennen geprüft; kein erneutes Hashen von 114 MB bei jedem Öffnen des Reiters).
17. **Entscheidung:** „Entfernen“ in einer Karte „Geladene Stimmen“ unter dem Editor (Name · Qualität, Größe, Link „Entfernen“), mit Rückfrage „„Kerstin · niedrig“ entfernen?“ / „Ansagen mit dieser Stimme spielen weiter. Zum Anhören oder neu Erzeugen wird sie wieder geladen (63 MB).“ Die mitgelieferte Stimme ist nicht entfernbar und nicht gelistet.
18. **Entscheidung:** Mitgelieferte Aufnahmen „Bin gleich da“/„Paket bitte abstellen“ zählen als Thorsten · mittel; „Übernehmen“ ist erst aktiv, wenn Text oder Stimme sich ändern. Jede andere Ansage ohne Piper-Kennung, aber mit Datei, ist „macOS (alt)“; eine Ansage mit nicht mehr angebotener Piper-Stimme zeigt „Diese Stimme gibt es nicht mehr – mit „Übernehmen“ neu erzeugen“.
19. **Entscheidung:** Kein Rückfall: Schlägt Piper fehl, bleibt die Ansage unverändert, die Meldung steht orange im Editor; Log-Zeilen „Piper: …“/„Stimme: …“ in `talkback.log`. Ein abgebrochener Download meldet nichts.
20. **Entscheidung:** Lizenzanzeige pro Stimme: Zeile „Lizenz der Stimme: CC0 1.0 · Thorsten-Voice (Thorsten Müller)“ unter dem Feld; vollständige Liste mit Quellen in `ThirdPartyNotices.txt` (Abschnitt „Sprachausgabe (Piper)“), Kurzfassung in „Über“.
21. **Entscheidung:** GPL-Quellcode-Angebot: genaue Upstream-URLs + Versionen/Commits in `ThirdPartyNotices.txt`, die SHA-256-Liste und Build-Befehle als `Contents/Resources/piper/build-scripts/{fetch.sh,build-piper.sh}` im Paket, dazu der Satz „Auf Anfrage schicken wir den vollständigen Quellcode samt Build-Skripten (mindestens drei Jahre …)“ (Kontaktweg: Offene Frage 1).
22. **Entscheidung:** onnxruntimes eigene `ThirdPartyNotices.txt` (293 KB) wird nicht in „Über“ eingefügt (zu lang für ein SwiftUI-`Text`), sondern als `Resources/piper/ThirdPartyNotices-onnxruntime.txt` mitgeliefert; „Über“ hat den Link-Button „Hinweise zu onnxruntime öffnen …“ (öffnet sie im Standard-Editor).
23. **Entscheidung:** `piper/NOTICES.txt` erzeugt `piper/scripts/collect-notices.sh` aus den heruntergeladenen Quellen (wird committet); `wgtunnel/scripts/collect-notices.sh` hängt sie an `ThirdPartyNotices.txt` an (der Go-Teil bleibt byte-gleich – geprüft).
24. **Entscheidung:** Integrationstest = `PiperIntegrationTests` in AppCore gegen `piper/build/dist` (übersprungen, wenn nicht gebaut) **plus** `smoke.sh` am Ende der Xcode-Phase nur bei `CONFIGURATION=Debug` (≈ 0,3–1 s je Build). Nie beim App-Start.
25. **Entscheidung:** Der 2.0.0-Eintrag in „Was ist neu“ ersetzt den Halbsatz „oder mit der macOS-Stimme Anna aus eigenem Text ab“; kein neuer Punkt.

## Offene Fragen

1. GPL-Angebot: Welche Kontaktadresse soll in „Auf Anfrage schicken wir …“ stehen – oder sollen die sechs Quell-Archive zusätzlich auf `unifi-protect-camera-popup-server.snackbits.dev` gespiegelt werden (Deploy außerhalb dieses Plans)?
2. +107 MB App-Paket / +69 MB Update-ZIP für Thorsten · mittel und das universale onnxruntime – in Ordnung, oder soll Thorsten · niedrig (63 MB, 16 kHz) statt mittel mitgeliefert werden?
3. Abweichung 1 (Feld zeigt bei alten Ansagen die Zielstimme + orange Hinweiszeile) bestätigen?

---

## File Structure

```
piper/                                    (neu, wie wgtunnel/)
  scripts/fetch.sh            gepinnte Downloads + SHA-256 nach piper/.cache (CMake, Quellen, onnxruntime, Thorsten)
  scripts/build-piper.sh      universaler Build → piper/build/dist (Helpers/, Resources/), Stempel
  scripts/smoke.sh            Piper spricht einen Satz (dist oder App-Contents), prüft WAV
  scripts/embed.sh            Xcode-Phase: build-piper.sh, kopieren, signieren, Debug-Smoke
  scripts/check-app.sh        fertige App: lipo, Dateien, Lizenz-Marken, codesign --verify
  scripts/collect-notices.sh  → piper/NOTICES.txt (Lizenztexte + Quellcode-Angebot + Stimmen)
  NOTICES.txt                 generiert, committet
.gitignore                                + piper/.cache/, piper/build/
Packages/AppCore/Sources/AppCore/Sound/
  PiperVoiceCatalog.swift     (neu) PiperQuality, VoiceLicense, VoiceFile, PiperVoice, PiperVoiceCatalog
  VoiceSelection.swift        (neu) PiperVoiceRef, AnnouncementVoice (Migration/„Übernehmen“), VoiceAvailability, Menütexte
  PiperCommand.swift          (neu) PiperInstallation, PiperVoiceFiles, PiperCommand (Argumente, stdin)
  PiperRunner.swift           (neu) PiperError, PiperRunner (Process, Zeitlimit, Abbruch)
  WAVFile.swift               (neu) WAVInfo (Kopf, Samples, hasSpeech)
  FileChecksum.swift          (neu) SHA-256 in 1-MiB-Stücken, Größe + Hash
  AnnouncementAudio.swift     − voices/preferredVoice/candidate/label/render/SpeechCollector
  VoiceChoice.swift           (gelöscht)
  SoundSettings.swift         − bundledVoiceLabel
  Announcement.swift          Doku voiceIdentifier
Packages/AppCore/Tests/AppCoreTests/
  PiperVoiceCatalogTests, VoiceSelectionTests (+VoiceMenuTests), PiperCommandTests, PiperRunnerTests,
  WAVFileTests, FileChecksumTests, PiperIntegrationTests (neu); VoiceChoiceTests (gelöscht); SoundSettingsTests (−3)
UniFiCameraPopup/
  Services/PiperVoiceStore.swift   (neu) Laden/Prüfen/Entfernen, render(text:voice:)
  Services/SoundStore.swift        Piper statt AVSpeech (previewBuffer, addText, applySpeech)
  Views/Settings/SoundTab.swift    Stimmenfeld, Sprecher, Fortschritt, Lizenzzeile, „Geladene Stimmen“
  Views/HelpView.swift             Hilfe „Sprechen und Ansagen“, „Über“
  Services/WhatsNewService.swift   2.0.0-Eintrag
  Debug/SnapshotRenderer.swift     S5-Varianten Phase 6
  ThirdPartyNotices.txt            + piper/NOTICES.txt (generiert)
  UniFiCameraPopup.xcodeproj/project.pbxproj  + PiperVoiceStore.swift (E6), + Phase „Build and embed Piper“
  scripts/build-release.sh         + check-app.sh, codesign --verify, smoke.sh
wgtunnel/scripts/collect-notices.sh       hängt piper/NOTICES.txt an
docs/design/einstellungen-ton.md          + Phase 6
docs/superpowers/manual-checks-2.0.0.md   + Phase 6
```

## Reihenfolge und parallele Gruppen

| Gruppe | Tasks | darf parallel (eigene Worktrees) | braucht |
|---|---|---|---|
| A | 1, 2, 3 | **ja** (1 ist ganz unabhängig; 3 legt die Datei `PiperVoiceCatalog.swift` aus Task 2 Step 3 inhaltsgleich mit an und überspringt den Integrationstest, solange 1 fehlt) | – |
| – | 4 | – | 1 |
| B | 5, 6 | **ja** (verschiedene Dateien; 5: Lizenztexte/„Über“/`check-app.sh`, 6: AppCore-Aufräumen/Store/Reiter) | 5: 1, 4 · 6: 2, 3, 4 |
| – | 7 | – | 5, 6 |

Merge-Hinweis Gruppe A: Task 2 und 3 legen nur neue Dateien an (`PiperVoiceCatalog.swift` in beiden identisch – Git führt gleiche Neuanlagen konfliktfrei zusammen); Task 1 ändert `.gitignore`. Gruppe B: keine gemeinsame Datei.

---
### Task 1: Piper-Build – gepinnte Quellen, universal, Thorsten mitgeliefert (Gruppe A, unabhängig)

**Files:**
- Create: `piper/scripts/fetch.sh`, `piper/scripts/build-piper.sh`, `piper/scripts/smoke.sh`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: nichts.
- Produces: `piper/scripts/build-piper.sh` (idempotent, druckt „build-piper: … ist aktuell“ oder „build-piper: <dist>“) erzeugt `piper/build/dist/Helpers/piper/{piper,lib/libespeak-ng.1.dylib,lib/libpiper_phonemize.1.dylib,lib/libonnxruntime.1.14.1.dylib}` und `piper/build/dist/Resources/piper/{espeak-ng-data/…,voices/de_DE-thorsten-medium.onnx,voices/de_DE-thorsten-medium.onnx.json,ThirdPartyNotices-onnxruntime.txt,build-scripts/{fetch.sh,build-piper.sh}}`; `piper/scripts/fetch.sh` druckt den Cache-Ordner `piper/.cache`; `piper/scripts/smoke.sh [<Contents-Ordner>]` (Standard `piper/build/dist`) endet mit „piper-smoke: ok (… s Ton in … s)“. Task 2 pinnt dieselben Thorsten-Prüfsummen; Task 3 testet gegen `piper/build/dist`; Task 4 ruft `build-piper.sh` und `smoke.sh` auf; Task 5 nutzt `fetch.sh`.

Gepinnte Eingaben (SHA-256 vollständig nur in `fetch.sh` – die einzige Quelle; hier geprüft am 18.10.2026):

| Datei | Quelle |
|---|---|
| cmake-3.31.8-macos-universal.tar.gz (78 MB) | github.com/Kitware/CMake Release v3.31.8 (SHA-256 aus `cmake-3.31.8-SHA-256.txt`) |
| piper-2023.11.14-2.tar.gz | rhasspy/piper Tag 2023.11.14-2 (Commit 38917ffd8c0e219c6581d73e07b30ef1d572fce1) |
| piper-phonemize-bfc2e75.tar.gz | rhasspy/piper-phonemize bfc2e7549957829b0227c66a305d11cc88167bda (5.12.2023) |
| espeak-ng-0f65aa3.tar.gz | rhasspy/espeak-ng 0f65aa301e0d6bae5e172cc74197d32a6182200f (von piper-phonemize vorgegeben) |
| fmt-10.0.0.tar.gz, spdlog-1.12.0.tar.gz | fmtlib/fmt 10.0.0, gabime/spdlog v1.12.0 (Versionen aus Piper's CMakeLists) |
| onnxruntime-osx-universal2-1.14.1.tgz | microsoft/onnxruntime Release v1.14.1 |
| de_DE-thorsten-medium.onnx (+ .onnx.json) | huggingface.co/rhasspy/piper-voices @ c10ece1aade47bb51c153c893d14e5bf8e5b7117 |



- [ ] **Step 1: Ignore-Regeln**

An `.gitignore` anhängen:

```gitignore

# Piper (Phase 6): pinned downloads (CMake, sources, onnxruntime, Thorsten) and the build.
piper/.cache/
piper/build/
```

- [ ] **Step 2: Downloads mit Prüfsumme**

Datei `piper/scripts/fetch.sh` neu anlegen:

```bash
#!/bin/bash
# Downloads every pinned input of the Piper build into piper/.cache (gitignored) and checks
# its SHA-256: CMake (build tool), the sources of piper, piper-phonemize, espeak-ng, fmt and
# spdlog, the onnxruntime release and the bundled voice Thorsten (medium). Idempotent: a file
# with the right checksum is not downloaded again. Prints the cache directory.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${ROOT}/.cache"
mkdir -p "${CACHE}"

VOICES_REV="c10ece1aade47bb51c153c893d14e5bf8e5b7117"
HF="https://huggingface.co/rhasspy/piper-voices/resolve/${VOICES_REV}"

# name | sha256 | url
PINNED="
cmake-3.31.8-macos-universal.tar.gz|d1449f969c54d5c00886d5b643340d493dfb3c81cb39ee29b35453395c11ebf7|https://github.com/Kitware/CMake/releases/download/v3.31.8/cmake-3.31.8-macos-universal.tar.gz
piper-2023.11.14-2.tar.gz|8b684e102cfe23af097830db9555a8641f17735725853c531a1daeb34b6ed1a8|https://github.com/rhasspy/piper/archive/refs/tags/2023.11.14-2.tar.gz
piper-phonemize-bfc2e75.tar.gz|cb72dd5564b292e043129d1c34b74f064dcc9ff0f713aebb3c6e44c5607de724|https://github.com/rhasspy/piper-phonemize/archive/bfc2e7549957829b0227c66a305d11cc88167bda.tar.gz
espeak-ng-0f65aa3.tar.gz|37ebbabb010200be8ec26c61b770e93f964f4503a329d7d74c239a1a40051e43|https://github.com/rhasspy/espeak-ng/archive/0f65aa301e0d6bae5e172cc74197d32a6182200f.tar.gz
fmt-10.0.0.tar.gz|ede1b6b42188163a3f2e0f25ad5c0637eca564bd8df74d02e31a311dd6b37ad8|https://github.com/fmtlib/fmt/archive/refs/tags/10.0.0.tar.gz
spdlog-1.12.0.tar.gz|4dccf2d10f410c1e2feaff89966bfc49a1abb29ef6f08246335b110e001e09a9|https://github.com/gabime/spdlog/archive/refs/tags/v1.12.0.tar.gz
onnxruntime-osx-universal2-1.14.1.tgz|bcbaa573172caa74f8273598d70733572a1b15279e63c7a18031cc8cc97cf134|https://github.com/microsoft/onnxruntime/releases/download/v1.14.1/onnxruntime-osx-universal2-1.14.1.tgz
de_DE-thorsten-medium.onnx|7e64762d8e5118bb578f2eea6207e1a35a8e0c30595010b666f983fc87bb7819|${HF}/de/de_DE/thorsten/medium/de_DE-thorsten-medium.onnx
de_DE-thorsten-medium.onnx.json|974adee790533adb273a1ac88f49027d2a1b8f0f2cf4905954a4791e79264e85|${HF}/de/de_DE/thorsten/medium/de_DE-thorsten-medium.onnx.json
"

while IFS='|' read -r name sha url; do
  [[ -z "${name}" ]] && continue
  target="${CACHE}/${name}"
  if [[ -f "${target}" ]] && echo "${sha}  ${target}" | shasum -a 256 -c - >/dev/null 2>&1; then
    continue
  fi
  echo "fetch: lade ${url}" >&2
  curl -fsSL --retry 3 -o "${target}.part" "${url}"
  if ! echo "${sha}  ${target}.part" | shasum -a 256 -c - >/dev/null 2>&1; then
    rm -f "${target}.part"
    echo "fetch: Prüfsumme falsch: ${name}" >&2
    exit 1
  fi
  mv "${target}.part" "${target}"
done <<< "${PINNED}"

echo "${CACHE}"
```

- [ ] **Step 3: Universaler Build**

Datei `piper/scripts/build-piper.sh` neu anlegen:

```bash
#!/bin/bash
# Builds Piper 2023.11.14-2 as a universal (arm64 + x86_64) program for macOS 13.0 from the
# pinned sources (scripts/fetch.sh) and assembles piper/build/dist:
#   Helpers/piper/piper, Helpers/piper/lib/*.dylib           (program, found via @executable_path/lib)
#   Resources/piper/espeak-ng-data/…                          (German + English only)
#   Resources/piper/voices/de_DE-thorsten-medium.onnx(.json)  (the bundled voice)
#   Resources/piper/ThirdPartyNotices-onnxruntime.txt, Resources/piper/build-scripts/…
# The official macOS release tarballs of 2023.11.14-2 cannot be used: both are x86_64 only and
# lack the three dylibs. Skips the build when dist/STAMP matches the build scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$("${ROOT}/scripts/fetch.sh")"
OUT="${ROOT}/build"
DIST="${OUT}/dist"
STAMP_VALUE="$(cat "${ROOT}/scripts/fetch.sh" "${ROOT}/scripts/build-piper.sh" | shasum -a 256 | awk '{print $1}')"

if [[ -f "${DIST}/STAMP" && "$(cat "${DIST}/STAMP")" == "${STAMP_VALUE}" \
      && -x "${DIST}/Helpers/piper/piper" ]]; then
  echo "build-piper: ${DIST} ist aktuell"
  exit 0
fi

WORK="${OUT}/work"
rm -rf "${WORK}" "${DIST}"
mkdir -p "${WORK}/src"
for archive in cmake-3.31.8-macos-universal.tar.gz piper-2023.11.14-2.tar.gz piper-phonemize-bfc2e75.tar.gz \
               espeak-ng-0f65aa3.tar.gz fmt-10.0.0.tar.gz spdlog-1.12.0.tar.gz onnxruntime-osx-universal2-1.14.1.tgz; do
  tar -xzf "${CACHE}/${archive}" -C "${WORK}/src"
done
SRC="${WORK}/src"
CMAKE="${SRC}/cmake-3.31.8-macos-universal/CMake.app/Contents/bin/cmake"
ORT="${SRC}/onnxruntime-osx-universal2-1.14.1"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
JOBS="$(sysctl -n hw.ncpu)"

# Xcode build phases export SDKROOT, ARCHS, CC … – CMake must see none of it.
CLEAN_ENV=(PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME="${HOME}")
if [[ -n "${DEVELOPER_DIR:-}" ]]; then CLEAN_ENV+=(DEVELOPER_DIR="${DEVELOPER_DIR}"); fi
run() {
  env -i "${CLEAN_ENV[@]}" "$@"
}
configure() {
  local source="$1" build="$2"; shift 2
  run "${CMAKE}" -S "${source}" -B "${build}" -DCMAKE_BUILD_TYPE=Release \
    "-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64" -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
    -DCMAKE_OSX_SYSROOT="${SDK}" "$@" > "${build}.log" 2>&1
}
build() {
  local build="$1"; shift
  run "${CMAKE}" --build "${build}" -j "${JOBS}" "$@" >> "${build}.log" 2>&1
  run "${CMAKE}" --install "${build}" >> "${build}.log" 2>&1
}

echo "build-piper: fmt, spdlog"
configure "${SRC}/fmt-10.0.0" "${WORK}/b-fmt" -DFMT_TEST=OFF -DCMAKE_INSTALL_PREFIX="${WORK}/fi"
build "${WORK}/b-fmt"
configure "${SRC}/spdlog-1.12.0" "${WORK}/b-spdlog" -DSPDLOG_BUILD_EXAMPLE=OFF -DCMAKE_INSTALL_PREFIX="${WORK}/si"
build "${WORK}/b-spdlog"

echo "build-piper: espeak-ng"
configure "${SRC}/espeak-ng-0f65aa301e0d6bae5e172cc74197d32a6182200f" "${WORK}/b-espeak" \
  -DCMAKE_INSTALL_PREFIX="${WORK}/ei" -DUSE_ASYNC=OFF -DBUILD_SHARED_LIBS=ON -DUSE_MBROLA=OFF \
  -DUSE_LIBSONIC=OFF -DUSE_LIBPCAUDIO=OFF -DUSE_KLATT=OFF -DUSE_SPEECHPLAYER=OFF \
  -DEXTRA_cmn=ON -DEXTRA_ru=ON -DCMAKE_C_FLAGS=-D_FILE_OFFSET_BITS=64
build "${WORK}/b-espeak"

echo "build-piper: piper-phonemize"
configure "${SRC}/piper-phonemize-bfc2e7549957829b0227c66a305d11cc88167bda" "${WORK}/b-phonemize" \
  -DCMAKE_INSTALL_PREFIX="${WORK}/pi" -DONNXRUNTIME_DIR="${ORT}" -DESPEAK_NG_DIR="${WORK}/ei"
build "${WORK}/b-phonemize"

echo "build-piper: piper"
configure "${SRC}/piper-2023.11.14-2" "${WORK}/b-piper" -DCMAKE_INSTALL_PREFIX="${WORK}/out" \
  -DFMT_DIR="${WORK}/fi" -DSPDLOG_DIR="${WORK}/si" -DPIPER_PHONEMIZE_DIR="${WORK}/pi"
run "${CMAKE}" --build "${WORK}/b-piper" --target piper -j "${JOBS}" >> "${WORK}/b-piper.log" 2>&1

HELPERS="${DIST}/Helpers/piper"
RESOURCES="${DIST}/Resources/piper"
mkdir -p "${HELPERS}/lib" "${RESOURCES}/espeak-ng-data/lang/gmw" "${RESOURCES}/voices" "${RESOURCES}/build-scripts"
cp "${WORK}/b-piper/piper" "${HELPERS}/piper"
cp -L "${WORK}/ei/lib/libespeak-ng.1.dylib" "${WORK}/pi/lib/libpiper_phonemize.1.dylib" \
      "${ORT}/lib/libonnxruntime.1.14.1.dylib" "${HELPERS}/lib/"
chmod 755 "${HELPERS}/piper"
chmod 644 "${HELPERS}/lib/"*.dylib

# Build-machine rpaths out, the bundle's own in.
strip_rpaths() {
  local file="$1" path
  for path in $(otool -l "${file}" | awk '/cmd LC_RPATH/ {getline; getline; print $2}' | sort -u); do
    install_name_tool -delete_rpath "${path}" "${file}" 2>/dev/null
  done
}
strip_rpaths "${HELPERS}/piper"
install_name_tool -add_rpath @executable_path/lib "${HELPERS}/piper" 2>/dev/null
for lib in "${HELPERS}/lib/"*.dylib; do
  strip_rpaths "${lib}"
done

# German voices only; English for words eSpeak marks as English ("Computer", "okay").
DATA="${WORK}/ei/share/espeak-ng-data"
cp "${DATA}/phontab" "${DATA}/phonindex" "${DATA}/phondata" "${DATA}/intonations" \
   "${DATA}/de_dict" "${DATA}/en_dict" "${RESOURCES}/espeak-ng-data/"
cp "${DATA}/lang/gmw/de" "${DATA}/lang/gmw/en" "${RESOURCES}/espeak-ng-data/lang/gmw/"

cp "${CACHE}/de_DE-thorsten-medium.onnx" "${CACHE}/de_DE-thorsten-medium.onnx.json" "${RESOURCES}/voices/"
cp "${ORT}/ThirdPartyNotices.txt" "${RESOURCES}/ThirdPartyNotices-onnxruntime.txt"
cp "${ROOT}/scripts/fetch.sh" "${ROOT}/scripts/build-piper.sh" "${RESOURCES}/build-scripts/"

# Ad-hoc signature so the program runs straight from dist (embed.sh signs again for the app).
codesign --force --sign - "${HELPERS}/lib/"*.dylib "${HELPERS}/piper" 2>/dev/null

for file in "${HELPERS}/piper" "${HELPERS}/lib/"*.dylib; do
  archs="$(lipo -archs "${file}")"
  if [[ " ${archs} " != *" arm64 "* || " ${archs} " != *" x86_64 "* ]]; then
    echo "build-piper: ${file} ist nicht universal (${archs})" >&2
    exit 1
  fi
done
echo "${STAMP_VALUE}" > "${DIST}/STAMP"
rm -rf "${WORK}"
echo "build-piper: ${DIST}"
```

- [ ] **Step 4: Smoke-Test**

Datei `piper/scripts/smoke.sh` neu anlegen:

```bash
#!/bin/bash
# Lets the Piper of an app bundle (or of piper/build/dist) speak one German sentence with
# Thorsten (medium) and checks the result: exit 0, a 16-bit mono 22050 Hz WAV of more than 1 s.
#   scripts/smoke.sh                       → piper/build/dist
#   scripts/smoke.sh "<path>/Contents"     → an app bundle's Contents folder
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${1:-${ROOT}/build/dist}"
PIPER="${BASE}/Helpers/piper/piper"
RES="${BASE}/Resources/piper"
WAV="$(mktemp "${TMPDIR:-/tmp}/piper-smoke.XXXXXX").wav"
trap 'rm -f "${WAV}"' EXIT

START=$(date +%s)
echo "Achtung: An der Haustür hat jemand geklingelt." | "${PIPER}" --quiet \
  --model "${RES}/voices/de_DE-thorsten-medium.onnx" --config "${RES}/voices/de_DE-thorsten-medium.onnx.json" \
  --espeak_data "${RES}/espeak-ng-data" --output_file "${WAV}" > /dev/null
INFO="$(afinfo "${WAV}")"
grep -q "1 ch,  22050 Hz, Int16" <<< "${INFO}" || { echo "piper-smoke: falsches Format" >&2; echo "${INFO}" >&2; exit 1; }
SECONDS_AUDIO="$(awk '/estimated duration/ {print $3}' <<< "${INFO}")"
awk -v d="${SECONDS_AUDIO}" 'BEGIN { exit !(d > 1.0) }' || { echo "piper-smoke: zu kurz (${SECONDS_AUDIO} s)" >&2; exit 1; }
echo "piper-smoke: ok (${SECONDS_AUDIO} s Ton in $(( $(date +%s) - START )) s)"
```

- [ ] **Step 5: Ausführbar machen, bauen, prüfen**

```bash
chmod +x piper/scripts/fetch.sh piper/scripts/build-piper.sh piper/scripts/smoke.sh
time piper/scripts/build-piper.sh
```

Erwartet (erstes Mal, mit Netz, ≈ 1 min): `fetch: lade …` für jede Datei auf stderr, dann
`build-piper: fmt, spdlog` · `build-piper: espeak-ng` · `build-piper: piper-phonemize` · `build-piper: piper` · `build-piper: …/piper/build/dist`. Schlägt ein Schritt fehl, steht das CMake-Protokoll in `piper/build/work/b-*.log` (der Ordner bleibt dann stehen).

```bash
piper/scripts/build-piper.sh                       # → build-piper: …/dist ist aktuell
piper/scripts/smoke.sh                             # → piper-smoke: ok (2.6 s Ton in 1 s)
for f in piper/build/dist/Helpers/piper/piper piper/build/dist/Helpers/piper/lib/*.dylib; do lipo -archs "$f"; done
# → viermal: x86_64 arm64
otool -l piper/build/dist/Helpers/piper/piper | grep -A2 LC_RPATH | grep path   # → nur @executable_path/lib (2×, je Architektur)
otool -l piper/build/dist/Helpers/piper/piper | grep -A3 LC_BUILD_VERSION | grep minos   # → minos 13.0 (2×)
du -sh piper/build/dist/Helpers piper/build/dist/Resources   # → ≈ 46M, ≈ 61M
git status --short   # → nur .gitignore und piper/scripts/ (kein .cache, kein build)
```

- [ ] **Step 6: Commit**

```bash
git add .gitignore piper/scripts/fetch.sh piper/scripts/build-piper.sh piper/scripts/smoke.sh
git diff --cached --name-only | grep AppConfig   # → leer
git commit -m "build(piper): pinned universal Piper 2023.11.14-2 build with Thorsten (medium)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: AppCore – Stimmenkatalog, Stimmenwahl, Migration alter Ansagen (Gruppe A, unabhängig)

**Files:**
- Create: `Packages/AppCore/Sources/AppCore/Sound/PiperVoiceCatalog.swift`
- Create: `Packages/AppCore/Sources/AppCore/Sound/VoiceSelection.swift`
- Test: `Packages/AppCore/Tests/AppCoreTests/PiperVoiceCatalogTests.swift`, `Packages/AppCore/Tests/AppCoreTests/VoiceSelectionTests.swift`

**Interfaces:**
- Consumes: `Announcement` (`kind`, `text`, `voiceIdentifier`, `fileName`, `usesBundledRecording`), `SoundSettings.bundledBinGleichDa` (bestehend).
- Produces:
  - `enum PiperQuality: String { xLow, low, medium, high }` mit `label: String`
  - `struct VoiceLicense { name, dataset, url: String; allowsRedistribution: Bool; attribution: String? }` + `.thorstenCC0`, `.kerstinCC0`, `.mailabs`, `.mlsCCBY4`, `.pavoqueNC`
  - `struct VoiceFile { path: String; size: Int64; sha256: String; fileName: String; url: URL }`
  - `struct PiperVoice: Identifiable { id, name: String; quality: PiperQuality; sampleRate: Int; model, config: VoiceFile; license: VoiceLicense; speakerNames: [String]; speakerCount: Int; defaultSpeaker: Int; isMultiSpeaker: Bool; downloadSize: Int64; label: String; func speakerLabel(_: Int) -> String?; sizeText: String; func menuTitle(_: VoiceAvailability) -> String; func progressText(received: Int64) -> String; licenseText: String; static menuOrder: [PiperVoice] }`
  - `enum PiperVoiceCatalog { static revision, bundledVoiceId: String; static all, offered, excluded: [PiperVoice]; static bundled: PiperVoice; static func voice(id: String) -> PiperVoice? }`
  - `struct PiperVoiceRef: Hashable { voiceId: String; speaker: Int; init(voiceId:speaker:); init(voice:); init?(identifier: String?); identifier: String; static standard; resolved: (voice: PiperVoice, speaker: Int)?; label: String }`
  - `enum AnnouncementVoice { piper(PiperVoiceRef), bundledRecording, legacyMacOS, none; static func of(_:) ; static func initialSelection(for:) -> PiperVoiceRef; static func note(for:) -> String?; static func canApply(_:text:selection:) -> Bool }`
  - `enum VoiceAvailability { bundled, downloaded, notDownloaded }`

- [ ] **Step 1: Write the failing tests**

Datei `Packages/AppCore/Tests/AppCoreTests/PiperVoiceCatalogTests.swift` neu anlegen:

```swift
import XCTest
@testable import AppCore

final class PiperVoiceCatalogTests: XCTestCase {
    func testEveryGermanVoiceIsListedOnce() {
        XCTAssertEqual(PiperVoiceCatalog.all.map(\.id), [
            "de_DE-eva_k-x_low", "de_DE-karlsson-low", "de_DE-kerstin-low", "de_DE-mls-medium", "de_DE-pavoque-low",
            "de_DE-ramona-low", "de_DE-thorsten-low", "de_DE-thorsten-medium", "de_DE-thorsten-high",
            "de_DE-thorsten_emotional-medium",
        ])
        XCTAssertEqual(Set(PiperVoiceCatalog.all.map(\.id)).count, PiperVoiceCatalog.all.count)
    }

    func testNonCommercialVoicesAreNotOffered() {
        XCTAssertEqual(PiperVoiceCatalog.excluded.map(\.id), ["de_DE-pavoque-low"])
        XCTAssertFalse(PiperVoiceCatalog.offered.contains { $0.id == "de_DE-pavoque-low" })
        XCTAssertNil(PiperVoiceCatalog.voice(id: "de_DE-pavoque-low"))
        XCTAssertNil(PiperVoiceCatalog.voice(id: "en_US-lessac-medium"))
        XCTAssertEqual(PiperVoiceCatalog.offered.count, 9)
        XCTAssertTrue(PiperVoiceCatalog.offered.allSatisfy { $0.license.allowsRedistribution })
    }

    func testBundledVoiceIsThorstenMedium() {
        let voice = PiperVoiceCatalog.bundled
        XCTAssertEqual(voice.id, "de_DE-thorsten-medium")
        XCTAssertEqual(voice.label, "Thorsten · mittel")
        XCTAssertEqual(voice.license, .thorstenCC0)
        // Same pin as piper/scripts/fetch.sh – the bundled file is the catalog's file.
        XCTAssertEqual(voice.model.sha256, "7e64762d8e5118bb578f2eea6207e1a35a8e0c30595010b666f983fc87bb7819")
        XCTAssertEqual(voice.config.sha256, "974adee790533adb273a1ac88f49027d2a1b8f0f2cf4905954a4791e79264e85")
    }

    func testFilesArePinnedToTheRevision() {
        for voice in PiperVoiceCatalog.all {
            for file in [voice.model, voice.config] {
                XCTAssertEqual(file.sha256.count, 64, file.path)
                XCTAssertNotNil(file.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression), file.path)
                XCTAssertGreaterThan(file.size, 0)
                XCTAssertTrue(file.url.absoluteString.hasPrefix(
                    "https://huggingface.co/rhasspy/piper-voices/resolve/c10ece1aade47bb51c153c893d14e5bf8e5b7117/de/de_DE/"))
                XCTAssertFalse(file.url.absoluteString.contains("/main/"))
            }
            XCTAssertEqual(voice.config.fileName, voice.model.fileName + ".json")
            XCTAssertEqual(voice.model.fileName, voice.id + ".onnx")
        }
    }

    func testSpeakers() throws {
        let emotional = try XCTUnwrap(PiperVoiceCatalog.voice(id: "de_DE-thorsten_emotional-medium"))
        XCTAssertEqual(emotional.speakerCount, 8)
        XCTAssertEqual(emotional.defaultSpeaker, 4)
        XCTAssertEqual(emotional.speakerLabel(4), "neutral")
        XCTAssertEqual(emotional.speakerLabel(7), "flüsternd")
        XCTAssertNil(emotional.speakerLabel(8))
        let mls = try XCTUnwrap(PiperVoiceCatalog.voice(id: "de_DE-mls-medium"))
        XCTAssertEqual(mls.speakerCount, 236)
        XCTAssertEqual(mls.speakerLabel(0), "Sprecher 1")
        XCTAssertEqual(mls.speakerLabel(235), "Sprecher 236")
        XCTAssertNil(PiperVoiceCatalog.bundled.speakerLabel(0))
        XCTAssertFalse(PiperVoiceCatalog.bundled.isMultiSpeaker)
    }

    func testDownloadSizeIsModelPlusConfig() throws {
        let high = try XCTUnwrap(PiperVoiceCatalog.voice(id: "de_DE-thorsten-high"))
        XCTAssertEqual(high.downloadSize, 113_895_201 + 4_875)
        XCTAssertEqual(high.label, "Thorsten · hoch")
        XCTAssertEqual(PiperVoiceCatalog.voice(id: "de_DE-eva_k-x_low")?.label, "Eva K. · sehr niedrig")
    }
}
```

Datei `Packages/AppCore/Tests/AppCoreTests/VoiceSelectionTests.swift` neu anlegen:

```swift
import XCTest
@testable import AppCore

final class VoiceSelectionTests: XCTestCase {
    private let emotional = PiperVoiceRef(voiceId: "de_DE-thorsten_emotional-medium", speaker: 7)

    func testIdentifierRoundTrip() {
        XCTAssertEqual(emotional.identifier, "piper:de_DE-thorsten_emotional-medium#7")
        XCTAssertEqual(PiperVoiceRef(identifier: emotional.identifier), emotional)
        XCTAssertEqual(PiperVoiceRef(identifier: "piper:de_DE-thorsten-medium"), .standard)
        for bad in [nil, "", "piper:", "piper:#1", "piper:x#-1", "piper:x#a", "com.apple.voice.premium.de-DE.Anna"] {
            XCTAssertNil(PiperVoiceRef(identifier: bad), bad ?? "nil")
        }
    }

    func testLabels() {
        XCTAssertEqual(PiperVoiceRef.standard.label, "Thorsten · mittel")
        XCTAssertEqual(emotional.label, "Thorsten emotional · mittel · flüsternd")
        XCTAssertEqual(PiperVoiceRef(voiceId: "de_DE-mls-medium", speaker: 11).label, "MLS · mittel · Sprecher 12")
        XCTAssertEqual(PiperVoiceRef(voiceId: "de_DE-pavoque-low").label, "Unbekannte Stimme")
        // A speaker outside the range falls back to the voice's default.
        XCTAssertEqual(PiperVoiceRef(voiceId: "de_DE-thorsten_emotional-medium", speaker: 99).resolved?.speaker, 4)
    }

    func testOldMacOSAnnouncementKeepsItsFileAndAsksForRerendering() {
        let old = Announcement(name: "Hallo", kind: .speech, text: "Hallo.",
                               voiceIdentifier: "com.apple.voice.premium.de-DE.Anna", fileName: "a.caf", duration: 1)
        XCTAssertEqual(AnnouncementVoice.of(old), .legacyMacOS)
        XCTAssertEqual(AnnouncementVoice.note(for: old), "macOS (alt) – mit „Übernehmen“ neu erzeugen")
        XCTAssertEqual(AnnouncementVoice.initialSelection(for: old), .standard)
        // Same text, Thorsten selected: still re-renderable.
        XCTAssertTrue(AnnouncementVoice.canApply(old, text: "Hallo.", selection: .standard))
    }

    func testBundledRecordingCountsAsThorstenMedium() {
        let bundled = SoundSettings.bundledBinGleichDa
        XCTAssertEqual(AnnouncementVoice.of(bundled), .bundledRecording)
        XCTAssertNil(AnnouncementVoice.note(for: bundled))
        XCTAssertEqual(AnnouncementVoice.initialSelection(for: bundled), .standard)
        XCTAssertFalse(AnnouncementVoice.canApply(bundled, text: bundled.text, selection: .standard))
        XCTAssertTrue(AnnouncementVoice.canApply(bundled, text: bundled.text, selection: emotional))
        XCTAssertTrue(AnnouncementVoice.canApply(bundled, text: "Bin gleich da.", selection: .standard))
    }

    func testPiperAnnouncement() {
        let entry = Announcement(name: "X", kind: .speech, text: "Paket bitte abstellen.",
                                 voiceIdentifier: emotional.identifier, fileName: "x.wav", duration: 2)
        XCTAssertEqual(AnnouncementVoice.of(entry), .piper(emotional))
        XCTAssertEqual(AnnouncementVoice.initialSelection(for: entry), emotional)
        XCTAssertFalse(AnnouncementVoice.canApply(entry, text: " Paket bitte abstellen. ", selection: emotional))
        XCTAssertTrue(AnnouncementVoice.canApply(entry, text: "Paket bitte abstellen.", selection: .standard))
        XCTAssertFalse(AnnouncementVoice.canApply(entry, text: "   ", selection: .standard))
        XCTAssertFalse(AnnouncementVoice.canApply(entry, text: "Neu", selection: PiperVoiceRef(voiceId: "de_DE-pavoque-low")))
    }

    func testRemovedVoiceStillPlaysButAsksForRerendering() {
        let entry = Announcement(name: "X", kind: .speech, text: "Hallo.",
                                 voiceIdentifier: "piper:de_DE-pavoque-low#0", fileName: "x.wav", duration: 1)
        XCTAssertEqual(AnnouncementVoice.note(for: entry), "Diese Stimme gibt es nicht mehr – mit „Übernehmen“ neu erzeugen")
        XCTAssertEqual(AnnouncementVoice.initialSelection(for: entry), .standard)
        XCTAssertTrue(AnnouncementVoice.canApply(entry, text: "Hallo.", selection: .standard))
    }

    func testNewTextAndMP3Entries() {
        let fresh = Announcement(name: Announcement.newName, kind: .speech, voiceIdentifier: PiperVoiceRef.standard.identifier)
        XCTAssertEqual(AnnouncementVoice.of(fresh), .none)
        XCTAssertFalse(AnnouncementVoice.canApply(fresh, text: "", selection: .standard))
        XCTAssertTrue(AnnouncementVoice.canApply(fresh, text: "Hallo", selection: .standard))
        let mp3 = Announcement(name: "Gong", kind: .file, fileName: "g.mp3", duration: 3)
        XCTAssertEqual(AnnouncementVoice.of(mp3), .none)
        XCTAssertTrue(AnnouncementVoice.canApply(mp3, text: "Hallo", selection: .standard))
    }
}

final class VoiceMenuTests: XCTestCase {
    func testMenuTitlesAndSizes() throws {
        let kerstin = try XCTUnwrap(PiperVoiceCatalog.voice(id: "de_DE-kerstin-low"))
        XCTAssertEqual(kerstin.sizeText, "63 MB")
        XCTAssertEqual(kerstin.menuTitle(.notDownloaded), "Kerstin · niedrig – 63 MB laden")
        XCTAssertEqual(kerstin.menuTitle(.downloaded), "Kerstin · niedrig – geladen")
        XCTAssertEqual(PiperVoiceCatalog.bundled.menuTitle(.bundled), "Thorsten · mittel – mitgeliefert")
        XCTAssertEqual(PiperVoiceCatalog.voice(id: "de_DE-thorsten-high")?.sizeText, "114 MB")
        XCTAssertEqual(PiperVoiceCatalog.voice(id: "de_DE-eva_k-x_low")?.sizeText, "21 MB")
    }

    func testProgressText() throws {
        let kerstin = try XCTUnwrap(PiperVoiceCatalog.voice(id: "de_DE-kerstin-low"))
        XCTAssertEqual(kerstin.progressText(received: 23_400_000), "Lade „Kerstin · niedrig“ … 23 von 63 MB")
        XCTAssertEqual(kerstin.progressText(received: -5), "Lade „Kerstin · niedrig“ … 0 von 63 MB")
        XCTAssertEqual(kerstin.progressText(received: 999_000_000), "Lade „Kerstin · niedrig“ … 63 von 63 MB")
    }

    func testMenuOrderStartsWithTheBundledVoiceAndLeavesOutPavoque() {
        let ids = PiperVoice.menuOrder.map(\.id)
        XCTAssertEqual(ids.first, "de_DE-thorsten-medium")
        XCTAssertEqual(ids.count, 9)
        XCTAssertFalse(ids.contains("de_DE-pavoque-low"))
        XCTAssertEqual(Set(ids).count, 9)
    }

    func testLicenseText() {
        XCTAssertEqual(PiperVoiceCatalog.bundled.licenseText, "Lizenz der Stimme: CC0 1.0 · Thorsten-Voice (Thorsten Müller)")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `(cd Packages/AppCore && swift test --filter "PiperVoiceCatalogTests|VoiceSelectionTests|VoiceMenuTests" 2>&1 | grep -E "error:" | head -5)`
Expected: FAIL – `cannot find 'PiperVoiceCatalog' in scope` / `cannot find 'PiperVoiceRef' in scope`.

- [ ] **Step 3: Katalog**

Datei `Packages/AppCore/Sources/AppCore/Sound/PiperVoiceCatalog.swift` neu anlegen:

```swift
import Foundation

/// Quality level of a Piper voice (`voices.json` › `quality`).
public enum PiperQuality: String, Codable, Sendable, CaseIterable {
    case xLow = "x_low"
    case low
    case medium
    case high

    /// „sehr niedrig“ … „hoch“ – second part of „Thorsten · mittel“.
    public var label: String {
        switch self {
        case .xLow: return "sehr niedrig"
        case .low: return "niedrig"
        case .medium: return "mittel"
        case .high: return "hoch"
        }
    }
}

/// License of a voice's training data (from its MODEL_CARD at `PiperVoiceCatalog.revision`).
public struct VoiceLicense: Equatable, Sendable {
    /// „CC0 1.0“, „CC BY 4.0“ …
    public let name: String
    /// Dataset the voice was trained on.
    public let dataset: String
    public let url: String
    /// Commercial use and redistribution allowed – otherwise the voice is not offered.
    public let allowsRedistribution: Bool
    /// Shown in „Über“ when the license asks for attribution.
    public let attribution: String?

    public static let thorstenCC0 = VoiceLicense(
        name: "CC0 1.0", dataset: "Thorsten-Voice (Thorsten Müller)",
        url: "https://github.com/thorstenMueller/Thorsten-Voice", allowsRedistribution: true, attribution: nil)
    public static let kerstinCC0 = VoiceLicense(
        name: "CC0 1.0", dataset: "dataset-voice-kerstin (Rhasspy)",
        url: "https://github.com/rhasspy/dataset-voice-kerstin", allowsRedistribution: true, attribution: nil)
    public static let mailabs = VoiceLicense(
        name: "M-AILABS-Lizenz (BSD-artig, kommerziell erlaubt)", dataset: "M-AILABS Speech Dataset",
        url: "https://www.caito.de/2019/01/03/the-m-ailabs-speech-dataset/", allowsRedistribution: true,
        attribution: "Copyright (c) 2017-2019 by the original creators @ M-AILABS")
    public static let mlsCCBY4 = VoiceLicense(
        name: "CC BY 4.0", dataset: "Multilingual LibriSpeech (OpenSLR 94)",
        url: "http://openslr.org/94/", allowsRedistribution: true,
        attribution: "Multilingual LibriSpeech (MLS), Pratap et al. 2020, CC BY 4.0")
    public static let pavoqueNC = VoiceLicense(
        name: "CC BY-NC-SA 4.0", dataset: "PAVOQUE (MaryTTS)",
        url: "https://github.com/marytts/pavoque-data", allowsRedistribution: false, attribution: nil)
}

/// One downloadable file of a voice, pinned by size and SHA-256.
public struct VoiceFile: Equatable, Sendable {
    /// Path inside the Hugging Face repository `rhasspy/piper-voices`.
    public let path: String
    public let size: Int64
    public let sha256: String

    public init(path: String, size: Int64, sha256: String) {
        self.path = path
        self.size = size
        self.sha256 = sha256
    }

    public var fileName: String { (path as NSString).lastPathComponent }

    /// Fixed revision – never `main`.
    public var url: URL {
        URL(string: "https://huggingface.co/rhasspy/piper-voices/resolve/\(PiperVoiceCatalog.revision)/\(path)")!
    }
}

/// One German Piper voice (model + config) from `rhasspy/piper-voices`.
public struct PiperVoice: Equatable, Identifiable, Sendable {
    /// `voices.json` key, e.g. „de_DE-thorsten-medium“.
    public let id: String
    public let name: String
    public let quality: PiperQuality
    public let sampleRate: Int
    public let model: VoiceFile
    public let config: VoiceFile
    public let license: VoiceLicense
    /// Speaker labels by index (Piper `--speaker`); empty = numbered „Sprecher 1 …“.
    public let speakerNames: [String]
    public let speakerCount: Int
    public let defaultSpeaker: Int

    public init(id: String, name: String, quality: PiperQuality, sampleRate: Int, model: VoiceFile, config: VoiceFile,
                license: VoiceLicense, speakerNames: [String] = [], speakerCount: Int? = nil, defaultSpeaker: Int = 0) {
        self.id = id
        self.name = name
        self.quality = quality
        self.sampleRate = sampleRate
        self.model = model
        self.config = config
        self.license = license
        self.speakerNames = speakerNames
        self.speakerCount = speakerCount ?? max(1, speakerNames.count)
        self.defaultSpeaker = defaultSpeaker
    }

    public var isMultiSpeaker: Bool { speakerCount > 1 }
    /// Model + config.
    public var downloadSize: Int64 { model.size + config.size }
    /// „Thorsten · mittel“.
    public var label: String { "\(name) · \(quality.label)" }

    /// „neutral“ / „Sprecher 12“; nil for single-speaker voices.
    public func speakerLabel(_ index: Int) -> String? {
        guard isMultiSpeaker, (0..<speakerCount).contains(index) else { return nil }
        return index < speakerNames.count ? speakerNames[index] : "Sprecher \(index + 1)"
    }
}

/// Every German voice of `rhasspy/piper-voices` at `revision` (de_DE only – no de_AT/de_CH exists).
/// Sizes and SHA-256 of the models are the Git-LFS object ids; the configs were hashed at the revision.
public enum PiperVoiceCatalog {
    public static let revision = "c10ece1aade47bb51c153c893d14e5bf8e5b7117"
    /// The voice shipped in the app (Contents/Resources/piper/voices) and used for new announcements.
    public static let bundledVoiceId = "de_DE-thorsten-medium"

    public static let all: [PiperVoice] = [
        PiperVoice(
            id: "de_DE-eva_k-x_low", name: "Eva K.", quality: .xLow, sampleRate: 16000,
            model: .init(path: "de/de_DE/eva_k/x_low/de_DE-eva_k-x_low.onnx", size: 20628813, sha256: "e88cf290fbfb768bf111330d2e8a46e376b0d85e3423a28bfebbc863a260dad8"),
            config: .init(path: "de/de_DE/eva_k/x_low/de_DE-eva_k-x_low.onnx.json", size: 4158, sha256: "ef14b3dcb279ab4b18422a7a132877bee7a148821bd91152fb7ae9c4b3d79625"),
            license: .mailabs
        ),
        PiperVoice(
            id: "de_DE-karlsson-low", name: "Karlsson", quality: .low, sampleRate: 16000,
            model: .init(path: "de/de_DE/karlsson/low/de_DE-karlsson-low.onnx", size: 63104526, sha256: "f9793bf7e461a472b3916cf260774bfc9812e9eb72601b147ed649d01064e8fe"),
            config: .init(path: "de/de_DE/karlsson/low/de_DE-karlsson-low.onnx.json", size: 4159, sha256: "3b2095adbfeede316f22007a0a09d4bfc25514b7189850740b06800a6cfb9838"),
            license: .mailabs
        ),
        PiperVoice(
            id: "de_DE-kerstin-low", name: "Kerstin", quality: .low, sampleRate: 16000,
            model: .init(path: "de/de_DE/kerstin/low/de_DE-kerstin-low.onnx", size: 63104526, sha256: "d352a7641892cebf2903859af94e9ba81a141110215fe3943bcda7f7da401b7a"),
            config: .init(path: "de/de_DE/kerstin/low/de_DE-kerstin-low.onnx.json", size: 4158, sha256: "56e708556b7b9b7a53c4f8957e021421e69f11a600962bba554cffbe72cf2d47"),
            license: .kerstinCC0
        ),
        PiperVoice(
            id: "de_DE-mls-medium", name: "MLS", quality: .medium, sampleRate: 22050,
            model: .init(path: "de/de_DE/mls/medium/de_DE-mls-medium.onnx", size: 76961079, sha256: "69cd1d2aa5a35839a518966fcc4924b5f93e5f8c948ed0752b1a616ad53f65bf"),
            config: .init(path: "de/de_DE/mls/medium/de_DE-mls-medium.onnx.json", size: 8948, sha256: "b0af1c89ddfdc72d32e015729b0e89b99eec13c2c8caa1db7488d98e9e570b40"),
            license: .mlsCCBY4, speakerCount: 236
        ),
        PiperVoice(
            id: "de_DE-pavoque-low", name: "Pavoque", quality: .low, sampleRate: 16000,
            model: .init(path: "de/de_DE/pavoque/low/de_DE-pavoque-low.onnx", size: 63104526, sha256: "96cd41fe2303dfe4745422a2580658bdbc5f935b7ee67640a94da7435a502a26"),
            config: .init(path: "de/de_DE/pavoque/low/de_DE-pavoque-low.onnx.json", size: 4158, sha256: "07d43d8946e869209a12d9b4fd780e3f277fe9afb305c21491a68bd97e01b74f"),
            license: .pavoqueNC
        ),
        PiperVoice(
            id: "de_DE-ramona-low", name: "Ramona", quality: .low, sampleRate: 16000,
            model: .init(path: "de/de_DE/ramona/low/de_DE-ramona-low.onnx", size: 63104526, sha256: "a1068592532aad8c49bf3d1a01b8749c11d7dba726689ee28ad64e7b627ae4c5"),
            config: .init(path: "de/de_DE/ramona/low/de_DE-ramona-low.onnx.json", size: 4157, sha256: "64906ab7a050ac685fa3dcea044baa798f67ed77be164f9c668a69298c6487d2"),
            license: .mailabs
        ),
        PiperVoice(
            id: "de_DE-thorsten-low", name: "Thorsten", quality: .low, sampleRate: 16000,
            model: .init(path: "de/de_DE/thorsten/low/de_DE-thorsten-low.onnx", size: 63104526, sha256: "9ac27fad17cec5c1a791161976a64f026f16fc058b400b1fea62565b8b2cf375"),
            config: .init(path: "de/de_DE/thorsten/low/de_DE-thorsten-low.onnx.json", size: 4159, sha256: "df38e892ed949f62d0c40978bc666de0b341c5f7921840ae7c72f4df8e8ffa05"),
            license: .thorstenCC0
        ),
        PiperVoice(
            id: "de_DE-thorsten-medium", name: "Thorsten", quality: .medium, sampleRate: 22050,
            model: .init(path: "de/de_DE/thorsten/medium/de_DE-thorsten-medium.onnx", size: 63201294, sha256: "7e64762d8e5118bb578f2eea6207e1a35a8e0c30595010b666f983fc87bb7819"),
            config: .init(path: "de/de_DE/thorsten/medium/de_DE-thorsten-medium.onnx.json", size: 4819, sha256: "974adee790533adb273a1ac88f49027d2a1b8f0f2cf4905954a4791e79264e85"),
            license: .thorstenCC0
        ),
        PiperVoice(
            id: "de_DE-thorsten-high", name: "Thorsten", quality: .high, sampleRate: 22050,
            model: .init(path: "de/de_DE/thorsten/high/de_DE-thorsten-high.onnx", size: 113895201, sha256: "9df1c43c61149ef9b39e618e2b861fbe41e1fcea9390b2dac62e8761573ea4f1"),
            config: .init(path: "de/de_DE/thorsten/high/de_DE-thorsten-high.onnx.json", size: 4875, sha256: "6de734444e4c3f9e33b7ebe2746dbc19b71e85f613e79c65acf623200b99a76a"),
            license: .thorstenCC0
        ),
        PiperVoice(
            id: "de_DE-thorsten_emotional-medium", name: "Thorsten emotional", quality: .medium, sampleRate: 22050,
            model: .init(path: "de/de_DE/thorsten_emotional/medium/de_DE-thorsten_emotional-medium.onnx", size: 76745905, sha256: "c1764e652266cd6dcebf1b95c61973df5970a5f5272e94b655ff1ddf9a99d1ff"),
            config: .init(path: "de/de_DE/thorsten_emotional/medium/de_DE-thorsten_emotional-medium.onnx.json", size: 5031, sha256: "92895b9e99f7cfc13f4a9879da615c3d6e0baa4d660e26d7b685abdd27a6d1d3"),
            license: .thorstenCC0, speakerNames: ["amüsiert", "wütend", "angewidert", "betrunken", "neutral", "schläfrig", "überrascht", "flüsternd"], defaultSpeaker: 4
        ),
    ]

    /// What the voice field lists: redistribution allowed (PAVOQUE is CC BY-NC-SA → left out).
    public static var offered: [PiperVoice] { all.filter(\.license.allowsRedistribution) }
    public static var excluded: [PiperVoice] { all.filter { !$0.license.allowsRedistribution } }

    public static var bundled: PiperVoice { voice(id: bundledVoiceId)! }

    /// Only offered voices – an excluded or unknown id is nil.
    public static func voice(id: String) -> PiperVoice? {
        offered.first { $0.id == id }
    }
}
```

- [ ] **Step 4: Stimmenwahl und Migration**

Datei `Packages/AppCore/Sources/AppCore/Sound/VoiceSelection.swift` neu anlegen:

```swift
import Foundation

/// A Piper voice plus speaker, stored in `Announcement.voiceIdentifier` as „piper:<id>#<speaker>“.
public struct PiperVoiceRef: Equatable, Hashable, Sendable {
    public static let prefix = "piper:"

    public let voiceId: String
    public let speaker: Int

    public init(voiceId: String, speaker: Int = 0) {
        self.voiceId = voiceId
        self.speaker = max(0, speaker)
    }

    /// The default for new announcements: Thorsten (medium).
    public static var standard: PiperVoiceRef { PiperVoiceRef(voiceId: PiperVoiceCatalog.bundledVoiceId) }

    /// Default speaker of a voice (neutral for Thorsten emotional).
    public init(voice: PiperVoice) {
        self.init(voiceId: voice.id, speaker: voice.defaultSpeaker)
    }

    public var identifier: String { "\(Self.prefix)\(voiceId)#\(speaker)" }

    /// nil for anything else (macOS identifiers „com.apple.…“, empty, malformed).
    public init?(identifier: String?) {
        guard let identifier, identifier.hasPrefix(Self.prefix) else { return nil }
        let body = identifier.dropFirst(Self.prefix.count)
        let parts = body.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first, !first.isEmpty else { return nil }
        var speaker = 0
        if parts.count == 2 {
            guard let value = Int(parts[1]), value >= 0 else { return nil }
            speaker = value
        }
        self.init(voiceId: String(first), speaker: speaker)
    }

    /// The offered voice, with the speaker clamped into its range (nil = unknown or excluded voice).
    public var resolved: (voice: PiperVoice, speaker: Int)? {
        guard let voice = PiperVoiceCatalog.voice(id: voiceId) else { return nil }
        let speaker = (0..<voice.speakerCount).contains(speaker) ? speaker : voice.defaultSpeaker
        return (voice, speaker)
    }

    /// „Thorsten emotional · mittel · neutral“ / „Thorsten · mittel“; „Unbekannte Stimme“ when gone.
    public var label: String {
        guard let (voice, speaker) = resolved else { return "Unbekannte Stimme" }
        guard let speakerLabel = voice.speakerLabel(speaker) else { return voice.label }
        return "\(voice.label) · \(speakerLabel)"
    }
}

/// Which voice an announcement's audio has (Phase 6: Piper only; macOS voices are gone).
public enum AnnouncementVoice: Equatable, Sendable {
    /// Rendered by Piper with this voice.
    case piper(PiperVoiceRef)
    /// One of the shipped recordings with its original wording (made with Piper, Thorsten medium).
    case bundledRecording
    /// Rendered by a macOS voice before Phase 6: still plays, „Übernehmen“ renders it again.
    case legacyMacOS
    /// MP3 entries, or text that was never rendered.
    case none

    public static func of(_ entry: Announcement) -> AnnouncementVoice {
        guard entry.kind == .speech else { return .none }
        if entry.usesBundledRecording { return .bundledRecording }
        if let ref = PiperVoiceRef(identifier: entry.voiceIdentifier) {
            return entry.fileName == nil ? .none : .piper(ref)
        }
        return entry.fileName == nil ? .none : .legacyMacOS
    }

    /// Voice the picker starts with for this entry: its own Piper voice, else Thorsten (medium).
    public static func initialSelection(for entry: Announcement) -> PiperVoiceRef {
        if case .piper(let ref) = of(entry), ref.resolved != nil { return ref }
        if let ref = PiperVoiceRef(identifier: entry.voiceIdentifier), ref.resolved != nil { return ref }
        return .standard
    }

    /// Note under the voice field; nil when the audio already matches.
    public static func note(for entry: Announcement) -> String? {
        switch of(entry) {
        case .legacyMacOS: return "macOS (alt) – mit „Übernehmen“ neu erzeugen"
        case .piper(let ref) where ref.resolved == nil:
            return "Diese Stimme gibt es nicht mehr – mit „Übernehmen“ neu erzeugen"
        default: return nil
        }
    }

    /// „Übernehmen“ is active when text or voice differ from the entry's audio (also for every
    /// macOS-rendered entry, so it can be rendered again with Piper).
    public static func canApply(_ entry: Announcement, text: String, selection: PiperVoiceRef) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, selection.resolved != nil else { return false }
        guard entry.kind == .speech, trimmed == entry.text else { return true }
        switch of(entry) {
        case .piper(let ref): return ref != selection
        case .bundledRecording: return selection != .standard
        case .legacyMacOS, .none: return true
        }
    }
}

/// Whether a voice can speak right away (bundled / downloaded) or must be downloaded first.
public enum VoiceAvailability: Equatable, Sendable {
    case bundled
    case downloaded
    case notDownloaded
}

extension PiperVoice {
    /// „63 MB“ – whole megabytes (10^6, like Finder), at least 1.
    public var sizeText: String {
        "\(max(1, Int((Double(downloadSize) / 1_000_000).rounded()))) MB"
    }

    /// Entry of the voice field: „Thorsten · mittel – mitgeliefert“, „… – geladen“, „Kerstin · niedrig – 63 MB laden“.
    public func menuTitle(_ availability: VoiceAvailability) -> String {
        switch availability {
        case .bundled: return "\(label) – mitgeliefert"
        case .downloaded: return "\(label) – geladen"
        case .notDownloaded: return "\(label) – \(sizeText) laden"
        }
    }

    /// „Lade „Kerstin · niedrig“ … 23 von 63 MB“.
    public func progressText(received: Int64) -> String {
        let done = Int((Double(max(0, min(received, downloadSize))) / 1_000_000).rounded(.down))
        return "Lade „\(label)“ … \(done) von \(sizeText)"
    }

    /// Line under the voice field: license of the training data.
    public var licenseText: String {
        "Lizenz der Stimme: \(license.name) · \(license.dataset)"
    }

    /// The voice field lists the bundled voice first, then the catalog order.
    public static var menuOrder: [PiperVoice] {
        let bundled = PiperVoiceCatalog.bundled
        return [bundled] + PiperVoiceCatalog.offered.filter { $0.id != bundled.id }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `(cd Packages/AppCore && swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -3)`
Expected: `Executed 142 tests, with 0 failures` (125 + 6 Katalog + 7 Auswahl + 4 Menü).

- [ ] **Step 6: Commit**

```bash
git add Packages/AppCore/Sources/AppCore/Sound/PiperVoiceCatalog.swift Packages/AppCore/Sources/AppCore/Sound/VoiceSelection.swift \
  Packages/AppCore/Tests/AppCoreTests/PiperVoiceCatalogTests.swift Packages/AppCore/Tests/AppCoreTests/VoiceSelectionTests.swift
git diff --cached --name-only | grep AppConfig   # → leer
git commit -m "feat(sound): German Piper voice catalog, voice choice and migration of old announcements

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: AppCore – Piper-Aufruf, Prozess mit Zeitlimit, WAV-Prüfung, Prüfsumme (Gruppe A; übernimmt `PiperVoiceCatalog.swift` aus Task 2)

**Files:**
- Create: `Packages/AppCore/Sources/AppCore/Sound/PiperCommand.swift`, `Packages/AppCore/Sources/AppCore/Sound/PiperRunner.swift`, `Packages/AppCore/Sources/AppCore/Sound/WAVFile.swift`, `Packages/AppCore/Sources/AppCore/Sound/FileChecksum.swift`
- Test: `Packages/AppCore/Tests/AppCoreTests/PiperCommandTests.swift`, `PiperRunnerTests.swift`, `WAVFileTests.swift`, `FileChecksumTests.swift`, `PiperIntegrationTests.swift` (alle unter `Packages/AppCore/Tests/AppCoreTests/`)

**Interfaces:**
- Consumes: `Loudness.gatedRMSdB(_:sampleRate:)`, `AnnouncementAudio.load(_:)`, `.loudnessGain(of:)` (bestehend). **Achtung Parallelbetrieb:** `PiperCommand.swift` und die Tests verwenden `PiperVoice`, `PiperVoiceCatalog` und `VoiceFile` aus Task 2. Läuft Task 3 in einem eigenen Worktree ohne Task 2, zuerst Task 2 Step 3 (nur `PiperVoiceCatalog.swift`, identischer Inhalt) mit übernehmen – beim Zusammenführen ist die Datei dann gleich.
- Produces:
  - `struct PiperInstallation { executable, espeakData, bundledVoices: URL; init(contents: URL) }` (`Contents/Helpers/piper/piper`, `Contents/Resources/piper/espeak-ng-data`, `Contents/Resources/piper/voices`)
  - `struct PiperVoiceFiles { model, config: URL; init(voice: PiperVoice, folder: URL) }`
  - `enum PiperCommand { static maxTextLength = 1000; static func arguments(installation:files:speaker: Int?, output: URL) -> [String]; static func input(for: String) -> String?; static func speakerArgument(voice:speaker:) -> Int? }`
  - `enum PiperError: Error, Equatable, LocalizedError { missing, timeout(TimeInterval), crashed(Int32), failed(Int32, String), noAudio, voiceNotInstalled(String), download(String), checksum(String) }`
  - `enum PiperRunner { static defaultTimeout = 20; static func run(executable: URL, arguments: [String], input: String, timeout: TimeInterval = 20) async throws }`
  - `struct WAVInfo { channels, sampleRate, bitsPerSample, dataOffset, dataLength: Int; duration; static func parse(Data) -> WAVInfo?; static func monoSamples(Data, info:) -> [Float]; static func hasSpeech(Data) -> Bool }`
  - `enum FileChecksum { static func sha256(of: URL) throws -> String; static func matches(URL, VoiceFile) -> Bool }`

- [ ] **Step 1: Write the failing tests**

Datei `Packages/AppCore/Tests/AppCoreTests/PiperCommandTests.swift` neu anlegen:

```swift
import XCTest
@testable import AppCore

final class PiperCommandTests: XCTestCase {
    private let installation = PiperInstallation(contents: URL(fileURLWithPath: "/Applications/UniFi Camera Popup.app/Contents"))

    func testInstallationPathsInsideTheBundle() {
        XCTAssertEqual(installation.executable.path, "/Applications/UniFi Camera Popup.app/Contents/Helpers/piper/piper")
        XCTAssertEqual(installation.espeakData.path, "/Applications/UniFi Camera Popup.app/Contents/Resources/piper/espeak-ng-data")
        XCTAssertEqual(installation.bundledVoices.path, "/Applications/UniFi Camera Popup.app/Contents/Resources/piper/voices")
    }

    func testArgumentsForASingleSpeakerVoice() {
        let files = PiperVoiceFiles(voice: PiperVoiceCatalog.bundled, folder: installation.bundledVoices)
        let output = URL(fileURLWithPath: "/tmp/out.wav")
        let speaker = PiperCommand.speakerArgument(voice: PiperVoiceCatalog.bundled, speaker: 3)
        XCTAssertNil(speaker)
        XCTAssertEqual(PiperCommand.arguments(installation: installation, files: files, speaker: speaker, output: output), [
            "--quiet",
            "--model", "/Applications/UniFi Camera Popup.app/Contents/Resources/piper/voices/de_DE-thorsten-medium.onnx",
            "--config", "/Applications/UniFi Camera Popup.app/Contents/Resources/piper/voices/de_DE-thorsten-medium.onnx.json",
            "--espeak_data", "/Applications/UniFi Camera Popup.app/Contents/Resources/piper/espeak-ng-data",
            "--output_file", "/tmp/out.wav",
        ])
    }

    func testSpeakerOnlyForMultiSpeakerVoices() throws {
        let emotional = try XCTUnwrap(PiperVoiceCatalog.voice(id: "de_DE-thorsten_emotional-medium"))
        XCTAssertEqual(PiperCommand.speakerArgument(voice: emotional, speaker: 7), 7)
        XCTAssertEqual(PiperCommand.speakerArgument(voice: emotional, speaker: 8), 4)
        let files = PiperVoiceFiles(voice: emotional, folder: URL(fileURLWithPath: "/v"))
        let arguments = PiperCommand.arguments(installation: installation, files: files, speaker: 7, output: URL(fileURLWithPath: "/o.wav"))
        XCTAssertEqual(Array(arguments.suffix(2)), ["--speaker", "7"])
    }

    func testInputIsOneLine() {
        XCTAssertEqual(PiperCommand.input(for: "  Bin gleich da!\nEinen\tMoment,   bitte. "), "Bin gleich da! Einen Moment, bitte.\n")
        XCTAssertNil(PiperCommand.input(for: " \n\t "))
        XCTAssertNil(PiperCommand.input(for: ""))
    }

    func testLongInputIsCutAtAWord() throws {
        let text = String(repeating: "Hallo ", count: 400)
        let line = try XCTUnwrap(PiperCommand.input(for: text))
        XCTAssertLessThanOrEqual(line.count, PiperCommand.maxTextLength + 1)
        XCTAssertTrue(line.hasSuffix("Hallo\n"))
        let oneWord = try XCTUnwrap(PiperCommand.input(for: String(repeating: "a", count: 2_000)))
        XCTAssertEqual(oneWord.count, PiperCommand.maxTextLength + 1)
    }
}
```

Datei `Packages/AppCore/Tests/AppCoreTests/PiperRunnerTests.swift` neu anlegen:

```swift
import XCTest
@testable import AppCore

/// The runner with `/bin/sh` standing in for Piper (exit codes, signals, hangs, stdin).
final class PiperRunnerTests: XCTestCase {
    private let shell = URL(fileURLWithPath: "/bin/sh")

    func testPassesTextOnStdin() async throws {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("runner-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: out) }
        try await PiperRunner.run(executable: shell, arguments: ["-c", "cat > \"$0\"", out.path], input: "Hallo Welt\n")
        XCTAssertEqual(try String(contentsOf: out, encoding: .utf8), "Hallo Welt\n")
    }

    func testMissingProgram() async {
        await assertThrows(.missing) {
            try await PiperRunner.run(executable: URL(fileURLWithPath: "/nonexistent/piper"), arguments: [], input: "x\n")
        }
    }

    func testExitCodeAndLastStderrLine() async {
        await assertThrows(.failed(3, "Model file doesn't exist")) {
            try await PiperRunner.run(executable: self.shell,
                                      arguments: ["-c", "echo first >&2; echo \"Model file doesn't exist\" >&2; exit 3"], input: "x\n")
        }
    }

    func testCrash() async {
        await assertThrows(.crashed(SIGABRT)) {
            try await PiperRunner.run(executable: self.shell, arguments: ["-c", "kill -ABRT $$"], input: "x\n")
        }
    }

    func testTimeoutEndsTheProcess() async {
        let start = Date()
        await assertThrows(.timeout(0.5)) {
            try await PiperRunner.run(executable: self.shell, arguments: ["-c", "sleep 30"], input: "x\n", timeout: 0.5)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testProgramThatIgnoresStdinDoesNotKillTheApp() async throws {
        // Exits before reading: the write into the closed pipe must not raise SIGPIPE here.
        try await PiperRunner.run(executable: shell, arguments: ["-c", "exit 0"],
                                  input: String(repeating: "x", count: 1 << 20))
    }

    func testCancellation() async {
        let task = Task {
            try await PiperRunner.run(executable: self.shell, arguments: ["-c", "sleep 30"], input: "x\n", timeout: 20)
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        do {
            try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
    }

    private func assertThrows(_ expected: PiperError, _ body: @escaping () async throws -> Void,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? PiperError, expected, file: file, line: line)
        }
    }

    func testMessagesAreGerman() {
        XCTAssertEqual(PiperError.timeout(20).errorDescription, "Piper hat nach 20 Sekunden keinen Ton geliefert und wurde beendet.")
        XCTAssertEqual(PiperError.voiceNotInstalled("Kerstin · niedrig").errorDescription, "Die Stimme „Kerstin · niedrig“ ist nicht geladen.")
        XCTAssertEqual(PiperError.failed(1, "").errorDescription, "Piper ist mit Fehler 1 beendet.")
    }
}
```

Datei `Packages/AppCore/Tests/AppCoreTests/WAVFileTests.swift` neu anlegen:

```swift
import XCTest
@testable import AppCore

final class WAVFileTests: XCTestCase {
    /// 16-bit PCM WAV as Piper writes it (44-byte header), optionally with a LIST chunk before data.
    static func wav(samples: [Int16], rate: Int = 22_050, channels: Int = 1, list: Bool = false, bits: Int = 16, format: Int = 1) -> Data {
        func u16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
        func u32(_ v: Int) -> [UInt8] { u16(v & 0xFFFF) + u16(v >> 16 & 0xFFFF) }
        let body = samples.flatMap { u16(Int(UInt16(bitPattern: $0))) }
        let listChunk: [UInt8] = list ? Array("LIST".utf8) + u32(5) + Array("INFOx".utf8) + [0] : []
        var bytes = Array("WAVE".utf8)
        bytes += Array("fmt ".utf8) + u32(16) + u16(format) + u16(channels) + u32(rate)
        bytes += u32(rate * channels * bits / 8) + u16(channels * bits / 8) + u16(bits)
        bytes += listChunk + Array("data".utf8) + u32(body.count) + body
        return Data(Array("RIFF".utf8) + u32(bytes.count) + bytes)
    }

    func testParsesPiperHeader() throws {
        let info = try XCTUnwrap(WAVInfo.parse(Self.wav(samples: [Int16](repeating: 0, count: 22_050))))
        XCTAssertEqual(info.channels, 1)
        XCTAssertEqual(info.sampleRate, 22_050)
        XCTAssertEqual(info.bitsPerSample, 16)
        XCTAssertEqual(info.dataOffset, 44)
        XCTAssertEqual(info.duration, 1.0, accuracy: 0.0001)
    }

    func testSkipsOtherChunksAndOddPadding() throws {
        let info = try XCTUnwrap(WAVInfo.parse(Self.wav(samples: [1, 2, 3], rate: 16_000, list: true)))
        XCTAssertEqual(info.dataOffset, 44 + 14)
        XCTAssertEqual(info.dataLength, 6)
    }

    func testRejectsWhatIsNotPiperOutput() {
        XCTAssertNil(WAVInfo.parse(Data()))
        XCTAssertNil(WAVInfo.parse(Data("RIFF....WAVE".utf8)))
        XCTAssertNil(WAVInfo.parse(Data("ID3 not a wav file at all".utf8)))
        XCTAssertNil(WAVInfo.parse(Self.wav(samples: [0], bits: 8)))
        XCTAssertNil(WAVInfo.parse(Self.wav(samples: [0], format: 3)))
    }

    func testTruncatedDataIsClamped() throws {
        let full = Self.wav(samples: [Int16](repeating: 100, count: 1_000))
        let info = try XCTUnwrap(WAVInfo.parse(full.prefix(44 + 500)))
        XCTAssertEqual(info.dataLength, 500)
    }

    func testSilenceIsNoSpeech() {
        // Empty text: Piper writes 0.2 s of zeros.
        XCTAssertFalse(WAVInfo.hasSpeech(Self.wav(samples: [Int16](repeating: 0, count: 4_410))))
        let tone = (0..<22_050).map { Int16(8_000 * sin(2 * Double.pi * 220 * Double($0) / 22_050)) }
        XCTAssertTrue(WAVInfo.hasSpeech(Self.wav(samples: tone)))
        XCTAssertFalse(WAVInfo.hasSpeech(Data("garbage".utf8)))
    }

    func testStereoIsAveraged() throws {
        let data = Self.wav(samples: [16_384, -16_384, 16_384, 16_384], channels: 2)
        let info = try XCTUnwrap(WAVInfo.parse(data))
        XCTAssertEqual(WAVInfo.monoSamples(data, info: info), [0, 0.5])
    }
}
```

Datei `Packages/AppCore/Tests/AppCoreTests/FileChecksumTests.swift` neu anlegen:

```swift
import XCTest
@testable import AppCore

final class FileChecksumTests: XCTestCase {
    private func temp(_ contents: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("checksum-\(UUID().uuidString)")
        try contents.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testKnownHashes() throws {
        XCTAssertEqual(try FileChecksum.sha256(of: temp(Data("abc".utf8))),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(try FileChecksum.sha256(of: temp(Data())),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func testMoreThanOneChunk() throws {
        let big = Data(repeating: 0x61, count: (1 << 20) * 2 + 7)
        let url = try temp(big)
        XCTAssertEqual(try FileChecksum.sha256(of: url), try FileChecksum.sha256(of: temp(big)))
        XCTAssertNotEqual(try FileChecksum.sha256(of: url), try FileChecksum.sha256(of: temp(big.prefix(big.count - 1))))
    }

    func testMatchesNeedsSizeAndHash() throws {
        let url = try temp(Data("abc".utf8))
        let good = VoiceFile(path: "x/abc", size: 3, sha256: "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD")
        XCTAssertTrue(FileChecksum.matches(url, good))
        XCTAssertFalse(FileChecksum.matches(url, VoiceFile(path: "x/abc", size: 4, sha256: good.sha256)))
        XCTAssertFalse(FileChecksum.matches(url, VoiceFile(path: "x/abc", size: 3, sha256: String(repeating: "0", count: 64))))
        XCTAssertFalse(FileChecksum.matches(URL(fileURLWithPath: "/nonexistent"), good))
    }
}
```

Datei `Packages/AppCore/Tests/AppCoreTests/PiperIntegrationTests.swift` neu anlegen (läuft gegen `piper/build/dist` aus Task 1, sonst übersprungen):

```swift
import AVFoundation
import XCTest
@testable import AppCore

/// The real Piper from piper/build/dist (piper/scripts/build-piper.sh) speaks with Thorsten (medium).
/// Skipped when the build is missing – never part of the app start.
final class PiperIntegrationTests: XCTestCase {
    private var dist: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("piper/build/dist", isDirectory: true)
    }

    func testBundledPiperSpeaksGerman() async throws {
        let installation = PiperInstallation(contents: dist)
        guard FileManager.default.isExecutableFile(atPath: installation.executable.path) else {
            throw XCTSkip("piper/build/dist fehlt – zuerst piper/scripts/build-piper.sh")
        }
        let files = PiperVoiceFiles(voice: PiperVoiceCatalog.bundled, folder: installation.bundledVoices)
        XCTAssertTrue(FileChecksum.matches(files.model, PiperVoiceCatalog.bundled.model))
        XCTAssertTrue(FileChecksum.matches(files.config, PiperVoiceCatalog.bundled.config))
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("piper-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: output) }
        let input = try XCTUnwrap(PiperCommand.input(for: "Achtung: An der Haustür hat jemand geklingelt.\nOkay, Computer-Update!"))
        let start = Date()
        try await PiperRunner.run(
            executable: installation.executable,
            arguments: PiperCommand.arguments(installation: installation, files: files, speaker: nil, output: output),
            input: input
        )
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
        let data = try Data(contentsOf: output)
        let info = try XCTUnwrap(WAVInfo.parse(data))
        XCTAssertEqual(info.sampleRate, 22_050)
        XCTAssertEqual(info.channels, 1)
        XCTAssertGreaterThan(info.duration, 2)
        XCTAssertTrue(WAVInfo.hasSpeech(data))
        // AVFoundation reads it like every other announcement, and the loudness step applies.
        let buffer = try AnnouncementAudio.load(output)
        XCTAssertEqual(Double(buffer.frameLength) / buffer.format.sampleRate, info.duration, accuracy: 0.01)
        XCTAssertLessThan(try AnnouncementAudio.loudnessGain(of: buffer), 1.0)
    }

    func testEmptyTextGivesNoSpeech() async throws {
        let installation = PiperInstallation(contents: dist)
        guard FileManager.default.isExecutableFile(atPath: installation.executable.path) else {
            throw XCTSkip("piper/build/dist fehlt – zuerst piper/scripts/build-piper.sh")
        }
        let files = PiperVoiceFiles(voice: PiperVoiceCatalog.bundled, folder: installation.bundledVoices)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("piper-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: output) }
        try await PiperRunner.run(
            executable: installation.executable,
            arguments: PiperCommand.arguments(installation: installation, files: files, speaker: nil, output: output),
            input: "!!!\n"
        )
        XCTAssertFalse(WAVInfo.hasSpeech(try Data(contentsOf: output)))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `(cd Packages/AppCore && swift test --filter "PiperCommandTests|PiperRunnerTests|WAVFileTests|FileChecksumTests|PiperIntegrationTests" 2>&1 | grep -E "error:" | head -5)`
Expected: FAIL – `cannot find 'PiperInstallation' in scope`, `cannot find 'PiperRunner' in scope`, `cannot find 'WAVInfo' in scope`, `cannot find 'FileChecksum' in scope`.

- [ ] **Step 3: Aufrufparameter**

Datei `Packages/AppCore/Sources/AppCore/Sound/PiperCommand.swift` neu anlegen:

```swift
import Foundation

/// Where the bundled Piper lives inside the app (filled by piper/scripts/embed.sh).
public struct PiperInstallation: Equatable, Sendable {
    public let executable: URL
    public let espeakData: URL
    /// Folder with the bundled voice (de_DE-thorsten-medium.onnx + .onnx.json).
    public let bundledVoices: URL

    public init(executable: URL, espeakData: URL, bundledVoices: URL) {
        self.executable = executable
        self.espeakData = espeakData
        self.bundledVoices = bundledVoices
    }

    /// `<App>.app/Contents/Helpers/piper/piper` and `<App>.app/Contents/Resources/piper/…`.
    public init(contents: URL) {
        self.init(
            executable: contents.appendingPathComponent("Helpers/piper/piper"),
            espeakData: contents.appendingPathComponent("Resources/piper/espeak-ng-data", isDirectory: true),
            bundledVoices: contents.appendingPathComponent("Resources/piper/voices", isDirectory: true)
        )
    }
}

/// Model and config of one installed voice.
public struct PiperVoiceFiles: Equatable, Sendable {
    public let model: URL
    public let config: URL

    public init(model: URL, config: URL) {
        self.model = model
        self.config = config
    }

    /// `<folder>/<file name of model>` and `<folder>/<file name of config>`.
    public init(voice: PiperVoice, folder: URL) {
        self.init(model: folder.appendingPathComponent(voice.model.fileName),
                  config: folder.appendingPathComponent(voice.config.fileName))
    }
}

/// Command line and input of one Piper run (Process – never linked).
public enum PiperCommand {
    /// Longest text handed to Piper (characters); longer text is cut at a word boundary.
    public static let maxTextLength = 1_000

    public static func arguments(installation: PiperInstallation, files: PiperVoiceFiles, speaker: Int?, output: URL) -> [String] {
        var arguments = [
            "--quiet",
            "--model", files.model.path,
            "--config", files.config.path,
            "--espeak_data", installation.espeakData.path,
            "--output_file", output.path,
        ]
        if let speaker {
            arguments += ["--speaker", String(speaker)]
        }
        return arguments
    }

    /// One line for stdin: line breaks and tabs become spaces, runs of spaces collapse, at most
    /// `maxTextLength` characters; nil when nothing speakable is left.
    public static func input(for text: String) -> String? {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard !words.isEmpty else { return nil }
        var line = ""
        for word in words {
            let next = line.isEmpty ? String(word) : line + " " + word
            if next.count > maxTextLength {
                if line.isEmpty { line = String(next.prefix(maxTextLength)) }
                break
            }
            line = next
        }
        return line + "\n"
    }

    /// Speaker argument only for multi-speaker voices (single-speaker models ignore it anyway).
    public static func speakerArgument(voice: PiperVoice, speaker: Int) -> Int? {
        guard voice.isMultiSpeaker else { return nil }
        return (0..<voice.speakerCount).contains(speaker) ? speaker : voice.defaultSpeaker
    }
}
```

- [ ] **Step 4: Prozess mit Zeitlimit und Abbruch**

Datei `Packages/AppCore/Sources/AppCore/Sound/PiperRunner.swift` neu anlegen:

```swift
import Foundation

/// Why rendering with Piper failed – shown in Einstellungen › Ton.
public enum PiperError: Error, Equatable, LocalizedError {
    case missing
    case timeout(TimeInterval)
    case crashed(Int32)
    case failed(Int32, String)
    case noAudio
    case voiceNotInstalled(String)
    case download(String)
    case checksum(String)

    public var errorDescription: String? {
        switch self {
        case .missing:
            return "Die Sprachausgabe (Piper) fehlt im App-Paket. Installiere die App neu."
        case .timeout(let seconds):
            return "Piper hat nach \(Int(seconds)) Sekunden keinen Ton geliefert und wurde beendet."
        case .crashed(let signal):
            return "Piper ist abgestürzt (Signal \(signal))."
        case .failed(let status, let detail):
            let tail = detail.isEmpty ? "" : ": \(detail)"
            return "Piper ist mit Fehler \(status) beendet\(tail)."
        case .noAudio:
            return "Piper hat keinen Ton erzeugt. Steht im Text etwas Sprechbares?"
        case .voiceNotInstalled(let label):
            return "Die Stimme „\(label)“ ist nicht geladen."
        case .download(let detail):
            return "Die Stimme konnte nicht geladen werden (\(detail))."
        case .checksum(let label):
            return "Die geladene Stimme „\(label)“ ist beschädigt (Prüfsumme stimmt nicht). Versuch es noch einmal."
        }
    }
}

/// Runs a program with text on stdin and a deadline – off the main thread, cancellable.
/// Used for Piper; generic so the tests can run `/bin/sh` instead.
public enum PiperRunner {
    public static let defaultTimeout: TimeInterval = 20

    /// Runs `executable` and waits. Throws `.missing`, `.timeout`, `.crashed`, `.failed`
    /// (with the last line of stderr) or `CancellationError`.
    public static func run(executable: URL, arguments: [String], input: String,
                           timeout: TimeInterval = defaultTimeout) async throws {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw PiperError.missing }
        let job = Job(executable: executable, arguments: arguments, input: input, timeout: timeout)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                job.start { continuation.resume(with: $0) }
            }
        } onCancel: {
            job.cancel()
        }
    }

    /// Owns the Process; completes exactly once (exit, timeout or cancellation).
    private final class Job: @unchecked Sendable {
        private let process = Process()
        private let timeout: TimeInterval
        private let input: String
        private let lock = NSLock()
        private var completion: ((Result<Void, Error>) -> Void)?
        private var reason: Error?
        private let stderr = Pipe()
        private var stderrData = Data()

        init(executable: URL, arguments: [String], input: String, timeout: TimeInterval) {
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = FileManager.default.temporaryDirectory
            // Nothing from the app's environment (DYLD_*, proxies) reaches the helper.
            process.environment = ["PATH": "/usr/bin:/bin", "LANG": "de_DE.UTF-8"]
            self.timeout = timeout
            self.input = input
        }

        func start(_ completion: @escaping (Result<Void, Error>) -> Void) {
            let stdin = Pipe()
            process.standardInput = stdin
            process.standardOutput = FileHandle.nullDevice
            process.standardError = stderr
            stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                guard let self, !chunk.isEmpty else { return }
                self.lock.withLock {
                    // Keep the tail only (Piper logs one line per sentence).
                    self.stderrData.append(chunk)
                    if self.stderrData.count > 8_192 { self.stderrData = self.stderrData.suffix(4_096) }
                }
            }
            process.terminationHandler = { [weak self] process in self?.finished(process) }
            let cancelledEarly: Bool = lock.withLock {
                self.completion = completion
                return reason != nil
            }
            if cancelledEarly { finishNow(); return }
            do {
                try process.run()
            } catch {
                lock.withLock { self.reason = PiperError.missing }
                finishNow()
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self else { return }
                self.stop(because: PiperError.timeout(self.timeout))
            }
            let data = Data(input.utf8)
            let writer = stdin.fileHandleForWriting
            // Piper may exit before reading everything: a write into the closed pipe must fail
            // with EPIPE instead of killing the app with SIGPIPE.
            _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
            DispatchQueue.global().async {
                try? writer.write(contentsOf: data)
                try? writer.close()
            }
        }

        func cancel() {
            stop(because: CancellationError())
        }

        /// Timeout or cancellation: remember why, then end the process (its termination handler
        /// completes). Before `start` the reason alone is enough – `start` sees it and completes.
        private func stop(because error: Error) {
            let running: Bool = lock.withLock {
                if reason == nil { reason = error }
                return process.isRunning
            }
            guard running else { return }
            process.terminate()
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [weak self] in
                if self?.process.isRunning == true { kill(pid, SIGKILL) }
            }
        }

        private func finished(_ process: Process) {
            stderr.fileHandleForReading.readabilityHandler = nil
            let rest = stderr.fileHandleForReading.readDataToEndOfFile()
            lock.withLock {
                stderrData.append(rest)
                guard reason == nil else { return }
                switch process.terminationReason {
                case .uncaughtSignal:
                    reason = PiperError.crashed(process.terminationStatus)
                case .exit where process.terminationStatus != 0:
                    reason = PiperError.failed(process.terminationStatus, Self.lastLine(stderrData))
                default:
                    break
                }
            }
            finishNow()
        }

        private func finishNow() {
            let (callback, error): (((Result<Void, Error>) -> Void)?, Error?) = lock.withLock {
                let callback = completion
                completion = nil
                return (callback, reason)
            }
            guard let callback else { return }
            if let error { callback(.failure(error)) } else { callback(.success(())) }
        }

        private static func lastLine(_ data: Data) -> String {
            let text = String(decoding: data, as: UTF8.self)
            let line = text.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
            return String(line.trimmingCharacters(in: .whitespaces).prefix(200))
        }
    }
}
```

- [ ] **Step 5: WAV-Kopf und Stille**

Datei `Packages/AppCore/Sources/AppCore/Sound/WAVFile.swift` neu anlegen:

```swift
import Foundation

/// The parts of a RIFF/WAVE header Piper's output is checked against (16-bit PCM).
public struct WAVInfo: Equatable, Sendable {
    public let channels: Int
    public let sampleRate: Int
    public let bitsPerSample: Int
    /// Byte offset of the first sample and number of sample bytes (clamped to the file).
    public let dataOffset: Int
    public let dataLength: Int

    public var duration: TimeInterval {
        let frameBytes = channels * bitsPerSample / 8
        guard frameBytes > 0, sampleRate > 0 else { return 0 }
        return Double(dataLength / frameBytes) / Double(sampleRate)
    }

    /// Walks the chunks (fmt may be followed by LIST etc.); nil unless PCM (format 1) with a data chunk.
    public static func parse(_ data: Data) -> WAVInfo? {
        let bytes = [UInt8](data)
        guard bytes.count >= 12, bytes[0..<4] == [0x52, 0x49, 0x46, 0x46], bytes[8..<12] == [0x57, 0x41, 0x56, 0x45] else {
            return nil
        }
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        var offset = 12
        var format: (channels: Int, rate: Int, bits: Int)?
        while offset + 8 <= bytes.count {
            let id = bytes[offset..<offset + 4]
            let size = u32(offset + 4)
            let body = offset + 8
            if id == [0x66, 0x6D, 0x74, 0x20] { // "fmt "
                guard size >= 16, body + 16 <= bytes.count, u16(body) == 1 else { return nil }
                format = (u16(body + 2), u32(body + 4), u16(body + 14))
            } else if id == [0x64, 0x61, 0x74, 0x61] { // "data"
                guard let format, format.channels > 0, format.rate > 0, format.bits == 16 else { return nil }
                return WAVInfo(channels: format.channels, sampleRate: format.rate, bitsPerSample: format.bits,
                               dataOffset: body, dataLength: min(size, bytes.count - body))
            }
            offset = body + size + (size & 1)
        }
        return nil
    }

    /// 16-bit samples as −1…1, all channels averaged (for the silence check before a file is kept).
    public static func monoSamples(_ data: Data, info: WAVInfo) -> [Float] {
        let frameBytes = info.channels * 2
        let frames = info.dataLength / frameBytes
        guard frames > 0 else { return [] }
        return data.withUnsafeBytes { raw -> [Float] in
            var out = [Float](repeating: 0, count: frames)
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<info.channels {
                    let at = info.dataOffset + frame * frameBytes + channel * 2
                    let value = Int16(bitPattern: UInt16(raw[at]) | UInt16(raw[at + 1]) << 8)
                    sum += Float(value) / 32_768
                }
                out[frame] = sum / Float(info.channels)
            }
            return out
        }
    }

    /// Piper's output is usable: PCM 16-bit and at least one block above the loudness gate
    /// (empty or unspeakable text gives 0.2 s of silence).
    public static func hasSpeech(_ data: Data) -> Bool {
        guard let info = parse(data) else { return false }
        return Loudness.gatedRMSdB(monoSamples(data, info: info), sampleRate: Double(info.sampleRate)) != nil
    }
}
```

- [ ] **Step 6: Prüfsumme**

Datei `Packages/AppCore/Sources/AppCore/Sound/FileChecksum.swift` neu anlegen:

```swift
import CryptoKit
import Foundation

/// SHA-256 of downloaded voices, read in 1 MiB pieces (models are up to 114 MB).
public enum FileChecksum {
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Size and hash both match (size first: cheap, catches truncated downloads).
    public static func matches(_ url: URL, _ file: VoiceFile) -> Bool {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber,
              size.int64Value == file.size else { return false }
        return (try? sha256(of: url)) == file.sha256.lowercased()
    }
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `(cd Packages/AppCore && swift test 2>&1 | grep -E "error:|skipped|Executed [0-9]+ tests" | tail -4)`
Expected: `Executed 149 tests, with 0 failures` ohne Task 2 (125 + 24; mit Task 2: 166). Ohne `piper/build/dist` erscheinen die zwei `PiperIntegrationTests` als „skipped“ – mit Task 1 laufen sie (≈ 0,5 s) und bestehen.

- [ ] **Step 8: Commit**

```bash
git add Packages/AppCore/Sources/AppCore/Sound/PiperCommand.swift Packages/AppCore/Sources/AppCore/Sound/PiperRunner.swift \
  Packages/AppCore/Sources/AppCore/Sound/WAVFile.swift Packages/AppCore/Sources/AppCore/Sound/FileChecksum.swift \
  Packages/AppCore/Tests/AppCoreTests/PiperCommandTests.swift Packages/AppCore/Tests/AppCoreTests/PiperRunnerTests.swift \
  Packages/AppCore/Tests/AppCoreTests/WAVFileTests.swift Packages/AppCore/Tests/AppCoreTests/FileChecksumTests.swift \
  Packages/AppCore/Tests/AppCoreTests/PiperIntegrationTests.swift
git diff --cached --name-only | grep AppConfig   # → leer
git commit -m "feat(sound): run Piper as a process with timeout, check its WAV and voice checksums

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 4: Xcode-Einbindung – Phase „Build and embed Piper“, Signatur, Release-Prüfungen (braucht Task 1)

**Files:**
- Create: `piper/scripts/embed.sh`, `piper/scripts/check-app.sh`
- Modify: `UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj` (neue Shell-Phase `E66000000000000000000001` nach „Resources“)
- Modify: `UniFiCameraPopup/scripts/build-release.sh:65-70`

**Interfaces:**
- Consumes: `piper/scripts/build-piper.sh`, `piper/scripts/smoke.sh`, `piper/build/dist` (Task 1); Xcode-Umgebung `TARGET_BUILD_DIR`, `CONTENTS_FOLDER_PATH`, `EXPANDED_CODE_SIGN_IDENTITY`, `CONFIGURATION`.
- Produces: jede gebaute App enthält `Contents/Helpers/piper/piper` (+ `lib/`) und `Contents/Resources/piper/…` – genau die Pfade von `PiperInstallation(contents:)` (Task 3). `piper/scripts/check-app.sh <App.app>` (Task 5 ergänzt die Lizenz-Marken).

- [ ] **Step 1: Einbettungs-Skript**

Datei `piper/scripts/embed.sh` neu anlegen:

```bash
#!/bin/bash
# Xcode build phase "Build and embed Piper" (after Resources): builds piper/build/dist if needed
# and copies it into the app – the program to Contents/Helpers/piper, data and the bundled voice
# to Contents/Resources/piper. Every Mach-O is signed here with the build's identity (Xcode's own
# CodeSign step only seals them); resign-app.sh re-signs them with --deep for releases.
# Debug builds then let the embedded Piper speak one sentence (scripts/smoke.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"${ROOT}/scripts/build-piper.sh"
DIST="${ROOT}/build/dist"
CONTENTS="${TARGET_BUILD_DIR:?}/${CONTENTS_FOLDER_PATH:?}"

mkdir -p "${CONTENTS}/Helpers" "${CONTENTS}/Resources"
rsync -a --delete "${DIST}/Helpers/piper/" "${CONTENTS}/Helpers/piper/"
rsync -a --delete "${DIST}/Resources/piper/" "${CONTENTS}/Resources/piper/"

IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [[ -z "${IDENTITY}" ]]; then IDENTITY="-"; fi
codesign --force --sign "${IDENTITY}" "${CONTENTS}/Helpers/piper/lib/"*.dylib
codesign --force --sign "${IDENTITY}" "${CONTENTS}/Helpers/piper/piper"

if [[ "${CONFIGURATION:-}" == "Debug" ]]; then
  "${ROOT}/scripts/smoke.sh" "${CONTENTS}"
fi
```

- [ ] **Step 2: Prüf-Skript für eine fertige App**

Datei `piper/scripts/check-app.sh` neu anlegen:

```bash
#!/bin/bash
# Checks the Piper inside a built app (called by build-release.sh, runnable on any build):
# program and libraries universal (arm64 + x86_64), data and bundled voice present, signature valid.
#   piper/scripts/check-app.sh "<path>/UniFi Camera Popup.app"
set -euo pipefail

APP_PATH="${1:?usage: check-app.sh <App.app>}"
PIPER_DIR="${APP_PATH}/Contents/Helpers/piper"
RES="${APP_PATH}/Contents/Resources/piper"

for file in "${PIPER_DIR}/piper" "${PIPER_DIR}/lib/libespeak-ng.1.dylib" \
            "${PIPER_DIR}/lib/libpiper_phonemize.1.dylib" "${PIPER_DIR}/lib/libonnxruntime.1.14.1.dylib"; do
  if [[ ! -f "${file}" ]]; then
    echo "ERROR: ${file} missing from the app bundle." >&2
    exit 1
  fi
  archs="$(lipo -archs "${file}")"
  for arch in arm64 x86_64; do
    if [[ " ${archs} " != *" ${arch} "* ]]; then
      echo "ERROR: ${file} lacks ${arch} (has: ${archs})." >&2
      exit 1
    fi
  done
done
for file in voices/de_DE-thorsten-medium.onnx voices/de_DE-thorsten-medium.onnx.json espeak-ng-data/phondata \
            espeak-ng-data/de_dict espeak-ng-data/en_dict ThirdPartyNotices-onnxruntime.txt \
            build-scripts/fetch.sh build-scripts/build-piper.sh; do
  if [[ ! -s "${RES}/${file}" ]]; then
    echo "ERROR: Contents/Resources/piper/${file} missing from the app bundle." >&2
    exit 1
  fi
done
codesign --verify --deep --strict "${APP_PATH}"
echo "check-app: Piper ok in ${APP_PATH}"
```

```bash
chmod +x piper/scripts/embed.sh piper/scripts/check-app.sh
```

- [ ] **Step 3: Build-Phase ins Projekt**

`pbxproj-add-files.py` legt nur Dateien an; die Phase fügt dieses einmalige Snippet ein (es bricht ab, wenn die Phase schon da ist oder ein Anker fehlt):

```bash
python3 -I - UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj <<'EOF'
import sys
path = sys.argv[1]
s = open(path, encoding="utf-8").read()
phase_id = "E66000000000000000000001"
if phase_id in s:
    sys.exit("phase already present")
anchor = "\t\t\t\tA60000000000000000000003 /* Resources */,\n\t\t\t);"
assert s.count(anchor) == 1, "Resources anchor"
s = s.replace(anchor, "\t\t\t\tA60000000000000000000003 /* Resources */,\n"
              f"\t\t\t\t{phase_id} /* Build and embed Piper */,\n\t\t\t);")
end = "/* End PBXShellScriptBuildPhase section */"
assert s.count(end) == 1, "shell section"
block = (f"\t\t{phase_id} /* Build and embed Piper */ = {{\n"
         "\t\t\tisa = PBXShellScriptBuildPhase;\n"
         "\t\t\talwaysOutOfDate = 1;\n"
         "\t\t\tbuildActionMask = 2147483647;\n"
         "\t\t\tfiles = (\n\t\t\t);\n"
         "\t\t\tinputPaths = (\n\t\t\t);\n"
         "\t\t\tname = \"Build and embed Piper\";\n"
         "\t\t\toutputPaths = (\n\t\t\t);\n"
         "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
         "\t\t\tshellPath = /bin/bash;\n"
         "\t\t\tshellScript = \"\\\"$PROJECT_DIR/../piper/scripts/embed.sh\\\"\\n\";\n"
         "\t\t\tshowEnvVarsInLog = 0;\n"
         "\t\t};\n")
s = s.replace(end, block + end)
open(path, "w", encoding="utf-8").write(s)
print("added", phase_id)
EOF
plutil -lint UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj
grep -n "E66000000000000000000001" UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj
```

Expected: `added E66000000000000000000001`, `…project.pbxproj: OK`, zwei Treffer (Liste `buildPhases` direkt nach `A60000000000000000000003 /* Resources */` und der Block im Abschnitt `PBXShellScriptBuildPhase`). Die Phase läuft nach „Resources“ und vor Xcodes CodeSign-Schritt; `ENABLE_USER_SCRIPT_SANDBOXING = NO` ist im Projekt schon gesetzt (Phase 4).

- [ ] **Step 4: Release-Prüfungen in `build-release.sh`**

In `UniFiCameraPopup/scripts/build-release.sh` ersetzen:

```bash
if [[ ! -s "${APP_PATH}/Contents/Resources/ThirdPartyNotices.txt" ]]; then
  echo "ERROR: ThirdPartyNotices.txt missing from the app bundle." >&2
  exit 1
fi

"${SCRIPT_DIR}/resign-app.sh" "$APP_PATH"
```

durch:

```bash
if [[ ! -s "${APP_PATH}/Contents/Resources/ThirdPartyNotices.txt" ]]; then
  echo "ERROR: ThirdPartyNotices.txt missing from the app bundle." >&2
  exit 1
fi
# Piper (Phase 6, build phase "Build and embed Piper"): universal program and libraries,
# espeak-ng data, the bundled voice, license marks, valid signature.
"${SCRIPT_DIR}/../../piper/scripts/check-app.sh" "$APP_PATH"

"${SCRIPT_DIR}/resign-app.sh" "$APP_PATH"
# The re-signed bundle (nested Piper included) must still verify – and Piper must still speak.
codesign --verify --deep --strict "$APP_PATH"
"${SCRIPT_DIR}/../../piper/scripts/smoke.sh" "${APP_PATH}/Contents"
```

`build-release.sh` wird **nicht** ausgeführt. Syntax prüfen: `bash -n UniFiCameraPopup/scripts/build-release.sh` → keine Ausgabe.

- [ ] **Step 5: Bauen und prüfen**

```bash
DD="${TMPDIR:-/tmp}/ucp-phase6-dd"
xcodebuild -project UniFiCameraPopup/UniFiCameraPopup.xcodeproj -scheme UniFiCameraPopup \
  -configuration Debug -derivedDataPath "$DD" build 2>&1 | grep -E "error:|build-piper|piper-smoke|\*\* BUILD" | tail -20
```

Expected: `build-piper: …/piper/build/dist ist aktuell` (bzw. der Build aus Task 1), `piper-smoke: ok (2.6 s Ton in 1 s)`, `** BUILD SUCCEEDED **`.

```bash
APP="$DD/Build/Products/Debug/UniFi Camera Popup.app"
piper/scripts/check-app.sh "$APP"   # → check-app: Piper ok in …
codesign -dv "$APP/Contents/Helpers/piper/piper" 2>&1 | grep -E "Authority|Signature"   # → Authority=UniFi Camera Popup (Self-Signed) bzw. Signature=adhoc
du -sh "$APP/Contents/Helpers/piper" "$APP/Contents/Resources/piper"   # → ≈ 46M, ≈ 61M
# Zweiter Build ändert nichts und dauert nur Sekunden:
xcodebuild -project UniFiCameraPopup/UniFiCameraPopup.xcodeproj -scheme UniFiCameraPopup \
  -configuration Debug -derivedDataPath "$DD" build 2>&1 | grep -E "build-piper|\*\* BUILD"
```

- [ ] **Step 6: Commit**

```bash
git add piper/scripts/embed.sh piper/scripts/check-app.sh UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj \
  UniFiCameraPopup/scripts/build-release.sh
git diff --cached --name-only | grep AppConfig   # → leer
git commit -m "build(piper): embed and sign Piper in the app, release checks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Lizenztexte – Piper, espeak-ng, onnxruntime und jede Stimme (Gruppe B, braucht Task 1 + 4; parallel zu Task 6)

**Files:**
- Create: `piper/scripts/collect-notices.sh`, `piper/NOTICES.txt` (generiert)
- Modify: `wgtunnel/scripts/collect-notices.sh`, `UniFiCameraPopup/ThirdPartyNotices.txt` (generiert), `UniFiCameraPopup/Views/HelpView.swift` (Abschnitt „Über“), `piper/scripts/check-app.sh`

**Interfaces:**
- Consumes: `piper/scripts/fetch.sh` (Task 1), `check-app.sh` (Task 4), die Lizenzangaben der Stimmen aus Task 2 (Tabelle oben – der Text in `collect-notices.sh` muss dazu passen).
- Produces: `ThirdPartyNotices.txt` mit Abschnitt „Camera Popup – Sprachausgabe (Piper)“ (Marken, die `check-app.sh` prüft: „Sprachausgabe (Piper)“, „--- espeak-ng“, „GPL-3.0-or-later“, „--- onnxruntime“, „Thorsten-Voice“, „M-AILABS“, „CC BY 4.0“).

- [ ] **Step 1: Hinweise für Piper erzeugen**

Datei `piper/scripts/collect-notices.sh` neu anlegen:

```bash
#!/bin/bash
# Writes piper/NOTICES.txt: what the bundled Piper consists of, the GPL source offer and the
# license texts of piper, piper-phonemize (+ uni-algo), espeak-ng, onnxruntime, fmt, spdlog and
# of every offered voice. wgtunnel/scripts/collect-notices.sh appends it to ThirdPartyNotices.txt.
# Re-run after every change to scripts/fetch.sh or the voice catalog and commit the result.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$("${ROOT}/scripts/fetch.sh")"
OUT="${ROOT}/NOTICES.txt"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/piper-notices.XXXXXX")"
trap 'rm -rf "${TMP}" "${OUT}.tmp"' EXIT

for archive in piper-2023.11.14-2.tar.gz piper-phonemize-bfc2e75.tar.gz espeak-ng-0f65aa3.tar.gz \
               fmt-10.0.0.tar.gz spdlog-1.12.0.tar.gz onnxruntime-osx-universal2-1.14.1.tgz; do
  tar -xzf "${CACHE}/${archive}" -C "${TMP}"
done
PIPER="${TMP}/piper-2023.11.14-2"
PHONEMIZE="${TMP}/piper-phonemize-bfc2e7549957829b0227c66a305d11cc88167bda"
ESPEAK="${TMP}/espeak-ng-0f65aa301e0d6bae5e172cc74197d32a6182200f"
ORT="${TMP}/onnxruntime-osx-universal2-1.14.1"

section() {
  echo
  echo "--- $1 ---"
  echo
  shift
  for file in "$@"; do cat "${file}"; echo; done
}

{
  echo
  echo "Camera Popup – Sprachausgabe (Piper)"
  echo "===================================="
  echo
  echo "Die Ansagen aus Text erzeugt Piper, ein eigenständiges Programm im App-Paket"
  echo "(Contents/Helpers/piper). Die App startet es als eigenen Prozess und linkt es nicht;"
  echo "die App selbst steht nicht unter der GPL. Piper ist mit espeak-ng (GPL-3.0-or-later)"
  echo "gelinkt; das Programm Piper samt Bibliotheken wird daher unter GPL-3.0-or-later"
  echo "weitergegeben (der Piper-Quellcode selbst ist MIT-lizenziert)."
  echo
  echo "Quellcode (genau die verwendeten Stände):"
  echo "  Piper 2023.11.14-2           https://github.com/rhasspy/piper/archive/refs/tags/2023.11.14-2.tar.gz"
  echo "  piper-phonemize bfc2e75      https://github.com/rhasspy/piper-phonemize/archive/bfc2e7549957829b0227c66a305d11cc88167bda.tar.gz"
  echo "  espeak-ng (rhasspy) 0f65aa3  https://github.com/rhasspy/espeak-ng/archive/0f65aa301e0d6bae5e172cc74197d32a6182200f.tar.gz"
  echo "  onnxruntime 1.14.1           https://github.com/microsoft/onnxruntime/releases/download/v1.14.1/onnxruntime-osx-universal2-1.14.1.tgz"
  echo "  fmt 10.0.0                   https://github.com/fmtlib/fmt/archive/refs/tags/10.0.0.tar.gz"
  echo "  spdlog 1.12.0                https://github.com/gabime/spdlog/archive/refs/tags/v1.12.0.tar.gz"
  echo "Prüfsummen und Build-Befehle: Contents/Resources/piper/build-scripts/fetch.sh und build-piper.sh."
  echo "Auf Anfrage schicken wir den vollständigen Quellcode samt Build-Skripten (mindestens drei Jahre"
  echo "ab Weitergabe dieser Version)."
  echo
  echo "Stimmen (rhasspy/piper-voices, Stand c10ece1aade47bb51c153c893d14e5bf8e5b7117, Modelle MIT):"
  echo "  Thorsten (niedrig, mittel, hoch), Thorsten emotional – Datensatz Thorsten-Voice, CC0 1.0"
  echo "    https://github.com/thorstenMueller/Thorsten-Voice  (Thorsten mittel ist mitgeliefert)"
  echo "  Kerstin – dataset-voice-kerstin, CC0 1.0  https://github.com/rhasspy/dataset-voice-kerstin"
  echo "  Eva K., Karlsson, Ramona – M-AILABS Speech Dataset:"
  echo "    Copyright (c) 2017-2019 by the original creators @ M-AILABS. Redistribution and use in any"
  echo "    form, including any commercial use, with or without modification are permitted provided"
  echo "    that the following conditions are met: Redistributions of source data must retain the"
  echo "    above copyright notice, this list of conditions and the following disclaimer. Neither the"
  echo "    name of the copyright holder nor the names of its contributors may be used to endorse or"
  echo "    promote products derived from this downloaded data, source-code or binary-code without"
  echo "    specific prior written permission. THIS DATA IS PROVIDED BY THE COPYRIGHT HOLDERS AND"
  echo "    CONTRIBUTORS \"AS IS\" AND ANY EXPRESS OR IMPLIED WARRANTIES ARE DISCLAIMED."
  echo "    https://www.caito.de/2019/01/03/the-m-ailabs-speech-dataset/"
  echo "  MLS (236 Sprecher) – Multilingual LibriSpeech (Pratap et al. 2020), CC BY 4.0"
  echo "    http://openslr.org/94/  https://creativecommons.org/licenses/by/4.0/"
  echo "  Nicht angeboten: Pavoque (CC BY-NC-SA 4.0 – keine kommerzielle Nutzung)."
  section "rhasspy/piper 2023.11.14-2 (MIT)" "${PIPER}/LICENSE.md"
  section "rhasspy/piper-phonemize bfc2e75 (MIT)" "${PHONEMIZE}/LICENSE.md"
  section "uni-algo (in piper-phonemize)" "${PHONEMIZE}/licenses/uni-algo/LICENSE.md"
  section "espeak-ng 1.52 (rhasspy-Fork 0f65aa3, GPL-3.0-or-later)" "${ESPEAK}/COPYING"
  section "espeak-ng: Unicode Character Database (ucd-tools)" "${ESPEAK}/COPYING.UCD"
  section "onnxruntime 1.14.1 (MIT; Hinweise Dritter: Contents/Resources/piper/ThirdPartyNotices-onnxruntime.txt)" "${ORT}/LICENSE"
  section "fmt 10.0.0 (MIT)" "${TMP}/fmt-10.0.0/LICENSE.rst"
  section "spdlog 1.12.0 (MIT)" "${TMP}/spdlog-1.12.0/LICENSE"
} > "${OUT}.tmp"
mv "${OUT}.tmp" "${OUT}"
echo "collect-notices: ${OUT}"
```

```bash
chmod +x piper/scripts/collect-notices.sh
piper/scripts/collect-notices.sh          # → collect-notices: …/piper/NOTICES.txt
grep -n "^--- " piper/NOTICES.txt
```

Expected: Abschnitte `rhasspy/piper 2023.11.14-2 (MIT)`, `rhasspy/piper-phonemize bfc2e75 (MIT)`, `uni-algo (in piper-phonemize)`, `espeak-ng 1.52 (rhasspy-Fork 0f65aa3, GPL-3.0-or-later)`, `espeak-ng: Unicode Character Database (ucd-tools)`, `onnxruntime 1.14.1 (…)`, `fmt 10.0.0 (MIT)` (darin fmt's eigene Zeile „--- Optional exception to the license ---“), `spdlog 1.12.0 (MIT)`; Datei ≈ 49 KB.

- [ ] **Step 2: An `ThirdPartyNotices.txt` anhängen**

In `wgtunnel/scripts/collect-notices.sh` ersetzen:

```bash
# Writes UniFiCameraPopup/ThirdPartyNotices.txt: license texts of the Go runtime and
# of every module linked into libwgtunnel.a (shown in Hilfe › „Über“).
```

durch:

```bash
# Writes UniFiCameraPopup/ThirdPartyNotices.txt: license texts of the Go runtime and
# of every module linked into libwgtunnel.a, followed by piper/NOTICES.txt (shown in Hilfe › „Über“).
```

In `wgtunnel/scripts/collect-notices.sh` ersetzen:

```bash
    done
} > "${OUT}.tmp"
```

durch:

```bash
    done
  # Phase 6: the bundled Piper (piper/scripts/collect-notices.sh writes this part).
  cat "${ROOT}/../piper/NOTICES.txt"
} > "${OUT}.tmp"
```

```bash
cp UniFiCameraPopup/ThirdPartyNotices.txt "${TMPDIR:-/tmp}/notices-before.txt"
wgtunnel/scripts/collect-notices.sh       # → collect-notices: …/ThirdPartyNotices.txt
cmp <(head -c "$(wc -c < "${TMPDIR:-/tmp}/notices-before.txt")" UniFiCameraPopup/ThirdPartyNotices.txt) "${TMPDIR:-/tmp}/notices-before.txt" && echo GO-TEIL-GLEICH
grep -c "Sprachausgabe (Piper)" UniFiCameraPopup/ThirdPartyNotices.txt   # → 1
```

Expected: `GO-TEIL-GLEICH` (der WireGuard-Teil bleibt byte-gleich, Datei ≈ 82 KB).

- [ ] **Step 3: „Über“ ergänzen**

In `UniFiCameraPopup/Views/HelpView.swift` ersetzen:

```swift
            Text("Die mitgelieferten Ansagen „Bin gleich da“ und „Paket bitte abstellen“ wurden mit Piper und der "
                 + "Stimme „Thorsten“ erzeugt (Datensatz CC0, gemeinfrei).")
                .fixedSize(horizontal: false, vertical: true)
```

durch:

```swift
            Text("Die mitgelieferten Ansagen „Bin gleich da“ und „Paket bitte abstellen“ wurden mit Piper und der "
                 + "Stimme „Thorsten“ erzeugt (Datensatz CC0, gemeinfrei).")
                .fixedSize(horizontal: false, vertical: true)
            Text("Ansagen aus Text spricht Piper 2023.11.14-2 (MIT-Lizenz, © Michael Hansen) mit espeak-ng "
                 + "(GPL-3.0-or-later), piper-phonemize (MIT), onnxruntime 1.14.1 (MIT, © Microsoft), fmt und spdlog (MIT). "
                 + "Piper liegt als eigenständiges Programm im App-Paket und läuft als eigener Prozess – die App selbst "
                 + "steht nicht unter der GPL. Quellcode-Adressen, die Lizenzen jeder Stimme und alle Lizenztexte stehen unten.")
                .fixedSize(horizontal: false, vertical: true)
            Button("Hinweise zu onnxruntime öffnen …") {
                if let url = Bundle.main.url(forResource: "ThirdPartyNotices-onnxruntime", withExtension: "txt", subdirectory: "piper") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
```

In `UniFiCameraPopup/Views/HelpView.swift` ersetzen:

```swift
    /// Full license texts, generated by `wgtunnel/scripts/collect-notices.sh`.
```

durch:

```swift
    /// Full license texts, generated by `wgtunnel/scripts/collect-notices.sh` (incl. piper/NOTICES.txt).
```

- [ ] **Step 4: Lizenz-Marken in `check-app.sh`**

In `piper/scripts/check-app.sh` ersetzen:

```bash
codesign --verify --deep --strict "${APP_PATH}"
echo "check-app: Piper ok in ${APP_PATH}"
```

durch:

```bash
NOTICES="${APP_PATH}/Contents/Resources/ThirdPartyNotices.txt"
for marker in "Sprachausgabe (Piper)" "--- espeak-ng" "GPL-3.0-or-later" "--- onnxruntime" "Thorsten-Voice" "M-AILABS" "CC BY 4.0"; do
  if ! grep -qF -- "${marker}" "${NOTICES}"; then
    echo "ERROR: ThirdPartyNotices.txt lacks \"${marker}\" – run piper/scripts/collect-notices.sh, then wgtunnel/scripts/collect-notices.sh." >&2
    exit 1
  fi
done
codesign --verify --deep --strict "${APP_PATH}"
echo "check-app: Piper ok in ${APP_PATH}"
```

- [ ] **Step 5: Bauen und prüfen**

```bash
DD="${TMPDIR:-/tmp}/ucp-phase6-dd"
xcodebuild -project UniFiCameraPopup/UniFiCameraPopup.xcodeproj -scheme UniFiCameraPopup \
  -configuration Debug -derivedDataPath "$DD" build 2>&1 | grep -E "error:|piper-smoke|\*\* BUILD" | tail -5
piper/scripts/check-app.sh "$DD/Build/Products/Debug/UniFi Camera Popup.app"
```

Expected: `** BUILD SUCCEEDED **`, `check-app: Piper ok in …`. Gegenprobe: in einer Kopie der App eine Marke entfernen (`sed -i '' 's/M-AILABS/X/g' <Kopie>/Contents/Resources/ThirdPartyNotices.txt`) → `check-app.sh <Kopie>` endet mit `ERROR: ThirdPartyNotices.txt lacks "M-AILABS" …`; Kopie löschen.

- [ ] **Step 6: Commit**

```bash
git add piper/scripts/collect-notices.sh piper/NOTICES.txt wgtunnel/scripts/collect-notices.sh \
  UniFiCameraPopup/ThirdPartyNotices.txt UniFiCameraPopup/Views/HelpView.swift piper/scripts/check-app.sh
git diff --cached --name-only | grep AppConfig   # → leer
git commit -m "docs(licenses): Piper, espeak-ng, onnxruntime and voice licenses in the notices and About

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 6: Reiter „Ton“ spricht mit Piper – Stimmen laden, prüfen, entfernen; Anna entfällt (Gruppe B, braucht Task 2 + 3 + 4; parallel zu Task 5)

**Files:**
- Create: `UniFiCameraPopup/Services/PiperVoiceStore.swift`
- Modify (ganz ersetzen): `UniFiCameraPopup/Services/SoundStore.swift`, `UniFiCameraPopup/Views/Settings/SoundTab.swift`, `Packages/AppCore/Sources/AppCore/Sound/AnnouncementAudio.swift`
- Modify: `Packages/AppCore/Sources/AppCore/Sound/SoundSettings.swift:28-31`, `Packages/AppCore/Sources/AppCore/Sound/Announcement.swift:15`, `Packages/AppCore/Tests/AppCoreTests/SoundSettingsTests.swift:90-148`, `UniFiCameraPopup/Debug/SnapshotRenderer.swift:33`, `UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj` (Skript)
- Delete: `Packages/AppCore/Sources/AppCore/Sound/VoiceChoice.swift`, `Packages/AppCore/Tests/AppCoreTests/VoiceChoiceTests.swift`

**Interfaces:**
- Consumes: Task 2 (`PiperVoiceCatalog`, `PiperVoice`, `PiperVoiceRef`, `AnnouncementVoice`, `VoiceAvailability`, `PiperVoice.menuOrder/.menuTitle/.progressText/.sizeText/.licenseText`), Task 3 (`PiperInstallation(contents:)`, `PiperVoiceFiles(voice:folder:)`, `PiperCommand`, `PiperRunner.run`, `PiperError`, `WAVInfo.hasSpeech`, `FileChecksum.matches`), Task 4 (Piper im Paket), bestehend `TalkbackLog.write`, `AnnouncementAudio.load/.loudnessGain`, `PreviewPlayer.play(_:id:)`.
- Produces:
  - `@MainActor final class PiperVoiceStore: ObservableObject { static shared; @Published downloads: [String: Int64]; @Published downloadedIds: Set<String>; folder: URL; installation: PiperInstallation; func availability(_:) -> VoiceAvailability; downloadedVoices: [PiperVoice]; func files(for:) -> PiperVoiceFiles; func refresh(); func ensure(_:) async throws -> PiperVoiceFiles; func cancelDownload(_:); func remove(_:); func render(text: String, voice: PiperVoiceRef) async throws -> URL; #if DEBUG simulateDownload(_:received:), simulateDownloaded(_:) }`
  - `SoundStore.previewBuffer(text: String, voice: PiperVoiceRef) async throws -> AVAudioPCMBuffer`, `SoundStore.applySpeech(id: UUID, text: String, voice: PiperVoiceRef) async throws`, `SoundStore.addText()` (Stimme `PiperVoiceRef.standard`)
  - `SnapshotRenderer.soundTabVoice: PiperVoiceRef?` (Task 7 setzt es)

- [ ] **Step 1: macOS-Stimmen aus AppCore entfernen (Tests zuerst anpassen)**

```bash
git rm Packages/AppCore/Sources/AppCore/Sound/VoiceChoice.swift Packages/AppCore/Tests/AppCoreTests/VoiceChoiceTests.swift
```

In `Packages/AppCore/Tests/AppCoreTests/SoundSettingsTests.swift` ersetzen:

```swift
        rerendered.fileName = "x.caf"
        rerendered.voiceIdentifier = "com.apple.voice.premium.de-DE.Anna"
```

durch:

```swift
        rerendered.fileName = "x.wav"
        rerendered.voiceIdentifier = "piper:de_DE-thorsten_emotional-medium#4"
```

In `Packages/AppCore/Tests/AppCoreTests/SoundSettingsTests.swift` diesen Block (die drei AVSpeech-Tests) ersatzlos löschen – er steht direkt vor `    func testAnnouncementDecodingKeepsEntryAndSanitizesFileName() throws {`:

```swift
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

    func testRenderRejectsEmptyText() async {
        do {
            _ = try await AnnouncementAudio.render(text: "   ", voiceIdentifier: nil)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? TalkbackError, .speechFailed)
        }
    }

    func testRenderTimesOut() async throws {
        do {
            _ = try await AnnouncementAudio.render(text: "Bin gleich da, ich muss noch etwas Längeres sagen.", voiceIdentifier: nil, timeout: 0.001)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? TalkbackError, .speechFailed)
        }
    }
```

Datei `Packages/AppCore/Sources/AppCore/Sound/AnnouncementAudio.swift` ganz ersetzen (ohne `voices`, `preferredVoice`, `candidate`, `label`, `render`, `SpeechCollector`):

```swift
import AVFoundation
import Foundation

/// Loads, converts, measures and writes announcement audio (MP3, CAF, Piper WAV).
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

    /// Writes a buffer as CAF.
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
```

In `Packages/AppCore/Sources/AppCore/Sound/SoundSettings.swift` ersetzen:

```swift
    /// Label of the voice of the bundled recordings (Piper, Thorsten, CC0).
    public static let bundledVoiceLabel = "Thorsten · mitgeliefert"

    /// The shipped original an entry was made from (also after it was re-rendered with a macOS voice).
```

durch:

```swift
    /// The shipped original an entry was made from (also after it was rendered again).
```

In `Packages/AppCore/Sources/AppCore/Sound/Announcement.swift` ersetzen:

```swift
    /// macOS voice (`AVSpeechSynthesisVoice.identifier`); nil = the bundled recording's voice.
```

durch:

```swift
    /// Piper voice „piper:<id>#<speaker>“ (`PiperVoiceRef`); before Phase 6 a macOS voice identifier;
    /// nil = the bundled recording's voice.
```

- [ ] **Step 2: AppCore-Tests laufen**

Run: `(cd Packages/AppCore && swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -3)`
Expected: `Executed 160 tests, with 0 failures` (166 − 3 VoiceChoice − 3 AVSpeech). `grep -rn "AVSpeech\|VoiceChoice\|preferredVoice" Packages/AppCore` → keine Treffer.

Der App-Build ist ab hier bis Step 6 rot (`SoundStore`/`SoundTab` nutzen noch die alten Funktionen) – das ist erwartet.

- [ ] **Step 3: Stimmen-Speicher der App**

Datei `UniFiCameraPopup/Services/PiperVoiceStore.swift` neu anlegen:

```swift
import AppCore
import Foundation

/// Piper voices on this Mac: the bundled Thorsten (medium) in the app, every other offered voice
/// downloaded on first use into ~/Library/Application Support/UniFi Camera Popup/Voices/<id>/
/// (pinned revision, size + SHA-256 checked), and rendering text with Piper (Process, never linked).
/// Not part of the configuration export.
@MainActor
final class PiperVoiceStore: ObservableObject {
    static let shared = PiperVoiceStore()

    /// Running downloads by voice id: bytes received so far.
    @Published private(set) var downloads: [String: Int64] = [:]
    /// Downloaded voices (not the bundled one).
    @Published private(set) var downloadedIds: Set<String> = []

    let folder: URL
    let installation = PiperInstallation(contents: Bundle.main.bundleURL.appendingPathComponent("Contents", isDirectory: true))
    private var tasks: [String: Task<PiperVoiceFiles, Error>] = [:]
    #if DEBUG
    private let isSnapshot = SnapshotRenderer.isActive
    #else
    private let isSnapshot = false
    #endif

    private init() {
        if isSnapshot {
            folder = FileManager.default.temporaryDirectory.appendingPathComponent("UniFiCameraPopup-snapshot-voices", isDirectory: true)
        } else {
            folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("UniFi Camera Popup/Voices", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        refresh()
    }

    // MARK: State

    func availability(_ voice: PiperVoice) -> VoiceAvailability {
        if voice.id == PiperVoiceCatalog.bundledVoiceId { return .bundled }
        return downloadedIds.contains(voice.id) ? .downloaded : .notDownloaded
    }

    var downloadedVoices: [PiperVoice] {
        PiperVoice.menuOrder.filter { downloadedIds.contains($0.id) }
    }

    func files(for voice: PiperVoice) -> PiperVoiceFiles {
        if voice.id == PiperVoiceCatalog.bundledVoiceId {
            return PiperVoiceFiles(voice: voice, folder: installation.bundledVoices)
        }
        return PiperVoiceFiles(voice: voice, folder: voiceFolder(voice))
    }

    private func voiceFolder(_ voice: PiperVoice) -> URL {
        folder.appendingPathComponent(voice.id, isDirectory: true)
    }

    /// A voice counts as downloaded when both files have the pinned size (the hash was checked
    /// before the folder got its final name). Leftover partial folders are removed.
    func refresh() {
        // `--render-snapshots` sets the state itself (simulateDownloaded).
        guard !isSnapshot else { return }
        var found: Set<String> = []
        for voice in PiperVoiceCatalog.offered where voice.id != PiperVoiceCatalog.bundledVoiceId {
            let files = files(for: voice)
            if Self.size(files.model) == voice.model.size, Self.size(files.config) == voice.config.size {
                found.insert(voice.id)
            }
        }
        downloadedIds = found
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for entry in entries where entry.hasSuffix(".partial") && tasks.isEmpty {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(entry))
        }
    }

    private static func size(_ url: URL) -> Int64? {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value
    }

    // MARK: Download

    /// The voice's files, downloading them first if needed (one download per voice at a time).
    func ensure(_ voice: PiperVoice) async throws -> PiperVoiceFiles {
        if availability(voice) != .notDownloaded { return files(for: voice) }
        if let running = tasks[voice.id] { return try await running.value }
        let task = Task { @MainActor [weak self] () throws -> PiperVoiceFiles in
            guard let self else { throw CancellationError() }
            return try await self.download(voice)
        }
        tasks[voice.id] = task
        defer {
            tasks[voice.id] = nil
            downloads[voice.id] = nil
        }
        return try await task.value
    }

    func cancelDownload(_ voice: PiperVoice) {
        tasks[voice.id]?.cancel()
    }

    private func download(_ voice: PiperVoice) async throws -> PiperVoiceFiles {
        let partial = folder.appendingPathComponent("\(voice.id).partial", isDirectory: true)
        let manager = FileManager.default
        try? manager.removeItem(at: partial)
        do {
            try manager.createDirectory(at: partial, withIntermediateDirectories: true)
        } catch {
            throw PiperError.download(error.localizedDescription)
        }
        downloads[voice.id] = 0
        TalkbackLog.write("Stimme: lade „\(voice.label)“ (\(voice.sizeText)) von \(voice.model.url.absoluteString)")
        do {
            var done: Int64 = 0
            for file in [voice.config, voice.model] {
                let target = partial.appendingPathComponent(file.fileName)
                try await fetch(file, to: target) { [weak self] received in
                    Task { @MainActor in
                        guard let self, self.downloads[voice.id] != nil else { return }
                        self.downloads[voice.id] = done + received
                    }
                }
                done += file.size
                let ok = await Task.detached(priority: .utility) { FileChecksum.matches(target, file) }.value
                guard ok else { throw PiperError.checksum(voice.label) }
            }
            try Task.checkCancellation()
            let final = voiceFolder(voice)
            try? manager.removeItem(at: final)
            try manager.moveItem(at: partial, to: final)
        } catch {
            try? manager.removeItem(at: partial)
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                TalkbackLog.write("Stimme: Laden von „\(voice.label)“ abgebrochen")
                throw CancellationError()
            }
            TalkbackLog.write("Stimme: Laden von „\(voice.label)“ fehlgeschlagen – \(error.localizedDescription)")
            if error is PiperError { throw error }
            throw PiperError.download((error as? URLError)?.localizedDescription ?? error.localizedDescription)
        }
        downloadedIds.insert(voice.id)
        TalkbackLog.write("Stimme: „\(voice.label)“ geladen")
        return files(for: voice)
    }

    /// One file via URLSession; progress through the task's received bytes.
    private func fetch(_ file: VoiceFile, to target: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let observer = DownloadObserver(progress: progress)
        let (temporary, response) = try await URLSession.shared.download(from: file.url, delegate: observer)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw PiperError.download("HTTP \(status)")
        }
        try FileManager.default.moveItem(at: temporary, to: target)
    }

    // MARK: Remove

    func remove(_ voice: PiperVoice) {
        guard voice.id != PiperVoiceCatalog.bundledVoiceId else { return }
        cancelDownload(voice)
        try? FileManager.default.removeItem(at: voiceFolder(voice))
        downloadedIds.remove(voice.id)
        TalkbackLog.write("Stimme: „\(voice.label)“ entfernt")
    }

    // MARK: Rendering

    /// Speaks `text` with Piper into a new WAV in the temporary folder (the caller moves or deletes it).
    /// Downloads the voice first if needed. Never falls back to another voice.
    func render(text: String, voice ref: PiperVoiceRef) async throws -> URL {
        guard let (voice, speaker) = ref.resolved else { throw PiperError.voiceNotInstalled(ref.label) }
        guard let input = PiperCommand.input(for: text) else { throw PiperError.noAudio }
        let files = try await ensure(voice)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("piper-\(UUID().uuidString).wav")
        let arguments = PiperCommand.arguments(
            installation: installation, files: files,
            speaker: PiperCommand.speakerArgument(voice: voice, speaker: speaker), output: output
        )
        let start = Date()
        do {
            try await PiperRunner.run(executable: installation.executable, arguments: arguments, input: input)
            let data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: output) }.value
            let speech = await Task.detached(priority: .userInitiated) { WAVInfo.hasSpeech(data) }.value
            guard speech else { throw PiperError.noAudio }
        } catch {
            try? FileManager.default.removeItem(at: output)
            if !(error is CancellationError) {
                TalkbackLog.write("Piper: „\(ref.label)“ fehlgeschlagen – \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
            }
            throw error
        }
        TalkbackLog.write(String(format: "Piper: „%@“, %d Zeichen in %.1f s", ref.label, input.count - 1, Date().timeIntervalSince(start)))
        return output
    }

    #if DEBUG
    /// `--render-snapshots`: show a download in progress without network.
    func simulateDownload(_ voiceId: String, received: Int64?) {
        downloads[voiceId] = received
    }

    func simulateDownloaded(_ ids: Set<String>) {
        downloadedIds = ids
    }
    #endif
}

/// Reports the received bytes of the one download task it is handed.
private final class DownloadObserver: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let progress: @Sendable (Int64) -> Void
    private var observation: NSKeyValueObservation?

    init(progress: @escaping @Sendable (Int64) -> Void) {
        self.progress = progress
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.observe(\.countOfBytesReceived, options: [.new]) { [progress] task, _ in
            progress(task.countOfBytesReceived)
        }
    }
}
```

```bash
python3 -I UniFiCameraPopup/scripts/pbxproj-add-files.py --prefix E6 Services 01 PiperVoiceStore.swift
plutil -lint UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj
```

Expected: `added PiperVoiceStore.swift E61000000000000000000001 E62000000000000000000001`, `OK`.

- [ ] **Step 4: Ton-Speicher erzeugt mit Piper**

Datei `UniFiCameraPopup/Services/SoundStore.swift` ganz ersetzen (geändert gegenüber Phase 5: `previewBuffer(text:voice:)`, `addText()` mit `PiperVoiceRef.standard`, `applySpeech(id:text:voice:)` verschiebt Pipers WAV als `<UUID>.wav` und misst sie im Hintergrund, `SpeechBuffer` statt `RenderedSpeech`; alles andere unverändert):

```swift
import AppCore
import AVFoundation
import Combine
import Foundation

/// Einstellungen › Ton: announcements, microphone, the two volumes.
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
    /// Set once the built-in "Gong" was offered, so a deleted Gong does not come back.
    private static let gongSeededKey = "unifi.camera.popup.sound.gongSeeded"
    private static let systemGong = URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff")
    #if DEBUG
    // `--render-snapshots`: throwaway defaults suite and a temporary folder, nothing reaches the real ones.
    private let defaults = SnapshotRenderer.isActive ? SnapshotRenderer.isolatedDefaults : UserDefaults.standard
    private static let isSnapshot = SnapshotRenderer.isActive
    #else
    private let defaults = UserDefaults.standard
    private static let isSnapshot = false
    #endif

    /// Saved settings could not be decoded: no cleanup, and the old blob is backed up before the first save.
    private var loadFailed = false

    private init() {
        if Self.isSnapshot {
            folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("UniFiCameraPopup-snapshot-sounds", isDirectory: true)
        } else {
            folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("UniFi Camera Popup/Sounds", isDirectory: true)
        }
        let stored = defaults.data(forKey: Self.storageKey)
        if let stored, let saved = try? JSONDecoder().decode(SoundSettings.self, from: stored) {
            settings = saved
        } else {
            settings = SoundSettings()
            // A blob exists but is unreadable (corrupt, newer schema): keep files and blob untouched.
            loadFailed = stored != nil
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard !loadFailed, defaults.data(forKey: Self.storageKey + ".corrupt-backup") == nil else { return }
        removeUnreferencedFiles()
        if !Self.isSnapshot {
            seedGongIfNeeded()
            measureMissingLoudness()
        }
    }

    // MARK: Loudness

    /// Files whose measurement failed this session: played with factor 1, not measured again.
    private var failedLoudness: Set<String> = []
    private var measuring: Set<UUID> = []

    /// Writes a factor measured off the main thread, only if the entry still has the same file.
    func recordLoudness(_ gain: Float?, id: UUID, fileName: String?) {
        measuring.remove(id)
        guard var entry = settings.announcement(id: id), entry.fileName == fileName else { return }
        guard let gain else {
            if let fileName { failedLoudness.insert(fileName) }
            return
        }
        guard entry.loudnessGain == nil else { return }
        entry.loudnessGain = Double(gain)
        settings.update(entry)
    }

    /// Entries without a factor (before Phase 5, bundled, just imported): measured once in the background.
    func measureMissingLoudness() {
        let pending = settings.announcements.compactMap { entry -> (UUID, String?, URL)? in
            guard entry.loudnessGain == nil, !measuring.contains(entry.id),
                  !(entry.fileName.map(failedLoudness.contains) ?? false),
                  let url = audioURL(for: entry) else { return nil }
            return (entry.id, entry.fileName, url)
        }
        guard !pending.isEmpty else { return }
        for (id, _, _) in pending { measuring.insert(id) }
        Task.detached(priority: .utility) {
            for (id, fileName, url) in pending {
                let gain = (try? AnnouncementAudio.load(url)).flatMap { try? AnnouncementAudio.loudnessGain(of: $0) }
                await MainActor.run { SoundStore.shared.recordLoudness(gain, id: id, fileName: fileName) }
            }
        }
    }

    // MARK: Audio

    /// Playable audio of an entry: copied/rendered file, else the bundled MP3. nil = file missing.
    func audioURL(for announcement: Announcement) -> URL? {
        if let name = announcement.fileName {
            guard let url = resolve(name) else { return nil }
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        if let resource = announcement.bundledResource {
            return Bundle.main.url(forResource: resource, withExtension: "mp3")
        }
        return nil
    }

    /// Audio for "Anhören": the text as „Übernehmen“ would render it with this Piper voice.
    func previewBuffer(text: String, voice: PiperVoiceRef) async throws -> AVAudioPCMBuffer {
        let wav = try await PiperVoiceStore.shared.render(text: text, voice: voice)
        defer { try? FileManager.default.removeItem(at: wav) }
        return try await Task.detached(priority: .userInitiated) { SpeechBuffer(buffer: try AnnouncementAudio.load(wav)) }.value.buffer
    }

    /// Maps a stored file name to a URL inside the sound folder: only the last path component
    /// counts, and the result must lie in the folder. nil = unusable name.
    private func resolve(_ name: String) -> URL? {
        let component = (name as NSString).lastPathComponent
        guard !component.isEmpty, component != ".", component != ".." else { return nil }
        let base = folder.standardizedFileURL
        let url = base.appendingPathComponent(component).standardizedFileURL
        let prefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
        return url.path.hasPrefix(prefix) && url.path != base.path ? url : nil
    }

    /// First run: the built-in "Gong" is a copy of the macOS system sound (never bundled).
    private func seedGongIfNeeded() {
        guard !defaults.bool(forKey: Self.gongSeededKey) else { return }
        defaults.set(true, forKey: Self.gongSeededKey)
        guard !settings.announcements.contains(where: { $0.name == "Gong" }),
              FileManager.default.fileExists(atPath: Self.systemGong.path),
              let duration = try? AnnouncementAudio.duration(of: Self.systemGong), duration > 0,
              duration <= SoundSettings.maxFileDuration else { return }
        let name = "\(UUID().uuidString).aiff"
        guard let target = resolve(name),
              (try? FileManager.default.copyItem(at: Self.systemGong, to: target)) != nil else { return }
        settings.add(Announcement(name: "Gong", kind: .file, fileName: name, duration: duration))
        save()
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

    /// "Ansage aus Text …": new empty text entry for Thorsten (medium), the bundled Piper voice.
    @discardableResult
    func addText() -> Announcement {
        let entry = Announcement(
            name: Announcement.newName,
            kind: .speech,
            voiceIdentifier: PiperVoiceRef.standard.identifier
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

    /// "Übernehmen": Piper speaks the text with `voice`; the WAV becomes the entry's audio (also
    /// for entries rendered by a macOS voice before Phase 6 and for the bundled recordings).
    func applySpeech(id: UUID, text: String, voice: PiperVoiceRef) async throws {
        guard let current = settings.announcement(id: id) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var entry = current
        entry.kind = .speech
        entry.text = trimmed
        let wav = try await PiperVoiceStore.shared.render(text: trimmed, voice: voice)
        let name = "\(UUID().uuidString).wav"
        guard let target = resolve(name) else {
            try? FileManager.default.removeItem(at: wav)
            throw TalkbackError.audioFile("Ablage")
        }
        // Moving, measuring and reading the length take a moment: off the main thread.
        let (duration, gain) = try await Task.detached(priority: .userInitiated) { () throws -> (TimeInterval, Double?) in
            do {
                try FileManager.default.moveItem(at: wav, to: target)
            } catch {
                try? FileManager.default.removeItem(at: wav)
                throw TalkbackError.audioFile(error.localizedDescription)
            }
            let buffer = try AnnouncementAudio.load(target)
            let gain = (try? AnnouncementAudio.loudnessGain(of: buffer)).map(Double.init)
            return (Double(buffer.frameLength) / buffer.format.sampleRate, gain)
        }.value
        entry.voiceIdentifier = voice.identifier
        entry.fileName = name
        entry.duration = duration
        entry.loudnessGain = gain
        // Deleted while rendering: drop the new file.
        guard var latest = settings.announcement(id: id) else {
            deleteFile(entry.fileName)
            return
        }
        // Edited while rendering (e.g. renamed): apply only the rendered fields to the current state.
        let previousFile = latest.fileName
        latest.kind = entry.kind
        latest.text = entry.text
        latest.voiceIdentifier = entry.voiceIdentifier
        latest.fileName = entry.fileName
        latest.duration = entry.duration
        latest.loudnessGain = entry.loudnessGain
        if latest.hasAutomaticName {
            latest.name = Announcement.suggestedName(forText: trimmed)
        }
        settings.update(latest)
        if previousFile != latest.fileName {
            deleteFile(previousFile)
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
        guard duration.isFinite, duration > 0 else { throw TalkbackError.audioFile("leer") }
        guard duration <= SoundSettings.maxFileDuration else { throw TalkbackError.fileTooLong }
        let ext = source.pathExtension.isEmpty ? "mp3" : source.pathExtension.lowercased()
        let name = "\(UUID().uuidString).\(ext)"
        guard let target = resolve(name) else { throw TalkbackError.audioFile("Ablage") }
        do {
            try FileManager.default.copyItem(at: source, to: target)
        } catch {
            throw TalkbackError.audioFile(error.localizedDescription)
        }
        var updated = entry
        updated.fileName = name
        updated.duration = duration
        // The new file is measured in the background once the caller has stored the entry.
        updated.loudnessGain = nil
        Task { @MainActor [weak self] in self?.measureMissingLoudness() }
        return updated
    }

    private func deleteFile(_ name: String?) {
        guard let name, let url = resolve(name) else { return }
        try? FileManager.default.removeItem(at: url)
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
        if loadFailed {
            loadFailed = false
            let backupKey = Self.storageKey + ".corrupt-backup"
            if defaults.data(forKey: backupKey) == nil, let old = defaults.data(forKey: Self.storageKey) {
                defaults.set(old, forKey: backupKey)
            }
        }
        defaults.set(data, forKey: Self.storageKey)
    }
}

/// Hands a buffer loaded off the main thread back to it (not touched meanwhile).
private struct SpeechBuffer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}
```

- [ ] **Step 5: Reiter „Ton“**

In `UniFiCameraPopup/Debug/SnapshotRenderer.swift` ersetzen:

```swift
    nonisolated(unsafe) static var soundTabError: String?
```

durch:

```swift
    nonisolated(unsafe) static var soundTabError: String?
    /// Read by `SoundTab` as the voice of the selected entry (S5 voice variants).
    nonisolated(unsafe) static var soundTabVoice: PiperVoiceRef?
```

Datei `UniFiCameraPopup/Views/Settings/SoundTab.swift` ganz ersetzen (geändert: `voices`/`draftVoice` statt `voice`, Stimmenfeld + Sprecherfeld, Hinweis-/Fortschritts-/Lizenzzeile, Hinweis „macOS (alt) …“, Karte „Geladene Stimmen“ mit Rückfrage, `listen`/`apply` übergeben `draftVoice`, `message` meldet einen Abbruch nicht; Liste, MP3-Teil, Mikrofon und Regler unverändert):

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
    @ObservedObject private var voices = PiperVoiceStore.shared
    @State private var selectedId: UUID?
    @State private var draftKind: Announcement.Kind = .speech
    @State private var draftText = ""
    /// Piper voice + speaker for „Anhören“ and „Übernehmen“ of the selected entry.
    @State private var draftVoice: PiperVoiceRef = .standard
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
                if !voices.downloadedVoices.isEmpty {
                    downloadedVoicesCard
                }
                deviceCard
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 40)
        }
        .onAppear {
            devices = MicrophoneCapture.inputDevices()
            voices.refresh()
            if selected == nil {
                select(store.settings.announcements.first)
            }
            #if DEBUG
            if let sample = SnapshotRenderer.soundTabError { errorText = sample }
            if let sample = SnapshotRenderer.soundTabVoice { draftVoice = sample }
            #endif
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
            // Without a selection there is no editor card to show the error in.
            if selected == nil, let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .fixedSize(horizontal: false, vertical: true)
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
                    PopUpField(selection: voiceSelection, options: voiceOptions)
                        .accessibilityLabel("Stimme")
                    if let voice = draftVoice.resolved?.voice, voice.isMultiSpeaker {
                        PopUpField(selection: speakerSelection, options: speakerOptions(voice))
                            .accessibilityLabel("Sprecher")
                    }
                    Spacer()
                    Button("Anhören") { listen(sound) }
                        .buttonStyle(FieldButtonStyle())
                        .disabled(busy || trimmedDraft.isEmpty)
                    Button("Übernehmen") { apply(sound) }
                        .buttonStyle(AccentButtonStyle(fontSize: 12, vertical: 3, horizontal: 10))
                        .disabled(busy || !AnnouncementVoice.canApply(sound, text: draftText, selection: draftVoice))
                }
                if let voice = draftVoice.resolved?.voice {
                    if let received = voices.downloads[voice.id] {
                        downloadProgress(voice, received: received)
                    } else {
                        Text(voices.availability(voice) == .notDownloaded
                             ? "Wird beim ersten Anhören oder Übernehmen geladen (\(voice.sizeText), einmalig) – danach auf diesem Mac erzeugt, ohne Internet."
                             : "Wird auf diesem Mac erzeugt – ohne Internet, ohne Konto.")
                            .font(.system(size: 11))
                            .foregroundStyle(Tokens.muted.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(voice.licenseText)
                        .font(.system(size: 11))
                        .foregroundStyle(Tokens.muted.color)
                        .lineLimit(1)
                }
                if let note = AnnouncementVoice.note(for: sound) {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .systemOrange))
                        .fixedSize(horizontal: false, vertical: true)
                }
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
            if let errorText, selected != nil {
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

    // MARK: Voices

    /// Voice id of the draft; choosing another voice starts with its default speaker.
    private var voiceSelection: Binding<String> {
        Binding(
            get: { draftVoice.voiceId },
            set: { id in
                guard let voice = PiperVoiceCatalog.voice(id: id) else { return }
                draftVoice = PiperVoiceRef(voice: voice)
            }
        )
    }

    private var voiceOptions: [(value: String, title: String)] {
        PiperVoice.menuOrder.map { (value: $0.id, title: $0.menuTitle(voices.availability($0))) }
    }

    private var speakerSelection: Binding<Int> {
        Binding(
            get: { draftVoice.resolved?.speaker ?? 0 },
            set: { draftVoice = PiperVoiceRef(voiceId: draftVoice.voiceId, speaker: $0) }
        )
    }

    private func speakerOptions(_ voice: PiperVoice) -> [(value: Int, title: String)] {
        (0..<voice.speakerCount).map { (value: $0, title: voice.speakerLabel($0) ?? "Sprecher \($0 + 1)") }
    }

    private func downloadProgress(_ voice: PiperVoice, received: Int64) -> some View {
        HStack(spacing: 8) {
            ProgressView(value: Double(received), total: Double(max(voice.downloadSize, 1)))
                .progressViewStyle(.linear)
                .tint(Tokens.accent.color)
                .frame(width: 120)
                .accessibilityLabel("Stimme wird geladen")
            Text(voice.progressText(received: received))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Tokens.muted.color)
                .lineLimit(1)
            Spacer()
            Button("Abbrechen") { voices.cancelDownload(voice) }
                .buttonStyle(LinkButtonStyle())
        }
    }

    /// Downloaded voices with their size and „Entfernen“ (the bundled voice is not listed).
    private var downloadedVoicesCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionLabel(text: "Geladene Stimmen")
            Card {
                ForEach(Array(voices.downloadedVoices.enumerated()), id: \.element.id) { index, voice in
                    if index > 0 { CardDivider() }
                    HStack(spacing: 10) {
                        Text(voice.label).frame(maxWidth: .infinity, alignment: .leading)
                        Text(voice.sizeText)
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Tokens.muted.color)
                        Button("Entfernen") { removeVoice(voice) }
                            .buttonStyle(LinkButtonStyle())
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                }
            }
        }
    }

    private func removeVoice(_ voice: PiperVoice) {
        let alert = NSAlert()
        alert.messageText = "„\(voice.label)“ entfernen?"
        alert.informativeText = "Ansagen mit dieser Stimme spielen weiter. Zum Anhören oder neu Erzeugen wird sie wieder geladen (\(voice.sizeText))."
        alert.addButton(withTitle: "Entfernen")
        alert.addButton(withTitle: "Abbrechen")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        voices.remove(voice)
    }

    // MARK: Microphone, volume

    private var deviceCard: some View {
        Card {
            CardRow(title: "Mikrofon") {
                PopUpField(selection: microphone, options: microphoneOptions)
            }
            CardDivider()
            CardRow(title: "Lautstärke Sprechen") {
                VolumeSlider(value: $store.settings.talkVolume, label: "Lautstärke Sprechen")
            }
            CardDivider()
            CardRow(title: "Lautstärke Ansagen") {
                VolumeSlider(value: $store.settings.announcementVolume, label: "Lautstärke Ansagen")
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
        draftVoice = sound.map(AnnouncementVoice.initialSelection) ?? .standard
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
                try await store.applySpeech(id: sound.id, text: text, voice: voice)
                if selectedId == sound.id { select(store.settings.announcement(id: sound.id)) }
            } catch {
                if selectedId == sound.id { errorText = message(error) }
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
                let buffer = try await store.previewBuffer(text: text, voice: voice)
                preview.play(buffer, id: sound.id)
            } catch {
                if selectedId == sound.id { errorText = message(error) }
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

    /// nil for a cancelled download (the user pressed „Abbrechen“ – nothing to report).
    private func message(_ error: Error) -> String? {
        if error is CancellationError { return nil }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
```

- [ ] **Step 6: Bauen und prüfen**

```bash
DD="${TMPDIR:-/tmp}/ucp-phase6-dd"
xcodebuild -project UniFiCameraPopup/UniFiCameraPopup.xcodeproj -scheme UniFiCameraPopup \
  -configuration Debug -derivedDataPath "$DD" build 2>&1 | grep -E "error:|piper-smoke|\*\* BUILD" | tail -10
grep -rn "AVSpeech\|VoiceChoice\|preferredVoice\|AnnouncementAudio.render" UniFiCameraPopup Packages/AppCore/Sources   # → keine Treffer
(cd Packages/AppCore && swift test 2>&1 | grep -E "error:|Executed [0-9]+ tests" | tail -1)   # → 160 tests, 0 failures
OUT="${TMPDIR:-/tmp}/ucp-phase6-snap"; rm -rf "$OUT"; mkdir -p "$OUT"
"$DD/Build/Products/Debug/UniFi Camera Popup.app/Contents/MacOS/UniFi Camera Popup" --render-snapshots "$OUT" > /dev/null
open "$OUT/S5-ton-light.png" "$OUT/S5-ton-dark.png"
```

Expected: `** BUILD SUCCEEDED **`; Bild S5: Feld „Thorsten · mittel – mitgeliefert“ (aktiv, mit Pfeilen), „Wird auf diesem Mac erzeugt – ohne Internet, ohne Konto.“, „Lizenz der Stimme: CC0 1.0 · Thorsten-Voice (Thorsten Müller)“, „Übernehmen“ grau (mitgelieferte Aufnahme, gleicher Text), keine orange Zeile, keine Karte „Geladene Stimmen“.

- [ ] **Step 7: Commit**

```bash
git add UniFiCameraPopup/Services/PiperVoiceStore.swift UniFiCameraPopup/Services/SoundStore.swift \
  UniFiCameraPopup/Views/Settings/SoundTab.swift UniFiCameraPopup/Debug/SnapshotRenderer.swift \
  UniFiCameraPopup/UniFiCameraPopup.xcodeproj/project.pbxproj \
  Packages/AppCore/Sources/AppCore/Sound/AnnouncementAudio.swift Packages/AppCore/Sources/AppCore/Sound/SoundSettings.swift \
  Packages/AppCore/Sources/AppCore/Sound/Announcement.swift Packages/AppCore/Tests/AppCoreTests/SoundSettingsTests.swift
git diff --cached --name-only | grep AppConfig   # → leer (VoiceChoice*.swift sind durch git rm schon vorgemerkt)
git commit -m "feat(sound): Piper voices in the Sound tab – download, verify, remove; macOS voices removed

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Sichtprüfung, Hilfe, „Was ist neu“, Design-Doku, manuelle Prüfpunkte (braucht Task 5 + 6)

**Files:**
- Modify: `UniFiCameraPopup/Debug/SnapshotRenderer.swift` (S5-Varianten), `UniFiCameraPopup/Views/HelpView.swift:159`, `UniFiCameraPopup/Services/WhatsNewService.swift:32`, `docs/design/einstellungen-ton.md`, `docs/superpowers/manual-checks-2.0.0.md`

**Interfaces:**
- Consumes: `SnapshotRenderer.soundTabVoice`, `PiperVoiceStore.simulateDownload(_:received:)`, `.simulateDownloaded(_:)` (Task 6), `PiperError.timeout` (Task 3).
- Produces: Bilder `S5-ton-stimme-nicht-geladen-*`, `S5-ton-stimme-laedt-*`, `S5-ton-sprecher-*`, `S5-ton-macos-alt-*` (hell + dunkel).

- [ ] **Step 1: Neue Renderer-Zustände**

In `UniFiCameraPopup/Debug/SnapshotRenderer.swift` ersetzen:

```swift
            SnapshotRenderer.soundTabError = nil
            SoundStore.shared.settings.announcements = savedSounds
```

durch:

```swift
            SnapshotRenderer.soundTabError = nil
            SoundStore.shared.settings.announcements = savedSounds
            // Phase 6: a voice that is not downloaded yet, loading, next to an already downloaded one.
            SnapshotRenderer.soundTabVoice = PiperVoiceRef(voiceId: "de_DE-kerstin-low")
            PiperVoiceStore.shared.simulateDownloaded(["de_DE-thorsten-high"])
            write(window: settingsWindow(tab: .sound), appearance: appearance,
                  to: directory.appendingPathComponent("S5-ton-stimme-nicht-geladen-\(suffix).png"))
            PiperVoiceStore.shared.simulateDownload("de_DE-kerstin-low", received: 23_400_000)
            write(window: settingsWindow(tab: .sound), appearance: appearance,
                  to: directory.appendingPathComponent("S5-ton-stimme-laedt-\(suffix).png"))
            PiperVoiceStore.shared.simulateDownload("de_DE-kerstin-low", received: nil)
            // Multi-speaker voice: second field with the speaker.
            SnapshotRenderer.soundTabVoice = PiperVoiceRef(voiceId: "de_DE-thorsten_emotional-medium", speaker: 4)
            write(window: settingsWindow(tab: .sound), appearance: appearance,
                  to: directory.appendingPathComponent("S5-ton-sprecher-\(suffix).png"))
            SnapshotRenderer.soundTabVoice = nil
            PiperVoiceStore.shared.simulateDownloaded([])
            // An announcement rendered by a macOS voice before Phase 6, with a Piper error line.
            SoundStore.shared.settings.announcements = [
                Announcement(name: "Bitte warten", kind: .speech, text: "Bitte einen Moment warten.",
                             voiceIdentifier: "com.apple.voice.premium.de-DE.Anna", fileName: "alt.caf", duration: 2.1),
            ] + savedSounds
            SnapshotRenderer.soundTabError = PiperError.timeout(20).errorDescription
            write(window: settingsWindow(tab: .sound), appearance: appearance,
                  to: directory.appendingPathComponent("S5-ton-macos-alt-\(suffix).png"))
            SnapshotRenderer.soundTabError = nil
            SoundStore.shared.settings.announcements = savedSounds
```

- [ ] **Step 2: Hilfe und „Was ist neu“**

In `UniFiCameraPopup/Views/HelpView.swift` ersetzen:

```swift
                + "die Ansagen (MP3 oder Text, gesprochen von der macOS-Stimme Anna, erzeugt auf diesem Mac). Die mitgelieferten Ansagen "
```

durch:

```swift
                + "die Ansagen (MP3 oder Text, gesprochen von einer Piper-Stimme und erzeugt auf diesem Mac). „Thorsten · mittel“ ist mitgeliefert; "
                + "weitere deutsche Stimmen lädt die App beim ersten Anhören oder Übernehmen einmalig (Größe steht in der Auswahl) "
                + "und du entfernst sie unter „Geladene Stimmen“ wieder. Die mitgelieferten Ansagen "
```

In `UniFiCameraPopup/Services/WhatsNewService.swift` ersetzen:

```swift
Fertige Ansagen spielst du als MP3 oder mit der macOS-Stimme Anna aus eigenem Text ab.
```

durch:

```swift
Fertige Ansagen spielst du als MP3 oder aus eigenem Text ab – gesprochen von Piper-Stimmen direkt auf dem Mac: „Thorsten“ ist dabei, acht weitere deutsche Stimmen lädt die App beim ersten Gebrauch.
```

(Nur dieser Satz innerhalb des bestehenden 2.0.0-Punkts „Sprechen und Ansagen: …“; Version und Build bleiben.)

- [ ] **Step 3: Design-Doku**

An `docs/design/einstellungen-ton.md` anhängen:

```markdown

## Phase 6 (Nutzerwunsch, gilt vor Vorlage und Phase 5)
- Stimme: Auswahlfeld aktiv mit allen angebotenen Piper-Stimmen, Reihenfolge „Thorsten · mittel – mitgeliefert“, dann
  Eva K. · sehr niedrig, Karlsson · niedrig, Kerstin · niedrig, MLS · mittel, Ramona · niedrig, Thorsten · niedrig,
  Thorsten · hoch, Thorsten emotional · mittel; Zusatz „– geladen“ bzw. „– NN MB laden“. Pavoque wird nicht angeboten (CC BY-NC-SA).
- Mehrsprecher-Stimme: zweites Auswahlfeld direkt rechts daneben (Thorsten emotional: amüsiert … flüsternd, Standard neutral;
  MLS: Sprecher 1 … 236).
- Unter der Zeile 11 `muted`: „Wird auf diesem Mac erzeugt – ohne Internet, ohne Konto.“ bzw. bei nicht geladener Stimme
  „Wird beim ersten Anhören oder Übernehmen geladen (NN MB, einmalig) – danach auf diesem Mac erzeugt, ohne Internet.“;
  während des Ladens stattdessen Zeile Abstand 8: Fortschrittsbalken 120 breit (`accent`) · „Lade „<Stimme>“ … 23 von 63 MB“
  11 `muted` tabellarisch · Freiraum · Link „Abbrechen“.
- Darunter 11 `muted` einzeilig: „Lizenz der Stimme: <Lizenz> · <Datensatz>“.
- Alte macOS-Ansage: 11 System-Orange „macOS (alt) – mit „Übernehmen“ neu erzeugen“ (Feld zeigt die Zielstimme).
- Neue Karte „Geladene Stimmen“ zwischen Editor und Mikrofon-Karte (nur mit mindestens einer geladenen Stimme):
  Abschnittstitel wie „Ansagen …“, Zeilen Innenabstand 6/12: Name · Qualität füllt · Größe 11 `muted` · Link „Entfernen“
  (Rückfrage nativ).
```

- [ ] **Step 4: Bildvergleich**

```bash
DD="${TMPDIR:-/tmp}/ucp-phase6-dd"
xcodebuild -project UniFiCameraPopup/UniFiCameraPopup.xcodeproj -scheme UniFiCameraPopup \
  -configuration Debug -derivedDataPath "$DD" build 2>&1 | grep -E "error:|\*\* BUILD" | tail -3
OUT="${TMPDIR:-/tmp}/ucp-phase6-snap"; rm -rf "$OUT"; mkdir -p "$OUT"
"$DD/Build/Products/Debug/UniFi Camera Popup.app/Contents/MacOS/UniFi Camera Popup" --render-snapshots "$OUT" > /dev/null
ls "$OUT" | grep -c "S5-ton"   # → 12
open "$OUT"/S5-ton-*
```

Jedes Bild gegen `docs/design/einstellungen-ton.md` (Phase 5 + 6) ansehen und abhaken:
- `S5-ton-stimme-nicht-geladen-*`: Feld „Kerstin · niedrig – 63 MB laden“, Hinweis „Wird beim ersten Anhören oder Übernehmen geladen (63 MB, einmalig) – …“, „Lizenz der Stimme: CC0 1.0 · dataset-voice-kerstin (Rhasspy)“, „Übernehmen“ aktiv; Karte „Geladene Stimmen“ mit „Thorsten · hoch“, „114 MB“, „Entfernen“.
- `S5-ton-stimme-laedt-*`: violetter Balken ≈ 37 %, „Lade „Kerstin · niedrig“ … 23 von 63 MB“, „Abbrechen“ rechts.
- `S5-ton-sprecher-*`: „Thorsten emotional · mittel – 77 MB laden“ und daneben „neutral“.
- `S5-ton-macos-alt-*`: Ansage „Bitte warten“ ausgewählt, Feld „Thorsten · mittel – mitgeliefert“, orange „macOS (alt) – mit „Übernehmen“ neu erzeugen“ und darunter orange „Piper hat nach 20 Sekunden keinen Ton geliefert und wurde beendet.“, „Übernehmen“ aktiv.
- Hell und dunkel: keine abgeschnittenen Texte, Fokusringe/Abstände wie die übrigen Zeilen. Abweichungen sind Fragen an den Nutzer, nicht still lösen.

- [ ] **Step 5: Manuelle Prüfpunkte**

An `docs/superpowers/manual-checks-2.0.0.md` anhängen:

```markdown

## Phase 6: Piper-Stimmen (Debug-Build; installierte App vorher beenden)

Vorher: `defaults export com.snackbits.UniFiCameraPopup ~/ucp-backup-phase6.plist`; `tail -f ~/Library/Logs/UniFi\ Camera\ Popup/talkback.log` in einem Terminal.

- [ ] Reiter Ton, „Bin gleich da“: Feld „Thorsten · mittel – mitgeliefert“, „Übernehmen“ grau; Text ändern → „Übernehmen“ → Log „Piper: „Thorsten · mittel“, … Zeichen in 0.x s“, Länge in der Liste stimmt, Probehören klingt nach Thorsten. WLAN aus: dasselbe geht weiter.
- [ ] Alte Anna-Ansage (aus Phase 5 übernommen): spielt beim Probehören und an der Kamera wie vorher; Editor zeigt orange „macOS (alt) – mit „Übernehmen“ neu erzeugen“; „Übernehmen“ ohne Textänderung → danach Thorsten, Hinweis weg, alte `.caf` aus `~/Library/Application Support/UniFi Camera Popup/Sounds` verschwunden.
- [ ] Stimme „Kerstin · niedrig – 63 MB laden“ wählen → „Anhören“: Fortschrittszeile zählt bis 63 MB, danach spricht Kerstin; Feld zeigt „– geladen“, Karte „Geladene Stimmen“ erscheint; `ls ~/Library/Application\ Support/UniFi\ Camera\ Popup/Voices/de_DE-kerstin-low` → `.onnx` + `.onnx.json`, kein `.partial`.
- [ ] Laden abbrechen: „Thorsten · hoch“ wählen, „Anhören“, nach ein paar MB „Abbrechen“ → keine Fehlermeldung, Feld wieder „– 114 MB laden“, kein `de_DE-thorsten-high.partial` übrig. Erneut mit WLAN aus → orange „Die Stimme konnte nicht geladen werden (…)“; App läuft weiter.
- [ ] „Thorsten emotional“: Sprecher „flüsternd“ → „Übernehmen“ → flüstert; Ansage erneut auswählen → Felder zeigen „Thorsten emotional · mittel …“ und „flüsternd“. MLS: „Sprecher 12“ → andere Stimme als „Sprecher 1“.
- [ ] „Entfernen“ in „Geladene Stimmen“ → Rückfrage → Ordner weg; eine mit Kerstin erzeugte Ansage spielt weiter; erneut „Anhören“ mit Kerstin lädt sie wieder.
- [ ] Text „🙂🙂“ bzw. „!!!“ → „Übernehmen“: orange „Piper hat keinen Ton erzeugt. Steht im Text etwas Sprechbares?“, Ansage unverändert. Text mit 3 000 Zeichen → nach wenigen Sekunden fertig, keine Zeitüberschreitung.
- [ ] Piper fehlt: Debug-App beenden, `chmod -x "<Debug-App>/Contents/Helpers/piper/piper"`, Debug-App starten, „Anhören“ → orange „Die Sprachausgabe (Piper) fehlt im App-Paket. Installiere die App neu.“, kein Absturz, keine macOS-Stimme; danach `chmod +x` zurück (oder neu bauen).
- [ ] Konfiguration exportieren → `grep -c "piper:" export.json` → 0 (Stimmen und Ton-Speicher nicht im Export).
- [ ] Hilfe › Über: Absatz zu Piper/espeak-ng/onnxruntime; Lizenztext enthält „Camera Popup – Sprachausgabe (Piper)“ mit Quellcode-Adressen und den Stimmen; „Hinweise zu onnxruntime öffnen …“ öffnet die Textdatei. „Was ist neu“ 2.0.0 nennt Piper statt Anna.
- [ ] Intel-Mac oder Rosetta (`arch -x86_64 "<App>/Contents/Helpers/piper/piper" --help`): läuft; auf einem Intel-Mac „Übernehmen“ mit Thorsten → Ton (nur wenn ein Intel-Mac verfügbar ist, sonst „nicht prüfbar“ notieren).
- [ ] Nur wenn ohnehin ein Release ansteht (`build-release.sh` führt der Nutzer aus): fertige ZIP auf einem zweiten Mac per Safari laden, öffnen, freigeben → „Übernehmen“ mit Thorsten funktioniert (Quarantäne der App stört Piper nicht); `build-release.sh`-Ausgabe zeigt `check-app: Piper ok` und `piper-smoke: ok`.
- [ ] Danach: `defaults import com.snackbits.UniFiCameraPopup ~/ucp-backup-phase6.plist` nur, falls etwas kaputt ging.
```

- [ ] **Step 6: Commit**

```bash
git add UniFiCameraPopup/Debug/SnapshotRenderer.swift UniFiCameraPopup/Views/HelpView.swift UniFiCameraPopup/Services/WhatsNewService.swift \
  docs/design/einstellungen-ton.md docs/superpowers/manual-checks-2.0.0.md
git diff --cached --name-only | grep AppConfig   # → leer
git commit -m "docs: Piper voices in help, What's New, design doc, renderer states and manual checks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short   # → nur " M UniFiCameraPopup/AppConfig.swift"
```

---

## Spezifikations-Abdeckung (Selbstprüfung)

| Spezifikation | Task |
|---|---|
| 1 Engine eigenständig, Bibliotheken + espeak-ng-data, universal, 13.0, gepinnt, Build-Skript wie wgtunnel, nur `Process` | 1, 3 (`PiperRunner`), 4 |
| 2 alle deutschen Stimmen aus `voices.json`, Thorsten mittel mitgeliefert, Download mit Fortschritt/Größe/Prüfsumme/Application Support/„Entfernen“, Lizenz je Stimme, NC nicht angeboten | 2 (Katalog, Filter), 3 (Prüfsumme), 6 (Laden/Entfernen/UI) |
| 3 Anna/`AVSpeechSynthesizer`/`VoiceChoice` weg, alte Ansagen spielen, „macOS (alt) …“, „Übernehmen“ erzeugt neu, neue Ansagen Thorsten | 2 (`AnnouncementVoice`), 6 |
| 4 Stimmenfeld aktiv, „Name · Qualität“/Sprecher, „geladen“/Größe, „Anhören“ | 2 (Menütexte), 6 |
| 5 Lautheitsmessung | 6 (`applySpeech` → `loudnessGain`), 3 (Integrationstest Faktor < 1) |
| 6 Fehler/Zeitüberschreitung 20 s, kein Absturz, kein Rückfall, nie Main Thread | 3 (`PiperRunner`, `PiperError`), 6 |
| 7 Lizenztexte, GPL-Hinweis, Quellcode-Angebot, Thorsten-CC0-Hinweis bleibt, `build-release.sh` prüft universal + Lizenztexte | 4 (`check-app.sh`, Release), 5 |
| 8 Export unverändert, Stimmen nicht im Export | 6 (Ton-Speicher/Voices-Ordner, kein Export-Code berührt), 7 (Prüfpunkt) |
| 9 Tests Katalog/Filter, Prüfsumme, Standardstimme, Migration, Aufrufparameter, WAV, Integrationstest | 2, 3 |
| 10 manuelle Prüfpunkte in `manual-checks-2.0.0.md` | 7 |
