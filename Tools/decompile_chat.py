import os
import re

path = os.path.join(os.environ["TEMP"], "lumi-apk", "decompiled.js")
data = open(path, encoding="utf-8", errors="ignore").read()

targets = [
    "Original name: _postChat",
    "Original name: _postChatAsync",
    "Original name: _createSession",
    "Original name: _listSessions",
    "Original name: ChatWsBoot",
    "Original name: _send",
    "Original name: _resumeLastChat",
    "Original name: _resumeChatSessionById",
]

for target in targets:
    index = data.find(target)
    print("\n\n################", target, "at", index)
    if index == -1:
        continue
    print(data[index : index + 7000])
