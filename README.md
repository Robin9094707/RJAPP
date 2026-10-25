# RJ Love

Privater iOS-Raum für zwei: gemeinsames Kino, Nachrichten, Momente, Karte, Widgets und Alltag.

**Aktuelle App: 4.2.1 (421).** Der Server bleibt bei 4.2.0. Momente mit Bestätigung löschen, direkter Kino-Tab und eine ausblendbare native Plex-Leiste: [Release 4.2.1](RELEASE-4.2.1.md).

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

Die Datenbank wird ausschließlich additiv erweitert. Die App benötigt mindestens Server 4.2.0; der Server akzeptiert Apps ab 4.2.0. Beim Update von App 4.2.0 auf 4.2.1 muss der Server nicht ersetzt werden.

## Installation

Python 3.11 oder neuer, HTTPS für den Fernzugriff. Der erste Start erzeugt die Konfiguration und zufällige Startpasswörter. Bestehende Installationen verwenden ihre vorhandene Konfiguration.

```sh
python3 Backend/rj_love_server.py
```

Details: [Installation](INSTALLATION.md), [Funktionen](FEATURES.md), [Datenschutz](PRIVACY.md).

## Build

GitHub Actions baut auf `main` App und Widgets als unsignierte IPA und liefert die einzelne Serverdatei sowie ein Komplettpaket. Vier gezielte Backend-Prüfungen decken die neuen Kinoabläufe ab. Alte Tests und zusätzliche Simulator-Jobs wurden entfernt. Compiler- und Paketprüfung bleiben erhalten.

YouTube verwendet [YouTubeKit](https://github.com/b5i/YouTubeKit), fest auf eine Revision gebunden; der Lizenztext liegt in den App-Ressourcen. Google-/YouTube-Anmeldedaten bleiben auf dem jeweiligen iPhone. Plex-Brücken speichern Zugangstokens ausschließlich befristet im Serverspeicher.
