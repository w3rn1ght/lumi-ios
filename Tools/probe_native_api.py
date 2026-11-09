"""
Проверка нативного API Lumi (используется мобильным приложением).

Запуск:  python Tools/probe_native_api.py
"""

import json
import urllib.error
import urllib.request

UA = "Lumi/1.0.0 (Android)"
BASE = "https://lumi-api.nexoragroup.dev"


def call(method, path, body=None, headers=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(
        BASE + path,
        data=data,
        method=method,
        headers={
            "User-Agent": UA,
            "Content-Type": "application/json",
            "Accept": "application/json",
            **(headers or {}),
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=25) as response:
            print(method, path, "->", response.status)
            print("  set-cookie:", response.headers.get_all("Set-Cookie"))
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        print(method, path, "->", error.code)
        print("  set-cookie:", error.headers.get_all("Set-Cookie"))
        return error.code, error.read()
    except Exception as error:  # noqa: BLE001
        print(method, path, "-> ERROR", error)
        return 0, b""


if __name__ == "__main__":
    call("GET", "/api/app/version-check")
    call("POST", "/api/users/login", {"email": "test@example.com", "password": "WrongPassword123"})
    call("POST", "/api/users/register", {"email": "test@example.com", "password": "WrongPassword123"})
