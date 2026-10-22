# RJ Love 3.0.0 (300)

Ein gemeinsames Update für App und Python-Server, ohne Zurücksetzen bestehender Konten oder Daten. iOS 26.1 oder neuer. Haupt-App und eingebettetes Widget bleiben unter denselben Bundle-IDs; gemeinsam signieren.

## Sicher aktualisieren

1. Beide iPhones und den Server zunächst auf demselben Stand belassen. Server stoppen und Konfiguration samt Datenordner sichern; alternativ zuvor den integrierten `backup`-Befehl verwenden.
2. Nur `rj_love_server.py` ersetzen. `rjapp_config.json` und `rjlove_data/` behalten. Python 3.11+; keine pip-Pakete erforderlich. Server starten.
3. Auf beiden iPhones die neue IPA inklusive Widget in Feather signieren und über die bisherige Installation installieren. App nicht vorher löschen, damit lokale Entwürfe und lokale Kopien erhalten bleiben. Gleiche App-ID, App Group und Signierung beibehalten.
4. Version 3.0 verwendet Protokoll 5 und benötigt mindestens Server 3.0. Alte Apps erhalten eine Updateaufforderung. Neue Tabellen werden automatisch ergänzt; bestehende Furze, Bewertungen, Momente, Termine und Konten bleiben erhalten.

## Duftpost und die lokale Duftschatzkiste

- Jeder geteilte Furz, auch aus älteren Versionen und vom Gegenüber, lässt sich auf dem iPhone sichern oder als M4A über das Teilen-Menü an Dateien/iMessage weitergeben. Lokale Kopien enthalten Audio und JSON-Metadaten einschließlich ursprünglichem Datum und vorhandenem Ort. Sie sind getrennt vom Serverbestand. Ein späterer Server-Löschvorgang entfernt bewusst keine bereits exportierten oder lokal gespeicherten Kopien.
- Ein ungeteilter Recorder-Entwurf kann direkt lokal gesichert werden. In der Schatzkiste lassen sich Audiodateien importieren, Titel, Kategorie und ursprüngliches Datum festlegen und entweder nur lokal behalten oder gemeinsam hochladen. Audios werden in M4A umgewandelt, höchstens die ersten 60 Sekunden. Importdatum und tatsächliche Aufnahmezeit sind getrennt. Unbekannte historische Aufnahmeorte werden nicht erfunden.
- Neue Aufnahmen übernehmen einen verfügbaren frischen Ort standardmäßig, solange der neue Aufnahmeort-Schalter an und iOS-Standortzugriff erlaubt ist. Der Schalter ist später abschaltbar. Ohne Freigabe oder Messwert bleibt das Ortsfeld leer; alte Aufnahmen erhalten keinen nachträglich erfundenen Ort.
- Playlist: alle gefilterten Aufnahmen, zufällig gemischt, nur eigene oder nur vom Gegenüber. Automatisch nacheinander, mit Weiter/Stoppen. Wiedergabe und Aufnahme enden beim Wechsel in den Hintergrund.
- Tempo von 0,25× bis 3× und unabhängige Spaß-Soundarten: Eichhörnchen, Monster, Kathedrale und Marsbesuch. Das Original auf dem Server wird nicht verändert. Schneiden, Bewertungen, Reaktionen und Löschbestätigung bleiben erhalten.
- Neues Kontrollzentrum-Element „Notfallfurz“: manuell hinzufügen. Ein Tipp öffnet die App und startet nach Mikrofonfreigabe die sichtbare Aufnahme. Bestehende Entwürfe werden geöffnet und nicht überschrieben. Entsperren kann durch iOS nötig sein. Die App kann das Element nicht selbst in euer Kontrollzentrum legen.

## Messenger und süße Sprachnachrichten

