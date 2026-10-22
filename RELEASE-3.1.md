# RJ Love 3.1.0 (310)

## Aktualisieren

Server stoppen und Konfiguration samt Datenordner sichern. Nur `rj_love_server.py` ersetzen, dann neu starten. `rjapp_config.json` und `rjlove_data/` behalten; die neue Einstellungstabelle wird automatisch ergänzt. Danach beide Apps inklusive Widget-Extension mit den bisherigen IDs signieren und über die vorhandene App installieren. Die neue App benötigt Server 3.1; Protokoll 5 bleibt unverändert.

## Fotos und Fotowünsche

Der Foto-Datenschutzhinweis ist ergänzt. Der System-Bildwähler liest Aufnahmedaten nur bei bereits erlaubtem Mediathekszugriff; ohne diesen Zugriff nutzt er die gewählte Datei. Vorschaubilder werden direkt aus der Datei verkleinert, damit hochauflösende Bilder nicht vollständig als Bitmap in den Speicher geladen werden müssen. Originaldateien von ausgewählten Momenten bleiben erhalten.

Fotowünsche werden über einen eigenen authentifizierten Endpunkt an das andere Konto gesendet. Wiederholungen mit derselben ID erzeugen keinen zweiten Wunsch. In der geöffneten App erscheint die sichtbare Frontkamera mit dem Wunschtext oder „Bitte lächeln“. Sobald die Kamera bereit und freigegeben ist, macht sie ohne Countdown ein Foto und sendet es automatisch. Fotowünsche sind bei beiden Konten zunächst aktiviert; eine bereits bewusst ausgeschaltete Einstellung bleibt erhalten. Kamera im Hintergrund und Umgehen einer verweigerten iOS-Freigabe sind nicht möglich.

Automatische Fotos werden als JPEG auf höchstens 2048 Pixel und unter 850 KB verkleinert. Scheitert der Versand, bleiben Vorschau und Wiederholen-Schaltfläche sichtbar. Ein bereits hochgeladenes Bild wird beim Wiederholen wiederverwendet; eine wiederholte Bestätigung erzeugt kein zweites Foto. Unter Unser Jetzt kann die aufgenommene Person ihr Foto zurückrufen. Bereits exportierte Kopien und Backups bleiben davon unabhängig.

Netzfehler, fehlerhafte Serverantworten und HTTP-Fehler sind getrennt. HTTP 413 benennt ausdrücklich das Upload-Limit. Für große Originalfotos/Videos hinter Nginx in der passenden `server`- oder `location`-Konfiguration beispielsweise `client_max_body_size 300m;` setzen, Konfiguration prüfen und Nginx neu laden. Das Python-Standardlimit liegt bei 256 MB pro Datei (`server.max_media_mb`).

## Persönliche Startseite und Navigation

Oben auf Wir auf das Regler-Symbol tippen. Überschrift, Rosé/Lavendel/Meer-Farbwelt, sichtbare Karten, Reihenfolge und kompakte/große Darstellung auswählen. Mit dem Griff verschieben, mit Minus ausblenden; unten wieder hinzufügen. Speichern bestätigt erst den erfolgreichen Serverkontakt. Beide Konten haben unabhängige Einstellungen. Sie bleiben nach Serverneustart und erneuter Anmeldung erhalten; eine lokale Kopie erlaubt die Anzeige ohne Netz. Gleichzeitig geänderte Einstellungen werden mit einem Hinweis zum Neuladen geschützt.

Die Bereiche Duftpost, Liebe und Momente haben große, direkt antippbare Schaltflächen. Dekorative Hintergründe fangen keine Berührungen ab. Startseiten-Verknüpfungen verwenden eine gemeinsame Kartendarstellung.

## Schlafbalance

Auf Wir und unter Health erscheint die freigegebene RJ-Schlafbalance des Gegenübers; unter Meine Daten die eigene. Sie vergleicht die vorhandene Schlafdauer der letzten 24 Stunden mit acht Stunden (0–100). Überlappende Schlafintervalle werden nur einmal gezählt. Das ist ein eigener Dauerindex, kein ausgelesener Apple- oder Garmin-Schlafscore und keine medizinische Qualitätsbewertung. Ohne erlaubte/verfügbare Schlafdaten bleibt die Anzeige leer. Der Schalter Schlaf & RJ-Schlafbalance regelt die Weitergabe.

## UWB mit Live-Aktivität

Apple erlaubt ab iOS 18.4 die Fortsetzung einer aktiven Nearby-Interaction-Sitzung mit einer sichtbaren Live-Aktivität. Beide starten die Suche zunächst in RJ Love. Mit der Hintergrundoption kann eine bereits verbundene Sitzung beim App-Wechsel oder Sperren weiterlaufen, höchstens 15 Minuten; Suchfreigaben laufen entsprechend ab. Die Kamera-Unterstützung wird im Hintergrund gestoppt. Die Live-Aktivität bietet einen Link zum Beenden.

Eine vollständig geschlossene App wird dadurch nicht zum heimlichen Start einer Suche aufgeweckt. Wird die Live-Aktivität verweigert, die App beendet oder das Signal unterbrochen, beide Apps wieder öffnen; alternativ die Hintergrundoption ausschalten und beidseitig im Vordergrund suchen. Tatsächliche Signierung, Hardware, iOS und Funkumgebung auf beiden iPhones prüfen. Quelle: https://developer.apple.com/documentation/nearbyinteraction
