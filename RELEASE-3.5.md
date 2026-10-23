# RJ Love 3.5.0 (350)

## Unser Tag und gemeinsame Neuigkeiten

Die neue Karte auf der Wir-Seite öffnet euren Tagesrückblick oder den Feed. Die Tagesansicht ruft den ausgewählten Tag direkt vom Server ab und berücksichtigt alle noch gespeicherten Beiträge dieses Tages, seitenweise auch jenseits der normalen Bootstrap-Grenzen. Sie zeigt Fotomomente, Nachrichten, Duftpost, Herzgedanken und weitere gemeinsame Beiträge als Zeitverlauf. Eine Detailansicht öffnet Medien oder die vollständige Duftpost-Karte. Gelöschte Beiträge bleiben ausgeschlossen.

BeReal und Momente gehören zum ursprünglichen Aufnahmetag, Duftpost zum gespeicherten Aufnahmezeitpunkt. Nachrichten und andere Beiträge zählen nach Erstellungszeit; geplante Termine werden als gespeicherte Termine angezeigt, nicht als nachgewiesener Besuch. Herzgedanken zählen anhand vorhandener Einzelereignisse. Alte reine Tagessummen werden nicht in erfundene Einzelereignisse umgewandelt. Die Tagesgrenzen verwenden die aktuelle Zeitzone des iPhones, einschließlich 23-/25-Stunden-Tagen bei der Zeitumstellung. Historische Health-, Bewegungs- oder Aufenthaltsdaten werden nicht erfunden.

Ab 19 Uhr kann die App einmal pro Tag beim Öffnen den Rückblick präsentieren. Im Profil unter Tagesrückblick abschaltbar. Das ist eine Anzeige in der geöffneten App, kein garantierter Hintergrundbericht und keine neue tägliche Push-Nachricht. Der Feed zeigt die bis zu 100 neuesten bereits synchronisierten Beiträge, keine vollständige Ereignis-Auditierung und keine erfundene Liste aller Bearbeitungen oder Kommentare.

## BeReal-Kalender

Der native iOS-Kalender markiert Tage mit der Zahl eurer vorhandenen BeReal-Fotos. Ein ausgewählter Tag öffnet eine ruhige Tagesgalerie mit Person, Aufnahmezeit, Beschreibung und gespeichertem Ort. Von dort lässt sich der vollständige Tagesrückblick öffnen. Heute-Schaltfläche, offene Fotowünsche, Metadatenbearbeitung und Zurückrufen eigener Aufnahmen bleiben erhalten. Das vollständige bestehende BeReal-Archiv wird geladen; die gespeicherte Aufnahmezeit ist maßgeblich.

## Überraschung: Unser Abendritual

Drei kleine Dinge. Ein großes Wir: Jeder kann pro Tag einen schönen Moment, ein Danke an den anderen und etwas Vorfreude festhalten. Beide Beiträge sind sofort gegenseitig sichtbar. Die zwei Herzen zeigen, ob ein oder beide Beiträge vorhanden sind; ohne Streak, Pflicht oder Bewertung. Jeder darf nur seinen eigenen Beitrag ändern oder löschen. Der Server verhindert doppelte Beiträge desselben Kontos und Tages. Lokale Entwürfe sind nach Server, Konto und Tag getrennt. Vergangene Beiträge bleiben beim jeweiligen Tag abrufbar. Die Funktion wird beim ersten Öffnen dieser Version vorgestellt.

## Duftstudio

Persönlicherer Einstieg mit Duftwolke, ruhiger Typografie und kompakten Kennzahlen für Werke, Tage und Kommentare. Ein tatsächlich bewertetes Werk erscheint als Jury-Highlight. Filter liegen in einer aufklappbaren Fläche. Kalender, Karte, Bilanz, Playlist, lokale Schatzkiste und bestehende Aufnahmen bleiben verfügbar.

## Nahsuche und geprüfte iOS-Grenzen

