# Aktuelle Änderungen 3.0

Walkie-Talkie, Push-to-Talk und die eigene Face-ID-Sperre sind entfernt. Süße Sprachnachrichten werden beim Öffnen auf Wunsch mit der eingestellten Medienlautstärke abgespielt; die automatische Wiedergabe ist zunächst eingeschaltet und abschaltbar. App-Öffnung und erste Nachrichtenöffnung werden gespeichert. Fotowünsche sind zunächst eingeschaltet und abschaltbar; die Kamera ist sichtbar, benötigt iOS-Zustimmung und zählt vor der Aufnahme abbrechbar herunter. Keine Hintergrundkamera. Das aufgenommene Foto wird automatisch geteilt und lässt sich vom Aufnehmenden zurückrufen.

Neue Furze teilen einen verfügbaren frischen Aufnahmeort standardmäßig. Der Aufnahmeort-Schalter ist abschaltbar; fehlende Systemfreigaben werden nicht umgangen. Lokale Kopien von Furzen bleiben unabhängig von späteren Serverlöschungen erhalten. Fotos, Videos und Live-Photo-Bestandteile liegen als authentifiziert abrufbare Dateien auf dem eigenen Server; Backups enthalten diese Dateien. Kein Cloud-Analyse- oder Transkriptionsdienst und keine Ende-zu-Ende-Verschlüsselung.

Nur verknüpfte RJ-Love-Termine und Aufgaben werden mit Apple Kalender/Erinnerungen abgeglichen. Exakte Herzzeitpunkte werden ab 3.0 gespeichert; alte Tageszähler werden nicht in erfundene Einzelereignisse umgewandelt. Private Feather-Quelladressen erlauben ausschließlich Abruf der freigegebenen App-IPA und ihres Icons; bei Bedarf neu erzeugen und dadurch widerrufen.

Die nachfolgenden Abschnitte beschreiben die bisherigen Datenformate und Aufbewahrung. Angaben zu Walkie-Talkie und eigener App-Sperre gelten ausschließlich für Versionen bis 2.4; sie sind in 3.0 entfernt.

# Datenschutz — RJ Love 3.0

RJ Love ist für Robin und Raphaela vorgesehen. Kein Tracking-SDK, keine Werbung und keine Analyseplattform. Inhalte sind nicht Ende-zu-Ende-verschlüsselt; der Betreiber eures eigenen Servers kann sie lesen. HTTPS schützt die Übertragung.

## Einrichtung und Freigaben

Die geführte Einrichtung fragt die benötigten Systemberechtigungen einzeln ab. Danach sind Standort, Health-Kategorien und WLAN-Name als App-Freigaben eingeschaltet. iOS entscheidet weiterhin, welche Daten tatsächlich zugänglich sind; eine Ablehnung wird nicht umgangen. Einstellungen lassen sich jederzeit einzeln ausschalten und werden bei späteren Starts beibehalten. Health erlaubt getrennte Weitergabe von Aktivität, Schlaf und Vitalwerten. Kalender werden nicht vollständig ausgelesen oder hochgeladen. Fotos werden über Apples geschützten Systembildwähler ausgewählt. Die Nahbereichssuche fragt erst bei der tatsächlichen Verbindung beider Geräte nach ihrer Freigabe. Fokus-Status wird weder angefragt noch geteilt.

Ein neuer vollständiger Status ersetzt den alten. Abschalten einer Kategorie entfernt deren zuvor geteilte Werte beim nächsten erfolgreichen Upload. Bereits offline gespeicherte Kopien verschwinden beim nächsten Abgleich; ein ausgeschaltetes Gerät kann nicht aus der Ferne bereinigt werden.

## Zugang und private Daten

Passwörter liegen serverseitig als gesalzene scrypt-Hashes, Sitzungstokens als Hashes vor. Auf dem iPhone liegt das Token im gerätegebundenen Schlüsselbund, für Hintergrundempfang nach dem ersten Entsperren zugänglich. Offline-Snapshots nutzen iOS-Dateischutz. Eine eigene Face-ID-/Gerätecode-Sperre gibt es in 3.0 nicht mehr; eine von iOS angebotene App-Sperre kann unabhängig davon genutzt werden.

Eine neue Anmeldung widerruft die alte Sitzung desselben Kontos und entfernt deren Push- und Nahbereichsregistrierungen. Beim nächsten Kontakt erhält das alte Gerät HTTP 401 und löscht seine lokale Sitzung sowie den Widget-Snapshot. Bis dahin können vorhandene Offlinedaten noch sichtbar sein.

