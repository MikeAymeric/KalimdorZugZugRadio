"""Compare two RadioProbe compatibility snapshots (RadioProbeDB.compat).

Dev-only. Pass the RadioProbe.lua SavedVariables file of a reference client (where the
addon is known to work, e.g. WoW Forever) and of the client being ported to. It prints
what exists on the reference but is missing on the other client: those are the names,
widget methods, events and templates to guard or replace.

Usage: python tools/probe_diff.py REFERENCE_SV OTHER_SV
"""
import re
import sys
from pathlib import Path

SECTIONS = ["globals", "methods", "events", "templates", "frameTypes"]


def section(text, name):
    """Strings listed in compat[name] = { ... } of a SavedVariables file."""
    compat = text[text.find('["compat"]'):]
    m = re.search(r'\["' + name + r'"\]\s*=\s*\{(.*?)\n\t*\}', compat, re.S)
    return set(re.findall(r'"((?:\\.|[^"\\])*)"', m.group(1))) if m else set()


def build(text):
    compat = text[text.find('["compat"]'):]
    m = re.search(r'\["build"\]\s*=\s*\{(.*?)\}', compat, re.S)
    return " ".join(re.findall(r'"([^"]*)"|(\d+)', m.group(1))[i][0] or "" for i in range(2)) if m else "?"


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    ref, other = (Path(p).read_text(encoding="utf-8", errors="replace") for p in sys.argv[1:])
    for label, text in (("reference", ref), ("other", other)):
        if '["compat"]' not in text:
            sys.exit(f"The {label} file has no compat snapshot: run /rprobe compat and /reload there.")
    print(f"Reference: {build(ref)}   Other: {build(other)}")
    for name in SECTIONS:
        missing = sorted(section(other, name) - section(ref, name))
        extra = sorted(section(ref, name) - section(other, name))
        print(f"\n{name}: {len(missing)} missing on the other client")
        for item in missing:
            print(f"  - {item}")
        if extra:
            print(f"  (present only on the other client: {', '.join(extra)})")


if __name__ == "__main__":
    main()
