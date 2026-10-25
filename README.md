Aktuelles Update: [AirPlay-Bühne, schlüsselfreie YouTube-Websuche und Plex-Transcoding 4.1.0](RELEASE-4.1.0.md). App und Server müssen für dieses Update beide auf 4.1.0 stehen; bestehende Daten und Signatur-IDs behalten.

Aktuelles Update: [Unser Kino, AirPlay, YouTube und Plex 4.0.0](RELEASE-4.0.0.md). Die bisherigen Daten und Protokoll 5 bleiben erhalten. Server 4.0.0 akzeptiert weiterhin App 3.9.2/3.9.3.

Aktuelles Update: [Automatische UWB-Nahsuche und Video-Ton 3.9.3](RELEASE-3.9.3.md). Server 3.9.2 bleibt gültig. Vorhandene Daten und Bark-/ntfy-Kopplungen behalten.

# RJ Love 4.1.0

Aktuelles Update: [Direkte Bark-Links, versteckte Fotowünsche und Tastatursteuerung 3.9.1](RELEASE-3.9.1.md). Server und beide Apps gemeinsam aktualisieren; Konfiguration und Daten behalten.

Neu: BeReal-Fotokalender, Tagesrückblick, gemeinsamer Feed, Abendritual und ein aufgeräumtes Duftstudio. Die UWB-Diagnose unterscheidet fehlenden Token, Serveraustausch und tatsächliche Freigabefehler.

> Aktuell: [Version 3.1 – Fotos, Startseite, Schlafbalance und UWB](RELEASE-3.1.md). Für App 3.1 zuerst den Python-Server auf 3.1 aktualisieren; Konfiguration und Daten behalten.

# RJ Love 3.0 — Robin & Raphaela

Ein privater, nativer iOS-Raum für zwei Menschen. Version **3.1.0 (310)**, für iOS 26.1 oder neuer. Bestehende 2.1-Aufnahmen werden beim Serverstart automatisch in das neue Medienarchiv übertragen.

Die neue Wir-Seite verbindet warme Rosé-Farben, ruhige Typografie, native Liquid-Glass-Flächen und einen interaktiven Herzgedanken. Dazu kommen privater Chat mit Tagesfrage, Wunschliste, besondere Tage mit Countdown, Gefühle, Karte, Nahbereichssuche, gemeinsame Notizen, Termine, Erinnerungen und Fotomomente.

## Neu in 3.0

Messenger mit Medien und süßen Sprachnachrichten, Momente mit Video/Live Photos und Alben, lokales Duftarchiv mit Import, Playlist und Soundarten, gemeinsame Jahresplanung mit Apple Erinnerungen, exakte Herzchronik, UWB-Pfeil und private Feather-Updatequelle. Walkie-Talkie und eigene Face-ID-Sperre sind entfernt. **Update und Funktionsgrenzen: [RELEASE-3.0.md](RELEASE-3.0.md).**

## Direkt loslegen

Die vollständige Anleitung steht in **[INSTALLATION.md](INSTALLATION.md)**. Das Build-Paket enthält die unsignierte IPA, die einzelne Python-Datei und alle Anleitungen.

```sh
python3 Backend/rj_love_server.py
```

Der erste Start erzeugt `rjapp_config.json` mit zwei zufälligen Startpasswörtern und beendet sich. Lies die Passwörter und richte den Server ein, dann starte erneut. Ab dann werden Passwörter als gesalzene scrypt-Hashes gespeichert. Keine `pip`-Abhängigkeiten; Python 3.11+ genügt. Für Internetbetrieb HTTPS konfigurieren.

## Zwei unabhängige Zugänge

Standardkonten: `robin` und `raphaela`. Eine neue Anmeldung beendet atomar die vorherige Sitzung desselben Kontos und entfernt deren Push- und Nahbereichstokens. Das andere Konto bleibt angemeldet. In **Mehr → Meinen Zugang ändern** können beide ihren eigenen Benutzernamen und ihr Passwort ändern. Danach ist eine Neuanmeldung nötig.

Die laufende Serverkonsole versteht:

```text
help
reset robin
reset raphaela
reload
```

`reset` erzeugt ein starkes neues Passwort und zeigt es einmal in der lokalen Konsole an. `reload` übernimmt geänderte Zugangsdaten aus der JSON-Datei und widerruft Sitzungen betroffener Konten. Serverparameter wie Port oder TLS werden erst nach einem Neustart übernommen. Alternativ: Server stoppen und `python3 rj_love_server.py --reset-user robin` ausführen; das Passwort wird verdeckt abgefragt.

## Was enthalten ist

| Bereich | Funktion |
| --- | --- |
| Wir | Herzgedanken, Partnerstatus, Akku/Bewegung, Schnellaktionen, gemeinsame Zeit |
| Für uns | Privater Chat, Tagesfragen, Wünsche mit Erledigt-Status, Countdown, Gefühle |
| Gemeinsamer Alltag | Notizen, Erinnerungen, gemeinsame Termine; einzelne Termine bestätigt in Apple Kalender übernehmen |
| Momente | Gemeinsame Fotogalerie, Kommentare und Reaktionen |
| Karte | Freiwilliger Standort, Orte/Geofences, Bewegung, Entfernung |
| Dich finden | Nearby Interaction: UWB-Entfernung und Richtung bei verfügbarer Hardware/Signalqualität |
| Health | Schritte, Weg, Aktivenergie, Trainingsminuten, Etagen, Schlaf, Puls, Ruhepuls, HRV, SpO₂ und Atmung |
| Widgets | Herzgedanke, Partnerstatus, Wohlgefühl, Unsere Zeit sowie drei Sperrbildschirm-Formate |
| Live-Aktivitäten | Sperrbildschirm, Dynamic Island, Weckrufe; optionale APNs-Aktualisierung |
| Schutz | Keychain, einzelne Freigaben, scrypt-Passwörter, Sitzungsaustausch |

