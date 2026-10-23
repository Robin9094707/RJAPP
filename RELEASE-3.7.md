# RJ Love 3.7.0 (370)

## Euer Abend

Ein eigener Player spielt eure Duftaufnahmen oder eure Videos aus Momente nacheinander. Er lädt das vollständige paginierte Serverarchiv, statt nur lokale Kopien oder die letzten Bootstrap-Einträge zu verwenden. Wählbar: nur eigene Beiträge, nur die des Lieblingsmenschen oder beide gemischt; chronologisch oder zufällig. Filme und Duftkonzert haben jeweils ihre eigene Auswahl.

Der native AVQueuePlayer puffert bis zu drei Beiträge. Es werden nur die aktuellen/nächsten Medien vorübergehend geladen, keine komplette private Mediensammlung dauerhaft gespeichert. Abgespielte Dateien werden entfernt; beim Beenden der Sitzung werden die übrigen temporären Dateien gelöscht. Die Wiedergabe bleibt beim Verlassen der Ansicht erhalten, hat Sperrbildschirm-Steuerung, Pause, Weiter, Zurück, Positionsregler und einen Einschlaftimer von 15 bis 60 Minuten. Anrufe und getrennte Kopfhörer pausieren. Neue Mikrofonaufnahmen beenden den Player; er läuft nicht parallel zum Recorder. Haupt-App erhält den regulären Hintergrundmodus audio. Kein Audio wird verwendet, um andere Hintergrundfunktionen am Leben zu halten.

Die nächsten Beiträge brauchen eine Verbindung zum eigenen Server. Nach erzwungenem Beenden der App oder wenn iOS die Wiedergabe beendet, startet sie nicht heimlich neu. Video-Hintergrundwiedergabe verwendet continuesIfPossible. Für das tatsächliche Verhalten bei gesperrten physischen iPhones ist ein Gerätetest erforderlich. Der Player verwendet Originalton; die lustigen Effekte bleiben im bisherigen lokalen Konzert.

## Kleine Schnellzugriffe

Direkt oben auf der Startseite stehen kleine beschriftete Buttons. Unter Startseite anpassen kann jeder bis zu zwölf eigene Schnellzugriffe hinzufügen, benennen, verschieben und löschen. Es gibt unter anderem Momente, direkt Moment aufnehmen, BeReal, Duftstudio, Notfallfurz, Abendplayer, Journal, Feed, Nachrichten, Status, Profil, Nahsuche, Karte, Health, Countdowns, Planung, Ritual, Notizen, Live-Aktivität, Updates und KI-Rückblick.

Jeder hat seine eigene Auswahl, die mit dem vorhandenen Versionsschutz am Server gespeichert wird. Bestehende Karten, Reihenfolgen und Titel bleiben erhalten. Alte gespeicherte Layouts bekommen nur die neue Standardreihe hinzu; auch ältere interne Layout-Schreibweisen ohne shortcuts löschen die gespeicherte Auswahl nicht. Eine ausdrücklich leere Reihe bleibt ausgeblendet.

## Optionaler KI-Rückblick

Unter Unser Tag und Profil → KI-Rückblick. Standardmäßig aus; API-Schlüssel ausschließlich auf dem Server. Beide aktivieren einzeln ihre Freigabe. Erst ein ausdrücklicher Tipp auf Momente zusammenfassen startet eine Anfrage für den gewählten Kalendertag.

An OpenAI gehen nur bis zu 60 Momente: Titel, Beschreibungen (jeweils begrenzt), Autorennamen, Medienart, Aufnahmezeiten und interne Quellen-IDs. Keine Bild-, Video- oder Audiodateien, Chats, Kommentare, Health-Werte oder GPS-Koordinaten. Beschreibungen können natürlich selbst persönliche Angaben enthalten. Die KI sieht keine Bilder und soll keine Bildinhalte oder Gefühle erraten.

Responses API mit store:false, reasoning.effort:none, maximal 1600 Ausgabetokens und strengem JSON-Schema. Daraus rendert die App Titel, Einleitung, bis zu vier Highlights mit passenden Moment-Verweisen, einen wertschätzenden Gedanken und eine Gesprächsfrage. Unvollständige Antworten, Ablehnungen, erfundene Quellen und ungültige Strukturen werden nicht als erfolgreicher Rückblick angezeigt. Keine automatische Wiederholung kostenpflichtiger Anfragen. Standardmodell gpt-6-luna, am Server änderbar auf ein kompatibles Modell. Die aktuelle offizielle Modellseite nennt $0.10 Eingabe und $0.50 Ausgabe pro Million Tokens: https://developers.openai.com/api/docs/models/gpt-6-luna (geprüft 23.10.2026). Tatsächlicher Zugang und Abrechnung hängen vom API-Konto ab.

Unveränderte Tage werden wiederverwendet. Standardlimit acht neue API-Versuche pro Servertag für beide zusammen; fehlgeschlagene Versuche zählen mit. Ein gleichzeitiger Auftrag, keine parallelen Doppelabrechnungen. Entzug einer Freigabe löscht den Servercache, nicht die Originalmomente. Bei zwischenzeitlich entfernten Momenten oder widerrufener Freigabe wird eine laufende Antwort verworfen. Rückblicke werden maximal 90 Tage aufbewahrt, die Bereinigung erfolgt bei der nächsten erfolgreichen Erstellung. store:false deaktiviert die Speicherung als abrufbare API-Antwort, ist keine Zusage über sämtliche sonstige API-Datenverarbeitung.

### Am bisherigen Server aktivieren

Server stoppen, Konfiguration/Daten sichern und nur rj_love_server.py ersetzen. In der bestehenden rjapp_config.json einen zusätzlichen Block auf oberster Ebene ergänzen (gültiges JSON, Komma zum vorherigen Eintrag):

```json
"openai": {
  "enabled": true,
  "api_key": "DEIN_OPENAI_API_SCHLUESSEL",
  "model": "gpt-6-luna",
  "daily_limit": 8
}
```

Alternativ api_key leer lassen und OPENAI_API_KEY in der Umgebung des Serverprozesses setzen. Die Datei und den Schlüssel niemals in GitHub hochladen. Bei systemd muss die Variable dem Dienst zur Verfügung stehen; eine Shell-Variable in einer anderen Sitzung reicht nicht. Danach den Server neu starten. Ohne diesen Block läuft alles wie bisher mit ausgeschalteter KI weiter. Es sind keine neuen Python-Pakete nötig. API-Guthaben wird separat vom ChatGPT-Abo abgerechnet.

App und Server benötigen mindestens 3.7.0. Zuerst Server, danach beide iPhones aktualisieren; bestehende Apps nicht löschen. Haupt-App und Widget passend signieren. Konfiguration, Datenordner, App-IDs und App Group behalten.

## Prüfung

Bestehende Prüfungen plus zwei gezielte Backend-Regressionen für KI-Freigabe, Datenschutz, Ausgabeprüfung, Cache und Limit sowie Schnellzugriff-Migration/Versionsschutz. Der Simulator prüft Profil/Status und eine echte Queue mit drei isolierten Audiodateien am Testserver einschließlich automatischem Wechsel und Rückkehr zur Startseite. Simulatorbilder prüfen die neuen Ansichten. Kein kostenpflichtiger echter OpenAI-Aufruf ohne konfigurierten Benutzerschlüssel; der Anbieterpfad wird mit kontrollierten Antworten geprüft. Physische Sperrbildschirm-/Bluetooth- und UWB-Prüfungen sind dadurch nicht ersetzt.
