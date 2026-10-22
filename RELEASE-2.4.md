# RJ Love 2.4.0 (240)

Das Duftstudio ist jetzt ein vollständiges privates Audioarchiv: Sammlung, Kalender, Furzkarte und Bilanz. Das native Liquid Glass erhält kräftigere Rosé-/Violett-Akzente, klarere Hierarchie, große Aufnahmeaktionen und feste Recorder-Bedienelemente auch auf kleinen iPhones. Reduzierte Bewegung wird berücksichtigt.

## Sammlung und Kalender

Suche nach Titel, Duftnote, Person, Aufnahmedatum, Situation oder Jury-Kommentar. Filter für Person, Kategorie, Favoriten und einen frei wählbaren Datumsbereich; Sortierung nach Datum, Bewertung oder Länge. Das Archiv lädt Metadaten seitenweise über die gesamte Sammlung, nicht nur die letzten 100 Aufnahmen. Audio wird weiterhin erst bei Wiedergabe geladen.

Der Monatskalender markiert Tage mit Aufnahmen; ein Tag öffnet seine Einträge. Ohne ausgewählten Tag werden alle Aufnahmen des Monats angezeigt. Die Jahresübersicht zeigt alle zwölf Monate mit Zählern und öffnet einen Monat direkt. Suche und Filter gelten auch in Kalender, Karte und Bilanz. Bilanz zeigt echte Aufnahmezahlen, Gesamtdauer, aktive Tage, Jury-Durchschnitt und die Verteilung zwischen euch beiden. Es werden keine Geruchs- oder Lautstärkewerte erfunden.

## Recorder und Sprüche

400 lokal gespeicherte Spruchkombinationen aus 80 situationsbezogenen Einstiegen und 40 passenden Schlusszeilen. Acht Situationen: Alltag, Morgen, Nacht, unterwegs, Zeit zu zweit, nach dem Essen, heimlich/leise und Zugabe. Tageszeit, eine vorhandene Aufnahme und der bereits verfügbare Bewegungsstatus schlagen eine Situation vor; Essen und Dates werden nicht automatisch erkannt. Die Situation ist frei wählbar. Bei jedem Öffnen wird neu gemischt, die letzten 32 Spruch-IDs pro Situation werden vermieden. Die Sprüche funktionieren ohne Internet und ohne KI-Dienst. Sie werden nicht automatisch vorgelesen und nicht in die Aufnahme eingespielt.

Aufnehmen/Pause/Stopp liegen in einem festen unteren Bereich. Schneiden, Vorschau, namenloses Senden, spätere Schnitte, Bewertungen, Favoriten und Reaktionen bleiben verfügbar. Auch die Sendetaste liegt außerhalb des Scrollinhalts. Fehlgeschlagene Uploads behalten den Entwurf.

## Furzkarte und Aufnahmezeit

Neue Aufnahmen speichern den Beginn der Aufnahme, auch wenn sie erst später hochgeladen oder nachträglich geschnitten werden. Ein vorhandener Standort wird nur erfasst, wenn eure Standortfreigabe eingeschaltet und der Messwert frisch genug ist. Beim Senden ist „Aufnahmeort auf eurer Furzkarte teilen“ zunächst aus. Ohne ausdrückliches Einschalten gelangen keine Koordinaten zum Server. Die Genauigkeit wird angezeigt; ein ungefährer Standort bleibt ungefähr.

Die Karte zeigt ausschließlich tatsächlich mitgesendete Aufnahmeorte. Markierung oder Liste öffnen die zugehörige Aufnahme. Im eigenen Drei-Punkte-Menü lässt sich ein geteilter Ort wieder entfernen. Frühere Aufnahmen haben keinen nachträglich erfundenen Ort; für ihre zeitliche Einordnung dient das bereits vorhandene Sendedatum. Frühere extern gespeicherte Backups werden durch späteres Entfernen eines Ortes nicht rückwirkend verändert.

## App und Server erkennen erforderliche Updates

