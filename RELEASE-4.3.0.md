# RJ Love 4.3.0 · Dein persönlicher Raum

App 4.3.0 (430) und Einzeldatei-Server 4.3.0 gehören zusammen. Protokoll 5 bleibt erhalten. Alte Apps erhalten HTTP 426 und die vorhandene Ansicht „Zeit für die neue App“.

## Was sich ändert

- Startseite: Kino, HomeKit, Abendplayer, Tagesjournal, Dokumente und Schnellzugriffe sind reguläre Karten. Alle Karten können entfernt, sortiert und kompakt/groß dargestellt werden. Eine leere Kartenliste bleibt leer. Alte Anordnungen werden einmal um die bisher festen Bereiche ergänzt.
- Navigation: eine bis fünf persönliche Schaltflächen, Beschriftungen und Reihenfolge in Profil → Startseite & Navigation. Standard: Wir, Für uns, Erleben, Karte. Kino bleibt als Karte, Schnellzugriff und im Profil erreichbar. Auch bei ausgeblendeter Startseite ist das Profil erreichbar.
- HomeKit: Kamera-Vollbild, stumm gestartetes Live-Bild, Zuhören und explizites Sprechen mit Mikrofonfreigabe. Zwei-Wege-Audio ist nur mit unterstützter Kamera und Home-Rechten möglich. Gemeinsame Feed-Verwaltung verhindert konkurrierende Stream-Delegates. Timeout und sichtbare Fehlermeldungen. Deaktivieren nur im Menü mit Bestätigung.
- Zuhause: vorhandene Apple-Home-Szenen ausführen, Räume und Geräte ansehen, unterstützte Ein/Aus-Schalter bedienen, Temperatur, Luftfeuchtigkeit, Helligkeit, Bewegung und Kontakte lesen. Kein Ersatz für sämtliche herstellerspezifischen Funktionen oder HomeKit-Secure-Video-Aufzeichnungen. Einladungen/Fernzugriff richtet man in Apple Home ein.
- AirPlay: Glasoberflächen, Widget-Vorschau, zwei/drei Spalten, Kamera, Health, Planung, Duftstudio und Dokumentübersicht als zusätzliche Widgets. Individuelle Diashow-Zeit. Das Kamera-Widget startet auf einem verbundenen Bildschirm auf Wunsch live, ohne automatisches Mikrofon. Kein dauerhaftes Live-Bild bei gesperrter/beendeter App zugesichert.
- Karte: Genauigkeitskreis aus `horizontal_accuracy`, Genauigkeit in Metern, passender Kartenausschnitt, Ladeindikator und animiertes Zentrieren. Veraltete Geocoding-Antworten überschreiben keinen neueren Standort.
- Duftstudio: kompakter Einstieg, direkte Favoriten/Sortierung/Zeitraum, klare Zugänge zu Import und Abendplayer. Vorhandene Aufnahmen und Filter bleiben erhalten.
- Dokumente: verschachtelte gemeinsame Ordner, persönliche Ordnerfavoriten, Datei-Upload über den bestehenden prüfsummen- und speicherlimitgeprüften Transfer, Quick Look mit Teilen/Export, Suche im Ordner. Entfernen nur durch Ersteller, Ordner nur leer. Upload-Wiederholungen sind idempotent. Geteilte Dokumente sind vor der Bereinigung verwaister Uploads geschützt.
- Bark: Dokument-Upload löst über denselben bestehenden NotificationHub eine Mitteilung aus. `rjlove://open?target=documents&id=…&account=…` führt zur Datei im Ordner. Kontoprüfung und entfernte Inhalte werden serverseitig geprüft. Bestehende Bark-Einstellungen und Schlüsseldatei bleiben erhalten.
- Automatische Sicherung: Startseite/Navigation bleiben in `user_preferences`, zusätzliche portable App-Einstellungen in `app_settings`, jeweils pro Konto mit Revision. TV-Anordnung und Kameraauswahl, Live-Aktivität, Standort/Health-Auswahl und App-Verhalten werden beim Synchronisieren gesichert und nach Anmeldung wiederhergestellt. Konflikte werden pro Einstellung mit der zuletzt bestätigten Basis zusammengeführt; Änderungen während eines Abrufs bleiben erhalten. Ein Fehler lässt lokale Änderungen zum nächsten Abgleich liegen.

## Sicher aktualisieren

1. Laufenden Server beenden und die vorhandene Konfiguration samt vollständigem Datenordner sichern.
2. Nur die Python-Programmdatei ersetzen. Konto-IDs, Datenpfad, Datenbank, Medien und Bark-Schlüsseldatei behalten. Mit derselben Konfiguration und demselben Arbeitsverzeichnis starten.
3. Neue IPA mit derselben Bundle-ID `eu.rjuhas.rjlove`, demselben Team und identischer App Group über die bestehende App signieren/installieren. HomeKit-Entitlement erhalten; die eingebettete Widget-Erweiterung mitsignieren.
4. Beide Konten einmal anmelden/öffnen und im Profil → Automatische Sicherung den erfolgreichen Abgleich prüfen, bevor eine App gelöscht wird.
5. Bei einem pfadbasierten Reverse Proxy die neuen `/v1/settings`, `/v1/documents` und Unterpfade an dieselbe Anwendung weiterleiten. Upload-Limit und Timeout passend konfigurieren. Bestehende `/v1/assets`, `/v1/navigation`, `/bark` und übrige Pfade behalten.

Datenbankänderungen sind additive `CREATE TABLE IF NOT EXISTS`-Anweisungen: `app_settings`, `document_folders`, `shared_documents`, `document_favorites`. Es werden keine alten Tabellen, Konten, Nachrichten, Momente, Aufnahmen oder Medienpfade ersetzt.

Die Einstellungssicherung ist kein vollständiges iPhone-Backup. iOS-Berechtigungen, Apple-Home-Einladungen, Signatur/App Group, System-Widget-Platzierung, Medien-Zugangstokens und nur lokal gespeicherte Audiodateien/Entwürfe bleiben gerätegebunden. Geteilte Inhalte und neue Dokumente liegen bereits auf dem Server. Zugangsdaten und APNs-Gerätetokens werden nicht als portable Einstellungen kopiert.

## Prüfung

Sieben kleine HTTP-Tests: bisherige Kino-Kompatibilität plus Kontotrennung/Revisionen, Dokument-Upload und Download als Partner, Favoriten, Aufbewahrung, Bark-Link, Löschrechte und einmalige Layout-Migration. Ein kurzer Foundation-Swift-Test prüft alte Layouts, Standardnavigation ohne Kino und die dauerhaft leere Startseite. Danach regulärer Release-Build für App und Widget sowie IPA-Paketprüfung.

Hardware-Abnahme: Zwei-Wege-Audio, Home-Einladungen, reales AirPlay und die konkrete Signatur müssen mit den vorhandenen iPhones/Kameras/TVs geprüft werden. Ein Compiler-Build kann diese Verbindungen nicht simulieren.
