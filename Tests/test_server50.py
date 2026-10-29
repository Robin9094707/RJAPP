"""Release 5.0: update prompt for older apps, gzip responses and automatic IPA publishing."""
import gzip
import hashlib
import io
import json
import plistlib
import urllib.error
import urllib.request
import unittest
import zipfile
from pathlib import Path
from Tests import test_cinema42 as old

server = old.server


def fake_ipa(version, build, bundle='eu.rjuhas.rjlove'):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, 'w') as archive:
        archive.writestr('Payload/RJ Love.app/Info.plist', plistlib.dumps({'CFBundleIdentifier': bundle, 'CFBundleShortVersionString': version, 'CFBundleVersion': build}))
        archive.writestr('Payload/RJ Love.app/RJ Love', b'binary-' + version.encode())
    return buffer.getvalue()


class Server50Tests(unittest.TestCase):
    setUp = old.Cinema42Tests.setUp
    tearDown = old.Cinema42Tests.tearDown
    request = old.Cinema42Tests.request

    def raw(self, path, who=None, version=server.APP_VERSION, headers=None, data=None, method=None):
        h = {'X-RJ-App-Version': version, 'X-RJ-Protocol': '5'}
        if who is not None:
            h['Authorization'] = 'Bearer ' + self.tokens[who]
        h.update(headers or {})
        request = urllib.request.Request(self.base + path, headers=h, data=data, method=method)
        return urllib.request.urlopen(request, timeout=5)

    def updates(self):
        folder = Path(self.tmp.name) / 'updates'
        folder.mkdir(exist_ok=True)
        self.app.bundled_release_folders = lambda: [folder]
        return folder

    def test_versions_and_old_app_update_prompt(self):
        self.assertEqual(server.APP_VERSION, '5.0.0')
        with urllib.request.urlopen(self.base + '/health', timeout=5) as response:
            health = json.load(response)
        self.assertEqual(health['version'], '5.0.0')
        self.assertEqual(health['minimum_app_version'], '5.0.0')
        self.assertEqual(health['minimum_protocol'], 5)
        for previous in ('4.3.1', '4.3.0', '4.9.9'):
            with self.assertRaises(urllib.error.HTTPError) as failure:
                self.request('/v1/bootstrap', who=0, version=previous)
            self.assertEqual(failure.exception.code, 426)
            body = json.loads(failure.exception.read())
            self.assertEqual(body['error'], 'app_update_required')
            self.assertEqual(body['compatibility']['minimum_app_version'], '5.0.0')
        # The update routes stay open so the old app can still fetch the new IPA.
        self.assertIsNone(self.request('/v1/app-release', who=0, version='4.3.1')['release'])
        self.assertIn('me', self.request('/v1/bootstrap', who=0))

    def test_gzip_only_when_requested(self):
        plain = self.request('/v1/bootstrap', who=0)
        with self.raw('/v1/bootstrap', who=0, headers={'Accept-Encoding': 'gzip, deflate, br'}) as response:
            self.assertEqual(response.headers.get('Content-Encoding'), 'gzip')
            body = response.read()
            self.assertEqual(int(response.headers['Content-Length']), len(body))
        stable = ('me', 'partners', 'records', 'preferences')
        decoded = json.loads(gzip.decompress(body))
        self.assertEqual({k: decoded[k] for k in stable}, {k: plain[k] for k in stable})
        for header in ({}, {'Accept-Encoding': 'gzip;q=0'}, {'Accept-Encoding': 'identity'}, {'Accept-Encoding': 'gzip;q=0, *;q=1'}, {'Accept-Encoding': '*;q=1, gzip;q=0'}):
            with self.raw('/v1/bootstrap', who=0, headers=header) as response:
                self.assertIsNone(response.headers.get('Content-Encoding'))
                value = json.loads(response.read())
                self.assertEqual({k: value[k] for k in stable}, {k: plain[k] for k in stable})
        with self.raw('/v1/bootstrap', who=0, headers={'Accept-Encoding': 'br;q=1, *;q=0.5'}) as response:
            self.assertEqual(response.headers.get('Content-Encoding'), 'gzip')
        # Small answers stay uncompressed.
        with self.raw('/health', headers={'Accept-Encoding': 'gzip'}) as response:
            self.assertIsNone(response.headers.get('Content-Encoding'))

    def test_bundled_ipa_published_once_newest_only_and_downloadable_by_old_app(self):
        before = self.request('/v1/bootstrap', who=0)
        folder = self.updates()
        data = fake_ipa('5.0.0', '500')
        (folder / 'RJ-Love-unsigned.ipa').write_bytes(data)
        (folder / 'other-app.ipa').write_bytes(fake_ipa('9.9.9', '999', bundle='com.example.other'))
        (folder / 'broken.ipa').write_bytes(b'not a zip')
        release = self.request('/v1/app-release', who=1, version='4.3.1')['release']
        self.assertEqual((release['version'], release['build']), ('5.0.0', '500'))
        with self.raw('/v1/app-release/ipa', who=1, version='4.3.1') as response:
            self.assertEqual(response.read(), data)
        # Unchanged files are not hashed again; a re-scan never duplicates a release.
        self.assertIsNone(self.app.import_bundled_releases())
        self.app._release_signature = None
        self.assertIsNone(self.app.import_bundled_releases())
        (folder / 'RJ-Love-older.ipa').write_bytes(fake_ipa('4.3.1', '431'))
        self.assertIsNone(self.app.import_bundled_releases())
        with self.app.database.connect() as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM app_releases').fetchone()[0], 1)
            digest = db.execute('SELECT sha256 FROM assets WHERE owner_id=?', ('rj-server',)).fetchone()[0]
        self.assertEqual(digest, hashlib.sha256(data).hexdigest())
        # Feather source of an old app lists the bundled release.
        token = self.request('/v1/update-feed', {'base_url': self.base}, 0, version='4.3.1')['token']
        with urllib.request.urlopen(self.base + '/updates/' + token + '/source.json', timeout=5) as response:
            source = json.load(response)
        self.assertEqual(source['apps'][0]['versions'][0]['version'], '5.0.0')
        # A newer build supersedes it; the server-owned asset survives cleanup and costs no user quota.
        newer = fake_ipa('5.0.1', '501')
        (folder / 'RJ-Love-unsigned.ipa').write_bytes(newer)
        self.assertEqual(self.app.import_bundled_releases(), '5.0.1')
        self.app.cleanup_assets()
        with self.raw('/v1/app-release/ipa', who=0) as response:
            self.assertEqual(response.read(), newer)
        after = self.request('/v1/bootstrap', who=0)
        for key in ('me', 'partners', 'records', 'preferences'):
            self.assertEqual(before[key], after[key])
        self.assertEqual(before['storage_used_bytes'], after['storage_used_bytes'])

    def test_existing_data_survives_restart_with_new_server(self):
        note = self.request('/v1/records', {'id': str(server.uuid.uuid4()), 'kind': 'note', 'payload': {'title': 'Aus 4.3.1', 'text': 'bleibt'}}, 0)
        before = self.request('/v1/bootstrap', who=1)
        server.Database(self.app.database.path)
        self.app.safe_import_bundled_releases()
        after = self.request('/v1/bootstrap', who=1)
        for key in ('me', 'partners', 'records', 'preferences'):
            self.assertEqual(before[key], after[key])
        self.assertIn(note['id'], [record['id'] for record in after['records']])


if __name__ == '__main__':
    unittest.main()
