"""Release 10.0: background heartbeat, per-field transfer timestamps, telemetry and silent presence pings."""
import json
import unittest
import urllib.error
from unittest.mock import patch

from Tests import test_cinema42 as old

server = old.server


class Server100Tests(unittest.TestCase):
    setUp = old.Cinema42Tests.setUp
    tearDown = old.Cinema42Tests.tearDown
    request = old.Cinema42Tests.request

    def failure(self, call):
        with self.assertRaises(urllib.error.HTTPError) as caught:
            call()
        return caught.exception.code, json.loads(caught.exception.read())

    def test_versions(self):
        self.assertEqual(server.APP_VERSION, '10.0.0')
        self.assertEqual(server.MINIMUM_APP_VERSION, '10.0.0')
        code, _ = self.failure(lambda: self.request('/v1/bootstrap', who=0, version='9.0.1'))
        self.assertEqual(code, 426)

    def test_heartbeat_without_location_keeps_full_presence(self):
        self.request('/v1/presence', {'battery_level': 80, 'battery_state': 'unplugged', 'steps': 4200,
                                      'location_sharing': True, 'latitude': 48.2, 'longitude': 16.37,
                                      'app_state': 'foreground', 'telemetry': {'thermal_state': 'nominal'}}, 0)
        first = self.request('/v1/bootstrap', who=1)['partners'][0]['presence']
        self.assertIn('battery_reported_at', first)
        self.assertIn('location_reported_at', first)
        self.assertIn('health_reported_at', first)
        self.assertEqual(first['report_source'], 'App im Vordergrund')

        result = self.request('/v1/presence/heartbeat', {
            'battery_level': 79, 'battery_state': 'unplugged', 'low_power_mode': False, 'network_type': 'cellular',
            'source': 'Akkuänderung', 'telemetry': {'thermal_state': 'fair', 'uptime_s': 3600, 'unknown_key': 'x',
                                                   'last_upload_latency_ms': 210}}, 0)
        self.assertEqual(result['report_source'], 'Akkuänderung')
        presence = self.request('/v1/bootstrap', who=1)['partners'][0]['presence']
        self.assertEqual(presence['battery_level'], 79)
        self.assertEqual(presence['steps'], 4200)  # Health survives a background heartbeat.
        self.assertEqual(presence['latitude'], 48.2)  # Position survives a heartbeat without a fix.
        self.assertEqual(presence['location_reported_at'], first['location_reported_at'])
        self.assertGreaterEqual(presence['battery_reported_at'], first['battery_reported_at'])
        self.assertEqual(presence['telemetry'], {'thermal_state': 'fair', 'uptime_s': 3600, 'last_upload_latency_ms': 210})
        self.assertEqual(presence['report_count'], 2)

    def test_heartbeat_validation_and_sharing_off(self):
        code, _ = self.failure(lambda: self.request('/v1/presence/heartbeat', {'latitude': 99, 'longitude': 0}, 0))
        self.assertEqual(code, 400)
        code, _ = self.failure(lambda: self.request('/v1/presence/heartbeat', {'telemetry': {'thermal_state': {'nested': 1}}}, 0))
        self.assertEqual(code, 400)
        self.request('/v1/presence', {'battery_level': 50, 'location_sharing': False, 'app_state': 'foreground'}, 0)
        self.request('/v1/presence/heartbeat', {'battery_level': 49, 'latitude': 1.0, 'longitude': 2.0, 'source': 'Standort'}, 0)
        presence = self.request('/v1/bootstrap', who=1)['partners'][0]['presence']
        self.assertNotIn('latitude', presence)
        self.assertEqual(presence['battery_level'], 49)
        # Bad optional values are dropped, not stored.
        self.request('/v1/presence/heartbeat', {'battery_level': 400, 'battery_state': 'exploding'}, 0)
        presence = self.request('/v1/bootstrap', who=1)['partners'][0]['presence']
        self.assertEqual(presence['battery_level'], 49)

    def test_heartbeat_triggers_battery_events_once(self):
        self.request('/v1/presence/heartbeat', {'battery_level': 40, 'battery_state': 'unplugged'}, 0)
        with patch.object(self.app, 'broadcast_event') as events:
            self.request('/v1/presence/heartbeat', {'battery_level': 12, 'battery_state': 'unplugged'}, 0)
            self.request('/v1/presence/heartbeat', {'battery_level': 11, 'battery_state': 'unplugged'}, 0)
            self.request('/v1/presence/heartbeat', {'battery_level': 11, 'battery_state': 'charging'}, 0)
            self.request('/v1/presence/heartbeat', {'battery_level': 100, 'battery_state': 'full'}, 0)
        kinds = [call.args[1] for call in events.call_args_list]
        self.assertEqual(kinds, ['battery_low', 'charging_started'])

    def test_telemetry_history_and_stats(self):
        for level, source in ((90, 'Standortänderung'), (89, 'Akkuänderung'), (88, 'Akkuänderung')):
            self.request('/v1/presence/heartbeat', {'battery_level': level, 'source': source}, 1)
        data = self.request('/v1/presence/telemetry', who=0)
        self.assertEqual([u['me'] for u in data['users']], [True, False])
        partner = data['users'][1]
        self.assertEqual([r['battery_level'] for r in partner['reports']], [88, 89, 90])
        self.assertEqual(partner['stats']['reports_24h'], 3)
        self.assertEqual(partner['stats']['by_source'], {'Standortänderung': 1, 'Akkuänderung': 2})
        self.assertIsNotNone(partner['stats']['median_gap_s'])
        self.assertFalse(data['apns_enabled'])

    def test_ping_without_apns_is_reported_and_rate_limited(self):
        ping = self.request('/v1/presence/ping', {}, 0)
        self.assertEqual(ping['status'], 'unavailable')
        code, body = self.failure(lambda: self.request('/v1/presence/ping', {}, 0))
        self.assertEqual(code, 429)
        self.assertEqual(body['error'] if 'error' in body else body.get('code'), 'ping_too_soon')
        # The partner answers with the ping id: the ping is marked answered with its latency.
        self.request('/v1/presence/heartbeat', {'battery_level': 70, 'source': 'Stiller Push', 'ping_id': ping['id']}, 1)
        pings = self.request('/v1/presence/telemetry', who=0)['pings']
        self.assertEqual(pings[0]['status'], 'answered')
        self.assertIsNotNone(pings[0]['answered_at'])

    def test_ping_with_apns_sends_background_push(self):
        self.app.config['apns']['enabled'] = True
        with self.app.database.connect() as db:
            db.execute("INSERT INTO devices(id,user_id,device_token,environment,updated_at) VALUES('d1',?,'abc','production','2026-01-01T00:00:00Z')", (self.other,))
        sent = []

        def fake_deliver(user_id, token, environment, payload, *, topic, push_type, expiration=0):
            sent.append((user_id, payload, push_type))
            return '200', ''
        with patch.object(self.app.apns, 'deliver', side_effect=fake_deliver):
            ping = self.request('/v1/presence/ping', {}, 0)
            for _ in range(50):
                if sent:
                    break
                import time; time.sleep(0.05)
        self.assertEqual(ping['status'], 'queued')
        self.assertEqual(sent[0][0], self.other)
        self.assertEqual(sent[0][2], 'background')
        self.assertEqual(sent[0][1]['aps'], {'content-available': 1})
        self.assertEqual(sent[0][1]['rj_presence_ping'], ping['id'])


if __name__ == '__main__':
    unittest.main()
