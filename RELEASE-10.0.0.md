# RJ Love 10.0.1 (1001) · Absturz beim Öffnen behoben

**Bitte 10.0.0 sofort durch 10.0.1 ersetzen.** Der Server bleibt 10.0.0; die Python-Datei muss nicht erneut ersetzt werden.

- Behoben: 10.0.0 stürzte unter iOS 27.3 direkt beim Öffnen ab. Apples `CLMonitor` brach beim Anlegen der Abfahrts-Geofence mit einer internen Prüfung ab. Die Geofence nutzt jetzt die bewährte Region-Überwachung von `CLLocationManager`; sie weckt die App weiterhin auch nach dem Wegwischen.
- Behoben: Ein normaler Start wurde als Hintergrundstart gezählt, weil iOS den App-Zustand vor dem Verbinden der Szene noch nicht als aktiv meldet. Jetzt wird erst nach dem Start entschieden.
- Neu in CI: Ein Starttest öffnet die App im iOS-Simulator gegen den echten Server, schickt sie in den Hintergrund und zurück und schlägt bei jedem Absturz fehl.

---

# RJ Love 10.0.0 (1000) · Live-Daten und neue Hintergrund-Engine

Großes Update. **App und Python-Server gemeinsam aktualisieren**: App 10.0.0 benötigt Server 10.0.0, Server 10.0.0 erwartet App 10.0.0. Protokoll 5 bleibt, die Datenbank ergänzt zwei Tabellen automatisch. Konten, Daten, Serveradresse und Konfiguration bleiben erhalten.

## Neu

### Live-Daten & Nerd-Infos
Neue Ansicht, erreichbar über die Partnerkarte auf der Startseite („Live-Daten“), das Partnerprofil und Einstellungen → Diagnose.

- Für **beide** iPhones sekundengenau: *Akku übertragen vor …*, *Standort übertragen vor …*, *Health übertragen vor …*, *letzte Meldung*. Die Farbe zeigt, wie frisch die Daten sind: grün unter 5 Minuten, orange unter 30 Minuten.
- **Wodurch die Daten kamen**: Live-Herzschlag, Akkuänderung, Standortänderung, Geofence verlassen, Besuch, stiller Push, Health-Hintergrundlieferung, iOS-Hintergrundaktualisierung, Wartungsfenster, App verlassen.
- Nerd-Daten: Temperaturzustand, Netz (WLAN/Mobilfunk, Hotspot, Datensparen), Stromsparmodus, Upload-Latenz, Meldungen in 24 h, Median-Abstand und längste Lücke, Prozessstarts, Weckungen, Standortrecht und Genauigkeit, Tempo, Höhe, Alter des GPS-Fix, Geofence-Status, Live-Modus, Push-Registrierung, iOS-Version, Modellkennung, App-Build, Uptime, freier Speicher, verfügbarer RAM, Audioausgang, Zeitzone.
- **Akkuverlauf der letzten 24 Stunden** für beide als Diagramm (jeder Punkt ist eine echte Meldung) und ein Diagramm der Weckquellen.
- **Weckprotokoll** dieses iPhones (bis 150 Einträge, nur lokal).
- Die Startseite zeigt auf der Partnerkarte live „Akku übertragen vor 42 s · über Live-Herzschlag“.

### Hintergrund-Engine
Alles, was iOS einer seitengeladenen App erlaubt, ist jetzt kombiniert. Jede Weckung schickt einen kleinen **Herzschlag** an den neuen Endpoint `/v1/presence/heartbeat` (Akku, Ladezustand, Stromsparmodus, Netz, Telemetrie, optional Position), ohne Health- oder Statuswerte zu überschreiben.

| Weckquelle | Funktioniert nach Wegwischen? | Hinweis |
| --- | --- | --- |
| **Live-Modus** (Hintergrund-Standort hält die App aktiv) | – | Akkuänderungen in ca. 3 s, zusätzlich Herzschlag alle 1–15 min (einstellbar) |
| Standortänderung, signifikante Ortswechsel, Besuche | ja | braucht Standort „Immer“ |
| **Abfahrts-Geofence** (CLMonitor, 150 m) | ja | wird bei jeder Position neu gesetzt |
| **Stiller Push / Live-Abfrage** | nein | braucht APNs auf dem Server |
| BGAppRefresh + neues **BGProcessing-Wartungsfenster** | nein | iOS entscheidet nach Nutzung und Akku |
| **HealthKit-Hintergrundlieferung** (Schritte) | eingeschränkt | höchstens stündlich |
| Push-Mitteilungen, Mitteilungsaktionen | nein | jede Weckung meldet mit |

