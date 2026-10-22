> Aktuell: [Version 3.1 – Fotos, Startseite, Schlafbalance und UWB](RELEASE-3.1.md). Für App 3.1 zuerst den Python-Server auf 3.1 aktualisieren; Konfiguration und Daten behalten.

# Build 3.1.0 (310)

XcodeGen erzeugt App-, Widget- und UI-Test-Targets aus `project.yml`. Mindestversion iOS 26.1; Swift 5-Sprachmodus. GitHub Actions baut die Release-App ohne Codesigning und packt sie inklusive `PlugIns/RJLoveWidgets.appex` in die IPA. Parallel laufen echte Simulator-Bedienungstests auf iPhone SE (3. Generation), iPhone 14 Pro und iPhone 15 Plus. Kein Testjob wird als optionaler Erfolg behandelt.

## Artefakte

- `RJ-Love-unsigned-IPA`: die installierbare, noch zu signierende `RJ-Love-unsigned.ipa`.
- `RJ-Love-3.1-Komplettpaket`: IPA, einzelne Python-Serverdatei und aktuelle Anleitungen. Das ZIP enthält ein SHA-256-Manifest mit Commit-ID.
- `RJ-Love-interface-preview-<Gerät>`: Screenshots, UI-Test-Ergebnisse und Simulatorprotokoll je Gerät.

Der Paketcheck prüft Version, App-Icon, `Assets.car`, Datenschutzhinweise, Mikrofonzweck und die eingebettete Widget-Extension. Die Backend-Vertragstests prüfen Anmeldung, Sitzungsaustausch, Freigaben, Medien, Archive, Backups und Updatequelle. Die UI-Tests verwenden ausschließlich synthetische Debug-Daten; der Vorschau-Einstieg ist im Release-Build nicht enthalten.

## Vorhandene Daten

Beim Update nur die Python-Datei ersetzen und neu starten; `rjapp_config.json` und `rjlove_data/` vorher sichern und behalten. Die Datenbank ergänzt neue Tabellen und Spalten automatisch. Die Apps mit denselben IDs über die vorhandenen Installationen installieren. Die konkrete Signierung, HealthKit, UWB, AlarmKit und APNs zusätzlich auf den realen iPhones prüfen.

## Reparatur vom 22. Oktober 2026

Im Duftstudio bleiben Bereichsauswahl und „Heute anzeigen“ auch nach dem Scrollen im Jahreskalender erreichbar. Ein Bereichswechsel beginnt oben im jeweiligen Inhalt. Die UI-Prüfung wartet auf tatsächlich bedienbare Schalter und testet die feste Kalendernavigation nach dem Scrollen.
