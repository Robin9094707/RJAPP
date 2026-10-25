# RJ Love 3.9.1 · Direkt zum richtigen Moment

- **Fotowünsche bleiben eine Überraschung.** Kein Bark-, ntfy- oder eigener APNs-Hinweis für einen eingehenden Fotowunsch. Auch bereits wartende Fotowunsch-Pushaufträge werden unterdrückt. Die Anfrage bleibt gespeichert und erscheint weiterhin erst im Vordergrund der App, mit den bisherigen Freigaben und Rückrufmöglichkeiten.
- **Bark führt direkt in RJ Love.** Kommentar → richtige Duftpost und Kommentarstelle; Bewertung/neue Duftpost → die Aufnahme; Nachricht → das Gespräch an der Nachricht; Foto/Moment → Galerie; Erinnerung/Notiz/Termin → der konkrete Eintrag. Sonstige Mitteilungen öffnen den passenden Bereich oder den Feed. Weckrufe öffnen Push & Wecker; „Bin wach“ bleibt eine bewusste Bestätigung.
- Auch alte Beiträge außerhalb des normalen Startabrufs können über ihre ID nachgeladen werden. Anmeldung und Konto werden geprüft. Zurückgerufene Beiträge zeigen einen verständlichen Hinweis. Ein Link allein sendet, löscht oder bestätigt nichts.
- **Zurück zur App** schließt die aus einer Mitteilung geöffnete Ansicht. Bearbeitungsfenster schließen sich nach erfolgreichem Speichern und bringen dich zurück zum geöffneten Beitrag. Die bisherige Navigation darunter bleibt erhalten.
- **Tastatur schließen:** Ein kleiner Tastaturknopf neben dem Nachrichtenfeld schließt sie direkt, auch in Duftpost-Kommentaren. Im Plus-Menü des Chats lässt sich „Tastatur nach dem Senden schließen“ optional einschalten. Standard: ausgeschaltet. Nach Sendefehlern bleiben Entwurf und Tastatur erhalten; neu getippter Text während eines Versands wird nicht überschrieben.

## Installation

Die neue `rj_love_server.py` ersetzen und den bisherigen Server neu starten. Konfiguration, Datenverzeichnis, Bark-Kopplung und ntfy-Einstellungen behalten. IPA 3.9.1 (391) wie bisher signieren und auf beiden iPhones installieren. Keine neuen Python-Abhängigkeiten und keine zusätzliche Bark-Einrichtung.

Bark bekommt einen `rjlove://open?...`-Link. Bark unterstützt das Öffnen fremder App-Schemes über den `url`-Parameter. Für Browser/ntfy gibt es zusätzlich `https://love.example.com/open?target=...`: Die Seite versucht die App zu öffnen und zeigt einen manuellen Öffnen-Knopf. iOS kann dafür eine Bestätigung verlangen; eine garantierte lautlose Sofortweiterleitung lässt sich ohne signierte Universal-Link-Zuordnung nicht versprechen. Die Seite enthält keine Nachrichtentexte, Zugangsdaten oder automatisch ausgeführten Kontoaktionen.

Bereits zugestellte Bark-Mitteilungen behalten ihre alten Links. Neue Mitteilungen verwenden die Ziele aus diesem Update. Bereits sichtbare ältere Fotowunsch-Mitteilungen auf dem iPhone können nicht rückwirkend unsichtbar gemacht werden.

Die umfassende Einrichtung von Bark, ntfy, Ruhezeiten und privaten Webhooks steht weiter in [RELEASE-3.9.md](RELEASE-3.9.md). Die normalen Python-Regressionstests werden um Fotowunsch-Unterdrückung, Linkziele, Kontoschutz, alte/gelöschte Beiträge und gezielten Kommentarabruf ergänzt. Ein Swift-Check prüft gültige und ungültige App-Links. Kompilierung, IPA-/Widget-Versionen und Paketintegrität werden im GitHub-Workflow geprüft. Den Wechsel aus der installierten Bark-App und die Tastatur abschließend auf dem iPhone testen.

