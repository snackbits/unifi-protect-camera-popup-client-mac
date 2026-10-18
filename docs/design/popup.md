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
