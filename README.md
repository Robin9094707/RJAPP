# RJ Love

RJ Love ist eine private, native iOS-Partner-App für Robin und Raphaela. Sie kombiniert eine „Wo ist?“-inspirierte Partnerkarte mit AlarmKit-Weckrufen, gemeinsamen Notizen, Erinnerungen, ausgewählten Kalenderterminen, einer privaten Momentgalerie, Health-Zusammenfassungen, Widgets und Live-Aktivitäten. Alle gemeinsamen Daten liegen auf dem eigenen Python-Server.

## Projektaufbau

```text
App/                 Native SwiftUI-App und Apple-Dienste
Shared/              Modelle, AlarmKit-Metadaten und App Intents
WidgetExtension/     Zwei Home-Screen-Widgets und zwei Live Activities
Backend/             Einzeldatei-Python-Server ohne Python-Pakete
Tests/               Backend-Integrationstests
Scripts/             Projekt-/Build-Validierung
.github/workflows/   Unsigned-IPA-Build
project.yml          XcodeGen Source of Truth
```

## Python-Server starten

Voraussetzung: Python 3.11 oder neuer. Es werden keine `pip`-Pakete benötigt.

1. `Backend/rj_love_server.py` in deine CubeCoders-Instanz kopieren.
2. Als Startdatei `rj_love_server.py` und als Interpreter `python3` wählen.
3. Einmal starten. Das Skript erzeugt neben sich `rjapp_config.json` und beendet sich absichtlich.
4. In der erzeugten Datei Benutzername, Passwort, Port und auf Wunsch Speicherlimit ändern.
5. Erneut starten. Standardmäßig lauscht der Server auf `0.0.0.0:8765`.
6. In RJ Love `http://SERVER-IP:8765` oder die öffentliche HTTPS-Domain eingeben.

Die erzeugte Konfiguration enthält bereits zufällige, starke Startpasswörter. Sie kann direkt verwendet oder geändert werden. `storage_limit_mb: 0` bedeutet unbegrenzt. Daten landen standardmäßig in `Backend/rjlove_data/rjlove.sqlite3`; WAL sorgt dafür, dass Neustarts und kurze Unterbrechungen nichts verlieren.

Die iOS-App hält zusätzlich einen durch iOS-Dateischutz abgesicherten Offline-Snapshot vor. Bereits synchronisierte Karten-, Status- und Gemeinschaftsdaten bleiben dadurch nach einem App- oder Serverneustart sichtbar. Herzgedanken werden bei fehlender Verbindung lokal vorgemerkt und beim nächsten erfolgreichen Sync zuverlässig nachgesendet.

### HTTPS

Empfohlen ist ein Reverse Proxy (NGINX, Caddy, Cloudflare Tunnel) vor dem internen HTTP-Port. Alternativ kann der Server selbst TLS aktivieren:

```json
"tls": {
  "enabled": true,
  "certificate_file": "/pfad/fullchain.pem",
  "private_key_file": "/pfad/privkey.pem"
}
```

HTTP darf nur in einem vertrauenswürdigen lokalen Netz verwendet werden, weil Zugangsdaten und private Inhalte sonst auf dem Transportweg mitgelesen werden könnten.

### Native Push-Mitteilungen (optional)

Ohne Push funktioniert RJ Love weiterhin über Vordergrund-Sync, Standortereignisse und von iOS gewährte Hintergrundläufe. Für APNs werden zusätzlich benötigt:

- ein Signatur-/Provisioningprofil mit Push Notifications für `eu.rjuhas.rjlove`;
- eine Apple-APNs-Schlüsseldatei (`.p8`), Team-ID und Key-ID;
- `curl` mit HTTP/2 und `openssl` auf dem Server;
- passende Werte im `apns`-Block der Konfiguration.

Die Python-Datei erzeugt das ES256-Provider-JWT selbst und benötigt dafür keine Python-Bibliothek. APNs-Schlüssel gehören niemals ins Repository.

## Unsigned IPA bauen

GitHub → **Actions** → **Build RJ Love unsigned IPA** → **Run workflow**. Der macOS-26-Runner verwendet Xcode 26.5 und XcodeGen. Nach Erfolg liegt `RJ-Love-unsigned.ipa` im Artifact `RJ-Love-unsigned-IPA`. Bei einem Compilerfehler wird `RJ-Love-build.log` als eigenes Artifact gesichert.

Die IPA ist absichtlich unsigniert. Beim späteren Signieren müssen die eingebettete Widget-Extension und ihre App-Group mit signiert werden. Push, HealthKit, App Groups und WLAN-Information funktionieren nur, wenn das verwendete Provisioningprofil die jeweiligen Entitlements akzeptiert.

## Datenschutz

- kein Analytics-SDK und keine Drittanbieter-Abhängigkeit;
- Passwort und Sitzungstoken im iOS-Schlüsselbund;
- freiwillige Freigaben einzeln schaltbar;
- Health teilt nur Schritte, Schlafminuten und den app-eigenen Dauer-Score;
- alle gemeinsamen Einträge sind in der App löschbar;
- einzelne Galeriekommentare sind mit Bestätigung löschbar;
- keine Zugangsdaten, Zertifikate oder persönlichen Serverdaten im Git-Repository.

Weitere Details stehen in [FEATURES.md](FEATURES.md), [BUILD-NOTES.md](BUILD-NOTES.md) und [PRIVACY.md](PRIVACY.md).
