# RJ Love Python Server

Start: `python3 rj_love_server.py`

Der erste Start erzeugt `rjapp_config.json` und endet. Datei bearbeiten, danach erneut starten. Keine Installation mit `pip` erforderlich. Datenbank, WAL-Dateien und Logs landen im konfigurierten `data_directory`.

Healthcheck: `GET /health`

Konfiguration per anderer Datei ist optional über die Umgebungsvariable `RJLOVE_CONFIG=/absoluter/pfad/config.json` möglich. Für CubeCoders genügt normalerweise die automatisch neben dem Skript erzeugte Datei.
