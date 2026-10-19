# Einstellungen › Ton (Vorlage S5)

Kopf wie Allgemein, Titel „Ton & Sprechen“, Reiter „Ton“ aktiv.
Inhalt Innenabstand 14/40, Abstand 10, Schrift 13. Scrollt, wenn der Inhalt höher als das Fenster ist.
1. Abschnitt Abstand 5: „Ansagen für „Ansage abspielen““ 11/600 `muted`. Karte Radius 10, `group`, Rand 1 `border`:
   Zeilen Abstand 10, Innenabstand 6/12, Trennlinie 1 `border` unter jeder Ansage:
   Play-Knopf 22 rund `accSoft`, Dreieck 9 (gefüllt) `accText` („Probehören“ am Mac, zweiter Klick stoppt) ·
   Name 500, füllt, einzeilig · Länge 11 `muted` tabellarisch („0:03“, auf Sekunden gerundet) ·
   Badge 10/700 Innenabstand 2/6 Radius 4 (MP3: `btn2`/`muted`; KI-STIMME: `accSoft`/`accText`).
   Ausgewählte Zeile Fläche `accSoft`; Klick auf die Zeile wählt aus.
   Kontextmenü (nativ): „Umbenennen …“, „Löschen“ – beide mit nativem Dialog.
   Mitgeliefert: „Bin gleich da“ 0:03 KI-STIMME · „Paket bitte abstellen“ 0:04 KI-STIMME.
   Danach Zeile Abstand 14, Innenabstand 6/12, 12: Links „MP3 hinzufügen …“ · „Ansage aus Text …“
   (`accText`, unterstrichen).
2. Editor-Karte (nur mit ausgewählter Ansage): Abstand 8, Innenabstand 10/12, Radius 10, `group`, Rand 1 `accent`:
   - „„<Name>““ 600, füllt | Segment „MP3-Datei“ · „KI-Stimme“
   KI-Stimme:
   - Eingabe „Text der Ansage“ 13, Innenabstand 5/8, Radius 6
   - Zeile Abstand 8: „Stimme“ 12 `muted` · Auswahlfeld · Freiraum · „Anhören“ (Feld-Button 12, 3/10) ·
     „Übernehmen“ (12/600, 3/10, `accent`, weiß). Stimmen: „Thorsten · mitgeliefert“ (nur mitgelieferte
     Ansage mit Originalwortlaut), dann deutsche macOS-Stimmen „Anna (Premium) · macOS“,
     „<Name> (Erweitert) · macOS“, „<Name> · macOS“.
   - „Wird auf diesem Mac erzeugt – ohne Internet, ohne Konto.“ 11 `muted`
   MP3-Datei:
   - Zeile Abstand 8: „MP3-Datei · 0:03“ bzw. „Noch keine Datei gewählt.“ 13 `muted` · Freiraum ·
     „Datei wählen …“ · „Anhören“ (Feld-Buttons 12, 3/10)
   - „MP3 bis 5 Minuten. Die Datei wird in die App kopiert und bleibt auf diesem Mac.“ 11 `muted`
   Fehler: eine Zeile 11 System-Orange unter dem Hinweis.
3. Karte Radius 10, Zeilen 10/14, Trennlinie 1 `border`:
   - „Mikrofon“ | Auswahlfeld mit den Eingabegeräten (Core-Audio-Name, z. B. „MacBook Pro-Mikrofon“)
   - „Sprechen“ | Segment „Leertaste halten“ · „Umschalten“
   - „Lautstärke an der Kamera“ | Regler: Spur 180 × 4 Radius 2 `toggleOff`, Füllung bis zum Wert `accent`,
     Knopf 16 weiß mittig auf dem Ende der Füllung, Schatten 0 1 3 rgba(0,0,0,.35).
     Vorlagenstellung 2/3 (Füllung 120, Knopf x 112) = unveränderte Lautstärke, ganz rechts × 1,5.

