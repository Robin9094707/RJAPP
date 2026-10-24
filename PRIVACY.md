## Ergänzung 3.9 · Bark und ntfy

Der je Konto gewählte externe Push-Dienst und Apple APNs erhalten auf ausdrücklichen Wunsch vollständige Benachrichtigungsinhalte. Bark-Symbole sind öffentlich; Bildvorschauen verwenden HMAC-signierte, auf genau einen Datensatz begrenzte Links mit einem Tag Gültigkeit. Ein Zurückrufen sperrt weitere Abrufe auf eurem Server, löscht aber keine bereits heruntergeladenen Bark-Kopien. Jeder sieht nur seine eigenen Geräteschlüssel, Topic-/Zugangsdaten und privaten Automations-Webhook. Partner sehen den gewählten Dienst und den aktiven Ruhetext/-zeitraum, keine Zugangsschlüssel. Ruhezeiten werden serverseitig durchgesetzt, auch für direkte Bark-Aufrufe. Details: [RELEASE-3.9.md](RELEASE-3.9.md).

## Ergänzung 3.8

Momentvideos werden über zeitlich begrenzte, auf Datei und aktuelle Anmeldung gebundene Wiedergabelinks in Bytebereichen geladen. Die App legt dabei keine dauerhaften Videodateien an; iOS kann puffern. Die Linkschlüssel stehen nicht in den normalen Serverlogs. Abmeldung, Ablauf oder eine aufgehobene Medienfreigabe verhindern weitere Abrufe. Die Serverdatenbank speichert nur Hashes der Linkschlüssel. Vollständige Momentfotos werden erst beim Öffnen geladen; temporäre Originaldateien werden beim Verlassen entfernt. Vorschaubilder bleiben begrenzt im Arbeitsspeicher. Alte eingebettete Originalfotos werden nicht mehr in lokalen Offline-Snapshots gespeichert und bleiben auf dem Server erhalten.

Optionale Komprimierung verändert nur die hochgeladene Kopie, nicht die Originale in Apple Fotos. Der Karten-Schalter entfernt die separat geteilten Koordinaten, bereinigt unveränderte Originaldateien jedoch nicht von allen eingebetteten Metadaten. Karten verwenden Apple MapKit. Drop-Poop speichert freiwillige Texte, Zeit, Minuten, Spaßbewertung und optional einen bewusst übernommenen Standort im gemeinsamen privaten Datenbestand. Keine automatische Erfassung und kein Toilettenhintergrundtracking. Kontrollzentrum, Widget und Kurzbefehl öffnen einen zu bestätigenden Eintrag. Diese Daten werden nicht für den KI-Rückblick verwendet. Beziehungsmonate werden aus dem bereits hinterlegten Beziehungsbeginn berechnet.

## Ergänzung 3.6

Es kann pro Konto nur ein unbeantworteter ausgehender Fotowunsch gespeichert werden. Zurückrufen markiert diesen Wunsch serverseitig als gelöscht und beendet seine weitere Beantwortbarkeit. Alte überzählige offene Wünsche werden beim Upgrade auf den neuesten je Absender begrenzt; fertige Fotos bleiben erhalten. Vor einer Kameraaufnahme prüft die App den noch offenen Auftrag. Die Oberfläche ändert keine vorhandenen Freigaben und erfasst keine zusätzlichen Daten.

## Ergänzung 3.5.1

Bei aktiver Kamera-Unterstützung der Nahsuche verwaltet Nearby Interaction die AR-Kamera intern. Es gibt keine zusätzliche Kameraaufzeichnung oder SceneKit-Vorschau. Nur der Mess- und Kalibrierzustand erscheint in der Suchansicht; keine Kamerabilder werden gespeichert oder auf den Server geladen. Beim Verlassen der Suchansicht wird die kameraaktive Sitzung beendet; eine ausdrücklich erlaubte Suche im Hintergrund wird ohne Kamera neu aufgebaut.

## Ergänzung 3.5

Tagesrückblick und Feed verwenden ausschließlich eure bereits gespeicherten Inhalte. Der Tagesabruf sendet die UTC-Grenzen des auf dem iPhone gewählten Kalendertags an den privaten Server. Neue Bewegungs-, Aufenthalts- oder Health-Verläufe werden dafür nicht aufgezeichnet. Der Abendrückblick erscheint optional beim Öffnen ab 19 Uhr; kein dauerhafter Hintergrundprozess und keine zusätzliche tägliche Push-Mitteilung.

Abendrituale speichern pro Konto und Kalendertag drei freiwillige Texte auf eurem privaten Server. Beiträge sind sofort für beide sichtbar; nur der Verfasser kann seinen Beitrag ändern oder löschen. Nicht gesendete Entwürfe liegen lokal, getrennt nach Server, Konto und Tag. Die Nahsuche-Diagnose enthält Funktionszustände, iOS-/App-Version und Systemfehler, aber keine UWB-Tokens oder Positionen. Diagnose wird nur auf ausdrückliches Teilen über das iOS-Teilen-Menü weitergegeben.

