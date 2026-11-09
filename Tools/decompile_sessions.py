import os

path = os.path.join(os.environ["TEMP"], "lumi-apk", "decompiled.js")
data = open(path, encoding="utf-8", errors="ignore").read()

for name in ("_createSession", "_listSessions", "_resumeLastChat", "_resumeChatSessionById", "listSessions"):
    index = data.find("Original name: " + name)
    print("\n\n################", name, index)
    if index >= 0:
        print(data[index : index + 9000])
