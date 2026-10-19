# Einstellungen › Allgemein (Vorlage S1)

Fenster 760 × 540, Fläche `win`. Kopf (`bar`, Rand unten 1 `border`): Titelleiste 28 hoch,
Titel „Allgemein“ 13/600 mittig (nativ); darunter Reiterleiste.

## Reiterleiste (alle Reiter gleich)
Zentriert, Abstand 4, Innenabstand oben 2 unten 8. Reiter-Button mindestens 78 breit (längere
Namen: Innenabstand 10 links/rechts), Innenabstand 5 oben/unten, Radius 7, senkrecht Symbol 20 + 3 + Text 11.
Reihenfolge/Texte/Symbole: Allgemein (tabGeneral) · Erscheinungsbild (tabAppearance, seit 3.0.0) ·
Kameras (tabCameras) · Ton (tabSound) · Unterwegs (tabRemote). Aktiv: Fläche `tabOn`, Farbe `accText`;
sonst transparent, `muted`.
Fenstertitel je Reiter: „Allgemein“, „Erscheinungsbild“, „Kameras“, „Ton & Sprechen“, „Unterwegs“.

## Inhalt
Innenabstand 22 oben/unten, 40 links/rechts; Abstand 16; Schrift 13. Scrollt bei Bedarf.

1. Karte (Radius 10, `group`, Rand 1 `border`), Zeilen Innenabstand 11/14, Abstand 10,
   Trennlinie 1 `border`:
   - „Konsole“ | Punkt 8 #34C759 + 6 + „UDM Pro · 192.168.1.1“ (`muted`) | Button „Ändern …“
   - „API-Schlüssel“ | „im Schlüsselbund“ (`muted`) | Button „Ersetzen …“
   Feld-Button: 12, Innenabstand 3/10, Radius 6, Rand 1 `chipBorder`, Fläche `field`, Text `fg`.
2. Karte, Zeilen Innenabstand 10/14:
   - „Im Fokus-Modus keine Popups“ | Schalter an
   - „Bei Anmeldung starten“ | Schalter an
   Schalter: 32 × 19, Radius 10, an `accent` (Knopf rechts), aus `toggleOff` (Knopf links);
   Knopf 15, weiß, 2 vom Rand.
3. Abschnitt (Abstand 6): Überschrift „Stummschalten (Menüleiste)“ 11/600 `muted`; Karte,
   Zeilen Innenabstand 9/14:
   - „Kurz“ | Dauer-Feld „15“ + „Minuten“
   - „Lang“ | Dauer-Feld „1“ + „Stunden“
   Dauer-Feld: Rahmen Radius 6, Rand 1 `chipBorder`, Fläche `field`, Schrift 12; Eingabe 34
   breit, Innenabstand 3/6, rechtsbündig, tabellarisch; Trenner 1 `chipBorder`; Einheit
   Innenabstand 3/8, Abstand 5, Text + Doppelpfeil 9. Einheitentext immer Plural.
4. Zeile, Abstand 8: links Aufklapper „Erweitert“, rechtsbündig „Konfiguration exportieren …“ ·
   „Importieren …“ (Feld-Button, Innenabstand 4/12).
5. „Erweitert“ (aufgeklappt): Abschnitte „Updates“, „Webhooks (Relay-Server)“ (nur solange eine
   Kamera per Webhook auslöst) und „Hilfe“.

## Umgezogen nach „Erscheinungsbild“ (3.0.0)
Die Zeilen „Erscheinungsbild“ (jetzt „Farbschema“), „Popup-Position“ und der frühere Bereich
„Erweitert › Popup“ (Bildschirm, Randabstand, Automatisch schließen, Alle aktiven Kameras zeigen)
stehen nicht mehr in Allgemein, siehe `einstellungen-erscheinungsbild.md`. Export und Import
bleiben hier.
