"""Generates KalimdorZugZugRadio/GameMusic.lua: the catalog of in-game music.

Developer tool, NOT for players: the generated file is committed to the repository.

1. Reads the WoW community listfile (FileDataID;path) and selects the WoW Forever and
   classic music (sound/music/forever, citymusic, musical moments, classic zones).
2. Measures each track's duration by downloading it once from wago.tools (cached in
   tools/game_music_durations.json, so later runs don't download anything again).
3. Picks a game icon as the cover (only icons present in the listfile).
4. Tags each track with a `preset` (the condition it suits: combat, boss, town...), used by the
   in-game onboarding to create ready-made playlists. --retag only redoes this step on the
   existing GameMusic.lua (no download).

Usage:  python tools/build_game_music.py [--listfile PATH] [--limit N] [--retag]
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
import urllib.error
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


# Title/folder pattern -> condition key (first match wins). Tracks matching nothing get no preset.
PRESET_RULES = [
    ("boss", r"^Dungeons Battle Boss|^Ahnqiraj King Room|^Guldansentrancetheme"),
    ("combat", r"^Battle\b|^Zulaman Battle|^Sp Templeofstormsaction"),
    ("pvp", r"^Pvp\b"),
    ("swimming", r"^Naga Incursion|^Riplash|High Seas"),
    ("dead", r"^Haunted|^Ghost|^Gloomy|^Spooky|/Ghostmusic$"),
    ("levelup", r"^Angelic|^Sacred|^Magic 0?1 Moment"),
    ("dungeon", r"^Dungeons\b|^Ahnqiraj ?(Interior|Triangle|Ruins|intro)|^Naxxramas|^Nerubian Nest|^Gnomeragon|"
                r"^Dalaran Sewer|^Zulaman Amb|^Zul ?gurub ?[Vv]oodoo|^Weavers Lair|^Silken Path|"
                r"/Zones/(Naxxramas|Ahnqiraj)$"),
    ("campfire", r"Tavern|Rest Area|^Undead Dance|/Taverns/"),
    ("town", r"/Cities/|^(Stormwind|Orgrimmar|Undercity|Thunder Bluff|Ironforge|Darnas+us|Dalaran)\b|"
             r"Hub [A-Z]$|Village [A-Z]$|^Tinkertown|^Goblin\b|^Freehold|^Warrior Terrace"),
    ("night", r"^Night\b|Walk Night|^Mystery|^Magic 0?1 Zone"),
    ("idle", r"^Day\b|Walk Day|^(Enchanted Forest|Cursed Land|Soggy Place|Stranglethorn|Hyjalextwalk|Terrokar)|"
             r"^Ahnqiraj Exterior|^Zalazanes Fall|^Swamp|^Druid Grove|General [A-Z]$|/Zones/|/New zones$"),
]


def preset_of(title: str, folder: str) -> str | None:
    for key, pattern in PRESET_RULES:
        if re.search(pattern, title) or re.search(pattern, "/" + folder):
            return key
    return None


def track_line(fid: int, title: str, folder: str, dur: float, icon: int | None) -> str:
    preset = preset_of(title, folder)
    return (f"  {{ fid = {fid}, title = {lua_str(title)}, folder = {lua_str(folder)}, duration = {dur}"
            + (f", icon = {icon}" if icon else "") + (f", preset = {lua_str(preset)}" if preset else "") + " },")


# Titles and folders of the catalog never contain quotes or backslashes (see title_of).
LINE_RE = re.compile(r'\{ fid = (\d+), title = "([^"]*)", folder = "([^"]*)", '
                     r'duration = ([\d.]+)(?:, icon = (\d+))?(?:, preset = "[^"]*")? \},')
PRESET_COMMENT = "-- preset = the condition the track suits (ready-made playlists of the onboarding)."


def retag() -> None:
    """Rewrites the presets of the existing GameMusic.lua, keeping everything else."""
    out, counts = [], {}
    for line in OUTPUT.read_text(encoding="utf-8").splitlines():
        m = LINE_RE.search(line)
        if not m:
            out.append(line)
            continue
        fid, title, folder, dur, icon = m.groups()
        out.append(track_line(int(fid), title, folder, float(dur) if "." in dur else int(dur),
                              int(icon) if icon else None))
        key = preset_of(title, folder) or "(none)"
        counts[key] = counts.get(key, 0) + 1
    if PRESET_COMMENT not in out:
        out.insert(2, PRESET_COMMENT)
    OUTPUT.write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")
    print(f"{OUTPUT.relative_to(ROOT)} retagged:", ", ".join(f"{k} {v}" for k, v in sorted(counts.items())))


# --- Retail catalog (GameMusicRetail.lua): the expansion soundtracks, loaded only on Mainline ---

RETAIL_OUTPUT = ROOT / "KalimdorZugZugRadio" / "GameMusicRetail.lua"
EXPANSIONS = {
    "cataclysm": "Cataclysm", "pandaria": "Mists of Pandaria", "draenor": "Warlords of Draenor",
    "legion": "Legion", "battleforazeroth": "Battle for Azeroth", "shadowlands": "Shadowlands",
    "dragonflight": "Dragonflight", "warwithin": "The War Within", "midnight": "Midnight",
}
# zonemusic folders that are not classic (CLASSIC_ZONES): expansion of each one.
TBC_ZONES = {"azuremyst", "bladesedge", "bloodmyst", "blacktemple", "eversong", "ghostlands", "hellfirepeninsula",
             "karazhan", "nagrand", "netherstorm", "outlandgeneral", "shadowmoonvalley", "sunwell", "tempestkeep",
             "terokkar", "zangarmarsh", "zulaman", "cavernsoftime"}
WOTLK_ZONES = {"argentcoliseum", "argenttournament", "azjolnerub", "boreantundra", "chamberoftheaspects",
               "crystalsong", "dalaran", "dragonblight", "ebon hold", "grizzlyhills", "howlingfjord",
               "icecrownglacier", "icecrownraid", "lakewintergrasp", "nexus", "northrend", "sholazarbasin",
               "stormpeaks", "stratholmepast", "ulduar", "ulduarraidext", "ulduarraidint", "utgarde keep",
               "violethold", "zuldrak"}
OTHER_DIRS = {"event": "World of Warcraft/Events", "worldevents": "World of Warcraft/Events",
              "petbattles": "World of Warcraft/Pet Battles", "gluescreenmusic": "World of Warcraft/Main themes"}
# Short jingles: not worth a slot in a playlist.
RETAIL_MIN_SECONDS = 30
RETAIL_SKIP = re.compile(r"stinger|_sting\b|_sting_")


def pretty(word: str) -> str:
    return " ".join(w.title() for w in re.split(r"[_\-\s]+", word) if w)


def classify_retail(path: str) -> tuple[str, str] | None:
    """(area, folder shown in-game) for an expansion track, or None."""
    parts = path.split("/")
    if len(parts) < 4 or RETAIL_SKIP.search(parts[-1]):
        return None
    area = parts[2]
    if area in EXPANSIONS:
        stem = re.sub(r"^(mus|zone)_(\d+_)?", "", Path(parts[-1]).stem)
        zone = re.sub(r"\d+$", "", stem.split("_")[0]) or stem
        return area, f"{EXPANSIONS[area]}/{pretty(zone)}"
    if area == "zonemusic" and len(parts) >= 5:
        zone = parts[3]
        if zone in TBC_ZONES:
            return area, f"The Burning Crusade/{pretty(zone)}"
        if zone in WOTLK_ZONES:
            return area, f"Wrath of the Lich King/{pretty(zone)}"
        if zone == "wanderingisle":
            return area, "Mists of Pandaria/Wandering Isle"
        if zone in ("brewfest", "darkmoonfaire"):
            return area, "World of Warcraft/Events"
        return None
    if area in OTHER_DIRS:
        return area, OTHER_DIRS[area]
    return None


def retail_title(path: str) -> str:
    stem = re.sub(r"^(mus|zone)_(\d+_)?", "", Path(path).stem)
    out = []
    for w in (w for w in re.split(r"[_\-\s]+", stem) if w):
        m = re.match(r"^([a-z]+)(\d+)$", w)
        out += [m.group(1).title(), m.group(2)] if m else [w.upper() if len(w) <= 2 else w.title()]
    return " ".join(out) or stem


# Conditions that exist on Retail (no campfire). Matched on the lowercase path; first match wins,
# everything else is "idle".
RETAIL_RAIDS = ("icecrownraid", "blacktemple", "karazhan", "sunwell", "ulduar", "tempestkeep", "azjolnerub",
                "nexus", "violethold", "utgarde", "zulaman", "cavernsoftime", "stratholmepast", "argentcoliseum",
                "chamberoftheaspects")
RETAIL_PRESETS = [
    ("boss", r"boss"),
    ("combat", r"combat|battle|fight|assault|_war_|warfront|invasion"),
    ("pvp", r"pvp|battleground|arena|wintergrasp"),
    ("dead", r"death|haunted|ghost|graveyard|maldraxxus|revendreth|torghast|maw"),
    ("dungeon", r"dungeon|raid|_inst|delve|" + "|".join(RETAIL_RAIDS)),
    ("town", r"valdrakken|dornogal|oribos|boralus|dazaralor|dalaran|shrine|stormshield|warspear|tavern|_inn|"
             r"town|city|silvermoon|housing|neighborhood|garrison|brewfest|darkmoon|petbattles"),
    ("night", r"night"),
]


def retail_preset(path: str) -> str:
    for key, pattern in RETAIL_PRESETS:
        if re.search(pattern, path):
            return key
    return "idle"


def write_retail(music: list[tuple[int, str]], durations: dict[str, float], icons: dict[str, int]) -> None:
    lines = [
        "-- GENERATED by tools/build_game_music.py --retail: do not edit by hand.",
        "-- The expansion soundtracks (FileDataID), only on Retail: WoW Forever doesn't have these files.",
        PRESET_COMMENT,
        "if WOW_PROJECT_ID ~= 1 then return end -- 1 = Mainline (Retail)",
        "KZZR_GameMusicRetail = {",
    ]
    kept, counts = 0, {}
    for fid, path, _area, folder in music:
        dur = durations.get(str(fid), 0)
        if dur < RETAIL_MIN_SECONDS:
            continue  # not measured, not downloadable, or a jingle
        preset = retail_preset(path)
        counts[preset] = counts.get(preset, 0) + 1
        icon = icon_of(path, "zone", icons)
        lines.append(f"  {{ fid = {fid}, title = {lua_str(retail_title(path))}, folder = {lua_str(folder)}, "
                     f"duration = {dur}" + (f", icon = {icon}" if icon else "") + f", preset = {lua_str(preset)} }},")
        kept += 1
    lines += ["}", ""]
    RETAIL_OUTPUT.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print(f"\n{RETAIL_OUTPUT.relative_to(ROOT)} written: {kept} tracks (",
          ", ".join(f"{k} {v}" for k, v in sorted(counts.items())), ")")


def lua_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def load_durations() -> dict[str, float]:
    return json.loads(DURATIONS.read_text(encoding="utf-8")) if DURATIONS.exists() else {}


def measure(todo: list[tuple], durations: dict[str, float], ffprobe: str, tmp: Path) -> None:
    """Downloads each (fid, path, ...) once and stores its duration (0 = not downloadable)."""
    for i, (fid, path, *_rest) in enumerate(todo, 1):
        f = tmp / f"{fid}.bin"
        try:
            for attempt in range(5):  # rate limited (429): wait and retry instead of losing the track
                try:
                    download(WAGO_URL.format(fid=fid), f)
                    break
                except urllib.error.HTTPError as exc:
                    if exc.code != 429 or attempt == 4:
                        raise
                    print(f"  rate limited, waiting {30 * (attempt + 1)} s...", flush=True)
                    time.sleep(30 * (attempt + 1))
            res = subprocess.run([ffprobe, "-v", "error", "-show_entries", "format=duration", "-of",
                                  "default=nw=1:nk=1", str(f)], capture_output=True, text=True)
            durations[str(fid)] = round(float(res.stdout.strip()), 2)
            print(f"  [{i}/{len(todo)}] {fid} {path.split('/')[-1]}: {durations[str(fid)]}s", flush=True)
        except Exception as exc:  # noqa: BLE001 - one missing file must not stop everything
            durations[str(fid)] = 0
            print(f"  [{i}/{len(todo)}] {fid} {path}: ERROR {exc}", flush=True)
        finally:
            f.unlink(missing_ok=True)
        if i % 20 == 0:
            DURATIONS.write_text(json.dumps(durations, indent=0, sort_keys=True), encoding="utf-8")
        time.sleep(0.2)  # be gentle with wago.tools
    DURATIONS.write_text(json.dumps(durations, indent=0, sort_keys=True), encoding="utf-8")


def build_retail(args: argparse.Namespace) -> None:
    ffprobe = find_tool("ffprobe")
    tmp = Path(tempfile.mkdtemp(prefix="kzzr_ost_"))
    try:
        listfile = Path(args.listfile) if args.listfile else tmp / "community-listfile.csv"
        if not args.listfile:
            print("downloading the listfile (about 150 MB)...")
            download(LISTFILE_URL, listfile)
        music, icons = load_listfile(listfile)
        selected = sorted(((fid, path, *c) for fid, path in music if (c := classify_retail(path))),
                          key=lambda x: (x[3], x[1]))
        print(f"{len(selected)} expansion tracks selected out of {len(music)} music files in the listfile")
        durations = load_durations()
        areas = {a.strip() for a in args.areas.split(",")} if args.areas else None
        todo = [s for s in selected if str(s[0]) not in durations and (areas is None or s[2] in areas)]
        if args.limit:
            todo = todo[:args.limit]
        print(f"{len(todo)} to measure")
        measure(todo, durations, ffprobe, tmp)
        write_retail(selected, durations, icons)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--listfile", help="already downloaded community-listfile.csv (otherwise it is downloaded)")
    parser.add_argument("--limit", type=int, default=0, help="measure at most N new durations (for testing)")
    parser.add_argument("--retag", action="store_true", help="only recompute the presets of the existing GameMusic.lua")
    parser.add_argument("--retail", action="store_true",
                        help="build GameMusicRetail.lua (expansion soundtracks) instead of GameMusic.lua")
    parser.add_argument("--areas", help="with --retail: download only these sound/music folders, comma separated "
                                        "(e.g. dragonflight); the output still lists every track already measured")
    args = parser.parse_args()
    if args.retag:
        retag()
        return
    if args.retail:
        build_retail(args)
        return
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

        durations = load_durations()
        todo = [s for s in selected if str(s[0]) not in durations]
        if args.limit:
            todo = todo[:args.limit]
        measure(todo, durations, ffprobe, tmp)

        lines = [
            "-- GENERATED by tools/build_game_music.py: do not edit by hand.",
            "-- In-game music (FileDataID), played with PlayMusic(fid). icon = FileDataID of the icon.",
            PRESET_COMMENT,
            "KZZR_GameMusic = {",
        ]
        kept = 0
        for fid, path, _cat, folder in selected:
            dur = durations.get(str(fid), 0)
            if dur <= 0:
                continue  # not downloadable or not measured: better not to offer it
            icon = icon_of(path, _cat, icons)
            lines.append(track_line(fid, title_of(path), folder, dur, icon))
            kept += 1
        lines += ["}", ""]
        OUTPUT.write_text("\n".join(lines), encoding="utf-8", newline="\n")
        print(f"\n{OUTPUT.relative_to(ROOT)} written: {kept} tracks.")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
