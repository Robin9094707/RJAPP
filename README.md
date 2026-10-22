# RJ Love 2.4 — Robin & Raphaela

Ein privater, nativer iOS-Raum für zwei Menschen. Version **2.4.0 (240)**, für iOS 26.1 oder neuer. Bestehende 2.1-Aufnahmen werden beim Serverstart automatisch in das neue Medienarchiv übertragen.

Die neue Wir-Seite verbindet warme Rosé-Farben, ruhige Typografie, native Liquid-Glass-Flächen und einen interaktiven Herzgedanken. Dazu kommen privater Chat mit Tagesfrage, Wunschliste, besondere Tage mit Countdown, Gefühle, Karte, Nahbereichssuche, gemeinsame Notizen, Termine, Erinnerungen und Fotomomente.

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
| Schutz | Face ID/Gerätecode, Keychain, einzelne Freigaben, scrypt-Passwörter, Sitzungsaustausch |

## Apple-Funktionen und Signierung

Die IPA wird **unsigniert** gebaut. ArcticSign/Feather muss die Haupt-App **und** die eingebettete Widget-Extension passend signieren. Ein vorhandener Zahlungsbeleg allein beschreibt nicht, welche Apple-Capabilities das Provisioningprofil freigibt.

- App Group: `group.eu.rjuhas.rjlove` für App und Extension identisch erhalten.
- HealthKit: passendes Entitlement/Profil, danach Zustimmung in Apple Health. Die Weitergabe-Schalter starten bei einer frischen Installation eingeschaltet; iOS fragt die jeweiligen Zugriffsrechte ausdrücklich ab.
- APNs: Profil mit Push plus eigener APNs-Schlüssel/Team-ID/Key-ID auf dem Server. Die App liest Sandbox/Production aus dem installierten Provisioningprofil. APNs-Schlüssel niemals committen.
- Live-Aktivitäten: lokal möglich, Server-Aktualisierungen brauchen ActivityKit-Push-Token und APNs. iOS kann Aktualisierungen beschränken. Veraltete Zustände werden markiert.
- Widgets: iOS bestimmt Aktualisierungszeitpunkte. Der Herzknopf merkt Gedanken vor; die App sendet sie beim nächsten Sync. Keine falsche Sofort-Zustellung.
- UWB: beide suchen aktiv in der geöffneten App; der Server vermittelt kurzlebige Discovery-Tokens. Es werden keine Entfernungen erfunden. Das Feature ersetzt keine Fernortung. Generationenübergreifende Funktionsprüfung muss auf den beiden realen iPhones erfolgen.
- Apple Health gibt keinen beliebigen Zugriff auf alle Daten frei. Nicht vorhandene/abgelehnte Messwerte bleiben leer. Der RJ-Schlafbalance-Wert ist ein eigener Vergleich der erfassten Schlafdauer mit acht Stunden, **kein offizieller Apple-Schlafscore**.
- Kritische Mitteilungen werden nicht angefordert. Kein künstlicher Dauerbetrieb im Hintergrund.

**Mehr → Funktionen & Signatur** zeigt unter anderem App-Group-Erreichbarkeit, APNs-Gerätetoken und UWB-Hardwarestatus.

## Mitteilungen ohne eigenes APNs

Der optionale `ntfy`-Block sendet ausschließlich allgemeine Hinweise ohne Nachrichteninhalt, Health-Werte oder Koordinaten. Dazu braucht jedes iPhone die separate ntfy-App mit eigenem privaten Topic. Das ist ein Hinweisweg zur App, kein Mechanismus, um RJ Love dauerhaft auszuführen. Empfang und Hintergrundzustellung hängen von ntfy, dessen iOS-Konfiguration und iOS ab.

## Entwicklung und Build

```sh
python3 Scripts/validate_project.py
python3 -m unittest -v Tests/test_backend.py
xcodegen generate
```

