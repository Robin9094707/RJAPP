# RJ Love installieren und aktualisieren

**Aktuell:** App **9.0.1 (Build 901)** mit Python-Server **9.0.0** und Protokoll **5**.

## Bestehende Installation aktualisieren

1. **App 9.0.0 → 9.0.1:** Die Python-Serverdatei bleibt unverändert. Die neue **unsigned IPA** auf beiden iPhones jeweils mit dem eigenen Zertifikat signieren und installieren.
2. **Server älter als 9.0.0:** Server stoppen, `rjapp_config.json` und den Datenordner sichern. Nur `Backend/rj_love_server.py` auf 9.0.0 aktualisieren und wieder starten. Vorhandene Konten, Passwörter, Datenbank, Datenpfade und Serveradresse beibehalten.
3. Bei einer Aktualisierung **auf derselben App-Installation** Bundle-ID und Signierungsidentität möglichst nicht ändern. Ein Team- oder Bundle-ID-Wechsel kann iOS-Keychain-Zugriff und lokale Daten verändern; ein Wechsel kann eine separate App erzeugen.
4. Die Widget-Erweiterung ist ein eigenes iOS-Target. Haupt-App und Extension jeweils mit **passenden App-IDs, Provisioning-Profilen und identischer erlaubter App Group** signieren.
5. Nach Installation **RJ Love → Widgets verbinden → Widget-Daten und Anzeige aktualisieren** auf beiden Geräten ausführen. Für Hintergrundupdates iOS-Berechtigungen und Hintergrundaktualisierung prüfen. Den Zeitpunkt bestimmt weiterhin iOS.

### Die zwei vorhandenen Zertifikatsprofile

| Gerät | Haupt-App-Bundle-ID im bereitgestellten Profil | Zu verwendende App Group |
| --- | --- | --- |
| iPhone 17 Pro Max | `app.lake6191.velvet1751` | `group.dfbc88d056a46f1b.1` |
| iPhone 14 Pro | `app.andromeda203.garnet9008` | `group.4d9963ba648cf299.1` |

Die gleiche **unsigned IPA** enthält den Code für beide Gruppen; er wählt zur Laufzeit nur einen durch die Signierung erlaubten Container. **Die Widget-Erweiterung benötigt trotzdem ein eigenes, korrektes Extension-Profil**, das in den beiden bereitgestellten Zertifikats-ZIPs nicht enthalten ist. Eine ID-Eingabe innerhalb der App kann keine iOS-Berechtigungen freischalten. Keine privaten Zertifikate, `.p12`-Dateien oder Passwörter ins GitHub-Repository hochladen.

[Änderungen in 9.0.1](RELEASE-9.0.1.md) · [GitHub Actions](https://github.com/Robin9094707/RJAPP/actions).

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

Bark-/Push-Einstellungen, eigene Serveradresse und alle bisherigen Konfigurationswerte übernehmen. Die vollständigen Funktionsgrenzen und Änderungen stehen in [Release 4.3.0](RELEASE-4.3.0.md).


## Dokumente und automatische Sicherung

Profil → Gemeinsame Dokumente: Dateien hochladen, verschachtelte Ordner anlegen und Ordner persönlich favorisieren. Ein Tipp auf eine Bark-Upload-Mitteilung öffnet den richtigen Ordner und markiert die Datei. Reverse-Proxys müssen `/v1/documents` samt Unterpfaden und `/v1/settings` weiterleiten.

Unter Profil → Automatische Sicherung den ersten erfolgreichen Abgleich prüfen. Nach Neuanmeldung werden portable Einstellungen automatisch wiederhergestellt; Betriebssystem-Berechtigungen und lokale Dateien/Entwürfe bleiben gerätegebunden. Startseite und bis zu fünf persönliche Navigationstasten: Profil → Startseite & Navigation. Die Kamera zum TV-Dashboard unter AirPlay gestalten als Widget hinzufügen und auswählen.
