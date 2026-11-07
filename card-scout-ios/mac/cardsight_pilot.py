"""Small, manually driven CardSight evaluation. Not connected to the app feed.

Run ``python3 mac/cardsight_pilot.py setup`` in a local terminal to enter a key
without echo, or use ``setup-web`` for a one-time loopback-only password form.
``serve`` accepts JSON requests on stdin and returns JSON lines.
Only read-only catalog, usage and price queries are allowed. No photos, collection
uploads, subscription changes, retries or persistent provider-data cache.
"""

from __future__ import annotations

import getpass
import http.client
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import re
import secrets
import ssl
import stat
import sys
import threading
import time
from urllib.parse import parse_qs, urlencode


KEY_PATH = Path.home() / "Library/Application Support/CardScoutMac/cardsight-api-key"
HOST = "api.cardsight.ai"
REQUEST_BUDGET = 40
MAX_RESPONSE_BYTES = 8 * 1024 * 1024
READ_PATH = re.compile(
    r"/v1/catalog/(?:segments|releases|sets|cards|parallels)"
    r"(?:/[0-9a-f-]{36})?(?:/cards)?$"
)


def check_private_parent(path: Path) -> None:
    info = path.parent.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise ValueError("Credential directory must be owned by the current user")
    if stat.S_IMODE(info.st_mode) & 0o077:
        raise ValueError("Credential directory must be private (mode 700)")


def save_secret(secret: str, path: Path = KEY_PATH) -> None:
    check_private_parent(path)
    if path.exists() or path.is_symlink():
        raise ValueError("Credential already exists; refusing to overwrite it")
    secret = secret.strip()
    if not re.fullmatch(r"[A-Za-z0-9_.-]{20,512}", secret):
        raise ValueError("Unexpected key format; nothing saved")
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        handle.write(secret + "\n")
        handle.flush()
        os.fsync(handle.fileno())
    print("CardSight key saved privately on this Mac. No API call made.", flush=True)


def save_key(path: Path = KEY_PATH) -> None:
    if not sys.stdin.isatty():
        raise ValueError("Key entry requires a local terminal with hidden input")
    save_secret(getpass.getpass("CardSight API key (hidden): "), path)


def setup_web() -> None:
    """One-use loopback form. No external assets, logs, cookies or key echo."""
    route = "/setup/" + secrets.token_urlsafe(32)

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_args: object) -> None:
            pass

        def respond(self, status: int, content: str) -> None:
            self.send_response(status)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Referrer-Policy", "same-origin")
            self.send_header("X-Frame-Options", "DENY")
            self.send_header("Content-Security-Policy", "default-src 'none'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'")
            self.end_headers()
            self.wfile.write(content.encode("utf-8"))

        def valid_destination(self) -> bool:
            expected_host = f"127.0.0.1:{self.server.server_port}"
            return self.path == route and self.headers.get("Host") == expected_host

        def do_GET(self) -> None:
            if not self.valid_destination():
                self.respond(404, "Not found")
                return
            self.respond(200, '<!doctype html><html><head><title>Card Scout private key setup</title></head>'
                         '<body><h1>Card Scout private key setup</h1><p>Saved only on this Mac. No subscription change.</p>'
                         f'<form method="post" action="{route}"><label>CardSight API key '
                         '<input type="password" name="api_key" autocomplete="off" required></label>'
                         '<button type="submit">Save privately on this Mac</button></form></body></html>')

        def do_POST(self) -> None:
            expected_origin = f"http://127.0.0.1:{self.server.server_port}"
            if (not self.valid_destination() or self.headers.get("Origin") != expected_origin
                    or self.headers.get("Content-Type") != "application/x-www-form-urlencoded"):
                print(json.dumps({"setup_rejected": True, "destination_matches": self.valid_destination(),
                                  "origin_matches": self.headers.get("Origin") == expected_origin,
                                  "content_type_matches": self.headers.get("Content-Type") == "application/x-www-form-urlencoded"}), flush=True)
                self.respond(403, "Rejected")
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 1 <= length <= 2048:
                    raise ValueError("Invalid length")
                form = parse_qs(self.rfile.read(length).decode("utf-8"), strict_parsing=True)
                values = form.get("api_key", [])
                if len(values) != 1:
                    raise ValueError("Invalid form")
                save_secret(values[0])
            except (ValueError, OSError):
                self.respond(400, "Key was not saved. Existing credentials are never overwritten.")
                return
            self.respond(200, '<!doctype html><title>Card Scout key saved</title>'
                         '<h1>Key saved privately on this Mac</h1><p>No API call made. You can close this tab.</p>')
            threading.Thread(target=self.server.shutdown, daemon=True).start()

    check_private_parent(KEY_PATH)
    server = HTTPServer(("127.0.0.1", 0), Handler)
    print(json.dumps({"setup_url": f"http://127.0.0.1:{server.server_port}{route}"}), flush=True)
    try:
        server.serve_forever()
    finally:
        server.server_close()


