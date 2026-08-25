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


if __name__ == "__main__":
    unittest.main()
