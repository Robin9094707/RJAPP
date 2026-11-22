# RJ Love 8.0.0 (800) · Tagebuch & KI-Begleiter

App 8.0.0 und Einzeldatei-Server 8.0.0 gehören zusammen. 8.0 baut auf der nie einzeln veröffentlichten Version 7.0 auf und enthält sie vollständig: Apple-Redesign, Öffnungsanimation, Funk, Frage des Tages sowie die Reparaturen bei Fotowünschen und Hintergrundstandort (Details in [RELEASE-7.0.0.md](RELEASE-7.0.0.md)). Protokoll 5 bleibt unverändert. Die Datenbank wird nur additiv erweitert (eine neue Tabelle `ai_sharing`, ein neuer Eintragstyp `diary`). Konten, Medien, Aufnahmen und lokale Einstellungen bleiben unberührt.

## Mit ChatGPT anmelden (optional)

- Profil → **KI & ChatGPT** → „Mit ChatGPT anmelden“. Jede Person meldet sich auf dem eigenen iPhone an; ihr dürft auch beide dasselbe ChatGPT-Konto verwenden.
- OAuth 2.0 mit PKCE über die offizielle Anmeldeseite von OpenAI. Passwort und Bestätigungscodes werden nur dort eingegeben. Die Rückmeldung kommt über einen kleinen lokalen Server auf `127.0.0.1:1455` (bei belegtem Port 1456–1462), der nur während der Anmeldung läuft.
- Tokens liegen im iOS-Schlüsselbund (nur dieses Gerät). Sie werden automatisch erneuert; immer nur eine Erneuerung gleichzeitig, weil Refresh-Tokens nur einmal gültig sind.
- Alle KI-Anfragen gehen direkt vom iPhone an `api.openai.com/v1/responses`, immer mit `store: false` und Streaming. Der Server braucht dafür **keinen** API-Schlüssel.
- Modellwahl aus den Modellen, die euer Abo freigibt (`/v1/models`), Denktiefe und Persönlichkeit (warm, verspielt, ruhig, direkt). Ist ein Modell nicht verfügbar, nimmt die App automatisch das nächste.
- Abmelden widerruft den Refresh-Token und löscht die Sitzung vom iPhone.

## Unser Tagebuch

- Pro Tag eine **gemeinsame Seite**, die ihr beide weiterschreiben könnt, je eine **eigene Seite** („Für uns“, nur der Autor bearbeitet) und **private Seiten**, die ausschließlich auf dem iPhone bleiben (Datei mit vollständigem iOS-Datenschutz, nie zum Server).
- Stimmung, Frage für den Abend (fest oder persönlich von der KI), Wochenleiste, Serie, Suche über alle Seiten, Monatsübersicht.
- KI-Schreibhilfe: aus eurem Tag schreiben (nutzt App-Wissen und die Seiten des Tages), aus Stichpunkten, schöner formulieren, kürzen, „Gedanken dazu“, passende Überschrift. „KI rückgängig“ stellt den vorherigen Text wieder her.
- Rückblick für Woche, Monat oder Jahr, auf Wunsch als gemeinsame Seite gespeichert.

## KI-Chat mit App-Wissen

- Gespräche bleiben auf dem iPhone, mit Umbenennen, Löschen, Modell- und Denktiefenwahl direkt im Chat.
- „App-Wissen“ schaltbar pro Gespräch: Momente, Tagebuch, Notizen, Wünsche, Gefühle, Nachrichten, Abendrituale, Termine und Countdowns, Herzgedanken, Drop-Poop-Titel und das Duftstudio (Titel, Kategorie, Länge, Jury-Wertung). Zeitraum 7–120 Tage, Nachrichten, Duftstudio sowie Schritte & Schlaf einzeln abschaltbar.
- Antworten ins Tagebuch übernehmen oder direkt als Nachricht an den Lieblingsmenschen senden.
- **KI & Tagebuch** als neue Seite und Startseitenkarte: Fragefeld, Ideen auf Knopfdruck (Liebesbrief, Date-Idee, Wochenrückblick, Gesprächsfragen, Überraschung, Duft-Jury), Tagebuchstatus von heute.

## Gegenseitige Freigabe

Die Inhalte deines Lieblingsmenschen erreichen deine KI nur, wenn er oder sie unter KI & ChatGPT „Meine Inhalte für …s KI“ einschaltet (Standard: aus). Deine eigenen Inhalte kennt deine KI immer, sobald du das App-Wissen nutzt. Fotos, Videos, Audio, GPS-Koordinaten, Passwörter und Tokens werden nie übertragen.

## Duftstudio flüssiger

- Recorder: Uhr, Wellenform und Pegelring lesen den Pegel selbst. Nur sie zeichnen 12-mal pro Sekunde neu, nicht mehr der ganze Recorder.
- Wiedergabe: Nur die Wellenform und der Regler der gerade spielenden Karte folgen der Wiedergabezeit; alle anderen Karten bleiben ruhig.
- Jede Karte hat ein Sheet statt fünf; Statistik im Kopf wird einmal pro Archivänderung berechnet; die Suche filtert nach einer kurzen Tipp-Pause.

## Server 8.0.0

- Neuer Eintragstyp `diary` (Felder `title`, `text`, `message`, `notes`, `day`, `emoji`, `entry_type` = `personal`/`together`, `ai_assisted`). Persönliche Seiten ändert nur ihr Autor, gemeinsame Seiten beide. Push zeigt nur die Überschrift.
- `GET /v1/ai/context?days=N` (1–120): kompakte, reine Textübersicht für den KI-Begleiter. Inhalte des Gegenübers nur mit dessen Freigabe.
- `POST /v1/ai/sharing {"enabled": true|false}`; `GET /v1/ai/status` liefert zusätzlich `my_sharing` und `partner_sharing`.
- Startseite: neue Karte `companion`, einmalig nach „Unser Tagesrückblick“ eingefügt (`layoutVersion` 4; Frage des Tages und Funk aus 7.0 bleiben oben). Wer sie entfernt, bekommt sie nicht zurück.
- Neue Schnellzugriffe `diary`, `aiChat`, `companion`.
- `MINIMUM_APP_VERSION = 8.0.0`: Apps 7.x und älter zeigen ihr Update-Fenster; IPA-Download und Feather-Quelle bleiben offen. Der bisherige Server-Tagesrückblick mit API-Schlüssel bleibt unverändert verfügbar.

## Sicher aktualisieren

1. Server stoppen, `rjapp_config.json` und den kompletten Datenordner sichern.
2. Nur `Backend/rj_love_server.py` ersetzen und mit derselben Konfiguration starten.
3. Optional die neue `RJ-Love-unsigned.ipa` neben die Serverdatei legen; die alte App bietet dann das Update an.
4. IPA wie bisher signieren (Bundle-ID `eu.rjuhas.rjlove`, gleiches Team, identische App Group, Widget mitsignieren) und über die bestehende App installieren, nicht vorher löschen.

## Prüfung

Neue Server-Tests: Tagebuch-Validierung und Bearbeitungsrechte, Archiv, Freigabe-gesteuerter KI-Kontext, Startseiten-Migration, Update-Fenster für 7.0; dazu alle 7.0-Tests (Funk, Frage des Tages, Fotowünsche, Standort). GitHub Actions kompiliert App und Widget mit Xcode 26. Die ChatGPT-Anmeldung selbst ist eine Geräteprüfung (echtes Konto, echtes iPhone).