## Ergänzung 3.4

Health-Leserechte werden auf jedem iPhone separat über iOS angefragt. Die bestehenden Weitergabe-Schalter bleiben beim Update erhalten. Aktivität, Schlaf und Vitalwerte sind weiterhin getrennt abschaltbar. Die Vitalwerte-Kategorie umfasst jetzt auch Körpergewicht, Blutdruck, Körper-/Handgelenktemperatur und Cardiofitness; vor dem Erweitern der Leserechte erklärt die App diese zusätzlichen Kategorien. Nur in Health tatsächlich vorhandene und freigegebene Daten können erscheinen. Die App schreibt keine Health-Daten.

Bei aktivierter Schlaffreigabe wird eine Zusammenfassung der letzten Hauptnacht inklusive aufgezeichneter Phasenintervalle, Quellenname und bis zu 13 vorherigen Nächten auf eurem privaten Server gespeichert und mit dem Partner geteilt. Der RJ-Schlafindex ist eine eigene Schätzung, kein medizinischer Wert und kein Originalwert von Apple. Einzelne Vitalwerte behalten ihr Messdatum (bis zu 30 Tage alt). Heute summierte Aktivität und der Zeitpunkt des Abgleichs werden getrennt benannt. Ausschalten der Weitergabe entfernt die Kategorie beim nächsten erfolgreichen Status-Upload.

Bewegung kann Erkennungssicherheit und den Beginn der erkannten Aktivität teilen. Die optionale Kamera-Unterstützung der Nahsuche läuft sichtbar in der geöffneten Suchansicht; sie speichert oder überträgt keine Kamerabilder. Beim Verlassen der Ansicht wird die Kamera pausiert. Ein fehlender Kamerafortschritt führt zur normalen UWB-Messung. Die Auswahl einer IPA liest nur die ausdrücklich gewählte Datei und erstellt eine temporäre Uploadkopie, die anschließend entfernt wird.

## Ergänzung 3.3

Kommentare zur Duftpost werden mit Verfasser und Serverzeit im privaten Datenbestand gespeichert. Ein getrenntes Aktivitätsprotokoll enthält zuletzt bestätigte App-Öffnung, Vordergrundkontakt und erfolgreichen Hintergrundabgleich. Diese Zeiten sind innerhalb eures verbundenen Paars sichtbar. Ein Hintergrundabruf wird nicht als App-Öffnung ausgewiesen. Jahrestag und Countdowns bleiben im gemeinsamen privaten Datenbestand; die freiwillig gewählten Widget-Inhalte werden über die bestehende App Group lokal bereitgestellt.

## Ergänzung 3.2

Neue Momente und BeReals können freiwillig Aufnahmeorte speichern. Bei importierten Medien wird ein verfügbarer Original-Aufnahmeort verwendet; eine Geräteposition wird nicht als historischer Aufnahmeort ausgegeben. Status und Ruhezeiten werden auf dem privaten Server gespeichert. Optional aktivierte Hintergrund-Ortung arbeitet unabhängig von Live-Aktivitäten und zeigt die iOS-Standortanzeige. Keine stille Kameraaufnahme im Hintergrund.

> Version 3.1: Persönliche Startseiten werden je Konto gespeichert. Fotowünsche verwenden eine sichtbare sofortige Kameraaufnahme. Eine aktiv gestartete UWB-Suche kann mit Live-Aktivität höchstens 15 Minuten im Hintergrund fortgesetzt werden; keine Suche auf einem geschlossenen Partnergerät starten.

# Aktuelle Änderungen 3.0

Walkie-Talkie, Push-to-Talk und die eigene Face-ID-Sperre sind entfernt. Süße Sprachnachrichten werden beim Öffnen auf Wunsch mit der eingestellten Medienlautstärke abgespielt; die automatische Wiedergabe ist zunächst eingeschaltet und abschaltbar. App-Öffnung und erste Nachrichtenöffnung werden gespeichert. Fotowünsche sind zunächst eingeschaltet und abschaltbar; die Kamera ist sichtbar, benötigt iOS-Zustimmung und nimmt im sichtbaren Vordergrund nach Freigabe ohne Countdown ein Foto auf. Keine Hintergrundkamera. Das aufgenommene Foto wird automatisch geteilt und lässt sich vom Aufnehmenden zurückrufen.

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

Geteilte Texte und Positionen liegen in SQLite auf eurem Server; Audio, Fotos und Videos im separaten Medienverzeichnis. APNs nutzt Apple für Benachrichtigungen und zulässige Hintergrundhinweise. Ab 3.9 enthalten Bark-/ntfy-Hinweise die vollständigen jeweiligen Ereignistexte, einschließlich geteilter Nachrichtentexte. Bark erhält außerdem passende Symbole und gegebenenfalls signierte Bildvorschau-URLs. Es wird kein gesamter Health-/Positionsverlauf übertragen. Diese Push-Integration nutzt keine Ende-zu-Ende-Verschlüsselung. Geheime Topics, APNs-Schlüssel, Konfiguration, Logs und Backups vertraulich behandeln.

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