def load_key(path: Path = KEY_PATH) -> str:
    check_private_parent(path)
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, "r", encoding="utf-8") as handle:
        info = os.fstat(handle.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
            raise ValueError("Invalid credential file owner or type")
        if stat.S_IMODE(info.st_mode) & 0o077:
            raise ValueError("Credential file must be private (mode 600)")
        secret = handle.read(1024).strip()
    if not re.fullmatch(r"[A-Za-z0-9_.-]{20,512}", secret):
        raise ValueError("Invalid stored credential format")
    return secret


def validate_request(request: dict) -> tuple[str, str, dict, dict | None]:
    method = request.get("method", "GET").upper()
    path = request["path"]
    params = request.get("params", {})
    body = request.get("body")
    if method == "GET":
        if path != "/v1/subscription/" and not READ_PATH.fullmatch(path):
            raise ValueError("Path is outside the read-only pilot")
        if body is not None:
            raise ValueError("GET requests cannot have a body")
        if "take" in params and not 1 <= int(params["take"]) <= 100:
            raise ValueError("Catalog page size must be 1 to 100")
    elif method == "POST" and path == "/v1/pricing/":
        if not isinstance(body, dict) or not 1 <= len(body.get("card_ids", [])) <= 12:
            raise ValueError("Pilot price sample must contain 1 to 12 card IDs")
        if body.get("listing_type") != "auction" or body.get("period") != "90d":
            raise ValueError("Pilot only requests completed auctions from the last 90 days")
        if body.get("grade_id", "missing") is not None:
            raise ValueError("Pilot must explicitly request ungraded cards")
        if "parallel_id" not in body:
            raise ValueError("Pilot must explicitly select base or one parallel")
        if not 1 <= int(body.get("limit", 25)) <= 100:
            raise ValueError("Price record limit must be 1 to 100")
    else:
        raise ValueError("Only read-only catalog and price queries are permitted")
    return method, path, params, body


class Pilot:
    def __init__(self, secret: str) -> None:
        self.secret = secret
        self.calls = 0
        self.last_call = 0.0
        self.halted = False

    def query(self, request: dict) -> dict:
        method, path, params, body = validate_request(request)
        if self.halted or self.calls >= REQUEST_BUDGET:
            raise ValueError("Pilot stopped: quota/auth error or 40-request budget exhausted")
        time.sleep(max(0, 1.0 - (time.monotonic() - self.last_call)))
        query = "?" + urlencode(params, doseq=True) if params else ""
        payload = json.dumps(body).encode("utf-8") if body is not None else None
        headers = {"X-API-Key": self.secret, "Accept": "application/json"}
        if payload is not None:
            headers["Content-Type"] = "application/json"
        self.calls += 1
        self.last_call = time.monotonic()
        connection = http.client.HTTPSConnection(HOST, timeout=25, context=ssl.create_default_context())
        try:
            connection.request(method, path + query, body=payload, headers=headers)
            response = connection.getresponse()
            status = response.status
            if status in (401, 402, 403, 429) or 300 <= status < 400:
                self.halted = True
            raw = response.read(MAX_RESPONSE_BYTES + 1)
            if len(raw) > MAX_RESPONSE_BYTES:
                raise ValueError("Response too large for this pilot")
            # Some usage endpoints echo the credential. Never emit it.
            decoded = raw.decode("utf-8").replace(self.secret, "[REDACTED]")
            data = json.loads(decoded)
            if path == "/v1/subscription/" and status == 200:
                data = {"calls": data.get("calls"), "this_key_calls": [
                    item.get("calls") for item in data.get("api_keys", [])
                ]}
            return {"request_number": self.calls, "http_status": status,
                    "elapsed_ms": round((time.monotonic() - self.last_call) * 1000),
                    "data": data}
        finally:
            connection.close()


def main() -> None:
    if sys.argv[1:] == ["setup"]:
        save_key()
        return
    if sys.argv[1:] == ["setup-web"]:
        setup_web()
        return
    if sys.argv[1:] != ["serve"]:
        raise ValueError("Choose setup, setup-web or serve")
    pilot = Pilot(load_key())
    print(json.dumps({"ready": True, "request_budget": REQUEST_BUDGET}), flush=True)
    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            result = pilot.query(json.loads(line))
        except (ValueError, KeyError, TypeError, OSError, http.client.HTTPException):
            # Do not print exception details that could include request headers.
            result = {"error": "Request rejected or failed; no automatic retry", "request_number": pilot.calls}
        print(json.dumps(result, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
