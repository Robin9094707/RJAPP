# Datenschutz & Sicherheitsmodell

RJ Love ist für eine private, einvernehmliche Verbindung zwischen den konfigurierten Personen gedacht. Jede sensible Datenart ist in iOS sichtbar genehmigungspflichtig und in der App separat deaktivierbar.

## Gespeichert

- Server: freigegebene Position/Statuswerte, gemeinsame Inhalte, Sitzungen, APNs-Gerätetoken und Ereigniszustand.
- iPhone-Schlüsselbund: Server-Sitzungstoken.
- iPhone-App-Container/App Group: nicht geheime UI-Einstellungen, Widget-Snapshot und noch nicht gesendete Widget-Herzgedanken.

## Nicht erhoben

- keine Werbung, Tracker oder Analytics;
- keine Kontakte, Nachrichten, Anruflisten oder Browserdaten;
- keine Health-Rohdaten oder vollständigen Kalender;
- kein Fokusname; Apple stellt ihn Drittanbieter-Apps nicht bereit;
- kein WLAN-Passwort.

## Empfehlungen

- öffentliche Server ausschließlich über HTTPS betreiben;
- `rjapp_config.json`, APNs-Keys, Zertifikatschlüssel und SQLite-Daten niemals veröffentlichen;
- lange, einmalige Passwörter verwenden;
- Serververzeichnis regelmäßig durch den vorhandenen Hosting-Backupdienst sichern;
- bei Geräteverlust Passwort in der Konfiguration ändern und den Server neu starten; bestehende Sitzungen bei Bedarf durch Löschen der Tabelle `sessions` oder der SQLite-Datei nur nach eigenem Backup widerrufen.
