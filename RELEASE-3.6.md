# RJ Love 3.6.0 (360)

## Ein Fotowunsch nach dem anderen

Pro Person ist höchstens ein unbeantworteter ausgehender Fotowunsch erlaubt. Die App zeigt den wartenden Wunsch mit Text, Empfänger und Sendezeit an und deaktiviert den neuen Wunsch, bis der andere ihn beantwortet oder der Absender ihn zurückruft. Das Zurückrufen benötigt einen Bestätigungsdialog. Beide haben einen eigenen unabhängigen Platz für einen Wunsch.

Die Begrenzung gilt atomar auf dem Server und zusätzlich als eindeutiger SQLite-Index. Sie erfasst auch parallele Aufrufe und den älteren allgemeinen Eintrags-Endpunkt. Gleiche Anfrage-IDs sind wiederholbar, ohne neue Kameraaufträge oder Push-Ereignisse zu erzeugen. Eine Beantwortung und ein Zurückrufen werden in Schreibtransaktionen geprüft: Ein bereits beantworteter Wunsch kann nicht mehr zurückgerufen werden; ein zurückgerufener kann keine neue Fotoantwort mehr annehmen. Ein fertig gesendetes Foto bleibt erhalten. Nur der Absender kann seinen offenen Wunsch zurückrufen; die Erledigung erfolgt über die tatsächliche Fotoantwort.

Beim Upgrade bleibt der neueste unbeantwortete Wunsch je Absender aktiv; ältere unbeantwortete Wünsche werden zurückgerufen und ihre noch ungelesenen Anfrage-Ereignisse entfernt. Fertige Fotos, beantwortete Wünsche und alle übrigen Inhalte werden nicht verändert. Diese Bereinigung läuft vor dem Anlegen des eindeutigen Index. Die App prüft einen Wunsch vor dem Öffnen der Kamera beim Server und beendet einen zurückgerufenen Auftrag beim nächsten erfolgreichen Abgleich. Bereits zugestellte Mitteilungen oder eine schon erfolgte Kameraaufnahme lassen sich nicht rückwirkend ungeschehen machen; nach einem erfolgreichen Zurückruf akzeptiert der Server aber keine Fotoantwort für diesen Auftrag mehr.

## Neues Design

Ein gemeinsames System aus warmen Rosé-/Pflaumentönen, ruhigen adaptiven Hintergründen, hellen bzw. dunklen Inhaltskarten mit dezenten Konturen, weniger Schatten und einheitlichen Symbolflächen ersetzt die großflächigen Farbwolken und Glasflächen hinter jedem Inhalt. Native Glaselemente bleiben für schwebende Bedienelemente. Die Änderungen gelten über die geteilten Komponenten für Wir, Journal, Health, Momente, Duftstudio und weitere Karten.

Das eigene Profil ist eine neue übersichtliche Einstiegsseite: Status, Lieblingsmensch, Health und Live-Aktivität stehen oben; persönliche Freigaben, Privatsphäre, iOS-Rechte, Zugang, Speicher und Verbindung haben klar beschriftete Bereiche. Vorhandene Schalter und Werte bleiben erhalten. Technische Informationen liegen bei Verbindung/Diagnose bzw. weiteren Möglichkeiten.

Der Statuseditor besitzt eine direkte Vorschau, passende Schnellvorschläge, eine klare Dauer- und Ruheauswahl sowie einen erreichbaren unteren Teilen-Knopf. Er ist eine normale Navigationsseite. Ein eigener Sheet-Host übernimmt nur beim separaten Öffnen Navigation und Fensterhöhe. Dadurch werden beim Profil → Status keine NavigationStacks mehr ineinander geschachtelt und die Höhe des Profilfensters nicht während des Übergangs geändert. Das Partnerprofil verwendet ebenfalls die Navigation seines aufrufenden Bereichs.

## Aktualisieren

1. Server stoppen und Konfiguration sowie Datenordner sichern. Nur `Backend/rj_love_server.py` ersetzen und mit dem bisherigen Startbefehl starten.
2. Beide iPhones mit der neuen IPA aktualisieren; wie bisher Haupt-App und Widget passend signieren. Nicht vorher löschen.
3. Bestehende zu viele offene Fotowünsche werden beim Serverstart begrenzt. In BeReal kann der verbleibende ausgehende Wunsch angesehen und bewusst zurückgerufen werden.

App und Server benötigen mindestens 3.6.0. Der neue Server fordert ältere Apps zum Update auf. App-/Widget-IDs, App Group, Konten und vorhandene Medien bleiben erhalten. Der Kamera-/UWB-Fix aus 3.5.1 ist unverändert enthalten. Der vorherige Stand ist im Backup-Branch gesichert.

## Prüfung

Bestehende Backend-Prüfungen plus zwei gezielte Regressionen für gleichzeitige Fotowünsche, Zurückruf, Beantwortung, Autorisierung und alte Warteschlangen. Ein einzelner UI-Smoke-Test prüft, dass Profil → Status → zurück zweimal funktioniert und anschließend das Profil geschlossen werden kann. Simulatoransichten zeigen Wir, Profil, Status und BeReal sowie das Profil im Dunkelmodus. Es gibt keine zusätzlichen umfangreichen Tests. Die physische UWB-Verbindung ist durch Simulatorprüfungen nicht abgedeckt.
