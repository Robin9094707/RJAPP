"""Release 9.0: group chat with ChatGPT answers, voice messages and diary 2.0 context fields."""
import json
import threading
import time
import urllib.error
import uuid
import unittest
from Tests import test_cinema42 as old
from Tests import test_server70 as walkie

server = old.server


class Server90Tests(unittest.TestCase):
    setUp = old.Cinema42Tests.setUp
    tearDown = old.Cinema42Tests.tearDown
    request = old.Cinema42Tests.request
    upload_audio = walkie.Server70Tests.upload_audio
    call = walkie.Server70Tests.call

    def save(self, kind, payload, who=0, record_id=None):
        return self.request('/v1/records', {'id': record_id or str(uuid.uuid4()), 'kind': kind, 'payload': payload}, who)

    def failure(self, call):
        with self.assertRaises(urllib.error.HTTPError) as caught:
            call()
        return caught.exception.code, json.loads(caught.exception.read())

    def test_versions(self):
        self.assertEqual(server.APP_VERSION, '9.0.0')
        code, _ = self.failure(lambda: self.request('/v1/bootstrap', who=0, version='8.0.0'))
        self.assertEqual(code, 426)

    def test_group_chat_text_voice_ai_and_long_poll(self):
        start = self.request('/v1/group?wait=0', who=1)['server_time']
        text = self.save('group', {'text': 'Hallo ihr zwei'}, who=0)
        asset = self.upload_audio(1)
        voice = self.save('group', {'text': 'Ich hab dich lieb', 'asset_ids': [asset], 'media_kind': 'audio', 'audio_seconds': 4.2}, who=1)
        ai = self.save('group', {'text': 'Ein Gedicht für euch', 'ai': True, 'model': 'gpt-6-luna', 'requested_by': self.user}, who=0)
        listed = self.request('/v1/group?after=' + start, who=1)['messages']
        self.assertEqual([m['id'] for m in listed], [text['id'], voice['id'], ai['id']])
        self.assertTrue(listed[2]['payload']['ai'])
        # Group messages stay out of bootstrap and the daily journal.
        self.assertNotIn('group', {r['kind'] for r in self.request('/v1/bootstrap', who=0)['records']})
        # The partner can hear the voice message asset.
        req = _request.Request(self.base + '/v1/assets/' + asset, headers={'Authorization': 'Bearer ' + self.tokens[0], 'X-RJ-App-Version': server.APP_VERSION, 'X-RJ-Protocol': '5'})
        with _request.urlopen(req, timeout=5) as response:
            self.assertEqual(response.read(), b'fake-m4a-audio')
        # Only the author may edit or recall.
        code, _ = self.failure(lambda: self.save('group', {'text': 'fremd'}, who=1, record_id=text['id']))
        self.assertEqual(code, 403)
        code, _ = self.failure(lambda: urllib.request_delete(self, text['id'], 1))
        self.assertEqual(code, 403)
        # Long poll wakes up when a message arrives.
        after = self.request('/v1/group?wait=0', who=1)['server_time']
        result = {}
        def wait():
            result['messages'] = self.request('/v1/group?wait=10&after=' + after, who=1)['messages']
        thread = threading.Thread(target=wait); thread.start(); time.sleep(0.4)
        began = time.monotonic()
        fresh = self.save('group', {'text': 'Live!'}, who=0)
        thread.join(timeout=8)
        self.assertLess(time.monotonic() - began, 5)
        self.assertEqual([m['id'] for m in result['messages']], [fresh['id']])
        urllib.request_delete(self, fresh['id'], 0)
        gone = self.request('/v1/group?after=' + after, who=1)['messages']
        self.assertIn({'id': fresh['id'], 'deleted': True}, gone)
        latest = self.request('/v1/group?limit=2', who=1)['messages']
        self.assertEqual([m['id'] for m in latest], [voice['id'], ai['id']])

    def test_group_validation(self):
        for bad in ({}, {'text': 'x', 'media_kind': 'video'}, {'text': 'x', 'audio_seconds': 9999}, {'text': 'x', 'requested_by': 'nobody'}, {'text': 'x', 'caption': 'y'}):
            code, _ = self.failure(lambda bad=bad: self.save('group', bad))
            self.assertEqual(code, 400)

    def test_diary_context_fields_and_ai_context(self):
        page = self.save('diary', {'title': 'See', 'text': 'Am See.', 'day': '2026-11-14', 'emoji': '😌', 'location': 'Wörthsee', 'latitude': 48.07, 'longitude': 11.2, 'tags': 'natur,wir', 'template': 'evening', 'context': '8000 Schritte'})
        self.assertEqual(page['payload']['location'], 'Wörthsee')
        code, _ = self.failure(lambda: self.save('diary', {'title': 'x', 'text': 'y', 'day': '2026-11-14', 'latitude': 500, 'longitude': 1}))
        self.assertEqual(code, 400)
        self.save('group', {'text': 'Gruppenhallo'}, who=0)
        items = self.request('/v1/ai/context', who=0)['items']
        diary = next(i for i in items if i['kind'] == 'diary')
        self.assertEqual((diary['place'], diary['tags']), ('Wörthsee', 'natur,wir'))
        self.assertIn('group', {i['kind'] for i in items})
        # Partners cannot delete each other's personal diary pages.
        code, _ = self.failure(lambda: urllib.request_delete(self, page['id'], 1))
        self.assertEqual(code, 403)


import urllib.request as _request


def _delete(case, record_id, who):
    req = _request.Request(case.base + '/v1/records/' + record_id, method='DELETE', headers={'Authorization': 'Bearer ' + case.tokens[who], 'X-RJ-App-Version': server.APP_VERSION, 'X-RJ-Protocol': '5'})
    with _request.urlopen(req, timeout=5) as response:
        return response.status


urllib.request_delete = _delete

if __name__ == '__main__':
    unittest.main()
