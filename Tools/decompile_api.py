import os
import re

path = os.path.join(os.environ["TEMP"], "lumi-apk", "decompiled.js")
data = open(path, encoding="utf-8", errors="ignore").read()
print("decompiled bytes:", len(data))

for needle in ("/api/users/login", "/api/users/register", "/api/chat/sessions", "/api/chat/stream",
               "users/login", "chat/sessions", "Bearer", "Authorization", "token/refresh"):
    matches = list(re.finditer(re.escape(needle), data))
    print("\n########", needle, len(matches))
    for match in matches[:3]:
        start = max(0, match.start() - 600)
        end = min(len(data), match.end() + 800)
        print("...", data[start:end], "...")
