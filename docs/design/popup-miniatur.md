# Popup-Layout „Miniatur“ und Reiter „Erscheinungsbild“ (3.0.0)

Abgestimmt mit dem Nutzer am 19.10.2026 anhand zweier HTML-Mockups, die verbindlich sind:
- `mockups/popup-miniatur-demo.html`: Ablauf und Animationen der Popups (im Browser öffnen, „Ablauf abspielen“, „Zeitlupe ×4“)
- `mockups/einstellungen-erscheinungsbild.html`: Reiter-Mock. Gewählt ist Grafikvorschlag **A · Desktop-Szene**, die anderen entfallen.

Maße sind in Punkten angegeben (Mock-Bühne 1440 × 900 pt).

## Einstellungen
- `PopupLayoutMode`: `.miniature` („Miniatur“, Standard, auch für bestehende Nutzer) / `.full` („Voll“ = bisheriges Verhalten).
- `PopupPosition` kennt nur noch `.left` („Links“) / `.right` („Rechts“, Standard). Sie gilt für beide Layouts, der Stapel beginnt immer oben.
  Migration beim Decode: Rohwerte `topLeft`, `middleLeft`, `bottomLeft` → `.left`, alle anderen → `.right`.
  Das gilt für `defaultPosition` und für `WebhookMapping.positionOverride`.
- „Voll“ behält `PopupStackLayout.frames` (schrumpfen, Spalten) mit Anker oben links bzw. oben rechts.

## Reiter „Erscheinungsbild“ (neu, rechts neben „Allgemein“)
Reihenfolge der Abschnitte:
1. **Popup-Layout**: Karte mit zwei Optionen nebeneinander, je eine animierte Grafik (16:10, Radius 8) und darunter Radio, Name und Beschreibung.
   - Miniatur: „Kleine Vorschau am Bildschirmrand, wird groß, wenn die Maus darauf bleibt.“
   - Voll: „Popups öffnen sofort in ihrer vollen Größe.“
   - Ausgewählt: Ring 2,5 pt `accent`. Nicht ausgewählt: Ring 1 pt `border`.
   - Die Grafik folgt Vorschlag A (Farben, Geometrie und Keyframes aus dem Mock, Zyklus 7 s). Das Popup wird durch **Darüberfahren** groß, nicht durch Klick: Der Zeiger bleibt stehen, der Hover-Balken blendet ein und füllt sich, dann wächst das Popup.
   - Bei „Bewegung reduzieren“ steht die Grafik still und zeigt das vergrößerte Popup.
2. **Darstellung**: „Farbschema“ (bisher „Erscheinungsbild“: System/Hell/Dunkel).
3. **Popup**: Popup-Position (Links/Rechts, Untertitel „Bildschirmseite für Miniaturen und volle Popups. Der Stapel beginnt oben.“), Bildschirm, Randabstand, Automatisch schließen, Alle aktiven Kameras zeigen.
   Diese Zeilen ziehen aus „Allgemein“ (auch aus „Erweitert“) hierher um. Export und Import bleiben in Allgemein.

## Verhalten im Layout „Miniatur“
- **Miniatur**: 200 pt breit, Höhe aus dem Seitenverhältnis der Popup-Größe der Kamera. Reines Video ohne Overlays: kein Chip, keine Knöpfe, keine Leiste, keine Hinweise.
- **Stapel**: eine Spalte an der gewählten Seite, beginnt oben (sichtbarer Bereich minus Randabstand), Abstand 20 pt, auch zwischen dem großen Popup und den Miniaturen (Nutzerwunsch 19.10.2026, 20:49; die Restzeit-Linie liegt in diesem Abstand). Die Außenkante liegt genau den Randabstand vom Rand des sichtbaren Bereichs entfernt, die Oberkante genau den Randabstand unter seiner Oberkante (Nutzerwunsch 19.10.2026, 20:49: Die ausgeblendeten Overlays dürfen das Fenster nicht vergrößern). Was nicht mehr passt, liegt unterhalb des Bildschirms. Es wird nicht geschrumpft und es gibt keine zweite Spalte. Neue Kameras reihen sich unten an. Löst eine offene Kamera erneut aus, startet nur ihr Timer neu.
- **Einschub/Ausschub** (Nutzerwunsch 19.10.2026, 20:49): Das Fenster steht sofort an seinem Platz (beim Ausschub bleibt es stehen). Nur der Inhalt (Video bzw. Standbild mit Hintergrund und Rand) gleitet im Fenster von außerhalb der Außenkante herein (300 ms, ease-out) bzw. hinaus (300 ms, ease-in) und wird an der abgerundeten Fensterkante abgeschnitten. So erscheint auf einem Nachbarmonitor nichts, und es wird nichts ein- oder ausgeblendet. Danach rücken die übrigen nach (300 ms, ease-in-out). Die Restzeit-Linie erscheint erst nach dem Einschub und verschwindet mit Beginn des Ausschubs; der Hover-Balken ist dabei ohnehin unsichtbar. Der Fensterschatten fehlt während des Gleitens.
- **Hover-Balken** (an der Innenseite, 5 pt Abstand zur Miniatur, 4 pt breit, Radius 2, volle Miniaturhöhe):
  - Ohne Maus ist er unsichtbar. Erst beim Hovern blendet die graue Spur (weiß 18 %) in **50 ms** ein.
  - Gleichzeitig startet die Füllung `#FFD84D` von oben nach unten, linear in 500 ms.
  - Verlässt die Maus die Miniatur vorher, blendet er in 50 ms aus und die Füllung wird zurückgesetzt.
