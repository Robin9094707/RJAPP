# RJ Love 2.3.0 (230)

## Passend für kleine und große iPhones

Die Hintergrunddekoration richtet sich nach der tatsächlichen Fensterbreite und vergrößert keine Ansicht mehr. Schnellaktionen und Recorder-Bedienung umbrechen bei wenig Platz; Überschriften dürfen mehrzeilig werden. Native Liquid-Glass-Karten, warme Rosé-Verläufe und klar getrennte Statuskarten führen durch die App. Die CI prüft iPhone 14 Pro, iPhone SE (3. Generation) und iPhone 15 Plus mit iOS 26.1 oder neuer sowie große Bedienungshilfen-Schrift. Auf älteren iOS-Versionen ist diese App nicht installierbar.

## Push und AlarmKit im Hintergrund

Der Hintergrundabruf startet direkt im App-Delegate, unabhängig von einer geöffneten Oberfläche, Face ID oder dem Vordergrund-Poller. Er lädt nur Weckaufträge und Erinnerungen, keine Fotos oder Health-Daten. Ein APNs-Alarmhinweis enthält `content-available: 1` und die Kategorie `RJ_WAKE`. Wenn iOS der App Laufzeit gewährt und AlarmKit zuvor freigegeben wurde, kann sie den Weckruf ohne Öffnen der Oberfläche einplanen. Der APNs-Fetch hat ein Zeitlimit von 25 Sekunden. Die Mitteilungsaktion „Weckruf jetzt einplanen“ bietet einen zusätzlichen ausdrücklichen Weg ohne Öffnen der Oberfläche. Nach einem Neustart muss das Gerät einmal entsperrt worden sein, damit der Sitzungsschlüssel zugänglich ist.

Weckrufe lassen sich nun bis zu 30 Tage im Voraus planen. AlarmKit verwendet einen festen Zeitpunkt. Bereits vom Empfängergerät eingeplante Alarme benötigen dann keinen erneuten Serverabruf zur Weckzeit. Unter **Wir → Push, Wecker & Hintergrund prüfen** wird die Bestätigung des Empfängergeräts angezeigt. „Auf dem iPhone eingeplant“ bedeutet, dass AlarmKit die Planung angenommen hat, nicht dass der Alarm bereits hörbar war. Fehlgeschlagene Planungen bleiben wiederholbar. Mehr als fünf Minuten verspätete Aufträge werden als abgelaufen bestätigt und nicht Stunden später ausgelöst.

APNs-Annahme, Hintergrundausführung und Alarmplanung sind getrennte Schritte. iOS kann Hintergrundpushes verzögern, drosseln oder nach manuellem Beenden unterdrücken. Auch die Hintergrundaktualisierung hat keinen garantierten Zeitplan. Es gibt keinen öffentlichen zuverlässigen Weg, eine zwangsbeendete App beliebig im Hintergrund zu starten. Für wichtige Weckzeiten im Voraus planen und die Empfängerbestätigung kontrollieren. Kritische Mitteilungen und künstliche Dauerlauf-Audiotricks werden nicht verwendet.

## ArcticSign Prime Plus und eigene APNs-Schlüssel

ArcticSign führt bei Prime Plus Distribution- und Developer/JIT-Zertifikate auf. Daraus lässt sich nicht ableiten, welche Capabilities das konkret installierte Profil erlaubt. Die neue Statusseite zeigt Bundle-ID, Team-ID, APNs-Umgebung, Profiltyp, Ablaufdatum und die Push-to-Talk-Freigabe im eingebetteten Profil. Diese Profilangaben sind eine Diagnose; die tatsächlich signierten Rechte und die Registrierung prüft iOS. iOS-Fehler werden mit Fehlerdomäne und Code angezeigt.

Eine Umbenennung auf Zellos Bundle-ID überträgt weder dessen Teamrechte noch dessen APNs-Schlüssel oder Server. Bundle-ID, Profil, Signing-Team, APNs-Schlüssel und Server-Topic müssen gemeinsam zu RJ Love passen. Beide eingebetteten Targets mit signieren; App Groups und benötigte Capabilities erhalten. Ein Distribution-`.p12` zur App-Signierung ersetzt keinen APNs-Provider-`.p8`-Schlüssel.

Auf dem eigenen Python-Server:

```sh
python3 rj_love_server.py --configure-push
python3 rj_love_server.py --check-push
python3 rj_love_server.py
```

Die Einrichtung fragt Team-ID, Key-ID, privaten `.p8`-Pfad und die tatsächliche Bundle-ID ab, prüft Werkzeuge/HTTP2 und das Signieren eines Provider-Tokens. Den Schlüssel muss das zur App passende Apple-Team bereitstellen; ein Zahlungsbeleg reicht dafür nicht. Die Datei bleibt auf dem Server und wird nicht ins Git geschrieben. Nach Änderungen den laufenden Server neu starten. Registrierung bei abweichender Bundle-/Team-ID wird mit einer Erklärung abgelehnt. Sandbox/Production wird aus dem installierten Profil ermittelt.

Der Push-Test in der App sendet ausschließlich an das eigene Konto. Die Statusseite zeigt echte APNs-Antworten einschließlich `DeviceTokenNotForTopic`, `InvalidProviderToken` oder `TopicDisallowed`. „Lokale Voraussetzungen vorhanden“ ist kein Empfangsnachweis. Ohne persönliche Schlüssel und signierte Geräte kann der unsigned Build keinen echten APNs-Empfang nachweisen; es sind keine persönlichen Serverzugänge oder Schlüssel vorkonfiguriert.

## Walkie-Talkie

Der bestehende Vordergrund-Audiotransport bleibt verfügbar. Der native Hintergrundkanal nutzt Apples PushToTalk und benötigt dessen Entitlement, Push-fähige Signierung sowie passenden APNs-Provider-Zugang. Der Server protokolliert jetzt auch PTT-APNs-Ablehnungen mit dem konkreten Grund. Die App zeigt Kanalfehler einschließlich iOS-Domäne/Code und fehlender Profilfreigabe an. Bei noch laufendem Upload wird keine zweite eigene Sendung gestartet. Nur eine echte Sprechtastenbetätigung aktiviert die Aufnahme. Die Position der System-Sprechtaste/Dynamic Island bestimmt iOS.

## Update und Prüfung

Python-Datei bei gestopptem Server ersetzen, Konfiguration und `rjlove_data` erhalten, neu starten. Die neuen Diagnose- und Empfangstabellen werden automatisch hinzugefügt. Vorhandene Duftpost-Versionen, Konten und Bewertungen bleiben erhalten. Duftpost-Aufnahme, Schneiden und namenloses Senden sowie alle Liebesfunktionen aus 2.2 bleiben enthalten.

GitHub Actions baut die unsignierte IPA und prüft Backend-Verträge, Paket/Icon-Versionen sowie UI-Geometrie und den echten AAC-Schnitt/Upload auf drei Simulatorgrößen. Push, PTT, AlarmKit-Ton, UWB und Health erfordern zusätzliche Tests auf den beiden tatsächlichen signierten Geräten. Auf beiden iPhones einrichten, Push-Test bei gesperrtem Display auslösen, einen vorausgeplanten Weckruf bis zur Empfängerbestätigung prüfen und danach den Funkkanal einschließlich einer Anrufunterbrechung testen.

Quellen: [ArcticSign](https://arcticsign.app/), [Apple Hintergrundmitteilungen](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app), [Apple AlarmKit](https://developer.apple.com/videos/play/wwdc2025/230/), [Apple App-ID](https://developer.apple.com/help/account/identifiers/register-an-app-id/).
