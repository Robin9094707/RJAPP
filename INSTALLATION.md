# App-Update 4.2.1

Nur die neue IPA über die bestehende App installieren. Server 4.2.0, Konfiguration und Datenordner unverändert behalten. Details: [Release 4.2.1](RELEASE-4.2.1.md).

# RJ Love installieren und aktualisieren

## Bestehende Installation auf 4.2.0 aktualisieren

1. Python-Server stoppen. Vorhandene Konfiguration und kompletten Datenordner sichern.
2. Nur `rj_love_server.py` ersetzen. Vorhandene Konto-IDs, Datenpfad, Passwörter und Serveradresse beibehalten.
3. Server wie bisher starten. Die Datenbank bekommt nur zusätzliche Tabellen.
4. Beide iPhones mit der neuen IPA aktualisieren. Dieselbe Bundle-ID und dasselbe Signierteam verwenden; die bestehende App nicht löschen.
5. Haupt-App und eingebettete Widget-Extension zusammen signieren. Die bereits funktionierende App Group in beiden erhalten; die aktuelle Projektvorgabe ist `group.dfbc88d056a46f1b.1`.

App und Server müssen beide 4.2.0 sein. Alte Apps erhalten vor Änderungen einen Updatehinweis. Ein Wechsel des Signierteams oder der Bundle-ID kann den Zugriff auf Keychain und lokale App-Daten verändern.

## Neue Installation

Python 3.11+ verwenden:

```sh
python3 rj_love_server.py
```

Der erste Start erzeugt `rjapp_config.json` mit zufälligen Startpasswörtern und beendet sich. Konfiguration vertraulich aufbewahren, zwei eigene Zugänge einrichten und anschließend erneut starten. Für Fernzugriff HTTPS über den bestehenden Reverse Proxy einrichten. Die Konfigurationsdatei niemals veröffentlichen.

Die laufende Konsole unterstützt `help`, `reload` und `reset BENUTZERNAME`. Nach Credential-Änderungen ist eine Neuanmeldung nötig. Bestehende interne Konto-IDs nicht ändern.

## Plex und AirPlay

Unter „Unser Kino → Plex“ anmelden, Profil entsperren und den Server auswählen. Die Kino-Automatik benötigt eine sichere von Plex bestätigte Verbindung und Zugriff auf die Sitzungsübersicht. Sie gilt bis zu zwölf Stunden und wird beim Öffnen erneuert. Nach einem Python-Neustart RJ Love einmal öffnen.

Beide sind standardmäßig im gemeinsamen Kino. Auf dem zweiten Gerät startet „Auch auf diesem iPhone abspielen“ einen eigenen Stream. Für einen gemeinsam betrachteten Fernseher „Ich schaue am selben Bildschirm mit“ aktivieren. Diese Bestätigung zählt nur zusammen mit einer frischen tatsächlichen Wiedergabequelle.

AirPlay über den iOS-Gerätewähler starten. Externe Plex-Geräte müssen Companion-Befehle unterstützen; neuere mobile Apps können diese ablehnen. Der Schlaftimer pausiert bzw. beendet die Wiedergabe, schaltet Apple TV jedoch nicht aus.

## YouTube

YouTube aktivieren. Suche ohne API-Schlüssel direkt in der App verwenden. Für Abos zuerst über „Anmelden“ in der eingebauten YouTube-Ansicht anmelden und dann „Meine Abos“ laden. Google kann eine eingebettete Anmeldung blockieren. Direkte YouTube-Wiedergabe und gemeinsamer eingebetteter Player können unterschiedliche Kontoberechtigungen haben.

## Apple Home

Auf der Startseite „HomeKit aktivieren“, iOS-Zugriff erlauben und ein eigenes oder geteiltes Zuhause auswählen. Das Haus muss vorher in Apple Home sichtbar sein. Für Kameras die erforderlichen Home-Freigaben und gegebenenfalls Fernzugriff über die Steuerzentrale einrichten. Beim Signieren `com.apple.developer.homekit` erhalten. Fehlt es im installierten Profil, zeigt die App einen Hinweis. Kameraansichten werden nicht zum RJ-Server hochgeladen.

## Weitere Berechtigungen

Widgets benötigen identische erreichbare App Groups. HealthKit, APNs, AlarmKit und HomeKit benötigen passende Signierung und iOS-Zustimmung. Background-Audio ist für laufende native Wiedergabe vorgesehen; iOS gewährt keinen beliebigen Dauerbetrieb. Kamera- und eigene TV-Dashboard-Ansichten stoppen bei gesperrtem iPhone.

Bark-/Push-Einstellungen, eigene Serveradresse und alle bisherigen Konfigurationswerte übernehmen. Die vollständigen Funktionsgrenzen und Änderungen stehen in [Release 4.2.0](RELEASE-4.2.0.md).
