from __future__ import annotations

import base64
import binascii
import json
import logging
import os
import secrets
import sqlite3
import time
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterator
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlparse
from urllib.request import Request, urlopen


LOGGER = logging.getLogger(__name__)
PROFILE_FIELDS = (
    "uid,email,display_name,role,is_approved,must_change_password,"
    "tenant_id,landlord_id"
)


class SupabaseConfigurationError(RuntimeError):
    pass


class SupabaseRequestError(RuntimeError):
    def __init__(
        self, status: int, code: str | None = None, user_message: str | None = None
    ):
        self.status = status
        self.code = code
        self.user_message = user_message
        super().__init__(f"Supabase request failed with status {status}.")


def _is_publishable_key(key: str) -> bool:
    if key.startswith("sb_publishable_"):
        return len(key) > len("sb_publishable_")
    parts = key.split(".")
    if len(parts) != 3:
        return False
    try:
        encoded_payload = parts[1]
        payload = base64.b64decode(
            encoded_payload + "=" * (-len(encoded_payload) % 4),
            altchars=b"-_",
            validate=True,
        )
        claims = json.loads(payload)
    except (binascii.Error, UnicodeDecodeError, json.JSONDecodeError, ValueError):
        return False
    return isinstance(claims, dict) and claims.get("role") == "anon"


@dataclass(frozen=True)
class SupabaseSettings:
    url: str
    publishable_key: str


@contextmanager
def _database(path: Path) -> Iterator[sqlite3.Connection]:
    path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(path)
    connection.row_factory = sqlite3.Row
    try:
        with connection:
            yield connection
    finally:
        connection.close()


def init_sessions(path: Path) -> None:
    with _database(path) as db:
        db.execute(
            """CREATE TABLE IF NOT EXISTS web_sessions (
                id TEXT PRIMARY KEY,
                access_token TEXT NOT NULL,
                refresh_token TEXT NOT NULL,
                expires_at INTEGER NOT NULL,
                csrf_token TEXT NOT NULL,
                created_at INTEGER NOT NULL
            )"""
        )


def settings() -> SupabaseSettings | None:
    if os.environ.get("RAMP_WEB_TEST_PREVIEW") == "1":
        return None
    production = os.environ.get("RAMP_ENV", "").strip().casefold() == "production"
    url = os.environ.get("RAMP_SUPABASE_URL", "").strip()
    key = os.environ.get("RAMP_SUPABASE_PUBLISHABLE_KEY", "").strip()
    config_path = os.environ.get("RAMP_SUPABASE_CONFIG", "").strip()
    paths = [Path(config_path).expanduser()] if config_path and not production else []
    if not paths and not production:
        paths.append(
            Path.home()
            / "AndroidStudioProjects"
            / "rampadmin"
            / ".env.local.json"
        )
    for path in paths:
        if not path.is_file():
            continue
        try:
            values = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise SupabaseConfigurationError(
                "The Supabase config file could not be read."
            ) from error
        if not isinstance(values, dict):
            raise SupabaseConfigurationError(
                "The Supabase config file must contain a JSON object."
            )
        url = url or str(values.get("SUPABASE_URL", "")).strip()
        key = key or str(values.get("SUPABASE_PUBLISHABLE_KEY", "")).strip()
        break
    if not url and not key:
        if production:
            raise SupabaseConfigurationError(
                "Set RAMP_SUPABASE_URL and RAMP_SUPABASE_PUBLISHABLE_KEY in the hosting environment."
            )
        return None
    parsed = urlparse(url)
    if not url or not key or parsed.scheme != "https" or not parsed.netloc:
        raise SupabaseConfigurationError(
            "Set a valid HTTPS Supabase URL and publishable key."
        )
    if not _is_publishable_key(key):
        raise SupabaseConfigurationError(
            "RAMP_SUPABASE_PUBLISHABLE_KEY must be a Supabase publishable key or legacy anon key, never a secret/service-role key."
        )
    return SupabaseSettings(url.rstrip("/"), key)


