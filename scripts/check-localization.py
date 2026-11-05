#!/usr/bin/env python3
"""Checks that every UI string in App/Sources is translated in App/Resources/Localizable.xcstrings.

Fails when a String(localized:) key is missing from the catalog, a key lacks an en, zh-Hans or ja
translation (or it is not marked translated), a translation's format specifiers differ from the
zh-Hant source, or a Chinese/Japanese string literal bypasses L10n. Unused catalog keys and
full-width punctuation joined into UI text (which every language then shows) are only warnings.

  scripts/check-localization.py          exit 1 on failure (CI, by hand)
  scripts/check-localization.py --hook   Claude Code Stop hook: reads the hook JSON on stdin and
                                         exits 2 on failure so Claude keeps working, at most once
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = os.path.join(ROOT, "App", "Sources")
CATALOG = os.path.join(ROOT, "App", "Resources", "Localizable.xcstrings")
LANGUAGES = ["en", "zh-Hans", "ja"]

KEY = re.compile(r'String\(localized:\s*"((?:[^"\\]|\\.)*)"')
LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
CJK = re.compile("[\u3040-\u30ff\u3400-\u9fff]")  # kana and Han
FULLWIDTH = re.compile("[\u3000-\u303f\uff01-\uff60]")
SPEC = re.compile(r"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?([@dDuUxXoOfFeEgGcCsSpaA%])")


def specifiers(value):
    return sorted(m.group(1).replace("D", "d") for m in SPEC.finditer(value) if m.group(1) != "%")


def units(loc):
    """Yields (label, stringUnit) for a plain value or each plural/device variant."""
    if "stringUnit" in loc:
        yield "", loc["stringUnit"]
    for kind, cases in loc.get("variations", {}).items():
        for case, sub in cases.items():
            for label, unit in units(sub):
                yield f" [{kind}.{case}{label}]", unit


def scan_sources():
    keys, stray, punct = {}, [], []
    for dirpath, _, files in os.walk(SOURCES):
        for name in sorted(files):
            if not name.endswith(".swift"):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, ROOT)
            text = open(path, encoding="utf-8").read()
            for m in KEY.finditer(text):
                keys.setdefault(m.group(1), f"{rel}:{text.count(chr(10), 0, m.start()) + 1}")
            for n, line in enumerate(text.splitlines(), 1):
                code = line.split("//", 1)[0] if not line.lstrip().startswith("//") else ""
                for m in LITERAL.finditer(code):
                    before = code[:m.start()].rstrip()
                    if before.endswith(("defaultValue:", "comment:")):
                        continue
                    if CJK.search(m.group(1)):
                        stray.append(f"{rel}:{n}: \"{m.group(1)}\"")
                    elif FULLWIDTH.search(m.group(1)):
                        punct.append(f"{rel}:{n}: \"{m.group(1)}\"")
    return keys, stray, punct


def check():
    errors, warnings = [], []
    keys, stray, punct = scan_sources()
    try:
        catalog = json.load(open(CATALOG, encoding="utf-8"))
    except (OSError, ValueError) as e:
        return [f"cannot read {os.path.relpath(CATALOG, ROOT)}: {e}"], [], 0
    strings = catalog.get("strings", {})
    source = catalog.get("sourceLanguage", "zh-Hant")

    for key, where in sorted(keys.items()):
        entry = strings.get(key)
        if entry is None:
            errors.append(f"{key}: not in the catalog ({where})")
            continue
        locs = entry.get("localizations", {})
        base = [specifiers(u.get("value", "")) for _, u in units(locs.get(source, {}))]
        base = base[0] if base else None
        for lang in LANGUAGES:
            found = list(units(locs.get(lang, {})))
            if not found:
                errors.append(f"{key}: no {lang} translation ({where})")
                continue
            plural = len(found) > 1
            for label, unit in found:
                value, state = unit.get("value", ""), unit.get("state")
                if not value.strip():
                    errors.append(f"{key}: empty {lang}{label} value")
                elif state != "translated":
                    errors.append(f"{key}: {lang}{label} is '{state}', not translated")
                if base is not None:
                    got = specifiers(value)
                    # A plural case such as "one" may spell the number out instead of using it.
                    ok = (not set(got) - set(base)) if plural else got == base
                    if not ok:
                        errors.append(f"{key}: {lang}{label} format {got} does not match {source} {base}")
    for s in stray:
        errors.append(f"{s} is not localized; add it to L10n with String(localized:defaultValue:)")
    for p in punct:
        warnings.append(f"{p} is full-width punctuation shown in every language; move it into a localized format")
    for key in sorted(set(strings) - set(keys)):
        if strings[key].get("extractionState") != "manual":
            warnings.append(f"{key}: in the catalog but not used in App/Sources")
    return errors, warnings, len(keys)


def main():
    hook = "--hook" in sys.argv[1:]
    if hook:
        try:
            payload = json.load(sys.stdin)
        except ValueError:
            payload = {}
        if payload.get("stop_hook_active"):
            return 0  # Already blocked once this turn; let Claude stop instead of looping.
    errors, warnings, count = check()
    out = sys.stderr if hook else sys.stdout
    if not hook:
        for w in warnings:
            print(f"warning: {w}")
    if not errors:
        if not hook:
            print(f"Localization OK: {count} keys translated into {', '.join(LANGUAGES)}.")
        return 0
    print(f"Localization check failed ({len(errors)} problem(s)):", file=out)
    for e in errors:
        print(f"  - {e}", file=out)
    if hook:
        print("Add the missing translations to App/Resources/Localizable.xcstrings as AGENTS.md describes, "
              "then rerun scripts/check-localization.py. If these strings belong to another session's "
              "unfinished work, leave them and tell the user instead.", file=out)
        return 2
    return 1


if __name__ == "__main__":
    sys.exit(main())
