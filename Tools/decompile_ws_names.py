import os
import re

path = os.path.join(os.environ["TEMP"], "lumi-apk", "decompiled.js")
data = open(path, encoding="utf-8", errors="ignore").read()

anchor = data.find("Original name: chatWsUrl")
print("chatWsUrl at", anchor)

start = max(0, anchor - 800000)
end = min(len(data), anchor + 800000)
segment = data[start:end]

names = []
for match in re.finditer(r"// Original name: ([A-Za-z0-9_$]+)", segment):
    names.append((start + match.start(), match.group(1)))

filtered = [(pos, name) for pos, name in names if re.search(r"chat|ws|socket|delta|message|send|stream|connect|session", name, re.I)]
for pos, name in filtered:
    print(pos, name)
