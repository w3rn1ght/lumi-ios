import os
import re

path = os.path.join(os.environ["TEMP"], "lumi-apk", "decompiled.js")
data = open(path, encoding="utf-8", errors="ignore").read()

names = sorted(set(re.findall(r"// Original name: ([A-Za-z0-9_$]+)", data)))
for name in names:
    if re.fullmatch(r"(createSession|getSessions|listSessions|sendMessage|fetchMessages|getMessages|createChat|postChat|sendChat|getChatSessions)", name):
        index = data.find("// Original name: " + name)
        print("\n\n################", name, index)
        print(data[index : index + 12000])
