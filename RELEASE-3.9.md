# RJ Love 3.9 · Bark, ntfy und eure Ruhezeiten

## Aktualisieren

1. Den laufenden Python-Server stoppen. Die vorhandene `rjapp_config.json` und den gesamten Datenordner sichern und behalten.
2. Ausschließlich `Backend/rj_love_server.py` durch die neue Datei ersetzen. Python 3.11+, OpenSSL und curl mit HTTP/2 werden benötigt (auf Debian: `apt install curl openssl ca-certificates`). Keine neuen Python-Pakete, kein Docker, kein zweiter Serverdienst.
3. In der bestehenden Konfiguration sollte `server.public_url` auf `https://love.rjuhas.eu` stehen. Der Standard ist diese Adresse, falls der Eintrag leer ist. Bei anderer Domain entsprechend ändern. Den kompletten Host einschließlich `/bark/`, `/push-icons/`, `/push-image/`, `/push-ack/` und `/push-integration/` über den bestehenden HTTPS-Reverse-Proxy an denselben Python-Port weiterleiten. Ein Proxy, der bereits die ganze Domain weiterleitet, braucht keine neuen Regeln.
4. Server mit dem bisherigen Befehl und derselben Konfiguration neu starten. Datenbank, Medien, Passwörter und Sitzungen bleiben erhalten; neue Tabellen werden automatisch ergänzt. Einen optionalen vorhandenen `ntfy`-Konfigurationsblock übernimmt die App als vorausgefüllte Zugangsdaten. Pro Konto ist zunächst Bark ausgewählt; ntfy bleibt umschaltbar. App 3.8 funktioniert weiterhin für die bisherigen Funktionen; App 3.9 benötigt Server 3.9.
5. Neue IPA wie bisher signieren und installieren, Haupt-App und Widget-Erweiterung mit derselben bisherigen App-Identität. Nach dem ersten Start in jedem Konto **Push & Wecker** öffnen. Die Installation selbst ist kein Zustelltest.

## Bark in zwei Minuten koppeln

- Offizielle Bark-App aus dem App Store installieren. Sie ist laut upstream kostenlos; ein eigener Server ist keine Umgehung eines Kaufs.
- In Bark einen eigenen Server hinzufügen: **https://love.rjuhas.eu/bark**. Bark registriert dort seinen eigenen APNs-Gerätetoken.
- Den von Bark angezeigten Geräteschlüssel oder die ganze Test-URL in RJ Love → **Push & Wecker** einfügen und speichern. Die Registrierung muss vom eigenen Server stammen. Jeder benutzt seinen eigenen Schlüssel; ein Gerät kann nicht mit beiden Konten verbunden sein.
- Mitteilungen und **kritische Hinweise** für Bark unter iOS erlauben. In RJ Love ebenfalls „Kritische Weckrufe erlauben“ einschalten. Dann die normale Testnachricht senden.
- Keine RJ-APNs-Schlüssel und keine Änderungen der RJ-Bundle-ID nötig. Der integrierte Bark-Provider nutzt ausschließlich die vom Bark-Projekt ausdrücklich für eigene Server veröffentlichte MIT-lizenzierte Bark-APNs-Zugangsinformation; sie vergibt keine Bark-Rechte an die RJ-App.

## Was die Hinweise enthalten

Eigene Überschriften, Absender und vollständiger Nachrichtentext bzw. Titel/Beschreibung von Momenten, Duftpost, Kommentaren und Drop-Poop. Lange Texte werden in mehrere Mitteilungen geteilt, damit Apples 4096-Byte-Grenze und ntfys Nachrichtengröße eingehalten werden. Bark bekommt passende PNG-Symbole. Bild-/Videovorschauen werden über ausschließlich auf diesen Datensatz bezogene, signierte, einen Tag gültige URLs ausgeliefert. Zurückgerufene Datensätze liefern keine Vorschau mehr; bereits in Bark heruntergeladene Inhalte können dort weiterhin gespeichert sein. iOS kann Vorschauen auf dem Sperrbildschirm ausblenden; zum Lesen langer Texte die Mitteilung erweitern.

## Wecken, wiederholen, Ruhe halten

