# Build Notes

- App: `RJLove`
- Scheme: `RJLove`
- Bundle-ID: `eu.rjuhas.rjlove`
- Widget-Bundle-ID: `eu.rjuhas.rjlove.widgets`
- App Group: `group.eu.rjuhas.rjlove`
- Deployment Target: iOS 26.1
- GitHub Runner: `macos-26`
- Xcode: `/Applications/Xcode_26.5.app`
- Projektgenerator: XcodeGen aus `project.yml`
- Build: Release / `iphoneos` / generic iOS device / Signing deaktiviert
- Erfolg-Artifact: `RJ-Love-unsigned-IPA`
- Fehler-Artifact: `RJ-Love-build-log`

Die Build-Action führt vor XcodeGen die Python-Integrationstests, `py_compile`, Plist-Prüfungen und Konsistenzchecks aus. Die Widget-Extension wird in der Haupt-App eingebettet. Ein späterer IPA-Signierer muss beide Bundles signieren und passende Provisioningprofile/Entitlements verwenden.

Der Golden-Master-Build wurde auf dem vorgesehenen macOS-/Xcode-Runner erfolgreich verifiziert. Der endgültige Workflow ist ausschließlich manuell über `workflow_dispatch` startbar.
