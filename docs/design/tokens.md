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