- Sofortige und geplante Weckrufe laufen auf dem Python-Server, auch wenn RJ Love beendet ist. Das Zielgerät braucht Bark und Internet. Kritischer Ton setzt die Bark-Berechtigung voraus.
- Bark `call=1` spielt einen Ton bis zu **30 Sekunden**. Optional schickt der Server alle **45 Sekunden** eine weitere Weckmitteilung. Ende: „Bin wach“ in RJ Love oder über den Link in der Bark-Mitteilung bestätigen, beginnende Ruhezeit oder spätestens **eine Stunde** nach Fälligkeit. Das ist kein garantiert unterbrechungsfreier iOS-Systemwecker. Ein bereits zugestellter Ton kann nach der Bestätigung noch auslaufen.
- Bei ntfy gibt es normale Nachrichten, keine kritischen Töne, kein `call` und keine Weckwiederholung. Ein optionaler Ersatzversand erfolgt nur bei erkanntem Bark-Sendefehler; Apple-Annahme bestätigt den Geräteempfang nicht und löst keinen zusätzlichen ntfy-Versand aus.
- Jeder setzt bis zu 20 eigene Ruhepläne mit Wochentagen, Zeitzone, Start, Ende und sichtbarem Statustext. Über Mitternacht zählt der Wochentag des Beginns. Gleiche Uhrzeiten bedeuten 24 Stunden. Sommer-/Winterzeit wird anhand der gewählten IANA-Zeitzone berücksichtigt.
- In Ruhezeiten werden kritische Hinweise und Weckrufe vollständig unterdrückt, auch direkte Bark-API-Aufrufe, geplante Alarme und Wiederholungen. Normale Bark-Hinweise kommen passiv. Der manuelle Nicht-stören-Status unterdrückt zusätzlich normale Hinweise. Ein während Ruhezeit fälliger Alarm wird nicht morgens nachgeholt.
- Alte von RJ geplante lokale AlarmKit-Wecker werden beim Öffnen/Abgleichen der neuen App entfernt, damit sie Ruhezeiten nicht umgehen. Daher neue App nach dem Update auf beiden iPhones einmal öffnen. Kalender-/Erinnerungseinträge bleiben erhalten; extern gesetzte Apple-Wecker werden nicht verändert.

## ntfy als Alternative

In **Push & Wecker** ntfy auswählen, Server, privates Topic und optionalen Zugriffstoken kopieren und in der ntfy-App abonnieren. Jeder erhält ein eigenes zufälliges Topic. Konfiguration speichern. Für schnelle Mitteilungen auf iOS muss ein selbst gehosteter ntfy-Server selbst passend für den iOS-Upstream eingerichtet sein; dieses Update integriert den Bark-Server, keinen zusätzlichen ntfy-Server.

## Eigene Automationen / ChatGPT-Anbindung

Jedes Konto kann seine private Webhook-URL unter **Dein Zugang für Automationen** kopieren. Diese URL ist ein Zugangsschlüssel und erlaubt nur Hinweise an genau dieses Konto. Nicht veröffentlichen.

POST JSON an die kopierte URL:

```json
{
  "title": "Guten Morgen 💗",
  "body": "Deine vollständige Wecknachricht",
  "alarm": true,
  "repeat_until_ack": true,
  "due_at": "2026-10-26T07:00:00+01:00"
}
```

Ohne `due_at` erfolgt der Versand sofort. Ohne `alarm` ist es eine normale Nachricht. Auch Webhooks beachten die Empfänger-Ruhezeiten. ChatGPT-Tasks können nicht allein durch Eintragen dieser URL automatisch externe Webhooks aufrufen: Die ausführende Automation muss HTTP-Anfragen tatsächlich unterstützen. Alternativ sendet ein eigener Scheduler oder eine Integration diesen POST. Der vorhandene angemeldete API-Endpunkt `POST /v1/commands` nimmt für Partnerweckrufe zusätzlich `repeat_until_ack` an.

## Datenschutz und Zustellgrenzen

Die vollständigen Inhalte gehen auf ausdrücklichen Wunsch an den ausgewählten Push-Dienst und Apple APNs; diese Integration aktiviert keine Bark-Ende-zu-Ende-Verschlüsselung. Wer sensible Inhalte nicht auf dem Sperrbildschirm sehen möchte, ändert die iOS-Vorschau-Einstellungen. Private Topic-, Geräte- und Integrationsschlüssel sind wie Passwörter zu behandeln. Zugriff auf Einstellungen und Bestätigungen ist kontogebunden. Vorschau-/Bestätigungs-/Webhook-URLs werden im Python-Zugriffslog maskiert; eigene Proxy-Logs entsprechend behandeln.

Bark-Registrierungen, Einstellungen und ausstehende Versandaufträge liegen in SQLite und überstehen Neustarts. Normale Meldungen werden bei Fehlern begrenzt erneut versucht; fällige Alarme verfallen nach fünf Minuten, wiederholende Alarme spätestens nach einer Stunde. Push ist keine garantierte Alarmzustellung. Apples Rückmeldung und tatsächlicher Empfang werden in der App getrennt benannt.

## Quellen / Protokoll

- https://github.com/Finb/Bark/blob/master/docs/en-us/params.md
- https://github.com/Finb/Bark/blob/master/docs/en-us/deploy.md
- https://github.com/Finb/Bark/blob/master/docs/en-us/cert.md
- https://github.com/Finb/bark-server/blob/master/apns/apns.go
- https://github.com/Finb/bark-server/blob/master/route_register.go

## Validierung

Backend-Regressionstests sowie zusätzliche lokale Integrationstests für Bark-Registrierung, Kontentrennung, vollständige Unicode-Nachrichten, ntfy-Payloads, echte JWT-Erzeugung, APNs-Payloadgrenze, Fälligkeit/Wiederholung, Bestätigung, Ruhezeiten über Mitternacht und Zeitumstellung, private Webhooks und zurückgerufene Bildvorschauen. APNs-/ntfy-Transporttests verwenden simulierte Antworten und versenden keine echten Nachrichten. Der iOS-Build läuft über den bestehenden GitHub-Workflow; tatsächlichen Ton und Empfang abschließend auf beiden iPhones prüfen.
