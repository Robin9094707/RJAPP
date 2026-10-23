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
- Optionaler KI-Tagesrückblick aus Momenttexten: OpenAI-Schlüssel nur am Server, beiderseitige Freigabe, formatierte Karten, Quellen-Verweise, Cache und gemeinsames Tageslimit. Einrichtung: RELEASE-3.7.md.
