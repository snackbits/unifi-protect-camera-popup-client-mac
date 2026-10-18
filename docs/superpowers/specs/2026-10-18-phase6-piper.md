# Spezifikation Phase 6: Piper-Stimmen statt macOS-Stimme

Stand 2026-10-18. Baut auf Phase 5 auf (Branch `feature/protect-integration`). Querschnitt-Regeln aus
`2026-10-18-phases-2-4.md` gelten weiter (Deutsch mit „…“, `AppConfig.swift` nie anfassen, Version 1.2.0,
WhatsNew-1.2.0-Eintrag ergänzen, App nie normal starten, `build-release.sh` nie ausführen).

## Nutzerwunsch
„Bau die Piper-Stimme ein. Entferne Anna und stelle alle Piper-Stimmen zur Verfügung. Pass auch den Text
für die Lizenz an.“ Vorher geklärt: Nutzer installieren weiterhin **eine** App; Piper liegt als eigenes
Programm **im App-Paket** und wird per `Process` aufgerufen (kein Linken → GPL bleibt bei Piper/espeak-ng).

## Verbindliche Entscheidungen (Controller)
1. **Engine:** Piper als eigenständige ausführbare Datei samt Bibliotheken (onnxruntime, espeak-ng,
   piper-phonemize) und `espeak-ng-data` unter `Contents/Resources/piper/` (oder `Contents/Helpers/`),
   **universal (arm64 + x86_64)**, macOS 13.0. Quelle und genaue Version wählt der Plan (z. B. die
   letzten offiziellen `rhasspy/piper`-Release-Binärdateien für macOS oder ein reproduzierbarer Build) –
   gepinnt mit SHA-256, Build-Skript im Repo wie bei `wgtunnel/` (Toolchain/Download geprüft, nicht im
   Git, falls groß). Die App ruft Piper nur über `Process` auf (stdin Text, Ausgabe WAV/raw in Datei oder
   stdout), nie durch Linken.
2. **„Alle Piper-Stimmen“ = alle deutschen Piper-Stimmen** (`de_DE`, ggf. `de_AT`/`de_CH`, falls vorhanden)
   aus `rhasspy/piper-voices`, jeweils mit allen Qualitätsstufen bzw. Sprechern (z. B. thorsten
   low/medium/high, thorsten_emotional mit Sprechern, eva_k, karlsson, kerstin, mls, pavoque, ramona …
   – die tatsächliche Liste stellt der Plan aus `voices.json` fest).
   - **Mitgeliefert:** genau eine Stimme, **Thorsten (medium)**, damit Ansagen ohne Internet gehen.
   - **Alle anderen:** im Reiter „Ton“ auswählbar, beim ersten Gebrauch **herunterladen** (Hugging Face,
     feste Revision/Commit-URL), mit Fortschritt, Größe vorher anzeigen, Prüfsumme aus einer in der App
     gepinnten Liste prüfen, Ablage unter Application Support; „Entfernen“ für heruntergeladene Stimmen.
   - **Lizenz pro Stimme:** jede Stimme mit ihrer Lizenz aus der Model Card anzeigen. Stimmen, deren
     Lizenz kommerzielle Nutzung oder Weitergabe ausschließt (z. B. „NC“), werden **nicht angeboten**;
     der Plan listet, welche das sind.
3. **Anna/macOS-Stimmen entfernen:** `AVSpeechSynthesizer`-Pfad, `VoiceChoice`, „Anna · macOS“, Hinweis
   „Anna fehlt“ entfallen. Bestehende Sprach-Ansagen behalten ihre Audiodatei und spielen weiter; ihr
   Stimmenfeld zeigt „macOS (alt) – mit „Übernehmen“ neu erzeugen“ o. ä.; „Übernehmen“ erzeugt sie neu
   mit der gewählten Piper-Stimme. Neue Ansagen: Standard Thorsten (medium).
4. **Stimmenfeld:** wieder aktiv (Phase-5-Sperre entfällt): Liste aller angebotenen Stimmen,
   „Name · Qualität“ (bzw. Sprecher), Marke „geladen“ / Größe zum Herunterladen. „Anhören“ spricht
   einen kurzen Beispielsatz mit der gewählten Stimme.
5. **Lautheit:** erzeugte Piper-Audios laufen durch dieselbe Lautheitsmessung wie in Phase 5.
6. **Fehler:** Piper fehlt/stürzt ab/Zeitüberschreitung (z. B. 20 s) → klare Meldung im Reiter „Ton“,
   kein Absturz, kein Rückfall auf macOS-Stimmen. Erzeugen läuft nie auf dem Main Thread.
7. **Lizenztexte:** `ThirdPartyNotices.txt` und „Über“ ergänzen: Piper (Lizenz der verwendeten Version,
   MIT bzw. GPL-3.0), espeak-ng (GPL-3.0-or-later), onnxruntime (MIT), piper-phonemize, jede angebotene
   Stimme (Lizenz + Quelle). GPL-Hinweis: Piper/espeak-ng sind eigenständige Programme im App-Paket, die
   App selbst ist nicht GPL; Quellcode-Angebot mit genauen Upstream-URLs + Versionen (bzw. Tags/Commits).
   Hinweis zu Thorsten-Aufnahmen (CC0) bleibt. `build-release.sh` prüft, dass Piper universal und die
   Lizenztexte vorhanden sind (wie heute für ThirdPartyNotices/lipo).
8. **Export/Import:** Stimmenwahl einer Ansage bleibt im Ton-Speicher (nicht im Export, wie bisher).
   Heruntergeladene Stimmen sind nicht im Export.
9. **Tests:** reine Logik in AppCore (Stimmenkatalog/Filter nach Lizenz, Prüfsummen-Check, Auswahl der
   Standardstimme, Migration alter Ansagen, Piper-Aufrufparameter, WAV-Parsing) mit XCTest. Ein
   Integrationstest, der das gebündelte Piper mit Thorsten (medium) einen Satz erzeugen lässt (darf beim
   Build im Debug laufen, nicht beim normalen App-Start).
10. **Manuelle Prüfpunkte** in `docs/superpowers/manual-checks-1.2.0.md` ergänzen.
