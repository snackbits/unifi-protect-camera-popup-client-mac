# Einstellungen › Erscheinungsbild (seit 3.0.0, Vorlage: Mock „Vorschlag A · Desktop-Szene“)

Grundlage: `popup-miniatur.md` (Verhalten der Layouts) und `mockups/einstellungen-erscheinungsbild.html`
(Reiter-Mock, verbindlich ist Vorschlag A). Code: `Views/Settings/AppearanceTab.swift`,
Grafik `Views/Settings/PopupLayoutPreview.swift`.

Kopf wie Allgemein, Titel „Erscheinungsbild“, Reiter „Erscheinungsbild“ (Symbol `tabAppearance`:
Bildschirmrahmen mit zwei kleinen Popups am rechten Rand) aktiv, zweiter Reiter nach „Allgemein“.
Inhalt Innenabstand 22 oben/unten, 40 links/rechts, Abstand 16, Schrift 13. Scrollt bei Bedarf.
Jeder Abschnitt (Abstand 6): Überschrift 11/600 `muted`, darunter Karte (Radius 10, `group`,
Rand 1 `border`, Trennlinie 1 `border`).

1. **Popup-Layout**: Karte, Innenabstand 14, zwei Optionen gleich breit nebeneinander, Abstand 14.
   Die ganze Option ist ein Button (Bedienungshilfen: „Popup-Layout Miniatur“ bzw. „… Voll“,
   Beschreibung als Hinweis, ausgewählt = `isSelected`).
   - Grafik 16:10, Radius 8; Ring außerhalb der Grafik: ausgewählt 2,5 `accent`, sonst 1 `border`
     (Wechsel 150 ms ease-out).
   - Darunter (Abstand 8) Radio 15 (aus: Rand 1,5 `chipBorder`; an: Rand 4,5 `accent`, oben 1
     versetzt) + 8 + Text senkrecht: Name 13/600, Beschreibung 11 `muted`, mehrzeilig.
     - „Miniatur“ · „Kleine Vorschau am Bildschirmrand, wird groß, wenn die Maus darauf bleibt.“
     - „Voll“ · „Popups öffnen sofort in ihrer vollen Größe.“
   - Grafik: Desktop-Szene mit festen Farben (Verlauf, Menüleiste, Hintergrundfenster, Dock),
     Geometrie und Keyframes aus dem Mock, Zyklus 7 s, beide Grafiken laufen im Gleichtakt.
     - Miniatur: drei Miniaturen gleiten herein, der Zeiger bleibt auf der zweiten stehen, der
       Hover-Balken blendet ein und füllt sich (`#FFD84D`), die Miniatur wächst mit Overlays, die
       dritte rutscht nach unten; zurück, alle gleiten hinaus. Kein Klick.
     - Voll: zwei volle Popups blenden ein (Skalierung 0,94 → 1 von der äußeren oberen Ecke) und aus.
   - **Seite folgt „Popup-Position“** (live): Bei „Links“ sind in beiden Grafiken Popups, Zeiger
     und Hover-Balken gespiegelt (Popups am linken Rand, Balken an ihrer rechten Innenseite,
     Einschub von links). Menüleiste, Hintergrundfenster und Dock bleiben unverändert, ebenso
     die Bildinhalte der Popups und die Form des Zeigers.
   - „Bewegung reduzieren“: Standbild, Miniatur bei 55 % (zweite Miniatur groß mit Overlays),
     Voll bei 50 % (beide Popups sichtbar).
2. **Darstellung**: „Farbschema“ | Segment „System“ · „Hell“ · „Dunkel“ (Segment wie bisher in
   Allgemein: Fläche `segBg`, Radius 7, Innenabstand 2, Schrift 12; Segment 3/12; aktiv Radius 5,
   `segOn`, Schatten `segShadow` 0 1 2, 600; inaktiv `muted`).
3. **Popup**, Zeilen Innenabstand 10/14:
   - „Popup-Position“, Untertitel 11 `muted` „Bildschirmseite für Miniaturen und volle Popups.
     Der Stapel beginnt oben.“ | Auswahlfeld „Links“ / „Rechts“ (Standard).
   - „Bildschirm“ | Auswahlfeld „Hauptbildschirm“ / „Bildschirm mit Maus“.
   - „Randabstand“ | Regler 0…120, Schritt 1 | „NN px“.
   - „Automatisch schließen“ | Regler 0…300, Schritt 5 | „NN s“, bei 0 „Aus“.
     Reglerzeilen: Titel 170 breit, Regler klein `accent`, Wert 12 tabellarisch `muted`, 52 breit rechtsbündig.
   - „Alle aktiven Kameras zeigen“, Untertitel „Jede auslösende Kamera bekommt ein eigenes Popup,
     untereinander gestapelt. Ohne diese Option ersetzt eine neue Kamera das aktuelle Popup.“ | Schalter.
   Auswahlfeld: 12, Innenabstand 3/10, Radius 6, Rand 1 `chipBorder`, Fläche `field`, Doppelpfeil 9.

## Herkunft der Zeilen
„Farbschema“ hieß in Allgemein „Erscheinungsbild“. „Popup-Position“ stand in Allgemein,
Bildschirm bis „Alle aktiven Kameras zeigen“ in „Allgemein › Erweitert › Popup“. Alte Positionen
(Oben/Mitte/Unten × Links/Rechts) werden beim Laden auf Links bzw. Rechts abgebildet
(`popup-miniatur.md`, Einstellungen).