Sprechblasen, Datum mit Sekunden, Fotos, Videos, Live Photos, Sprachnachrichten und verlinkte gemeinsame Termine. Inhalte bleiben auf eurem eigenen Server; das vollständige Chatarchiv wird seitenweise geladen. Keine Ende-zu-Ende-Verschlüsselung: der eigene Serverbetreiber kann die Inhalte lesen. HTTPS für Internetbetrieb verwenden.

Sprachnachrichten können als süße Begrüßung beim nächsten Öffnen markiert werden. Der Empfang ist zunächst eingeschaltet und unter Mehr abschaltbar. Eine sichtbare Wiedergabeansicht bietet Stoppen. Der Abspielpegel lässt sich innerhalb der aktuellen Medienlautstärke von leise bis deutlich festlegen. Die App verändert die Systemlautstärke nicht. Ein App-Öffnungszeitpunkt und die erste Öffnung einer Nachricht werden serverseitig aufgezeichnet. „Geöffnet“ ist keine Zusicherung, dass ein Mensch den Inhalt vollständig gehört/gelesen hat. Ohne Netzwerk erscheint der Status erst nach erfolgreichem Kontakt.

Eigene Nachrichten lassen sich nach Bestätigung zurückrufen. Danach können andere sie nicht neu vom Server abrufen. Bereits exportierte oder zuvor geladene Kopien und externe Backups werden dadurch nicht rückwirkend entfernt.

Walkie-Talkie, PushToTalk-Systemkanal, Funk-Widget, Audio-Hintergrundmodus und Push-to-Talk-Entitlement sind entfernt. Alte Funkrouten antworten mit HTTP 410; alte Tabellen werden zur Datenverträglichkeit nicht zerstört. Es gibt keine heimliche Aufnahme und keinen fingierten Hintergrundempfang.

## Momente, Alben, Videos und Live Photos

Der bisherige Foto-Upload wird durch eine gemeinsame Binärdatei-Pipeline ersetzt. Dateien werden stückweise auf Platte geschrieben, SHA-256 und Größe geprüft und erst nach vollständig erfolgreichem Upload freigegeben. Die App zeigt den tatsächlichen übertragenen Anteil. Standardlimit: 256 MB pro Datei, optional `server.max_media_mb`. Der kleine bisherige JSON-Upload bleibt für alte Momente erhalten.

Medienstruktur: `media/assets/<Benutzer>/<Jahr>/<Monat>/<UUID>/original.<Format>` plus Metadaten. Bei Live Photos bleiben Standbild und zugehöriges Video zusammen gespeichert; Anzeige, Export und Speichern zurück nach Apple Fotos erhalten beide Teile. Videos werden bei Bedarf geladen. Alben können angelegt, umbenannt und entfernt werden; Entfernen eines Albums löscht keine Fotos. Die Speicherübersicht zeigt beide Konten und ihre Summe, einschließlich reservierter laufender Uploads und gespeicherter Schnittfassungen. Abgebrochene Uploads werden bestmöglich freigegeben; keine persönlichen Medien in GitHub.

## Unser Jetzt: Fotowünsche

Beide können dem anderen einen Fotowunsch schicken. Die Funktion ist zunächst eingeschaltet und unter Mehr abschaltbar. Beim Öffnen wird die Vordergrundkamera sichtbar angezeigt, mit 3-Sekunden-Countdown und Abbrechen. Erst nach iOS-Kamerafreigabe wird aufgenommen; es gibt keine Hintergrundkamera. Das Foto wird automatisch auf eurem Server geteilt. Bei Fehlern bleibt die Vorschau zum erneuten Senden sichtbar. „Jetzt nicht“ überspringt diesen Wunsch auf diesem Gerät; später kann er im Bereich erneut geöffnet werden. Die Person auf dem Foto kann ihren Eintrag nach Bestätigung zurückrufen.

## Gemeinsame Planung und Apple-Apps

