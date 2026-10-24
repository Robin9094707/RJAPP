# RJ Love 3.9.3 (393)

Nur die App muss aktualisiert werden. Der vorhandene Python-Server 3.9.2 bleibt unverändert kompatibel. Datenbank, Medien, Konten, Bark-/ntfy-Kopplung und Signieridentität beibehalten. Im Komplettpaket liegt die unveränderte Serverdatei 3.9.2 bei.

## Automatische Nahsuche

Auf beiden iPhones RJ Love öffnen. Bei verbundenem Partner startet die UWB-Bereitschaft standardmäßig automatisch, auch wenn „Dich finden“ nie geöffnet wird. Unter „Dich finden“ kann jeder die Automatik abschalten; „Suche beenden“ und der Beenden-Link der Live-Aktivität schalten sie ebenfalls ab. Ein manueller Start bleibt möglich. Ohne Partner oder nach Abmeldung wird kein Token weiter angeboten. Eine verweigerte Systemfreigabe wird nicht in einer Endlosschleife neu angefordert; wiederholte Systemfehler erhalten eine Wartezeit.

Außerhalb der Nahsuchansicht wird nur die Entfernung gesucht. Die Kamera-Freigabe wird nur beim sichtbaren Öffnen der Nahsuchansicht angefordert. Beim Verlassen der Ansicht bzw. des Vordergrunds bleibt dieselbe NI-Sitzung mit denselben Discovery-Tokens bestehen und wird ohne Kamera weiterverwendet. Dadurch muss nicht ausgerechnet im Hintergrund eine neue Tokenverbindung aufgebaut werden.

Vor dem Hintergrundwechsel wird für eine bereits konfigurierte UWB-Verbindung eine sichtbare Live-Aktivität angefordert. Die Option ist separat abschaltbar. Es gibt keine künstliche Audio-, GPS- oder Netzwerk-Dauerschleife zum Wachhalten der App. Discovery-Tokens sind höchstens 15 Minuten gültig; die App begrenzt die Hintergrundsuche auf dieses Fenster, sobald sie Ausführungszeit bekommt. Eine Live-Aktivität stellt keine allgemeine Garantie für dauerhafte Serverabfragen oder beliebigen Hintergrundcode dar. Entfernungswerte werden nach Signalverlust gelöscht, nicht als aktuelle Messung ausgegeben.

iOS unterstützt die Fortsetzung von Nearby Interaction mit einer Live-Aktivität ab iOS 18.4. Ob beide Geräte im Einzelfall weiter messen, hängt von iOS, Hardware, Freigaben, Signierung, Reichweite und der bestehenden Verbindung ab. Nach bewusstem vollständigem Beenden der App lässt sich eine iPhone-zu-iPhone-UWB-Sitzung nicht automatisch neu starten. Beim erneuten Öffnen stellt die Automatik die Bereitschaft wieder her. Beide realen iPhones müssen für den Hardwaretest aktualisiert werden.

## Video-Ton

Der Moment-Player aktiviert nach dem Stoppen vorheriger Audiowiedergaben ausdrücklich eine `.playback`-Audio-Sitzung mit `.moviePlayback`. Der Player wird nicht stumm geschaltet; die Systemlautstärke und die gewählte Audioausgabe bleiben erhalten. Das behebt den bislang fehlenden Ton durch die Standard-/deaktivierte Audio-Sitzung, auch bei aktiviertem Lautlosmodus.

Die sichtbare Videoseite besitzt die Sitzung. Ein verspätetes Aufräumen der vorherigen Seite kann die nächste nicht stummschalten. Andere Aufnahme-/Wiedergabearten übernehmen die Sitzung ausdrücklich; gewöhnliche Stop-Aufrufe deaktivieren einen laufenden Moment-Player nicht mehr nebenbei. Aufnahmen werden nicht zugunsten eines Videos verworfen. Bereits ohne Audiospur gespeicherte Videos erhalten durch dieses Update keine nachträgliche Tonspur.

## Prüfungen

Bestehende Backend-Prüfungen und Galerie-Geometrieprüfung bleiben bestehen. Zusätzliche reine Swift-Prüfungen decken automatischen Start, ausgeschaltete Automatik, fehlenden Partner, verweigerte Freigabe, Fehler-Wartezeit, Hintergrundablauf und Tokenlaufzeit ab. Ein Simulator-Test prüft die native Audio-Kategorie, Movie-Modus, Player-Stummschaltung, Seitenbesitz, fremde Stop-Aufrufe und Freigabe der Audio-Sitzung. Empfang von UWB-Funk und tatsächliche Audioausgabe auf beiden iPhones sind durch Simulator-Tests nicht nachgewiesen.

Apple: https://developer.apple.com/documentation/nearbyinteraction

Apple: https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback
