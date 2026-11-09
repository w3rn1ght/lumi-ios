"""
Диагностика нативного API Lumi (мобильный бэкенд).
Запускается на GitHub Actions (macos-15), т.к. с локальной машины хост
lumi-api.nexoragroup.dev сбрасывает TLS-соединение.

Ничего не пишет: только коды ответов, набор полей и ошибочные сообщения.
"""

import json
import ssl
import urllib.error
import urllib.request

BASE = "https://lumi-api.nexoragroup.dev"
UA = "Lumi/1.0.0 (Android)"


def call(method, path, body=None, headers=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(
        BASE + path,
        data=data,
        method=method,
        headers={
            "User-Agent": UA,
            "Accept": "application/json",
            "Content-Type": "application/json",
            **(headers or {}),
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30, context=ssl.create_default_context()) as response:
            payload = response.read()
            print(f"{method} {path} -> {response.status} ({len(payload)} bytes)")
            print("  server:", response.headers.get("Server"))
            for cookie in response.headers.get_all("Set-Cookie") or []:
                print("  set-cookie:", cookie.split(";")[0])
            return response.status, payload
    except urllib.error.HTTPError as error:
        payload = error.read()
        print(f"{method} {path} -> {error.code}")
        print("  body:", payload[:400])
        return error.code, payload
    except Exception as error:  # noqa: BLE001
        print(f"{method} {path} -> ERROR {type(error).__name__}: {error}")
        return 0, b""


status, body = call("GET", "/api/app/version-check/")
if status == 200:
    print("  keys:", sorted(json.loads(body).keys()))

# Invalid credentials should produce a deterministic, non-destructive error.
for payload in (
    {"email": "nonexistent-probe@example.com", "password": "x"},
    {"email": "nonexistent-probe@example.com", "password": "x", "device": "probe"},
):
    status, body = call("POST", "/api/users/login/", payload)
    try:
        print("  keys:", sorted(json.loads(body).keys()))
    except Exception:  # noqa: BLE001
        pass

# Unauthenticated private endpoints: we only care about status codes.
for method, path in (
    ("GET", "/api/users/profile/"),
    ("GET", "/api/chat/sessions/"),
    ("POST", "/api/users/token/refresh/"),
):
    call(method, path, {} if method == "POST" else None)
