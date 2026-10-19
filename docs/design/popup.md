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
   „Ansage abspielen“ · „Leertaste halten“ · „Kameraton“ · Buttons des Nutzers. Die ersten drei nur bei
   Protect-Kameras mit Lautsprecher; ohne alles keine Leiste.
   - „Ansage abspielen“: Kreis 34 `pillBtn`, Megafon 16 (Lucide `megaphone`, Strich 1,8) `pillFg`, Tooltip „Ansage abspielen“.
     Während eine Ansage aus diesem Popup läuft: Fläche `accent`, Symbol weiß, Tooltip „Ansage stoppen“, Klick stoppt.
   - „Leertaste halten“: 40 hoch, Innenabstand 0/18, Radius 20, `accent`, 12/700 weiß,
     Mikrofon 16 (Strich 2) + 6 + Text. Texte: Ruhe „Leertaste halten“ (Modus Halten) bzw. „Sprechen“
     (Umschalten); Aufbau „Verbinde …“ (Deckkraft 70 %); senden „Spricht …“ (Halten) bzw. „Beenden“ (Umschalten).
     Maustaste gedrückt halten = sprechen. Die Leertaste wirkt, solange der Zeiger über dem Popup ist.
   - „Kameraton“ (2.5.0, nicht aus der Vorlage): Kreis 34 `pillBtn`, Lautsprecher 16 (Strich 1,8) `pillFg`;
     aus: derselbe Lautsprecher durchgestrichen (`speakerOff`). Tooltip „Kameraton ausschalten“ / „… einschalten“.
     Klick schaltet den Ton des laufenden Livebilds und speichert ihn als „Ton des Livebilds“ der Kamera.
   - Buttons des Nutzers: Kreis 34 `pillBtn`, Symbol 16 (Strich 1,8) `pillFg` (Tür/Lampe/Haus/Blitz), Tooltip = Titel.
5. Ansagen-Menü (offen nach Klick auf „Ansage abspielen“): Unterkante auf der Oberkante der Leiste
   (Vorlage: unten 64), linke Kante 45 vor „Ansage abspielen“ (Vorlage: links 70), mindestens 10 vom Rand.
   Breite 180 + 2×5, Radius 9, `menu`, Schatten 0 10 24 rgba(0,0,0,.4), Ring 1 `mainBorder`, Schrift 12 `fg`:
   je Ansage eine Zeile, Innenabstand 5/8, Radius 5: Name links, rechts Art 10 `muted`
   („MP3“ / „KI-Stimme“), Abstand 8; danach Trennlinie 1 `mainBorder`, Rand 3/4; „MP3 hinzufügen …“
   `accText`, Innenabstand 5/8. Zeile unter der Maus `accent` + weiß. Klick spielt an der Kamera ab.
6. Hinweis bei Fehlern: Kapsel `overlay`, Innenabstand 4/9, 11/600 weiß, mittig 8 über der Leiste,
   höchstens Popup-Breite − 20 (gekürzt, voller Text als Tooltip), 6 s sichtbar, Klicks gehen durch.
7. Ein Klick neben ein offenes Menü schließt erst das Menü. Während gesprochen oder eine Ansage
   gesendet wird, schließt sich das Popup nicht automatisch.

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
