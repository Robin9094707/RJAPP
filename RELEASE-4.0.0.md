# RJ Love 4.0.0 · Unser Kino

Dieses Update ergänzt App 3.9.3 um einen eigenen Medienbereich unter **Erleben → Kino** und **Profil → Unser Kino & AirPlay**. Gleiche Bundle-ID, gleicher App-Group-Identifier, unveränderte bisherige Zugangsdaten und Datenpfade.

## Installation und Rückkehr zur bisherigen Version

1. Den bisherigen Server stoppen und den vorhandenen Datenordner sowie `rjapp_config.json` sichern.
2. **Nur** `rj_love_server.py` durch die neue Datei ersetzen. Vom gleichen Arbeitsverzeichnis mit der bisherigen Konfiguration starten. Keine neue Konfiguration anlegen und keinen Datenordner verschieben.
3. Die neue unsigned IPA wie bisher mit Feather signieren, einschließlich Widget-Erweiterung. Dieselbe Bundle-ID, App Group und möglichst dieselbe Signatur verwenden. Über die bestehende App installieren; die App nicht löschen.
4. Bei Problemen die bisherige IPA darüber installieren. Der neue Server akzeptiert weiterhin App 3.9.2 und 3.9.3 mit Protokoll 5. Auch die bisherige Python-Datei kann mit derselben Datenbank weiterverwendet werden; sie ignoriert die zusätzlichen Tabellen. Neue Medienräume funktionieren mit ihr nicht.

Die neue App benötigt für die bisherigen Funktionen weiterhin nur Server 3.9.2. Fehlende Kino-Endpunkte auf dem alten Server führen zu einem Hinweis ausschließlich im Kino. Es gibt keine erzwungene Datenmigration für bisherige Funktionen. Die vorhandenen Tests prüfen das Legacy-Verhalten; ein lokales Backup bleibt für einen realen Wechsel sinnvoll. iOS-Datenkontinuität hängt auch davon ab, dass die Sideload-Signatur dieselben Container weiterverwendet.

## Vorhandener Bark-Schlüssel

Der bisherige Server enthielt einen eingebetteten privaten Bark/APNs-Schlüssel. Dieser wird nicht erneut verteilt. Die neue Datei verwendet weiterhin eine bereits vorhandene `bark-public-apns.p8` im bisherigen Datenordner oder die bisher konfigurierte `bark.private_key_file`. Diese Datei beim Update unbedingt behalten. Fehlt beides, benötigt Bark einen separat bereitgestellten passenden Signaturschlüssel; der Server meldet dies, statt einen Schlüssel aus dem Quelltext zu erzeugen. Eigene RJ-APNs-, ntfy- und Kontodaten werden nicht geändert.

## AirPlay: zwei unterschiedliche Verbindungen

- **Eigene TV-Oberfläche:** Im iOS-Kontrollzentrum „Bildschirmsynchronisierung“ und den AirPlay-Fernseher wählen. Die registrierte externe iOS-Szene füllt den TV mit einem eigenen Layout; die iPhone-Oberfläche bleibt Fernbedienung. AirPlay-TV-Unterstützung durch das Zielgerät ist Voraussetzung.
- **Direkte Medienwiedergabe:** Die AirPlay-Taste im Kino verwendet die iOS-Geräteauswahl. Bei Plex übernimmt AVPlayer die Videowiedergabe. Dieser Medienweg transportiert keine frei gestalteten Widgets.
- **Unser Wir:** Uhr, Datum, Namen, freiwillig bereits freigegebener Partnerstatus und Akkustand.
- **Momente:** Vollständiges Fotoarchiv abrufen, vor/zurück und Diashow. Live Photos werden als Standbilder gezeigt; Videos bleiben im bisherigen Abendprogramm verfügbar.
- **Kino:** Sichtbarer YouTube-Player bzw. native Plex-Wiedergabe auf dem externen Bildschirm. Optional zeigt eine separate Seitenleiste Uhr, Partnerstatus und Timer neben dem Video; sie überdeckt den YouTube-Player nicht.
- **Nacht:** Sehr dunkle, leicht wandernde Uhr. Der Nachtmodus verdunkelt keine YouTube-Videos und versteckt keinen laufenden YouTube-Player.

Das Layout passt sich dem externen Bildschirm an. Fotos und Videos behalten ihr Seitenverhältnis und können Balken haben. Für die eigene TV-Oberfläche muss die App im Vordergrund und das iPhone entsperrt bleiben; bei verbundener externer Szene wird der automatische Ruhezustand verhindert. AirPlay muss von euch über die iOS-Systemoberfläche verbunden werden. Eine IPA kann die Auswahl nicht selbst erzwingen.

## YouTube

