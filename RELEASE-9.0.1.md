# RJ Love 9.0.1 (901) · Widgets und Hintergrund-Updates

Mini-Update auf Basis von 9.0.0. **Der Python-Server bleibt 9.0.0 und Protokoll 5 bleibt unverändert**. Keine Änderungen an der Datenbank, Authentifizierung, Backend-Datei, Serveradresse oder Konten.

## Neu

- Widgets und Haupt-App erkennen automatisch die tatsächlich signierte, zugängliche App Group beider Zertifikatsanbieter.
- Widget-Diagnose mit erkanntem Container, Erweiterungsprofil, Widget-Zugriff, Hintergrundabruf und manueller WidgetKit-Aktualisierung.
- Ein von iOS gewährter Hintergrundlauf lädt nach der Alarm- und Kommandoverarbeitung aktuelle Partnerdaten aus dem vorhandenen authentifizierten Endpoint `/v1/bootstrap` und aktualisiert den Widget-Snapshot. Fehler dabei blockieren die Kommandoverarbeitung nicht.
- Keine erfundenen Standortwerte: Eine alte Entfernung wird gelöscht, wenn der Partnerstandort gewechselt hat oder die Messung ablief.

## Signierung auf beiden Geräten

Die **gleiche unsigned IPA** kann für beide iPhones verwendet werden. Sie muss pro Gerät separat neu signiert werden:

| Gerät | vorhandene Haupt-App-Bundle-ID | App Group |
| --- | --- | --- |
| iPhone 17 Pro Max | `app.lake6191.velvet1751` | `group.dfbc88d056a46f1b.1` |
| iPhone 14 Pro | `app.andromeda203.garnet9008` | `group.4d9963ba648cf299.1` |

**Wichtig:** Die Widget-Erweiterung ist ein eigenes iOS-Target und braucht eine passende eigene App-ID sowie ein eigenes signiertes Provisioning-Profil mit derselben zugelassenen App Group wie die Haupt-App. Die bereits vorliegenden ZIPs enthalten jeweils nur Haupt-App-Profile, keine eigenen Widget-Profile. App-IDs und App Groups lassen sich nicht durch Eingabe innerhalb der App freischalten. Eine geänderte Bundle-ID kann zu einer separaten App-Installation führen.

**Keine Zertifikate, P12-Dateien oder Passwörter in GitHub hochladen.**

Nach der Installation die App öffnen und unter **Widgets verbinden** „Widget-Daten und Anzeige aktualisieren“ auswählen. iOS bestimmt weiterhin selbst, ob und wann die Hintergrundaktualisierung läuft.

## Serverseite

Weiterhin `Backend/rj_love_server.py` in Version 9.0.0 verwenden. Daten, bestehende Server-Anmeldungen und Endpunkte bleiben unverändert.
