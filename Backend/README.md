# Neuer Einzeldatei-Server

`python3 rj_love_server.py` (Python 3.11+). Beim ersten Start wird die lokale Konfiguration mit zwei zufälligen Zugangsdaten erzeugt. Einstellungen prüfen, Passwörter notieren, erneut starten. Kein pip notwendig.

Vollständige Einrichtung, HTTPS, Zugänge, APNs, ntfy und Feather/ArcticSign: [INSTALLATION.md](../INSTALLATION.md).


## Medien-Update 4.0.0

Die neue Einzeldatei ergänzt nur `cinema_rooms`, `cinema_members` und `cinema_stats`. Bisherige Datenpfade, Mindest-App-Version 3.9.2 und Protokoll 5 bleiben gleich. Optionaler Google-Schlüssel/OAuth sowie HTTPS/Plex-Freigaben: siehe [RELEASE-4.0.0.md](../RELEASE-4.0.0.md). Alle neuen API-Routen beginnen mit `/v1/cinema/`, native Plex-Dateitickets mit `/cinema-media/` und der Google-Callback mit `/cinema-oauth/youtube`. Diese Pfade beim HTTPS-Proxy an dieselbe Python-Anwendung weiterleiten.

Bark: Eine vorhandene `bark-public-apns.p8` im Datenordner oder `bark.private_key_file` wird weiterverwendet. Im Quelltext werden keine privaten APNs-Schlüssel mehr mitgeliefert. Fehlt die Schlüsseldatei, muss sie separat bereitgestellt werden.
