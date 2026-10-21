# Build 2.1.0 (210)

XcodeGen erzeugt App- und Widget-Targets aus `project.yml`. Mindestversion iOS 26.1; Swift 5-Sprachmodus. Der Workflow wählt ein installiertes stabiles Xcode 26, baut ohne Codesigning und packt die Haupt-App inklusive `PlugIns/RJLoveWidgets.appex` in die IPA. Der zusätzliche Simulatorjob erstellt UI-Vorschauen aus synthetischen Debug-Daten. Auf dem Runner sind keine privaten Apple-Zertifikate erforderlich.

Artefakte: `RJ-Love-unsigned-IPA`, `RJ-Love-2.1-Komplettpaket` und `RJ-Love-interface-preview`. Das Komplettpaket enthält ein SHA-256-Manifest mit Commit-ID. Fehlerprotokolle bleiben als Artefakte verfügbar.

Ein frischer Installations-/Serverordner ist vorgesehen. Keine Datenmigration. Native Fähigkeiten benötigen nach dem Build weiterhin passende Provisioningprofile und die Zustimmung des Nutzers. Die Produktion aktiviert keine Debug-Vorschau.


2.1 (210) bindet `App/Resources` ausdrücklich als Ressourcenquelle ein. `Scripts/verify_ipa.py` bricht den Build ab, wenn Icon-Metadaten, Icon-PNGs, `Assets.car`, Datenschutzerklärung, Mikrofonzweck oder die Widget-Extension fehlen. Die UI-Prüfung erfasst zusätzlich Duftpost, Recorder und Liebesbereich. Das Recorder-Mikrofon wird in der synthetischen Vorschau nicht aktiviert.