Geteilte Texte und Positionen liegen in SQLite auf eurem Server; Audio, Fotos und Videos im separaten Medienverzeichnis. APNs nutzt Apple für Benachrichtigungen und zulässige Hintergrundhinweise. Optionale ntfy-Hinweise enthalten nur einen allgemeinen App-Hinweis, keine Koordinaten, Health-Werte oder Nachrichtentexte. Geheime Topics, APNs-Schlüssel, Konfiguration, Logs und Backups vertraulich behandeln.

UWB-Tokens werden dem Gegenüber bis zu 20 Sekunden vermittelt und beim Beenden der Suche oder Sitzungswechsel entfernt. Normale gemeinsame Einträge verwenden serverseitig eine Löschmarkierung. Frühere SQLite-Seiten und externe Sicherungen können gelöschte Bytes weiter enthalten.

## Duftpost und Schnittarchiv

Das Mikrofon wird in der Einrichtung oder beim ersten Aufnehmen angefragt. Die sichtbare Aufnahme startet nur durch deine Aktion; iOS zeigt den Mikrofonindikator. Das Widget öffnet die App und startet nach Freigabe eine Aufnahme. Clips sind auf 60 Sekunden begrenzt, beim Wechsel in den Hintergrund wird gestoppt. Ein Entwurf bleibt mit Dateischutz lokal. Erst „Duftpost senden“ lädt ihn hoch. Ein Upload-Fehler behält den Entwurf.

Audio wird authentifiziert geladen; es gibt keine öffentlichen Audio-Links. Geteilte Duftpost wird nicht automatisch abgespielt. Nur der Eigentümer darf schneiden, umbenennen und löschen; nur das Gegenüber darf bewerten. Das Original und jede spätere Schnittversion bleiben bewusst im Serverarchiv erhalten. „Löschen“ entfernt das gesamte aktive Aufnahmeverzeichnis einschließlich aller Fassungen sowie Bewertungen und Reaktionen aus den Tabellen. Bestehende Backups bleiben erhalten. Schnittvorschauen verwenden vorübergehende lokale Dateien, die beim Schließen entfernt werden. Abmeldung entfernt lokale Recorder-Entwürfe.

Sterne sind Spaßbewertungen; die Wellenform zeigt Aufnahmepegel, keinen objektiven Geruch oder Qualitätswert. Die Aufnahme-Live-Aktivität zeigt nur den Recorderstatus.

## Backups

Der integrierte Backup-Befehl erstellt ein Archiv aus konsistentem Datenbank-Snapshot, Mediendateien und Konfiguration. Es ist nicht zusätzlich verschlüsselt und kann sensible Inhalte und Zugangskonfiguration enthalten. Der Betreiber bestimmt Speicherort, Aufbewahrung und externe Verschlüsselung. Extern abgelegte APNs-Privatschlüssel separat sichern. Details: [RELEASE-2.2.md](RELEASE-2.2.md).

## Zustellungsdiagnose ab 2.3

Geräteregistrierung speichert zusätzlich die Bundle-ID und, falls auslesbar, die Signing-Team-ID zur Prüfung der APNs-Zuordnung. APNs-Zustellungsdiagnosen enthalten Status, Fehlergrund und Zeitpunkt, keine Provider-Schlüssel oder Gerätetokens; sie werden nach sieben Tagen gelöscht. Weckrufbestätigungen speichern AlarmKit-Planungsstatus und Fehlergrund. Der eigenständige Hintergrundabruf lädt nur Weckaufträge und Erinnerungen. Das Profil wird ausschließlich aus dem eigenen installierten App-Bundle gelesen.

## Duftstudio 2.4

Aufnahmezeit, selbst gewählte Situation und optional ausdrücklich mitgesendeter Aufnahmeort werden als Metadaten gespeichert. Orte lassen sich später vom eigenen Eintrag entfernen; bereits externe Backups bleiben unverändert. Die Karte ruft Kartendaten über Apple MapKit ab. Sprüche werden lokal ausgewählt. Die Versionsprüfung übermittelt App-Version und Protokollgeneration an euren eigenen Server. Die automatische APNs-Erkennung liest ausschließlich konfigurierte Schlüsselpfade, definierte Umgebungsvariablen und die beschriebenen Schlüsseldateien im Konfigurations-/Push-Ordner. Private Schlüssel werden niemals an die App übertragen.