## Apple-Funktionen und Signierung

Die IPA wird **unsigniert** gebaut. ArcticSign/Feather muss die Haupt-App **und** die eingebettete Widget-Extension passend signieren. Ein vorhandener Zahlungsbeleg allein beschreibt nicht, welche Apple-Capabilities das Provisioningprofil freigibt.

- App Group: `group.dfbc88d056a46f1b.1` für App und Extension identisch erhalten.
- HealthKit: passendes Entitlement/Profil, danach Zustimmung in Apple Health. Die Weitergabe-Schalter starten bei einer frischen Installation eingeschaltet; iOS fragt die jeweiligen Zugriffsrechte ausdrücklich ab.
- APNs: Profil mit Push plus eigener APNs-Schlüssel/Team-ID/Key-ID auf dem Server. Die App liest Sandbox/Production aus dem installierten Provisioningprofil. APNs-Schlüssel niemals committen.
- Live-Aktivitäten: lokal möglich, Server-Aktualisierungen brauchen ActivityKit-Push-Token und APNs. iOS kann Aktualisierungen beschränken. Veraltete Zustände werden markiert.
- Widgets: iOS bestimmt Aktualisierungszeitpunkte. Der Herzknopf merkt Gedanken vor; die App sendet sie beim nächsten Sync. Keine falsche Sofort-Zustellung.
- UWB: Bei aktivierter Automatik sind beide Apps im Vordergrund ohne Öffnen der Suchansicht bereit. Bestehende Sitzungen können mit Live-Aktivität im Hintergrund fortgesetzt werden; nach vollständigem Beenden beide Apps wieder öffnen. Der Server vermittelt kurzlebige Discovery-Tokens. Es werden keine Entfernungen erfunden. Das Feature ersetzt keine Fernortung. Generationenübergreifende Funktionsprüfung muss auf den beiden realen iPhones erfolgen.
- Apple Health gibt keinen beliebigen Zugriff auf alle Daten frei. Nicht vorhandene/abgelehnte Messwerte bleiben leer. Der RJ-Schlafbalance-Wert ist ein eigener Vergleich der erfassten Schlafdauer mit acht Stunden, **kein offizieller Apple-Schlafscore**.
- Kritische Mitteilungen werden nicht angefordert. Kein künstlicher Dauerbetrieb im Hintergrund.

**Mehr → Funktionen & Signatur** zeigt unter anderem App-Group-Erreichbarkeit, APNs-Gerätetoken und UWB-Hardwarestatus.

## Mitteilungen ohne eigenes APNs

Bark ist ab 3.9 der vorausgewählte externe Push-Weg. Der Bark-Server ist direkt in der Python-Datei unter `/bark` enthalten. Jeder koppelt seinen eigenen Bark-Geräteschlüssel unter **Push & Wecker**; dort sind auch Ruhezeiten, kritische Hinweise und die ntfy-Alternative einstellbar. Beide Wege erhalten auf Wunsch des Betreibers vollständige Nachrichteninhalte und Überschriften. Bark bietet Bilder, passende Symbole und kritische Weckrufe; ntfy ausschließlich normale Hinweise. Bestehende ntfy-Konfigurationsdaten werden übernommen. Einrichtung, Zustellgrenzen und Update ohne Datenverlust: [RELEASE-3.9.md](RELEASE-3.9.md).

## Entwicklung und Build

```sh
python3 Scripts/validate_project.py
python3 -m unittest -v Tests/test_backend.py
xcodegen generate
```

GitHub Actions baut bei Änderungen an `main` und manuell. Der Workflow prüft den Server, baut die unsignierte IPA und erstellt das Komplettpaket. Drei weitere Jobs prüfen Bedienung und Layout auf iPhone SE (3. Generation), 14 Pro und 15 Plus und erzeugen echte UI-Vorschauen. Diese nutzen ausschließlich synthetische Daten in einer nur im Debug-Build vorhandenen Vorschaufunktion. Release-Builds enthalten diesen Einstieg nicht.

Der grüne Build prüft Compiler, Paketstruktur und Backend-Verträge. HealthKit, UWB, APNs, AlarmKit und die konkrete ArcticSign-Signierung müssen zusätzlich auf realen Geräten geprüft werden.


## Frühere Versionen

Die historischen Änderungslisten stehen in [RELEASE-2.2.md](RELEASE-2.2.md), [RELEASE-2.3.md](RELEASE-2.3.md) und [RELEASE-2.4.md](RELEASE-2.4.md). Für die aktuelle Installation gelten ausschließlich [INSTALLATION.md](INSTALLATION.md) und [RELEASE-3.0.md](RELEASE-3.0.md). Walkie-Talkie und die eigene Face-ID-Sperre sind in 3.0 entfernt.

