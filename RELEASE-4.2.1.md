# RJ Love 4.2.1 (421)

Dieses Update betrifft die iOS-App. Der vorhandene Python-Server 4.2.0 funktioniert unverändert weiter. Die neue IPA mit derselben Bundle-ID und demselben Signierteam über die bestehende App installieren; die App nicht löschen. Vorhandene Konfiguration und Daten behalten.

## Momente löschen

- Einen Moment öffnen und oben auf den Papierkorb tippen. Alternativ eine Galeriekachel lange drücken und „Moment löschen“ wählen.
- Der Bestätigungsdialog nennt ausdrücklich, dass der Moment für beide aus der gemeinsamen Galerie und den Alben entfernt wird. „Behalten“ bricht ab. Bereits in Apple Fotos gespeicherte Kopien bleiben erhalten.
- Eine laufende Löschung zeigt Fortschritt; Fehler erscheinen direkt in der jeweiligen Ansicht.
- Gelöschte Einträge verschwinden sofort auch aus bereits geladenen Archivseiten und aus dem Vollbildbetrachter. Der Betrachter zeigt den nächsten Moment oder schließt sich nach dem letzten. Verzögert eintreffende Galerie- und Sync-Antworten können gelöschte Einträge nicht erneut einblenden.
- Sofortfotos bleiben an die bestehenden Serverrechte gebunden. Für normale gemeinsame Momente gelten die bisherigen gemeinsamen Löschrechte.

## Navigation und Plex

Das Kino hat einen eigenen Haupttab. Die Bereiche Duftpost, Liebe und Momente bleiben unter Erleben; die zusätzliche verschachtelte Kino-Auswahl entfällt. Die Haupttabs bleiben sichtbar und verkleinern sich nicht beim Scrollen. Beim Bereichswechsel wird die Tastatur geschlossen. Die Kinokarte auf der Startseite öffnet direkt den Kino-Tab, bei laufendem Plex ist dort der Plex-Bereich ausgewählt.

Die Plex-Steuerung verwendet die native iOS-Leiste oberhalb der Tabs statt eines zusätzlichen Inset unterhalb der gesamten TabView. Sie lässt sich mit dem Pfeil nach unten ausblenden, ohne die Wiedergabe oder AirPlay zu beenden. Der Kino-Tab bleibt jederzeit erreichbar; dort kann die Leiste wieder eingeblendet werden. Neue Filme blenden die Steuerung erneut ein. Die Leiste zeigt den tatsächlichen externen Wiedergabestatus des nativen Players.

Der sichtbare YouTube-Mini-Player bleibt innerhalb der sicheren Fläche des gerade gewählten Tabs. Er überlagert die Hauptnavigation nicht. Die Wiedergabe- und Freigaberegeln von 4.2.0 bleiben erhalten.

## Prüfung

Release-Compiler für App und Widgets, bestehende kurze Serverprüfung und IPA-Paketprüfung. Für dieses UI-Update gibt es keine zusätzlichen umfassenden Testläufe. Die tatsächliche AirPlay-Darstellung muss auf einem verbundenen iPhone geprüft werden.
