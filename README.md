# RJ Love

Privater iOS-Raum für zwei: gemeinsames Kino, Nachrichten, Momente, Karte, Widgets und Alltag.

**Aktueller Stand: iOS-App 9.0.1 (Build 901), Python-Server 9.0.0, Protokoll 5.**

- **[9.0.1 – Widgets und Hintergrund-Sync](RELEASE-9.0.1.md):** erkennt die zugelassene App Group der jeweiligen Signierung automatisch und aktualisiert Widget-Daten bei von iOS erlaubten Hintergrundläufen.
- **[9.0.0 – Tagebuch 2.0 und Gruppenchat](RELEASE-9.0.0.md):** Rückfragen, Stimmung, Sprach-Tagebuch, ChatGPT-Gruppenchat mit Sprachnachrichten und Websuche.
- Frühere Änderungen: [8.0.0](RELEASE-8.0.0.md) · [7.0.0](RELEASE-7.0.0.md).

**Ein Quellcode-Stand für beide iPhones:** Die gleiche **unsigned IPA** wird auf jedem Gerät separat mit dessen Zertifikat signiert. Für Widgets muss auch die eingebettete Erweiterung ein passendes Profil und dieselbe erlaubte App Group wie die Haupt-App erhalten.

## Neu: Unser Kino

- Plex standardmäßig als gemeinsamer Abend: beide steuern, der zweite iPhone-Stream ist optional.
- Plex-Kino-Automatik erkennt zugängliche Sitzungen des verbundenen Profils auf dem gewählten Server.
- AirPlay und native Plex-Hintergrundwiedergabe, Film- und Geräteinformationen.
- Kinozeit, Filmverlauf und bestätigtes Zurücksetzen für beide.
- Native YouTube-Suche ohne eigenen API-Schlüssel; Anmeldung und direkte YouTube-Wiedergabe innerhalb der App. Google kann eingebettete Anmeldungen und Videos einschränken.
- Optional Apple Home: eigene und geteilte Häuser auswählen, Kameravorschauen und Live-Ansicht. HomeKit muss beim Signieren erhalten bleiben.
- Kino- und Zuhause-Karten auf dem Dashboard.

Plex-Fernsteuerung setzt einen kompatiblen Empfänger und passende Serverrechte voraus. Der Schlaftimer pausiert die Wiedergabe; er schaltet Apple TV nicht aus. Echte Dienstverbindungen und die konkrete Signierung brauchen eine Geräteprüfung.

## Aktualisieren und Daten behalten

**Von App 9.0.0 auf 9.0.1:** Der Server bleibt 9.0.0; du musst die Python-Datei nicht ersetzen. Die bestehende App mit derselben Bundle-ID und derselben Signierungsidentität aktualisieren, wenn die lokalen Daten erhalten bleiben sollen. Die App nicht vorher löschen.

**Von älteren Serverständen:** Server stoppen, Konfiguration und Datenordner sichern und ausschließlich `Backend/rj_love_server.py` aus dem passenden Komplettpaket ersetzen. Konto-IDs, Datenpfad und Konfiguration behalten. App 9.0.1 benötigt mindestens Server 9.0.0. Ältere Apps erhalten den vorgesehenen Updatehinweis. Eine `RJ-Love…ipa` neben der Serverdatei (oder in `rjlove_data/updates/`) kann als neues Release bereitgestellt werden. Details: [Installation und Signierung](INSTALLATION.md).

## Installation

Python 3.11 oder neuer, HTTPS für den Fernzugriff. Der erste Start erzeugt die Konfiguration und zufällige Startpasswörter. Bestehende Installationen verwenden ihre vorhandene Konfiguration.

```sh
python3 Backend/rj_love_server.py
```

Details: [Installation](INSTALLATION.md), [Funktionen](FEATURES.md), [Datenschutz](PRIVACY.md).

## Build

GitHub Actions baut bei Änderungen auf `main`, auf dem Release-Entwicklungszweig und bei Pull Requests eine **unsignierte IPA samt Widget-Erweiterung**. Die Aktion überprüft den Projektaufbau, die Server-Tests, Swift-Smoke-Tests und das IPA-Paket; sie veröffentlicht die IPA sowie ein separates Komplettpaket mit der Serverdatei. Das Kompilieren bestätigt **nicht** die korrekte Gerätesignierung oder Push-/Widget-Funktion auf echten iPhones.

[GitHub Actions – neueste Builds](https://github.com/Robin9094707/RJAPP/actions) · [Versionshinweise](RELEASE-9.0.1.md).

YouTube verwendet [YouTubeKit](https://github.com/b5i/YouTubeKit), fest auf eine Revision gebunden; der Lizenztext liegt in den App-Ressourcen. Google-/YouTube-Anmeldedaten bleiben auf dem jeweiligen iPhone. Plex-Brücken speichern Zugangstokens ausschließlich befristet im Serverspeicher.

