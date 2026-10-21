# Datenschutz — RJ Love 2.2

RJ Love ist für Robin und Raphaela vorgesehen. Kein Tracking-SDK, keine Werbung und keine Analyseplattform. Inhalte sind nicht Ende-zu-Ende-verschlüsselt; der Betreiber eures eigenen Servers kann sie lesen. HTTPS schützt die Übertragung.

## Einrichtung und Freigaben

Die geführte Einrichtung fragt die benötigten Systemberechtigungen einzeln ab. Danach sind Standort, Health-Kategorien und WLAN-Name als App-Freigaben eingeschaltet. iOS entscheidet weiterhin, welche Daten tatsächlich zugänglich sind; eine Ablehnung wird nicht umgangen. Einstellungen lassen sich jederzeit einzeln ausschalten und werden bei späteren Starts beibehalten. Health erlaubt getrennte Weitergabe von Aktivität, Schlaf und Vitalwerten. Kalender werden nicht vollständig ausgelesen oder hochgeladen. Fotos werden über Apples geschützten Systembildwähler ausgewählt. Die Nahbereichssuche fragt erst bei der tatsächlichen Verbindung beider Geräte nach ihrer Freigabe. Fokus-Status wird weder angefragt noch geteilt.

Ein neuer vollständiger Status ersetzt den alten. Abschalten einer Kategorie entfernt deren zuvor geteilte Werte beim nächsten erfolgreichen Upload. Bereits offline gespeicherte Kopien verschwinden beim nächsten Abgleich; ein ausgeschaltetes Gerät kann nicht aus der Ferne bereinigt werden.

## Zugang und private Daten

Passwörter liegen serverseitig als gesalzene scrypt-Hashes, Sitzungstokens als Hashes vor. Auf dem iPhone liegt das Token im gerätegebundenen Schlüsselbund, für Hintergrundempfang nach dem ersten Entsperren zugänglich. Offline-Snapshots nutzen iOS-Dateischutz. Face ID/Gerätecode wird während der Einrichtung angeboten und kann später deaktiviert werden.

Eine neue Anmeldung widerruft die alte Sitzung desselben Kontos und entfernt deren Push-, Funk- und Nahbereichsregistrierungen. Beim nächsten Kontakt erhält das alte Gerät HTTP 401 und löscht seine lokale Sitzung sowie den Widget-Snapshot. Bis dahin können vorhandene Offlinedaten noch sichtbar sein.

Geteilte Inhalte, Bilder und Positionen liegen in SQLite auf eurem Server; Audiodateien im separaten Medienverzeichnis. APNs nutzt Apple; Walkie-Talkie-Pushes enthalten den Sprechernamen und die Übertragungsnummer, keine Audiodaten. Optionale ntfy-Hinweise enthalten nur einen allgemeinen App-Hinweis, keine Koordinaten, Health-Werte oder Nachrichtentexte. Geheime Topics, APNs-Schlüssel, Konfiguration, Logs und Backups vertraulich behandeln.

UWB-Tokens werden dem Gegenüber bis zu 20 Sekunden vermittelt und beim Beenden der Suche oder Sitzungswechsel entfernt. Normale gemeinsame Einträge verwenden serverseitig eine Löschmarkierung. Frühere SQLite-Seiten und externe Sicherungen können gelöschte Bytes weiter enthalten.

## Duftpost und Schnittarchiv

Das Mikrofon wird in der Einrichtung oder beim ersten Aufnehmen angefragt. Die sichtbare Aufnahme startet nur durch deine Aktion; iOS zeigt den Mikrofonindikator. Das Widget öffnet die App und startet nach Freigabe eine Aufnahme. Clips sind auf 60 Sekunden begrenzt, beim Wechsel in den Hintergrund wird gestoppt. Ein Entwurf bleibt mit Dateischutz lokal. Erst „Duftpost senden“ lädt ihn hoch. Ein Upload-Fehler behält den Entwurf.

Audio wird authentifiziert geladen; es gibt keine öffentlichen Audio-Links. Geteilte Duftpost wird nicht automatisch abgespielt. Nur der Eigentümer darf schneiden, umbenennen und löschen; nur das Gegenüber darf bewerten. Das Original und jede spätere Schnittversion bleiben bewusst im Serverarchiv erhalten. „Löschen“ entfernt das gesamte aktive Aufnahmeverzeichnis einschließlich aller Fassungen sowie Bewertungen und Reaktionen aus den Tabellen. Bestehende Backups bleiben erhalten. Schnittvorschauen verwenden vorübergehende lokale Dateien, die beim Schließen entfernt werden. Abmeldung entfernt lokale Recorder-Entwürfe.

Sterne sind Spaßbewertungen; die Wellenform zeigt Aufnahmepegel, keinen objektiven Geruch oder Qualitätswert. Die Aufnahme-Live-Aktivität zeigt nur den Recorderstatus.

## Walkie-Talkie und Vorlesen

Nach der Einrichtung sind Funkempfang und Vorlesen eingeschaltet. Eingehendes Audio oder Funktexte können dann auch bei gesperrtem Bildschirm laut ausgegeben werden. Beide Schalter sind getrennt abschaltbar; „Kanal verlassen“ beendet den Empfang. Das Mikrofon sendet ausschließlich während betätigter Sprechtaste, höchstens 30 Sekunden. Es wird kein fremdes Mikrofon aus der Ferne aktiviert.

Kurze Audioteile und Funktexte bleiben höchstens zehn Minuten als Übertragungspuffer im Server-Datenbestand verfügbar; der minütliche Bereinigungslauf entfernt alte Einträge auch ohne weitere Funkaktionen. Ein Backup kann solche flüchtigen Daten als Teil des Datenbank-Snapshots enthalten. Funktexte in der App werden nur für die laufende Sitzung angezeigt und nicht als dauerhafter Chat gespeichert. iOS-Sprachausgabe erzeugt das Vorlesen lokal. Systemkanal, Hintergrundlaufzeit und Push sind abhängig von iOS, Signierprofil und APNs-Konfiguration.

## Backups

Der integrierte Backup-Befehl erstellt ein Archiv aus konsistentem Datenbank-Snapshot, Mediendateien und Konfiguration. Es ist nicht zusätzlich verschlüsselt und kann sensible Inhalte und Zugangskonfiguration enthalten. Der Betreiber bestimmt Speicherort, Aufbewahrung und externe Verschlüsselung. Extern abgelegte APNs-Privatschlüssel separat sichern. Details: [RELEASE-2.2.md](RELEASE-2.2.md).
