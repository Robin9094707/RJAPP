# RJ Love 3.3.0 (330)

## Kommentare zur Duftpost

Jede Aufnahme besitzt jetzt einen eigenen Kommentarverlauf – auch vorhandene Aufnahmen. Beide können unabhängig von der Sternebewertung beliebig viele Kommentare schreiben. Die bisherigen Jury-Kommentare bleiben erhalten. Neue Kommentare enthalten Autor und Serverzeit; nur der jeweilige Verfasser kann seinen Kommentar löschen. Wiederholtes Senden desselben Auftrags erstellt keinen doppelten Kommentar. Der Verlauf wird seitenweise geladen, Entwurfstext bleibt auf dem jeweiligen iPhone gespeichert. Beim Löschen einer Aufnahme werden ihre Kommentare ebenfalls entfernt; bestehende Audiodateien und Bewertungen werden nicht umgeschrieben.

## Partnerprofil und Datenstände

Auf Wir → Lieblingsmensch → Profil & Aktivität sind getrennte, bestätigte Zeiten sichtbar:

- App zuletzt geöffnet: tatsächlich empfangener Vordergrundstart.
- Zuletzt in der App aktiv: letzter empfangener Vordergrundkontakt. Ein Hintergrundabruf ändert diesen Zeitpunkt nicht.
- Gerätedaten aktualisiert: letzter erfolgreicher Upload der freigegebenen Gerätedaten.
- Hintergrund erfolgreich: letzter vom Server bestätigter Hintergrundabgleich oder Standort-Upload, einschließlich Quelle.
- Standort aufgenommen und Health ausgewertet: ursprüngliche Mess-/Auswertungszeitpunkte.
- Auf deinem iPhone abgeglichen: letzter erfolgreicher Serverabruf dieses iPhones.

Fehlende historische Zeiten werden als nicht bestätigt angezeigt. „Vor kurzem aktiv“ bedeutet einen Vordergrundkontakt innerhalb von 45 Sekunden ohne späteren Abgangshinweis, keine lückenlose Online-Garantie. Ohne Netz oder ohne Ausführung durch iOS bleiben bestätigte Zeiten stehen. Die App leitet Aktivität nicht aus beliebigen API-Anfragen oder APNs-Live-Aktivitätsupdates ab.

## Jahrestag und eigene Countdowns

Für uns → Unsere Zeit ist jetzt ein eigener Bereich für euren Jahrestag und weitere Countdowns. Auch über die Wir-Karte „Jahrestag & Countdowns“ erreichbar. Der Jahrestag berechnet den nächsten Termin und gemeinsame Tage; eigene Countdowns können einmalig oder jährlich sein. Heute bleibt den gesamten Kalendertag „Heute“. Der 29. Februar wird in Nicht-Schaltjahren am 28. Februar angezeigt. Bestehende besondere Tage bleiben erhalten und können hier bearbeitet werden; der gemeinsame Kalender bleibt separat erreichbar.

Das neue Widget „Mein Countdown“ unterstützt Start- und Sperrbildschirm. Über Widget bearbeiten wählt jedes Widget einen eigenen Eintrag; ohne Auswahl erscheint der nächste Termin. Das vorhandene Widget „Unsere Zeit“ bleibt bestehen und zeigt bevorzugt den Jahrestag. Zeitachsen enthalten weitere Tageswechsel, damit die Tageszahl ohne ständig geöffnete App aktualisiert werden kann. Neue und geänderte Countdowns werden sofort in den Widget-Datenstand übernommen. Widgets benötigen weiterhin eine funktionierende App Group in der Signierung und unterliegen dem iOS-Aktualisierungsplan.

## Live-Aktivität

„Jetzt starten“ fordert die Aktivität direkt lokal an, bevor die Push-Registrierung abgeschlossen wird. Ohne APNs-Fähigkeit wird ein lokaler Start versucht. Ein Relevanzwert priorisiert diese Aktivität innerhalb der App für die Dynamic Island. Die aktuelle Anzeige und eventuelle Startfehler werden sichtbar gemeldet.

Unter Profil → Live-Aktivität & Dynamic Island lassen sich Akku, Status, Herzgedanken, Notfallfurz-Zugang und die Erneuerung beim nächsten Öffnen einstellen. „Anzeige übernehmen“ aktualisiert eine laufende Aktivität mit diesen Optionen. Die Optionen gelten auch bei späteren Server-Pushes. Das normale Beenden deaktiviert die automatische Erneuerung für diese Sitzung.

iOS muss Live-Aktivitäten erlauben, und die signierte IPA muss ihre Widget-Erweiterung enthalten. Die Aktivität ist höchstens acht Stunden aktiv. Bei mehreren Apps entscheidet iOS über die Darstellung in der Dynamic Island; das Aufklappen lässt sich nicht erzwingen. Langes Drücken zeigt die erweiterte Ansicht. Live-Aktivitäten selbst führen keine Standortarbeit aus.

## Aktualisieren

1. Server stoppen und nur `Backend/rj_love_server.py` ersetzen. Konfiguration, Datenordner und Startbefehl behalten. Server starten.
2. Auf beiden iPhones IPA wie bisher mit derselben App-/Widget-Zuordnung signieren und über die bestehende App installieren. Nicht vorher löschen.
3. Server und App benötigen jetzt mindestens 3.3.0. Ältere kompatibilitätsfähige Apps zeigen nach Serverupdate die Updateaufforderung.

Die Datenbankänderungen sind additiv (`fart_comments`, `app_activity`). Vorhandene Konten, Duftpost, Momente, Bewertungen, Status und Termine bleiben erhalten. Backup-Branch des Standes 3.2 vorhanden. Das Paket enthält keine persönlichen Serverdaten oder Zugangsschlüssel.

## Validierung

Bestehende Backend-Prüfungen plus drei gezielte Regressionen für Kommentare/Autorisierung/alte Aufnahmen, getrennte Aktivitätszeiten sowie Jahrestagsdaten/Live-Tokenwechsel. GitHub Actions kompiliert App und Widget-Erweiterung und prüft Version und Inhalt der fertigen IPA. Ein Test auf den tatsächlichen iPhones ist weiterhin nötig, insbesondere für Signierung, Widgets und Dynamic Island.
