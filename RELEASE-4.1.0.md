# RJ Love 4.1.0 · Unsere AirPlay-Bühne

Update für die installierte App 4.0.0. Gleiche Bundle-ID, App Group, Anmeldung, Konfiguration und bisherige Datenpfade. Neue Funktionen unter **Erleben → Kino → AirPlay**.

## Installation und Versionsschutz

1. Den bisherigen Datenordner und `rjapp_config.json` sichern. Eine vorhandene Bark-Schlüsseldatei ebenfalls behalten.
2. Server stoppen und ausschließlich `rj_love_server.py` austauschen. Mit derselben Konfiguration und demselben Datenordner neu starten.
3. **Dieser Server verlangt App 4.1.0.** Die installierte App 4.0.0 erkennt die Mindestversion über `/health` und zeigt ihre bestehende Update-Ansicht. Geschützte API-Anfragen alter Apps werden vor der Ausführung mit HTTP 426 abgelehnt. Die bisherigen Update-Download-Routen bleiben ausgenommen.
4. Die neue unsigned IPA mit derselben Feather-Signatur und App Group einschließlich Widget-Erweiterung signieren und über die bestehende App installieren; nicht vorher löschen. App 4.1.0 verlangt ihrerseits Server 4.1.0.

Die Protokollnummer bleibt 5; Versionsgrenzen schützen die geänderten Medienabläufe. Es werden keine bisherigen Tabellen umgebaut oder persönlichen Datensätze umgeschrieben. Zusätzlich entstehen nur `tv_shared_state` und `tv_action_ids`. Für eine Rückkehr zu 4.0.0 **App und Python-Datei gemeinsam** auf 4.0.0 zurücksetzen. Der alte Server ignoriert die zusätzlichen TV-Tabellen. Wiederverwendbare Signatur-/App-Group-Berechtigungen sind Voraussetzung für den Erhalt des iOS-Containers.

## YouTube ohne eigenen API-Schlüssel

Die Standardsuche öffnet die **echte mobile YouTube-Webseite in Apples SFSafariViewController innerhalb der App**. Suche, Google-Anmeldung, Abos und „Mein Bereich“ benötigen damit weder einen von euch eingetragenen API-Schlüssel noch eine OAuth-Client-Konfiguration. Google verwaltet dabei wie auf seiner Webseite die eigene Anmeldung und eventuelle Premium-Funktionen. RJ Love liest weder Kennwörter, Cookies noch private Browserdaten aus.

Ein Video gemeinsam übernehmen:

1. „Zusammen schauen“ eingeschaltet lassen und die Websuche oder „Meine Abos“ öffnen.
2. Ein Video aufrufen.
3. Die **Teilen-Taste des eingebauten Browsers** öffnen und **„Mit Schatzi schauen“** wählen. Die Aktion erscheint auf unterstützten YouTube-Video-URLs; sie ist eine eigene native Freigabeaktion und kein Auslesen des Browsers.
4. Das Video landet im gemeinsamen RJ-Love-Player. Alternativ kann weiterhin ein Video-Link direkt eingefügt werden.

Jedes iPhone hat seine eigene Browser-Anmeldung. Auf einem gemeinsam verwendeten iPhone müssen Accounts auch auf der YouTube-Webseite getrennt abgemeldet/gewechselt werden; der Browser-Login folgt nicht automatisch dem RJ-Love-Benutzer. Die Browser-Anmeldung und YouTube Premium werden **nicht automatisch in den separaten eingebetteten gemeinsamen Player übertragen**. Insbesondere private, altersbeschränkte oder nicht einbettbare Inhalte können dort fehlen. Für direkte, alleinige Wiedergabe auf der YouTube-Webseite gelten deren angebotene Player-/AirPlay-Funktionen.

Die bisherige native API-Playlist-Anzeige bleibt unter „Optionale API-Playlists“ erhalten. Nur sie benötigt weiterhin die eigene Google-OAuth-Konfiguration aus 4.0.0. Es werden keine fremden API-Schlüssel, Sessions oder YouTube-App-Binaries übernommen.

