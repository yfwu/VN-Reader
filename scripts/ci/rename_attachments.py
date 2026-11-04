#!/usr/bin/env python3
"""Renames exported xcresult attachments to their XCTAttachment names (filesystem-safe)."""
import json, os, re, sys
d = sys.argv[1]
manifest = json.load(open(os.path.join(d, "manifest.json")))
for test in manifest:
    for a in test.get("attachments", []):
        src = os.path.join(d, a["exportedFileName"])
        name = a.get("suggestedHumanReadableName") or a["exportedFileName"]
        base = name.split("_0_")[0] if "_0_" in name else os.path.splitext(name)[0]
        base = re.sub(r'[\\/"\':<>|*?\r\n`]+', "_", base).strip("_ ")
        ext = os.path.splitext(a["exportedFileName"])[1]
        dst = os.path.join(d, base + ext)
        n = 2
        while os.path.exists(dst):
            dst = os.path.join(d, f"{base}-{n}{ext}"); n += 1
        if os.path.exists(src):
            os.rename(src, dst)
