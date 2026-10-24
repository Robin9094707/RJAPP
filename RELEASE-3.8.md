# RJ Love 3.8.0 (380)

## Eure Momente

Die Galerie zeigt ein kompaktes Raster nach Monaten, Suche und Filter nach Person und Album. Im Vollbild könnt ihr zwischen Erinnerungen wischen und Fotos vergrößern. Beschreibung, Datum, Album, Kommentare und Reaktionen bleiben erreichbar. Originale lassen sich ausdrücklich teilen oder in Apple Fotos sichern.

Videos in der Galerie und im Abendplayer werden direkt vom privaten Server mit HTTP-Bytebereichen gestreamt. Vorher muss keine vollständige Videodatei heruntergeladen werden. iOS darf für die Wiedergabe puffern; die App legt dafür keine dauerhafte Videokopie an. Spulen, offene und abschließende Bytebereiche, HEAD und ungültige Bereiche werden serverseitig unterstützt. Die temporären Wiedergabelinks sind auf ein Medium und die aktuelle Anmeldung begrenzt, laufen nach sechs Stunden ab und verlieren nach Abmelden oder Entzug der Freigabe ihre Berechtigung. Die normalen Serverlogs verbergen den Linkschlüssel. HTTPS verwenden und Wiedergabelinks nicht weitergeben.

Neue Videos erhalten beim Import ein kleines Vorschaubild. Bei älteren Videos ohne Vorschau versucht die App, einen Einzelbildausschnitt aus dem Stream zu laden; höchstens zwei solche Aufgaben laufen gleichzeitig. Ein nicht unterstütztes Videoformat kann weiterhin einen Wiedergabefehler liefern. Der Player zeigt dann Erneut laden an.

Das Raster verwendet kleine Vorschaubilder mit einem begrenzten Arbeitsspeichercache. Ein vollständiges Foto wird erst beim Öffnen der aktiven Vollbildseite geladen. Die temporäre Originaldatei wird beim Wechsel oder Schließen wieder entfernt. Vorübergehende Betriebssystempuffer sind davon unabhängig. Explizites Teilen/Sichern lädt die dafür nötigen Originaldateien. Live Photos behalten ihre zusammengehörenden Originalbestandteile; im Raster und Vollbild wird das Foto gezeigt, beim Sichern können beide Bestandteile übernommen werden.

Auch die ältesten eingebetteten Fotos werden in Bootstrap, Archiv und Journal nur noch als Metadaten übertragen. Ihr Original bleibt unverändert in der Datenbank und kann beim Öffnen abgerufen werden. Ein alter Eintrag ohne kleines Vorschaubild zeigt bis dahin ein Fotosymbol; es werden dafür keine Originale im Hintergrund heruntergeladen. Kommentare und Bearbeitungen dieser Einträge erhalten das Original. Lokale Offline-Snapshots enthalten keine vollständigen älteren Momentfotos mehr.

## Optional platzsparend teilen

Im Teilen-Dialog gibt es einen zunächst ausgeschalteten Schalter. Fotos werden dann als JPEG mit Qualität 0,88 und höchstens 3200 Pixeln an der langen Seite vorbereitet; Videos mit dem 1080p-Exportprofil und für Netzwerkzugriff optimierter Datei. Die vorbereitete Variante wird nur verwendet, wenn sie tatsächlich kleiner ist. Live Photos bleiben unverändert. Eure Dateien in Apple Fotos werden nicht überschrieben. Aufnahmezeit und separat freigegebene Ortskoordinaten bleiben in den App-Metadaten erhalten. Komprimieren kann eingebettete Dateimetadaten oder HDR-Eigenschaften verändern.

## Momentkarte