Das geprüfte Beispiel YouProEXTRA injiziert Erweiterungen in eine separat bereitgestellte YouTube-IPA. Es ist keine Player-Bibliothek, die sich in RJ Love importieren ließe. Die neue Webintegration verwendet Apples dokumentierten Browser und dessen eigene Share-Aktivität.

### Ein gemeinsamer YouTube-Raum

Beim Erstellen eines YouTube-Raums sind beide Partner automatisch Mitglieder. Im Vordergrund entdecken die Apps einen vorhandenen Raum etwa alle drei Sekunden und verbinden sich automatisch, sofern YouTube zuvor aktiviert wurde. „Gemeinsamen Raum automatisch verbinden“ kann auf jedem iPhone ausgeschaltet werden. Eine ausdrücklich gestartete Solo-Wiedergabe wird nicht automatisch ersetzt. Ein verlassener Raum wird auf dem betreffenden iPhone nicht sofort erneut betreten.

Beide können Play/Pause, Springen, Timer **und die Videoauswahl im selben Raum** bedienen. Veraltete parallele Videoauswahlen werden per Revision zurückgewiesen. Ein Gerät, das nur automatisch Mitglied ist, aber nicht abspielt, zählt nicht als gemeinsame Schauzeit. Die Freigabe von Google-Daten an den Partner erweitert sich dadurch nicht.

Der offizielle eingebettete Player bleibt sichtbar. Beim Öffnen des YouTube-Browsers wird der lokale eingebettete Player pausiert, um Doppelton zu vermeiden. iOS bzw. YouTube können weiterhin eine direkte Play-Berührung verlangen. Keine framegenaue Synchronisation, keine garantierte YouTube-Hintergrundwiedergabe und keine zugesicherte Übernahme von Premium-Rechten in den eingebetteten Player.

## Plex: kompatible Wiedergabe und Home-Profile

Standard ist jetzt **„Kompatibel (HLS)“**. Der Plex Media Server erhält einen HLS-Transcode-Auftrag mit H.264/AAC-Ausgabe bis 1080p/12 Mbit/s und eingebrannten ausgewählten Untertiteln. Damit kann er Quellen und Container wiedergeben, die AVPlayer nicht direkt unterstützt. **„Original (Direct Play)“** bleibt für nativ geeignete Dateien verfügbar.

Das ist die Nutzung des Plex-Server-Transcoders, kein unbegrenztes Codec-Paket auf dem iPhone. Der Server muss Transcoding erlauben, die Quelle decodieren können, die erforderlichen Zugriffsrechte haben und genug Leistung/Bandbreite liefern. Beschädigte Dateien, DRM-geschützte Streamingangebote, deaktiviertes Transcoding oder serverseitig nicht unterstützte Codecs werden dadurch nicht abspielbar. HDR/Tonemapping und Hardwarebeschleunigung hängen ebenfalls vom Plex-Server und seinen Berechtigungen ab. Es wird keine pauschale Garantie für jedes Format gegeben.

### Profile und PIN

Nach Plex-Anmeldung werden verfügbare Plex-Home-Profile abgerufen. Bei mehreren Profilen oder einem geschützten Profil muss ein Profil ausgewählt und gegebenenfalls seine vierstellige PIN eingegeben werden. **Plex prüft die PIN selbst**; es gibt keinen lokalen PIN-Bypass. PINs werden nicht gespeichert. Das ausgewählte Profil erhält einen eigenen effektiven Token nur im Arbeitsspeicher. Bibliotheken und Freigaben verwenden dieses Profil und dessen Rechte. Die dauerhafte ursprüngliche Anmeldung bleibt getrennt je RJ-Server/Benutzer im iOS-Schlüsselbund. Nach einem App-Neustart kann die Profilwahl/PIN erneut erforderlich sein.

Ein Profilwechsel beendet eine laufende gemeinsame Plex-Wiedergabe, bevor der neue Zugang benutzt wird. Der Partner bekommt weiterhin weder die Bibliothek noch den Konto-/Profil-Token.

