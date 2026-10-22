> Aktuell: [Version 3.1 – Fotos, Startseite, Schlafbalance und UWB](RELEASE-3.1.md). Für App 3.1 zuerst den Python-Server auf 3.1 aktualisieren; Konfiguration und Daten behalten.

> Aktuelles Update 3.0: Erst [RELEASE-3.0.md](RELEASE-3.0.md) lesen. Serverdatei ersetzen, Konfiguration und Datenordner behalten; danach beide Apps inklusive Widget aktualisieren.

# RJ Love 3.0 einrichten

## 1. Python-Server

**Vorhandenen Server aktualisieren:** Server stoppen, `rj_love_server.py` durch die Datei aus diesem Paket ersetzen und wieder starten. `rjapp_config.json` und `rjlove_data/` unverändert behalten und vorher sichern. Die neue App benötigt Server 3.0 mit Protokoll 5; deshalb zuerst den Server, danach die App aktualisieren. Die folgenden Schritte mit leerem Ordner gelten ausschließlich für eine erstmalige Einrichtung.

1. `Backend/rj_love_server.py` in einen neuen leeren Serverordner kopieren. Python 3.11 oder neuer verwenden.
2. `python3 rj_love_server.py` starten. Die Datei `rjapp_config.json` wird erzeugt. Der erste Lauf beendet sich absichtlich.
3. Die beiden zufälligen Startpasswörter sicher notieren. Auf Wunsch eigene Passwörter mit mindestens zehn Zeichen und Benutzernamen eintragen. Die internen IDs `robin` und `raphaela` beibehalten.
4. Host/Port einstellen; Standard ist `0.0.0.0:8765`. Für das Internet einen HTTPS-Reverse-Proxy oder den TLS-Block verwenden. Keine Zugangsdaten über öffentliches HTTP übertragen.
5. Erneut starten. Es sind keine zusätzlichen Python-Pakete nötig. Beim Start werden Klartextpasswörter durch scrypt-Hashes ersetzt. Das ist normal; zur Anmeldung weiterhin das ursprüngliche Passwort verwenden.
6. CubeCoders: Interpreter `python3`, Startdatei `rj_love_server.py`, Arbeitsordner derselbe Ordner. Serverdaten und Konfiguration gegen fremden Zugriff schützen und sichern.

## 2. App signieren und installieren

1. `RJ-Love-unsigned.ipa` in Feather bzw. deinen Signaturdienst importieren.
2. Haupt-App `eu.rjuhas.rjlove` und Extension `eu.rjuhas.rjlove.widgets` zusammen signieren.
3. Gemeinsame App Group `group.eu.rjuhas.rjlove` erhalten. Falls der Dienst Bundle-IDs neu zuordnet, müssen App, Extension und App-Group-Zuordnung konsistent bleiben. Keine Extension entfernen, wenn Widgets/Live-Aktivitäten gewünscht sind.
4. Der Dienst muss HealthKit, App Groups und gegebenenfalls Push in den Provisioningprofilen erlauben. Fehlt eine Fähigkeit, zeigt die App einen eingeschränkten Zustand; eine unsignierte IPA kann das nicht vorab freischalten.
5. Auf beiden iPhones installieren, dieselbe HTTPS-Serveradresse eingeben und jeweils mit eigenem Konto anmelden.
6. Unter **Mehr → Funktionen & Signatur** Status prüfen. Dann gewünschte Rechte und Freigaben setzen.

## 3. Bewusst freigeben