- **Wachsen**: Nach 500 ms Hover skaliert das Popup auf seine echte Größe (`popupSize`). Die obere Außenecke bleibt stehen, rechts wächst es also nach unten links (300 ms, ease-in-out). Die Popups darunter rutschen nach unten. Overlays und Aktionen blenden danach ein (180 ms). Es ist immer nur ein Popup groß.
- **Ausweichen nach oben** (Nutzerwunsch 19.10.2026): Würde das große Popup an der Oberkante seiner Miniatur unter den sichtbaren Bereich ragen (`visible.minY` + Randabstand), rückt es so weit nach oben, dass es ganz sichtbar ist: Unterkante bei `visible.minY` + Randabstand, höchstens bis zur Oberkante des Stapels. Wachsen und Hochrücken sind eine gemeinsame Bewegung (300 ms, ease-in-out). Es überdeckt dabei keine anderen Miniaturen:
  - Miniaturen davor, die vollständig oberhalb seiner neuen Oberkante passen, bleiben in ihrer Reihenfolge stehen.
  - Die übrigen davor folgen in ihrer Reihenfolge direkt unter dem großen Popup (Abstand 20 pt), danach die Miniaturen, die ohnehin danach kamen. Sie dürfen unter den Bildschirm hinausragen.
  - Beim Zurückschrumpfen gilt wieder die ursprüngliche Stapelreihenfolge.
  - Rutscht das Popup dabei unter der Maus weg, gilt die Schonfrist von 2 s (siehe unten). Ausgewichen wird erst ab dem Wachsen; solange der Hover-Balken läuft, steht der Stapel still.
- **Klick** (Nutzerwunsch 19.10.2026):
  - Auf die Miniatur vor Ablauf der 500 ms schließt er sie (Ausschub).
  - Während das Popup wächst, bewirkt ein Klick nichts.
  - Ist das Popup ganz offen, schließt ein Klick aufs Video wie im Layout „Voll“ (nicht bei Zoom; ein offenes Menü schließt zuerst nur das Menü). Knöpfe und Menüs schließen das Popup nicht.
- **Maus verlässt das große Popup**: Es schrumpft sofort zurück zur Miniatur, die Overlays verschwinden sofort. Ausnahme: Solange ein Menü des Popups offen ist oder gesprochen bzw. eine Ansage gesendet wird, bleibt es groß.
- **Stapel steht still während des Hoverns** (Nutzerwunsch 19.10.2026, 19:05): Solange eine Miniatur gehovert wird, also der 500-ms-Balken läuft, bewegt sich der Stapel nicht. Schließt in dieser Zeit ein Popup darüber, gleitet nur dieses hinaus und die Lücke bleibt offen. Die gehoverte Miniatur und alle darunter bleiben stehen, damit die Maus nicht von der Miniatur rutscht.
  Erst wenn das Popup vollständig geöffnet ist, also das Wachsen abgeschlossen ist, wird nachgeholt: Das Popup darf hochrutschen, die übrigen rücken nach.
- **Kein Zuklappen durch Verschieben**: Rutscht das große Popup durch ein Nachrücken unter der Maus weg, schrumpft es nicht sofort. Es gibt eine Schonfrist von 2 s, in der man die Maus wieder darauf bewegen kann. Kommt die Maus zurück, bleibt es groß. Sonst schrumpft es nach Ablauf zurück. Sofortiges Zuklappen gilt nur, wenn der Nutzer die Maus selbst hinausbewegt.
  Dasselbe gilt, wenn ein Popup oberhalb schließt, während das große Popup gehovert wird.
- **Restzeit** (nur die Linie, Nutzerwunsch 19.10.2026, 20:49):
  - *Linie*: 3 pt hoch, Radius 2, 4 pt unter der Miniatur, so breit wie die Miniatur mal Restanteil. Sie schrumpft zur Außenkante hin. Farbe weiß 75 %, in den letzten 3 s `#FFD84D`. Nur im Miniatur-Zustand sichtbar.
  - *Keine Vorwarnung* (Nutzerwunsch 19.10.2026, 20:49): Die Miniatur steht still, bis die Linie abgelaufen ist; sie rückt nicht nach außen und ändert ihre Deckkraft nicht. Danach gleitet sie vollständig hinaus (Ausschub).
  - Bei Hover oder im großen Zustand pausiert der Timer. Die Linie wird dann wieder weiß.
- **Bewegung reduzieren**: Kein Gleiten, Skalieren oder Verschieben, Rahmen werden direkt gesetzt. Hover-Balken und Linie bleiben (Fortschrittsanzeigen).
- „Alle aktiven Kameras zeigen“ aus: Es gibt höchstens eine Miniatur, eine neue Kamera ersetzt sie.
- Zuschnitt-Auswahl (Crop) öffnet weiter in voller Größe.
