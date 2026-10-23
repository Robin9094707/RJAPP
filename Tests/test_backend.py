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

    def request(self, path, method="GET", body=None, token=None, version=SERVER.APP_VERSION, protocol=SERVER.PROTOCOL_VERSION):
        encoded = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(self.base + path, data=encoded, method=method)
        request.add_header("Accept", "application/json")
        if version is not None: request.add_header("X-RJ-App-Version", version)
        if protocol is not None: request.add_header("X-RJ-Protocol", str(protocol))
        if body is not None:
            request.add_header("Content-Type", "application/json")
        if token:
            request.add_header("Authorization", f"Bearer {token}")
        with urllib.request.urlopen(request, timeout=5) as response:
            raw = response.read()
            return response.status, json.loads(raw) if raw else None

    def test_status_expiry_quiet_and_telemetry_independence(self):
        import datetime
        token=self.login()
        partner=self.login("raphaela","raphaela-test-password")
        deadline=(SERVER.utc_now()+datetime.timedelta(hours=2)).isoformat()
        body={"status_message":"😴 Schlafe gerade","status_expires_at":deadline,"dnd_until":deadline}
        self.assertEqual(self.request("/v1/status","POST",body,token)[0],204)
        self.request("/v1/presence","POST",{"battery_level":65,"status_message":"old telemetry"},token)
        status=self.request("/v1/bootstrap",token=partner)[1]["partners"][0]["presence"]
        self.assertEqual(status["status_message"],body["status_message"])
        self.assertEqual(status["battery_level"],65)
        self.app.apns.send_to_user=lambda *args: self.fail("Quiet status must suppress normal push")
        self.app.send_ntfy=lambda *args: self.fail("Quiet status must suppress ntfy")
        self.app.create_event("robin","thought","Hello","Quiet")
        body["status_expires_at"]="2000-01-01T00:00:00Z"
        body["dnd_until"]=body["status_expires_at"]
        self.request("/v1/status","POST",body,token)
        status=self.request("/v1/bootstrap",token=partner)[1]["partners"][0]["presence"]
        self.assertEqual(status["status_message"],"")
        self.assertEqual(status["dnd_until"],"")
        with self.assertRaises(urllib.error.HTTPError) as failure:
            self.request("/v1/status","POST",{"status_message":"x","dnd_until":(SERVER.utc_now()+datetime.timedelta(hours=9)).isoformat()},token)
        self.assertEqual(failure.exception.code,400)

    def test_photo_coordinates_and_old_app_update_gate(self):
        import uuid
        payload={"asset_ids":[str(uuid.uuid4())],"media_kind":"image","latitude":51.43,"longitude":6.76}
        for kind in ("moment","instant"):
            self.assertEqual(self.app.validate_record_payload(kind,payload)["latitude"],51.43)
            legacy={k:v for k,v in payload.items() if k not in {"latitude","longitude"}}
            self.assertNotIn("latitude",self.app.validate_record_payload(kind,legacy))
            for bad in (True,91,float("nan"),None):
                with self.assertRaises(SERVER.APIError):self.app.validate_record_payload(kind,payload|{"latitude":bad})
        with self.assertRaises(urllib.error.HTTPError) as failure:
            self.request("/v1/bootstrap",version="3.1.0")
        self.assertEqual(failure.exception.code,426)
        self.assertEqual(json.loads(failure.exception.read())["compatibility"]["minimum_app_version"],SERVER.MINIMUM_APP_VERSION)

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

    def test_extended_health_sleep_roundtrip_validation_and_revocation(self):
        import copy
        token=self.login()
        partner=self.login("raphaela","raphaela-test-password")
        night={"start_at":"2026-10-22T22:00:00Z","end_at":"2026-10-23T06:00:00Z","total_minutes":450,"rem_minutes":90,"core_minutes":270,"deep_minutes":90,"awake_minutes":30,"unspecified_minutes":0,"wake_count":2,"source":"Apple Watch"}
        summary={"algorithm":"rj_sleep_v2","night":night,"segments":[{"stage":"core","start_at":night["start_at"],"end_at":"2026-10-22T23:00:00Z"}],"history":[],"duration_points":46.875,"baseline_nights":0,"target_minutes":480}
        body={"sleep_summary":summary,"sleep_minutes":450,"health_metrics":{"wrist_temperature_c":36.2,"vo2_max":42,"systolic_mmhg":120},"health_metric_dates":{"vo2_max":"2026-10-21T10:00:00Z"},"motion":"Zu Fuß","motion_confidence":"hoch","motion_updated_at":"2026-10-23T10:00:00Z"}
        self.assertEqual(self.request("/v1/presence","POST",body,token)[0],200)
        shared=self.request("/v1/bootstrap",token=partner)[1]["partners"][0]["presence"]
        for key in body:self.assertEqual(shared[key],body[key])
        for edit in (lambda x:x.update(score=98),lambda x:x["night"].update(rem_minutes=1000),lambda x:x["segments"].append(dict(x["segments"][0])),lambda x:x.update(baseline_nights=True)):
            invalid=copy.deepcopy(summary);edit(invalid)
            self.assertEqual(self.request_error("/v1/presence","POST",{"sleep_summary":invalid},token)[0],400)
        self.assertEqual(self.request_error("/v1/presence","POST",{"health_metrics":{"vo2_max":42},"health_metric_dates":{"vo2_max":"invalid"}},token)[0],400)
        self.request("/v1/presence","POST",{"battery_level":80},token)
        shared=self.request("/v1/bootstrap",token=partner)[1]["partners"][0]["presence"]
        for key in body:self.assertNotIn(key,shared)

    def test_old_nearby_stop_does_not_revoke_new_search(self):
        token=self.login()
        partner=self.login("raphaela","raphaela-test-password")
        old,new="b2xk","bmV3"
        for value in (old,new):self.request("/v1/nearby","POST",{"token":value},token)
        self.request("/v1/nearby","POST",{"token":"","expected_token":old},token)
        self.assertEqual(self.request("/v1/nearby",token=partner)[1]["token"],new)
        self.request("/v1/nearby","POST",{"token":"","expected_token":new},token)
        self.assertIsNone(self.request("/v1/nearby",token=partner)[1]["token"])

    def test_ritual_unique_daily_owner_and_preserved_history(self):
        import uuid
        token=self.login();partner=self.login("raphaela","raphaela-test-password")
        payload={"title":"Drei kleine Dinge","text":"Unser Spaziergang","message":"Danke fürs Zuhören","notes":"Auf morgen","day":"2026-10-23","start_at":"2026-10-22T22:00:00Z"}
        record={"id":str(uuid.uuid4()),"kind":"ritual","payload":payload}
        self.assertEqual(self.request("/v1/records","POST",record,token)[0],200)
        self.assertEqual(self.request_error("/v1/records","POST",record,partner)[0],403)
        self.assertEqual(self.request_error("/v1/records/"+record["id"],"DELETE",token=partner)[0],403)
        duplicate={**record,"id":str(uuid.uuid4())}
        self.assertEqual(self.request_error("/v1/records","POST",duplicate,token)[0],409)
        self.assertEqual(self.request("/v1/records","POST",duplicate,partner)[0],200)
        record["payload"]={**payload,"text":"Unser Abend"}
        self.assertEqual(self.request("/v1/records","POST",record,token)[1]["payload"]["text"],"Unser Abend")
        for day in ("2026-02-30","20261023",None):
            bad={**record,"id":str(uuid.uuid4()),"payload":{**payload,"day":day}}
            self.assertEqual(self.request_error("/v1/records","POST",bad,token)[0],400)
        records=self.request("/v1/records/archive?kind=ritual",token=partner)[1]["records"]
        self.assertEqual(len(records),2)

    def test_daily_journal_boundaries_capture_dates_pagination_and_auth(self):
        import uuid,urllib.parse
        token=self.login()
        # A 25-hour local calendar day (Europe/Berlin DST change).
        params={"start":"2026-10-24T22:00:00Z","end":"2026-10-25T23:00:00Z"}
        path="/v1/journal?"+urllib.parse.urlencode(params)
        self.assertEqual(self.request_error(path)[0],401)
        photo_id=str(uuid.uuid4())
        photo={"id":photo_id,"kind":"moment","payload":{"caption":"Historischer Moment","image_base64":"YQ==","mime_type":"image/jpeg","captured_at":"2026-10-25T22:59:59Z"}}
        self.request("/v1/records","POST",photo,token)
        with self.app.database.connect() as db:
            for index in range(202):
                stamp="2026-10-24T22:00:00Z" if index<201 else params["end"]
                db.execute("INSERT INTO records VALUES(?,?,?,?,?,?,?,NULL)",(str(uuid.uuid4()),"chat","robin",json.dumps({"text":str(index)}),10,stamp,stamp))
            db.execute("INSERT INTO thought_events VALUES(?,?,?,?)",(str(uuid.uuid4()),"robin","2026-10-25T22:50:00Z","2026-10-26T00:00:00Z"))
        first=self.request(path,token=token)[1]
        self.assertEqual(first["counts"],{"chat":201,"moment":1,"farts":0})
        self.assertEqual(first["hearts"],{"robin":1})
        self.assertEqual(len(first["records"]),200);self.assertTrue(first["has_more"])
        second=self.request(path+"&offset=200",token=token)[1]
        self.assertEqual(len(second["records"]),2);self.assertFalse(second["has_more"])
        self.assertIn(photo_id,{r["id"] for r in first["records"]+second["records"]})
        self.request("/v1/records/"+photo_id,"DELETE",token=token)
        self.assertNotIn("moment",self.request(path,token=token)[1]["counts"])
        invalid="/v1/journal?"+urllib.parse.urlencode({**params,"end":"2026-11-25T23:00:00Z"})
        self.assertEqual(self.request_error(invalid,token=token)[0],400)

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

    def test_comments_on_existing_audio_are_idempotent_private_and_preserved(self):
        import uuid
        robin=self.login();raphaela=self.login("raphaela","raphaela-test-password")
        body,(_,clip),audio=self.upload_clip(robin)
        endpoint="/v1/farts/"+clip["id"]+"/comments"
        self.assertEqual(self.request(endpoint,token=raphaela)[1]["comments"],[])
        comment={"id":str(uuid.uuid4()),"text":"Auch beim alten Meisterwerk: 😂"}
        self.assertEqual(self.request(endpoint,"POST",comment,raphaela)[0],201)
        self.assertEqual(self.request(endpoint,"POST",comment,raphaela)[0],200)
        self.request(endpoint,"POST",{"id":str(uuid.uuid4()),"text":"Danke Schatzi"},robin)
        self.assertEqual(self.app.fart_clip(clip["id"])["comment_count"],2)
        self.assertEqual(self.request_error(endpoint+"/"+comment["id"],"DELETE",token=robin)[0],403)
        self.assertEqual(self.request_error(endpoint)[0],401)
        edit=dict(body,title="Neuer Titel",base_revision=1,edit_id=str(uuid.uuid4()))
        self.request("/v1/farts/"+clip["id"]+"/edit","POST",edit,robin)
        self.assertEqual(len(self.request(endpoint,token=robin)[1]["comments"]),2)
        self.request(endpoint+"/"+comment["id"],"DELETE",token=raphaela)
        self.assertEqual(self.app.fart_clip(clip["id"])["comment_count"],1)
        self.request("/v1/farts/"+clip["id"],"DELETE",token=robin)
        with self.app.database.connect() as db:self.assertEqual(db.execute("SELECT COUNT(*) FROM fart_comments").fetchone()[0],0)

    def test_activity_distinguishes_open_foreground_and_background(self):
        token=self.login()
        self.request("/v1/open","POST",{},token)
        opened=self.app.last_opened()["robin"]
        self.request("/v1/presence","POST",{"battery_level":52,"app_state":"foreground"},token)
        foreground=self.app.activity_history()["robin"]["foreground_at"]
        self.request("/v1/activity","POST",{"mode":"inactive"},token)
        self.request("/v1/activity","POST",{"mode":"background","source":"iOS-Hintergrundaktualisierung"},token)
        history=self.app.activity_history()["robin"]
        self.assertEqual(history["foreground_at"],foreground)
        self.assertEqual(self.app.last_opened()["robin"],opened)
        self.assertIsNotNone(history["background_sync_at"])
        self.assertIsNotNone(history["foreground_ended_at"])
        self.assertEqual(self.app.bootstrap("raphaela")["activity"]["robin"],history)
        self.assertEqual(self.request_error("/v1/activity","POST",{"mode":[]},token)[0],400)

    def test_anniversary_roundtrip_and_live_token_removal_is_scoped(self):
        import uuid
        token=self.login()
        payload={"title":"Unser Jahrestag","start_at":"2026-05-03T00:00:00+02:00","countdown_type":"anniversary","recurrence":"none"}
        saved=self.request("/v1/records","POST",{"id":str(uuid.uuid4()),"kind":"milestone","payload":payload},token)[1]
        self.assertEqual(saved["payload"]["recurrence"],"yearly")
        self.assertEqual(saved["payload"]["countdown_type"],"anniversary")
        for activity in ("old","new"):
            self.request("/v1/live-activities","POST",{"activity_id":activity,"token":"ab"*32,"environment":"production"},token)
        self.request("/v1/live-activities","POST",{"activity_id":"old","token":"","environment":"production"},token)
        with self.app.database.connect() as db:self.assertEqual(db.execute("SELECT id FROM live_activities").fetchone()[0],"new")

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

    def test_obsolete_walkie_talkie_is_removed(self):
        token=self.login()
        for path in ["/v1/radio/join","/v1/radio/begin","/v1/radio/text"]:
            self.assertEqual(self.request_error(path,"POST",{},token)[0],410)
        self.assertEqual(self.request_error("/v1/radio/feed",token=token)[0],410)
        self.assertFalse(self.app.bootstrap("robin")["features"]["radio_enabled"])

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
        req = urllib.request.Request(self.base + "/v1/farts/" + clip["id"] + "/audio", headers={"Authorization":"Bearer " + partner,"X-RJ-App-Version":SERVER.APP_VERSION,"X-RJ-Protocol":str(SERVER.PROTOCOL_VERSION)})
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

    def test_background_wake_receipts_are_target_only_and_retryable(self):
        import datetime, uuid
        robin = self.login(); raphaela = self.login("raphaela", "raphaela-test-password")
        due = (SERVER.utc_now() + datetime.timedelta(hours=8)).isoformat()
        command = self.request("/v1/commands", "POST", {"target_id":"raphaela", "message":"Guten Morgen", "due_at":due}, robin)[1]
        self.request("/v1/records", "POST", {"id":str(uuid.uuid4()),"kind":"note","payload":{"title":"Private Medien","text":"Kein Hintergrunddownload"}}, robin)
        self.assertEqual(self.request_error("/v1/background")[0], 401)
        snapshot = self.request("/v1/background", token=raphaela)[1]
        self.assertEqual(set(snapshot), {"user_id","sender_name","commands","reminders"})
        self.assertEqual(snapshot["commands"][0]["id"], command["id"])
        self.assertEqual(self.request("/v1/background", token=robin)[1]["commands"], [])
        endpoint = "/v1/commands/" + command["id"] + "/receipt"
        self.assertEqual(self.request_error(endpoint,"POST",{"status":"scheduled"},robin)[0],404)
        self.assertEqual(self.request_error(endpoint,"POST",{"status":"invented"},raphaela)[0],400)
        self.request(endpoint,"POST",{"status":"failed","reason":"AlarmKit nicht freigegeben"},raphaela)
        self.assertEqual(len(self.request("/v1/background",token=raphaela)[1]["commands"]),1)
        self.assertEqual(self.request("/v1/commands/delivery",token=robin)[1]["deliveries"][0]["status"],"failed")
        self.request(endpoint,"POST",{"status":"scheduled","reason":"AlarmKit bestätigt"},raphaela)
        self.request(endpoint,"POST",{"status":"failed","reason":"Verspätete Antwort"},raphaela)
        self.assertEqual(self.request("/v1/background",token=raphaela)[1]["commands"],[])
        delivery = self.request("/v1/commands/delivery",token=robin)[1]["deliveries"][0]
        self.assertEqual(delivery["status"],"scheduled")
        self.assertEqual(delivery["reason"],"AlarmKit bestätigt")
        self.assertEqual(self.request("/v1/commands/delivery",token=raphaela)[1]["deliveries"],[])

    def test_push_diagnostics_and_signing_topic_mismatch(self):
        token = self.login()
        readiness = self.request("/v1/push/status",token=token)[1]
        self.assertFalse(readiness["ready"])
        self.assertTrue(any("Zugangsdaten" in reason for reason in readiness["issues"]))
        self.assertEqual(self.request_error("/v1/push/test","POST",{},token)[0],409)
        body = {"device_id":"test-device","device_token":"ab"*32,"environment":"production","bundle_id":"com.zello.client"}
        self.assertEqual(self.request_error("/v1/devices","POST",body,token)[0],422)
        body["bundle_id"] = self.config["apns"]["bundle_id"]
        self.assertEqual(self.request("/v1/devices","POST",body,token)[0],204)
        self.config["apns"].update(enabled=True,team_id="ABCDEFGHIJ")
        body["team_id"] = "OTHERTEAM1X"
        self.assertEqual(self.request_error("/v1/devices","POST",body,token)[0],422)
        self.config["apns"]["enabled"] = False

    def test_apns_rejection_preserves_topic_mismatch_token_and_reports_reason(self):
        import types
        from unittest.mock import patch
        token = self.login()
        self.request("/v1/devices","POST",{"device_id":"test-device","device_token":"ab"*32,"environment":"sandbox"},token)
        self.config["apns"]["enabled"] = True
        with patch.object(self.app.apns,"provider_token",return_value="test-jwt"), patch.object(SERVER.subprocess,"run",return_value=types.SimpleNamespace(returncode=0,stdout=b'{"reason":"DeviceTokenNotForTopic"}\n400',stderr=b"")) as send:
            self.app.apns._send_worker("robin", {"id":"event","kind":"wake_request","title":"Weckruf","body":"Hallo","payload":{"command_id":"wake"}})
            args, kwargs = send.call_args
            self.assertIn("apns-push-type: alert",args[0])
            self.assertIn("https://api.sandbox.push.apple.com/3/device/"+"ab"*32,args[0])
            payload = json.loads(kwargs["input"])
            self.assertEqual(payload["aps"]["content-available"],1)
            self.assertEqual(payload["aps"]["category"],"RJ_WAKE")
            self.assertEqual(payload["rj_command_id"],"wake")
        self.config["apns"]["enabled"] = False
        readiness = self.request("/v1/push/status",token=token)[1]
        self.assertIn("DeviceTokenNotForTopic",readiness["attempts"][0]["reason"])
        self.assertEqual(readiness["registered_devices"],1)

    def test_client_server_update_gate_runs_before_login_and_writes(self):
        for version,protocol in [(None,None),("2.3.0",3),("2.4.0",99)]:
            with self.assertRaises(urllib.error.HTTPError) as raised:
                self.request("/v1/auth/login","POST",{"username":"robin","password":"robin-test-password","device_id":"test-device"},version=version,protocol=protocol)
            error = raised.exception
            try:
                self.assertEqual(error.code,426)
                body=json.loads(error.read())
                self.assertEqual(body["compatibility"]["minimum_app_version"],SERVER.MINIMUM_APP_VERSION)
            finally:error.close()
        self.assertEqual(self.request("/health",version=None,protocol=None)[1]["minimum_protocol"],SERVER.PROTOCOL_VERSION)
        self.login()
        self.assertEqual(self.request("/health",version="99.0.0",protocol=99)[0],200)

    def test_complete_archive_paginates_past_one_hundred_and_orders_equal_times(self):
        import uuid
        token=self.login()
        _,(_,clip),_=self.upload_clip(token)
        with self.app.database.connect() as db:
            row=dict(db.execute("SELECT * FROM fart_clips WHERE id=?",(clip["id"],)).fetchone())
            for _ in range(109):
                row["id"]=str(uuid.uuid4())
                columns=list(row)
                db.execute("INSERT INTO fart_clips ("+",".join(columns)+") VALUES ("+",".join("?" for _ in columns)+")",tuple(row[c] for c in columns))
        first=self.request("/v1/farts?limit=70",token=token)[1]
        second=self.request("/v1/farts?limit=70&offset="+str(first["next_offset"])+"&before="+urllib.parse.quote(first["before"]),token=token)[1]
        self.assertTrue(first["has_more"]);self.assertFalse(second["has_more"])
        self.assertEqual(len({c["id"] for c in first["clips"]+second["clips"]}),110)
        self.assertEqual(self.request_error("/v1/farts?offset=wrong",token=token)[0],400)
        self.assertNotIn("audio_base64",first["clips"][0])

    def test_capture_location_date_trim_and_owner_only_location_removal(self):
        import datetime,uuid
        token=self.login();partner=self.login("raphaela","raphaela-test-password")
        recorded=(SERVER.utc_now()-datetime.timedelta(days=35)).isoformat()
        point={"latitude":51.43,"longitude":6.76,"accuracy":20,"captured_at":recorded}
        body,(_,clip),_=self.upload_clip(token,recorded_at=recorded,location=point,situation="unterwegs")
        self.assertEqual(clip["location"],point);self.assertEqual(clip["recorded_at"],recorded)
        edit=dict(body,base_revision=1,edit_id=str(uuid.uuid4()),location=None,recorded_at=SERVER.iso_now())
        changed=self.request("/v1/farts/"+clip["id"]+"/edit","POST",edit,token)[1]
        self.assertEqual(changed["recorded_at"],recorded);self.assertEqual(changed["location"],point)
        endpoint="/v1/farts/"+clip["id"]+"/location"
        self.assertEqual(self.request_error(endpoint,"DELETE",token=partner)[0],403)
        removed=self.request(endpoint,"DELETE",token=token)[1]
        self.assertIsNone(removed["location"])
        with self.app.database.connect() as db:
            row=db.execute("SELECT * FROM fart_clips WHERE id=?",(clip["id"],)).fetchone()
            manifest=json.loads((self.app.clip_directory(row)/"metadata.json").read_text())
            self.assertIsNone(manifest.get("location"))
        for invalid in [dict(point,latitude=91),dict(point,longitude=True),dict(point,accuracy=-1),dict(point,captured_at=SERVER.iso_now())]:
            with self.assertRaises(urllib.error.HTTPError) as raised:self.upload_clip(token,location=invalid,recorded_at=recorded)
            raised.exception.close()

    def test_automatic_push_discovers_local_key_and_preserves_missing_key_state(self):
        from unittest.mock import patch
        folder=self.config_path.parent/"push";folder.mkdir()
        self.app.configure_push_automatically(force=True)
        self.assertFalse(self.app.apns.enabled)
        self.assertIn("Warte",self.app.push_setup_status)
        key=folder/"AuthKey_ABCDEFGHIJ.p8";key.write_text("test-only-not-a-real-key")
        (folder/"credentials.json").write_text(json.dumps({"team_id":"0123456789"}))
        with patch.object(self.app.apns,"issues",return_value=[]),patch.object(self.app.apns,"provider_token",return_value="test-provider-token"):
            self.app.configure_push_automatically(force=True)
        saved=json.loads(self.config_path.read_text())["apns"]
        self.assertTrue(saved["enabled"]);self.assertEqual(saved["key_id"],"ABCDEFGHIJ")
        self.assertEqual(saved["team_id"],"0123456789");self.assertEqual(Path(saved["private_key_file"]).resolve(),key.resolve())
        self.assertNotIn("test-only",self.config_path.read_text())
        self.config["apns"]["enabled"]=False

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

    def upload_asset(self,token,data=b"test-media",mime="image/jpeg"):
        import hashlib
        body={"filename":"test.jpg","mime_type":mime,"size_bytes":len(data),"sha256":hashlib.sha256(data).hexdigest()}
        asset=self.request("/v1/assets","POST",body,token)[1]["id"]
        self.raw_asset_request("/v1/assets/"+asset,"PUT",token,data)
        return asset

    def raw_asset_request(self,path,method,token,data=None,extra=None):
        headers={"X-RJ-App-Version":SERVER.APP_VERSION,"X-RJ-Protocol":str(SERVER.PROTOCOL_VERSION)}
        if token:headers["Authorization"]="Bearer "+token
        headers.update(extra or {})
        req=urllib.request.Request(self.base+path,data=data,headers=headers,method=method)
        with urllib.request.urlopen(req,timeout=5) as response:return response.status,response.read()

    def test_media_upload_integrity_share_recall_and_owner_access(self):
        import uuid
        token=self.login();partner=self.login("raphaela","raphaela-test-password")
        asset=self.upload_asset(token,b"private-photo")
        self.assertEqual(self.raw_asset_request("/v1/assets/"+asset,"GET",token)[1],b"private-photo")
        self.assertEqual(self.request_error("/v1/assets/"+asset,token=partner)[0],404)
        record={"id":str(uuid.uuid4()),"kind":"chat","payload":{"asset_ids":[asset],"media_kind":"image","text":"Hallo"}}
        self.assertEqual(self.request("/v1/records","POST",record,token)[0],200)
        self.assertEqual(self.raw_asset_request("/v1/assets/"+asset,"GET",partner,extra={"Range":"bytes=1-3"}), (206,b"riv"))
        self.assertEqual(self.request_error("/v1/records/"+record["id"],"DELETE",token=partner)[0],403)
        self.assertEqual(self.request_error("/v1/assets/"+asset,"DELETE",token=token)[0],409)
        self.request("/v1/records/"+record["id"],"DELETE",token=token)
        self.assertEqual(self.request_error("/v1/assets/"+asset,token=partner)[0],404)
        self.assertIn(record["id"],self.app.bootstrap("robin")["deleted_record_ids"])

    def test_unfinished_and_foreign_assets_cannot_be_attached(self):
        import uuid,hashlib
        token=self.login();partner=self.login("raphaela","raphaela-test-password")
        asset=self.request("/v1/assets","POST",{"filename":"x.jpg","mime_type":"image/jpeg","size_bytes":3,"sha256":hashlib.sha256(b"abc").hexdigest()},token)[1]["id"]
        payload={"id":str(uuid.uuid4()),"kind":"moment","payload":{"asset_ids":[asset],"media_kind":"image"}}
        self.assertEqual(self.request_error("/v1/records","POST",payload,token)[0],403)
        self.raw_asset_request("/v1/assets/"+asset,"PUT",token,b"abc")
        self.assertEqual(self.request_error("/v1/records","POST",payload,partner)[0],403)
        self.assertEqual(self.request("/v1/records","POST",payload,token)[0],200)
        self.assertEqual(self.app.storage_usage("robin")>3,True)

    def test_corrupt_upload_and_pending_quota_reservations(self):
        import hashlib
        token=self.login();self.config["users"][0]["storage_limit_mb"]=1
        body={"filename":"x.mov","mime_type":"video/quicktime","size_bytes":700000,"sha256":hashlib.sha256(b"a"*700000).hexdigest()}
        asset=self.request("/v1/assets","POST",body,token)[1]["id"]
        self.assertEqual(self.request_error("/v1/assets","POST",body,token)[0],507)
        with self.assertRaises(urllib.error.HTTPError) as raised:self.raw_asset_request("/v1/assets/"+asset,"PUT",token,b"b"*700000)
        self.assertEqual(raised.exception.code,400);raised.exception.close()
        self.assertEqual(self.request_error("/v1/assets/"+asset,token=token)[0],404)
        self.request("/v1/assets/"+asset,"DELETE",token=token)
        self.assertEqual(self.app.storage_usage("robin"),0)

    def test_live_photo_album_and_binary_backup_survive_restart(self):
        import uuid,tarfile
        token=self.login();first=self.upload_asset(token,b"photo");second=self.upload_asset(token,b"paired-video","video/quicktime")
        album={"id":str(uuid.uuid4()),"kind":"album","payload":{"title":"Unser Sommer"}}
        self.request("/v1/records","POST",album,token)
        moment={"id":str(uuid.uuid4()),"kind":"moment","payload":{"asset_ids":[first,second],"album_id":album["id"],"media_kind":"live","captured_at":"2020-02-29T12:00:00Z"}}
        self.request("/v1/records","POST",moment,token)
        backup=self.app.backup()
        with tarfile.open(backup) as archive:self.assertTrue(any(n.endswith("original.mov") for n in archive.getnames()))
        self.request("/v1/records/"+album["id"],"DELETE",token=token)
        SERVER.Database(self.app.database.path).initialize()
        records=self.request("/v1/records/archive?kind=moment",token=token)[1]["records"]
        self.assertEqual(records[0]["payload"]["asset_ids"],[first,second])
        self.assertEqual(records[0]["payload"]["captured_at"],"2020-02-29T12:00:00Z")

    def test_photo_request_only_recipient_can_reply_once_and_recall(self):
        import uuid
        token=self.login();partner=self.login("raphaela","raphaela-test-password")
        request={"id":str(uuid.uuid4()),"kind":"photo_request","payload":{"title":"Ein Lächeln","target_id":"raphaela","completed":False}}
        self.request("/v1/records","POST",request,token)
        asset=self.upload_asset(partner,b"selfie")
        body={"asset_id":asset,"caption":"Süßefresse"}
        endpoint="/v1/photo-requests/"+request["id"]+"/reply"
        self.assertEqual(self.request_error(endpoint,"POST",body,token)[0],403)
        photo=self.request(endpoint,"POST",body,partner)[1]
        self.assertEqual(photo["owner_id"],"raphaela")
        self.assertEqual(self.request(endpoint,"POST",body,partner)[1]["id"], photo["id"])
        self.assertEqual(self.request_error("/v1/records/"+photo["id"],"DELETE",token=token)[0],403)
        self.request("/v1/records/"+photo["id"],"DELETE",token=partner)
        self.assertEqual(self.request_error("/v1/assets/"+asset,token=token)[0],404)

    def test_precise_thoughts_idempotency_receipts_and_open_times(self):
        import uuid
        token=self.login();partner=self.login("raphaela","raphaela-test-password")
        event={"id":str(uuid.uuid4()),"occurred_at":SERVER.iso_now()}
        self.request("/v1/thoughts","POST",event,token);self.request("/v1/thoughts","POST",event,token)
        history=self.request("/v1/thoughts/history",token=partner)[1]["events"]
        self.assertEqual(len(history),1);self.assertEqual(history[0]["occurred_at"],event["occurred_at"])
        snapshot=self.app.bootstrap("robin");self.assertEqual(snapshot["thoughts"]["robin"],1)
        self.request("/v1/open","POST",{},partner)
        asset=self.upload_asset(token,b"audio","audio/mp4")
        chat={"id":str(uuid.uuid4()),"kind":"chat","payload":{"asset_ids":[asset],"media_kind":"audio","autoplay":True,"urgency":0.8}}
        self.request("/v1/records","POST",chat,token)
        self.request("/v1/records/"+chat["id"]+"/opened","POST",{},partner)
        snapshot=self.app.bootstrap("robin")
        self.assertIn("raphaela",snapshot["last_opened"])
        self.assertEqual(snapshot["opened_records"][0]["record_id"],chat["id"])

    def test_annual_plans_remain_editable_by_both_and_visible_beyond_bootstrap_limit(self):
        import uuid
        token=self.login();partner=self.login("raphaela","raphaela-test-password")
        plan={"id":str(uuid.uuid4()),"kind":"calendar","payload":{"title":"Jahrestag","start_at":"2020-02-29T10:00:00Z","end_at":"2020-02-29T11:00:00Z","recurrence":"yearly","alarm_enabled":True,"reminder_sync":True,"calendar_sync":True}}
        self.request("/v1/records","POST",plan,token);plan["payload"]["title"]="Unser Tag"
        self.request("/v1/records","POST",plan,partner)
        self.assertEqual(self.app.bootstrap("robin")["records"][0]["payload"]["title"],"Unser Tag")
        plan["payload"]["recurrence"]="nonsense"
        self.assertEqual(self.request_error("/v1/records","POST",plan,token)[0],400)

    def test_home_layout_is_private_validated_and_persisted(self):
        token = self.login(); partner = self.login("raphaela", "raphaela-test-password")
        initial = self.request("/v1/preferences", token=token)[1]
        changed = {"dashboard": {"cards": [{"kind": "health", "size": "compact"}, {"kind": "instant", "size": "large"}], "theme": "ocean", "title": "Robins Startseite"}, "revision": initial["revision"]}
        saved = self.request("/v1/preferences", "POST", changed, token)[1]
        self.assertEqual(saved["revision"], 1)
        self.assertEqual(self.request("/v1/preferences", token=partner)[1]["revision"], 0)
        self.assertEqual(self.request_error("/v1/preferences", "POST", changed, token)[0], 409)
        SERVER.Database(self.app.database.path).initialize()
        self.assertEqual(self.app.bootstrap("robin")["preferences"], saved)
        self.assertNotIn("Robins Startseite", json.dumps(self.app.bootstrap("raphaela")))
        for invalid in [dict(saved, user_id="raphaela"), {"revision": 1, "dashboard": {**saved["dashboard"], "cards": [{"kind": "health", "size": "compact"}] * 2}}, {"revision": 1, "dashboard": {**saved["dashboard"], "theme": "unknown"}}]:
            self.assertEqual(self.request_error("/v1/preferences", "POST", invalid, token)[0], 400)
        self.assertEqual(self.request_error("/v1/preferences")[0], 401)

    def test_one_outgoing_photo_request_atomic_recall_and_reply(self):
        import uuid,concurrent.futures
        token=self.login();partner=self.login("raphaela","raphaela-test-password")
        def send(index):
            try:
                if index==0:return self.request("/v1/photo-requests","POST",{"id":str(uuid.uuid4()),"title":"Ein Foto"},token)
                return self.request("/v1/records","POST",{"id":str(uuid.uuid4()),"kind":"photo_request","payload":{"title":"Noch eins","target_id":"raphaela","completed":False}},token)
            except urllib.error.HTTPError as e:return e.code,json.loads(e.read())
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(send,range(2)))
        self.assertEqual(sorted(r[0] for r in results),[200,409])
        outgoing=self.request("/v1/photo-requests",token=token)[1]["outgoing"]
        self.assertIsNotNone(outgoing)
        request_id=outgoing["id"];recall="/v1/photo-requests/"+request_id+"/recall"
        self.assertEqual(self.request_error(recall,"POST",{},partner)[0],403)
        self.assertEqual(len(self.request("/v1/photo-requests",token=partner)[1]["incoming"]),1)
        self.assertEqual(self.request(recall,"POST",{},token)[0],204)
        self.assertEqual(self.request(recall,"POST",{},token)[0],204)
        self.assertIsNone(self.request("/v1/photo-requests",token=token)[1]["outgoing"])
        asset=self.upload_asset(partner,b"photo")
        self.assertEqual(self.request_error("/v1/photo-requests/"+request_id+"/reply","POST",{"asset_id":asset},partner)[0],404)
        next_request=self.request("/v1/photo-requests","POST",{"id":str(uuid.uuid4())},token)[1]
        self.request("/v1/photo-requests/"+next_request["id"]+"/reply","POST",{"asset_id":asset},partner)
        self.assertIsNone(self.request("/v1/photo-requests",token=token)[1]["outgoing"])
        self.assertEqual(self.request_error("/v1/photo-requests/"+next_request["id"]+"/recall","POST",{},token)[0],409)
        self.assertEqual(self.request("/v1/photo-requests","POST",{"id":str(uuid.uuid4())},token)[0],200)
        # The other sender has an independent slot.
        self.assertEqual(self.request("/v1/photo-requests","POST",{"id":str(uuid.uuid4())},partner)[0],200)
        self.assertEqual(self.request_error("/v1/photo-requests")[0],401)

    def test_upgrade_collapses_old_pending_photo_queue_preserving_answers(self):
        import uuid,sqlite3
        ids=[str(uuid.uuid4()) for _ in range(4)]
        with self.app.database.connect() as db:
            db.execute("DROP INDEX one_open_photo_request_per_sender")
            for index,record_id in enumerate(ids):
                payload=json.dumps({"title":"Old wish","target_id":"raphaela","completed":index==3})
                stamp=f"2026-10-23T10:00:0{index}Z"
                db.execute("INSERT INTO records VALUES(?,?,?,?,?,?,?,NULL)",(record_id,"photo_request","robin",payload,len(payload),stamp,stamp))
        SERVER.Database(self.app.database.path).initialize()
        with self.app.database.connect() as db:
            rows={r["id"]:dict(r) for r in db.execute("SELECT * FROM records")}
            self.assertIsNotNone(rows[ids[0]]["deleted_at"]);self.assertIsNotNone(rows[ids[1]]["deleted_at"])
            self.assertIsNone(rows[ids[2]]["deleted_at"]);self.assertIsNone(rows[ids[3]]["deleted_at"])
            self.assertTrue(json.loads(rows[ids[3]]["payload"])["completed"])
            with self.assertRaises(sqlite3.IntegrityError):
                db.execute("INSERT INTO records VALUES(?,?,?,?,?,?,?,NULL)",(str(uuid.uuid4()),"photo_request","robin",rows[ids[2]]["payload"],10,SERVER.iso_now(),SERVER.iso_now()))
        SERVER.Database(self.app.database.path).initialize()

    def test_photo_request_endpoint_delivers_once_and_can_be_recalled(self):
        import uuid
        token = self.login(); partner = self.login("raphaela", "raphaela-test-password")
        body = {"id": str(uuid.uuid4()), "title": "Bitte lächeln"}
        first = self.request("/v1/photo-requests", "POST", body, token)[1]
        self.assertEqual(self.request("/v1/photo-requests", "POST", body, token)[1]["id"], first["id"])
        incoming = [r for r in self.app.bootstrap("raphaela")["records"] if r["id"] == first["id"]]
        self.assertEqual(len(incoming), 1); self.assertEqual(incoming[0]["payload"]["target_id"], "raphaela")
        self.assertEqual(len([e for e in self.app.bootstrap("raphaela")["events"] if e["kind"] == "record_photo_request"]), 1)
        asset = self.upload_asset(partner, b"photo")
        endpoint = "/v1/photo-requests/" + first["id"] + "/reply"
        photo = self.request(endpoint, "POST", {"asset_id": asset, "caption": body["title"]}, partner)[1]
        self.assertEqual(photo["owner_id"], "raphaela")
        self.assertEqual(self.request(endpoint, "POST", {"asset_id": asset}, partner)[1]["id"], photo["id"])
        other_asset = self.upload_asset(partner, b"other-photo")
        self.assertEqual(self.request_error(endpoint, "POST", {"asset_id": other_asset}, partner)[0], 409)
        self.request("/v1/records/" + photo["id"], "DELETE", token=partner)
        self.assertEqual(self.request_error("/v1/assets/" + asset, token=token)[0], 404)

    def test_nearby_background_grant_is_bounded_and_logout_revokes_it(self):
        import base64
        token = self.login(); partner = self.login("raphaela", "raphaela-test-password")
        value = base64.b64encode(b"test-discovery-token").decode()
        self.request("/v1/nearby", "POST", {"token": value, "lifetime": 900}, token)
        self.assertEqual(self.request("/v1/nearby", token=partner)[1]["token"], value)
        self.assertEqual(self.request_error("/v1/nearby", "POST", {"token": value, "lifetime": 901}, token)[0], 400)
        self.request("/v1/auth/logout", "POST", {}, token)
        self.assertIsNone(self.request("/v1/nearby", token=partner)[1]["token"])

    def test_feather_feed_only_serves_validated_rj_ipa_and_token_rotates(self):
        import io,zipfile,plistlib
        token=self.login()
        memory=io.BytesIO()
        with zipfile.ZipFile(memory,"w") as z:
            z.writestr("Payload/RJ Love.app/Info.plist",plistlib.dumps({"CFBundleIdentifier":"eu.rjuhas.rjlove","CFBundleShortVersionString":"3.1.0","CFBundleVersion":"310"}))
            z.writestr("Payload/RJ Love.app/AppIcon60.png",b"fake-icon")
        asset=self.upload_asset(token,memory.getvalue(),"application/octet-stream")
        self.request("/v1/app-release","POST",{"asset_id":asset},token)
        body={"base_url":"https://liebe.example/rj"}
        feed=self.request("/v1/update-feed","POST",body,token)[1]["token"]
        source=self.request("/updates/"+feed+"/source.json",version=None,protocol=None)[1]
        version=source["apps"][0]["versions"][0]
        self.assertEqual(version["version"],"3.1.0")
        older=self.request("/v1/app-release",token=token,version="2.4.0",protocol=4)[1]
        self.assertEqual(older["release"]["version"],"3.1.0")
        with self.assertRaises(urllib.error.HTTPError) as unauthorized:
            self.request("/v1/app-release",version="2.4.0",protocol=4)
        self.assertEqual(unauthorized.exception.code,401);unauthorized.exception.close()

        self.assertTrue(version["downloadURL"].startswith("https://liebe.example/rj/updates/"))
        self.assertEqual(self.raw_asset_request("/updates/"+feed+"/latest.ipa","GET",None)[1],memory.getvalue())
        self.request("/v1/update-feed","POST",body,token)
        self.assertEqual(self.request_error("/updates/"+feed+"/source.json")[0],404)
        invalid=self.upload_asset(token,b"not-an-ipa","application/octet-stream")
        self.assertEqual(self.request_error("/v1/app-release","POST",{"asset_id":invalid},token)[0],400)


if __name__ == "__main__":
    unittest.main()
