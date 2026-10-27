# RJ Love 4.3.1 (431)

## Notfallaufnahme und Anmeldung

- Der vorhandene Kontrollzentrum-Button und Kurzbefehl bleiben erhalten. Der aufnehmende Intent verwendet den Vordergrundmodus von iOS 26 und den App-Prozess für die Aufnahme mit Live-Aktivität.
- Aufnahmeaufträge werden lokal und optional in der App Group gespeichert. Ohne App-Group-Berechtigung funktioniert der Vordergrund-Intent weiterhin über den App-Speicher.
- Die App hört ab der Initialisierung zu; Netzwerk- und Health-Abgleiche blockieren den Aufnahmeauftrag nicht.
- Ein Auftrag bleibt bis zur bereiten Recorder-Ansicht erhalten. Fehlt die Nutzerkennung im Offline-Cache, wartet er auf den ersten erfolgreichen Abgleich oder die Anmeldung.
- Andere Ansichten werden vor dem Öffnen geschlossen. Wenn das nicht möglich ist, bleibt eine sichtbare Wiederholen-Taste erhalten. Einrichtungsdialoge werden zuerst abgeschlossen.
- Die Aufnahme beginnt nur bei sichtbarer, aktiver App und nach Mikrofonfreigabe. Ein vorhandener Entwurf wird wie bisher geschützt geparkt. Ohne Freigabe erscheint ein verständlicher Hinweis, die manuelle Aufnahme bleibt erreichbar.
- Schlüsselbundeinträge werden aktualisiert, statt sie zuerst zu löschen. Vorübergehend nicht lesbare Zugangsdaten führen zum Warten auf das entsperrte iPhone.
- Ein abgelaufenes Login verwirft keine lokalen Entwürfe oder Offline-Daten mehr. Alte fehlgeschlagene Sync-Antworten dürfen eine inzwischen erneuerte Anmeldung nicht abmelden.

## Dateien

- Bild- und PDF-Miniaturen bei Dateien bis 15 MiB; größere Dateien bleiben manuell vollständig zu öffnen.
- Quick Look direkt in der App für unterstützte Dokumente, Bilder, Videos und Audiodateien. Andere Dateitypen lassen sich über Teilen sichern oder extern öffnen.
- Listen- und Rasteransicht, Sortierung nach Name, Datum, Größe und Dateityp; Suche im aktuellen oder in allen Ordnern.
- Eigene Dateien und Ordner umbenennen sowie zwischen Ordnern verschieben. Favoriten und Dokument-IDs bleiben erhalten.
- Originaldateien werden beim Umbenennen nicht verändert. Der neue Name liegt ausschließlich in einer zusätzlichen Metadatentabelle.
- Zwei parallele Downloads, Wiederverwendung bereits geladener Originale und begrenzter temporärer Cache (150 MiB, Bereinigung beim nächsten Download; eine einzelne größere manuell geöffnete Datei kann die Grenze vorübergehend überschreiten). Separate Vorschaukopien verhindern, dass Cache-Bereinigung eine offene Vorschau entfernt. Explizites Abmelden leert den Downloadcache.
- Berechtigungsprüfungen, ungültige Namen, doppelte Ordnernamen und Verschieben in eigene Unterordner werden serverseitig abgefangen. Entfernte Dateien liefern eine verständliche 404-Meldung.

## Update mit bestehenden Daten

1. Laufenden Server stoppen und Konfiguration sowie Datenordner sichern.
2. Nur `Backend/rj_love_server.py` ersetzen, mit derselben Konfiguration und demselben Datenpfad neu starten.
3. IPA wie bisher signieren. Bundle-ID, Signierteam und App Group beibehalten und über die bestehende App installieren, ohne sie vorher zu löschen.

App 4.3.1 benötigt Server 4.3.1. Der neue Server akzeptiert weiterhin App 4.3.0 und Protokoll 5. Keine Änderung an vorhandenen Konten, Sessions, Asset-IDs, Originaldateien oder bestehenden Tabellen. Die neue Tabelle wird bei jedem Start idempotent ergänzt.

Ein direkter Zugriff auf den laufenden privaten Server ist über dieses Repository nicht eingerichtet. Das Komplettpaket enthält die aktualisierte Einzeldatei für den bestehenden Dienst.

## Prüfung

Elf HTTP-Regressionen für Kino, Einstellungen, Dokumente, Migration und Rechte; Swift-Smoke-Tests für Layout sowie persistente Notfallübergabe ohne App Group und nach verzögerter Darstellung. GitHub Actions kompiliert App und Widget-Erweiterung mit Xcode 26 und prüft die fertige IPA inklusive Versionsnummern und Ressourcen.

Nicht durch einen Build ersetzbar: Kalt-/Warmstart über echtes Kontrollzentrum, Mikrofonfreigabe, Signierung und Anmeldung auf beiden iPhones. Die ausgelieferte IPA ist unsigniert.