Diese App benötigt Server 2.4.0 oder neuer mit Protokollgeneration 4. Der Server verlangt mindestens App 2.4.0 und das passende Protokoll. Ein öffentlicher `/health`-Vorabcheck unterscheidet „Python-Server aktualisieren“ von „App aktualisieren“. Die App zeigt eine zentrale Updateansicht mit Erklärung und erneuter Prüfung. Ein neuer Server weist alte Apps mit HTTP 426 und einer verständlichen Updateaufforderung ab, bevor Anmeldungen oder Änderungen verarbeitet werden. Eine sehr alte App kann dabei nur ihre bisherige Fehleranzeige benutzen.

Kein automatisches Überschreiben, Löschen oder Zurücksetzen von Konten, lokalen Entwürfen und Aufnahmen. Ein angezeigtes Update ist selbst durchzuführen: Server stoppen, Python-Datei ersetzen, Konfiguration und Datenverzeichnis behalten, Server starten; neue IPA inklusive Widget in Feather signieren und installieren.

## Push ohne Einrichtungsbefehl

Der Server prüft beim normalen Start, nach Geräteanmeldungen und anschließend jede Minute automatisch:

- Bereits vollständig konfigurierte APNs-Zugangsdaten.
- Den Ordner `push` neben `rjapp_config.json` und direkt daneben liegende Dateien `AuthKey_<KEYID>.p8`.
- Optional `push/credentials.json` mit `team_id`, `key_id`, `bundle_id`, `private_key_file`.
- Optional Umgebungsvariablen `RJ_APNS_TEAM_ID`, `RJ_APNS_KEY_ID`, `RJ_APNS_BUNDLE_ID`, `RJ_APNS_KEY_FILE`.

Die Key-ID kann aus Apples Dateinamen gelesen werden. Eine fehlende Team-ID kann aus den registrierten iPhones übernommen werden, wenn ihre Team-IDs eindeutig übereinstimmen. Der Server prüft Schlüsseldatei, Kennungen, HTTP/2-Werkzeuge und das lokale Signieren eines Provider-Tokens und aktiviert erst dann die Konfiguration. Bei mehreren gefundenen Schlüsseln oder uneindeutigen IDs wird nichts geraten. Der Status in der App beschreibt den fehlenden Bestandteil; ein Konsolenbefehl ist nicht mehr erforderlich. Automatische Einrichtung lässt sich mit `apns.auto_configure: false` abschalten.

Beispiel für `push/credentials.json`, falls die Team-ID nicht von den Geräten verfügbar ist:

```json
{"team_id":"DEINTEAMID","bundle_id":"eu.rjuhas.rjlove"}
```

Daneben die echte `AuthKey_<KEYID>.p8` ablegen. Eigene IDs verwenden; das Beispiel ist kein gültiger Zugang. Ein relativer `private_key_file`-Pfad wird wie bisher relativ zum Konfigurationsordner aufgelöst.

Apple muss den privaten APNs-Schlüssel ausgestellt haben. Ein App-Signatur-.p12 oder ein ArcticSign-Zahlungsbeleg ersetzt ihn nicht; die Python-Datei kann keine Apple-Zugangsdaten oder Profilrechte erzeugen. Eine erfolgreiche lokale Konfiguration ist keine Empfangsbestätigung. Ohne passenden Schlüssel bleiben Vordergrundabgleich und Vordergrundfunk verfügbar. Hintergrund-PTT und Push brauchen weiterhin passende Profile und Zugangsdaten; iOS bestimmt die Laufzeit. Die alte manuelle Einrichtung bleibt als optionales Verwaltungswerkzeug erhalten.

## Prüfung und Übergabe

Backend-Vertragstests prüfen Versionssperren, vollständige Archivseiten, Datums-/Ortsvalidierung, Erhalt beim Schneiden, Entfernen eigener Orte und automatische Schlüsselübernahme. Die CI prüft die App auf iPhone 14 Pro, SE (3. Generation) und 15 Plus mit iOS 26.1 oder neuer, einschließlich großer Schrift, Recorder-Upload, Suche, Monats-/Jahresnavigation, Karte und Updateanzeigen für alte Server bzw. Apps. Das IPA-Paket wird auf Version, Widget, Icon und alle 400 eingebetteten Sprüche geprüft.

Echter APNs-Empfang und die konkreten ArcticSign-Profile sind zusätzlich auf euren beiden signierten iPhones zu testen. Bestehende Konten, Bewertungen, Medienversionen und Backups bleiben erhalten; neue optionale Spalten werden beim Serverstart ergänzt.