## Optionaler KI-Rückblick (3.7)

Ohne eingerichteten OpenAI-Zugang am privaten Server und Freigabe beider Personen wird kein Moment an OpenAI übertragen. Eine Zusammenfassung wird ausschließlich auf ausdrücklichen Tipp für einen gewählten Tag erstellt. Übertragen werden bis zu 60 begrenzte Momenttexte mit Anzeigenamen, Medienart, Aufnahmezeiten und Quellen-IDs. Keine Mediendateien, Chatnachrichten, Kommentare, Health-Werte oder GPS-Koordinaten. Selbst eingegebene Beschreibungen können persönliche Angaben enthalten. Schlüssel bleiben auf dem Server und werden weder an die App geliefert noch protokolliert. Antworten werden mit store:false angefordert; darüber hinaus gelten die API-Datenbedingungen des verwendeten OpenAI-Kontos. Die KI kann sich irren und bewertet keine Beziehung.

Gespeicherte Rückblicke liegen im privaten Servercache, werden bei Freigabeentzug gelöscht und nach 90 Tagen bei der nächsten Erstellung bereinigt. Originalmomente bleiben erhalten. Die Erstellung ist begrenzt und unveränderte Tage werden wiederverwendet. Temporäre Playlist-Dateien liegen auf dem iPhone; abgespielte Dateien und die restlichen Dateien einer beendeten Playersitzung werden entfernt. Eigene Schnellzugriffe liegen unter den bereits vorhandenen, personenbezogenen Startseiten-Einstellungen am Server.



## Optionale Medienfunktionen ab 4.0.0

YouTube wird erst nach Bestätigung in der App geladen. RJ Love verwendet YouTube API Services (IFrame Player und optional YouTube Data API v3). Die Nutzung bindet an die [YouTube-Nutzungsbedingungen](https://www.youtube.com/t/terms). Es gilt auch [Googles Datenschutzerklärung](https://policies.google.com/privacy). Google erhält beim Laden/Abspielen unter anderem IP-Adresse, Geräte-/Browserinformationen und Videoauswahl und kann eigene Cookies verwenden. YouTube lässt sich im Kino deaktivieren. Eine Google-Anmeldung ist optional und öffnet den Systembrowser; RJ Love fragt kein Google-Passwort ab. Sie gibt nur Lesezugriff auf den eigenen YouTube-Kanal und Playlists.

Plex wird freiwillig über den offiziellen Plex-PIN-Login verbunden. Plex-Passwörter werden nicht verarbeitet. Tokens für beide Dienste liegen getrennt je privatem RJ-Server und RJ-Benutzer im iOS-Schlüsselbund; es gibt keine automatische Weitergabe an den Partner. Google-OAuth-Code/State und gerade erhaltene Tokens liegen vor der Abholung durch das berechtigte iPhone kurzzeitig im Server-Arbeitsspeicher. Langfristige Google-/Plex-Kontotokens werden nicht in der gemeinsamen Datenbank gespeichert. Konto trennen löscht die lokalen Kontotokens; Google-Widerruf wird online versucht. Die Berechtigung kann zusätzlich bei [Google](https://myaccount.google.com/permissions) oder in den autorisierten Geräten bei Plex entzogen werden.

Gemeinsames Schauen ist ausdrücklich auswählbar. Gespeichert werden zusätzliche Medienräume (Dienst, gewählte Video-ID/Titel, Eigentümer, Wiedergabezustand, Timer), Beitritte/Heartbeats und die Summe gemeldeter gemeinsamer Wiedergabezeit. Der Partner sieht den ausgewählten Inhalt und den gemeinsamen Raum, nicht private Playlists, Kontotokens oder die gesamte Plex-Bibliothek. YouTube-Titel/Video-IDs abgelaufener Räume werden beim nächsten Raumabruf nach 30 Tagen entfernt. Statistikwerte sind appinterne Näherungswerte. Die bisherige Datenspeicherung bleibt unverändert.

Eine zeitweise Plex-Filmfreigabe vermittelt nur die ausgewählte Datei über euren eigenen RJ-Server. Der benötigte Plex-Zugang wird für höchstens vier Stunden im Arbeitsspeicher gehalten und nach Widerruf, Raumende bzw. Serverneustart unbrauchbar. Der Partner bekommt nur ein sitzungsgebundenes Ticket. Bereits gepufferte Daten können nach Widerruf noch kurz abspielen. Zugriffslogs enthalten weder diese Medien-Tickets noch OAuth-Callback-Parameter.

Der AirPlay-Fernseher kann die von euch gewählten Partnerinformationen und Momente für Anwesende sichtbar machen. Es werden nur bereits freigegebene Statusinformationen verwendet. Die TV-Ansicht beim Abmelden schließen; keine automatische Wiedergabe sensibler privater Bibliotheken. Weitere Details und Einrichtung: [Release 4.0.0](RELEASE-4.0.0.md).
