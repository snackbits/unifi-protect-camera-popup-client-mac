# Manuelle Prüfungen vor dem Release 1.2.0

Stand 2026-10-18. Diese Punkte konnten die Subagenten nicht prüfen (keine echte Konsole/Kamera, App nie normal gestartet). Vorher: installierte App beenden, `defaults export com.snackbits.UniFiCameraPopup ~/ucp-backup.plist`.

## Phase 1–2: Einrichtung, Einstellungen, Popup, Stummschalten
- [ ] Erster Start über bestehenden Einstellungen: Kameras, Tastenkürzel, Buttons (inkl. Token) vorhanden; laufende Stummschaltung gilt weiter.
- [ ] Einrichtung: Konsole wird gefunden (auch mit VPN / WLAN+Ethernet); falscher Schlüssel → Fehler; richtiger → Kameras; bei ≥ 5 Kameras Menü mit ‹ › im Auslöser-Schritt.
- [ ] Auslöser: Klingel/Person/Fahrzeug öffnen Popup, abgeschaltete bleiben still; Fokus-Modus beachtet.
- [ ] Stream ohne aktivierten RTSP-Stream spielt trotzdem.
- [ ] Erscheinungsbild System/Hell/Dunkel wirkt auf Einstellungen, Panel, Popup; „System“ folgt live.
- [ ] Stumm pro Kamera aus dem Popup; Neustart → weiter stumm; nach Ablauf meldet sie sich, Panel-Zeile verschwindet. „Aufheben“ im Panel und im Rechtsklick-Menü.
- [ ] Dauer-Felder „0“, „abc“, „5000“ → 1 / alter Wert / 999.
- [ ] Alte installierte App und neuer Build abwechselnd starten: neue Einstellungen (Stumm pro Kamera, Erscheinungsbild, „Vor dem Ausführen nachfragen“) bleiben erhalten.
- [ ] Export enthält keinen API-Schlüssel, keine Ton-Daten, keine Stummschaltungen; Import stellt alles wieder her.
- [ ] Bildvergleich: Einstellungen (alle Reiter), Popup, Menü-Panel, Einrichtung Schritt 6 nebeneinander mit der Vorlage https://claude.ai/artifact/Q9JCg1b1gu5stRG2SxaKsP (hell + dunkel).

## Phase 3: Ton & Sprechen (an echter Kamera)

Vorher: `tail -f ~/Library/Logs/UniFi\ Camera\ Popup/talkback.log` in einem Terminal; in einem zweiten `sudo tcpdump -n -i any udp and host <Kamera-IP> -c 40` (zeigt, ob Pakete den Mac verlassen).
1. Test-Popup der Türklingel (Lautsprecher). „Leertaste halten“ mit der Maus halten, 3 s sprechen. Log: „Sitzung anfordern“, „Antwort {…}“ (Rohtext notieren: `url`, `codec`, `samplingRate`, `bitsPerSample`), „Ziel …“, „UDP bereit“, „erstes Paket gesendet“, „Mikrofon zu“, „fertig, N Pakete“ (N ≈ Sekunden × 50 bei Opus bzw. × Rate/1024 bei AAC). tcpdump zeigt Pakete an `<Kamera-IP>:<Port>` im 20-ms- bzw. 46-ms-Takt.
2. **Ton an der Kamera hörbar und verständlich?** Notieren: ja/nein, Verzögerung, Aussetzer.
3. „Ton abspielen“ › „Bin gleich da“ → an der Kamera hörbar, ohne Beschleunigung/Abbruch.
4. Eigene MP3 und eine Text-Ansage (macOS-Stimme) → hörbar.
5. Lautstärke-Regler ganz links/mitte/rechts → leiser/normal/lauter, rechts ohne Knacken.
6. Wenn **kein Ton** trotz Paketen: Log-Antwort prüfen. Opus → nacheinander prüfen: RTP-Payload-Typ (Konstante `RTPPacketizer.opusPayloadType`, ffmpeg nimmt 97), Marker-Bit, fehlendes RTCP (ffmpeg sendet an Port + 1); AAC → Abtastrate im ADTS-Kopf = `samplingRate` der Antwort. Befund mit Rohantwort und tcpdump-Auszug als Rückfrage melden, **keine Änderung ins Blaue**.
7. Wenn die Sitzung scheitert: HTTP-Status aus dem Log (z. B. „Fehler 404/400“) notieren – evtl. verlangt die Konsole einen Body (`{}`) oder eine neuere Protect-Version; als Rückfrage melden.

- [ ] **Step 6: Ende-zu-Ende-Prüfung** (Ergebnis je Punkt notieren)

1. Erster Start über bestehenden Einstellungen: Reiter Ton zeigt die zwei mitgelieferten Ansagen; Konfigurations-Export enthält keine Ton-Daten (`grep -c "announcements" <export>` → 0) und keinen API-Schlüssel.
2. Mikrofon-Dialog erscheint genau einmal; nach „Nicht erlauben“ zeigt das Popup den Hinweis, nach Freigabe in den Systemeinstellungen geht Sprechen ohne Neustart.
3. Zwei Popups gleichzeitig (zwei Kameras): Sprechen in einem stoppt eine laufende Ansage im anderen; die Leertaste gehört dem Popup unter dem Zeiger.
4. Popup während des Sprechens schließen → Log „Mikrofon zu“ bzw. keine weiteren Pakete (tcpdump verstummt).
5. Kamera-Tastenkürzel (⌥⌘1 …) funktionieren weiter, auch während der Zeiger über einem Popup liegt.
6. Ansagen-Datei im Finder aus dem Sounds-Ordner löschen → „Ton abspielen“ › diese Ansage → Hinweis „Die Ansage konnte nicht gelesen werden (Datei fehlt).“, kein Absturz.


