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
