import os
import re

path = os.path.join(os.environ["TEMP"], "lumi-apk", "decompiled.js")
data = open(path, encoding="utf-8", errors="ignore").read()

# Look for message framing keys used with the chat socket.
for needle in ("'X-Chat-Turn-Id'", "X-Chat-Turn-Id", "client_message_id", "turn_id", "answer", "'message'", "chat.send", "sendMessage"):
    matches = list(re.finditer(re.escape(needle), data))
    print("\n########", needle, len(matches))
    for match in matches[:2]:
        start = max(0, match.start() - 900)
        end = min(len(data), match.end() + 1400)
        chunk = data[start:end]
        if "chat" in chunk.lower() or "message" in chunk.lower() or "turn" in chunk.lower():
            print(chunk)
            print("\n---")