Neue Planungsansicht mit Datum, Beginn/Ende, Jahreswiederholung, Notizen und optionalem AlarmKit-Wecker. Beide können gemeinsame Pläne bearbeiten. Nur die in RJ Love angelegten und verknüpften Einträge werden in Apple Kalender und Apple Erinnerungen synchronisiert; private sonstige Kalender/Listen werden nicht hochgeladen. Änderungen an verknüpften Apple-Einträgen werden beim Öffnen abgeglichen. Berechtigungen sind erforderlich. Erst freigeben und dann die App öffnen, um die Verbindung zu prüfen.

AlarmKit hat keinen nativen Jahresrhythmus. Deshalb werden jährliche Termine als mehrere datierte Einzelalarme für die kommenden Jahre vorausgeplant und bei jedem Öffnen ergänzt. Am 29. Februar wird in Nichtschaltjahren der 28. Februar verwendet. Die Planung ist begrenzt, nach Zeitpunkt sortiert; für dauerhafte jährliche Wecker muss die App regelmäßig geöffnet werden. Ein neuer Plan auf dem Partnergerät wird spätestens nach dessen nächstem erfolgreichen Öffnungsabgleich eingeplant, wenn AlarmKit erlaubt ist. APNs und Hintergrundlaufzeit bleiben von Apple und Signierung abhängig; keine Zustellgarantie ohne Öffnungsabgleich.

## Herzen, Health, UWB und Systemführung

Einzelne Herzgedanken erhalten eine idempotente ID, tatsächlichen Tippzeitpunkt und Server-Empfangszeit. Widget-Gedanken bleiben mit Zeit in der lokalen Warteschlange, auch über Mitternacht. Bisherige Tageszähler werden behalten, historische Einzelzeitpunkte daraus aber nicht erfunden. Die Herzchronik zeigt Datum, Uhrzeit und Sekunden.

Beim Öffnen wird Health neu abgefragt; zusätzliche Vordergrundabgleiche werden gedrosselt. Freigaben gelten unverändert, fehlende Health-Daten bleiben leer. Die eigene Face-ID-/Gerätecode-Sperre wurde vollständig entfernt; die optionale iOS-App-Sperre kann separat genutzt werden. Ein einmaliges Änderungsfenster erklärt die neuen Funktionen und zunächst aktiven Einstellungen.

UWB zeigt einen echten Richtungspfeil aus Richtungsvektor oder Horizontalwinkel von Nearby Interaction, außerdem Entfernung und verfügbare Höhenhinweise. Optional lässt sich Kamera-Unterstützung aktivieren. Beide Geräte müssen die Suche geöffnet haben. Liefert iOS keinen Richtungswert, wird kein Pfeil erfunden. Die Kombination iPhone 14 Pro / 15 Plus muss auf euren realen Geräten getestet werden.

Beim Hintergrundwechsel werden Nahbereichssuche, Kamera, Aufnahme und Wiedergabe gestoppt, die Partner-Live-Aktivität beendet und kontinuierliche Standortupdates eingestellt. Erlaubte signifikante Standort-/Regionsereignisse bleiben möglich. Den von iOS selbst verwalteten Datenschutzindikator kann die App nicht beliebig ausblenden.

## Updates über Feather

Unter Mehr → App aktualisieren kann eine RJ-Love-IPA hochgeladen und als aktuelles Update freigegeben werden. Der Server prüft Bundle-ID, Version und ZIP-Struktur. Eine private AltStore-kompatible Quelladresse liefert nur diese IPA und ihr Icon, keine Kontodaten oder Medien. In Feather die Adresse als Quelle hinzufügen; Signieren und Installieren erfolgen weiterhin durch Feather mit eurem Zertifikat. Eine neue Quelladresse widerruft die vorherige desselben Kontos. Die Adresse geheim halten. Es wird keine nicht verifizierte Feather-URL-Schnittstelle vorausgesetzt und keine Zertifikatsdatei an den Server geschickt.

Eine eigene iMessage-Recorder-Extension wird wegen unbestätigter Signatur-/Installationsunterstützung nicht mitgeliefert. Vorhandene Furze können über Apples normales Teilen-Menü als abspielbare Audio-Anhänge an iMessage übergeben werden.