- Offizieller IFrame-Player mit korrekter App-Identifikation/Referer und AirPlay-Freigabe in WKWebView.
- Öffentliche Video-Links bzw. Video-IDs können ohne Suchschlüssel geöffnet werden.
- Suche mit Folgeseiten über die offizielle YouTube Data API.
- Alleine schauen oder einen gemeinsamen Raum starten. Der Partner muss ausdrücklich beitreten; beide können Play/Pause, 15-Sekunden-Sprünge und Timer steuern.
- Sichtbarer kleiner Player beim Wechsel in einen anderen App-Bereich. Bei gesperrtem iPhone oder Verlassen der App wird YouTube pausiert. Der offizielle Player erlaubt keine garantierte Hintergrundwiedergabe; es werden keine Tweaks injiziert, Anzeigen entfernt oder Streams extrahiert.
- YouTube kann Einbettung, Wiedergabe oder AirPlay für einzelne Videos/Geräte sperren. Gegebenenfalls direkt im Player auf Play tippen. Der AirPlay-Ausgang des Webplayers muss mit eurem Gerät geprüft werden; er ist nicht identisch mit dem sicherer kontrollierbaren AVPlayer-Pfad von Plex.

### Suche einrichten

Im eigenen Google-Cloud-Projekt die **YouTube Data API v3** aktivieren und einen API-Schlüssel erstellen. Auf dem RJ-Server entweder die Umgebungsvariable `RJ_YOUTUBE_API_KEY` setzen oder der vorhandenen Konfiguration **zusätzlich** Folgendes auf oberster Ebene hinzufügen:

```json
"cinema": {
  "youtube_api_key": "DEIN_GOOGLE_API_SCHLUESSEL"
}
```

Die übrigen Konfigurationseinträge behalten. Google verwaltet Quoten; Suchanfragen können bei ausgeschöpfter Quote fehlschlagen. Es liegt kein fremder oder eingebauter API-Schlüssel im Repository.

### Getrennte Google-Konten (optional)

Einmalig einen **OAuth-Webclient** im selben Google-Cloud-Projekt erstellen, `youtube.readonly` als Scope einrichten und eure beiden Google-Konten bei einem OAuth-Projekt im Testmodus als Testnutzer eintragen. Die autorisierte Weiterleitungsadresse muss exakt die eigene öffentliche HTTPS-Serveradresse mit `/cinema-oauth/youtube` sein, einschließlich eines gegebenenfalls vorhandenen Proxy-Pfads.

Die vorhandene Konfiguration ergänzen:

```json
"cinema": {
  "youtube_api_key": "DEIN_GOOGLE_API_SCHLUESSEL",
  "youtube_oauth": {
    "client_id": "DEINE_WEB_CLIENT_ID.apps.googleusercontent.com",
    "client_secret": "DEIN_WEB_CLIENT_SECRET",
    "redirect_uri": "https://EUER-RJ-SERVER/cinema-oauth/youtube"
  }
}
```

Der Reverse-Proxy muss diesen Callback-Pfad an dieselbe Python-Anwendung weiterleiten. „Bei Google anmelden“ öffnet den Systembrowser. Nach Bestätigung zur App zurückkehren; die App holt die Tokens über die authentifizierte Verbindung ab. Der Flow ist mit zufälligem State, PKCE und Bindung an die RJ-Sitzung abgesichert. Tokens werden serverseitig nur kurz im Arbeitsspeicher gehalten und nach Abholung entfernt. Dauerhafte Speicherung erfolgt getrennt je Server und RJ-Benutzer im iOS-Schlüsselbund. Keine Tokens gelangen in Bootstrap, Räume oder zum Partner. Ein Serverneustart während der Anmeldung erfordert einen neuen Anmeldeversuch.

Die Anmeldung ermöglicht das Lesen des eigenen Kanalnamens und der eigenen Playlists mit vollständiger Seitennavigation. Sie ist **keine Anmeldung im eingebetteten Player**; private/Alters-/Premium-Inhalte erhalten dadurch keine zusätzliche Abspielberechtigung. „YouTube-Konto trennen“ löscht lokale Tokens und versucht, die Freigabe bei Google zu widerrufen. Bei fehlender Verbindung kann sie zusätzlich auf https://myaccount.google.com/permissions entzogen werden. Google-OAuth im Testmodus kann Refresh-Tokens nach kurzer Zeit ablaufen lassen; dann erneut anmelden. Ein vollständiger YouTube-App-Ersatz ist dies nicht.

## Plex

Anmeldung über den Plex-PIN-Flow auf der offiziellen Plex-Webseite. Kein Plex-Passwort wird in RJ Love eingegeben. Account-Token und Gerätekennung werden getrennt je Server/RJ-Nutzer im Schlüsselbund gespeichert. Es wird keine Bibliothek automatisch an den Partner übertragen.

Nach „Server laden“ einen Server wählen, Bibliotheken/Serien/Staffeln öffnen, suchen und direkt unterstützte Filme/Episoden starten. Listen haben Nachladefunktionen. Der direkte AVPlayer-Pfad unterstützt AirPlay, systemseitiges Picture in Picture (soweit iOS es anbietet), Hintergrundton und Sperrbildschirmsteuerung. Native Formate/Codecs sind Voraussetzung; ein eigener Transcoder sowie Plex-TV/Leih-/DRM-Angebote sind nicht integriert.

