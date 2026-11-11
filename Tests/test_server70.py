"""Release 7.0: walkie-talkie messages, question of the day, photo-wish expiry/nudge and background location merge."""
import hashlib
import json
import threading
import time
import unittest
import urllib.error
import urllib.request
import uuid
from Tests import test_cinema42 as old

server = old.server


class Server70Tests(unittest.TestCase):
    setUp = old.Cinema42Tests.setUp
    tearDown = old.Cinema42Tests.tearDown
    request = old.Cinema42Tests.request

    def call(self, path, who, method='GET', body=None):
        h = {'X-RJ-App-Version': server.APP_VERSION, 'X-RJ-Protocol': '5', 'Authorization': 'Bearer ' + self.tokens[who]}
        data = None
        if body is not None:
            h['Content-Type'] = 'application/json'; data = json.dumps(body).encode()
        request = urllib.request.Request(self.base + path, data=data, headers=h, method=method)
        with urllib.request.urlopen(request, timeout=40) as response:
            raw = response.read()
            return json.loads(raw) if raw else None

    def upload_audio(self, who, payload=b'fake-m4a-audio'):
        asset = self.request('/v1/assets', {'filename': 'walkie.m4a', 'mime_type': 'audio/mp4', 'size_bytes': len(payload), 'sha256': hashlib.sha256(payload).hexdigest()}, who)
        h = {'X-RJ-App-Version': server.APP_VERSION, 'X-RJ-Protocol': '5', 'Authorization': 'Bearer ' + self.tokens[who], 'Content-Type': 'audio/mp4'}
        urllib.request.urlopen(urllib.request.Request(self.base + '/v1/assets/' + asset['id'], data=payload, headers=h, method='PUT'), timeout=5).read()
        return asset['id']

    def test_versions(self):
        self.assertEqual(server.APP_VERSION, '7.0.0')
        self.assertEqual(server.MINIMUM_APP_VERSION, '7.0.0')
        with self.assertRaises(urllib.error.HTTPError) as failure:
            self.request('/v1/bootstrap', who=0, version='6.0.0')
        self.assertEqual(failure.exception.code, 426)

    def test_walkie_roundtrip_long_poll_played_and_privacy(self):
        start = self.call('/v1/walkie', 1)['server_time']
        asset = self.upload_audio(0)
        received = {}
        def wait():
            received['value'] = self.call('/v1/walkie?after=' + start + '&wait=10', 1)
        waiter = threading.Thread(target=wait); waiter.start()
        time.sleep(0.4)
        message_id = str(uuid.uuid4())
        sent = self.request('/v1/walkie', {'id': message_id, 'asset_id': asset, 'duration': 4.2}, 0)
        self.assertEqual(sent['target_id'], self.other)
        # Idempotent retry.
        self.assertEqual(self.request('/v1/walkie', {'id': message_id, 'asset_id': asset, 'duration': 4.2}, 0)['id'], message_id)
        waiter.join(timeout=15)
        self.assertEqual([m['id'] for m in received['value']['messages']], [message_id])
        boot = self.request('/v1/bootstrap', who=1)
        self.assertEqual(boot['walkie_unplayed'], 1)
        self.assertTrue(any(e['kind'] == 'walkie_message' for e in boot['events']))
        # Recipient may download the audio; the asset survives cleanup.
        self.app.cleanup_assets()
        h = {'X-RJ-App-Version': server.APP_VERSION, 'X-RJ-Protocol': '5', 'Authorization': 'Bearer ' + self.tokens[1]}
        with urllib.request.urlopen(urllib.request.Request(self.base + '/v1/assets/' + asset, headers=h), timeout=5) as response:
            self.assertEqual(response.read(), b'fake-m4a-audio')
        with self.assertRaises(urllib.error.HTTPError) as failure:
            self.call('/v1/walkie/' + message_id + '/played', 0, 'POST', {})
        self.assertEqual(failure.exception.code, 403)
        self.call('/v1/walkie/' + message_id + '/played', 1, 'POST', {})
        listing = self.call('/v1/walkie', 0)['messages']
        self.assertIsNotNone(listing[0]['played_at'])
        self.assertEqual(self.request('/v1/bootstrap', who=1)['walkie_unplayed'], 0)
        with self.assertRaises(urllib.error.HTTPError):
            self.request('/v1/walkie', {'id': str(uuid.uuid4()), 'asset_id': asset, 'duration': 999}, 0)
        with self.assertRaises(urllib.error.HTTPError) as failure:
            self.call('/v1/walkie/' + message_id, 1, 'DELETE')
        self.assertEqual(failure.exception.code, 403)
        cursor = self.call('/v1/walkie', 1)['server_time']
        self.call('/v1/walkie/' + message_id, 0, 'DELETE')
        self.assertEqual(self.call('/v1/walkie', 1)['messages'], [])
        # Clients that already fetched it receive a tombstone and drop it.
        tombstones = self.call('/v1/walkie?after=' + cursor, 1)['messages']
        self.assertEqual([(m['id'], m.get('deleted')) for m in tombstones], [(message_id, True)])

    def test_walkie_cursor_never_skips_a_message(self):
        asset = self.upload_audio(0)
        cursor = self.call('/v1/walkie', 1)['server_time']
        seen = set()
        for _ in range(5):
            sent = self.request('/v1/walkie', {'id': str(uuid.uuid4()), 'asset_id': asset, 'duration': 1.0}, 0)
            listing = self.call('/v1/walkie?after=' + cursor, 1)
            seen.update(m['id'] for m in listing['messages'])
            self.assertIn(sent['id'], seen)
            self.assertGreaterEqual(listing['server_time'], sent['created_at'])
            cursor = listing['server_time']

    def test_question_of_the_day_reveals_only_after_answering(self):
        day = self.app.local_day()
        self.request('/v1/daily-question', {'day': day, 'question': 'Was war heute schön?', 'answer': 'Dein Lachen'}, 0)
        other = self.call('/v1/daily-question?day=' + day, 1)
        self.assertTrue(other['partner_answered'])
        self.assertIsNone(other['partner'])
        self.request('/v1/daily-question', {'day': day, 'question': 'Was war heute schön?', 'answer': 'Unser Kaffee'}, 1)
        both = self.call('/v1/daily-question?day=' + day, 1)
        self.assertEqual(both['partner']['answer'], 'Dein Lachen')
        self.assertEqual(both['mine']['answer'], 'Unser Kaffee')
        self.assertEqual(len(self.call('/v1/daily-question/history', 0)['days']), 1)
        self.assertEqual(self.request('/v1/bootstrap', who=0)['daily_question']['partner']['answer'], 'Unser Kaffee')
        with self.assertRaises(urllib.error.HTTPError):
            self.request('/v1/daily-question', {'day': '2001-01-01', 'question': 'x', 'answer': 'y'}, 0)

    def test_stuck_photo_request_expires_and_nudge_is_rate_limited(self):
        request_id = str(uuid.uuid4())
        self.request('/v1/photo-requests', {'id': request_id, 'title': 'Bitte lächeln'}, 0)
        self.assertEqual(self.call('/v1/photo-requests', 1)['incoming'][0]['id'], request_id)
        self.call('/v1/photo-requests/' + request_id + '/nudge', 0, 'POST', {})
        with self.assertRaises(urllib.error.HTTPError) as failure:
            self.call('/v1/photo-requests/' + request_id + '/nudge', 0, 'POST', {})
        self.assertEqual(failure.exception.code, 429)
        with self.assertRaises(urllib.error.HTTPError):
            self.call('/v1/photo-requests/' + request_id + '/nudge', 1, 'POST', {})
        with self.assertRaises(urllib.error.HTTPError) as failure:
            self.request('/v1/photo-requests', {'id': str(uuid.uuid4()), 'title': 'Noch eins'}, 0)
        self.assertEqual(failure.exception.code, 409)
        with self.app.database.connect() as db:
            db.execute("UPDATE records SET created_at='2020-01-01T00:00:00Z' WHERE id=?", (request_id,))
        self.assertIsNone(self.call('/v1/photo-requests', 0)['outgoing'])
        self.assertIn(request_id, self.request('/v1/bootstrap', who=1)['deleted_record_ids'])
        fresh = str(uuid.uuid4())
        self.assertEqual(self.request('/v1/photo-requests', {'id': fresh, 'title': 'Neu'}, 0)['id'], fresh)

    def test_background_location_merges_into_presence(self):
        self.request('/v1/presence', {'latitude': 48.1, 'longitude': 11.5, 'steps': 4321, 'battery_level': 80, 'location_sharing': True, 'status_message': 'Hallo'}, 0)
        self.request('/v1/presence/location', {'latitude': 48.2, 'longitude': 11.6, 'battery_level': 77, 'app_state': 'background', 'steps': 1}, 0)
        partner = self.request('/v1/bootstrap', who=1)['partners'][0]['presence']
        self.assertEqual((partner['latitude'], partner['longitude'], partner['battery_level']), (48.2, 11.6, 77))
        self.assertEqual(partner['steps'], 4321)
        self.assertEqual(partner['status_message'], 'Hallo')
        self.request('/v1/presence', {'location_sharing': False}, 0)
        self.request('/v1/presence/location', {'latitude': 1, 'longitude': 1}, 0)
        self.assertNotIn('latitude', self.request('/v1/bootstrap', who=1)['partners'][0]['presence'])

    def test_preferences_gain_new_cards(self):
        prefs = self.request('/v1/preferences', who=0)
        kinds = [c['kind'] for c in prefs['dashboard']['cards']]
        self.assertEqual(kinds[:2], ['question', 'walkie'])
        dashboard = prefs['dashboard']; dashboard['tabs'][1]['action'] = 'walkie'
        saved = self.request('/v1/preferences', {'dashboard': dashboard, 'revision': prefs['revision']}, 0)
        self.assertEqual(saved['dashboard']['layoutVersion'], 3)
        # Layout from 6.0 gains the new cards without losing the existing order.
        with self.app.database.connect() as db:
            stored = json.loads(db.execute('SELECT dashboard FROM user_preferences WHERE user_id=?', (self.user,)).fetchone()[0])
            stored['layoutVersion'] = 2; stored['cards'] = [c for c in stored['cards'] if c['kind'] not in ('walkie', 'question')]
            db.execute('UPDATE user_preferences SET dashboard=? WHERE user_id=?', (json.dumps(stored), self.user))
        migrated = [c['kind'] for c in self.request('/v1/preferences', who=0)['dashboard']['cards']]
        self.assertEqual(migrated[:2], ['question', 'walkie'])
        self.assertEqual(migrated[2:], [c['kind'] for c in stored['cards']])


if __name__ == '__main__':
    unittest.main()
