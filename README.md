# RJ Love

Privater iOS-Raum für zwei: gemeinsames Kino, Nachrichten, Momente, Karte, Widgets und Alltag.

**Aktuelle App: 4.3.0 (430), Server 4.3.0.** Frei gestaltbare Startseite und Navigation, HomeKit mit Vollbild und Kamera-Audio, Live-Kamera im AirPlay-Dashboard, gemeinsame Dokumente und automatische Einstellungssicherung: [Release 4.3.0](RELEASE-4.3.0.md).

## Neu: Unser Kino

- Plex standardmäßig als gemeinsamer Abend: beide steuern, der zweite iPhone-Stream ist optional.
- Plex-Kino-Automatik erkennt zugängliche Sitzungen des verbundenen Profils auf dem gewählten Server.
- AirPlay und native Plex-Hintergrundwiedergabe, Film- und Geräteinformationen.
- Kinozeit, Filmverlauf und bestätigtes Zurücksetzen für beide.
- Native YouTube-Suche ohne eigenen API-Schlüssel; Anmeldung und direkte YouTube-Wiedergabe innerhalb der App. Google kann eingebettete Anmeldungen und Videos einschränken.
- Optional Apple Home: eigene und geteilte Häuser auswählen, Kameravorschauen und Live-Ansicht. HomeKit muss beim Signieren erhalten bleiben.
- Gläserne Kino- und Zuhause-Karten auf dem Dashboard.

Plex-Fernsteuerung setzt einen kompatiblen Empfänger und passende Serverrechte voraus. Der Schlaftimer pausiert die Wiedergabe; er schaltet Apple TV nicht aus. Echte Dienstverbindungen und die konkrete Signierung brauchen eine Geräteprüfung.

## Aktualisieren und Daten behalten

Server stoppen, Konfiguration und Datenordner sichern, nur `Backend/rj_love_server.py` ersetzen und neu starten. Konfiguration, Konto-IDs und Datenpfad unverändert behalten. Die neue IPA mit demselben Signierteam, derselben Bundle-ID und identischer App Group über die bestehende App installieren. Die App nicht löschen.

Die Datenbank wird ausschließlich additiv erweitert. App und Server benötigen jetzt mindestens 4.3.0. Alte Apps erhalten die Update-Ansicht. Beide müssen aus demselben Komplettpaket aktualisiert werden.

## Installation

Python 3.11 oder neuer, HTTPS für den Fernzugriff. Der erste Start erzeugt die Konfiguration und zufällige Startpasswörter. Bestehende Installationen verwenden ihre vorhandene Konfiguration.

```sh
python3 Backend/rj_love_server.py
```

Details: [Installation](INSTALLATION.md), [Funktionen](FEATURES.md), [Datenschutz](PRIVACY.md).

## Build

GitHub Actions baut auf `main` App und Widgets als unsignierte IPA und liefert die einzelne Serverdatei sowie ein Komplettpaket. Sieben schnelle HTTP-Prüfungen und ein kurzer Swift-Layouttest prüfen Kino, Dokumente, Einstellungen und Migration. Keine zusätzlichen Simulator-Jobs. Compiler- und Paketprüfung bleiben erhalten.

YouTube verwendet [YouTubeKit](https://github.com/b5i/YouTubeKit), fest auf eine Revision gebunden; der Lizenztext liegt in den App-Ressourcen. Google-/YouTube-Anmeldedaten bleiben auf dem jeweiligen iPhone. Plex-Brücken speichern Zugangstokens ausschließlich befristet im Serverspeicher.
