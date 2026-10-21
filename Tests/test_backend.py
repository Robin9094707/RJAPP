import importlib.util
import json
from pathlib import Path
import tempfile
import threading
import unittest
import urllib.error
import urllib.request


MODULE_PATH = Path(__file__).resolve().parents[1] / "Backend" / "rj_love_server.py"
SPEC = importlib.util.spec_from_file_location("rj_love_server", MODULE_PATH)
SERVER = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(SERVER)


class RJLoveBackendTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        root = Path(self.temporary.name)
        self.config = SERVER.default_config()
        self.config["server"]["host"] = "127.0.0.1"
        self.config["server"]["port"] = 0
        self.config["server"]["data_directory"] = str(root / "data")
        self.config["users"][0]["password"] = "robin-test-password"
        self.config["users"][1]["password"] = "raphaela-test-password"
        self.config_path = root / "rjapp_config.json"
        self.config_path.write_text(json.dumps(self.config), encoding="utf-8")
        self.app = SERVER.RJLoveApplication(self.config, self.config_path)
        self.httpd = SERVER.build_server(self.app)
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()
        self.base = f"http://127.0.0.1:{self.httpd.server_port}"

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.app.close()
        self.thread.join(timeout=3)
        self.temporary.cleanup()

    def request(self, path, method="GET", body=None, token=None):
        encoded = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(self.base + path, data=encoded, method=method)
        request.add_header("Accept", "application/json")
        if body is not None:
            request.add_header("Content-Type", "application/json")
        if token:
            request.add_header("Authorization", f"Bearer {token}")
        with urllib.request.urlopen(request, timeout=5) as response:
            raw = response.read()
            return response.status, json.loads(raw) if raw else None

    def login(self, username="robin", password="robin-test-password"):
        status, body = self.request(
            "/v1/auth/login",
            "POST",
            {"username": username, "password": password, "device_id": "test-device"},
        )
        self.assertEqual(status, 200)
        return body["token"]

    def request_error(self, path, method="GET", body=None, token=None):
        try:
            self.request(path, method, body, token)
        except urllib.error.HTTPError as error:
            try:
                raw = error.read()
                return error.code, json.loads(raw) if raw else None
            finally:
                error.close()
        self.fail("Die Anfrage hätte abgelehnt werden müssen.")

    def test_health_and_authentication(self):
        status, health = self.request("/health")
        self.assertEqual(status, 200)
        self.assertEqual(health["status"], "ok")
        token = self.login()
        status, snapshot = self.request("/v1/bootstrap", token=token)
        self.assertEqual(status, 200)
        self.assertEqual(snapshot["me"]["id"], "robin")
        self.assertEqual(snapshot["partners"][0]["id"], "raphaela")

    def test_presence_thoughts_records_and_restart_persistence(self):
        token = self.login()
        status, _ = self.request(
            "/v1/presence",
            "POST",
            {"battery_level": 82, "battery_state": "unplugged", "network_type": "wifi", "latitude": 51.4, "longitude": 6.7},
            token,
        )
        self.assertEqual(status, 200)
        status, thought = self.request("/v1/thoughts", "POST", {}, token)
        self.assertEqual(thought["count"], 1)

        record_id = "45b234f4-ed2c-4f5d-bc16-380573ea9ff4"
        status, record = self.request(
            "/v1/records",
            "POST",
            {"id": record_id, "kind": "note", "payload": {"title": "Test", "text": "Bleibt gespeichert"}},
            token,
        )
        self.assertEqual(status, 200)
        self.assertEqual(record["id"], record_id)

        status, snapshot = self.request("/v1/bootstrap", token=token)
        self.assertEqual(snapshot["thoughts"]["robin"], 1)
        self.assertEqual(snapshot["partners"][0]["id"], "raphaela")
        self.assertTrue(any(item["id"] == record_id for item in snapshot["records"]))

        # A new application object reads the same SQLite database after a process restart.
        restarted = SERVER.RJLoveApplication(self.config, self.config_path)
        try:
            persisted = restarted.bootstrap("robin")
            self.assertTrue(any(item["id"] == record_id for item in persisted["records"]))
            self.assertEqual(persisted["thoughts"]["robin"], 1)
        finally:
            restarted.close()

        status, _ = self.request(f"/v1/records/{record_id}", "DELETE", None, token)
        self.assertEqual(status, 204)

    def test_invalid_login_is_rejected(self):
        with self.assertRaises(urllib.error.HTTPError) as raised:
            self.request(
                "/v1/auth/login",
                "POST",
                {"username": "robin", "password": "wrong-password", "device_id": "test"},
            )
        try:
            self.assertEqual(raised.exception.code, 401)
        finally:
            raised.exception.close()

    def test_record_payloads_are_validated_and_kinds_are_immutable(self):
        token = self.login()
        record_id = "a85251ed-4385-43f6-adce-766daf292f54"
        status, _ = self.request(
            "/v1/records",
            "POST",
            {"id": record_id, "kind": "note", "payload": {"title": "Sicher", "text": "Gemeinsam"}},
            token,
        )
        self.assertEqual(status, 200)

        status, error = self.request_error(
            "/v1/records",
            "POST",
            {
                "id": record_id,
                "kind": "calendar",
                "payload": {
                    "title": "Falscher Typ",
                    "start_at": "2026-09-01T10:00:00Z",
                    "end_at": "2026-09-01T11:00:00Z",
                },
            },
            token,
        )
        self.assertEqual(status, 409)
        self.assertEqual(error["error"], "record_kind_conflict")

        status, error = self.request_error(
            "/v1/records",
            "POST",
            {
                "id": "4c6861d8-64cd-49a8-a96e-236b098daf74",
                "kind": "reminder",
                "payload": {
                    "title": "Test",
                    "due_at": "2026-09-01T10:00:00Z",
                    "target_id": "unbekannt",
                    "alarm_enabled": True,
                },
            },
            token,
        )
        self.assertEqual(status, 400)
        self.assertEqual(error["error"], "invalid_target")

        status, error = self.request_error(
            "/v1/records",
            "POST",
            {
                "id": "081f4795-98ae-4609-9df4-cf9a5f7b9a8d",
                "kind": "moment",
                "payload": {
                    "caption": "Kaputt",
                    "image_base64": "kein-base64!",
                    "mime_type": "image/jpeg",
                    "comments": [],
                    "reactions": [],
                },
            },
            token,
        )
        self.assertEqual(status, 400)
        self.assertEqual(error["error"], "invalid_image")

        status, error = self.request_error(
            "/v1/records",
            "POST",
            {
                "id": "01e0d696-fab9-482d-906b-8c534c05674b",
                "kind": "calendar",
                "payload": {
                    "title": "Zeitreise",
                    "start_at": "2026-09-01T12:00:00Z",
                    "end_at": "2026-09-01T11:00:00Z",
                },
            },
            token,
        )
        self.assertEqual(status, 400)
        self.assertEqual(error["error"], "invalid_calendar_range")

    def test_new_login_revokes_old_session_and_push_devices(self):
        old = self.login()
        self.request("/v1/devices", "POST", {"device_id": "test-device", "device_token": "ab" * 32, "environment": "production"}, old)
        new = self.login()
        status, _ = self.request_error("/v1/bootstrap", token=old)
        self.assertEqual(status, 401)
        self.assertEqual(self.request("/v1/bootstrap", token=new)[0], 200)
        with self.app.database.connect() as db:
            self.assertEqual(db.execute("SELECT count(*) FROM sessions WHERE user_id='robin'").fetchone()[0], 1)
            self.assertEqual(db.execute("SELECT count(*) FROM devices WHERE user_id='robin'").fetchone()[0], 0)

    def test_credentials_can_be_changed_and_admin_reset_persists(self):
        token = self.login()
        other = self.login("raphaela", "raphaela-test-password")
        status, _ = self.request("/v1/auth/credentials", "POST", {"current_password": "robin-test-password", "username": "robin-neu", "password": "a-new-strong-password"}, token)
        self.assertEqual(status, 204)
        self.assertEqual(self.request_error("/v1/bootstrap", token=token)[0], 401)
        self.assertEqual(self.request("/v1/bootstrap", token=other)[0], 200)
        new = self.login("robin-neu", "a-new-strong-password")
        saved = json.loads(self.config_path.read_text())
        self.assertTrue(saved["users"][0]["password"].startswith("scrypt$"))
        self.assertNotIn("a-new-strong-password", self.config_path.read_text())
        self.app.reset_credentials("robin", "admin-reset-password")
        self.assertEqual(self.request_error("/v1/bootstrap", token=new)[0], 401)
        self.login("robin-neu", "admin-reset-password")
        loaded = SERVER.load_config(self.config_path)
        restarted = SERVER.RJLoveApplication(loaded, self.config_path)
        try:
            self.assertTrue(restarted.password_matches(restarted.user_by_id("robin"), "admin-reset-password"))
        finally:
            restarted.close()

    def test_revoked_sharing_removes_old_health_and_location(self):
        token = self.login()
        other = self.login("raphaela", "raphaela-test-password")
        self.request("/v1/presence", "POST", {"latitude": 51, "longitude": 6, "location_sharing": True, "steps": 7000, "health_metrics": {"heart_rate": 72}}, token)
        self.request("/v1/presence", "POST", {"location_sharing": False, "battery_level": 80}, token)
        presence = self.request("/v1/bootstrap", token=other)[1]["partners"][0]["presence"]
        for key in ("steps", "health_metrics", "latitude", "longitude"):
            self.assertNotIn(key, presence)
        self.assertEqual(self.request_error("/v1/presence", "POST", {"health_metrics": {"heart_rate": "wrong"}}, token)[0], 400)

    def test_new_shared_features_and_author_ownership(self):
        import uuid
        token = self.login()
        other = self.login("raphaela", "raphaela-test-password")
        for kind, payload in [("chat", {"text": "Ich denke an dich"}), ("wish", {"title": "Meer", "completed": False}), ("milestone", {"title": "Unser Tag", "start_at": "2027-02-14T12:00:00Z"}), ("checkin", {"title": "Glücklich", "message": "💗", "text": "Bei dir"})]:
            record_id = str(uuid.uuid4())
            body = {"id": record_id, "kind": kind, "payload": payload}
            self.assertEqual(self.request("/v1/records", "POST", body, token)[0], 200)
            records = self.request("/v1/bootstrap", token=other)[1]["records"]
            self.assertTrue(any(r["id"] == record_id for r in records))
            if kind in {"chat", "checkin"}:
                self.assertEqual(self.request_error("/v1/records", "POST", body, other)[0], 403)

    def test_nearby_exchange_requires_auth_and_expires(self):
        import datetime
        token = self.login()
        other = self.login("raphaela", "raphaela-test-password")
        self.assertEqual(self.request_error("/v1/nearby")[0], 401)
        self.request("/v1/nearby", "POST", {"token": "aGVsbG8="}, token)
        self.assertEqual(self.request("/v1/nearby", token=other)[1]["token"], "aGVsbG8=")
        self.assertIsNone(self.request("/v1/nearby", token=token)[1]["token"])
        with self.app.database.connect() as db:
            db.execute("UPDATE nearby SET expires_at=?", ((SERVER.utc_now() - datetime.timedelta(seconds=1)).isoformat(),))
        self.assertIsNone(self.request("/v1/nearby", token=other)[1]["token"])
        self.request("/v1/nearby", "POST", {"token": ""}, token)

    def test_apns_registration_can_rotate_and_live_tokens_are_revoked(self):
        token = self.login()
        body = {"device_id": "test-device", "device_token": "ab" * 32, "environment": "production"}
        self.request("/v1/devices", "POST", body, token)
        body["device_token"] = "cd" * 32
        self.assertEqual(self.request("/v1/devices", "POST", body, token)[0], 204)
        self.request("/v1/live-activities", "POST", {"activity_id": "live-1", "token": "ab" * 40}, token)
        self.login()
        with self.app.database.connect() as db:
            self.assertEqual(db.execute("SELECT count(*) FROM live_activities").fetchone()[0], 0)

    def test_file_password_reset_invalidates_sessions_on_restart(self):
        token = self.login()
        changed = json.loads(self.config_path.read_text())
        changed["users"][0]["password"] = "file-reset-password"
        self.config_path.write_text(json.dumps(changed))
        restarted = SERVER.RJLoveApplication(SERVER.load_config(self.config_path), self.config_path)
        try:
            with self.assertRaises(SERVER.APIError):
                restarted.authenticate("Bearer " + token)
            self.assertTrue(restarted.password_matches(restarted.user_by_id("robin"), "file-reset-password"))
        finally:
            restarted.close()

    def test_logout_clears_remote_delivery_tokens(self):
        token = self.login()
        self.request("/v1/devices", "POST", {"device_id": "test-device", "device_token": "ab" * 32, "environment": "production"}, token)
        self.request("/v1/nearby", "POST", {"token": "aGVsbG8="}, token)
        self.request("/v1/live-activities", "POST", {"activity_id": "live-1", "token": "ab" * 40}, token)
        self.assertEqual(self.request("/v1/auth/logout", "POST", {}, token)[0], 204)
        with self.app.database.connect() as db:
            for table in ("devices", "nearby", "live_activities", "sessions"):
                self.assertEqual(db.execute(f"SELECT count(*) FROM {table}").fetchone()[0], 0)

    def upload_clip(self, token, clip_id=None, **overrides):
        import uuid, base64
        audio = b"\x00\x00\x00\x18ftypM4A \x00\x00\x00\x00M4A isom" + b"\x00" * 40
        body = {"id": clip_id or str(uuid.uuid4()), "title": "Donnerwetter", "caption": "Ein Naturtalent", "category": "Donnergrollen", "duration": 2.5, "waveform": [0.1, 0.6, 0.9, 0.2], "audio_base64": base64.b64encode(audio).decode()}
        body.update(overrides)
        return body, self.request("/v1/farts", "POST", body, token), audio

    def test_unnamed_audio_edit_versions_backups_and_ownership(self):
        import uuid, tarfile
        token = self.login(); partner = self.login("raphaela", "raphaela-test-password")
        body, (_, clip), audio = self.upload_clip(token, title="")
        self.assertEqual(clip["title"], "Ein kleines Meisterwerk")
        with self.app.database.connect() as db:
            row = db.execute("SELECT * FROM fart_clips WHERE id=?", (clip["id"],)).fetchone()
            original = self.app.media_path(row["audio_path"])
            self.assertEqual(bytes(row["audio"]), b"")
            self.assertEqual(original.read_bytes(), audio)
            self.assertIn("/media/duftpost/robin/", str(original))
        self.request("/v1/farts/" + clip["id"] + "/rating", "POST", {"overall":5,"power":4,"style":3}, partner)
        edit = dict(body, title="Geschnitten", duration=1.0, base_revision=1, edit_id=str(uuid.uuid4()))
        endpoint = "/v1/farts/" + clip["id"] + "/edit"
        self.assertEqual(self.request_error(endpoint, "POST", edit, partner)[0], 403)
        _, changed = self.request(endpoint, "POST", edit, token)
        self.assertEqual(changed["revision"], 2)
        self.assertEqual(changed["ratings"][0]["overall"], 5)
        self.assertEqual(self.request(endpoint, "POST", edit, token)[1]["revision"], 2)
        self.assertEqual(self.app.storage_usage("robin"), len(audio) * 2)
        stale = dict(edit, edit_id=str(uuid.uuid4()))
        self.assertEqual(self.request_error(endpoint, "POST", stale, token)[0], 409)
        manifest = json.loads((original.parent / "metadata.json").read_text())
        self.assertEqual(len(manifest["versions"]), 2)
        self.assertEqual(manifest["revision"], 2)
        archive = self.app.backup()
        with tarfile.open(archive) as backup:
            names = backup.getnames()
            self.assertIn("rjlove_data/rjlove.sqlite3", names)
            self.assertIn("rjapp_config.json", names)
            self.assertEqual(len([n for n in names if n.endswith(".m4a")]), 2)
        self.request("/v1/farts/" + clip["id"], "DELETE", token=token)
        self.assertFalse(original.parent.exists())
        self.assertEqual(self.app.storage_usage("robin"), 0)

    def test_legacy_blob_migrates_without_losing_ratings(self):
        import uuid
        token = self.login()
        _, (_, clip), audio = self.upload_clip(token)
        with self.app.database.connect() as db:
            row = db.execute("SELECT * FROM fart_clips WHERE id=?", (clip["id"],)).fetchone()
            self.app.media_path(row["audio_path"]).unlink()
            db.execute("UPDATE fart_clips SET audio=?,audio_path='' WHERE id=?", (audio,clip["id"]))
            db.execute("DELETE FROM audio_versions WHERE clip_id=?", (clip["id"],))
        restarted = SERVER.RJLoveApplication(self.config, self.config_path)
        try:
            with restarted.database.connect() as db:
                row = db.execute("SELECT * FROM fart_clips WHERE id=?", (clip["id"],)).fetchone()
                self.assertEqual(restarted.media_path(row["audio_path"]).read_bytes(), audio)
                self.assertEqual(row["revision"], 1)
                self.assertEqual(bytes(row["audio"]), b"")
        finally:
            restarted.close()

    def test_radio_half_duplex_ordered_audio_text_and_revocation(self):
        import uuid, base64
        token = self.login(); partner = self.login("raphaela", "raphaela-test-password")
        tx = str(uuid.uuid4())
        body = {"transmission_id": tx}
        self.assertEqual(self.request_error("/v1/radio/begin", "POST", body, token)[0], 409)
        for auth in (token, partner):
            self.assertEqual(self.request("/v1/radio/join", "POST", {}, auth)[0], 200)
        self.request("/v1/radio/begin", "POST", body, token)
        self.assertEqual(self.request_error("/v1/radio/begin", "POST", {"transmission_id":str(uuid.uuid4())}, partner)[0], 409)
        audio = base64.b64encode(b"\x00\x00\x00\x18ftypM4A " + b"\x00" * 40).decode()
        chunk = dict(body, chunk_index=0, audio_base64=audio)
        self.assertEqual(self.request_error("/v1/radio/audio", "POST", dict(chunk, chunk_index=1), token)[0], 409)
        for _ in range(2):
            self.assertEqual(self.request("/v1/radio/audio", "POST", chunk, token)[0], 200)
        feed = self.request("/v1/radio/feed?after=0", token=partner)[1]
        self.assertEqual(len(feed["events"]), 1)
        self.assertEqual(feed["events"][0]["audio_base64"], audio)
        self.assertEqual(feed["speaker_id"], "robin")
        self.request("/v1/radio/end", "POST", dict(body,chunk_index=1), token)
        self.request("/v1/radio/text", "POST", {"transmission_id":str(uuid.uuid4()),"text":"Ich liebe dich"}, partner)
        feed = self.request("/v1/radio/feed?after=0", token=token)[1]
        self.assertEqual(feed["events"][0]["text"], "Ich liebe dich")
        self.request("/v1/auth/logout", "POST", {}, partner)
        with self.app.database.connect() as db:
            self.assertIsNone(db.execute("SELECT * FROM radio_members WHERE user_id='raphaela'").fetchone())
        self.assertEqual(self.request_error("/v1/radio/feed?after=0", token=partner)[0], 401)

    def test_radio_native_push_headers_and_short_term_retention(self):
        import uuid, datetime, types
        from unittest.mock import patch
        token = self.login(); partner = self.login("raphaela", "raphaela-test-password")
        self.request("/v1/radio/join", "POST", {"token":"ab" * 32, "environment":"production"}, partner)
        self.app.config["apns"]["enabled"] = True
        with patch.object(self.app.apns, "provider_token", return_value="test-jwt"), patch.object(SERVER.subprocess, "run", return_value=types.SimpleNamespace(returncode=0,stdout=b"200")) as send, patch.object(SERVER.threading, "Thread", side_effect=lambda target, daemon: types.SimpleNamespace(start=target)):
            self.app.push_radio("robin", 42)
            args, kwargs = send.call_args
            command = args[0]
            self.assertIn("apns-push-type: pushtotalk", command)
            self.assertIn("apns-topic: eu.rjuhas.rjlove.voip-ptt", command)
            self.assertIn("apns-expiration: 0", command)
            payload = json.loads(kwargs["input"])
            self.assertEqual(payload["sequence"], 42)
            self.assertNotIn("audio", payload)
        self.app.config["apns"]["enabled"] = False
        old = (SERVER.utc_now() - datetime.timedelta(minutes=11)).isoformat().replace("+00:00", "Z")
        with self.app.database.connect() as db:
            db.execute("INSERT INTO radio_events(transmission_id,chunk_index,user_id,kind,text,created_at) VALUES(?,0,'robin','text','old',?)", (str(uuid.uuid4()),old))
        self.assertEqual(self.request("/v1/radio/feed?after=0", token=partner)[1]["events"], [])
        self.app.cleanup()
        with self.app.database.connect() as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM radio_events").fetchone()[0], 0)

    def test_private_audio_upload_roundtrip_and_metadata_only_bootstrap(self):
        token = self.login(); partner = self.login("raphaela", "raphaela-test-password")
        body, (status, clip), audio = self.upload_clip(token)
        self.assertEqual(status, 200)
        self.assertEqual(clip["owner_id"], "robin")
        self.assertNotIn("audio_base64", clip)
        snapshot = self.request("/v1/bootstrap", token=partner)[1]
        self.assertEqual(snapshot["farts"][0]["id"], clip["id"])
        self.assertNotIn("audio", snapshot["farts"][0])
        self.assertEqual(snapshot["features"]["audio_studio_enabled"], True)
        self.assertEqual(snapshot["storage_used_bytes"], 0)
        self.assertEqual(self.app.storage_usage("robin"), len(audio))
        self.assertEqual(self.request_error("/v1/farts/" + clip["id"] + "/audio")[0], 401)
        req = urllib.request.Request(self.base + "/v1/farts/" + clip["id"] + "/audio", headers={"Authorization":"Bearer " + partner})
        with urllib.request.urlopen(req) as response:
            self.assertEqual(response.headers["Content-Type"], "audio/mp4")
            self.assertEqual(response.headers["Cache-Control"], "no-store")
            self.assertEqual(response.read(), audio)
        self.assertEqual(self.request("/v1/farts", "POST", body, token)[0], 200)
        self.assertEqual(len(self.app.list_farts()), 1)

    def test_partner_rating_reaction_and_owner_only_audio_deletion(self):
        token = self.login(); partner = self.login("raphaela", "raphaela-test-password")
        _, (_, clip), _ = self.upload_clip(token)
        path = "/v1/farts/" + clip["id"]
        score = {"overall":5,"power":4,"style":5,"comment":"Ein echtes Meisterwerk"}
        self.assertEqual(self.request_error(path+"/rating", "POST", score, token)[0], 403)
        self.assertEqual(self.request(path+"/rating", "POST", score, partner)[1]["ratings"][0]["overall"], 5)
        score["overall"] = 3
        rated = self.request(path+"/rating", "POST", score, partner)[1]
        self.assertEqual(len(rated["ratings"]), 1)
        self.assertEqual(rated["ratings"][0]["overall"], 3)
        reacted = self.request(path+"/reaction", "POST", {"emoji":"😂"}, partner)[1]
        self.assertEqual(len(reacted["reactions"]), 1)
        reacted = self.request(path+"/reaction", "POST", {"emoji":"😂"}, partner)[1]
        self.assertEqual(reacted["reactions"], [])
        self.assertEqual(self.request_error(path,"DELETE",token=partner)[0],403)
        self.assertEqual(self.request(path,"DELETE",token=token)[0],204)
        self.assertEqual(self.request_error(path+"/audio",token=partner)[0],404)
        self.assertEqual(self.app.storage_usage("robin"),0)
        with self.app.database.connect() as db:
            self.assertEqual(db.execute("SELECT count(*) FROM fart_ratings").fetchone()[0],0)

    def test_audio_and_rating_validation(self):
        import base64, uuid
        token = self.login(); partner = self.login("raphaela", "raphaela-test-password")
        body, (_, clip), _ = self.upload_clip(token)
        for change in [{"audio_base64":"invalid!"}, {"audio_base64":base64.b64encode(b"not an audio file at all").decode()}, {"duration":61}, {"duration":False}, {"waveform":[-1]}, {"waveform":[True]}, {"waveform":[]}, {"category":"unknown"}]:
            changed = dict(body, id=str(uuid.uuid4()), **change)
            self.assertEqual(self.request_error("/v1/farts","POST",changed,token)[0],400)
        for value in [0,6,True,"5"]:
            self.assertEqual(self.request_error("/v1/farts/"+clip["id"]+"/rating","POST",{"overall":value,"power":3,"style":3},partner)[0],400)
        self.assertEqual(self.request_error("/v1/farts/"+clip["id"]+"/reaction","POST",{"emoji":"invalid"},partner)[0],400)

    def test_audio_storage_quota_is_enforced(self):
        token = self.login()
        self.config["users"][0]["storage_limit_mb"] = 1
        self.upload_clip(token)
        self.assertGreater(self.app.storage_usage("robin"),0)
        import base64,uuid
        body, _, _ = self.upload_clip(token)
        audio = b"\x00\x00\x00\x18ftypM4A " + b"\x00" * (1024*1024)
        body.update(id=str(uuid.uuid4()),audio_base64=base64.b64encode(audio).decode())
        self.assertEqual(self.request_error("/v1/farts","POST",body,token)[0],507)

    def test_coupons_are_redeemable_without_rewriting_gift(self):
        import uuid
        token = self.login(); partner = self.login("raphaela", "raphaela-test-password")
        body = {"id":str(uuid.uuid4()), "kind":"coupon", "payload":{"title":"Frühstück", "text":"Mit Liebe", "target_id":"raphaela", "completed":False}}
        self.assertEqual(self.request("/v1/records","POST",body,token)[0],200)
        body["payload"]["completed"] = True
        self.assertEqual(self.request("/v1/records","POST",body,partner)[1]["payload"]["completed"],True)
        body["payload"]["title"] = "Fremder Text"
        self.assertEqual(self.request_error("/v1/records","POST",body,partner)[0],403)
        body = {"id":str(uuid.uuid4()),"kind":"gratitude","payload":{"title":"Heute mag ich an dir", "text":"Deinen Humor"}}
        self.assertEqual(self.request("/v1/records","POST",body,token)[0],200)
        self.assertEqual(self.request_error("/v1/records","POST",body,partner)[0],403)


if __name__ == "__main__":
    unittest.main()
