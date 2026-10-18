# Spezifikation Phase 5: Nutzer-Feedback zu 1.2.0 (Build-Test)

Stand 2026-10-18. Baut auf Phasen 1–4 auf (Branch `feature/protect-integration`, Spezifikation
`2026-10-18-phases-2-4.md`, deren Querschnitt-Regeln weiter gelten: Deutsch mit „…“, Schlüssel nur im
Schlüsselbund, `AppConfig.swift` nie committen/zurücksetzen, Version 1.2.0 bleibt, WhatsNew-1.2.0-Eintrag
ergänzen). Alle Punkte stammen vom Nutzer nach einem Test der laufenden App; wo die Vorlage etwas anderes
zeigt, gilt hier der Nutzerwunsch (bewusste Abweichung, im Plan benennen).

## 1. Popup: Name/Zeit-Einblendung standardmäßig aus
Die App-eigene Einblendung oben links („Haustür (unten) · 19:58“) doppelt die Kamera-eigene OSD.
Standard: **ausgeblendet**. Pro Kamera unter „Erweitert“ ein Schalter **„Name und Zeit einblenden“**
(aus). Bestehende Kameras bekommen ebenfalls „aus“.

## 2. Menüleisten-Panel: Version und Update
Im Panel fehlt ein Versionshinweis. Unten (über/bei „Einstellungen …“) eine dezente Zeile
„Version 1.2.0 (27)“; ist laut `UpdateService` ein Update verfügbar, zusätzlich ein Button
**„Update auf <Version> installieren“** (bzw. die bestehende Update-Aktion des alten Menüs).
Ohne Update: Eintrag „Nach Updates suchen“ wie im alten Menü, falls vorhanden.

## 3. Standardgröße des Popups
Standardhöhe einer Kamera ≈ **42 %** der sichtbaren Bildschirmhöhe (`visibleFrame`), Breite aus dem
Seitenverhältnis (16:9 bzw. Kamera), sodass zwei Kameras untereinander passen. In den Einstellungen
(Kamera › Größe) gilt: leere Felder = automatisch; Platzhalter zeigt den berechneten Wert. Ein vom
Nutzer eingetragener Wert gilt weiter. Der bisherige Standard 480×270 zählt als „nie geändert“ → automatisch.

## 4. Mehr Popups als Platz
Öffnen sich mehr Popups, als auf den Bildschirm passen, **verkleinern sich alle** gleichmäßig, sodass
immer alle vollständig sichtbar sind (Seitenverhältnis bleibt, Stapel an der eingestellten Position).
Schließt ein Popup, wachsen die übrigen **schrittweise** auf ihre eingestellte Größe zurück, maximal so
weit, wie Platz ist. Größenwechsel **animiert, 300 ms**, ease-in-out (`NSAnimationContext`,
`setFrame(_:display:animate:)` bzw. Animator). Reduzierte Bewegung (Bedienungshilfen) → ohne Animation.
Untergrenze: 160 pt Höhe; reicht selbst das nicht, in eine zweite Spalte daneben ausweichen.
Die Layout-Berechnung ist reine Logik in `AppCore` und getestet.

## 5. „Kamera entfernen“
Als roter Link **„Kamera entfernen“** (ohne „…“) immer sichtbar, auch bei eingeklapptem „Erweitert“.
Die Rückfrage vor dem Entfernen bleibt.

## 6. „Ton des Livebilds“
Der Schalter gehört in die Karte mit „Tastenkürzel / Hinweiston beim Öffnen / Zoom und Ausschnitt
merken“ (nicht mehr unter „Erweitert“).

## 7. Stimme
Nur **Anna** anbieten: Stimmen-Auswahl deaktiviert, zeigt „Anna · macOS“. Ist Anna nicht installiert,
die beste deutsche Stimme verwenden und das anzeigen. Bestehende Ansagen mit anderer Stimme werden beim
nächsten Rendern mit Anna erzeugt.

