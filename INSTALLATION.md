# RJ Love 2.4 einrichten

## 1. Python-Server

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
- Kalender: gemeinsame Termine unter **Für uns → Ablage-Symbol → Kalender** erstellen. Das Gegenüber übernimmt einen Termin mit „In iOS-Kalender“. Wiederholtes Übernehmen aktualisiert den zugeordneten Termin. Private bestehende Kalender werden nicht automatisch hochgeladen. Löschen in RJ Love löscht keinen bereits übernommenen Apple-Kalendereintrag.
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

`rjapp_config.json` und `rjlove_data/` privat sichern; für eine einfache konsistente Kopie den Server kurz stoppen. Keine dieser Dateien ins öffentliche Repository hochladen. Für diesen Neustart neue leere Verzeichnisse verwenden; keine alten Datenbanken übernehmen.


## Neu: Duftpost, Aufnahme-Widget und Liebessachen

Unter **Spielplatz** findest du Duftpost, Liebe und die bisherige Momentgalerie. Beim ersten Aufnehmen Mikrofonzugriff erlauben. Aufnahmen bleiben zunächst als lokaler Entwurf auf dem eigenen iPhone; erst „Duftpost senden“ teilt sie mit dem Gegenüber. Schließen beendet eine laufende Aufnahme. Ein Entwurf bleibt bis zum Teilen/Verwerfen bzw. Abmelden erhalten. Die Aufnahmedauer ist auf 60 Sekunden begrenzt. Ein Prozessabbruch oder Gerätefehler kann eine gerade noch laufende Aufnahme beschädigen; sichere wichtige Aufnahmen durch Stoppen.

Widget **Duftpost · Sofortaufnahme** hinzufügen. Ein Tipp öffnet die App und die Aufnahmeansicht und startet dort nach Freigabe des Mikrofons automatisch. Bei Face-ID-Schutz zuerst entsperren. Bei vorhandenem Entwurf wird dieser geöffnet, ohne ihn zu überschreiben. Live-Aktivitäten und App-Group-Widgets benötigen weiterhin eine passende Signierung.

Bewertungen sind dem Gegenüber vorbehalten. Du kannst eigene Aufnahmen löschen; Audio und Bewertungen werden dann unmittelbar aus der aktiven Serverdatenbank entfernt (eigene Backups separat verwalten). Gespeicherte Audios zählen zum Speicherlimit. Der Server liefert die neuesten 100 Aufnahmen in der Sammlung.

Unter **Liebe**: Date-Ideen auslosen und als Wunsch merken, persönliche Gutscheine verschenken/einlösen und Wertschätzung teilen. Unter **Momente** bleibt die Fotogalerie erreichbar.

Beim Update von 2.0: Server stoppen, Python-Datei ersetzen, erneut starten. Konfiguration und Datenordner behalten. Für diesen Funktionszuwachs ist keine manuelle Datenmigration notwendig. App und Backend jeweils auf 2.2 aktualisieren.

## Update 2.2

Die Änderungen, Einrichtungsanleitung, Medienstruktur, Backup-Befehle und Voraussetzungen für Walkie-Talkie stehen in [RELEASE-2.2.md](RELEASE-2.2.md). Der Fokus-Status entfällt vollständig. Die neue geführte Einrichtung startet Freigaben eingeschaltet; jede iOS-Berechtigung wird separat angefragt. Funk hält Audio und Texte zehn Minuten abrufbar; der anschließende Minutenlauf löscht sie.

## 2.3: Hintergrundwecker und Signatur prüfen

Unter **Wir → Push, Wecker & Hintergrund prüfen** Profil, tatsächliches APNs-Topic und Serverantworten prüfen. Bei wichtigen Weckrufen im Voraus planen und die Bestätigung „Auf dem iPhone eingeplant“ abwarten. Hintergrundpushes sind durch iOS nicht garantiert. Eine fremde Bundle-ID übernimmt keine Rechte eines anderen Apple-Teams. Weitere Schritte: [RELEASE-2.3.md](RELEASE-2.3.md).

## 2.4: Erst Server, dann App aktualisieren

Die App benötigt Server 2.4 und Protokoll 4. Python-Datei ersetzen, Konfiguration und Datenordner behalten, neu starten; anschließend App inklusive Widget aktualisieren. Push wird automatisch geprüft: Apples AuthKey-Datei in den Ordner `push` neben der Konfiguration legen; passende IDs werden übernommen, soweit eindeutig verfügbar. Details und Voraussetzungen: [RELEASE-2.4.md](RELEASE-2.4.md).