Ehrlich: Keine iPhone-App läuft ununterbrochen. Wirklich live ist es, solange der Hintergrund-Standort aktiv ist. Nach dem Wegwischen wecken nur Standortereignisse und der Geofence die App zuverlässig. Im Stromsparmodus pausiert iOS die Hintergrundaktualisierung.

### Live-Abfrage
„Jetzt live abfragen“ schickt dem anderen iPhone einen stillen Push (`apns-push-type: background`). Es holt in bis zu 8 Sekunden einen frischen Standort und antwortet. Die Ansicht zeigt die Antwortzeit. Ohne APNs-Schlüssel auf dem Server meldet der Server das offen. Das iPhone antwortet dann beim nächsten iOS-Fenster.

**Zu APNs:** Die `.p12` aus dem Zertifikats-ZIP ist ein **App-Signaturzertifikat**, kein Push-Schlüssel. Stille Pushes vom eigenen Server brauchen einen **APNs-Auth-Key (.p8)** desselben Apple-Teams, das die App signiert. Mit diesem Zertifikat ist das Team `Z9LJXP32VS`. Wer den Key nicht hat, nutzt alle anderen Weckquellen. Die Live-Abfrage zeigt dann „ohne APNs“.

### Design
- Karten mit Lichtkante (heller Verlauf oben), zweistufigem Schatten und dezentem Schimmer im Dunkelmodus.
- Zweiter, kühler Farbschimmer im Hintergrund, weiterhin statisch für flüssiges Scrollen.
- Akku-Ringe, Akku-Kapseln mit Ladesymbol, Zähler mit `numericText`-Übergängen, haptisches Feedback mit `sensoryFeedback`.
- Neue Klassen nutzen `@Observable` statt `ObservableObject`, Geofences nutzen `CLMonitor` statt der älteren Region-API.

## Server 10.0.0

- `POST /v1/presence/heartbeat`: Hintergrund-Meldung mit optionaler Position.
- `POST /v1/presence/ping`: Live-Abfrage per stillem Push, 30 s Abklingzeit.
- `GET /v1/presence/telemetry`: beide Presences, Meldungshistorie der letzten 24 h, Statistik und Pings.
- Jede Presence enthält jetzt `battery_reported_at`, `location_reported_at`, `health_reported_at`, `telemetry_reported_at`, `report_source`, `report_count` und `telemetry`.
- Eine Vordergrund-Meldung ohne frischen GPS-Fix behält die letzte bekannte Position samt Zeitstempel.
- Akku-Mitteilungen („braucht Strom“, „lädt jetzt“) werden auch aus Hintergrund-Meldungen ausgelöst, ohne Doppelungen bei *lädt → voll*.
- Meldungshistorie wird 7 Tage aufbewahrt (ohne Koordinaten), Pings 7 Tage.

## Installation

1. Server stoppen, `rjapp_config.json` und `rjlove_data/` sichern, nur `Backend/rj_love_server.py` ersetzen, neu starten.
2. Die unsigned IPA auf beiden iPhones wie bisher mit dem jeweiligen Zertifikat signieren und **über** die bestehende App installieren.
3. In der App unter **Live-Daten** die Checkliste „Dieses iPhone · Hintergrund-Engine“ grün machen: Standort „Immer“, genauer Standort, Hintergrund-Standort teilen, Hintergrundaktualisierung an.

Neue Berechtigung im Code: `com.apple.developer.healthkit.background-delivery`. Das Profil für das iPhone 17 Pro Max enthält sie. Falls ein anderes Profil sie nicht enthält und die Installation scheitert, beim Signieren in Feather die Entitlements des Profils verwenden.

**Keine Zertifikate, P12-Dateien, .p8-Schlüssel oder Passwörter in GitHub hochladen.**
