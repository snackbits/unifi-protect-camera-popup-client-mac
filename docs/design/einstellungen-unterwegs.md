# Einstellungen › Unterwegs (Vorlage S6)

Kopf wie Allgemein, Titel „Unterwegs“, Reiter „Unterwegs“ aktiv.
Inhalt Innenabstand 20/40, Abstand 14, Schrift 13, Text `fg`.
1. Statusfläche: Abstand 14, Innenabstand 14/16, Radius 12, `accSoft`. Kreis 40 `accent` mit
   Schild-Häkchen 20 (Strich 1,8) weiß · Text senkrecht Abstand 2: Titel 14/700, Untertitel 12 `muted`
   · Feld-Button „Jetzt testen“ (12, 4/12). Während des Tests „Teste …“, deaktiviert (Abw. 7).
   Texte je Zustand (Abw. 2):
   - zu Hause: „Bereit · gerade zu Hause“ / „Der Tunnel springt an, sobald die Konsole nicht direkt erreichbar ist.“ (Vorlage)
   - „Nie“: „Aus“ / „Die App verbindet sich nur direkt mit der Konsole.“
   - Aufbau: „Verbinde · unterwegs“ / „Der Tunnel wird aufgebaut …“
   - verbunden: „Verbunden · unterwegs“ / „Die App erreicht deine Konsole über den Tunnel.“
   - Ausfall: „Keine Verbindung · unterwegs“ / „Die Gegenstelle antwortet nicht. Prüfe Internet und Port-Weiterleitung.“
   - Startfehler: „Tunnel startet nicht“ / Fehlermeldung des Tunnels
2. Karte Radius 10, Fläche `group`, Rand 1 `border`, Zeilen 10/14, Trennlinie 1 `border`, Beschriftung 140 breit:
   „Konfiguration“ | Dateiname `muted` (Mitte gekürzt) | Feld-Button „Ersetzen …“ (12, 3/10) →
     Menü „Datei auswählen …“ / „Aus Zwischenablage einfügen“ (Abw. 5) ·
   „Gegenstelle“ | Endpoint der Datei `muted` (auswählbar) ·
   „Letzte Verbindung“ | „gestern, 18:22 · über Mobilfunk“ `muted`, sonst „noch nie“ (Abw. 4) ·
   „Tunnel verwenden“ (füllt) | Auswahlfeld „Automatisch“ / „Immer“ / „Nie“ (Abw. 3).
3. Zeile verteilt: Link „Anleitung: WireGuard auf dem UniFi-Gateway einrichten“ 12 `accText` ·
   Link „Tunnel entfernen“ 12 `muted` → Bestätigung (Abw. 8).
Darunter bei Bedarf eine Zeile 12: Import-Rückmeldung (Abw. 6), Testergebnis (Abw. 7).
Ohne Datei (Abw. 1): „Noch nicht eingerichtet“ 14/700, Abstand 2, Text 12 `muted`
„Lege die WireGuard-Datei deines Gateways hier ab. Die App nutzt den Tunnel nur für sich.“,
Abstand 10, Ablagefeld wie Einrichtung Schritt 6; Fußzeile nur mit dem Anleitungs-Link.

Routing einer neuen Konsolenadresse (Einrichtung, „Ändern …“): Eine Adresse, die nicht der gespeicherten entspricht, bekommt im Modus „Automatisch“ eine eigene direkte Zertifikatsabfrage (3 s). Antwortet sie, gilt der direkte Weg, sonst der Tunnel. Ist ein Tunnel eingerichtet und noch kein Zertifikat gepinnt, geht der API-Schlüssel erst nach ausdrücklich bestätigtem Fingerabdruck hinaus (Dialog „Neuem Zertifikat vertrauen?“) – eine direkte Antwort kann unterwegs von einem fremden Gerät stammen; Trust on first use nur ohne Tunnel. Bei schon gepinnter Konsole gilt wie bisher: andere Adresse → Fingerabdruck bestätigen; nach dem Speichern bewertet der Router die Route für die neue Adresse sofort neu.

Hintergrund: Ist ein Tunnel eingerichtet und kein Zertifikat gepinnt ("" zählt als keins), verbindet die App weder direkt noch über den Tunnel (kein Trust on first use, `RouteDecision.requiresConfirmedPin`). Hinweis in Allgemein und im Menüleisten-Panel: „Bestätige das Zertifikat deiner Konsole: Einstellungen › Allgemein › Konsole › Ändern …“.