## Phase 4: Unterwegs (WireGuard)
- [ ] **Step 1: Automatische Prüfungen**

Run:
```bash
wgtunnel/scripts/go.sh vet ./... && wgtunnel/scripts/go.sh test -count=1 ./...
wgtunnel/scripts/smoke.sh | tail -1
(cd Packages/ProtectKit && swift test 2>&1 | tail -1)
(cd Packages/AppCore && swift test 2>&1 | tail -1)
```
Expected: alles grün, `SMOKE OK`; Build-Befehl → `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Einrichten**

Auf dem Gateway (Einstellungen › VPN › VPN-Server) einen WireGuard-Server mit einem Client „MacBook Camera Popup“ anlegen, Datei herunterladen. Installierte App beenden, Debug-App starten, Einrichtung bis Schritt 6, Datei ablegen.
Expected: „Passt. Gegenstelle: <öffentliche Adresse>:51820“ ohne AllowedIPs-Hinweis (UniFi-Export: `0.0.0.0/0`).

- [ ] **Step 3: Zu Hause**

Expected im Log: `Route (Einstellung geändert): direct, direkt: console`; kein `Tunnel: gestartet`. Reiter „Unterwegs“: „Bereit · gerade zu Hause“. „Jetzt testen“: „Tunnel funktioniert – deine Konsole antwortet.“ – kann der Router kein NAT-Loopback, kommt zu Hause „Keine Antwort …“; dann diesen Punkt in Step 4 auf dem Hotspot wiederholen.

- [ ] **Step 4: Unterwegs (iPhone-Hotspot)**

Mac ins Hotspot-WLAN.
Expected innerhalb von ≈ 10 s: `Route (Netzwerkwechsel): tunnel, direkt: unreachable`, `Tunnel: gestartet`, `Route jetzt: Tunnel`; Rechtsklick-Menü „Protect: verbunden · unterwegs“, Panel-Chip „Unterwegs“; Reiter: „Verbunden · unterwegs“, „Letzte Verbindung | heute, hh:mm · über Mobilfunk“. Test-Popup bzw. Klingeln → Livebild läuft, Log `VLC: starting playback for 127.0.0.1`. **Host-Header-Prüfpunkt (Offene Frage 5):** Kommen Kameraliste und Ereignisse über `127.0.0.1:<port>` an, ist er erledigt; antwortet die Konsole mit 4xx, Arbeit stoppen und Plan B besprechen.

- [ ] **Step 5: Ausfall > 120 s**

Ein Test-Popup mit langer Schließzeit offen lassen, dann am Mac WLAN aus, 150 s warten, WLAN wieder an (Hotspot).
Expected: während des Ausfalls nach ≈ 75 s `Tunnel: keine Antwort mehr`, Reiter „Keine Verbindung · unterwegs“; nach Wiederkehr innerhalb von ≈ 20 s `Tunnel: Tunnel wieder da – n Verbindung(en) neu aufbauen`, `VLC: Stream neu verbinden`, Livebild läuft weiter, Menü wieder „Protect: verbunden · unterwegs“; ein neues Ereignis erzeugt ein Popup.

- [ ] **Step 6: Ruhezustand unterwegs**

Deckel zu, 2 Minuten, Deckel auf.
Expected: `Tunnel: Ruhezustand beendet – …`, kurz darauf wieder verbunden; Ereignisse kommen.

- [ ] **Step 7: Zurück nach Hause**

Mac ins Heim-WLAN.
Expected: `Route (Netzwerkwechsel): direct, direkt: console`, `Route jetzt: direkt`, `Tunnel: gestoppt`; Livebild/Ereignisse laufen direkt (`VLC: starting playback for 192.168.…`).

- [ ] **Step 8: Falsche Dateien, Schlüssel und Export**

- Im Reiter „Ersetzen …“ › „Datei auswählen …“ ein PDF, dann eine `.conf` mit Tippfehler (`AllowedIP = …`) wählen → orange Meldung (mit „Zeile n“), „Konfiguration“ zeigt weiter die echte Datei, unterwegs funktioniert der Tunnel weiter.
- Export prüfen (Allgemein › „Konfiguration exportieren …“ nach `${TMPDIR:-/tmp}/export.json`):
```bash
grep -ci "privatekey\|wireguard\|tunnel\|51820" "${TMPDIR:-/tmp}/export.json"      # Erwartet: 0
defaults export com.snackbits.UniFiCameraPopup - | python3 -c "import plistlib,sys; d=plistlib.load(sys.stdin.buffer); print(d['unifi.camera.popup.tunnel'].decode())" | grep -c -i "privatekey"   # Erwartet: 0
security find-generic-password -s com.snackbits.UniFiCameraPopup.wireguard-config >/dev/null && echo "im Schlüsselbund"
```
Expected: `0`, `0`, `im Schlüsselbund`.

- [ ] **Step 9: Release-Probe (ohne `build-release.sh`)**

Universal-Build wie Task 6 Step 6 wiederholen; die gebaute App auf einem Intel-Mac (oder unter Rosetta: `arch -x86_64 "…/MacOS/UniFi Camera Popup"`) starten → Menüleisten-Symbol erscheint, Hilfe › „Über“ zeigt die Lizenzen.

- [ ] **Step 10: Abschluss**

Alle Prüfpunkte abgehakt, Befunde behoben und committet. `git status --short` zeigt nur ` M UniFiCameraPopup/AppConfig.swift` (lokale Änderung des Nutzers) und keine unversionierten Dateien außer gitignorierten. Kein Merge, kein Push.