Die Kartenansicht zeigt alle geladenen und gefilterten Momente mit gültigen, freigegebenen Koordinaten. Nahe Marker werden gruppiert; ein Tipp öffnet den entsprechenden Moment. Das paginierte Serverarchiv wird beim Öffnen nachgeladen. Fotoorte kommen aus verfügbaren EXIF-/Photos-Metadaten, Videoorte auch aus verfügbaren QuickTime-Metadaten. Eine Aufnahme direkt in der App verwendet nur einen verfügbaren frischen Standort mit System- und App-Freigabe. Fehlende historische Orte werden nicht mit dem heutigen Standort ersetzt. Der Teilen-Dialog erlaubt das Weglassen der Kartenmarkierung.

Wichtig: Der Orts-Schalter betrifft die separat geteilte Kartenmarkierung. Eine unverändert geteilte Originaldatei kann weiterhin eingebettete Ortsdaten enthalten. Die App behauptet keine vollständige Metadatenbereinigung.

## Drop-Poop

Euer privates Thronarchiv mit Thronchronik und Kack-Karte. Einträge haben einen frei gewählten Titel, Notiz, Zeitpunkt, Minuten Sitzfleisch, Legendenstufe und ein Symbol. Nach Person filterbar; nur der jeweilige Verfasser darf bearbeiten oder löschen. Vorhandene App-Daten und Freigaben bleiben erhalten.

Ein Ortsname funktioniert ohne GPS. Eine Kartenmarkierung ist zunächst aus und wird nur nach bewusster einmaliger Standortübernahme gespeichert. Kein automatisches Toiletten-Tracking. Der neue Schnellzugriff, ein Homescreen-Widget, der Kontrollzentrum-Button und der App-Kurzbefehl öffnen den Eintrag zum Bestätigen. Sie speichern keinen stillen Eintrag und keinen Standort im Hintergrund. Kontrollzentrum- und Widget-Funktion setzen eine passend signierte Erweiterung samt bestehender App Group voraus.

## Unsere Zeit

Die optionale Startseitenkarte und ein neues Widget verwenden den eingetragenen Beziehungsbeginn. Sie zeigen volle gemeinsame Monate, den laufenden Beziehungsmonat, gemeinsame Kalendertage und den nächsten Monatstag/Jahrestag. Beispiel: fünf volle Monate bedeuten, dass ihr im sechsten Beziehungsmonat seid. Monatsenden werden auf den letzten gültigen Tag begrenzt, ohne den ursprünglichen Starttag für spätere Monate zu verlieren. Ein zukünftiger Beginn wird als Vorfreude angezeigt.

Unter Startseite anpassen könnt ihr Unsere Beziehungsmonate und Drop-Poop hinzufügen. Neue Schnellzugriffe umfassen Drop-Poop, Drop setzen und Momentkarte. Bisherige persönliche Layouts bleiben bestehen; neue Karten werden nicht ungefragt eingeschaltet.

## Aktualisieren

App und Server brauchen mindestens 3.8.0; Protokollgeneration bleibt 5. Zuerst den laufenden Server stoppen, bestehende Konfiguration und Daten sichern, nur Backend/rj_love_server.py ersetzen und wieder starten. rjapp_config.json, Datenbank und Medienordner behalten. Die zusätzliche Tabelle wird automatisch angelegt. Danach beide iPhones über die bestehende Installation aktualisieren, App-IDs und App Group beibehalten und Haupt-App sowie Widget signieren. Alte App-Versionen erhalten den bestehenden Updatehinweis. Bestehende OpenAI-Einstellungen bleiben unverändert; Drop-Poop-Einträge werden nicht an die KI-Zusammenfassung übergeben.

## Gezielte Prüfung

54 Backendprüfungen einschließlich der vorhandenen Regressionen und drei neuen Prüfungen für Streamingberechtigung/Bytebereiche, alte Momentoriginale und Drop-Poop. Zusätzlich Kalenderberechnungen an Monatsgrenzen, Schaltjahr und zukünftigem Beginn. Der iOS-Simulator prüft Profil/Status, die echte Audioqueue am isolierten Testserver sowie Galerieöffnung und Speichern eines Drop-Poop-Eintrags. Simulatorbilder zeigen die neuen Ansichten. Physische iPhone-, Sideload-Signierungs- und Fremdformatprüfungen werden dadurch nicht ersetzt.