Für gemeinsames Schauen den Schalter **Zusammen schauen** und die ausdrückliche **Freigabe dieses Films** einschalten. Der Partner erhält nur den gewählten Titel, einen Raum und ein kurzlebiges, an seine RJ-Sitzung gebundenes Wiedergabeticket. Der Server überprüft die Plex-Ressourcen und die Metadaten mit dem Zugang des Besitzers. Nur der bestätigte Dateipfad des ausgewählten Mediums wird vermittelt; keine freie Proxy-URL und kein Bibliothekszugriff. Diese Freigabe benötigt:

- HTTPS am RJ-Server;
- eine sichere, erreichbare, von Plex bestätigte `plex.direct`-Verbindung zum Plex-Server;
- eine einzelne, direkt abspielbare Mediendatei;
- ausreichende Upload-Bandbreite am Plex- und RJ-Server sowie Erlaubnis zur Weitergabe des Inhalts.

Die Freigabe endet nach maximal vier Stunden, Widerruf, Ende des Raums oder Serverneustart. Sie wird ausschließlich im Arbeitsspeicher gehalten. Logout bzw. Verlassen durch den Empfänger sperrt dessen Ticket. Bestehende Proxy-Übertragungen prüfen Widerruf, Raum, Timer und Sitzung regelmäßig. Bereits vom Empfänger oder AirPlay-Gerät gepufferte Daten lassen sich nicht zurückholen. Es ist keine vollständige Plex-Bibliotheksfreigabe und kein dauerhaftes Plex-Serverrecht.

## Synchronität, Timer und Statistik

Die App gleicht den Raum im Vordergrund etwa alle drei Sekunden ab, korrigiert größere Zeitabweichungen und meldet tatsächliche Wiedergabe. Revisionen verhindern, dass veraltete parallele Steuerbefehle den neuen Zustand überschreiben. Das ist koordiniertes gemeinsames Schauen, keine framegenaue Synchronisation: Werbung, Buffering, unterschiedliche Netze und Hintergrundbeschränkungen bleiben wirksam. Im Hintergrund kann Plex lokal weiterspielen; fremde Steuerbefehle werden dort nicht zuverlässig sofort empfangen. Nach Rückkehr erfolgt der Abgleich.

Timer: 15/30/60/120/180/240 Minuten oder ohne Timer. Er pausiert die Wiedergabe, schaltet den Fernseher nicht physisch aus. Der Server lässt abgelaufene gemeinsame Räume nicht erneut starten und beendet vermittelte Plex-Übertragung. Ein angehaltenes bzw. im Hintergrund eingefrorenes YouTube-WebView wird bei Rückkehr erneut geprüft.

Die gemeinsame Schauzeit zählt nur Intervalle, in denen mindestens zwei beigetretene Geräte tatsächliche Wiedergabe melden. Veraltete Heartbeats werden nach zwölf Sekunden nicht weiter gezählt. Statistiken sind Näherungswerte und keine YouTube-Analytics-Messung. Alleinige Wiedergabe erzeugt keine gemeinsame Statistik. Titel/Video-IDs abgelaufener Räume werden beim nächsten Raumabruf nach 30 Tagen entfernt; die Summe der gemeinsamen Zeiten bleibt erhalten.

## Prüfung und verbleibender Gerätetest

Automatisiert: bestehende Backend-/Benachrichtigungstests, neue Kino-Tests für Kompatibilität, Mitgliedschaft, Revisionen, Timer, tatsächliche gemeinsame Wiedergabe, Google-Kontotrennung, Plex-Dateifreigaben, Range-Übertragung und Widerruf. Xcode-Gerätebuild erstellt die unsigned IPA, die anschließend inklusive Widget-Erweiterung geprüft und paketiert wird. Ein Simulatorlauf prüft die Navigation der neuen Medienoberfläche.

Ein erfolgreicher Build ersetzt keine Hardwareprüfung. Mit zwei iPhones testen: gemeinsame YouTube-Wiedergabe, Play/Pause/Seek beiderseits, Netzwerkunterbrechung, Timer, beide Google-Konten. Mit Plex testen: Anmeldung, Serverauswahl, Dateiformate, freigegebener Film, Widerruf während Wiedergabe, Logout. Mit Apple TV/AirPlay-TV testen: externer Vollbildschirm und Seitenverhältnis, Telefon-Fernbedienung, Player-Ausgang, Disconnect/Reconnect und Sperrverhalten. Es liegen keine echten Plex-/Google-Zugänge oder ein physischer AirPlay-Empfänger in der Buildumgebung vor.

## Quellen

- https://developer.apple.com/documentation/uikit/presenting-content-on-a-connected-display
- https://developers.google.com/youtube/iframe_api_reference
- https://developers.google.com/youtube/terms/required-minimum-functionality
- https://developers.google.com/youtube/terms/developer-policies
- https://developers.google.com/youtube/v3/docs/search/list
- https://developers.google.com/identity/protocols/oauth2/web-server
- https://developer.plex.tv/pms/
- https://github.com/fosterbarnes/YTPlusYTweaks (geprüft: injiziert Tweaks in eine separat bereitgestellte YouTube-IPA, keine einbettbare RJ-Love-Playerbibliothek)