def _request(
    config: SupabaseSettings,
    path: str,
    *,
    method: str = "GET",
    token: str | None = None,
    body: Any = None,
    query: dict[str, str] | None = None,
    prefer: str | None = None,
) -> Any:
    query_string = f"?{urlencode(query)}" if query else ""
    url = f"{config.url}{path}{query_string}"
    headers = {
        "apikey": config.publishable_key,
        "Authorization": f"Bearer {token or config.publishable_key}",
        "Accept": "application/json",
    }
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode("utf-8")
    if prefer:
        headers["Prefer"] = prefer
    request = Request(url, data=data, headers=headers, method=method)
    try:
        with urlopen(request, timeout=15) as response:
            payload = response.read()
    except HTTPError as error:
        error_body = error.read()
        code = None
        user_message = None
        try:
            error_payload = json.loads(error_body)
            code = error_payload.get("code")
            if path.startswith("/functions/v1/"):
                message = error_payload.get("error")
                if isinstance(message, str):
                    user_message = message[:240]
        except (AttributeError, json.JSONDecodeError, UnicodeDecodeError):
            pass
        raise SupabaseRequestError(error.code, code, user_message) from None
    except (TimeoutError, URLError, OSError) as error:
        LOGGER.warning("Supabase request could not reach %s (%s).", path, type(error).__name__)
        raise SupabaseRequestError(503, "connection_error") from None
    if not payload:
        return None
    try:
        return json.loads(payload)
    except (json.JSONDecodeError, UnicodeDecodeError):
        raise SupabaseRequestError(502, "invalid_response") from None


def sign_in(
    config: SupabaseSettings, database_path: Path, email: str, password: str
) -> tuple[str, str]:
    result = _request(
        config,
        "/auth/v1/token",
        method="POST",
        body={"email": email.strip().lower(), "password": password},
        query={"grant_type": "password"},
    )
    if not isinstance(result, dict):
        raise SupabaseRequestError(502, "invalid_response")
    access_token = result.get("access_token")
    refresh_token = result.get("refresh_token")
    auth_user = result.get("user") or {}
    auth_uid = auth_user.get("id")
    if not all(isinstance(value, str) and value for value in (access_token, refresh_token, auth_uid)):
        raise SupabaseRequestError(502, "invalid_response")
    profile = get_profile(config, access_token, auth_uid)
    if (
        profile is None
        or str(profile.get("role", "")).casefold() != "super_admin"
        or profile.get("is_approved") is not True
    ):
        try:
            _request(config, "/auth/v1/logout", method="POST", token=access_token)
        except SupabaseRequestError:
            LOGGER.info("Rejected Supabase session could not be revoked.")
        raise SupabaseRequestError(403, "admin_access_required")
    sid = secrets.token_urlsafe(32)
    csrf_token = secrets.token_urlsafe(32)
    expires_at = int(time.time()) + int(result.get("expires_in", 3600))
    with _database(database_path) as db:
        db.execute(
            """INSERT INTO web_sessions
               (id, access_token, refresh_token, expires_at, csrf_token, created_at)
               VALUES (?, ?, ?, ?, ?, ?)""",
            (sid, access_token, refresh_token, expires_at, csrf_token, int(time.time())),
        )
    return sid, csrf_token


def get_profile(
    config: SupabaseSettings, access_token: str, auth_uid: str
) -> dict[str, Any] | None:
    result = _request(
        config,
        "/rest/v1/users",
        token=access_token,
        query={
            "select": PROFILE_FIELDS,
            "uid": f"eq.{auth_uid}",
            "limit": "1",
        },
    )
    if not isinstance(result, list):
        raise SupabaseRequestError(502, "invalid_response")
    profile = result[0] if result else None
    if profile and profile.get("uid") != auth_uid:
        raise SupabaseRequestError(502, "invalid_profile")
    return profile


