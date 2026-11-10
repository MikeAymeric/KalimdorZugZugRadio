"""Generates KalimdorZugZugRadio/GameMusic.lua: the catalog of in-game music.

Developer tool, NOT for players: the generated file is committed to the repository.

1. Reads the WoW community listfile (FileDataID;path) and selects the WoW Forever and
   classic music (sound/music/forever, citymusic, musical moments, classic zones).
2. Measures each track's duration by downloading it once from wago.tools (cached in
   tools/game_music_durations.json, so later runs don't download anything again).
3. Picks a game icon as the cover (only icons present in the listfile).

Usage:  python tools/build_game_music.py [--listfile PATH] [--limit N]
Requires ffprobe (on PATH or installed with winget Gyan.FFmpeg).
"""
from __future__ import annotations

import argparse
import csv
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "KalimdorZugZugRadio" / "GameMusic.lua"
DURATIONS = Path(__file__).resolve().parent / "game_music_durations.json"
LISTFILE_URL = "https://github.com/wowdev/wow-listfile/releases/latest/download/community-listfile.csv"
WAGO_URL = "https://wago.tools/api/casc/{fid}?download"
USER_AGENT = "KalimdorZugZugRadio-catalog/1.0 (+https://github.com/MikeAymeric/KalimdorZugZugRadio)"

# Classic (vanilla) zones inside sound/music/zonemusic; the other folders belong to expansions.
CLASSIC_ZONES = {
    "barrendry", "cursedland", "desert", "enchantedforest", "evilforest", "forest", "ghostmusic", "jungle",
    "mountain", "plains", "soggyplace", "volcanic", "ahnqiraj", "naxxramas",
    "tavernalliance", "taverndwarf", "tavernhorde", "tavernhuman", "tavernnightelf", "tavernorc",
    "tavernpirate", "taverntauren", "tavernundead",
}

# Keyword in the path -> candidate icons (the first one present in the listfile wins).
ICON_RULES = [
    ("orgrimmar", ["spell_arcane_teleportorgrimmar"]),
    ("stormwind", ["spell_arcane_teleportstormwind"]),
    ("ironforge", ["spell_arcane_teleportironforge"]),
    ("darnassus", ["spell_arcane_teleportdarnassus"]),
    ("undercity", ["spell_arcane_teleportundercity"]),
    ("thunderbluff", ["spell_arcane_teleportthunderbluff"]),
    ("thunder_bluff", ["spell_arcane_teleportthunderbluff"]),
    ("pirate", ["inv_misc_bandana_03"]),
    ("tavern", ["inv_drink_05", "inv_drink_04"]),
    ("rest_area", ["inv_drink_04"]),
    ("naxx", ["achievement_dungeon_naxxramas"]),
    ("ahnqiraj", ["achievement_boss_cthun"]),
    ("silithus", ["achievement_zone_silithus_01"]),
    ("pvp", ["achievement_pvp_h_01", "achievement_pvp_a_01"]),
    ("battle", ["ability_warrior_battleshout"]),
    ("boss", ["inv_sword_04"]),
    ("dungeon", ["inv_misc_key_10"]),
    ("horror", ["spell_shadow_raisedead"]),
    ("cursed", ["achievement_zone_tirisfalglades_01", "spell_shadow_raisedead"]),
    ("evilforest", ["achievement_zone_tirisfalglades_01"]),
    ("ghost", ["spell_shadow_raisedead"]),
    ("undead", ["achievement_zone_tirisfalglades_01"]),
    ("hyjal", ["spell_nature_starfall"]),
    ("enchanted", ["achievement_zone_ashenvale_01"]),
    ("forest", ["achievement_zone_ashenvale_01"]),
    ("alpine", ["achievement_zone_alteracmountains_01"]),
    ("mountain", ["achievement_zone_alteracmountains_01"]),
    ("barren", ["achievement_zone_barrens_01"]),
    ("desert", ["achievement_zone_tanaris_01"]),
    ("jungle", ["achievement_zone_stranglethorn_01"]),
    ("soggy", ["achievement_zone_swampsorrows_01"]),
    ("swamp", ["achievement_zone_swampsorrows_01"]),
    ("wetlands", ["achievement_zone_wetlands_01"]),
    ("volcan", ["achievement_zone_burningsteppes_01", "spell_fire_volcano"]),
    ("plains", ["achievement_zone_mulgore_01", "achievement_zone_westfall_01"]),
    ("moment", ["inv_misc_note_02"]),
]
DEFAULT_ICONS = {"forever": "inv_misc_drum_01", "city": "inv_misc_map_01", "zone": "inv_misc_map_01",
                 "moments": "inv_misc_note_02"}

CITY_NAMES = {"thunderbluff": "Thunder Bluff"}


def find_tool(name: str) -> str:
    found = shutil.which(name)
    if found:
        return found
    pattern = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Microsoft", "WinGet", "Packages",
                           "Gyan.FFmpeg*", "**", "bin", f"{name}.exe")
    matches = sorted(glob.glob(pattern, recursive=True))
    if matches:
        return matches[-1]
    sys.exit(f"ERROR: {name} not found")


def download(url: str, dst: Path) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=120) as r, open(dst, "wb") as f:
        shutil.copyfileobj(r, f)


