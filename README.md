# RJ Love

Privater iOS-Raum für zwei: gemeinsames Kino, Nachrichten, Momente, Karte, Widgets und Alltag.

**Aktuelle App: 5.0.0 (500), Server 5.0.0.** Neu gestaltet mit durchgängigem Liquid Glass, flüssigen Animationen, neuem Duftstudio-Recorder, Kino-AirPlay mit Überblendungen, Live-Vorschau und Herz-Signalen, spürbar flüssigerer Synchronisierung sowie automatischer IPA-Bereitstellung durch den Server: [Release 5.0.0](RELEASE-5.0.0.md).

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

Die Datenbank wird ausschließlich additiv erweitert. App 5.0.0 benötigt Server 5.0.0. Server 5.0.0 zeigt älteren Apps (4.3.x) ihr eingebautes Update-Fenster; der IPA-Download und die Feather-Quelle bleiben für sie erreichbar. Eine `RJ-Love…ipa` neben der Serverdatei (oder in `rjlove_data/updates/`) wird automatisch als neues Release bereitgestellt.

## Installation

Python 3.11 oder neuer, HTTPS für den Fernzugriff. Der erste Start erzeugt die Konfiguration und zufällige Startpasswörter. Bestehende Installationen verwenden ihre vorhandene Konfiguration.

```sh
python3 Backend/rj_love_server.py
```

Details: [Installation](INSTALLATION.md), [Funktionen](FEATURES.md), [Datenschutz](PRIVACY.md).

## Build

GitHub Actions baut auf `main` und für Pull Requests App und Widgets als unsignierte IPA und liefert die einzelne Serverdatei sowie ein Komplettpaket. Fünfzehn schnelle HTTP-Prüfungen sowie Swift-Tests für Layout und Notfallübergabe prüfen Kino, Dokumente, Einstellungen und Migration. Keine zusätzlichen Simulator-Jobs. Compiler- und Paketprüfung bleiben erhalten.

YouTube verwendet [YouTubeKit](https://github.com/b5i/YouTubeKit), fest auf eine Revision gebunden; der Lizenztext liegt in den App-Ressourcen. Google-/YouTube-Anmeldedaten bleiben auf dem jeweiligen iPhone. Plex-Brücken speichern Zugangstokens ausschließlich befristet im Serverspeicher.

