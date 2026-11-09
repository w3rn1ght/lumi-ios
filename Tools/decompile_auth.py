import os
import re

path = os.path.join(os.environ["TEMP"], "lumi-apk", "decompiled.js")
data = open(path, encoding="utf-8", errors="ignore").read()

needles = [
    "Original name: login",
    "Original name: register",
    "Original name: signIn",
    "apiRequest",
    "authenticatedRequest",
    "credentials:",
    "withCredentials",
    "refreshToken",
    "accessToken",
    "session_id",
    "sessionId",
]

for needle in needles:
    matches = list(re.finditer(re.escape(needle), data))
    print("\n########", needle, len(matches))
    for match in matches[:2]:
        start = max(0, match.start() - 500)
        end = min(len(data), match.end() + 900)
        print("...", data[start:end], "...")
