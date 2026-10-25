# RJ Love 4.2.0 · Unser Kino

App 4.2.0 (420) und Python-Server 4.2.0 zusammen aktualisieren. Erst den Server stoppen, eine Sicherung von Konfiguration und Datenordner anlegen, nur die Python-Datei ersetzen und neu starten. Die IPA mit derselben Bundle-ID, App Group und dem bisherigen Signierteam über die bestehende Installation installieren. Die App nicht löschen. Datenbankänderungen sind ausschließlich zusätzliche Tabellen; vorhandene Konten und Inhalte werden nicht umbenannt.

## Plex

Zusammen schauen und die Freigabe des ausgewählten Films sind standardmäßig aktiv. Der Partner verbindet sich zunächst als Fernbedienung; „Auch auf diesem iPhone abspielen“ startet bei Bedarf den zweiten Stream. AirPlay wird über den iOS-Gerätewähler gewählt. Native Plex-Wiedergabe verwendet die Hintergrund-Audioberechtigung und wird beim Sperren nicht absichtlich pausiert. iOS, Empfänger und Netzwerk müssen die Wiedergabe unterstützen.

Nach Plex-Anmeldung ein Profil und einen Server wählen. Die Kino-Automatik beobachtet ausschließlich Sitzungen dieses bestätigten Plex-Profils. Sie erkennt auch Filme, die anschließend in einer anderen Plex-App gestartet werden. Das Konto benötigt Zugriff auf die Sitzungsübersicht; bei eingeschränkten Gastkonten kann Plex diesen Zugriff verweigern. Server und sichere plex.direct-Verbindung müssen vom RJ-Server erreichbar sein.

Die Verbindung bleibt höchstens zwölf Stunden im Serverspeicher und ist an die bestehende RJ-Anmeldung gebunden. Beim Öffnen der App wird sie erneuert. Nach Neustart des Python-Servers die App einmal öffnen. Tokens werden nicht in Datenbank oder Konfiguration gespeichert. Der Partner erhält ausschließlich befristete Wiedergabetickets für den ausgewählten Film. „Automatik trennen“ beendet die Beobachtung und externe Filmfreigabe.

Beide können Play/Pause und Springen anfordern. Externe Geräte müssen Plex Companion annehmen; neuere mobile Plex-Apps unterstützen dies teilweise nicht. Die App zeigt einen Fehler, wenn das Gerät einen Befehl ablehnt. Eigene RJ-Player synchronisieren sich über euren Server. Das ersetzt nicht Plex-Abonnements, Medienrechte oder Fernzugriffsvoraussetzungen. HLS-Transcoding muss Plex unterstützen; zwei Geräte brauchen zwei Streams.

Der Schlaftimer pausiert bzw. beendet den Kino-Raum. Bei externem Plex übernimmt der Python-Server die Timeraktion auch ohne entsperrtes iPhone. Eine ausgeschaltete App kann keine zusätzlichen iOS-Systemrechte erhalten. Ein Apple TV wird nicht ausgeschaltet; dafür stellt HomeKit keine allgemeine öffentliche Steuerung bereit.

Kinozeit zählt bei zwei tatsächlich gemeldeten Streams oder wenn beide ihre Anwesenheit am selben Bildschirm bestätigen. Der Besitzer einer extern beobachteten Plex-Sitzung zählt über deren tatsächlichen Wiedergabestatus. Frische Anwesenheit des Partners ist erforderlich. Der Filmverlauf enthält maximal 100 Einträge in der Ansicht. Statistik und Filmverlauf können mit Bestätigung für beide zurückgesetzt werden. Andere Daten bleiben erhalten.

## YouTube

Native Suche und abonnierte Videos verwenden b5i/YouTubeKit ohne eigenen API-Schlüssel, fest auf Revision 6532af39da4c1612b0a1af603792419d8fb0e67f. Die YouTube-Seite für Anmeldung, Konto und direkte Wiedergabe läuft als WKWebView innerhalb der App. Es öffnet sich keine Safari-Vorschau. Kontodaten bleiben in einer getrennten lokalen WebKit-Datenablage je RJ-Konto und werden nicht zum Python-Server gesendet. Abmelden löscht diese lokale Webanmeldung.

Google kann eingebettete Anmeldungen blockieren; die nicht öffentliche YouTube-Schnittstelle kann sich ändern. Geschützte, nicht einbettbare oder kontogebundene Videos funktionieren eventuell ausschließlich in der YouTube-Ansicht. Ein gemeinsamer eingebetteter Player übernimmt die Kontoanmeldung nicht automatisch. YouTube wird beim Sperren pausiert. Es gibt keine Zusage für uneingeschränktes Google-Login oder alle Videos.

## Zuhause und Dashboard

Neue gläserne Kinokarte mit aktuellem Film auf der Startseite. Optionaler Apple-Home-Bereich mit Auswahl eigener und geteilter Häuser, Kameravorschauen und Live-Ansicht. Erst „HomeKit aktivieren“ erstellt den Home-Manager und löst die Systemfreigabe aus. HomeKit-Entitlement beim Signieren erhalten. Die konkret vorliegenden Profile enthalten diese Berechtigung; der Signierer kann sie trotzdem entfernen. Kameraansichten verwenden nur Apples HomeKit und werden weder an den Partner noch an den RJ-Server weitergeleitet. Geteilte Häuser brauchen die in Apple Home gewährten Kamera-/Fernzugriffsrechte. Live-Kameras stoppen beim Verlassen bzw. Sperren.

## Prüfung

Vier gezielte Backend-Prüfungen für additive Datenübernahme, Versionssperre, bestätigtes Zurücksetzen, Profilabgrenzung, gemeinsame Erfassung und serverseitigen Timer. Alte Tests und zusätzliche Simulator-Jobs wurden auf Wunsch entfernt. Der Release-Workflow kompiliert App und Widgets und prüft das IPA-Paket. Echte Plex-, AirPlay-, Google- und HomeKit-Verbindungen müssen auf euren iPhones geprüft werden.
