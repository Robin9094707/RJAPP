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


if __name__ == "__main__":
    unittest.main()
