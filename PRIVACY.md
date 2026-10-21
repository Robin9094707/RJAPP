# Datenschutz — RJ Love 2.2

RJ Love ist für genau zwei konfigurierte Konten vorgesehen. Kein Tracking-SDK, keine Werbung, keine Analyseplattform.

- Health- und Standortfreigaben sind bei frischer Installation aus. Health erlaubt getrennte Weitergabe von Aktivität, Schlaf und Vitalwerten. Keine Kalender werden im Hintergrund ausgelesen und hochgeladen.
- Der Server speichert die bewusst geteilten Zusammenfassungen, Fotos, Inhalte und Positionen in einer lokalen SQLite-Datei. Inhalte sind nicht Ende-zu-Ende verschlüsselt; der Serverbetreiber kann sie lesen. Im Internet HTTPS verwenden. Datenbank und Sicherungen selbst verschlüsseln bzw. Zugriffe absichern.
- Ein neuer vollständiger Status ersetzt den alten: Beim Abschalten einer Kategorie entfernt der nächste erfolgreiche Upload zuvor geteilte Werte dieser Kategorie. Bereits offline angezeigte Kopien verschwinden erst beim nächsten Abgleich und können nicht aus der Ferne aus einem ausgeschalteten Gerät gelöscht werden.
- Passwörter werden beim regulären Serverstart und bei Änderungen als gesalzene scrypt-Hashes gespeichert. Sitzungstokens liegen serverseitig nur gehasht. Auf dem iPhone wird das Sitzungstoken im Schlüsselbund gespeichert; Offline-Snapshots nutzen iOS-Dateischutz. Face ID/Gerätecode ist optional.
- Eine neue Anmeldung widerruft vorherige Tokens desselben Kontos. Alte Geräte erhalten beim nächsten Serverkontakt HTTP 401 und löschen ihre lokale Sitzung sowie Widget-Snapshot. Offlinedaten können bis zu diesem Kontakt noch sichtbar sein.
- UWB-Discovery-Tokens werden nur an das verbundene Gegenüber vermittelt und nach 20 Sekunden nicht mehr ausgeliefert. Beim Beenden der Suche werden sie aktiv gelöscht. Login-Wechsel entfernt sie ebenfalls. Entfernen aus dem Datenbestand erfolgt auch beim nächsten Upload oder bei Abmeldung.
- Optionale APNs-Mitteilungen nutzen Apple. Optionale ntfy-Hinweise nutzen den konfigurierten Betreiber; sie enthalten nur einen allgemeinen Hinweis, keine Koordinaten, Health-Werte oder Nachrichtentexte. Geheime Topics vertraulich halten.
- Geteilte Einträge können in der App gelöscht werden. Serverseitig ist dies eine Löschmarkierung; zur vollständigen Entfernung alter Daten und Sicherungen ist der Serverbetreiber zuständig. Derzeit existiert kein automatischer Lösch-/Export-Assistent.
- Die Konfigurationsdatei, Logs, Konsolen-Reset-Ausgaben und Sicherungen sind vertraulich und dürfen nicht ins öffentliche GitHub-Repository gelangen.


## Private Audioaufnahmen

Mikrofonzugriff wird erst nach einer Aufnahmeaktion abgefragt. Der Recorder ist sichtbar; iOS zeigt den Mikrofonindikator. Ein Widget kann die App direkt in die Aufnahmeansicht öffnen. Es werden nur ausdrücklich gestartete Clips bis 60 Sekunden aufgenommen. Pause, Stopp und Verwerfen stehen bereit. Beim Verlassen in den Hintergrund wird gestoppt.

Ein Entwurf liegt mit iOS-Dateischutz lokal im App-Ordner. Erst die Senden-Aktion lädt ihn auf den eigenen Server hoch. Anhören lädt Audio nur nach Nutzeraktion; es gibt keinen öffentlichen Audio-Link und kein automatisches Abspielen eingehender Clips. Die aktive App-Anmeldung ist bei jedem Download erforderlich. Playback nutzt einen flüchtigen Speicherpuffer. Bei Abmeldung werden lokale Entwürfe gelöscht. Aufnahmen sind für beide Konten sichtbar. Nur der Ersteller kann sie löschen; nur das Gegenüber kann bewerten. Audio/zugehörige Wertungen werden beim Löschen aus den aktiven Tabellen entfernt. Serverseitige SQLite-Freiseiten und eigene Sicherungen können frühere Bytes enthalten; deren sichere Löschung liegt beim Serverbetreiber. Keine Ende-zu-Ende-Verschlüsselung.

Die Aufnahme-Live-Aktivität zeigt nur den laufenden Recorder, keine geteilten Audioinhalte. Optionale Push-Dienste erhalten nur einen allgemeinen Hinweis auf neue Duftpost. Sterne sind manuelle Spaßbewertungen; Wellenformen sind Aufnahmepegel, keine objektive Geruchs- oder Qualitätsmessung.

## Update 2.2

Die Änderungen, Einrichtungsanleitung, Medienstruktur, Backup-Befehle und Voraussetzungen für Walkie-Talkie stehen in [RELEASE-2.2.md](RELEASE-2.2.md). Der Fokus-Status entfällt vollständig. Die neue geführte Einrichtung startet Freigaben eingeschaltet; jede iOS-Berechtigung wird separat angefragt. Funk puffert Audio und Texte höchstens zehn Minuten auf eurem eigenen Server.