### Gemeinsame HLS-Filmfreigabe

Die bisherige ausdrücklich ausgewählte, maximal vierstündige Filmfreigabe unterstützt nun auch HLS. Der RJ-Server schreibt Master-/Media-Playlists und deren Segment-/Schlüssel-URIs auf undurchsichtige, an die RJ-Sitzung gebundene Tickets um. Plex-Tokens werden aus Playlist-URLs entfernt und privat im Server-Header verwendet. Nur dieselbe bestätigte Plex-Transcoder-Sitzung darf referenziert werden; fremde Hosts, andere Bibliothekspfade, Pfad-Traversal und URL-Weiterleitungen sind gesperrt. Widerruf, Raumende, Timer und Logout sperren auch neue Segmentanfragen. Bereits gepufferte Medien lassen sich weiterhin nicht zurückholen.

Erforderlich sind wie zuvor HTTPS am RJ-Server und eine erreichbare, von Plex bestätigte sichere `plex.direct`-Verbindung. Gemeinsame HLS-Wiedergabe braucht entsprechend Bandbreite am RJ-Server. Inaktive Transcoder-Sitzungen werden von Plex verwaltet; die App kann keine universelle serverseitige Codec-/Berechtigungsfreigabe erzwingen.

## AirPlay gestalten

Die iOS-Bildschirmsynchronisierung liefert weiterhin eine eigene externe Szene statt einer bloßen Kopie der iPhone-Oberfläche. Die AirPlay-Taste am Player bleibt ein separater Weg für reine Medienübertragung.

Neue Ansichten:

- **Dashboard:** hell, Abendfarben oder dunkel; sortierbare Widgets und eine Fotoseitenleiste.
- **Momentwand:** 4/6/9/12 Fotos gleichzeitig, Diashow, vor/zurück, optional bildfüllender Zuschnitt.
- **Zusammen malen:** normalisierte Zeichenfläche, Farben und Strichbreite. Das iPhone ist die Touch-Fernbedienung; TV und Partner-App zeigen dieselben Striche.
- **Tic-Tac-Toe:** abwechselnde Züge, X/O-Zuordnung, Gewinn-/Unentschieden-Erkennung und neue Runde.
- **Signale:** Herz, Kuss, Umarmung, Stern und Winken auf der gemeinsamen Bühne und im Dashboard-Widget; keine Einblendungen über YouTube-Videos.

Weiter vorhanden: Unser Wir, einzelner Moment, Kino mit optionaler Infoleiste und sehr dunkler Nachtmodus.

Unter **„AirPlay gestalten & Widgets sortieren“** können Uhr/Datum, eigenes iPhone, Schatzi, freigegebener Standort, Momente, nächster gemeinsamer Termin, Kino und Signale hinzugefügt, entfernt und sortiert werden. Die Anordnung und Standortauswahl werden lokal getrennt je Server/RJ-Benutzer gespeichert.

Das iPhone-Widget beobachtet den eigenen aktuellen Akku, Ladezustand, Netz und Stromsparmodus. Partnerdaten zeigen den zuletzt übermittelten Stand. Die Standortkarte zeigt den letzten freigegebenen Standort mit Zeitstempel; sie fordert keine neue Berechtigung an. Der eigene Standort muss zusätzlich in den TV-Einstellungen eingeschaltet werden und die bestehende Standortfreigabe muss aktiv sein. Wenn beide gewählt sind, zeigt das Karten-Widget bevorzugt den eigenen Standort. Nicht verfügbare Daten werden nicht durch erfundene Live-Daten ersetzt.

### Gemeinsame Bühne und Hintergrund