- Standort aktivieren und für Hintergrundortung auf Wunsch „Immer“ erlauben.
- **Mehr → Health & Freigaben → Meine Daten**: Apple Health verbinden, Kategorien auswählen und Weitergabe-Schalter aktivieren. Health-Leserechte und die Weitergabe an den Partner sind zwei getrennte Entscheidungen.
- Planung: gemeinsame Termine, Jahrestage und Erinnerungen unter **Für uns → Kalendersymbol oben links (Gemeinsame Planung)** anlegen. Die Schalter für Apple Kalender und Apple Erinnerungen legen fest, welche Einträge nach Freigabe beim Öffnen abgeglichen werden. Verknüpfte Apple-Einträge werden bei Änderungen aktualisiert und beim Löschen des gemeinsamen Plans entfernt, sofern der Zugriff erlaubt ist. Private sonstige Kalender und Listen werden nicht hochgeladen.
- Nahbereich: beide **Wir → Dich finden** öffnen, Suche starten, nah zusammengehen und iPhones aufrecht halten. Bei fehlendem Richtungsvektor wird kein Pfeil gezeigt.
- Widgets durch langes Drücken auf den Home- oder Sperrbildschirm hinzufügen. Sie zeigen den letzten App-Abgleich.
- Live-Aktivität auf der Wir-Seite starten. Bei nicht laufender App aktualisiert sie sich nur durch zulässige Hintergrundereignisse/APNs.

## 4. Zugänge zurücksetzen

Im laufenden Server `reset robin` oder `reset raphaela` eingeben. Die Konsole gibt ein neues Passwort aus; frühere Sitzungen und Push-Tokens werden gelöscht. Auch ohne Terminaldialog in CubeCoders nutzbar. Konsolenprotokolle vertraulich behandeln.

Dateiweg: Im `users`-Block das Passwort durch ein neues Klartextpasswort ersetzen und gegebenenfalls den Benutzernamen ändern. Danach `reload` in der laufenden Konsole ausführen. Alternativ Server neu starten. Nicht die internen IDs ändern. Bereits ausgegebene Passwörter werden nach dem Einlesen gehasht.

Verdeckte Eingabe in einem echten Terminal: Server stoppen, `python3 rj_love_server.py --reset-user robin` ausführen und danach normal starten. Die App bietet unter **Mehr → Meinen Zugang ändern** denselben Weg für das eigene Konto mit aktuellem Passwort.

Pro Konto bleibt nur die neueste Anmeldung gültig. Ein altes Gerät verliert den Serverzugriff sofort; beim nächsten Verbindungsversuch meldet es sich lokal ab. Bereits offline gespeicherte Daten können technisch nicht aus der Ferne von einem ausgeschalteten Gerät gelöscht werden.

## 5. Optionales APNs

Der Server erkennt beim normalen Start und anschließend jede Minute passende Apple-APNs-Zugangsdaten automatisch. Lege die echte `AuthKey_<KEYID>.p8` in den Ordner `push` neben der Konfiguration. Key-ID und gegebenenfalls die eindeutige Team-ID der registrierten iPhones werden übernommen. Optional liefert `push/credentials.json` die fehlenden IDs. Es ist kein Einrichtungsbefehl nötig. Der Server benötigt curl mit HTTP/2 und openssl. Ohne von Apple ausgestellten Schlüssel kann er keine APNs-Zugangsdaten erzeugen. Details: [RELEASE-2.4.md](RELEASE-2.4.md).

Die App registriert Geräte- und Live-Aktivitätstokens automatisch, wenn iOS dies erlaubt. Der Server aktualisiert Live-Aktivitäten höchstens alle 15 Sekunden bei neuen Status-/Herzereignissen; zusätzliche Apple-Limits sind möglich.

## 6. Optionales ntfy

Beispiel für die lokale Konfiguration (Platzhalter durch eigene zufällige Topic-Namen ersetzen):

```json
"ntfy": {
  "enabled": true,
  "server_url": "https://ntfy.sh",
  "access_token": "",
  "topics": {
    "robin": "HIER-EINEN-ZUFAELLIGEN-PRIVATEN-TOPIC-EINTRAGEN",
    "raphaela": "HIER-EINEN-ANDEREN-ZUFAELLIGEN-TOPIC-EINTRAGEN"
  }
}
```

