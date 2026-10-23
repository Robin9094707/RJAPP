# RJ Love 3.4.0 (340)

## Health und Schlaf

Health → Meine Daten bietet eine erneute iOS-Lesefreigabe auf jedem iPhone. Beim ersten Öffnen nach diesem Update erklärt ein eigener Hinweis die zusätzlichen Daten. Bestehende Weitergabe-Einstellungen bleiben erhalten; Schlaf, Aktivität und Vitalwerte bleiben getrennt abschaltbar.

Die letzte Hauptnacht zeigt echte REM-, Kern-, Tiefschlaf- und aufgezeichnete Wachphasen, eine Zeitachse, Schlafanteil, Wachabschnitte, Datenquelle und bis zu 13 vorherige Nächte. Die Auswertung bevorzugt eine Datenquelle pro Nacht und verrechnet überlappende Phasen ohne doppelte Minuten. Grobe Schlafdaten werden nicht in erfundene REM- oder Tiefschlafwerte umgewandelt. Kurze Nickerchen ersetzen keine vorhandene Hauptnacht.

Der **RJ-Schlafindex** ist eine eigene, offengelegte Schätzung, keine identische Nachbildung oder Auslesung von Apples Score. Er gewichtet Dauer bis 50, Regelmäßigkeit bis 30 und Unterbrechungen bis 20 Punkte. Die Dauer bezieht sich auf das einstellbare Schlafziel. Regelmäßigkeit vergleicht die Einschlafzeit kreisförmig über Mitternacht mit bis zu 13 vorherigen Hauptnächten; Abweichungen bis zwei Stunden senken die Punkte linear. Unterbrechungen berücksichtigen aufgezeichnete Wachminuten und Wachabschnitte. Ohne mindestens drei Vergleichsnächte und verwertbare Wachinformationen bleibt der Gesamtwert leer. Apples interne Kurven und Originalscore sind damit nicht identisch. Quelle für die öffentlich beschriebene Gewichtung: https://support.apple.com/en-us/108906.

Zusätzlich: Radstrecke, Ruheenergie, Stehzeit, Gehpuls, Handgelenk- und Körpertemperatur, Cardiofitness, Gewicht, Gehgeschwindigkeit, Schrittlänge und Blutdruck. Messwerte hängen von euren Geräten und Health-Quellen ab. Fehlende Werte bleiben leer. Heutige Aktivität und letzte Einzelmessungen (höchstens 30 Tage) werden unterschieden; einzelne Werte zeigen ihr Datum. Bewegung & Fitness besitzt passende Symbole, Berechtigungszugang und Erkennungssicherheit. Kein medizinischer Mess- oder Diagnosedienst.

## Nahsuche

Die Verbindung wartet auf den lokalen Discovery-Token, veröffentlicht ihn erneut und unterscheidet den gefundenen Partner von einem tatsächlich empfangenen UWB-Messsignal. Die Kamera ist sichtbar, zeigt Kalibrierhinweise und pausiert außerhalb der Suchansicht. Ohne Messfortschritt wechselt die Suche nach etwa 15 Sekunden zur normalen UWB-Messung. Suspendierte Sitzungen werden wieder aufgenommen; ungültige Sitzungen werden begrenzt neu aufgebaut. Ein verzögertes Beenden einer alten Sitzung löscht keinen bereits neu veröffentlichten Token mehr.

Startet auf beiden UWB-fähigen iPhones die Suche. Bei Kamera-Unterstützung ein iPhone ruhig halten und das andere langsam seitlich/auf-ab bewegen. Gute Beleuchtung und sichtbare Raumdetails helfen. Ohne verfügbare Live-Aktivität bleibt die Suche im Vordergrund möglich. iOS, Hardware, Signierung und Signalumgebung bestimmen die tatsächliche Verfügbarkeit.

## IPA und persönliches Icon

Der Dokumentenpicker lässt jetzt Dateien unabhängig von uneinheitlichen IPA-Typregistrierungen auswählen. Die App prüft danach .ipa-Endung und ZIP-Kennung, liest die Datei koordiniert auch von Dateianbietern und lädt eine temporäre lokale Kopie hoch. Die vorhandene serverseitige Prüfung kontrolliert weiterhin Bundle, Version und IPA-Inhalt. ZIP-Komplettpakete vorher in Dateien entpacken und die enthaltene IPA wählen.

Neues Icon in `Design/RJ-AppIcon-3.4.png`, mit allen App-Icon-Größen und BrandMark eingebaut. Erzeugt mit dem integrierten Bildgenerator aus dem bereitgestellten Paarfoto und dem vorhandenen Icon als Stilreferenz. Gestaltungsanweisung: wiedererkennbare Gesichter nebeneinander, glänzendes rosa-violettes Glasherz, weiche Lichtreflexe, perlmuttfarbene RJ-Buchstaben und kleine Duftwolke; quadratisch, vollflächig und ohne vorgezeichnete iOS-Außenrundung.

## Aktualisieren ohne Datenverlust

1. Server stoppen, nur `Backend/rj_love_server.py` ersetzen und mit unverändertem Startbefehl neu starten. Konfiguration und Datenordner behalten; vor dem Austausch sichern.
2. Auf beiden iPhones IPA mit den bisherigen App-/Widget-IDs und passenden Capabilities signieren und über die vorhandene App installieren. Nicht vorher löschen.
3. Auf beiden Geräten Health-Leserechte erweitern; unter Health → Meine Daten die gewünschten Weitergabe-Kategorien prüfen. Eine Apple Watch oder andere passende Health-Quelle muss Schlafphasen tatsächlich aufzeichnen.

App und Server benötigen mindestens 3.4.0. Ältere Apps mit Versionsprüfung erhalten nach Serverupdate eine Updateaufforderung. Die neuen Health-Daten verwenden das bestehende optionale Präsenzformat; bestehende Konten, Fotos, Duftpost, Kommentare, Status und Termine bleiben erhalten. Es gibt keine destruktive Datenmigration. Das Paket enthält keine persönlichen Serverdaten oder Schlüssel.

## Prüfung

Bestehende Backend-Tests plus zwei gezielte Regressionen für erweiterte Health-Übertragung/Validierung/Löschung und sitzungsgebundenen UWB-Tokenwiderruf. Kleine Swift-Prüfung für Quellen-Deduplizierung, fehlende Vergleichsdaten und überlappende Wachphasen. GitHub Actions baut App und Widget und prüft die fertige IPA. Health-Freigaben, Dateianbieter und UWB mit Kamera benötigen anschließend eine Prüfung auf den tatsächlichen iPhones.