## 8. Glocken-Symbol im Popup
Das Stumm-Symbol (`bellSlash`) wirkt kaputt (offene Glocke). Durch ein vollständiges „Glocke durchgestrichen“
ersetzen (Lucide `bell-off`, 24er-Raster, Strich 2, runde Enden) und dem Knopf einen Tooltip
„Diese Kamera stummschalten“ geben. Gilt für alle Stellen, die `bellSlash` nutzen.

## 9. Sprechen nur per gedrücktem Button
Popups haben keinen Fokus und sollen keinen bekommen; Leertaste und „Umschalten“ entfallen.
- Einstellung „Sprechen: Leertaste halten / Umschalten“ entfernen, `PushToTalkKey` entfernen,
  gespeicherter Wert wird ignoriert.
- Sprech-Button **zweizeilig**: große Zeile je Zustand „Sprechen“ → „Verbinde …“ → „Loslassen zum
  Beenden“; kleine Zeile darunter, dauerhaft: **„Gedrückt halten zum Sprechen“**.
- Sprechen nur, solange die Maustaste auf dem Button gehalten wird; Loslassen (auch außerhalb) beendet.

## 10. Lautstärke
Problem: MP3/Stimme sind deutlich lauter als das Mikrofon. Die Kamera-Lautsprecherlautstärke ist über
die Integration API nicht sicher einstellbar → Ausgleich in der App:
- Ansagen beim Erzeugen/Import auf einheitliche Lautheit normalisieren (Ziel −20 dBFS RMS, Spitze ≤ −1 dBFS).
- Mikrofon: automatische Verstärkung zum selben Ziel (max. +18 dB, schnelle Spitzenbegrenzung).
- Reiter „Ton“: zwei Regler **„Lautstärke Sprechen“** und **„Lautstärke Ansagen“** statt einem
  (alter Wert geht in beide über).
Prüft der Plan eine echte API für die Kamera-Lautstärke (Integration API `PATCH /v1/cameras/{id}`),
darf er sie zusätzlich nur nutzen, wenn sie in der Referenz/Doku belegt ist.

## 11. Buttons können Töne abspielen
Button-Dialog: neues Feld **„Ton“** (Kein Ton / Ansagen aus dem Reiter „Ton“). Ein Button kann
Webhook, Ton oder beides auslösen; „Adresse“ ist nur noch Pflicht, wenn kein Ton gewählt ist. Ton
läuft über Talkback an die Kamera des Popups; Buttons mit Ton nur bei Kameras mit Lautsprecher anzeigen
(Webhook-Teil bleibt sonst sichtbar). Reihenfolge bei beidem: parallel.

## 12. Neue Kategorie „Ereignisse“
Pro Kamera (Reiter „Kameras“, eigener Abschnitt wie „Buttons“) Regeln:
- **Ereignis:** Klingeln, Bewegung, Person, Fahrzeug, Tier, Paket (was ProtectKit an Ereignis-Arten liefert).
- **Aktion:** Webhook (Methode/Adresse/Token wie Buttons, Token im Schlüsselbund) und/oder Ton.
- **Verzögerung** in Sekunden (0–600, Standard 0).
Regeln laufen unabhängig vom Popup und von Stummschaltungen (Stumm betrifft nur Popups am Mac).
Gleiche Regel wird pro Ereignis höchstens einmal ausgelöst (Entprellung pro Kamera+Regel: 30 s).
Ausführung über dieselben Wege wie Buttons (Webhook-Routing zu Hause/unterwegs aus Phase 4, Ton über
Talkback). Eine Rückfrage („Vor dem Ausführen nachfragen“) gibt es bei Ereignissen nicht. Ereignisse
landen im Event-Log. Regeln sind Teil des Konfigurations-Exports (ohne Token). Nur in der Einstellungs-UI,
keine Anzeige im Popup.

## Querschnitt
- Neue Einstellungen unter `settingsExtensionsV2` (nicht vom alten Build überschreibbar).
- Reine Logik (Layout, Normalisierung/Gain, Ereignis-Regeln/Entprellung, Größen-Default) in `AppCore`
  mit Tests; UI nach bestehenden Design-Komponenten.
- Manuelle Prüfpunkte in `docs/superpowers/manual-checks-1.2.0.md` ergänzen.
