"""Builds KalimdorZugZugRadio/fonts/KZZRSans-Regular.ttf (dev-only; the output is committed).

WoW draws a font string with a single font file and has no per-glyph fallback, so symbols that
M+ 1p lacks (❤ ✿ ☀ ⚡ ✨ ➡ ㊙ ...) would show as boxes. This script takes M+ 1p and adds, for
every code point in SYMBOL_RANGES that it lacks, the glyph from the first source font that has
it. Glyphs are decomposed, scaled to M+'s units per em and copied without hinting.

All sources are under the SIL Open Font License 1.1 and are downloaded from github.com/google/fonts
into tools/.font-cache/ (gitignored). Noto Sans JP reserves the name "Source", M+ and Noto reserve
none; the result is renamed "KZZR Sans" as the OFL asks for modified versions.

Usage: python tools/build_fonts.py   (needs: pip install fonttools)
"""
from __future__ import annotations

import hashlib
import sys
import urllib.request
from pathlib import Path

from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "tools" / ".font-cache"
OUT_DIR = ROOT / "KalimdorZugZugRadio" / "fonts"
OUT_FONT = OUT_DIR / "KZZRSans-Regular.ttf"
OUT_LICENSE = OUT_DIR / "OFL-KZZRSans.txt"

GF = "https://github.com/google/fonts/raw/main/ofl/"
BASE = ("mplus1p/MPLUS1p-Regular.ttf", "mplus1p/OFL.txt")
# Fill order: the first font that has a code point wins. location = default instance of a variable font.
SOURCES = [
    ("notosanssymbols2/NotoSansSymbols2-Regular.ttf", "notosanssymbols2/OFL.txt", None),
    ("notosanssymbols/NotoSansSymbols%5Bwght%5D.ttf", "notosanssymbols/OFL.txt", {"wght": 400}),
    ("notosansmath/NotoSansMath-Regular.ttf", "notosansmath/OFL.txt", None),
    ("notosansjp/NotoSansJP%5Bwght%5D.ttf", "notosansjp/OFL.txt", {"wght": 400}),
    ("notoemoji/NotoEmoji%5Bwght%5D.ttf", "notoemoji/OFL.txt", {"wght": 400}),  # monochrome outlines
]
# Letterlike symbols .. miscellaneous symbols and arrows (incl. dingbats, braille), enclosed CJK and
# CJK compatibility squares. Only the BMP: whether WoW draws code points above U+FFFF is untested.
SYMBOL_RANGES = [(0x2100, 0x2BFF), (0x3200, 0x33FF)]

FAMILY = "KZZR Sans"
PS_NAME = "KZZRSans-Regular"


def fetch(rel: str) -> Path:
    CACHE.mkdir(parents=True, exist_ok=True)
    dest = CACHE / rel.replace("/", "__").replace("%5B", "[").replace("%5D", "]")
    if not dest.exists():
        print(f"downloading {rel}")
        with urllib.request.urlopen(GF + rel) as r:
            dest.write_bytes(r.read())
    return dest


def copyright_line(license_path: Path) -> str:
    return license_path.read_text(encoding="utf-8").splitlines()[0].strip()


def main() -> int:
    base = TTFont(fetch(BASE[0]))
    upm = base["head"].unitsPerEm
    cmap = base.getBestCmap()
    glyf = base["glyf"]
    hmtx = base["hmtx"].metrics
    vmtx = base["vmtx"].metrics if "vmtx" in base else None
    order = list(base.getGlyphOrder())
    wanted = [cp for a, b in SYMBOL_RANGES for cp in range(a, b + 1) if cp not in cmap]

    notices = [copyright_line(fetch(BASE[1]))]
    added: dict[int, str] = {}
    for font_rel, lic_rel, location in SOURCES:
        src = TTFont(fetch(font_rel))
        src_cmap = src.getBestCmap()
        glyphset = src.getGlyphSet(location=location) if location else src.getGlyphSet()
        scale = upm / src["head"].unitsPerEm
        count = 0
        for cp in wanted:
            if cp in added or cp not in src_cmap:
                continue
            g = glyphset[src_cmap[cp]]
            rec = DecomposingRecordingPen(glyphset)
            g.draw(rec)
            pen = TTGlyphPen(None)
            rec.replay(TransformPen(pen, (scale, 0, 0, scale, 0, 0)))
            glyph = pen.glyph()
            name = f"kzzr_uni{cp:04X}"
            glyf[name] = glyph
            glyph.recalcBounds(glyf)
            order.append(name)
            hmtx[name] = (round(g.width * scale), getattr(glyph, "xMin", 0))
            if vmtx is not None:
                vmtx[name] = (upm, 0)
            added[cp] = name
            count += 1
        print(f"{Path(fetch(font_rel)).name}: {count} glyphs")
        if count:
            notice = copyright_line(fetch(lic_rel))
            if notice not in notices:
                notices.append(notice)

    base.setGlyphOrder(order)
    glyf.glyphOrder = order
    for table in base["cmap"].tables:
        if table.isUnicode() and table.format in (4, 12):
            table.cmap.update(added)

    name_table = base["name"]
    copyright_text = "; ".join(notices) + ". Modified for Kalimdor ZugZug Radio (symbols merged)."
    for rec in list(name_table.names):
        if rec.nameID in (1, 3, 4, 6, 16, 17, 21, 22):
            name_table.removeNames(nameID=rec.nameID)
    for pid, eid, lid in ((3, 1, 0x409), (1, 0, 0)):
        name_table.setName(copyright_text, 0, pid, eid, lid)
        name_table.setName(FAMILY, 1, pid, eid, lid)
        name_table.setName("Regular", 2, pid, eid, lid)
        name_table.setName(f"{PS_NAME};KZZR", 3, pid, eid, lid)
        name_table.setName(f"{FAMILY} Regular", 4, pid, eid, lid)
        name_table.setName(PS_NAME, 6, pid, eid, lid)
    if "post" in base and base["post"].formatType == 2.0:
        base["post"].extraNames = []
        base["post"].mapping = {}

    base.save(OUT_FONT)
    license_text = fetch(BASE[1]).read_text(encoding="utf-8").split("\n", 1)[1]
    OUT_LICENSE.write_text(
        f"{FAMILY} is M+ 1p with symbols merged from Noto fonts, by Kalimdor ZugZug Radio.\n\n"
        + "\n".join(notices) + "\n" + license_text, encoding="utf-8")

    check = TTFont(OUT_FONT)
    missing = [cp for cp in added if cp not in check.getBestCmap()]
    sha = hashlib.sha1(OUT_FONT.read_bytes()).hexdigest()[:12]
    print(f"added {len(added)} of {len(wanted)} missing symbols; {OUT_FONT.name} "
          f"{OUT_FONT.stat().st_size // 1024} KB, sha1 {sha}; unmapped after save: {len(missing)}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
