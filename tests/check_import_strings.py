"""Checks the import window's translations (KalimdorZugZugRadio/tools/import_strings.py): every
language has exactly the keys of enUS, the same {placeholders}, and the languages match the addon's
Locales.lua. Run with: npm run strings (from tests/)."""
import re
import string
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "KalimdorZugZugRadio" / "tools"))
from import_strings import STRINGS, Texts, _from_os_name  # noqa: E402

failures = 0


def check(label, ok):
    global failures
    print(("PASS " if ok else "FAIL ") + label)
    failures += not ok


def fields(text):
    return sorted(f for _, f, _, _ in string.Formatter().parse(text) if f is not None)


ref = STRINGS["enUS"]
locales = set(re.findall(r"^LOCALES\.(\w+)\s*=", (ROOT / "KalimdorZugZugRadio" / "Locales.lua")
                         .read_text(encoding="utf-8"), re.M))
check(f"same languages as Locales.lua ({len(STRINGS)})", not locales or locales == set(STRINGS))
for lang, table in STRINGS.items():
    missing = sorted(set(ref) - set(table))
    extra = sorted(set(table) - set(ref))
    check(f"{lang}: keys (missing {missing}, extra {extra})" if missing or extra else f"{lang}: keys", not (missing or extra))
    bad = [k for k in ref if k in table and fields(table[k]) != fields(ref[k])]
    check(f"{lang}: placeholders {bad}" if bad else f"{lang}: placeholders", not bad)
    empty = [k for k, v in table.items() if not v.strip()]
    check(f"{lang}: no empty texts {empty}" if empty else f"{lang}: no empty texts", not empty)

T = Texts("itIT")
check("format with values", T("music_count", tracks=5).endswith("5"))
check("unknown language falls back to English", Texts("xxXX")("import") == "Import")
check("Windows names", [_from_os_name(n) for n in ("it_IT", "zh_TW", "zh_CN", "es_MX", "es_ES", "en_GB", "nl_NL")]
      == ["itIT", "zhTW", "zhCN", "esMX", "esES", "enUS", None])

print("ALL TESTS PASSED" if not failures else f"{failures} FAILED")
sys.exit(1 if failures else 0)
