# RJ Love 9.0.0 (900) · Tagebuch 2.0 & Gruppenchat mit ChatGPT

App 9.0.0 und Einzeldatei-Server 9.0.0 gehören zusammen. Protokoll 5 bleibt. Die Datenbank wird nur ergänzt (neuer Eintragstyp `group`, neue Tagebuchfelder), bestehende Konten, Medien, Einträge und Einstellungen bleiben unverändert. Enthält alles aus 7.0 und 8.0.

## Tagebuch 2.0 (nach dem Vorbild von Rosebud)

- **Rückfragen beim Schreiben:** Nach einer kurzen Schreibpause stellt ChatGPT drei einfühlsame Rückfragen als Buttons. Ein Tipp fügt die Frage in den Text ein. „Frag mich“ holt jederzeit neue Fragen. Die KI kennt frühere Einträge („Letzte Woche schriebst du …“).
- **Stimmung automatisch:** Schon beim Tippen ein Vorschlag aus dem Text (auch ohne KI), danach von ChatGPT Stimmung, 1–4 Themen und eine Überschrift. Wer nichts auswählt, bekommt den Vorschlag beim Speichern automatisch eingetragen.
- **Kontext des Eintrags:** Ort (aus dem aktuellen Standort, abschaltbar), Wochentag und Tageszeit, Schritte, Herzgedanken, Momente und Nachrichten des Tages samt Momentbeschreibungen. Wird mit der Seite gespeichert und fließt ins App-Wissen.
- **Sprach-Tagebuch:** Erzählen statt tippen. Das iPhone schreibt live Stück für Stück mit (Apple-Spracherkennung, wenn möglich auf dem Gerät).
- **Geführtes Schreiben:** Vorlagen Dankbarkeit, Abendreflexion, Beziehungs-Check, Sorgen loslassen, Träume & Ziele, Morgenseite, Brief an dich, jeweils mit Einstiegsfrage und Folgefragen.
- **Themen:** Schlagwörter pro Seite, Vorschläge zum Antippen.
- **Einblicke:** Stimmungsverlauf (7 Tage, 30 Tage, 1 Jahr), häufigste Stimmungen, Themen und Orte, Seiten und Wörter, „Frag dein Tagebuch“.
- **Spiegeln:** In jeder Seite fasst ChatGPT auf Wunsch zusammen, was es heraushört, mit einer sanften Frage für morgen.
- **Privater Bereich:** Private Seiten bleiben nur auf dem iPhone und lassen sich mit Face ID schützen.

## Gruppenchat mit ChatGPT

- Ihr zwei und ChatGPT in einem Chat, live über euren Server (Long-Poll wie beim Funk).
- **Sprachnachrichten** werden beim Sprechen live mitgeschrieben und mit Text verschickt; beide können sie anhören.
- **ChatGPT antwortet**, wenn eine Nachricht `@KI` oder `@ChatGPT` enthält oder über den ✨-Knopf. Die Antwort entsteht auf dem iPhone der fragenden Person (mit deren Abo) und erscheint für beide, gekennzeichnet „ChatGPT · für …“. Die KI kennt den Chatverlauf und euer App-Wissen.
- **Herz-Knöpfe:** Komplimente, Liebesgedicht, Date-Idee, „Weißt du noch?“, Frage für uns, Wochenende planen.
- Antworten ins Tagebuch übernehmen, eigene Nachrichten für beide zurückrufen. Bark/ntfy melden neue Nachrichten.

## KI-Chat

- **Internetsuche** pro Gespräch (Menü → „Im Internet suchen“), mit Statusanzeige und Quellenliste. Lehnt das Abo die Suche ab, antwortet die KI automatisch ohne und versucht es am nächsten Tag erneut.

## Was über das ChatGPT-Abo geht und was nicht

- Laut OpenAI zählen alle Anfragen über „Sign in with ChatGPT“ auf das Kontingent für ChatGPT Work und Codex. Ein eigenes Chat-Kontingent für fremde Apps gibt es nicht. In ChatGPT unter Einstellungen → Nutzung lässt sich ein Limit pro App setzen.
- Text und (je nach Konto) die Internetsuche funktionieren. Audio, Whisper/Transkription, Echtzeit-Sprache, Bildgenerierung und Code Interpreter sind über das Abo **nicht** möglich. Spracheingabe und Transkription laufen deshalb auf dem iPhone.
- Videoanrufe sind für ein späteres Update vorgesehen (benötigen WebRTC).

## Server 9.0.0

- `MINIMUM_APP_VERSION = 9.0.0`; Apps 8.x und älter zeigen ihr Update-Fenster, IPA-Download und Feather-Quelle bleiben offen.
- Neuer Eintragstyp `group` (`text`, `asset_ids`, `media_kind` = `audio`, `audio_seconds`, `ai`, `model`, `requested_by`, `sources`, `reference_id`). Nur der Autor ändert oder ruft zurück. Gruppennachrichten belasten den Bootstrap nicht.
- `GET /v1/group?after=…&wait=…` (Long-Poll), `limit`, `before` für ältere Nachrichten; gelöschte Nachrichten kommen als `{"id","deleted":true}`.
- Tagebuch: zusätzliche Felder `location`, `latitude`, `longitude`, `tags`, `template`, `context`. Persönliche Seiten kann nur ihr Autor löschen.
- KI-Kontext enthält Gruppenchat, Ort und Themen von Tagebuchseiten.

## Sicher aktualisieren

1. Server stoppen, `rjapp_config.json` und den Datenordner sichern.
2. Nur `Backend/rj_love_server.py` ersetzen und neu starten.
3. IPA wie bisher signieren (Bundle-ID `eu.rjuhas.rjlove`, gleiches Team, identische App Group, Widget mitsignieren) und über die bestehende App installieren.

Beim ersten Sprach-Tagebuch bzw. der ersten Sprachnachricht fragt iOS nach Spracherkennung, beim Schützen privater Seiten nach Face ID.
