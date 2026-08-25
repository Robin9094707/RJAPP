#!/usr/bin/env python3
"""RJ Love Server — dependency-free private backend for two trusted partners.

Run with Python 3.11+:

    python3 rj_love_server.py

On the first start the server creates ``rjapp_config.json`` next to this file and
exits. Edit that file, then start the script again.  SQLite, password hashing,
sessions, rate limiting, optional TLS and optional APNs delivery are all provided
by the Python standard library (APNs additionally uses the system ``curl`` and
``openssl`` executables when enabled).
"""

from __future__ import annotations

import base64
import contextlib
import datetime as dt
import hashlib
import hmac
import json
import logging
from logging.handlers import RotatingFileHandler
import mimetypes
import os
from pathlib import Path
import secrets
import signal
import sqlite3
import ssl
import subprocess
import sys
import threading
import time
import uuid
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import parse_qs, urlparse
from zoneinfo import ZoneInfo


APP_VERSION = "1.0.0"
CONFIG_FILENAME = "rjapp_config.json"
ALLOWED_RECORD_KINDS = {"note", "reminder", "moment", "geofence", "calendar"}
ALLOWED_COMMAND_KINDS = {"wake", "love_alarm"}


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def iso_now() -> str:
    return utc_now().isoformat(timespec="milliseconds").replace("+00:00", "Z")


def parse_iso(value: str | None) -> dt.datetime | None:
    if not value:
        return None
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=dt.timezone.utc)
        return parsed.astimezone(dt.timezone.utc)
    except (ValueError, TypeError):
        return None


def json_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def safe_text(value: Any, maximum: int, *, allow_empty: bool = True) -> str:
    if not isinstance(value, str):
        raise APIError(HTTPStatus.BAD_REQUEST, "invalid_text", "Ein Textfeld ist ungültig.")
    value = value.strip()
    if not allow_empty and not value:
        raise APIError(HTTPStatus.BAD_REQUEST, "empty_text", "Das Textfeld darf nicht leer sein.")
    if len(value) > maximum:
        raise APIError(
            HTTPStatus.BAD_REQUEST,
            "text_too_long",
            f"Das Textfeld darf höchstens {maximum} Zeichen enthalten.",
        )
    return value


class APIError(Exception):
    def __init__(self, status: int | HTTPStatus, code: str, message: str):
        super().__init__(message)
        self.status = int(status)
        self.code = code
        self.message = message


def default_config() -> dict[str, Any]:
    return {
        "_instructions": [
            "Benutzernamen, Passwörter und Anzeigenamen unten anpassen.",
            "Für Internetzugriff HTTPS über einen Reverse Proxy oder den TLS-Block verwenden.",
            "Diese Datei niemals in GitHub hochladen.",
        ],
        "server": {
            "host": "0.0.0.0",
            "port": 8765,
            "public_url": "",
            "timezone": "Europe/Berlin",
            "data_directory": "./rjlove_data",
            "max_request_mb": 10,
            "session_days": 30,
            "trust_reverse_proxy": False,
        },
        "tls": {
            "enabled": False,
            "certificate_file": "",
            "private_key_file": "",
        },
        "security": {
            "server_secret": secrets.token_urlsafe(48),
            "login_attempts_per_10_minutes": 10,
        },
        "users": [
            {
                "id": "robin",
                "display_name": "Robin",
                "username": "robin",
                "password": secrets.token_urlsafe(15),
                "accent": "cyan",
                "storage_limit_mb": 0,
            },
            {
                "id": "raphaela",
                "display_name": "Raphaela",
                "username": "raphaela",
                "password": secrets.token_urlsafe(15),
                "accent": "pink",
                "storage_limit_mb": 0,
            },
        ],
        "notifications": {
            "low_battery_threshold": 15,
            "notify_when_charging_starts": True,
            "notify_when_charging_stops": True,
        },
        "apns": {
            "enabled": False,
            "environment": "sandbox",
            "team_id": "",
            "key_id": "",
            "bundle_id": "eu.rjuhas.rjlove",
            "private_key_file": "",
        },
    }


