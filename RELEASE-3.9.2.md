# RJ Love 3.9.2 (392)

## Aktualisieren ohne neue Einrichtung

Vorhandene `rjapp_config.json`, Datenverzeichnis und SQLite-Datei behalten. Nur die Python-Datei ersetzen und mit dem bisherigen Befehl neu starten. Dann die neue IPA wie bisher signieren und installieren. Bestehende Bark-Geräteschlüssel, ntfy-Topics, Konten, Medien und Beiträge aus 3.9/3.9.1 bleiben erhalten. Die SQLite-Erweiterung ergänzt nur einen Galerieindex. Neue App braucht Server 3.9.2; ältere Apps bleiben mit dem Server kompatibel.

## Galerie

Drei gleich große quadratische Zellen je Reihe, feste Bildgrenzen und drei Pixel Abstand. Hochkantfotos und Videos können die Nachbarzellen nicht mehr auseinanderdrücken. Vertikales Scrollen, Monatsabschnitte, Suche, Alben und Karte bleiben erhalten.

Neue Galerie-API lädt 60 Datensätze pro Seite mit stabilem Datum-/ID-Cursor. Such- und Albumfilter laufen auf dem Server. Das Raster bekommt Metadaten statt eingebetteter Originaldateien und großer Vorschau-Strings. Neuere Apps erhalten auch beim Start kompakte Momentdaten. Originale bleiben gespeichert; alte Clients bekommen weiter ihr gewohntes Format. Bilddateien werden erst für sichtbare Zellen geladen und außerhalb der UI auf höchstens 500 Pixel heruntergerechnet. Der decodierte Cache bleibt auf 24 MB / 100 Bilder begrenzt. Höchstens zwei gleichzeitige Downloads bzw. fehlende Videovorschauen; beim Verlassen einer Zelle wird deren Bildreferenz freigegeben. Bei sehr alten Fotos ohne Vorschaubild muss einmalig die Originaldatei übertragen werden, sie wird auf dem Gerät heruntergerechnet. Große Originalvideos werden im Raster nicht vollständig geladen.

## Nachrichten und Fotowünsche

Im Plus-Menü des Chats „Als dringende Nachricht senden“ wählen. Die nächste Textnachricht erhält eine Kennzeichnung. Bark: `timeSensitive`, kurzer normaler Hinweiston, kein `critical`, kein `call`, keine Wiederholung. ntfy: erhöhte normale Priorität. Ruhezeit: leiser/passiver Bark-Hinweis, manuelles Nicht-stören unterdrückt die Nachricht. Der vorhandene Weckruf bleibt getrennt.

Ein erfolgreich beantworteter Fotowunsch erzeugt genau eine Nachricht an den ursprünglichen Absender: „… hat deinen Fotowunsch erfüllt“. Sie führt direkt zum Foto. Foto, Erledigt-Status, Benachrichtigung und Versandauftrag werden zusammen gespeichert; ein wiederholter Uploadabschluss erzeugt keine zweite Erfolgsmeldung. Die noch unbeantwortete Anfrage wird weiterhin nicht extern verraten.

## Widgets und Signierung

Die vom Nutzer bereitgestellten Development-/Distribution-Profile enthalten als App-ID `app.lake6191.velvet1751` und fünf fremd benannte App Groups. Keine privaten Schlüssel oder Profile wurden ins Repository übernommen.

Beide Targets fordern nun dieselbe bereits in diesen Profilen erlaubte Gruppe `group.dfbc88d056a46f1b.1` an. Konfiguration ist in beiden Info.plists identisch. Der Speicher prüft den Container und verwendet keinen stillen privaten `.standard`-Fallback mehr. Ohne Container zeigt das Widget „Widget nicht verbunden“ und ein Herz-Intent behauptet nicht, einen Gedanken gespeichert zu haben. Vorhandene erreichbare ältere Snapshot-/Herzwarteschlangen werden in die gemeinsame Gruppe übernommen, ohne gespeicherte IDs doppelt anzulegen. Die Haupt-App behält ihre bisherigen Bundle-IDs; eine automatische Identitätsänderung könnte lokale Daten verlieren und wird daher nicht durchgeführt.

**Die Profile allein reichen nicht aus:** Beide hochgeladenen Profile gelten für dieselbe Haupt-App-ID. Die Widget-Erweiterung braucht weiterhin ein eigenes gültiges Profil für ihre eigene Bundle-ID und dieselbe Gruppe. Diese Apple-Freigabe lässt sich nicht im Quellcode oder durch Kopieren eines Entitlements erzeugen. In „Funktionen & Signatur → App Group & Erweiterung prüfen“ werden Container, App-/Widget-Profil und der letzte tatsächliche Widget-Zugriff sichtbar. Eine unsigned IPA ist noch kein Nachweis einer korrekten Gerätesignierung. Alte App-Daten bleiben beim Update nur mit derselben tatsächlichen App-Identität des bisherigen Signierdienstes erreichbar.

Neues Widget „Schatzi finden“: Name, freigegebene Entfernung, Zeitstempel und Link zur Partnerkarte. Keine Koordinaten werden ins Widget geschrieben. Entfernung nur bei beidseitiger aktiver Freigabe, erlaubtem Standort und Messungen jünger als 30 Minuten; fehlende Freigaben oder veraltete Daten erhalten einen klaren Text. Abmelden leert den Snapshot und die Warteschlange wie bisher. Ein Widget-Refresh wird angefordert, die sichtbare Ausführung bestimmt iOS.

## Live-Aktivität und Dynamic Island

Überarbeitete Partnerkarte mit Status/Ruhezeit, Herzen, Akku und direkten Links zu Karte und Chat; optional bleibt die Duftpost-Aktion. Die kompakte Insel markiert veraltete Daten mit einer Uhr. Unveränderte Inhalte werden nicht bei jedem Poll erneut an ActivityKit gesendet. Bestehende Activity-Modelle bleiben unverändert kompatibel.

Bark/ntfy aktualisieren keine fremde RJ-Live-Aktivität im Hintergrund. Lokale Aktualisierungen erfolgen beim RJ-Abgleich; Fernaktualisierung über Apples ActivityKit benötigt weiterhin eigene passende APNs-Konfiguration. iOS entscheidet über Laufzeit und Sichtbarkeit. Die bereitgestellten Profile enthalten weder eigene Critical-Alert- noch Location-Push-Extension-Freigaben; das Update fordert diese nicht an.

## Prüfungen

Bestehende Backend-Tests plus zusätzliche Tests für 135 alte Galerieeinträge über mehrere Seiten, kompakte Payloads, alte Originale/Vorschaubilder nach Bearbeitung, dringende Hinweise ohne Alarmwiederholung, Ruhezeiten und idempotente Fotowunsch-Erfolgsmeldung. Ein Swift-Geometrietest prüft iPhone-/iPad-Breiten; der Simulator prüft die drei echten Zellen und erstellt einen Screenshot. Physische Widget-Signierung und Empfang/Klang auf dem eigenen iPhone abschließend testen.

Apple-Grundlagen: https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date
