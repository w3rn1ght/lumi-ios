"""
Проверка нативного API Lumi в GitHub Actions.
Хост lumi-api.nexoragroup.dev недоступен с локальной машины,
поэтому запросы выполняются на раннере.

Внимание: успешный вход не проверяется, чтобы не использовать чужие аккаунты.
"""

import json
import urllib.error
import urllib.request

BASE = "https://lumi-api.nexoragroup.dev"
UA = "Lumi/1.0.0 (Android)"


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(
        BASE + path,
        data=data,
        method=method,
        headers={
            "User-Agent": UA,
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = response.read()
            print(f"{method} {path} -> {response.status} ({len(payload)} bytes)")
            return response.status, payload
    except urllib.error.HTTPError as error:
        payload = error.read()
        print(f"{method} {path} -> {error.code}")
        print("  body:", payload[:300])
        return error.code, payload
    except Exception as error:  # noqa: BLE001
        print(f"{method} {path} -> ERROR {type(error).__name__}: {error}")
        return 0, b""


print("== invalid login (deterministic 401) ==")
call("POST", "/api/users/login/", {"email": "probe-not-real@example.com", "password": "x"})

print("\n== protected endpoints without token ==")
for method, path in (
    ("GET", "/api/users/profile/"),
    ("GET", "/api/chat/sessions/"),
    ("GET", "/api/chat/sessions/00000000-0000-0000-0000-000000000000/messages/"),
    ("POST", "/api/chat/"),
):
    call(method, path, {} if method == "POST" else None)

print("\n== public web API (catalog) ==")
request = urllib.request.Request(
    "https://api.lumi.site/public/characters?limit=2",
    headers={"User-Agent": "Mozilla/5.0"},
)
try:
    with urllib.request.urlopen(request, timeout=30) as response:
        body = json.loads(response.read())
        print("public characters ->", response.status, "items:", len(body.get("items", [])))
except Exception as error:  # noqa: BLE001
    print("public characters -> ERROR", error)