def load_listfile(path: Path) -> tuple[list[tuple[int, str]], dict[str, int]]:
    music, icons = [], {}
    with open(path, encoding="utf-8", errors="replace", newline="") as f:
        for row in csv.reader(f, delimiter=";"):
            if len(row) < 2:
                continue
            fid, p = row[0], row[1].lower()
            if p.startswith("sound/music/") and p.endswith((".mp3", ".ogg")):
                music.append((int(fid), p))
            elif p.startswith("interface/icons/") and p.endswith(".blp"):
                icons[p[len("interface/icons/"):-4]] = int(fid)
    return music, icons


def classify(path: str) -> tuple[str, str] | None:
    """(category, folder shown in-game) or None if the track should not be included."""
    parts = path.split("/")
    if len(parts) < 4:
        return None
    area = parts[2]
    if area == "forever":
        name = parts[-1]
        return "forever", "WoW Forever/" + ("New zones" if name.startswith("mus_c60_") else "Classic")
    if area == "citymusic" and len(parts) >= 5:
        city = CITY_NAMES.get(parts[3], parts[3].title())
        return "city", f"WoW Classic/Cities/{city}"
    if area == "musical moments":
        return "moments", "WoW Classic/Moments"
    if area == "zonemusic" and len(parts) >= 5 and parts[3] in CLASSIC_ZONES:
        zone = parts[3]
        if zone.startswith("tavern"):
            return "zone", f"WoW Classic/Taverns/{zone[6:].title()}"
        return "zone", f"WoW Classic/Zones/{zone.title()}"
    return None


def title_of(path: str) -> str:
    stem = Path(path).stem
    stem = re.sub(r"^mus_(c60_|c_)?", "", stem)
    words = [w for w in re.split(r"[_\-\s]+", stem) if w]
    out = []
    for w in words:
        m = re.match(r"^([a-z]+)(\d+)$", w)   # "orgrimmar01" -> "Orgrimmar 01"
        if m:
            out += [m.group(1).title(), m.group(2)]
        else:
            out.append(w.upper() if len(w) == 1 else w.title())
    return " ".join(out) or stem


def icon_of(path: str, category: str, icons: dict[str, int]) -> int | None:
    for key, candidates in ICON_RULES:
        if key in path:
            for c in candidates:
                if c in icons:
                    return icons[c]
    return icons.get(DEFAULT_ICONS.get(category, "inv_misc_drum_01"))


def lua_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--listfile", help="already downloaded community-listfile.csv (otherwise it is downloaded)")
    parser.add_argument("--limit", type=int, default=0, help="measure at most N new durations (for testing)")
    args = parser.parse_args()
    ffprobe = find_tool("ffprobe")

    tmp = Path(tempfile.mkdtemp(prefix="kzzr_ost_"))
    try:
        listfile = Path(args.listfile) if args.listfile else tmp / "community-listfile.csv"
        if not args.listfile:
            print("downloading the listfile (about 150 MB)...")
            download(LISTFILE_URL, listfile)
        music, icons = load_listfile(listfile)

        selected = []
        for fid, path in music:
            c = classify(path)
            if c:
                selected.append((fid, path, *c))
        selected.sort(key=lambda x: (x[3], x[1]))
        print(f"{len(selected)} tracks selected out of {len(music)} music files in the listfile")

        durations: dict[str, float] = json.loads(DURATIONS.read_text(encoding="utf-8")) if DURATIONS.exists() else {}
        todo = [s for s in selected if str(s[0]) not in durations]
        if args.limit:
            todo = todo[:args.limit]
        for i, (fid, path, _cat, _folder) in enumerate(todo, 1):
            f = tmp / f"{fid}.bin"
            try:
                download(WAGO_URL.format(fid=fid), f)
                res = subprocess.run([ffprobe, "-v", "error", "-show_entries", "format=duration", "-of",
                                      "default=nw=1:nk=1", str(f)], capture_output=True, text=True)
                durations[str(fid)] = round(float(res.stdout.strip()), 2)
                print(f"  [{i}/{len(todo)}] {fid} {path.split('/')[-1]}: {durations[str(fid)]}s")
            except Exception as exc:  # noqa: BLE001 - one missing file must not stop everything
                durations[str(fid)] = 0
                print(f"  [{i}/{len(todo)}] {fid} {path}: ERROR {exc}")
            finally:
                f.unlink(missing_ok=True)
            if i % 20 == 0:
                DURATIONS.write_text(json.dumps(durations, indent=0, sort_keys=True), encoding="utf-8")
            time.sleep(0.2)  # be gentle with wago.tools
        DURATIONS.write_text(json.dumps(durations, indent=0, sort_keys=True), encoding="utf-8")

        lines = [
            "-- GENERATED by tools/build_game_music.py: do not edit by hand.",
            "-- In-game music (FileDataID), played with PlayMusic(fid). icon = FileDataID of the icon.",
            "KZZR_GameMusic = {",
        ]
        kept = 0
        for fid, path, _cat, folder in selected:
            dur = durations.get(str(fid), 0)
            if dur <= 0:
                continue  # not downloadable or not measured: better not to offer it
            icon = icon_of(path, _cat, icons)
            lines.append(f"  {{ fid = {fid}, title = {lua_str(title_of(path))}, folder = {lua_str(folder)}, "
                         f"duration = {dur}" + (f", icon = {icon}" if icon else "") + " },")
            kept += 1
        lines += ["}", ""]
        OUTPUT.write_text("\n".join(lines), encoding="utf-8")
        print(f"\n{OUTPUT.relative_to(ROOT)} written: {kept} tracks.")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
