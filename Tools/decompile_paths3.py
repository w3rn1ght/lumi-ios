import os
import re

path = os.path.join(os.environ["TEMP"], "lumi-apk", "decompiled.js")
data = open(path, encoding="utf-8", errors="ignore").read()

# All string literals that look like chat-related path fragments or WS URLs.
for pattern, label in [
    (r"['\"]([^'\"]*(?:chat-ws|/chat/|chat/sessions|/ws|wss?:)[^'\"]*)['\"]", "paths"),
    (r"['\"]([^'\"]*[?&](?:chat_id|session_id|token|access)[^'\"]*)['\"]", "query"),
]:
    print("\n===", label)
    for value in sorted(set(re.findall(pattern, data))):
        if len(value) < 300:
            print(value)
