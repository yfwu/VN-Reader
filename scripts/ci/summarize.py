#!/usr/bin/env python3
"""Writes artifacts/SUMMARY.md from xcresult summaries (Markdown, also used for the job summary)."""
import json, os, sys, glob, subprocess
root = sys.argv[1]
lines = ["# CI summary", ""]
try:
    lines.append("Xcode: " + subprocess.check_output(["xcodebuild", "-version"], text=True).replace("\n", " "))
    lines.append("iOS Simulator SDK: " + subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], text=True).strip())
    lines.append("macOS: " + subprocess.check_output(["sw_vers", "-productVersion"], text=True).strip())
except Exception as e:
    lines.append(f"(version query failed: {e})")
lines.append("")
for log in ["core-macos.log", "core-ios.log"]:
    p = os.path.join(root, log)
    if os.path.exists(p):
        ex = [l.strip() for l in open(p, errors="replace") if "Executed" in l]
        lines.append(f"- {log}: {ex[-1] if ex else 'no summary line'}")
def walk(nodes, out, device):
    for n in nodes:
        if n.get("nodeType") == "Test Case":
            out.append((device, n.get("name"), n.get("result"), n.get("durationInSeconds", n.get("duration", ""))))
        walk(n.get("children", []), out, device)
for d in sorted(glob.glob(os.path.join(root, "ui-*"))):
    s = os.path.join(d, "summary.json")
    if os.path.exists(s):
        try:
            j = json.load(open(s))
            dev = ", ".join(f"{x.get('deviceName')} ({x.get('osVersion')})" for x in j.get("devicesAndConfigurations", [{}])[0:1] for x in [x.get("device", {})])
            lines.append(f"- {os.path.basename(d)}: {j.get('result')} — passed {j.get('passedTests')}, failed {j.get('failedTests')}, skipped {j.get('skippedTests')} — {dev}")
            for f in j.get("testFailures", []):
                lines.append(f"  - FAIL {f.get('testName')}: {f.get('failureText')}")
        except Exception as e:
            lines.append(f"- {d}: cannot parse summary ({e})")
    t = os.path.join(d, "tests.json")
    if os.path.exists(t):
        try:
            rows = []
            walk(json.load(open(t)).get("testNodes", []), rows, os.path.basename(d))
            for dev, name, res, dur in rows:
                lines.append(f"  - {res}: {name} ({dur}s)" if dur != "" else f"  - {res}: {name}")
        except Exception as e:
            lines.append(f"  (tests.json parse error {e})")
info = os.path.join(root, "device", "UNSIGNED-IPA-INFO.txt")
if os.path.exists(info):
    lines += ["", "## Device build", "", "```", open(info).read().strip(), "```"]
text = "\n".join(lines) + "\n"
open(os.path.join(root, "SUMMARY.md"), "w").write(text)
print(text)
