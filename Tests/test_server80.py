"""Release 8.0: shared diary records, per-person AI sharing and the text-only AI context API."""
import json
import urllib.error
import uuid
import unittest
from Tests import test_cinema42 as old

server = old.server


class Server80Tests(unittest.TestCase):
    setUp = old.Cinema42Tests.setUp
    tearDown = old.Cinema42Tests.tearDown
    request = old.Cinema42Tests.request

    def save(self, kind, payload, who=0, record_id=None):
        return self.request('/v1/records', {'id': record_id or str(uuid.uuid4()), 'kind': kind, 'payload': payload}, who)

    def failure(self, call):
        with self.assertRaises(urllib.error.HTTPError) as caught:
            call()
        return caught.exception.code, json.loads(caught.exception.read())

    def test_version_gate_for_older_apps(self):
        self.assertEqual(server.APP_VERSION, '10.0.0')
        self.assertEqual(server.MINIMUM_APP_VERSION, '10.0.0')
        code, body = self.failure(lambda: self.request('/v1/bootstrap', who=0, version='8.0.0'))
        self.assertEqual(code, 426)
        self.assertEqual(body['error'], 'app_update_required')
        self.assertIsNone(self.request('/v1/app-release', who=0, version='8.0.0')['release'])

    def test_diary_records_validation_and_ownership(self):
        personal = self.save('diary', {'title': 'Mein Tag', 'text': 'Spaziergang am See.', 'day': '2026-11-14', 'emoji': '🥰', 'ai_assisted': True})
        self.assertEqual(personal['payload']['entry_type'], 'personal')
        together = self.save('diary', {'title': 'Unser Tag', 'text': 'Pizza und Film.', 'day': '2026-11-14', 'entry_type': 'together'})
        # The partner may continue a shared page, but not rewrite a personal one.
        updated = self.save('diary', {'title': 'Unser Tag', 'text': 'Pizza, Film und Tee.', 'day': '2026-11-14', 'entry_type': 'together'}, who=1, record_id=together['id'])
        self.assertEqual(updated['owner_id'], self.user)
        code, body = self.failure(lambda: self.save('diary', {'title': 'Fremd', 'text': 'x', 'day': '2026-11-14'}, who=1, record_id=personal['id']))
        self.assertEqual((code, body['error']), (403, 'diary_owner'))
        code, _ = self.failure(lambda: self.save('diary', {'title': 'Fremd', 'text': 'x', 'day': '2026-11-14', 'entry_type': 'together'}, who=1, record_id=personal['id']))
        self.assertEqual(code, 403)
        for bad in ({'title': 'x', 'text': 'y', 'day': '14.11.2026'}, {'title': 'x', 'day': '2026-11-14'}, {'title': 'x', 'text': 'y', 'day': '2026-11-14', 'entry_type': 'secret'}, {'title': 'x', 'text': 'y', 'day': '2026-11-14', 'image_base64': 'AA=='}):
            code, _ = self.failure(lambda bad=bad: self.save('diary', bad))
            self.assertEqual(code, 400)
        kinds = {r['kind'] for r in self.request('/v1/bootstrap', who=1)['records']}
        self.assertIn('diary', kinds)
        archive = self.request('/v1/records/archive?kind=diary', who=1)['records']
        self.assertEqual(len(archive), 2)

    def test_ai_sharing_controls_context(self):
        self.save('diary', {'title': 'Robin', 'text': 'Geheimnis A', 'day': '2026-11-14'}, who=0)
        self.save('wish', {'title': 'Urlaub', 'text': 'Meer'}, who=1)
        status = self.request('/v1/ai/status', who=0)
        self.assertFalse(status['my_sharing'])
        self.assertFalse(status['partner_sharing'])
        context = self.request('/v1/ai/context?days=30', who=0)
        self.assertFalse(context['partner']['shares'])
        self.assertEqual({i['title'] for i in context['items']}, {'Robin'})
        self.assertEqual(self.request('/v1/ai/sharing', {'enabled': True}, 1)['my_sharing'], True)
        context = self.request('/v1/ai/context?days=30', who=0)
        self.assertTrue(context['partner']['shares'])
        self.assertEqual({i['title'] for i in context['items']}, {'Robin', 'Urlaub'})
        diary = next(i for i in context['items'] if i['kind'] == 'diary')
        self.assertEqual(diary['day'], '2026-11-14')
        # The partner's own context never depends on the other person's toggle for their own data.
        other = self.request('/v1/ai/context', who=1)
        self.assertEqual({i['title'] for i in other['items']}, {'Urlaub'})
        self.assertEqual(self.request('/v1/ai/status', who=0)['partner_sharing'], True)
        code, _ = self.failure(lambda: self.request('/v1/ai/sharing', {'enabled': 'yes'}, 0))
        self.assertEqual(code, 400)
        code, _ = self.failure(lambda: self.request('/v1/ai/context?days=abc', who=0))
        self.assertEqual(code, 400)

    def test_dashboard_companion_card_and_migration(self):
        prefs = self.request('/v1/preferences', who=0)
        kinds = [c['kind'] for c in prefs['dashboard']['cards']]
        self.assertEqual(kinds.count('companion'), 1)
        self.assertEqual(kinds.index('companion'), kinds.index('dailyJournal') + 1)
        # A 6.0 layout gets the card once; removing it afterwards is respected.
        dashboard = prefs['dashboard']
        dashboard['cards'] = [c for c in dashboard['cards'] if c['kind'] != 'companion']
        with self.app.database.connect() as db:
            legacy = dict(dashboard, layoutVersion=3)
            db.execute('INSERT INTO user_preferences(user_id,dashboard,revision,updated_at) VALUES(?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET dashboard=excluded.dashboard,revision=excluded.revision', (self.user, json.dumps(legacy), 4, server.iso_now()))
        migrated = self.request('/v1/preferences', who=0)
        self.assertEqual(migrated['dashboard']['layoutVersion'], 4)
        self.assertIn('companion', [c['kind'] for c in migrated['dashboard']['cards']])
        dashboard = migrated['dashboard']
        dashboard['cards'] = [c for c in dashboard['cards'] if c['kind'] != 'companion']
        saved = self.request('/v1/preferences', {'dashboard': dashboard, 'revision': migrated['revision']}, 0)
        self.assertNotIn('companion', [c['kind'] for c in saved['dashboard']['cards']])
        self.assertNotIn('companion', [c['kind'] for c in self.request('/v1/preferences', who=0)['dashboard']['cards']])

if __name__ == '__main__':
    unittest.main()