Nur HTTPS; Topic mindestens 16 Zeichen aus Buchstaben, Zahlen, `_` oder `-`. Auf jedem iPhone ntfy installieren und nur den eigenen Topic abonnieren. Wenn verfügbar, geschützte authentifizierte Topics verwenden. Über diesen Weg verlassen nur allgemeine Hinweise wie „Eine neue Nachricht wartet in eurer App“ den privaten Server. Für selbst gehostetes ntfy die iOS-Push-Konfiguration des Betreibers beachten. Änderungen an dieser Konfiguration durch Serverneustart übernehmen.

## 7. Sicherung und Neustart

`rjapp_config.json` und `rjlove_data/` privat sichern; für eine einfache konsistente Kopie den Server kurz stoppen. Alternativ den integrierten Backup-Befehl verwenden, siehe [RELEASE-2.2.md](RELEASE-2.2.md). Keine dieser Dateien ins öffentliche Repository hochladen. Beim Update bleiben Konfiguration und Datenverzeichnis erhalten; neue optionale Spalten werden automatisch ergänzt. Nur eine ausdrücklich gewünschte, vollständig neue Einrichtung beginnt in einem leeren Ordner.


## Neu: Duftpost, Aufnahme-Widget und Liebessachen

Unter **Spielplatz** findest du Duftpost, Liebe und die bisherige Momentgalerie. Beim ersten Aufnehmen Mikrofonzugriff erlauben. Aufnahmen bleiben zunächst als lokaler Entwurf auf dem eigenen iPhone; erst „Duftpost senden“ teilt sie mit dem Gegenüber. Schließen beendet eine laufende Aufnahme. Ein Entwurf bleibt bis zum Teilen/Verwerfen bzw. Abmelden erhalten. Die Aufnahmedauer ist auf 60 Sekunden begrenzt. Ein Prozessabbruch oder Gerätefehler kann eine gerade noch laufende Aufnahme beschädigen; sichere wichtige Aufnahmen durch Stoppen.

Widget **Duftpost · Sofortaufnahme** hinzufügen. Ein Tipp öffnet die App und die Aufnahmeansicht und startet dort nach Freigabe des Mikrofons automatisch. Wenn iOS eine Entsperrung verlangt, zuerst das iPhone entsperren. Bei vorhandenem Entwurf wird dieser geöffnet, ohne ihn zu überschreiben. Live-Aktivitäten und App-Group-Widgets benötigen weiterhin eine passende Signierung.

Bewertungen sind dem Gegenüber vorbehalten. Du kannst eigene Aufnahmen löschen; Audio und Bewertungen werden dann unmittelbar aus dem aktiven Serverbestand entfernt (eigene Backups separat verwalten). Gespeicherte Audios zählen zum Speicherlimit. Der normale Abgleich enthält die neuesten 100 Aufnahmen; das Duftstudio lädt das gesamte Archiv seitenweise nach. Sammlung, Monats-/Jahreskalender, Furzkarte und Bilanz haben eine fest erreichbare Bereichsauswahl. Im Jahresmodus werden die Aufnahmen des ganzen Jahres angezeigt. Suche und Filter gelten in allen vier Ansichten.

Unter **Liebe**: Date-Ideen auslosen und als Wunsch merken, persönliche Gutscheine verschenken/einlösen und Wertschätzung teilen. Unter **Momente** bleibt die Fotogalerie erreichbar.

Auch beim Update von einer früheren Version: Server stoppen, Python-Datei ersetzen, erneut starten. Konfiguration und Datenordner behalten. Die Ergänzung der Tabellen erfolgt automatisch. App und Backend jeweils auf 3.0 aktualisieren.

## Push, Wecker und Hintergrund prüfen

Unter **Wir → Push, Wecker & Hintergrund prüfen** Profil, tatsächliches APNs-Topic und Serverantworten prüfen. Bei wichtigen Weckrufen im Voraus planen und die Bestätigung „Auf dem iPhone eingeplant“ abwarten. Hintergrundpushes sind durch iOS nicht garantiert. Eine fremde Bundle-ID übernimmt keine Rechte eines anderen Apple-Teams. Walkie-Talkie wird in 3.0 nicht mehr angeboten.
