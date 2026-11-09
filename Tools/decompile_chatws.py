import os
import re

path = os.path.join(os.environ["TEMP"], "lumi-apk", "decompiled.js")
data = open(path, encoding="utf-8", errors="ignore").read()

for needle in ("@/services/chat-ws", "/ws/chat/", "access_token=", "?session_id=", "ws/chat"):
    print("\n########", needle, data.count(needle))
    for match in list(re.finditer(re.escape(needle), data))[:3]:
        start = max(0, match.start() - 1500)
        end = min(len(data), match.end() + 2500)
        print(data[start:end])
        print("\n---")
