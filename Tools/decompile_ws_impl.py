import os

path = os.path.join(os.environ["TEMP"], "lumi-apk", "decompiled.js")
data = open(path, encoding="utf-8", errors="ignore").read()

targets = [
    "Original name: sendChatWsFrame",
    "Original name: handleMessage",
    "Original name: handleDeltaFrame",
    "Original name: connectChatWs",
    "Original name: sendPing",
    "Original name: sendThroughOutbox",
]

for name in targets:
    index = data.find(name)
    print("\n\n################", name, index)
    if index >= 0:
        print(data[index : index + 12000])