GitHub Actions baut bei Änderungen an `main` und manuell. Der Workflow prüft den Server, baut die unsignierte IPA und erstellt das Komplettpaket. Ein zweiter Job baut die Simulator-App und erzeugt echte UI-Vorschauen. Diese nutzen ausschließlich synthetische Daten in einer nur im Debug-Build vorhandenen Vorschaufunktion. Release-Builds enthalten diesen Einstieg nicht.

Der grüne Build prüft Compiler, Paketstruktur und Backend-Verträge. HealthKit, UWB, APNs, AlarmKit und die konkrete ArcticSign-Signierung müssen zusätzlich auf realen Geräten geprüft werden.


## Neu in 2.2: Euer Spielplatz

- **Duftpost**: echter M4A/AAC-Recorder mit Pegelanzeige, Pause/Fortsetzen, maximal 60 Sekunden, lokalem Entwurf, Vorschau und explizitem Teilen.
- Eigene Aufnahmen löschen, gegenseitig 1–5 Sterne in Gesamtkunstwerk/Wumms/Stil vergeben, Jury-Kommentar, Emoji-Reaktionen, Herz-Favoriten und Best-of-Sortierung.
- Audio wird authentifiziert bei Bedarf geladen. Es läuft nicht mit jedem normalen Sync über die Leitung. Roh-Audio wird nicht an Push-Anbieter geschickt. Hörtempo: Zeitlupe, Original, Turbo.
- **Sofortaufnahme-Widget** in kleinen/mittleren sowie Sperrbildschirm-Formaten. Ein Tipp öffnet die App/ggf. Geräteentsperrung und startet im sichtbaren Recorder nach Mikrofonfreigabe. Vorhandene Entwürfe werden zuerst geöffnet. Der Widget-Prozess nimmt selbst kein Audio auf.
- Aufnahme-Live-Aktivität mit Dynamic Island, falls auf dem Gerät erlaubt. Beim Wechsel in den Hintergrund wird die Aufnahme beendet und als Entwurf behalten. Keine heimliche Hintergrundaufnahme.
- Date-Roulette mit Zuhause-/Draußen-Filter, Ideen als gemeinsamen Wunsch speichern, persönliche Liebesgutscheine verschenken/einlösen und kleine „Das mag ich an dir“-Botschaften.
- Neues KI-generiertes RJ-Icon mit gläsernem Herz und einer kleinen Duftwolke. Alle iPhone-/iPad-Größen werden eingebettet. Der Paketcheck prüft die tatsächlichen Icon-Dateien und `Assets.car` in der IPA.

Für das Update die Python-Datei ersetzen und den Server neu starten. Bestehende Konten und geteilte Daten bleiben erhalten; neue Tabellen werden automatisch hinzugefügt. Die neue App und das neue Backend gehören zusammen.

## Neu in 2.2

Duftpost lässt sich ohne Namenseingabe senden und vor oder nach dem Teilen schneiden. Geführte Einrichtung ohne Fokus-Status, Freigaben zunächst eingeschaltet, Walkie-Talkie mit Apples PushToTalk, Sprachausgabe, Funk-Widget sowie versioniertes Medienarchiv mit konsistenten Backups. Einrichtung und konkrete Systemgrenzen: [RELEASE-2.2.md](RELEASE-2.2.md).

## Neu in 2.3

Automatisch passende Ansichten, Prüfung auf drei iPhone-Größen, unabhängige Hintergrund-Weckplanung, vorausgeplante AlarmKit-Wecker, Empfängerbestätigungen und ein Push-/Signatur-Diagnosezentrum. APNs-Einrichtung per `--configure-push`, Prüfung per `--check-push`. Details und Grenzen: [RELEASE-2.3.md](RELEASE-2.3.md).

## Neu in 2.4

Duftstudio mit vollständigem Archiv, Suche, Monats-/Jahreskalender, optionaler Furzkarte, echter Bilanz, 400 offline verfügbaren Spruchkombinationen und neuem Recorder. App/Server-Updateprüfung und automatische APNs-Erkennung ohne Konsolenbefehl: [RELEASE-2.4.md](RELEASE-2.4.md).
