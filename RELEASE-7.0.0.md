# RJ Love 7.0.0 (700) · Redesign, Funk und Frage des Tages

App 7.0.0 und Einzeldatei-Server 7.0.0 gehören zusammen. Protokoll 5 bleibt unverändert. Die Datenbank wird nur ergänzt (drei neue Tabellen), bestehende Konten, Medien, Einträge und lokale Einstellungen bleiben unverändert.

## Design wie eine Apple-App

- Aufgebaut wie die iOS-Einstellungen: deckende, gruppierte Karten, farbige Symbolkacheln mit weißem Symbol, Abschnittsüberschriften und eingerückte Trennlinien.
- Liquid Glass gezielt und nie zu durchsichtig: Tab- und Navigationsleiste, runde Bedienknöpfe, die Funk-Taste und die „Funk spielt“-Anzeige. Inhalte bleiben auf festen Karten gut lesbar.
- Ruhiger Hintergrund in der Farbe gruppierter iOS-Listen mit einem sanften Rosé-Schimmer oben (wie Health und Fitness).
- iOS-26-Proportionen: Kartenradius 26, Kachelradius 22, einheitliche Abstände.
- Profil mit Kopfbereich wie das Apple-Account-Feld; aufgeräumte Gruppen „Für euch zwei“, „Dein Alltag“, „Weitere Möglichkeiten“.

## Neue Öffnungsanimation

Euer Bild übernimmt exakt an der Stelle des iOS-Startbildschirms, schlägt einmal wie ein Herz (mit Lichtring, kleinen Herzen und sanfter Haptik), der Name erscheint und der Startbildschirm öffnet sich zur App hin. Mit „Bewegung reduzieren“ nur ein ruhiges Ausblenden; eine Notfallaufnahme überspringt den Start sofort.

## Neu: Funk

- Gedrückt halten, sprechen, loslassen – bis zu zwei Minuten. Nach oben ziehen verwirft die Aufnahme.
- Sind beide in der App, kommt die Nachricht über eine Live-Verbindung (Long-Polling) nach einem Augenblick an und wird sofort laut abgespielt.
- Sonst spielt sie automatisch, sobald dein Lieblingsmensch RJ Love öffnet – außer im Ruhemodus. Mehrere Nachrichten laufen nacheinander.
- Bark/ntfy melden neuen Funk („🎙️ Funk von …“), ein Tipp öffnet direkt den Funk.
- „Gehört“-Anzeige für den Absender, eigene Nachrichten lassen sich für beide zurückrufen.
- Einstellbar: automatisch abspielen, laut abspielen, Funk-Klick. Funktioniert mit jeder Sideload-Signatur, ohne Apples Push-to-Talk-Berechtigung.

## Neu: Frage des Tages

Jeden Tag dieselbe Frage auf beiden iPhones. Die Antwort des anderen wird erst sichtbar, wenn du selbst geantwortet hast. Mit Verlauf aller Tage und Mitteilung, wenn dein Lieblingsmensch geantwortet hat.

## Fotowünsche repariert

Ursache: Ein Fotowunsch wird bewusst ohne Mitteilung gesendet und erschien nur als automatische Kamera beim Öffnen. Wurde diese übersprungen, war die Kamera-Funktion aus oder lag gerade ein anderes Fenster offen, sah das Gegenüber den Wunsch nicht – und der Absender konnte keinen neuen senden.

- Offene Wünsche erscheinen jetzt immer als Hinweis oben auf der Startseite („… wünscht sich ein Foto“).
- „Jetzt nicht“ pausiert die automatische Kamera nur noch für drei Stunden.
- Unbeantwortete Wünsche laufen nach 12 Stunden automatisch ab; danach ist ein neuer Wunsch möglich. Fotos und erfüllte Wünsche bleiben unberührt.
- Neu: „Sanft erinnern“ schickt auf ausdrücklichen Wunsch eine Mitteilung (höchstens alle 30 Minuten).
- Nach einem Zurückruf erzeugt der nächste Wunsch immer eine neue ID (vorher konnte ein erneuter Versuch abgelehnt werden).

## Hintergrundstandort

- Standortupdates pausieren im Hintergrund nicht mehr automatisch (iOS hat sie danach nicht wieder aufgenommen).
- Im Hintergrund sparsamer (100 m Genauigkeit, 60 m Abstand), dazu signifikante Ortswechsel und Besuche, die die App nach dem Beenden wieder starten.
- `CLBackgroundActivitySession` hält die Sitzung auch mit „Beim Verwenden“ aktiv.
- Ein eigener Uploader sendet Position und Akku sofort innerhalb der von iOS gewährten Hintergrundzeit an den neuen Endpunkt `/v1/presence/location`. Dieser ergänzt nur Position/Akku und überschreibt keine Health- oder Statuswerte.

## Server 7.0.0

- `MINIMUM_APP_VERSION = 7.0.0`: Apps 6.x und älter zeigen ihr Update-Fenster; IPA-Download und Feather-Quelle bleiben offen.
- Neue Tabellen `walkie_messages`, `daily_answers`, `photo_request_nudges` (nur ergänzend).
- Neue Endpunkte: `/v1/walkie` (Liste/Long-Poll, Senden), `/v1/walkie/<id>/played`, `DELETE /v1/walkie/<id>`, `/v1/daily-question`, `/v1/daily-question/history`, `/v1/photo-requests/<id>/nudge`, `/v1/presence/location`.
- Startseiten-Layout 3: Frage des Tages und Funk erscheinen einmalig oben, die bisherige Reihenfolge bleibt.
- Bark: Funk und Antworten laufen über den bestehenden Versand inklusive Ruhezeiten.

## Sicher aktualisieren

1. Laufenden Server stoppen, `rjapp_config.json` und den kompletten Datenordner sichern.
2. Nur `Backend/rj_love_server.py` ersetzen und mit derselben Konfiguration neu starten.
3. Optional die neue `RJ-Love-unsigned.ipa` neben die Serverdatei legen; die alte App bietet dann das Update an.
4. IPA wie bisher signieren (Bundle-ID `eu.rjuhas.rjlove`, dasselbe Team, identische App Group, Widget mitsignieren) und über die bestehende App installieren, nicht vorher löschen.

## Prüfung

21 HTTP-Regressionen, davon 6 neue für Funk (inkl. Long-Poll, Zugriffsschutz, Gehört-Status), Frage des Tages, Ablauf und Erinnerung von Fotowünschen, Standort-Zusammenführung und Layout-Migration. GitHub Actions kompiliert App und Widgets mit Xcode 26 und prüft die IPA. Mikrofon, Lautsprecher, Hintergrundstandort und Bark-Empfang bleiben eine Prüfung auf den echten iPhones.
