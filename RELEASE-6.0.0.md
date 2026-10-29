# RJ Love 6.0.0 (600) · Ruhig, schnell, einheitlich

App 6.0.0 und Einzeldatei-Server 6.0.0 gehören zusammen. Protokoll 5 bleibt unverändert; Datenbank, Konten, Medien und lokale Einstellungen werden nicht umgebaut.

## Design

- Klassisch statt durchsichtig: Inhalte liegen auf festen Karten in der Farbe gruppierter iOS-Listen (hell und dunkel, in Sheets automatisch angehoben). Liquid Glass bleibt der Systemleiste vorbehalten: Tableiste, Navigationsleiste und Toolbar-Tasten.
- Ruhiger Hintergrund: ein einfacher Verlauf (Nachtblau im Dunkelmodus, Papierton im Hellmodus) statt eines Mesh-Verlaufs.
- Einheitliche Tasten: alle Inhaltstasten als Kapseln (`bordered` / `borderedProminent`) in der App-Farbe.
- Einheitliche Maße: Kartenradius 24, Kachelradius 20, Innenabstand 18, Abstand zwischen Karten 16.
- Profil und Einstellungen im iOS-Stil: Abschnittsüberschrift über einer Karte, Zeilen mit kleinen Symbolen und eingerückten Trennlinien.
- AirPlay-Bühne: Texte über Fotos und Video auf ruhigen dunklen Flächen statt Glas.

## Weniger Bewegung, mehr Flüssigkeit

- Keine Endlos-Animationen mehr: pulsierende Punkte, atmende Logos und Knöpfe, sich wiederholende Symboleffekte und der wandernde Startbildschirm-Verlauf sind entfernt.
- Kein gestaffeltes Einblenden und kein Skalieren von Karten beim Scrollen.
- Alle verbleibenden Übergänge sind kurz und federn nicht nach (0,12–0,3 s).
- Herz-Signale: weniger Partikel, keine pulsierenden Ringe mehr.
- Ergebnis: deutlich weniger Zeichenarbeit pro Bild, flüssiges Scrollen auch auf älteren iPhones und weniger Akkuverbrauch.

## Notfallaufnahme repariert

- Der „atmende“ Aufnahmeknopf lief als Endlos-Animation, die beim Öffnen des Recorders die Positionsänderung des Sheets mitnahm: der Knopf sprang und wanderte. Er ist jetzt ruhig und bleibt an seinem Platz.
- Die Pegelringe während der Aufnahme skalieren, statt ihre Größe zu ändern. Das Layout bewegt sich während der Aufnahme nicht mehr.
- Keine globale Animation mehr auf dem ganzen Recorder beim Wechsel Aufnehmen → Schneiden.
- Die Ersatztaste „Notfallaufnahme öffnen“ verschiebt den Inhalt nicht mehr und erscheint nur noch, wenn sich der Recorder nach 1,6 s nicht selbst öffnen konnte.
- Die Wolke im Recorder ist ein statisches Bild statt einer laufenden Animation.

## Startbildschirm

- Neuer, nahtloser Start: iOS zeigt euer Bild auf der App-Hintergrundfarbe, die App übernimmt exakt an derselben Stelle und blendet nach dem Wiederherstellen der Sitzung sanft über. Bei einer Notfallaufnahme wird der Startbildschirm sofort übersprungen.
- Neuer, ruhiger Neuerungen-Bildschirm für 6.0 (einmal pro Version über `rjlove.changelog-seen`).

## Server 6.0.0

- `MINIMUM_APP_VERSION = 6.0.0`: Apps 5.x und älter erhalten HTTP 426 und zeigen ihren vorhandenen Bildschirm „Zeit für die neue App“. Die Update-Wege (`/v1/app-release`, `/v1/app-release/ipa`, `/v1/update-feed`, Feather-Quelle) bleiben für sie offen.
- Eine `RJ-Love…ipa` neben `rj_love_server.py` (oder eine `.ipa` in `rjlove_data/updates/`) wird wie bisher automatisch als neues Release bereitgestellt.
- Keine Schema-Änderung. Bestehende Tabellen, Konten, Sitzungen, Asset-IDs, Originaldateien und Einstellungen bleiben unberührt.

## Sicher aktualisieren

1. Laufenden Server stoppen, `rjapp_config.json` und den kompletten Datenordner sichern.
2. Nur `Backend/rj_love_server.py` ersetzen und mit derselben Konfiguration neu starten.
3. Optional die neue `RJ-Love-unsigned.ipa` neben die Serverdatei legen. Dann zeigt die alte App beim nächsten Öffnen das Update-Fenster und kann die IPA direkt über Feather installieren.
4. IPA wie bisher signieren: Bundle-ID `eu.rjuhas.rjlove`, dasselbe Team, identische App Group, Widget-Erweiterung mitsignieren. Über die bestehende App installieren, nicht vorher löschen.

Alle lokalen Daten (Offline-Cache, Entwürfe, Startseiten-Layout, TV-Layout, Widgets, Schlüsselbund) verwenden unveränderte Schlüssel und Formate.

## Prüfung

15 HTTP-Regressionen inklusive Update-Fenster für 5.x und 4.x, offener Update-Wege, gzip, IPA-Übernahme und Datenerhalt nach Neustart. GitHub Actions kompiliert App und Widget-Erweiterung mit Xcode 26 und prüft die fertige IPA. Echte Signierung und Installation auf beiden iPhones bleiben eine Geräteprüfung; die ausgelieferte IPA ist unsigniert.
