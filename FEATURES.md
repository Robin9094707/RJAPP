# RJ Love – aktuelle Funktionen (App 10.0.0)

## Stand 10.0 – Live-Daten und Hintergrund-Engine

- Live-Daten für beide iPhones: sekundengenaue Übertragungszeiten für Akku, Standort und Health, letzte Weckquelle, Akkuverlauf über 24 h, Weckquellen-Diagramm und ausführliche Nerd-Telemetrie.
- Hintergrund-Engine: Live-Modus mit Akkumeldung in Sekunden und einstellbarem Herzschlag, Abfahrts-Geofence (CLMonitor), stille Live-Abfrage per APNs, HealthKit-Hintergrundlieferung, BGProcessing-Wartungsfenster und ein Herzschlag bei jeder iOS-Weckung.
- Lokales Weckprotokoll und eine Checkliste für alle Hintergrundvoraussetzungen.
- Designfeinschliff: Karten mit Lichtkante, Akku-Ringe, Live-Zähler.

Details: [Release 10.0.0](RELEASE-10.0.0.md).

## Stand 9.0.1 – Widgets und Hintergrund

- **Widgets und Live-Aktivitäten:** Partnerstatus, Gedanken, Entfernung bei freiwilliger Standortfreigabe, Countdown und weitere Widget-Ansichten.
- **Automatische App-Group-Auswahl:** Die App und die Widget-Erweiterung erkennen die vom installierten Profil tatsächlich erlaubte gemeinsame Gruppe beider unterstützter Signier-Teams.
- **Widget-Diagnose:** gemeinsamer Speicher, Zugriffe der Erweiterung und signierte Profile; manuelle Aktualisierung der WidgetKit-Timelines.
- **Hintergrund-Abruf:** Soweit iOS ihn gewährt, werden Partnerstatusdaten über den bestehenden privaten Server geladen und im Widget-Snapshot aktualisiert. Kein garantierter Zeitplan, keine unbemerkte Standortaufnahme.
- **Sichere Installation:** Eine gemeinsame unsigned IPA, die auf den beiden Geräten separat signiert werden muss. Ein eigenes Widget-Provisioning-Profil bleibt erforderlich.

Details: [Release 9.0.1](RELEASE-9.0.1.md).

## Stand 9.0 – Tagebuch, Chat und KI

- Tagebuch 2.0 mit Schreibfragen, Stimmungen, Kategorien, Spracheingabe und privatem Face-ID-Schutz für einzelne Tagebuchseiten.
- Gemeinsamer Gruppenchat für euch zwei und ChatGPT, Sprachnachrichten und optionale KI-Funktionen.
- Eigenständiger privater Python-Server 9.0.0, der bestehende Konten und Daten weiter verwendet.

Details: [Release 9.0.0](RELEASE-9.0.0.md) · [8.0.0](RELEASE-8.0.0.md) · [7.0.0](RELEASE-7.0.0.md).

---

## Historische Funktionsnotizen

Die folgenden älteren Versionshinweise bleiben zur Nachvollziehbarkeit erhalten. Hinweise auf „aktuell“ in den historischen Abschnitten beziehen sich auf deren damaligen Stand, nicht auf die heutige App-Version.

### Neu in 4.2.0

Gemeinsames Plex-Kino mit Sitzungsbeobachtung, optionalem zweitem iPhone-Stream, Fernsteuerung kompatibler Empfänger, erweiterten Filminformationen, Kinozeit und bestätigtem Statistik-Reset. Native YouTube-Suche ohne eigenen API-Schlüssel und direkte YouTube-Ansicht innerhalb der App. Optionale Apple-Home-Auswahl mit Kameraansichten sowie gläserne Dashboard-Karten. Funktionsgrenzen: [Release 4.2.0](RELEASE-4.2.0.md).

> Aktuell: [Version 3.1 – Fotos, Startseite, Schlafbalance und UWB](RELEASE-3.1.md). Für App 3.1 zuerst den Python-Server auf 3.1 aktualisieren; Konfiguration und Daten behalten.

> Aktueller Funktionsstand 3.0 und Systemgrenzen: [RELEASE-3.0.md](RELEASE-3.0.md). Walkie-Talkie und die eigene Face-ID-Sperre sind entfernt.

# RJ Love 3.0 — Funktionsstand

Implementiert: neue Wir-Oberfläche mit nativen Liquid-Glass-Flächen, Hell/Dunkel, Dynamic Type und reduzierten Herzanimationen bei entsprechender Systemeinstellung; fünf Hauptbereiche; Chat mit lokalem Entwurf und Tagesfrage; gemeinsame Wunschliste; besondere Tage mit Countdown; freiwillige Gefühls-Updates; Notizen, Erinnerungen, Kalender, Fotos/Kommentare/Reaktionen; Partnerkarte und Orte.

HealthKit liest ausschließlich nach Systemfreigabe. Weitergabe an den Partner ist zusätzlich separat für Aktivität, Schlaf und Vitalwerte schaltbar. Fehlende Daten werden nicht als Nullmessung dargestellt. Schlafdauer berücksichtigt die Vereinigung aller Schlafintervalle der letzten 24 Stunden und verhindert Doppelzählung über mehrere Datenquellen.

Nearby Interaction verwendet die öffentliche Apple-API und tauscht kurzlebige Tokens ausschließlich zwischen den beiden angemeldeten Konten aus. Start beidseitig im Vordergrund. Abstand und Richtungsvektor hängen von Hardware, Funkumgebung und iOS ab. Veraltete Messungen verschwinden. Keine Fern-UWB-Ortung und kein heimliches Suchen.

