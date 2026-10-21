# RJ Love 2.2.0 (220)

## Duftpost: aufnehmen → schneiden → senden

Der Name ist jetzt optional. Ohne Eingabe wird „Ein kleines Meisterwerk“ verwendet; eine fertige Aufnahme lässt sich direkt senden. Bei zu langen Texten erscheint eine Erklärung. Ein fehlgeschlagener Upload behält den lokalen Entwurf. Start- und Endregler mit Ausschnitt-Vorschau schneiden vor dem Upload. Eigene geteilte Aufnahmen lassen sich über das Drei-Punkte-Menü nachträglich schneiden und umbenennen. Das Original und frühere Schnitte bleiben im Serverarchiv erhalten; Bewertungen und Reaktionen bleiben zugeordnet. Gleichzeitige Änderungen werden über Versionsnummern geschützt.

## Einrichten und Freigaben

Nach der Anmeldung erscheint einmalig die geführte Einrichtung. „Alles einrichten“ fragt nacheinander Mitteilungen, Mikrofon, Standort, Bewegung, Health, Kalender, Weckrufe und App-Schutz an. Die Freigaben für Standort, alle verfügbaren Health-Zusammenfassungen und WLAN-Name sowie Walkie-Talkie mit Audioempfang und Vorlesen starten eingeschaltet. Spätere Änderungen werden nicht beim App-Start überschrieben. iOS-Dialoge bleiben maßgeblich; eine Ablehnung wird nicht umgangen. Health kann eine erlaubte Leseauswahl nicht zuverlässig offenlegen, daher bedeutet „angefragt“ keine Zusage auf bestimmte Daten.

„Immer“-Standort kann iOS später bestätigen lassen. Nahbereichssuche fordert ihre Freigabe an, wenn beide Geräte die Suche öffnen und ihre Tokens austauschen. Bilder werden über den geschützten Systembildwähler ausgewählt, ohne pauschalen Fotomediathekzugriff. Fokus-Status wurde vollständig entfernt.

## Eure private Frequenz

Walkie-Talkie ist von „Wir“, „Für uns“, „Mehr“ und einem neuen Widget erreichbar. Gedrückt halten sendet bis zu 30 Sekunden. Kleine AAC-Audioteile werden während des Sprechens über den eigenen Server geschickt und auf dem anderen iPhone nacheinander abgespielt. Der Server erlaubt nur eine sprechende Person gleichzeitig, prüft die Reihenfolge und verhindert doppelte Audioteile. Funktexte können auf dem anderen iPhone per iOS-Sprachausgabe vorgelesen werden. Beide Empfangsschalter lassen sich separat ausschalten. Funkdaten sind zehn Minuten als kurzfristiger Übertragungspuffer abrufbar und werden im anschließenden Minutenlauf gelöscht, keine dauerhafte Mediathek. Die Funkübertragung ist transportverschlüsselt, wenn HTTPS verwendet wird, aber nicht Ende-zu-Ende-verschlüsselt.

Die native Integration verwendet Apples `PushToTalk` mit Systemkanal, Wiederherstellung und kurzlebigen Push-Tokens. Das iOS-System stellt seine Sprechtaste und Statusanzeige am oberen Bildschirmrand bzw. Sperrbildschirm bereit; eine bestimmte Dynamic-Island-Platzierung kann die App nicht erzwingen. Audio wird ausschließlich nach tatsächlicher Sprechtastenbetätigung aufgenommen. Die App aktiviert kein fremdes Mikrofon.

### Hintergrund einrichten

1. Beide Apps mit einem Profil signieren, das `com.apple.developer.push-to-talk`, `aps-environment` und die bisherigen Capabilities erlaubt. Die Widget-Erweiterung mit signieren; App Group beibehalten.
2. Im Apple-Entwicklerkonto Push Notifications und Push to Talk für die Bundle-ID aktivieren. Der verwendete Signaturdienst muss diese Capabilities im Profil erhalten. Ein Zahlungsbeleg stellt keine APNs-Schlüssel bereit.
3. In `rjapp_config.json` den bestehenden `apns`-Abschnitt mit `enabled`, `team_id`, `key_id`, `private_key_file` und passender `bundle_id` einrichten. Der `.p8`-Schlüssel gehört zum selben Apple-Team wie die Signatur. Die Release-App registriert Produktions-Tokens. `curl` mit HTTP/2 und `openssl` müssen auf dem Server vorhanden sein.
4. Server neu starten, beide Apps einrichten und dem Funkkanal beitreten. Unter Walkie-Talkie werden Systemkanal und Serverkonfiguration getrennt angezeigt. „Konfiguriert“ ist kein erfolgreicher Empfangstest. Den tatsächlichen Empfang mit gesperrtem iPhone und anschließend mit einem Telefonanruf als Unterbrechung auf beiden echten Geräten prüfen.

Der Server verwendet `apns-push-type: pushtotalk`, Topic `<Bundle-ID>.voip-ptt`, Priorität 10 und Ablaufzeit 0. Push startet die Empfangssitzung; die App wartet auf die von iOS aktivierte Audiositzung, bevor sie Audio abspielt. Ohne passendes Profil/APNs funktioniert der Austausch bei geöffneten Apps. iOS gewährt keine beliebige permanente Hintergrundlaufzeit. Live-Gerätetests und Tests mit dem persönlichen Signierprofil sind nicht durch den unsigned GitHub-Build abgedeckt.

## Medienstruktur und Backup

Die „Cloud“ ist euer eigener Python-Server. Es wird kein iCloud-Konto benötigt.

```text
rjlove_data/
  rjlove.sqlite3
  media/duftpost/robin/2026/10/<Aufnahme-UUID>/
    original.m4a
    edit-0002-<Bearbeitungs-UUID>.m4a
    metadata.json
  media/duftpost/raphaela/2026/10/<Aufnahme-UUID>/...
  backups/RJ-Love-<UTC-Zeit>-<Kennung>.tar.gz
```

`metadata.json` enthält Titel, Wellenform, Bewertungen, Reaktionen und ein Verzeichnis aller Versionen. Die Datenbank ist die verbindliche Zuordnung. Vorhandene 2.1-Audio-BLOBs werden beim Serverstart in diese Struktur übertragen; Zugangsdaten, IDs und Bewertungen bleiben erhalten. Dateien werden atomar geschrieben. Ein Prozess- und Thread-Lock schützt Medienänderungen und Backups. Das Speicherlimit zählt alle aufbewahrten Audiofassungen. Löschen entfernt das gesamte Aufnahmeverzeichnis; bereits extern gesicherte Backups bleiben davon unberührt.

Im laufenden Server in die Konsole `backup` eingeben oder separat ausführen:

```sh
python3 rj_love_server.py --backup
python3 rj_love_server.py --backup /sicherer/pfad/RJ-Love.tar.gz
```

Das Archiv enthält einen konsistenten SQLite-Snapshot, alle Mediendateien, `rjapp_config.json` und `BACKUP.json`. Es enthält private Daten und Zugangskonfiguration, deshalb an einem geschützten Ort aufbewahren. Das Archiv ist nicht zusätzlich verschlüsselt. Ein extern referenzierter APNs-Privatschlüssel wird nicht automatisch kopiert und muss separat gesichert werden. Wiederherstellen: Server stoppen, Konfiguration und `rjlove_data` gemeinsam zurückkopieren, `data_directory` kontrollieren, Server starten. Für regelmäßige Backups diesen Befehl im eigenen Server-Scheduler eintragen.
