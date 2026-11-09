import os
import re

path = os.path.join(os.environ["TEMP"], "lumi-apk", "decompiled.js")
data = open(path, encoding="utf-8", errors="ignore").read()

# 1. Find the login function body and its arguments.
index = data.find("Original name: login, environment: r2")
print("login fn at", index)
print(data[index : index + 6000])