Widget-Extension: vier Home-Screen-Widgets (Herzgedanke, Status, Health, Countdown), zusätzlich Sperrbildschirm-Widget in drei Größen, Partner-Live-Aktivität und AlarmKit-Live-Aktivität mit Dynamic-Island-Darstellung.

Backend: eine Python-Datei, SQLite/WAL, Konfiguration beim ersten Start, scrypt-Passwörter, Login-Limit, unabhängige Konten, atomarer Sitzungsaustausch, Passwort-/Benutzernamenänderung mit aktuellem Passwort, Rücksetzen per Konsole/CLI/Datei, TLS, optionale native APNs- und ActivityKit-Pushes sowie optionale allgemeine ntfy-Hinweise.

Nicht zugesichert: dauerhaft laufender iOS-Hintergrundprozess, exakte Widget-Aktualisierungstakte, sofortige Zustellung ohne APNs, kritische Mitteilungen, ein offizieller Apple-Schlafscore, Freischaltung nicht erlaubter Entitlements durch Sideloading. Reale Hardware- und Signaturtests bleiben notwendig. Ein erfolgreicher Compilerlauf ist kein Hardwaretest.


2.2 ergänzt das Duftstudio (echte private AAC-Aufnahmen, lokale Entwürfe, Vorschau, Pegel/Wellenform, Pause, 60-Sekunden-Limit), Jury-Wertungen, Kommentare, Reaktionen, Favoriten/Best-of, direkte Recorder-Widgets und eine Aufnahme-Live-Aktivität. Dazu kommen Date-Roulette, einlösbare Gutscheine und Wertschätzungsbotschaften. Das Icon und alle Bildressourcen werden direkt im fertigen IPA geprüft.

## Duftstudio

Vier fest erreichbare Ansichten: vollständige Sammlung, Monats-/Jahreskalender mit Tagwahl und Zählern, Furzkarte mit ausdrücklich geteilten Aufnahmeorten sowie Bilanz aus echten Archivdaten. Suche nach Text, Person, Situation und Datum; Filter für Kategorie, Person, Favoriten und Zeitraum; Sortierung nach Datum, Bewertung oder Länge. Metadaten werden über die gesamte Sammlung nachgeladen, Audio nur bei Bedarf.

Recorder mit fester Aufnahme-/Sendeaktion, Schnitt vor und nach dem Teilen und 400 offline gespeicherten Spruchkombinationen für acht Situationen. App und Server erkennen erforderliche Gegenstellen-Updates. Der Server übernimmt vorhandene passende APNs-Schlüssel automatisch ohne Konsolenbefehl; echte Apple-Schlüssel und passende Signaturrechte bleiben Voraussetzung. Details: [RELEASE-2.4.md](RELEASE-2.4.md).

### Neu in 3.7
- Abendplayer für das vollständige Serverarchiv: Duftaufnahmen und Moment-Videos, eigene/Partner-/gemischte Auswahl, Shuffle, Warteschlange, Einschlaftimer, Hintergrund-Audio und Sperrbildschirm-Steuerung.
- Bis zu zwölf kleine persönliche Schnellzugriffe mit eigenen Namen und Reihenfolge direkt oben auf der Startseite.
- Tagebuch 2.0 (9.0): Rückfragen als Buttons beim Schreiben, automatische Stimmung/Themen/Titel, Kontext (Ort, Zeit, Schritte, Momente), Sprach-Tagebuch mit Live-Transkription, Vorlagen, Einblicke mit Stimmungsverlauf, „Frag dein Tagebuch“, Face-ID-Schutz für private Seiten.
- Gruppenchat mit ChatGPT (9.0): ihr zwei plus KI, live mitgeschriebene Sprachnachrichten, @KI, Herz-Knöpfe; Internetsuche mit Quellen im KI-Chat.
- Unser Tagebuch (8.0): gemeinsame Tagesseite für beide, eigene Seiten, private Seiten nur auf dem iPhone, Stimmung, Abendfrage, Suche, Serie und Rückblicke.
- Mit ChatGPT anmelden (8.0, optional): KI-Chat mit App-Wissen und Modellwahl, Tagebuch-Schreibhilfe und Ideen über das eigene ChatGPT-Abo, gegenseitige Freigabe. Einrichtung: RELEASE-8.0.0.md.
- Optionaler KI-Tagesrückblick aus Momenttexten: OpenAI-Schlüssel nur am Server, beiderseitige Freigabe, formatierte Karten, Quellen-Verweise, Cache und gemeinsames Tageslimit. Einrichtung: RELEASE-3.7.md.
# Neu in 3.8

- Momentraster nach Monaten, Suche, Personen-/Albumfilter, Vollbild-Wischen und Fotozoom.
- Video-Streaming mit Bytebereichen, Vorschauen und Originalfotos erst beim Öffnen; optional platzsparender Upload.
- Momentkarte mit gruppierten Markern und verfügbaren Original-Aufnahmeorten.
- Drop-Poop: privates Thronarchiv, Liste/Karte, bewusste Ortsfreigabe, Schnellzugriff, Widget, Kontrollzentrum und Kurzbefehl.
- Optionale Startseitenkarte und Widget für volle Beziehungsmonate, laufenden Monat, Monatstag und Jahrestag.