Die Meldung „Warte auf Freigabe“ war nicht belegbar: Der vorherige Code fasste einen fehlenden Discovery-Token und eine fehlgeschlagene Token-Kodierung zusammen und behandelte beides wie eine nicht erteilte Freigabe. Apple beschreibt den Discovery-Token als Sitzungskennung, die bei Initialisierung entsteht; die Freigabe wird beim Ausführen der Konfiguration geprüft. Eine fehlende Kennung beweist keine verweigerte Berechtigung.

Jetzt laufen Token-Austausch und Partnerabruf unabhängig: Auch ohne eigenen Token wird ein vorhandener Partner-Token abgefragt, sodass die Peer-Konfiguration gestartet werden kann. Bei fehlendem lokalen Token wird die reine UWB-Sitzung begrenzt zweimal neu erzeugt. Kamera und optionale Live-Aktivität starten erst nach dem Austausch. Der einfache Vordergrundmodus ist der Standard. Die App unterscheidet eigenen Token, erreichbaren Server, Partner-Token, gestartete Sitzung und tatsächliches Messsignal. Diagnose teilt diese Zustände, iOS-Version und originale Systemfehler mit Domain/Code, keine Discovery-Tokens oder Koordinaten. Ein UWB-Hardwaretest ist hier nicht möglich; die konkrete Ursache auf euren iPhones ist ohne diese Laufzeitdiagnose nicht sicher festgestellt.

Apple nennt für gute Messbedingungen wenige Meter Abstand (typisch unter neun Metern), aufrechte Geräte und aufeinander gerichtete Rückkameras. Kamera-Unterstützung erweitert die Richtungserfassung erst, nachdem das Gegenüber einmal im normalen Sichtkegel erkannt wurde. UWB hängt von Hardware, Region und Systemzustand ab. Das Framework hat laut Apple Developer Support kein gesondertes Nearby-Interaction-Entitlement; eine allgemeine Sideload-Sperre wurde nicht dokumentiert. Andere Capabilities wie HealthKit, App Groups und Push benötigen weiterhin passende Signierung.

Quellen:
- https://developer.apple.com/documentation/nearbyinteraction/nisession/discoverytoken
- https://developer.apple.com/documentation/nearbyinteraction/initiating-and-maintaining-a-session
- https://developer.apple.com/forums/thread/799000
- https://support.apple.com/de-de/109512

## Installation und Daten

1. Server stoppen, Konfiguration und Daten sichern und nur `Backend/rj_love_server.py` ersetzen. Mit unverändertem Startbefehl starten.
2. Beide iPhones auf die neue IPA aktualisieren. Haupt-App und Widget wie bisher signieren und über die vorhandene App installieren; nicht löschen.
3. Bei Nahsuche zunächst auf beiden Geräten Vordergrundmodus ohne Kamera verwenden. Bei Problemen Diagnose öffnen und teilen. Bluetooth an, Flugmodus aus; gegebenenfalls iPhone neu starten.

App und Server benötigen jetzt mindestens 3.5.0; ältere Apps mit Versionsprüfung erhalten die Updateaufforderung. Es gibt keine destruktive Datenbankänderung: Abendrituale verwenden einen zusätzlichen Eintragstyp in der bestehenden Datentabelle. Fotos, Health-Zusammenfassungen, Duftpost, Kommentare, Termine und Zugänge bleiben erhalten. Das persönliche Icon aus 3.4 bleibt eingebaut. Vorheriger Stand im Backup-Branch gesichert.

## Validierung

Bestehende Backend-Prüfungen plus zwei gezielte Regressionen: Tagesgrenzen mit Zeitumstellung, Aufnahmedatum, Paginierung und Löschung sowie Eigentümerschutz, Eindeutigkeit und Verlauf des Abendrituals. Der bestehende kleine Swift-Schlafcheck bleibt erhalten. GitHub Actions kompiliert App/Widget und prüft die fertige IPA. Die Kamera/UWB-Verbindung und der native Kalender müssen anschließend auf den echten iPhones geprüft werden.