def write_first_run_config(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(default_config(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    with contextlib.suppress(OSError):
        path.chmod(0o600)


def load_config(path: Path) -> dict[str, Any]:
    try:
        config = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"Konfiguration kann nicht gelesen werden: {exc}") from exc

    required = ("server", "security", "users", "notifications", "apns", "tls")
    for key in required:
        if key not in config:
            raise RuntimeError(f"Konfiguration unvollständig: '{key}' fehlt.")

    users = config["users"]
    if not isinstance(users, list) or len(users) < 2:
        raise RuntimeError("Mindestens zwei Benutzer müssen konfiguriert sein.")

    seen_ids: set[str] = set()
    seen_names: set[str] = set()
    for user in users:
        for key in ("id", "display_name", "username", "password"):
            if not isinstance(user.get(key), str) or not user[key].strip():
                raise RuntimeError(f"Benutzerfeld '{key}' fehlt oder ist leer.")
        user["id"] = user["id"].strip().lower()
        user["username"] = user["username"].strip().lower()
        if user["id"] in seen_ids or user["username"] in seen_names:
            raise RuntimeError("Benutzer-IDs und Benutzernamen müssen eindeutig sein.")
        if len(user["password"]) < 10:
            raise RuntimeError(f"Passwort für {user['username']} muss mindestens 10 Zeichen lang sein.")
        seen_ids.add(user["id"])
        seen_names.add(user["username"])

    secret = config["security"].get("server_secret", "")
    if not isinstance(secret, str) or len(secret) < 32:
        raise RuntimeError("security.server_secret muss mindestens 32 Zeichen lang sein.")

    try:
        ZoneInfo(config["server"].get("timezone", "Europe/Berlin"))
    except Exception as exc:
        raise RuntimeError("server.timezone ist keine gültige IANA-Zeitzone.") from exc

    return config


class Database:
    def __init__(self, path: Path):
        self.path = path
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.initialize()

    def connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path, timeout=20, isolation_level=None)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys=ON")
        connection.execute("PRAGMA busy_timeout=20000")
        return connection

    def initialize(self) -> None:
        with self.connect() as db:
            db.execute("PRAGMA journal_mode=WAL")
            db.execute("PRAGMA synchronous=NORMAL")
            db.executescript(
                """
                CREATE TABLE IF NOT EXISTS sessions (
                    token_hash TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    device_id TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    expires_at TEXT NOT NULL,
                    last_seen_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS sessions_user ON sessions(user_id);

                CREATE TABLE IF NOT EXISTS presence (
                    user_id TEXT PRIMARY KEY,
                    payload TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS thoughts (
                    user_id TEXT NOT NULL,
                    local_day TEXT NOT NULL,
                    count INTEGER NOT NULL DEFAULT 0,
                    updated_at TEXT NOT NULL,
                    PRIMARY KEY(user_id, local_day)
                );

                CREATE TABLE IF NOT EXISTS records (
                    id TEXT PRIMARY KEY,
                    kind TEXT NOT NULL,
                    owner_id TEXT NOT NULL,
                    payload TEXT NOT NULL,
                    size_bytes INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    deleted_at TEXT
                );
                CREATE INDEX IF NOT EXISTS records_visible ON records(kind, deleted_at, updated_at);
                CREATE INDEX IF NOT EXISTS records_owner ON records(owner_id, deleted_at);

                CREATE TABLE IF NOT EXISTS commands (
                    id TEXT PRIMARY KEY,
                    owner_id TEXT NOT NULL,
                    target_id TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    payload TEXT NOT NULL,
                    due_at TEXT,
                    created_at TEXT NOT NULL,
                    acknowledged_at TEXT
                );
                CREATE INDEX IF NOT EXISTS commands_target ON commands(target_id, acknowledged_at);

                CREATE TABLE IF NOT EXISTS events (
                    id TEXT PRIMARY KEY,
                    target_id TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    title TEXT NOT NULL,
                    body TEXT NOT NULL,
                    payload TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    read_at TEXT
                );
                CREATE INDEX IF NOT EXISTS events_target ON events(target_id, read_at, created_at);

                CREATE TABLE IF NOT EXISTS devices (
                    id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    device_token TEXT NOT NULL UNIQUE,
                    environment TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS devices_user ON devices(user_id);
                """
            )


class LoginLimiter:
    def __init__(self, maximum: int):
        self.maximum = max(3, int(maximum))
        self.lock = threading.Lock()
        self.attempts: dict[str, list[float]] = {}

    def check(self, key: str) -> None:
        cutoff = time.monotonic() - 600
        with self.lock:
            recent = [stamp for stamp in self.attempts.get(key, []) if stamp >= cutoff]
            self.attempts[key] = recent
            if len(recent) >= self.maximum:
                raise APIError(
                    HTTPStatus.TOO_MANY_REQUESTS,
                    "login_rate_limited",
                    "Zu viele Anmeldeversuche. Bitte später erneut versuchen.",
                )

    def fail(self, key: str) -> None:
        with self.lock:
            self.attempts.setdefault(key, []).append(time.monotonic())

    def success(self, key: str) -> None:
        with self.lock:
            self.attempts.pop(key, None)


class APNSProvider:
    """Optional APNs sender without Python packages.

    It creates ES256 provider tokens with ``openssl`` and sends HTTP/2 requests
    with ``curl``. If the tools or APNs credentials are unavailable, events remain
    persisted and the app receives them during its next sync.
    """

    def __init__(self, app: "RJLoveApplication"):
        self.app = app
        self._jwt: str | None = None
        self._jwt_created = 0.0
        self._lock = threading.Lock()

    @property
    def enabled(self) -> bool:
        value = self.app.config.get("apns", {})
        return bool(value.get("enabled"))

    @staticmethod
    def _der_to_raw(signature: bytes) -> bytes:
        if len(signature) < 8 or signature[0] != 0x30:
            raise ValueError("Ungültige DER-Signatur")
        index = 1
        length = signature[index]
        index += 1
        if length & 0x80:
            count = length & 0x7F
            index += count
        if signature[index] != 0x02:
            raise ValueError("Ungültige DER-Signatur (r)")
        index += 1
        r_len = signature[index]
        index += 1
        r = signature[index:index + r_len]
        index += r_len
        if signature[index] != 0x02:
            raise ValueError("Ungültige DER-Signatur (s)")
        index += 1
        s_len = signature[index]
        index += 1
        s = signature[index:index + s_len]
        r = r.lstrip(b"\x00").rjust(32, b"\x00")
        s = s.lstrip(b"\x00").rjust(32, b"\x00")
        if len(r) != 32 or len(s) != 32:
            raise ValueError("Unerwartete ES256-Signaturlänge")
        return r + s

    def provider_token(self) -> str:
        with self._lock:
            if self._jwt and time.time() - self._jwt_created < 45 * 60:
                return self._jwt

            config = self.app.config["apns"]
            key_path = self.app.resolve_config_path(config.get("private_key_file", ""))
            if not key_path.is_file():
                raise RuntimeError("APNs private_key_file wurde nicht gefunden.")
            header = b64url(json_bytes({"alg": "ES256", "kid": config.get("key_id", "")}))
            claims = b64url(json_bytes({"iss": config.get("team_id", ""), "iat": int(time.time())}))
            signing_input = f"{header}.{claims}".encode("ascii")
            result = subprocess.run(
                ["openssl", "dgst", "-sha256", "-sign", str(key_path)],
                input=signing_input,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
                timeout=15,
            )
            if result.returncode != 0:
                raise RuntimeError(f"OpenSSL konnte APNs JWT nicht signieren: {result.stderr.decode(errors='replace')}")
            self._jwt = f"{header}.{claims}.{b64url(self._der_to_raw(result.stdout))}"
            self._jwt_created = time.time()
            return self._jwt

    def send_to_user(self, user_id: str, event: dict[str, Any]) -> None:
        if not self.enabled:
            return
        thread = threading.Thread(target=self._send_worker, args=(user_id, event), daemon=True)
        thread.start()

    def _send_worker(self, user_id: str, event: dict[str, Any]) -> None:
        try:
            token = self.provider_token()
            config = self.app.config["apns"]
            with self.app.database.connect() as db:
                devices = db.execute(
                    "SELECT id, device_token, environment FROM devices WHERE user_id=?",
                    (user_id,),
                ).fetchall()
            for device in devices:
                environment = device["environment"] or config.get("environment", "sandbox")
                host = "api.push.apple.com" if environment == "production" else "api.sandbox.push.apple.com"
                payload = {
                    "aps": {
                        "alert": {"title": event["title"], "body": event["body"]},
                        "sound": "default",
                        "content-available": 1,
                    },
                    "rj_event_id": event["id"],
                    "rj_event_kind": event["kind"],
                }
                command = [
                    "curl", "--silent", "--show-error", "--http2",
                    "--max-time", "15", "--output", "/dev/null",
                    "--write-out", "%{http_code}",
                    "--header", f"authorization: bearer {token}",
                    "--header", f"apns-topic: {config.get('bundle_id', 'eu.rjuhas.rjlove')}",
                    "--header", "apns-push-type: alert",
                    "--header", "apns-priority: 10",
                    "--data-binary", "@-",
                    f"https://{host}/3/device/{device['device_token']}",
                ]
                result = subprocess.run(
                    command,
                    input=json_bytes(payload),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    check=False,
                    timeout=20,
                )
                status = result.stdout.decode(errors="replace").strip()
                if result.returncode != 0 or status not in {"200"}:
                    self.app.logger.warning(
                        "APNs delivery failed for device %s (HTTP %s): %s",
                        device["id"], status or "?", result.stderr.decode(errors="replace").strip(),
                    )
                    if status in {"400", "410"}:
                        with self.app.database.connect() as db:
                            db.execute("DELETE FROM devices WHERE id=?", (device["id"],))
        except Exception as exc:
            self.app.logger.warning("APNs delivery unavailable: %s", exc)


class RJLoveApplication:
    def __init__(self, config: dict[str, Any], config_path: Path):
        self.config = config
        self.config_path = config_path
        data_value = config["server"].get("data_directory", "./rjlove_data")
        self.data_directory = self.resolve_config_path(data_value)
        self.data_directory.mkdir(parents=True, exist_ok=True)
        self.database = Database(self.data_directory / "rjlove.sqlite3")
        self.logger = self._make_logger()
        self.login_limiter = LoginLimiter(config["security"].get("login_attempts_per_10_minutes", 10))
        self.apns = APNSProvider(self)
        self.timezone = ZoneInfo(config["server"].get("timezone", "Europe/Berlin"))
        self._cleanup_stop = threading.Event()
        self._cleanup_thread = threading.Thread(target=self._cleanup_loop, daemon=True)
        self._cleanup_thread.start()

    def _make_logger(self) -> logging.Logger:
        logger = logging.getLogger(f"rj_love_server.{id(self)}")
        logger.setLevel(logging.INFO)
        logger.propagate = False
        formatter = logging.Formatter("%(asctime)s %(levelname)s %(message)s")
        stream = logging.StreamHandler(sys.stdout)
        stream.setFormatter(formatter)
        logger.addHandler(stream)
        rotating = RotatingFileHandler(
            self.data_directory / "server.log", maxBytes=2_000_000, backupCount=3, encoding="utf-8"
        )
        rotating.setFormatter(formatter)
        logger.addHandler(rotating)
        return logger

    def resolve_config_path(self, value: str) -> Path:
        path = Path(value).expanduser()
        return path if path.is_absolute() else (self.config_path.parent / path).resolve()

    def public_user(self, user: dict[str, Any]) -> dict[str, Any]:
        return {
            "id": user["id"],
            "display_name": user["display_name"],
            "accent": user.get("accent", "pink"),
            "storage_limit_mb": int(user.get("storage_limit_mb", 0) or 0),
        }

    def user_by_username(self, username: str) -> dict[str, Any] | None:
        normalized = username.strip().lower()
        return next((item for item in self.config["users"] if item["username"] == normalized), None)

    def user_by_id(self, user_id: str) -> dict[str, Any] | None:
        return next((item for item in self.config["users"] if item["id"] == user_id), None)

    def partner_ids(self, user_id: str) -> list[str]:
        return [item["id"] for item in self.config["users"] if item["id"] != user_id]

    def password_matches(self, user: dict[str, Any], candidate: str) -> bool:
        secret = self.config["security"]["server_secret"].encode("utf-8")
        salt = hmac.new(secret, user["username"].encode("utf-8"), hashlib.sha256).digest()[:16]
        expected = hashlib.scrypt(user["password"].encode("utf-8"), salt=salt, n=2**14, r=8, p=1)
        actual = hashlib.scrypt(candidate.encode("utf-8"), salt=salt, n=2**14, r=8, p=1)
        return hmac.compare_digest(expected, actual)

    def issue_session(self, user_id: str, device_id: str) -> tuple[str, str]:
        token = secrets.token_urlsafe(36)
        token_hash = hashlib.sha256(token.encode("ascii")).hexdigest()
        created = utc_now()
        expires = created + dt.timedelta(days=int(self.config["server"].get("session_days", 30)))
        with self.database.connect() as db:
            db.execute(
                "INSERT INTO sessions(token_hash,user_id,device_id,created_at,expires_at,last_seen_at) VALUES(?,?,?,?,?,?)",
                (token_hash, user_id, device_id, created.isoformat(), expires.isoformat(), created.isoformat()),
            )
        return token, expires.isoformat().replace("+00:00", "Z")

    def authenticate(self, authorization: str | None) -> str:
        if not authorization or not authorization.startswith("Bearer "):
            raise APIError(HTTPStatus.UNAUTHORIZED, "authentication_required", "Bitte erneut anmelden.")
        token = authorization[7:].strip()
        if not token:
            raise APIError(HTTPStatus.UNAUTHORIZED, "authentication_required", "Bitte erneut anmelden.")
        token_hash = hashlib.sha256(token.encode("ascii", errors="ignore")).hexdigest()
        now = utc_now()
        with self.database.connect() as db:
            row = db.execute("SELECT * FROM sessions WHERE token_hash=?", (token_hash,)).fetchone()
            if row is None or (parse_iso(row["expires_at"]) or now) <= now:
                if row is not None:
                    db.execute("DELETE FROM sessions WHERE token_hash=?", (token_hash,))
                raise APIError(HTTPStatus.UNAUTHORIZED, "session_expired", "Die Sitzung ist abgelaufen.")
            db.execute("UPDATE sessions SET last_seen_at=? WHERE token_hash=?", (iso_now(), token_hash))
        return str(row["user_id"])

    def local_day(self) -> str:
        return dt.datetime.now(self.timezone).date().isoformat()

    def storage_usage(self, user_id: str, db: sqlite3.Connection | None = None) -> int:
        owns_connection = db is None
        connection = db or self.database.connect()
        try:
            row = connection.execute(
                "SELECT COALESCE(SUM(size_bytes),0) AS total FROM records WHERE owner_id=? AND deleted_at IS NULL",
                (user_id,),
            ).fetchone()
            return int(row["total"])
        finally:
            if owns_connection:
                connection.close()

    def enforce_quota(self, user_id: str, new_size: int, previous_size: int = 0, db: sqlite3.Connection | None = None) -> None:
        user = self.user_by_id(user_id)
        limit_mb = int((user or {}).get("storage_limit_mb", 0) or 0)
        if limit_mb <= 0:
            return
        used = self.storage_usage(user_id, db)
        if used - previous_size + new_size > limit_mb * 1024 * 1024:
            raise APIError(
                HTTPStatus.INSUFFICIENT_STORAGE,
                "storage_limit_reached",
                f"Das Speicherlimit von {limit_mb} MB ist erreicht.",
            )

    def create_event(
        self,
        target_id: str,
        kind: str,
        title: str,
        body: str,
        payload: dict[str, Any] | None = None,
        *,
        db: sqlite3.Connection | None = None,
    ) -> dict[str, Any]:
        event = {
            "id": str(uuid.uuid4()),
            "target_id": target_id,
            "kind": kind,
            "title": title[:120],
            "body": body[:500],
            "payload": payload or {},
            "created_at": iso_now(),
        }
        owns_connection = db is None
        connection = db or self.database.connect()
        try:
            connection.execute(
                "INSERT INTO events(id,target_id,kind,title,body,payload,created_at) VALUES(?,?,?,?,?,?,?)",
                (
                    event["id"], target_id, kind, event["title"], event["body"],
                    json.dumps(event["payload"], ensure_ascii=False), event["created_at"],
                ),
            )
        finally:
            if owns_connection:
                connection.close()
        self.apns.send_to_user(target_id, event)
        return event

    def broadcast_event(
        self,
        sender_id: str,
        kind: str,
        title: str,
        body: str,
        payload: dict[str, Any] | None = None,
        *,
        db: sqlite3.Connection | None = None,
    ) -> None:
        for target_id in self.partner_ids(sender_id):
            self.create_event(target_id, kind, title, body, payload, db=db)

    def bootstrap(self, user_id: str) -> dict[str, Any]:
        day = self.local_day()
        with self.database.connect() as db:
            presences = {row["user_id"]: json.loads(row["payload"]) | {"updated_at": row["updated_at"]}
                         for row in db.execute("SELECT * FROM presence")}
            thought_rows = db.execute("SELECT user_id,count FROM thoughts WHERE local_day=?", (day,)).fetchall()
            thoughts = {row["user_id"]: int(row["count"]) for row in thought_rows}
            record_rows = db.execute(
                "SELECT id,kind,owner_id,payload,created_at,updated_at FROM records "
                "WHERE deleted_at IS NULL ORDER BY updated_at DESC LIMIT 500"
            ).fetchall()
            command_rows = db.execute(
                "SELECT * FROM commands WHERE target_id=? AND acknowledged_at IS NULL ORDER BY created_at LIMIT 50",
                (user_id,),
            ).fetchall()
            event_rows = db.execute(
                "SELECT * FROM events WHERE target_id=? AND read_at IS NULL ORDER BY created_at LIMIT 100",
                (user_id,),
            ).fetchall()

        records = [
            {
                "id": row["id"], "kind": row["kind"], "owner_id": row["owner_id"],
                "payload": json.loads(row["payload"]), "created_at": row["created_at"],
                "updated_at": row["updated_at"],
            }
            for row in record_rows
        ]
        commands = [
            {
                "id": row["id"], "owner_id": row["owner_id"], "target_id": row["target_id"],
                "kind": row["kind"], "payload": json.loads(row["payload"]),
                "due_at": row["due_at"], "created_at": row["created_at"],
            }
            for row in command_rows
        ]
        events = [
            {
                "id": row["id"], "kind": row["kind"], "title": row["title"],
                "body": row["body"], "payload": json.loads(row["payload"]),
                "created_at": row["created_at"],
            }
            for row in event_rows
        ]
        user = self.user_by_id(user_id)
        assert user is not None
        return {
            "server_time": iso_now(),
            "local_day": day,
            "me": self.public_user(user),
            "partners": [self.public_user(item) | {"presence": presences.get(item["id"])}
                         for item in self.config["users"] if item["id"] != user_id],
            "my_presence": presences.get(user_id),
            "thoughts": thoughts,
            "records": records,
            "commands": commands,
            "events": events,
            "storage_used_bytes": self.storage_usage(user_id),
            "features": {
                "apns_enabled": self.apns.enabled,
                "low_battery_threshold": int(self.config["notifications"].get("low_battery_threshold", 15)),
                "max_request_mb": int(self.config["server"].get("max_request_mb", 10)),
            },
        }

    def cleanup(self) -> None:
        now = utc_now()
        old_events = now - dt.timedelta(days=30)
        old_commands = now - dt.timedelta(days=14)
        with self.database.connect() as db:
            db.execute("DELETE FROM sessions WHERE expires_at < ?", (now.isoformat(),))
            db.execute("DELETE FROM events WHERE read_at IS NOT NULL AND created_at < ?", (old_events.isoformat(),))
            db.execute("DELETE FROM commands WHERE acknowledged_at IS NOT NULL AND created_at < ?", (old_commands.isoformat(),))
            db.execute("DELETE FROM records WHERE deleted_at IS NOT NULL AND deleted_at < ?", (old_events.isoformat(),))

    def _cleanup_loop(self) -> None:
        while not self._cleanup_stop.wait(3600):
            with contextlib.suppress(Exception):
                self.cleanup()

    def close(self) -> None:
        self._cleanup_stop.set()
        for handler in list(self.logger.handlers):
            handler.close()
            self.logger.removeHandler(handler)


class RJLoveRequestHandler(BaseHTTPRequestHandler):
    server_version = f"RJLoveServer/{APP_VERSION}"
    protocol_version = "HTTP/1.1"

    @property
    def app(self) -> RJLoveApplication:
        return self.server.app  # type: ignore[attr-defined]

    def log_message(self, fmt: str, *args: Any) -> None:
        self.app.logger.info("%s %s", self.client_address[0], fmt % args)

    def client_key(self) -> str:
        if self.app.config["server"].get("trust_reverse_proxy"):
            forwarded = self.headers.get("X-Forwarded-For", "").split(",", 1)[0].strip()
            if forwarded:
                return forwarded
        return self.client_address[0]

    def send_json(self, status: int | HTTPStatus, body: Any) -> None:
        encoded = json_bytes(body)
        self.send_response(int(status))
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")
        self.end_headers()
        self.wfile.write(encoded)

    def send_empty(self, status: int | HTTPStatus = HTTPStatus.NO_CONTENT) -> None:
        self.send_response(int(status))
        self.send_header("Content-Length", "0")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()

    def read_json(self) -> dict[str, Any]:
        raw_length = self.headers.get("Content-Length", "0")
        try:
            length = int(raw_length)
        except ValueError as exc:
            raise APIError(HTTPStatus.BAD_REQUEST, "invalid_length", "Ungültige Anfragegröße.") from exc
        maximum = int(self.app.config["server"].get("max_request_mb", 10)) * 1024 * 1024
        if length <= 0:
            return {}
        if length > maximum:
            raise APIError(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, "request_too_large", "Die Anfrage ist zu groß.")
        raw = self.rfile.read(length)
        try:
            value = json.loads(raw)
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            raise APIError(HTTPStatus.BAD_REQUEST, "invalid_json", "Die JSON-Anfrage ist ungültig.") from exc
        if not isinstance(value, dict):
            raise APIError(HTTPStatus.BAD_REQUEST, "invalid_json", "Es wird ein JSON-Objekt erwartet.")
        return value

    def current_user(self) -> str:
        return self.app.authenticate(self.headers.get("Authorization"))

    def route(self) -> tuple[str, list[str], dict[str, list[str]]]:
        parsed = urlparse(self.path)
        parts = [part for part in parsed.path.split("/") if part]
        return parsed.path, parts, parse_qs(parsed.query)

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(HTTPStatus.NO_CONTENT)
        self.send_header("Allow", "GET, POST, DELETE, OPTIONS")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        try:
            path, parts, _ = self.route()
            if path == "/health":
                self.send_json(HTTPStatus.OK, {"status": "ok", "version": APP_VERSION, "time": iso_now()})
                return
            if path == "/v1/bootstrap":
                self.send_json(HTTPStatus.OK, self.app.bootstrap(self.current_user()))
                return
            if len(parts) == 4 and parts[:2] == ["v1", "moments"] and parts[3] == "image":
                self._get_moment_image(self.current_user(), parts[2])
                return
            raise APIError(HTTPStatus.NOT_FOUND, "not_found", "Route nicht gefunden.")
        except APIError as exc:
            self.send_json(exc.status, {"error": exc.code, "message": exc.message})
        except Exception:
            request_id = secrets.token_hex(6)
            self.app.logger.exception("Unhandled GET error %s", request_id)
            self.send_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": "server_error", "message": f"Serverfehler ({request_id})."})

    def do_POST(self) -> None:  # noqa: N802
        try:
            path, parts, _ = self.route()
            if path == "/v1/auth/login":
                self._login()
                return
            if path == "/v1/auth/logout":
                self._logout()
                return

            user_id = self.current_user()
            if path == "/v1/presence":
                self._presence(user_id)
            elif path == "/v1/thoughts":
                self._thought(user_id)
            elif path == "/v1/records":
                self._upsert_record(user_id)
            elif path == "/v1/commands":
                self._create_command(user_id)
            elif path == "/v1/geofence-events":
                self._geofence_event(user_id)
            elif path == "/v1/devices":
                self._register_device(user_id)
            elif len(parts) == 4 and parts[:2] == ["v1", "commands"] and parts[3] == "ack":
                self._ack_command(user_id, parts[2])
            elif len(parts) == 4 and parts[:2] == ["v1", "events"] and parts[3] == "ack":
                self._ack_event(user_id, parts[2])
            else:
                raise APIError(HTTPStatus.NOT_FOUND, "not_found", "Route nicht gefunden.")
        except APIError as exc:
            self.send_json(exc.status, {"error": exc.code, "message": exc.message})
        except Exception:
            request_id = secrets.token_hex(6)
            self.app.logger.exception("Unhandled POST error %s", request_id)
            self.send_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": "server_error", "message": f"Serverfehler ({request_id})."})

    def do_DELETE(self) -> None:  # noqa: N802
        try:
            _, parts, _ = self.route()
            user_id = self.current_user()
            if len(parts) == 3 and parts[:2] == ["v1", "records"]:
                self._delete_record(user_id, parts[2])
            elif len(parts) == 3 and parts[:2] == ["v1", "devices"]:
                self._delete_device(user_id, parts[2])
            else:
                raise APIError(HTTPStatus.NOT_FOUND, "not_found", "Route nicht gefunden.")
        except APIError as exc:
            self.send_json(exc.status, {"error": exc.code, "message": exc.message})
        except Exception:
            request_id = secrets.token_hex(6)
            self.app.logger.exception("Unhandled DELETE error %s", request_id)
            self.send_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": "server_error", "message": f"Serverfehler ({request_id})."})

    def _login(self) -> None:
        key = self.client_key()
        self.app.login_limiter.check(key)
        body = self.read_json()
        username = safe_text(body.get("username", ""), 80, allow_empty=False).lower()
        password = body.get("password")
        device_id = safe_text(body.get("device_id", "unknown-device"), 100, allow_empty=False)
        if not isinstance(password, str) or len(password) > 500:
            self.app.login_limiter.fail(key)
            raise APIError(HTTPStatus.UNAUTHORIZED, "invalid_credentials", "Benutzername oder Passwort ist falsch.")
        user = self.app.user_by_username(username)
        if user is None or not self.app.password_matches(user, password):
            self.app.login_limiter.fail(key)
            time.sleep(0.35)
            raise APIError(HTTPStatus.UNAUTHORIZED, "invalid_credentials", "Benutzername oder Passwort ist falsch.")
        self.app.login_limiter.success(key)
        token, expires = self.app.issue_session(user["id"], device_id)
        self.app.logger.info("Login successful for %s from %s", user["id"], key)
        self.send_json(
            HTTPStatus.OK,
            {"token": token, "expires_at": expires, "user": self.app.public_user(user), "server_version": APP_VERSION},
        )

    def _logout(self) -> None:
        authorization = self.headers.get("Authorization", "")
        self.current_user()
        token = authorization.removeprefix("Bearer ").strip()
        token_hash = hashlib.sha256(token.encode("ascii", errors="ignore")).hexdigest()
        with self.app.database.connect() as db:
            db.execute("DELETE FROM sessions WHERE token_hash=?", (token_hash,))
        self.send_empty()

    def _presence(self, user_id: str) -> None:
        body = self.read_json()
        allowed = {
            "latitude", "longitude", "horizontal_accuracy", "altitude", "speed",
            "course", "location_timestamp", "battery_level", "battery_state",
            "low_power_mode", "network_type", "wifi_name", "focus_active",
            "motion", "steps", "sleep_minutes", "sleep_score", "health_updated_at",
            "location_sharing", "status_message", "device_name", "app_version",
        }
        payload = {key: value for key, value in body.items() if key in allowed}
        if "latitude" in payload or "longitude" in payload:
            try:
                latitude = float(payload["latitude"])
                longitude = float(payload["longitude"])
            except (KeyError, TypeError, ValueError) as exc:
                raise APIError(HTTPStatus.BAD_REQUEST, "invalid_location", "Standortkoordinaten sind ungültig.") from exc
            if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
                raise APIError(HTTPStatus.BAD_REQUEST, "invalid_location", "Standortkoordinaten liegen außerhalb des gültigen Bereichs.")
            payload["latitude"] = latitude
            payload["longitude"] = longitude
        if "battery_level" in payload:
            payload["battery_level"] = min(100, max(0, int(payload["battery_level"])))
        if "status_message" in payload:
            payload["status_message"] = safe_text(payload["status_message"], 120)
        if "wifi_name" in payload and payload["wifi_name"] is not None:
            payload["wifi_name"] = safe_text(str(payload["wifi_name"]), 80)
        payload["reported_at"] = iso_now()

        with self.app.database.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            previous_row = db.execute("SELECT payload FROM presence WHERE user_id=?", (user_id,)).fetchone()
            previous = json.loads(previous_row["payload"]) if previous_row else {}
            merged = previous | payload
            now = iso_now()
            db.execute(
                "INSERT INTO presence(user_id,payload,updated_at) VALUES(?,?,?) "
                "ON CONFLICT(user_id) DO UPDATE SET payload=excluded.payload,updated_at=excluded.updated_at",
                (user_id, json.dumps(merged, ensure_ascii=False), now),
            )
            db.execute("COMMIT")

        sender = self.app.user_by_id(user_id) or {"display_name": "Schatzi"}
        old_battery = previous.get("battery_level")
        new_battery = merged.get("battery_level")
        threshold = int(self.app.config["notifications"].get("low_battery_threshold", 15))
        if isinstance(new_battery, (int, float)) and (
            not isinstance(old_battery, (int, float)) or old_battery > threshold
        ) and new_battery <= threshold:
            self.app.broadcast_event(
                user_id, "battery_low", f"{sender['display_name']} braucht Strom",
                f"Der Akku liegt nur noch bei {int(new_battery)} %.", {"battery_level": int(new_battery)},
            )
        old_state, new_state = previous.get("battery_state"), merged.get("battery_state")
        if old_state and old_state != new_state:
            if new_state in {"charging", "full"} and self.app.config["notifications"].get("notify_when_charging_starts", True):
                self.app.broadcast_event(
                    user_id, "charging_started", f"{sender['display_name']} lädt jetzt",
                    f"Akku: {int(new_battery)} %" if isinstance(new_battery, (int, float)) else "Das iPhone wurde angeschlossen.",
                )
            elif old_state in {"charging", "full"} and self.app.config["notifications"].get("notify_when_charging_stops", True):
                self.app.broadcast_event(
                    user_id, "charging_stopped", f"{sender['display_name']} lädt nicht mehr",
                    f"Akku: {int(new_battery)} %" if isinstance(new_battery, (int, float)) else "Das iPhone wurde vom Strom getrennt.",
                )
        self.send_json(HTTPStatus.OK, {"updated_at": now})

    def _thought(self, user_id: str) -> None:
        day = self.app.local_day()
        now = iso_now()
        with self.app.database.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            db.execute(
                "INSERT INTO thoughts(user_id,local_day,count,updated_at) VALUES(?,?,1,?) "
                "ON CONFLICT(user_id,local_day) DO UPDATE SET count=count+1,updated_at=excluded.updated_at",
                (user_id, day, now),
            )
            count = int(db.execute(
                "SELECT count FROM thoughts WHERE user_id=? AND local_day=?", (user_id, day)
            ).fetchone()["count"])
            db.execute("COMMIT")
        sender = self.app.user_by_id(user_id) or {"display_name": "Schatzi"}
        self.app.broadcast_event(
            user_id, "thought", f"{sender['display_name']} denkt an dich 💗",
            f"Heute schon {count}× an dich gedacht.", {"count": count, "day": day},
        )
        self.send_json(HTTPStatus.OK, {"day": day, "count": count})

    def _upsert_record(self, user_id: str) -> None:
        body = self.read_json()
        record_id = safe_text(body.get("id") or str(uuid.uuid4()), 64, allow_empty=False)
        try:
            uuid.UUID(record_id)
        except ValueError as exc:
            raise APIError(HTTPStatus.BAD_REQUEST, "invalid_record_id", "Die Datensatz-ID ist ungültig.") from exc
        kind = safe_text(body.get("kind", ""), 30, allow_empty=False)
        if kind not in ALLOWED_RECORD_KINDS:
            raise APIError(HTTPStatus.BAD_REQUEST, "invalid_record_kind", "Dieser Datensatztyp wird nicht unterstützt.")
        payload = body.get("payload")
        if not isinstance(payload, dict):
            raise APIError(HTTPStatus.BAD_REQUEST, "invalid_payload", "Der Datensatzinhalt ist ungültig.")
        raw_payload = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
        size = len(raw_payload.encode("utf-8"))
        now = iso_now()

        with self.app.database.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            old = db.execute("SELECT owner_id,size_bytes,created_at FROM records WHERE id=?", (record_id,)).fetchone()
            owner_id = str(old["owner_id"]) if old else user_id
            if old and owner_id != user_id:
                # Both partners may edit shared records, but quota remains charged to the creator.
                previous_size = int(old["size_bytes"])
            else:
                previous_size = int(old["size_bytes"]) if old else 0
            self.app.enforce_quota(owner_id, size, previous_size, db)
            created_at = str(old["created_at"]) if old else now
            db.execute(
                "INSERT INTO records(id,kind,owner_id,payload,size_bytes,created_at,updated_at,deleted_at) "
                "VALUES(?,?,?,?,?,?,?,NULL) ON CONFLICT(id) DO UPDATE SET kind=excluded.kind,payload=excluded.payload,"
                "size_bytes=excluded.size_bytes,updated_at=excluded.updated_at,deleted_at=NULL",
                (record_id, kind, owner_id, raw_payload, size, created_at, now),
            )
            db.execute("COMMIT")

        sender = self.app.user_by_id(user_id) or {"display_name": "Schatzi"}
        labels = {
            "note": ("Gemeinsame Notiz", "hat eine Notiz geteilt."),
            "reminder": ("Gemeinsame Erinnerung", "hat eine Erinnerung gespeichert."),
            "moment": ("Neuer gemeinsamer Moment 💞", "hat einen Moment geteilt."),
            "geofence": ("Gemeinsamer Ort", "hat einen Ort aktualisiert."),
            "calendar": ("Gemeinsamer Termin", "hat einen Termin geteilt."),
        }
        title, phrase = labels[kind]
        self.app.broadcast_event(user_id, f"record_{kind}", title, f"{sender['display_name']} {phrase}", {"record_id": record_id})
        self.send_json(
            HTTPStatus.OK,
            {"id": record_id, "kind": kind, "owner_id": owner_id, "payload": payload, "created_at": created_at, "updated_at": now},
        )

    def _delete_record(self, user_id: str, record_id: str) -> None:
        now = iso_now()
        with self.app.database.connect() as db:
            row = db.execute("SELECT kind FROM records WHERE id=? AND deleted_at IS NULL", (record_id,)).fetchone()
            if row is None:
                raise APIError(HTTPStatus.NOT_FOUND, "record_not_found", "Der Eintrag wurde nicht gefunden.")
            db.execute("UPDATE records SET deleted_at=?,updated_at=? WHERE id=?", (now, now, record_id))
        sender = self.app.user_by_id(user_id) or {"display_name": "Schatzi"}
        self.app.broadcast_event(
            user_id, "record_deleted", "Gemeinsamer Eintrag gelöscht",
            f"{sender['display_name']} hat einen Eintrag entfernt.", {"record_id": record_id},
        )
        self.send_empty()

    def _create_command(self, user_id: str) -> None:
        body = self.read_json()
        target_id = safe_text(body.get("target_id", ""), 64, allow_empty=False)
        if target_id not in self.app.partner_ids(user_id):
            raise APIError(HTTPStatus.BAD_REQUEST, "invalid_target", "Das Ziel ist kein verbundener Partner.")
        kind = safe_text(body.get("kind", "wake"), 30, allow_empty=False)
        if kind not in ALLOWED_COMMAND_KINDS:
            raise APIError(HTTPStatus.BAD_REQUEST, "invalid_command", "Dieser Befehl wird nicht unterstützt.")
        message = safe_text(body.get("message", "Schatzi möchte dich wecken 💗"), 120, allow_empty=False)
        due = parse_iso(body.get("due_at")) or (utc_now() + dt.timedelta(seconds=2))
        if due > utc_now() + dt.timedelta(days=30):
            raise APIError(HTTPStatus.BAD_REQUEST, "due_too_far", "Der Alarm darf höchstens 30 Tage in der Zukunft liegen.")
        command_id = str(uuid.uuid4())
        created = iso_now()
        payload = {"message": message}
        with self.app.database.connect() as db:
            db.execute(
                "INSERT INTO commands(id,owner_id,target_id,kind,payload,due_at,created_at) VALUES(?,?,?,?,?,?,?)",
                (command_id, user_id, target_id, kind, json.dumps(payload, ensure_ascii=False), due.isoformat(), created),
            )
        sender = self.app.user_by_id(user_id) or {"display_name": "Schatzi"}
        self.app.create_event(
            target_id, "wake_request", f"Weckruf von {sender['display_name']} 💗", message,
            {"command_id": command_id, "due_at": due.isoformat()},
        )
        self.send_json(
            HTTPStatus.CREATED,
            {"id": command_id, "kind": kind, "target_id": target_id, "payload": payload, "due_at": due.isoformat(), "created_at": created},
        )

    def _ack_command(self, user_id: str, command_id: str) -> None:
        with self.app.database.connect() as db:
            cursor = db.execute(
                "UPDATE commands SET acknowledged_at=? WHERE id=? AND target_id=?",
                (iso_now(), command_id, user_id),
            )
        if cursor.rowcount == 0:
            raise APIError(HTTPStatus.NOT_FOUND, "command_not_found", "Der Befehl wurde nicht gefunden.")
        self.send_empty()

    def _ack_event(self, user_id: str, event_id: str) -> None:
        with self.app.database.connect() as db:
            cursor = db.execute(
                "UPDATE events SET read_at=? WHERE id=? AND target_id=?", (iso_now(), event_id, user_id)
            )
        if cursor.rowcount == 0:
            raise APIError(HTTPStatus.NOT_FOUND, "event_not_found", "Die Meldung wurde nicht gefunden.")
        self.send_empty()

    def _geofence_event(self, user_id: str) -> None:
        body = self.read_json()
        event_kind = safe_text(body.get("event", ""), 10, allow_empty=False)
        if event_kind not in {"enter", "exit"}:
            raise APIError(HTTPStatus.BAD_REQUEST, "invalid_geofence_event", "Ungültiges Geofence-Ereignis.")
        name = safe_text(body.get("name", "Ort"), 80, allow_empty=False)
        sender = self.app.user_by_id(user_id) or {"display_name": "Schatzi"}
        verb = "hat den Ort betreten" if event_kind == "enter" else "hat den Ort verlassen"
        self.app.broadcast_event(
            user_id, f"geofence_{event_kind}", f"{sender['display_name']} · {name}",
            f"{sender['display_name']} {verb}.",
            {"geofence_id": body.get("geofence_id"), "event": event_kind, "name": name},
        )
        self.send_empty()

    def _register_device(self, user_id: str) -> None:
        body = self.read_json()
        token = safe_text(body.get("device_token", ""), 256, allow_empty=False).lower()
        if any(character not in "0123456789abcdef" for character in token) or len(token) < 32:
            raise APIError(HTTPStatus.BAD_REQUEST, "invalid_device_token", "Der APNs-Gerätetoken ist ungültig.")
        environment = safe_text(body.get("environment", "sandbox"), 20, allow_empty=False)
        if environment not in {"sandbox", "production"}:
            raise APIError(HTTPStatus.BAD_REQUEST, "invalid_environment", "Ungültige APNs-Umgebung.")
        device_id = safe_text(body.get("device_id", str(uuid.uuid4())), 100, allow_empty=False)
        with self.app.database.connect() as db:
            db.execute(
                "INSERT INTO devices(id,user_id,device_token,environment,updated_at) VALUES(?,?,?,?,?) "
                "ON CONFLICT(device_token) DO UPDATE SET user_id=excluded.user_id,environment=excluded.environment,updated_at=excluded.updated_at",
                (device_id, user_id, token, environment, iso_now()),
            )
        self.send_empty()

    def _delete_device(self, user_id: str, device_id: str) -> None:
        with self.app.database.connect() as db:
            db.execute("DELETE FROM devices WHERE id=? AND user_id=?", (device_id, user_id))
        self.send_empty()

    def _get_moment_image(self, user_id: str, record_id: str) -> None:
        del user_id  # Authentication is enough; moments are shared inside the private pair.
        with self.app.database.connect() as db:
            row = db.execute(
                "SELECT payload FROM records WHERE id=? AND kind='moment' AND deleted_at IS NULL", (record_id,)
            ).fetchone()
        if row is None:
            raise APIError(HTTPStatus.NOT_FOUND, "moment_not_found", "Der Moment wurde nicht gefunden.")
        payload = json.loads(row["payload"])
        encoded = payload.get("image_base64")
        if not isinstance(encoded, str):
            raise APIError(HTTPStatus.NOT_FOUND, "image_not_found", "Das Bild wurde nicht gefunden.")
        try:
            data = base64.b64decode(encoded, validate=True)
        except ValueError as exc:
            raise APIError(HTTPStatus.INTERNAL_SERVER_ERROR, "image_invalid", "Das gespeicherte Bild ist beschädigt.") from exc
        mime = str(payload.get("mime_type") or "image/jpeg")
        if not mime.startswith("image/"):
            mime = mimetypes.guess_type("image.jpg")[0] or "image/jpeg"
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "private, max-age=300")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(data)


class RJLoveHTTPServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address: tuple[str, int], app: RJLoveApplication):
        super().__init__(address, RJLoveRequestHandler)
        self.app = app


def build_server(app: RJLoveApplication) -> RJLoveHTTPServer:
    server_config = app.config["server"]
    host = str(server_config.get("host", "0.0.0.0"))
    port = int(server_config.get("port", 8765))
    server = RJLoveHTTPServer((host, port), app)
    tls = app.config.get("tls", {})
    if tls.get("enabled"):
        certificate = app.resolve_config_path(str(tls.get("certificate_file", "")))
        private_key = app.resolve_config_path(str(tls.get("private_key_file", "")))
        if not certificate.is_file() or not private_key.is_file():
            raise RuntimeError("TLS ist aktiviert, aber Zertifikat oder privater Schlüssel fehlt.")
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(certificate, private_key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
    return server


def config_path_from_environment() -> Path:
    custom = os.environ.get("RJLOVE_CONFIG")
    return Path(custom).expanduser().resolve() if custom else Path(__file__).resolve().with_name(CONFIG_FILENAME)


def main() -> int:
    config_path = config_path_from_environment()
    if not config_path.exists():
        write_first_run_config(config_path)
        print(f"RJ Love: Konfiguration wurde erstellt: {config_path}")
        print("Benutzer und Servereinstellungen prüfen, Datei speichern und das Skript erneut starten.")
        return 0

    try:
        config = load_config(config_path)
        app = RJLoveApplication(config, config_path)
        server = build_server(app)
    except Exception as exc:
        print(f"RJ Love kann nicht starten: {exc}", file=sys.stderr)
        return 2

    scheme = "https" if config.get("tls", {}).get("enabled") else "http"
    host, port = server.server_address[:2]
    app.logger.info("RJ Love Server %s listening on %s://%s:%s", APP_VERSION, scheme, host, port)

    stopping = threading.Event()

    def stop_server(signum: int, _frame: Any) -> None:
        if stopping.is_set():
            return
        stopping.set()
        app.logger.info("Signal %s received, shutting down", signum)
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, stop_server)
    signal.signal(signal.SIGINT, stop_server)
    try:
        server.serve_forever(poll_interval=0.5)
    finally:
        server.server_close()
        app.close()
        app.logger.info("RJ Love Server stopped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
