# RJ Love 5.0.0 (500) · Neu gestaltet

App 5.0.0 und Einzeldatei-Server 5.0.0 gehören zusammen. Protokoll 5 bleibt unverändert, Datenbank, Konten, Medien und lokale Einstellungen werden nicht umgebaut.

## Design und Bedienung

- Liquid Glass durchgängig: alle Haupt- und Nebentasten nutzen die nativen Glas-Stile von iOS 26, Karten erhalten einen einheitlichen Glasrand, Abstände und Radien kommen aus gemeinsamen Design-Tokens.
- Ruhiger, statischer Mesh-Hintergrund für hell und dunkel. Er wird einmal gezeichnet und bewegt sich nicht, damit Scrollen flüssig bleibt.
- Neue Bewegung: Karten gleiten beim Öffnen gestaffelt herein und setzen sich beim Scrollen sanft ab, Tasten federn bei Berührung, Zahlen und Symbole wechseln mit weichen Übergängen. „Bewegung reduzieren“ schaltet all das ab.
- Die Tableiste wird beim Scrollen schmal (iOS 26), der Kino-Miniplayer bleibt erreichbar.
- Gebrandeter Startbildschirm beim Wiederherstellen der Sitzung statt eines einfachen Ladekreises.
- Einmaliger Neuerungen-Bildschirm für 5.0 (wie bisher über `rjlove.changelog-seen`, einmal pro Version).

## Startseite

- Begrüßung passend zur Tageszeit, Verbindungsstatus als Glas-Kapsel mit pulsierendem Punkt.
- Herzgedanken lassen sichtbar Herzen aufsteigen; Zähler zählen weich hoch.
- Partnerkarte mit „gerade in der App“-Hinweis (nur bei frischem Status), Bewegungs- und Akkuzeile.
- Alle Karten, Reihenfolgen, Größen und Schnellzugriffe bleiben exakt wie gespeichert.

## Duftstudio

- Schwebende Glas-Bedienleiste oben (Bereiche, Kalender) und schwebende Aufnahmetaste unten.
- Suche über einen vorberechneten Suchindex: Datumsformatierung pro Aufnahme passiert nur noch, wenn sich das Archiv ändert, nicht bei jedem Tastendruck.
- Aufnahmeknopf atmet im Ruhezustand, während der Aufnahme reagieren Ringe auf den Pegel. Timer und Symbole mit weichen Übergängen.
- Abspielen, Reaktionen und Bewertungen mit spürbarem Feedback.

## AirPlay

- Weiche Überblendungen zwischen allen TV-Ansichten.
- Diashow ohne schwarzes Zwischenbild: das nächste Foto wird im Hintergrund vollständig dekodiert und vorgeladen. Langsame Kamerafahrt während der Diashow, unscharfer Bildhintergrund statt schwarzer Ränder, optional Titel und Datum (abschaltbar in „AirPlay gestalten“).
- Neue Ambient-Ansicht mit langsam fließendem Farbverlauf, großer Uhr, Glas-Infochips (Datum, Akku, nächster Countdown). Der Nachtmodus behält den Einbrennschutz.
- Herz-Signale erscheinen groß über der Bühne (nie über einem laufenden Film).
- Live-Vorschau des Fernsehers auf dem iPhone, Ansichtswahl als Kacheln, Hinweis beim Verbinden eines Fernsehers. In der Vorschau laufen Video und Kamera nie doppelt.
- Dashboard-Hintergrund passend zum gewählten Thema, Uhr mit weichem Minutenwechsel.

## Schneller und sparsamer

- Der Offline-Speicher wird im Hintergrund kodiert und geschrieben (bisher auf dem Haupt-Thread bei jedem 12-Sekunden-Abgleich). Abmelden verwirft noch ausstehende Schreibvorgänge sicher.
- Widgets werden nur neu geladen, wenn sich ihr Inhalt ändert (spätestens alle 10 Minuten), statt bei jedem Abgleich.
- Server 5.0 komprimiert JSON-Antworten ab 1 KiB mit gzip, wenn die App das anbietet (URLSession tut das automatisch).

## Server 5.0.0

- `MINIMUM_APP_VERSION = 5.0.0`: ältere Apps (4.3.x und früher) erhalten HTTP 426 und zeigen ihren vorhandenen Bildschirm „Zeit für die neue App“. Die Update-Wege (`/v1/app-release`, `/v1/app-release/ipa`, `/v1/update-feed`, Feather-Quelle) bleiben für sie offen.
- Automatische IPA-Bereitstellung: eine RJ-Love-IPA (Dateiname beginnt mit `RJ-Love`) neben `rj_love_server.py` oder eine beliebige `.ipa` im Ordner `rjlove_data/updates/` wird beim Start und bei jedem Update-Abruf geprüft. Ist sie gültig (`eu.rjuhas.rjlove`) und neuer als die zuletzt veröffentlichte, wird sie einmalig als Release übernommen. Die alte App kann sie dann direkt über „IPA abrufen & mit Feather aktualisieren“ laden; eure private Feather-Quelle zeigt sie ebenfalls an. Die Datei zählt nicht zum Speicherkontingent eines Kontos.
- Keine Schema-Änderung. Bestehende Tabellen, Konten, Sitzungen, Asset-IDs, Originaldateien und Einstellungen bleiben unberührt.

## Sicher aktualisieren

1. Laufenden Server stoppen, `rjapp_config.json` und den kompletten Datenordner sichern.
2. Nur `Backend/rj_love_server.py` ersetzen und mit derselben Konfiguration neu starten.
3. Optional die neue `RJ-Love-unsigned.ipa` neben die Serverdatei legen. Dann zeigt die alte App beim nächsten Öffnen das Update-Fenster und kann die IPA direkt über Feather installieren.
4. IPA wie bisher signieren: Bundle-ID `eu.rjuhas.rjlove`, dasselbe Team, identische App Group, Widget-Erweiterung mitsignieren. Über die bestehende App installieren, nicht vorher löschen.

App 5.0.0 benötigt Server 5.0.0 und weist mit einem klaren Hinweis auf einen älteren Server hin. Alle lokalen Daten (Offline-Cache, Entwürfe, Startseiten-Layout, TV-Layout, Widgets, Schlüsselbund) verwenden unveränderte Schlüssel und Formate. Das TV-Layout erhält nur das optionale Feld `showCaptions`; ältere Layouts werden unverändert gelesen.

## Prüfung

15 HTTP-Regressionen: bisherige Kino-, Einstellungs- und Dokumenttests plus Update-Fenster für 4.3.x, offene Update-Wege, gzip nur auf Anforderung, einmalige und nur neuere IPA-Übernahme inklusive Feather-Quelle, Datenerhalt nach Neustart. GitHub Actions kompiliert App und Widget-Erweiterung mit Xcode 26 und prüft die fertige IPA inklusive Versionsnummern und Ressourcen.

Nicht durch einen Build ersetzbar: echtes AirPlay, Signierung und Installation auf beiden iPhones. Die ausgelieferte IPA ist unsigniert.
