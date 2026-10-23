# RJ Love 3.2.0 (320)

## Neu für euch

- Vier Hauptbereiche: Wir, Karte, Für uns und Erleben. Profil und Einstellungen öffnen über den Avatar mit der nativen iOS-Zoom-Animation.
- Duftpost, Liebe und Momente sowie die Bereiche unter Für uns verwenden native Segmentauswahlen. Bereichswechsel blenden weich über; reduzierte Bewegung wird beachtet.
- Unter Momente direkt ein Foto aufnehmen, beschreiben und einem Album hinzufügen. Original-Aufnahmeorte aus Fotos/Live Photos werden übernommen, sofern die Mediathek oder Datei sie bereitstellt. Beim Teilen eines Moments lässt sich der Ort weglassen.
- BeReal-Verlauf über Momente erreichbar. Fotowünsche öffnen sichtbar die Kamera, nehmen ohne Countdown auf und senden direkt. Wiederholte Uploadversuche behalten Foto, Zeit und Ort. Ein eigenes BeReal kann weiterhin zurückgerufen werden.
- Aufnahmeorte von Momenten und BeReals erscheinen auf einer Karte mit Übergabe an Apple Karten. Ohne verfügbare Koordinaten wird kein Ort erfunden. Bestehende Fotos ohne Ortsdaten bleiben nutzbar.
- Statusvorschläge, eigener Text und eine Laufzeit von einer, zwei, vier oder acht Stunden oder bis zur nächsten Änderung. Bitte nicht stören endet spätestens nach acht Stunden. Sichtbar auf Startseite, Profil und Live-Aktivität. Normale Push-/ntfy- und lokale RJ-Love-Mitteilungen bleiben in dieser Zeit still; bewusst gesendete Weckrufe bleiben möglich. Der iOS-Fokus wird nicht verändert.
- Kontrollzentrum: bestehendes Notfallfurz-Element behält seine Kennung und zeigt eine Wolke. Bestehende Entwürfe werden dauerhaft geparkt und nach Senden oder Verwerfen der Notfallaufnahme wiederhergestellt. Kein automatisches Löschen und kein automatisches Versenden von Audio.
- Kurzbefehle für Notfallfurz, Partnerkarte, Momente, Status und Herzgedanken. Kamera/Mikrofon öffnen weiter sichtbar; Anmeldung und passende iOS-Freigaben gelten. Herzgedanken ohne App-Öffnen werden bis zum nächsten Sync vorgemerkt.
- Live-Aktivität wird beim Wechsel in den Hintergrund nicht mehr beendet; Status, Akku, Herzgedanken, Datenalter und direkter Notfallfurz-Zugang. Gewünschte Live-Aktivitäten werden beim nächsten Öffnen erneuert, wenn iOS sie beendet oder entfernt hat. In der App ausdrücklich beenden schaltet diese Erneuerung aus.
- Freiwillige Hintergrund-Ortung im Profil. Sie ist unabhängig von der Live-Aktivität, benötigt Standortfreigabe und zeigt die iOS-Standortanzeige. Updates bei Bewegung übertragen auch den zuletzt ermittelten Akkuwert. Kein Versprechen einer permanenten Ausführung nach erzwungenem Beenden, bei fehlendem Netz oder iOS-Energiesparentscheidungen.

## Update ohne Datenverlust

1. Server stoppen und die vorhandene Python-Datei durch `Backend/rj_love_server.py` ersetzen.
2. `rjapp_config.json`, Datenverzeichnis und bisherigen Startbefehl behalten. Server neu starten.
3. `RJ-Love-unsigned.ipa` wie bisher signieren und über die bestehende App installieren. Bundle-ID und zugehörige Widget-/App-Group-Zuordnung erhalten; App nicht vorher löschen.
4. Beide iPhones aktualisieren. Der Server fordert mindestens App 3.2.0 an; bereits vorhandene Apps mit Kompatibilitätsanzeige zeigen die Aktualisierungsaufforderung. Die neue App benötigt Server 3.2.0.
5. Optional: Profil → Was ich teile → Live-Standort → Auch im Hintergrund teilen. Die Live-Aktivität separat auf der Wir-Seite starten.

Die Datenbankänderung ist additiv (`user_status`); vorhandene Konten, Fotos, BeReals, Duftpost, Termine, Reaktionen und Alben bleiben unverändert. Status liegt getrennt von Gerätetelemetrie und wird nicht durch alte Akku-/Standortdaten überschrieben. Die vorherige Version lässt sich per GitHub-Backup-Branch wiederherstellen. Vor einem Rollback App und Server wieder zusammen verwenden.

## iOS-Grenzen

Live-Aktivitäten sind maximal acht Stunden aktiv und führen selbst keine Standort- oder Netzwerkarbeit aus. Nach Wegwischen erfolgt ein lokaler Neustart beim nächsten Öffnen, solange die Option eingeschaltet bleibt. APNs-Updates, Widgets und Kontrollzentrum brauchen die vom Signaturprofil unterstützten Fähigkeiten; Kurzbefehle mit App-Öffnen benötigen keine Push-Berechtigung. Standorte von BeReals werden nur gespeichert, wenn die neue Foto-Ortsoption aktiv ist, die Freigabe vorliegt und ein frischer Standort verfügbar ist.

## Prüfung

Bestehende Backend-Prüfungen plus zwei gezielte Regressionen für Statusablauf/Ruhemodus/Telemetrie und Foto-Koordinaten/Updateaufforderung. GitHub Actions baut App und Widget-Extension und prüft das fertige IPA-Paket. Simulator-Vorschauen bleiben optional per manuellem Workflowstart.
