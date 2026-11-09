import os
import re

path = os.path.join(os.environ["TEMP"], "lumi-apk", "decompiled.js")
data = open(path, encoding="utf-8", errors="ignore").read()

names = sorted(set(re.findall(r"// Original name: ([A-Za-z0-9_$]+)", data)))
interesting = [n for n in names if re.search(r"chat|message|session|stream|token|login|auth|socket|send", n, re.I)]
print("interesting functions:", len(interesting))
for name in interesting:
    print(name)

print("\n=== /api strings in decompiled ===")
for value in sorted(set(re.findall(r"['\"](/api/[^'\"]+)['\"]", data))):
    print(value)

print("\n=== ws/wss strings ===")
for value in sorted(set(re.findall(r"['\"](wss?://[^'\"]+)['\"]", data))):
    print(value)
