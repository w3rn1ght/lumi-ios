import os

path = os.path.join(os.environ["TEMP"], "lumi-apk", "decompiled.js")
data = open(path, encoding="utf-8", errors="ignore").read()

for name in ("ChatWsBoot", "_createSession", "_listSessions", "_resumeLastChat"):
    index = data.find("Original name: " + name)
    print("\n\n################", name, index)
    print(data[index : index + 9000])