„Gemeinsame Bühne aktualisieren“ synchronisiert den ausgewählten Modus, Zeichnungen, Spielzüge und Signale über euren privaten Server. Jeder Fernseher verwendet weiterhin seine eigenen lokalen Widgets und Standortfreigaben. Zeichenstriche werden in kleinen Abschnitten gesendet, die Gegenstelle wird während der Bedienung ungefähr alle 0,7 Sekunden, sonst ungefähr alle zwei Sekunden aktualisiert. Verbindungen und Serverlaufzeit können diese Abstände verlängern. Die Zeichenfläche ist auf die jüngsten 250 Strichabschnitte begrenzt. „Zeichenfläche leeren“ schützt gegen nachträglich eintreffende alte Striche durch eine Canvas-Epoche. Zeichnungen/Spielzüge sind gemeinsame Aktionen; das Ausschalten der Aktualisierung macht eine weiterhin ausdrücklich gesendete Aktion nicht privat.

Eine eigene AirPlay-Szene kann **nicht garantiert dauerhaft weiter aktualisieren, wenn iOS die App sperrt, beendet oder im Hintergrund suspendiert**. Die TV-Szene soll bei entsperrtem iPhone und geöffneter App verwendet werden; der automatische Ruhezustand wird bei verbundenem Bildschirm verhindert. Bestehende Standort-/Hintergrundfreigaben behalten ihre bisherigen Regeln. Native Plex-Medienwiedergabe kann unabhängig davon im Hintergrund laufen. Remote-Befehle im Hintergrund und ein physisches Ausschalten des TVs werden nicht zugesichert.

## Daten und Prüfung

Bisherige Fotos, Videos, Nachrichten, Standorte, Konten und Tabellen werden weiterverwendet. Die neue gemeinsame Bühne speichert nur Zeichenpunkte/Farben, Spielstand, Modus, kurzlebige Signale und technische Aktions-IDs in zusätzlichen Tabellen; keine Standortkopien und keine Konto-Tokens. Aktions-IDs werden nach 24 Stunden bereinigt, Signale bei weiteren Signalen auf maximal fünf Minuten bzw. 15 Einträge begrenzt. Die aktuelle Zeichnung bleibt bis zum Leeren erhalten. TV-Layouts liegen lokal, Plex-/Google-Zugänge folgen dem bisherigen getrennten Speicherverfahren.

Automatisierte Prüfungen decken Legacy-Funktionen, Versionssperre, automatische Raum-Mitgliedschaft, gemeinsame Videoauswahl, Zeichen-Idempotenz/Epochen, Spielzüge, HLS-Playlist-Umschreibung/Host-Grenzen und Widerruf ab. Simulator-Tests prüfen Navigation, Widget-Einstellungen sowie tatsächlich im Testserver gespeicherte Zeichenstriche, Spielzüge und Signale. Xcode baut eine unsigned IPA einschließlich Widgets; das Paket enthält einen Commit- und SHA-256-Manifest.

Nicht durch diese Umgebung nachweisbar: Anmeldung mit euren echten Google-/Plex-Konten, konkrete Plex-Transcoder/Codecs, Premium-Verhalten der Webseite und physische AirPlay-Empfänger. Diese Punkte müssen mit euren Geräten geprüft werden.

## Technische Quellen

- Apple Safari-Share-Aktivitäten: https://developer.apple.com/documentation/safariservices/sfsafariviewcontrollerdelegate/safariviewcontroller(_:activityitemsfor:title:)
- Safari-Systembrowser: https://developer.apple.com/documentation/safariservices/sfsafariviewcontroller
- Externe Displays: https://developer.apple.com/documentation/uikit/presenting-content-on-a-connected-display
- Plex-Profil-/Transcode-Dokumentation: https://developer.plex.tv/pms/
- Plex-eigener Client (Home/PIN): https://github.com/plexinc/plex-for-kodi/blob/master/lib/_included_packages/plexnet/myplexaccount.py
- Plex-eigener Client (HLS): https://github.com/plexinc/plex-for-kodi/blob/master/lib/_included_packages/plexnet/plexplayer.py
- Plex-Transcoding: https://support.plex.tv/articles/115002178853-using-hardware-accelerated-streaming/
- Geprüftes Beispiel: https://github.com/mrdrvt99/YouProEXTRA
