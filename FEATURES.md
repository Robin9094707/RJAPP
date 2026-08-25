# Funktionsumfang

## Nähe & Status

- private Anmeldung per Serveradresse, Benutzername und Passwort
- Live-/Letzter-Standort mit Zeit, Genauigkeit, Adresse, Distanz und Apple-Maps-Route
- adaptive Hintergrundortung mit Core Location und Bewegungsart aus Core Motion
- Akku, Ladezustand, Stromsparmodus, WLAN/Mobilfunk und optionaler WLAN-Name
- optionaler Fokusstatus (`aktiv`/`nicht aktiv`; iOS gibt keinen Fokusnamen frei)
- frei editierbarer Kurzstatus
- Geofences für Betreten/Verlassen, pro Zielperson und mit 50–1000 m Radius

## Liebe & Alltag

- täglicher „Ich denke an dich“-Zähler mit interaktivem Widget
- offlinefähige Herzgedanken-Warteschlange mit automatischem Tageswechsel
- bestätigter Weckruf mit frei wählbarer Nachricht und AlarmKit-Fallback
- gemeinsame Notizen mit Bearbeiten und bestätigtem Löschen
- gemeinsame Erinnerungen, frei wählbare Zielperson, Datum und AlarmKit
- gemeinsame ausgewählte Termine plus freiwilliger Export in den lokalen iOS-Kalender
- private Fotomomente mit Caption, Reaktionen sowie einzeln löschbaren Kommentaren
- konfigurierbares Speicherlimit je Benutzer

## iOS-Integration

- SwiftUI + Liquid Glass, Dark Mode, Dynamic Type, VoiceOver und Haptics
- Apple Maps / MapKit, Core Location, Core Motion, Network.framework
- AlarmKit-Systemalarme
- HealthKit für Schritte und Schlafdauer (optional)
- EventKit, LocalAuthentication, Keychain und UserNotifications
- zwei Home-Screen-Widgets: Herzgedanke und Partnerstatus
- Live Activity / Dynamic Island für Partnerstatus
- AlarmKit-Live-Activity-Darstellung
- App Intent / Siri Shortcut „An Schatzi denken“
- Face-ID-/Gerätecode-Appschutz
- geschützter Offline-Snapshot für bereits synchronisierte Inhalte
- Widget-Deep-Links direkt zur Karte und zu App-Bereichen
- persistente Debug-Konsole ohne Passwörter oder Tokens

## Backend

- genau eine Python-Datei, Python 3.11+, keine `pip`-Abhängigkeiten
- automatische JSON-Konfiguration beim ersten Start
- SQLite mit WAL, atomische Änderungen und automatische Bereinigung
- sichere zufällige Bearer-Sitzungen, konstante Passwortprüfung und Login-Rate-Limit
- optionale native TLS-Terminierung
- optionaler APNs-Versand mit `curl`/`openssl`
- persistente Ereignisse und Befehle, sodass Serverneustarts keine Daten verlieren
- Upload-/Request-Limit und Speicherquote
- typsichere Datensatzvalidierung, unveränderliche Eintragstypen und normalisierte Galerie-Metadaten
- sanitäre Logs ohne Zugangsdaten

## Bewusste Apple-Grenzen

- iOS entscheidet selbst, wann allgemeine BackgroundTasks ausgeführt werden. Dauerhafte Standortberechtigung und APNs verbessern die Aktualität, garantieren aber kein sekündliches Tracking.
- Ein Weckruf kann AlarmKit erst nutzen, nachdem das Zielgerät den Serverbefehl empfangen und lokal verarbeitet hat.
- Sideloading allein gewährt keine Push-, HealthKit-, App-Group- oder WLAN-Entitlements; das Signaturprofil muss sie enthalten.
- iOS liefert nur einen booleschen Fokusstatus, nicht den Namen des aktiven Fokus.
- „Schlafbalance“ ist eine RJ-Love-Dauerberechnung und kein offizieller Apple-Schlafscore.
