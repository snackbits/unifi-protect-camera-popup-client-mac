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
- **Stapel**: eine Spalte an der gewählten Seite, beginnt oben (sichtbarer Bereich minus Randabstand), Abstand 10 pt. Was nicht mehr passt, liegt unterhalb des Bildschirms. Es wird nicht geschrumpft und es gibt keine zweite Spalte. Neue Kameras reihen sich unten an. Löst eine offene Kamera erneut aus, startet nur ihr Timer neu.
- **Einschub/Ausschub**: Neue Miniaturen gleiten von außerhalb der Außenkante herein (300 ms, ease-out). Beim Schließen gleiten sie auf demselben Weg hinaus (300 ms, ease-in), danach rücken die übrigen nach (300 ms, ease-in-out). Liegt an der Außenkante ein weiterer Monitor, bleibt die Bewegung auf dem eigenen Bildschirm: Start bzw. Ende an der Bildschirmkante, dazu blendet die Miniatur ein bzw. aus (Deckkraft 0 ↔ 1), damit auf dem Nachbarmonitor nichts erscheint.
- **Hover-Balken** (an der Innenseite, 5 pt Abstand zur Miniatur, 4 pt breit, Radius 2, volle Miniaturhöhe):
  - Ohne Maus ist er unsichtbar. Erst beim Hovern blendet die graue Spur (weiß 18 %) in **50 ms** ein.
  - Gleichzeitig startet die Füllung `#FFD84D` von oben nach unten, linear in 500 ms.
  - Verlässt die Maus die Miniatur vorher, blendet er in 50 ms aus und die Füllung wird zurückgesetzt.
- **Wachsen**: Nach 500 ms Hover skaliert das Popup auf seine echte Größe (`popupSize`). Die obere Außenecke bleibt stehen, rechts wächst es also nach unten links (300 ms, ease-in-out). Die Popups darunter rutschen nach unten. Overlays und Aktionen blenden danach ein (180 ms). Es ist immer nur ein Popup groß.
- **Schneller Klick** auf die Miniatur vor Ablauf der 500 ms schließt sie (Ausschub).
- **Maus verlässt das große Popup**: Es schrumpft sofort zurück zur Miniatur, die Overlays verschwinden sofort. Ausnahme: Solange ein Menü des Popups offen ist oder gesprochen bzw. eine Ansage gesendet wird, bleibt es groß.
- **Stapel steht still während des Hoverns** (Nutzerwunsch 19.10.2026, 19:05): Solange eine Miniatur gehovert wird, also der 500-ms-Balken läuft, bewegt sich der Stapel nicht. Schließt in dieser Zeit ein Popup darüber, gleitet nur dieses hinaus und die Lücke bleibt offen. Die gehoverte Miniatur und alle darunter bleiben stehen, damit die Maus nicht von der Miniatur rutscht.
  Erst wenn das Popup vollständig geöffnet ist, also das Wachsen abgeschlossen ist, wird nachgeholt: Das Popup darf hochrutschen, die übrigen rücken nach.
- **Kein Zuklappen durch Verschieben**: Rutscht das große Popup durch ein Nachrücken unter der Maus weg, schrumpft es nicht sofort. Es gibt eine Schonfrist von 2 s, in der man die Maus wieder darauf bewegen kann. Kommt die Maus zurück, bleibt es groß. Sonst schrumpft es nach Ablauf zurück. Sofortiges Zuklappen gilt nur, wenn der Nutzer die Maus selbst hinausbewegt.
  Dasselbe gilt, wenn ein Popup oberhalb schließt, während das große Popup gehovert wird.
- **Restzeit** (Variante „Beides“):
  - *Linie*: 3 pt hoch, Radius 2, 4 pt unter der Miniatur, so breit wie die Miniatur mal Restanteil. Sie schrumpft zur Außenkante hin. Farbe weiß 75 %, in den letzten 3 s `#FFD84D`. Nur im Miniatur-Zustand sichtbar.
  - *Vorwarnung*: In den letzten 3 s rückt die Miniatur linear bis zu 36 pt zur Außenkante hinaus, die Deckkraft sinkt von 1 auf 0,7. Danach folgt der normale Ausschub.
  - Bei Hover oder im großen Zustand pausiert der Timer. Linie und Vorwarnung springen dann zurück: keine Verschiebung, volle Deckkraft, Linie wieder weiß.
- **Bewegung reduzieren**: Kein Gleiten, Skalieren oder Verschieben, Rahmen werden direkt gesetzt. Hover-Balken und Linie bleiben (Fortschrittsanzeigen), die Vorwarnung wirkt nur über die Deckkraft.
- „Alle aktiven Kameras zeigen“ aus: Es gibt höchstens eine Miniatur, eine neue Kamera ersetzt sie.
- Zuschnitt-Auswahl (Crop) öffnet weiter in voller Größe.
