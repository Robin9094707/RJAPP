# Build 2.0.0 (200)

XcodeGen erzeugt App- und Widget-Targets aus `project.yml`. Mindestversion iOS 26.1; Swift 5-Sprachmodus. Der Workflow wählt ein installiertes stabiles Xcode 26, baut ohne Codesigning und packt die Haupt-App inklusive `PlugIns/RJLoveWidgets.appex` in die IPA. Der zusätzliche Simulatorjob erstellt UI-Vorschauen aus synthetischen Debug-Daten. Auf dem Runner sind keine privaten Apple-Zertifikate erforderlich.

Artefakte: `RJ-Love-unsigned-IPA`, `RJ-Love-2.0-Komplettpaket` und `RJ-Love-interface-preview`. Das Komplettpaket enthält ein SHA-256-Manifest mit Commit-ID. Fehlerprotokolle bleiben als Artefakte verfügbar.

Ein frischer Installations-/Serverordner ist vorgesehen. Keine Datenmigration. Native Fähigkeiten benötigen nach dem Build weiterhin passende Provisioningprofile und die Zustimmung des Nutzers. Die Produktion aktiviert keine Debug-Vorschau.
