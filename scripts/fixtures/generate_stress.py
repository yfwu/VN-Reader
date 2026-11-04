#!/usr/bin/env python3
"""Generates large archives for stress tests (not committed; ~1 GB each).

    python3 scripts/fixtures/generate_stress.py --rar /path/to/rar --out /tmp/vn-stress [--pages 1000 --page-kb 1000]

Pages are incompressible pseudo-random payloads wrapped as minimal JPEG-like
files (SOI ... EOI) so archive sizes are realistic; they test the archive /
import / cache layers, not image decoding.
"""
import argparse, os, random, subprocess, zipfile, shutil

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rar"); ap.add_argument("--out", required=True)
    ap.add_argument("--pages", type=int, default=1000); ap.add_argument("--page-kb", type=int, default=1000)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    src = os.path.join(a.out, "src")
    os.makedirs(src, exist_ok=True)
    rnd = random.Random(7)
    for i in range(1, a.pages + 1):
        p = os.path.join(src, f"page{i}.jpg")
        if not os.path.exists(p):
            with open(p, "wb") as f:
                f.write(b"\xff\xd8\xff\xe0" + rnd.randbytes(a.page_kb * 1024) + b"\xff\xd9")
    with zipfile.ZipFile(os.path.join(a.out, "stress.cbz"), "w", zipfile.ZIP_STORED, allowZip64=True) as z:
        for i in range(1, a.pages + 1):
            z.write(os.path.join(src, f"page{i}.jpg"), f"vol/page{i}.jpg")
    if a.rar:
        for name, flags in [("stress_rar5_solid.cbr", ["-ma5", "-s", "-m1"]), ("stress_rar5_nonsolid.cbr", ["-ma5", "-m1"]),
                            ("stress_rar4_solid.cbr", ["-ma4", "-s", "-m1"])]:
            out = os.path.join(a.out, name)
            if os.path.exists(out): os.remove(out)
            subprocess.run([a.rar, "a", "-ep1", "-idq", "-y", *flags, out, os.path.join(src, "*")], check=True)
    shutil.rmtree(src)
    for f in sorted(os.listdir(a.out)):
        print(f"{os.path.getsize(os.path.join(a.out, f)) / 1e6:9.1f} MB  {f}")

if __name__ == "__main__":
    main()
