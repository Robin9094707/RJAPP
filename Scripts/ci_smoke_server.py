#!/usr/bin/env python3
"""CI only: runs the real server on 127.0.0.1:8787 with a throwaway data folder and a session for
the token the Debug app uses with --ui-test-server, so the simulator launch test exercises the
authenticated start path (sync, presence upload, heartbeat, telemetry) against server 10.0."""
import datetime as dt
import hashlib
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Backend"))
import rj_love_server as server  # noqa: E402

root = Path(tempfile.mkdtemp(prefix="rj-smoke-"))
config = server.default_config()
config["server"].update(host="127.0.0.1", port=8787, data_directory=str(root / "data"))
for index, user in enumerate(config["users"]):
    user["password"] = f"ci-smoke-password-{index}"
app = server.RJLoveApplication(config, root / "config.json")
now = dt.datetime.now(dt.timezone.utc)
with app.database.connect() as db:
    for token, user in (("ui-test-token", config["users"][0]["id"]), ("ui-test-partner", config["users"][1]["id"])):
        db.execute(
            "INSERT OR REPLACE INTO sessions(token_hash,user_id,device_id,created_at,expires_at,last_seen_at) VALUES(?,?,?,?,?,?)",
            (hashlib.sha256(token.encode()).hexdigest(), user, "ci-" + user, now.isoformat(),
             (now + dt.timedelta(days=1)).isoformat(), now.isoformat()))
print("RJ smoke server on http://127.0.0.1:8787", flush=True)
server.build_server(app).serve_forever()