def load_session(
    config: SupabaseSettings, database_path: Path, sid: str
) -> tuple[dict[str, Any], str] | None:
    with _database(database_path) as db:
        row = db.execute("SELECT * FROM web_sessions WHERE id = ?", (sid,)).fetchone()
    if row is None:
        return None
    access_token = row["access_token"]
    refresh_token = row["refresh_token"]
    expires_at = row["expires_at"]
    if expires_at <= int(time.time()) + 90:
        try:
            result = _request(
                config,
                "/auth/v1/token",
                method="POST",
                body={"refresh_token": refresh_token},
                query={"grant_type": "refresh_token"},
            )
        except SupabaseRequestError as error:
            if error.status in (400, 401):
                delete_session(database_path, sid)
                return None
            raise
        if not isinstance(result, dict) or not result.get("access_token"):
            delete_session(database_path, sid)
            return None
        access_token = result["access_token"]
        refresh_token = result.get("refresh_token") or refresh_token
        expires_at = int(time.time()) + int(result.get("expires_in", 3600))
        with _database(database_path) as db:
            db.execute(
                """UPDATE web_sessions SET access_token = ?, refresh_token = ?,
                   expires_at = ? WHERE id = ?""",
                (access_token, refresh_token, expires_at, sid),
            )
    try:
        user = _request(config, "/auth/v1/user", token=access_token)
        profile = get_profile(config, access_token, user.get("id", ""))
    except SupabaseRequestError as error:
        if error.status in (400, 401, 403):
            delete_session(database_path, sid)
            return None
        raise
    except AttributeError:
        delete_session(database_path, sid)
        return None
    if (
        not isinstance(user, dict)
        or not profile
        or str(profile.get("role", "")).casefold() != "super_admin"
        or profile.get("is_approved") is not True
    ):
        delete_session(database_path, sid)
        return None
    return {"access_token": access_token, "profile": profile}, row["csrf_token"]


def api_request(
    config: SupabaseSettings,
    token: str,
    table: str,
    *,
    method: str = "GET",
    query: dict[str, str] | None = None,
    body: dict[str, Any] | list[dict[str, Any]] | None = None,
    prefer: str | None = None,
) -> Any:
    if not table.replace("_", "").isalnum():
        raise ValueError("Invalid Supabase table name.")
    return _request(
        config,
        f"/rest/v1/{table}",
        method=method,
        token=token,
        query=query,
        body=body if isinstance(body, dict) else body,
        prefer=prefer,
    )


def rpc_request(
    config: SupabaseSettings,
    token: str,
    function: str,
    arguments: dict[str, Any],
) -> Any:
    if not function.replace("_", "").isalnum():
        raise ValueError("Invalid Supabase RPC name.")
    return _request(
        config,
        f"/rest/v1/rpc/{function}",
        method="POST",
        token=token,
        body=arguments,
    )


def invoke_function(
    config: SupabaseSettings,
    token: str,
    function: str,
    body: dict[str, Any],
) -> Any:
    if not function.replace("-", "").isalnum():
        raise ValueError("Invalid Supabase function name.")
    return _request(
        config,
        f"/functions/v1/{function}",
        method="POST",
        token=token,
        body=body,
    )


def delete_session(database_path: Path, sid: str) -> None:
    with _database(database_path) as db:
        db.execute("DELETE FROM web_sessions WHERE id = ?", (sid,))


def request_password_reset(config: SupabaseSettings, email: str) -> None:
    result = _request(
        config,
        "/auth/v1/recover",
        method="POST",
        body={"email": email.strip().lower()},
    )
    if result is not None and not isinstance(result, dict):
        raise SupabaseRequestError(502, "invalid_response")


def sign_out(config: SupabaseSettings, database_path: Path, sid: str) -> None:
    with _database(database_path) as db:
        row = db.execute(
            "SELECT access_token FROM web_sessions WHERE id = ?", (sid,)
        ).fetchone()
        db.execute("DELETE FROM web_sessions WHERE id = ?", (sid,))
    if row is not None:
        _request(config, "/auth/v1/logout", method="POST", token=row["access_token"])