## Phase 5 (Nutzerwunsch, gilt vor der Vorlage)
- Stimme: Auswahlfeld deaktiviert, zeigt „Anna · macOS“; ohne Anna „<beste deutsche Stimme> · macOS“ und darunter 11 System-Orange
  „Anna ist auf diesem Mac nicht installiert – es spricht „<Name>“. …“. „Thorsten · mitgeliefert“ wird nicht mehr angeboten.
- Karte 3: „Mikrofon“ · „Lautstärke Sprechen“ · „Lautstärke Ansagen“ (beide Regler wie „Lautstärke an der Kamera“, 2/3 = unverändert);
  die Zeile „Sprechen“ (Leertaste halten · Umschalten) entfällt.

## Phase 6 (Nutzerwunsch, gilt vor Vorlage und Phase 5)
- Stimme: Auswahlfeld aktiv mit allen angebotenen Piper-Stimmen, Reihenfolge „Thorsten · mittel“ (Standard), dann
  Eva K. · sehr niedrig, Karlsson · niedrig, Kerstin · niedrig, MLS · mittel, Ramona · niedrig, Thorsten · niedrig,
  Thorsten · hoch, Thorsten emotional · mittel; Zusatz „– geladen“ bzw. „– NN MB laden“ (auch bei Thorsten · mittel: keine
  Stimme ist mitgeliefert, Entscheidung C1 der Schlussprüfung – app.zip bleibt unter GitHubs 100-MB-Grenze). Pavoque wird
  nicht angeboten (CC BY-NC-SA).
- Mehrsprecher-Stimme: zweites Auswahlfeld direkt rechts daneben (Thorsten emotional: amüsiert … flüsternd, Standard neutral;
  MLS: Sprecher 1 … 236).
- Unter der Zeile 11 `muted`: „Wird auf diesem Mac erzeugt – ohne Internet, ohne Konto.“ bzw. bei nicht geladener Stimme
  „Wird beim ersten Anhören oder Übernehmen geladen (NN MB, einmalig, braucht Internet) – danach auf diesem Mac erzeugt,
  ohne Internet.“ (bei Thorsten · mittel beginnt sie mit „Die Standardstimme wird …“), rechts daneben Link „Jetzt laden“;
  während des Ladens stattdessen Zeile Abstand 8: Fortschrittsbalken 120 × 5, Kapsel, Spur `btn2`, Füllung `accent` · „Lade „<Stimme>“ … 23 von 63 MB“
  11 `muted` tabellarisch · Freiraum · Link „Abbrechen“.
- Darunter 11 `muted` einzeilig: „Lizenz der Stimme: <Lizenz> · <Datensatz>“.
- Alte macOS-Ansage: 11 System-Orange „macOS (alt) – mit „Übernehmen“ neu erzeugen“ (Feld zeigt die Zielstimme).
- Neue Karte „Geladene Stimmen“ zwischen Editor und Mikrofon-Karte (nur mit mindestens einer geladenen Stimme):
  Abschnittstitel wie „Ansagen …“, Zeilen Innenabstand 6/12: Name · Qualität füllt · Größe 11 `muted` · Link „Entfernen“
  (Rückfrage nativ).
- Textfeld: direkt darunter rechtsbündig 11 `muted` tabellarisch „NN von höchstens 1000 Zeichen“; über 1000 Zeichen
  System-Orange „NNNN Zeichen – höchstens 1000 Zeichen. Kürze den Text oder teile ihn auf zwei Ansagen auf.“ und
  „Anhören“/„Übernehmen“ deaktiviert (Entscheidung I3 der Schlussprüfung).
- „Entfernen“ in „Geladene Stimmen“ ist deaktiviert, solange Piper mit dieser Stimme spricht. Thorsten · mittel steht nach
  dem Laden ebenfalls in der Karte und ist entfernbar (wird beim nächsten Gebrauch wieder geladen).
