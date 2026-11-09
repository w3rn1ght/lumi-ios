"""
Проверка валидации нативного API Lumi (Django REST Framework).
Запускается в CI: хост lumi-api.nexoragroup.dev недоступен локально.
"""

import json
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
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = response.read()
            print(f"{method} {path} -> {response.status}")
            print("  body:", payload[:600])
            return response.status, payload
    except urllib.error.HTTPError as error:
        payload = error.read()
        print(f"{method} {path} -> {error.code}")
        print("  body:", payload[:600])
        return error.code, payload
    except Exception as error:  # noqa: BLE001
        print(f"{method} {path} -> ERROR {type(error).__name__}: {error}")
        return 0, b""


print("== app/version-check ==")
for method in ("POST", "GET"):
    call(method, "/api/app/version-check/", {} if method == "POST" else None)

print("\n== login validation (empty body, wrong types) ==")
call("POST", "/api/users/login/", {})
call("POST", "/api/users/login/", {"username": "probe@example.com", "password": "x"})
call("POST", "/api/users/login/", {"email": "probe@example.com"})
call("POST", "/api/users/login/", {"email": "", "password": ""})

print("\n== refresh validation ==")
call("POST", "/api/users/token/refresh/", {"refresh": "invalid"})

print("\n== register validation ==")
call("POST", "/api/users/register/", {})
call("POST", "/api/users/register/", {"email": "probe@example.com"})
call("POST", "/api/users/register/", {"email": "probe@example.com", "password": "short"})

print("\n== password reset (possible routes) ==")
for path in (
    "/api/users/password/reset/",
    "/api/users/password-reset/",
    "/api/users/forgot-password/",
    "/api/users/reset-password/",
    "/api/users/password-reset/request/",
):
    call("POST", path, {"email": "probe@example.com"})
