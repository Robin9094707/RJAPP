# RJ Love 2.0 — Funktionsstand

Implementiert: neue Wir-Oberfläche mit nativen Liquid-Glass-Flächen, Hell/Dunkel, Dynamic Type und reduzierten Herzanimationen bei entsprechender Systemeinstellung; fünf Hauptbereiche; Chat mit lokalem Entwurf und Tagesfrage; gemeinsame Wunschliste; besondere Tage mit Countdown; freiwillige Gefühls-Updates; Notizen, Erinnerungen, Kalender, Fotos/Kommentare/Reaktionen; Partnerkarte und Orte.

HealthKit liest ausschließlich nach Systemfreigabe. Weitergabe an den Partner ist zusätzlich separat für Aktivität, Schlaf und Vitalwerte schaltbar. Fehlende Daten werden nicht als Nullmessung dargestellt. Schlafdauer berücksichtigt die Vereinigung aller Schlafintervalle der letzten 24 Stunden und verhindert Doppelzählung über mehrere Datenquellen.

Nearby Interaction verwendet die öffentliche Apple-API und tauscht kurzlebige Tokens ausschließlich zwischen den beiden angemeldeten Konten aus. Start beidseitig im Vordergrund. Abstand und Richtungsvektor hängen von Hardware, Funkumgebung und iOS ab. Veraltete Messungen verschwinden. Keine Fern-UWB-Ortung und kein heimliches Suchen.

Widget-Extension: vier Home-Screen-Widgets (Herzgedanke, Status, Health, Countdown), zusätzlich Sperrbildschirm-Widget in drei Größen, Partner-Live-Aktivität und AlarmKit-Live-Aktivität mit Dynamic-Island-Darstellung.

Backend: eine Python-Datei, SQLite/WAL, Konfiguration beim ersten Start, scrypt-Passwörter, Login-Limit, unabhängige Konten, atomarer Sitzungsaustausch, Passwort-/Benutzernamenänderung mit aktuellem Passwort, Rücksetzen per Konsole/CLI/Datei, TLS, optionale native APNs- und ActivityKit-Pushes sowie optionale allgemeine ntfy-Hinweise.

Nicht zugesichert: dauerhaft laufender iOS-Hintergrundprozess, exakte Widget-Aktualisierungstakte, sofortige Zustellung ohne APNs, kritische Mitteilungen, ein offizieller Apple-Schlafscore, Freischaltung nicht erlaubter Entitlements durch Sideloading. Reale Hardware- und Signaturtests bleiben notwendig. Ein erfolgreicher Compilerlauf ist kein Hardwaretest.
