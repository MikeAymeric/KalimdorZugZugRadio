"""Imports music (and podcasts) for Kalimdor ZugZug Radio.

Your music lives in a separate folder next to the addon, AddOns/KalimdorZugZugRadio_Library/
(a tiny data addon created by this script), so updating the addon (e.g. with the CurseForge
app, which replaces the addon folder) never deletes it. Files dropped into the old
KalimdorZugZugRadio/music/ folder are moved there.

Recursively scans KalimdorZugZugRadio_Library/music/ (subfolders are only for organizing:
playlists are created in-game), converts formats WoW can't play (mp4, m4a, flac,
wav, ...) to OGG, extracts covers (embedded, or cover.jpg/folder.jpg in the folder)
as deduplicated 256x256 PNGs, measures each track's loudness (so the addon can even out the
volume) and generates KalimdorZugZugRadio_Library/Library.lua.

Usage:  python import_music.py [--addon FOLDER] [--keep-originals] [--keep-names] [--podcasts]
        (with no options, in a window, it shows a menu; --help lists every option)
The addon folder is found automatically: the folder you run the script from, then the
addon installed in World of Warcraft on this PC (Windows registry and usual locations,
WoW Forever first). If it isn't found, pass it with --addon "path/to/KalimdorZugZugRadio".
Requires ffmpeg and ffprobe (on PATH or installed with winget Gyan.FFmpeg). If they are missing,
on Windows the script offers to download them into %LOCALAPPDATA%/KalimdorZugZugRadio/ffmpeg.
"""
from __future__ import annotations

import argparse
import unicodedata
import glob
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path

ADDON_NAME = "KalimdorZugZugRadio"
DATA_ADDON_NAME = "KalimdorZugZugRadio_Library"  # the user's data, next to the addon (see the docstring)
# Set by set_addon_dir() in main().
ADDON_DIR = DATA_DIR = MUSIC_DIR = COVERS_DIR = LIBRARY_FILE = ORIGINALS_DIR = Path()


FLAVOR_PREFERENCE = ["_forever_", "_retail_", "_classic_era_", "_classic_", "_anniversary_"]


def _check_addon(p: Path) -> Path | None:
    if (p / f"{ADDON_NAME}.toc").is_file():
        return p
    if (p / ADDON_NAME / f"{ADDON_NAME}.toc").is_file():
        return p / ADDON_NAME
    return None


def wow_roots() -> list[Path]:
    """Possible World of Warcraft install folders on this PC (registry first, then usual locations)."""
    roots: list[Path] = []
    if sys.platform == "win32":
        try:
            import winreg
            for hive, key in ((winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft"),
                              (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Blizzard Entertainment\World of Warcraft"),
                              (winreg.HKEY_CURRENT_USER, r"SOFTWARE\Blizzard Entertainment\World of Warcraft")):
                try:
                    with winreg.OpenKey(hive, key) as k:
                        path = Path(winreg.QueryValueEx(k, "InstallPath")[0])
                        # InstallPath usually points to a flavor folder such as ...\_retail_\
                        roots.append(path.parent if path.name.startswith("_") else path)
                except OSError:
                    pass
        except ImportError:
            pass
        drives = [Path(f"{d}:\\") for d in "CDEFGHIJKLMNOPQRSTUVWXYZ" if os.path.exists(f"{d}:\\")]
        for drive in drives:
            for sub in ("World of Warcraft", r"Games\World of Warcraft", r"Program Files (x86)\World of Warcraft",
                        r"Program Files\World of Warcraft", r"Blizzard\World of Warcraft", r"Battle.net\World of Warcraft",
                        r"Games\Blizzard\World of Warcraft"):
                roots.append(drive / sub)
    else:
        roots += [Path("/Applications/World of Warcraft"), Path.home() / "Applications/World of Warcraft",
                  Path.home() / "Games/world-of-warcraft/drive_c/Program Files (x86)/World of Warcraft"]
    seen, result = set(), []
    for r in roots:
        key = str(r).lower()
        if key not in seen and r.is_dir():
            seen.add(key)
            result.append(r)
    return result


def installed_addons() -> list[Path]:
    """KalimdorZugZugRadio folders installed in the game's AddOns, WoW Forever first."""
    found = []
    for root in wow_roots():
        flavors = sorted((d for d in root.iterdir() if d.is_dir() and d.name.startswith("_") and d.name.endswith("_")),
                         key=lambda d: FLAVOR_PREFERENCE.index(d.name) if d.name in FLAVOR_PREFERENCE else 99)
        for flavor in flavors:
            addon = _check_addon(flavor / "Interface" / "AddOns")
            if addon and addon not in found:
                found.append(addon)
    return found


def find_addon_dir(explicit: str | None) -> Path | None:
    """The folder containing KalimdorZugZugRadio.toc.

    Order: --addon, the current folder (and its parents), the addon installed in World of
    Warcraft (searched on this PC), and finally the script's own location (development).
    """
    if explicit:
        return _check_addon(Path(explicit).expanduser().resolve())
    start = Path.cwd().resolve()
    for p in (start, *start.parents):
        found = _check_addon(p)
        if found:
            return found
    installed = installed_addons()
    if installed:
        if len(installed) > 1:
            others = ", ".join(str(a) for a in installed[1:])
            print(f"Found the addon in several game folders, using the first one (others: {others}).\n"
                  f"Use --addon to pick another one.")
        return installed[0]
    here = Path(__file__).resolve().parent
    for p in (here, *here.parents):
        found = _check_addon(p)
        if found:
            return found
    return None


def set_addon_dir(path: Path) -> None:
    global ADDON_DIR, DATA_DIR, MUSIC_DIR, COVERS_DIR, LIBRARY_FILE, ORIGINALS_DIR
    ADDON_DIR = path
    DATA_DIR = ADDON_DIR.parent / DATA_ADDON_NAME
    MUSIC_DIR = DATA_DIR / "music"
    COVERS_DIR = DATA_DIR / "covers"
    LIBRARY_FILE = DATA_DIR / "Library.lua"
    ORIGINALS_DIR = MUSIC_DIR / "_originals"


# --- Data addon -------------------------------------------------------------------
# Until 0.7 everything lived inside the addon folder, which addon managers replace on update.
# The data addon is a separate folder that no package contains, so updates never touch it.
MOVED_ITEMS = ["music", "covers", "podcasts.txt", "podcast.txt", "import_settings.json"]
MERGED_JSON = {"_original_names.json", "_index.json"}  # name maps: merged when both sides have one
LEGACY_LIBRARY = """-- Kept for compatibility. Since 0.8 your music library is in the separate folder
-- AddOns\\KalimdorZugZugRadio_Library (created by Import music.py), which addon updates never touch.
KZZR_Library = KZZR_Library or { tracks = {} }
"""


def interface_version() -> str:
    for line in (ADDON_DIR / f"{ADDON_NAME}.toc").read_text(encoding="utf-8-sig").splitlines():
        if line.startswith("## Interface:"):
            return line.split(":", 1)[1].strip()
    return "16001"


def ensure_data_addon() -> None:
    """Creates KalimdorZugZugRadio_Library (folder, .toc, Library.lua) if missing."""
    (DATA_DIR / "music").mkdir(parents=True, exist_ok=True)
    toc = DATA_DIR / f"{DATA_ADDON_NAME}.toc"
    text = (f"## Interface: {interface_version()}\n"
            "## Title: Kalimdor ZugZug Radio - My Music\n"
            "## Notes: Your music for Kalimdor ZugZug Radio, created by Import music.py. Keep it enabled. "
            "Addon updates never touch this folder.\n"
            "## IconTexture: Interface\\Icons\\INV_Misc_Drum_01\n"
            "\nLibrary.lua\n")
    if not toc.is_file() or toc.read_text(encoding="utf-8-sig") != text:
        toc.write_text(text, encoding="utf-8")
    if not LIBRARY_FILE.is_file():
        write_library([])


def move_merge(src: Path, dst: Path, stats: dict) -> None:
    """Moves src to dst; folders are merged, never overwriting an existing file."""
    if not dst.exists():
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(src), str(dst))
        stats["moved"] += 1
    elif src.is_dir() and dst.is_dir():
        for child in list(src.iterdir()):
            move_merge(child, dst / child.name, stats)
        try:
            src.rmdir()
        except OSError:
            pass
    elif src.name in MERGED_JSON:
        merged = json.loads(src.read_text(encoding="utf-8"))
        merged.update(json.loads(dst.read_text(encoding="utf-8")))
        dst.write_text(json.dumps(merged, ensure_ascii=False, indent=1, sort_keys=True), encoding="utf-8")
        src.unlink()
    elif src.is_file() and dst.is_file() and src.stat().st_size == dst.stat().st_size:
        src.unlink()  # same file already moved
    else:
        stats["warnings"].append(f"{src}: not moved, {dst} already exists")


def migrate_to_data_addon(stats: dict) -> None:
    """Moves the user's files from the addon folder (layout <= 0.7, or files dropped into its music
    folder) into the data addon. A rename on the same drive, so it is instant even for many GB."""
    found = [ADDON_DIR / n for n in MOVED_ITEMS if (ADDON_DIR / n).exists()]
    found = [f for f in found if not (f.is_dir() and not any(f.iterdir()))]
    if not found:
        return
    print(f"Moving your files to {DATA_DIR} (addon updates never touch it):")
    for src in found:
        print(f"  {src.name}")
        move_merge(src, DATA_DIR / src.name, stats)
    (ADDON_DIR / "music").mkdir(exist_ok=True)  # stays as a drop folder
    old_library = ADDON_DIR / "Library.lua"
    if old_library.is_file() and old_library.read_text(encoding="utf-8") != LEGACY_LIBRARY:
        old_library.write_text(LEGACY_LIBRARY, encoding="utf-8")
    print()

NATIVE = {".ogg", ".mp3"}
CONVERT = {".mp4", ".m4a", ".aac", ".flac", ".wav", ".webm", ".opus", ".wma",
           ".mkv", ".mov", ".aiff", ".aif", ".alac", ".oga"}
FOLDER_COVERS = ["cover", "folder", "front", "album"]
IMAGE_EXT = [".jpg", ".jpeg", ".png", ".webp"]
COVER_SIZE = 256


# ffmpeg: found on PATH, in the folder setup_ffmpeg() downloads it to, or where winget put it.
# Set by setup_ffmpeg() in main().
FFMPEG = FFPROBE = ""
LOCAL_FFMPEG_DIR = Path(os.environ.get("LOCALAPPDATA") or Path.home()) / ADDON_NAME / "ffmpeg"
# Gyan's Windows builds (the ones winget's Gyan.FFmpeg installs), published on GitHub with a sha256
FFMPEG_RELEASE_API = "https://api.github.com/repos/GyanD/codexffmpeg/releases/latest"
FFMPEG_ASSET_SUFFIX = "-essentials_build.zip"
FFMPEG_MAX_BYTES = 500 * 1024 * 1024


def find_tool(name: str) -> str | None:
    found = shutil.which(name)
    if found:
        return found
    local = LOCAL_FFMPEG_DIR / (name + ".exe" if os.name == "nt" else name)
    if local.is_file():
        return str(local)
    pattern = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Microsoft", "WinGet", "Packages",
                           "Gyan.FFmpeg*", "**", "bin", f"{name}.exe")
    matches = sorted(glob.glob(pattern, recursive=True))
    return matches[-1] if matches else None


def print_ffmpeg_help() -> None:
    print(" You can also install ffmpeg yourself:")
    if os.name == "nt":
        print("   open the Start menu, type cmd, open \"Command Prompt\" and run:  winget install Gyan.FFmpeg")
        print("   then run this script again.")
    elif sys.platform == "darwin":
        print("   install Homebrew (https://brew.sh), then run in Terminal:  brew install ffmpeg")
    else:
        print("   with your package manager, for example:  sudo apt install ffmpeg")


def download_ffmpeg(progress=None) -> bool:
    """Downloads Gyan's ffmpeg build from GitHub into LOCAL_FFMPEG_DIR (only ffmpeg.exe and
    ffprobe.exe are kept). Checks the sha256 GitHub publishes for the file. Windows only.
    progress(bytes_done, bytes_total) replaces the printed progress (used by the window)."""
    import urllib.request
    import zipfile
    try:
        info = json.loads(http_get(FFMPEG_RELEASE_API) or b"{}")
        asset = next((a for a in info.get("assets", []) if a.get("name", "").endswith(FFMPEG_ASSET_SUFFIX)), None)
        if not asset:
            raise RuntimeError("no ffmpeg download found in the latest release")
        url = asset.get("browser_download_url", "")
        if not url.startswith("https://github.com/"):
            raise RuntimeError(f"unexpected download address: {url[:80]}")
        total = int(asset.get("size") or 0)
        if total > FFMPEG_MAX_BYTES:
            raise RuntimeError("the download is too large")
        LOCAL_FFMPEG_DIR.mkdir(parents=True, exist_ok=True)
        part = LOCAL_FFMPEG_DIR / "download.zip.part"
        digest = hashlib.sha256()
        written = 0
        print(f" Downloading {asset['name']} ({total / 1048576:.0f} MB)...")
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=60) as r, open(part, "wb") as f:
            while chunk := r.read(1024 * 256):
                written += len(chunk)
                if written > FFMPEG_MAX_BYTES:
                    raise RuntimeError("the download is too large")
                digest.update(chunk)
                f.write(chunk)
                if progress:
                    progress(written, total)
                elif total:
                    print(f"\r   {written / 1048576:5.0f} / {total / 1048576:.0f} MB  ({written * 100 // total}%)",
                          end="", flush=True)
        print()
        expected = str(asset.get("digest") or "")
        if expected.startswith("sha256:") and digest.hexdigest() != expected[7:].lower():
            raise RuntimeError("the downloaded file is damaged (checksum mismatch), try again")
        print(" Extracting...")
        with zipfile.ZipFile(part) as z:
            for exe in ("ffmpeg.exe", "ffprobe.exe"):
                member = next((m for m in z.namelist() if m.endswith("/bin/" + exe)), None)
                if not member:
                    raise RuntimeError(f"{exe} is not in the download")
                tmp = LOCAL_FFMPEG_DIR / (exe + ".part")
                with z.open(member) as src, open(tmp, "wb") as dst:
                    shutil.copyfileobj(src, dst)
                os.replace(tmp, LOCAL_FFMPEG_DIR / exe)
        part.unlink()
        return True
    except (OSError, ValueError, RuntimeError, zipfile.BadZipFile) as exc:
        print(f"\n ERROR: ffmpeg could not be downloaded ({exc}).")
        for leftover in LOCAL_FFMPEG_DIR.glob("*.part"):
            try:
                leftover.unlink()
            except OSError:
                pass
        return False


def setup_ffmpeg() -> None:
    """Finds ffmpeg/ffprobe; if they are missing, offers to download them (Windows) or explains how
    to install them, and exits if they still aren't there."""
    global FFMPEG, FFPROBE
    FFMPEG, FFPROBE = find_tool("ffmpeg") or "", find_tool("ffprobe") or ""
    if FFMPEG and FFPROBE:
        return
    print("=" * 72)
    print(" ffmpeg is needed")
    print("=" * 72)
    print(" This script uses ffmpeg, a free program, to convert your music and read its titles and")
    print(" covers. It is not installed on this PC yet.\n")
    if os.name == "nt":
        print(" It can be downloaded now (about 110 MB, from github.com/GyanD/codexffmpeg) into")
        print(f"   {LOCAL_FFMPEG_DIR}")
        print(" Nothing else on your PC is changed: to remove it, just delete that folder.\n")
        if ask(" Download ffmpeg now? Press Enter for yes, or type N for no: ").lower() in ("", "y", "yes"):
            print()
            if download_ffmpeg():
                FFMPEG, FFPROBE = find_tool("ffmpeg") or "", find_tool("ffprobe") or ""
                if FFMPEG and FFPROBE:
                    print(" ffmpeg is ready.\n")
                    return
        print()
    print_ffmpeg_help()
    sys.exit(1)


if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


# ffmpeg/ffprobe never get a console window of their own: started from the window (pythonw, no
# console), Windows would otherwise flash a new terminal for every file.
NO_WINDOW = {"creationflags": subprocess.CREATE_NO_WINDOW} if os.name == "nt" else {}


def run(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace", **NO_WINDOW)


def probe(path: Path) -> dict:
    res = run([FFPROBE, "-v", "error", "-print_format", "json", "-show_format", "-show_streams", str(path)])
    if res.returncode != 0:
        raise RuntimeError(res.stderr.strip() or "ffprobe failed")
    return json.loads(res.stdout or "{}")


def tags_of(info: dict) -> dict:
    """Lower-case tags from the format + audio stream (OGG stores them on the stream)."""
    tags: dict[str, str] = {}
    for stream in info.get("streams", []):
        if stream.get("codec_type") == "audio":
            for k, v in (stream.get("tags") or {}).items():
                tags.setdefault(k.lower(), v)
    for k, v in (info.get("format", {}).get("tags") or {}).items():
        tags[k.lower()] = v
    return tags


MP4_EXT = {".mp4", ".m4a", ".m4b", ".m4v", ".mov", ".3gp"}
MP4_CONTAINERS = {b"moov", b"udta", b"ilst"}


def mp4_genre(path: Path) -> str | None:
    """The text genre of an MP4/M4A file (iTunes '\\xa9gen' atom, or a text 'gnre').

    Store-bought files often carry the genre as text in 'gnre' too, which ffmpeg decodes as an
    ID3v1 genre number (its second character): "Game Soundtrack" becomes "Big Band". So the genre of
    these files is read here, seeking from atom to atom (the audio data is never read)."""
    found: dict[bytes, str] = {}

    def walk(f, start: int, end: int, parent: bytes) -> None:
        pos = start
        while pos + 8 <= end:
            f.seek(pos)
            head = f.read(16)
            if len(head) < 8:
                return
            size, kind = int.from_bytes(head[:4], "big"), head[4:8]
            header = 8
            if size == 1 and len(head) == 16:
                size, header = int.from_bytes(head[8:16], "big"), 16
            elif size == 0:
                size = end - pos
            if size < header:
                return
            body = pos + header
            if kind == b"meta":
                walk(f, body + 4, pos + size, kind)  # 4 bytes of version/flags first
            elif kind in MP4_CONTAINERS:
                walk(f, body, pos + size, kind)
            elif parent == b"ilst" and kind in (b"\xa9gen", b"gnre") and size < 4096:
                f.seek(body)
                data = f.read(size - header)
                # child 'data' atom: size(4) 'data' type(4) locale(4) payload; type 1 = UTF-8 text
                if len(data) >= 16 and data[4:8] == b"data" and int.from_bytes(data[8:12], "big") & 0xFFFFFF == 1:
                    text = data[16:int.from_bytes(data[:4], "big")].decode("utf-8", "replace").replace("\x00", "").strip()
                    if text:
                        found[kind] = text
            pos += size

    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            walk(f, 0, f.tell(), b"")
    except OSError:
        return None
    return found.get(b"\xa9gen") or found.get(b"gnre")


def genre_of(path: Path, tags: dict) -> str:
    """The track's genre: from the MP4 atoms for MP4 files, from the tags otherwise."""
    if path.suffix.lower() in MP4_EXT:
        g = mp4_genre(path)
        if g:
            return g
    return (tags.get("genre") or "").strip()


def number_of(value: str | None) -> int | None:
    """'3/12' -> 3, '2008-05-01' -> 2008 (the first number), None if there is none."""
    m = re.match(r"\s*(\d+)", value or "")
    return int(m.group(1)) if m else None


def year_of(tags: dict) -> int | None:
    m = re.search(r"(1[89]\d\d|2\d\d\d)", tags.get("date") or tags.get("year") or "")
    return int(m.group(1)) if m else None


def duration_of(info: dict) -> float:
    candidates = [info.get("format", {}).get("duration")]
    candidates += [s.get("duration") for s in info.get("streams", []) if s.get("codec_type") == "audio"]
    for c in candidates:
        try:
            if c and float(c) > 0:
                return round(float(c), 2)
        except ValueError:
            pass
    return 0.0


def attached_pic_index(info: dict) -> int | None:
    for s in info.get("streams", []):
        if s.get("codec_type") == "video" and (s.get("disposition") or {}).get("attached_pic") == 1:
            return int(s["index"])
    return None


COVER_FILTER = (f"scale={COVER_SIZE}:{COVER_SIZE}:force_original_aspect_ratio=decrease,"
                f"pad={COVER_SIZE}:{COVER_SIZE}:(ow-iw)/2:(oh-ih)/2:color=black")


# --- Deduplicated covers ------------------------------------------------------
# Each cover is scaled to 256x256 and identified by the hash of its pixels: tracks with
# the same image point to the same PNG. covers/_index.json remembers which cover each
# track has, so it isn't re-extracted on every run.
COVER_INDEX_NAME = "_index.json"
cover_index: dict[str, dict] = {}  # key (track path or "folder:<dir>") -> {"cover", "mtime"}
seen_cover_keys: set[str] = set()

# What ffprobe said about each playable track, so a rerun doesn't probe ~2000 unchanged files again:
# music/_probe_cache.json, track id -> {"stamp": [size, mtime], "info": slim probe, "genre"}.
# A changed size or mtime (or a renamed file) probes again; tracks not seen in a run are dropped.
PROBE_CACHE_NAME = "_probe_cache.json"
probe_cache: dict[str, dict] = {}
probe_cache_seen: dict[str, dict] = {}


def load_probe_cache() -> None:
    global probe_cache
    probe_cache_seen.clear()
    try:
        probe_cache = json.loads((MUSIC_DIR / PROBE_CACHE_NAME).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        probe_cache = {}


def save_probe_cache() -> None:
    try:
        (MUSIC_DIR / PROBE_CACHE_NAME).write_text(json.dumps(probe_cache_seen, ensure_ascii=False),
                                                  encoding="utf-8")
    except OSError as exc:
        print(f"  WARNING: {PROBE_CACHE_NAME} not saved ({exc})")


def slim_info(info: dict) -> dict:
    """Only what tags_of/duration_of/attached_pic_index read."""
    streams = []
    for s in info.get("streams", []):
        keep = {"index": s.get("index"), "codec_type": s.get("codec_type"), "duration": s.get("duration"),
                "disposition": {"attached_pic": (s.get("disposition") or {}).get("attached_pic", 0)}}
        if s.get("codec_type") == "audio":
            keep["tags"] = s.get("tags") or {}
        streams.append(keep)
    fmt = info.get("format", {})
    return {"format": {"duration": fmt.get("duration"), "tags": fmt.get("tags") or {}}, "streams": streams}


def cached_probe(path: Path, rel: str) -> tuple[dict, str]:
    """(probe info, genre) of a playable track, from the cache when the file hasn't changed."""
    st = path.stat()
    stamp = [st.st_size, st.st_mtime]
    entry = probe_cache.get(rel)
    if not (entry and entry.get("stamp") == stamp and "info" in entry):
        info = slim_info(probe(path))
        entry = {"stamp": stamp, "info": info, "genre": genre_of(path, tags_of(info))}
    probe_cache_seen[rel] = entry
    return entry["info"], entry.get("genre", "")


def cached_original(rel: str, src: Path, field: str, compute):
    """compute(src) for the original of track rel in the music library (genre, cover stream), cached
    in the track's probe-cache entry while the original's size and mtime don't change."""
    st = src.stat()
    stamp = [st.st_size, st.st_mtime]
    entry = probe_cache_seen.get(rel)
    if entry is None:
        return compute(src)
    saved = entry.get(field)
    if saved and saved.get("stamp") == stamp:
        return saved.get("value")
    value = compute(src)
    entry[field] = {"stamp": stamp, "value": value}
    return value


# --- Loudness (volume normalization) ------------------------------------------------
# WoW has one Music volume for everything, so some tracks sound louder than others. The import
# measures each track's integrated loudness (EBU R128, in LUFS) with ffmpeg's ebur128 filter and
# writes it to Library.lua ("loudness"); in-game the volume of each track is corrected towards the
# median of the library (Player.lua). The files are never changed. The value is cached in the
# track's probe-cache entry, so only new or changed tracks are measured.
LOUDNESS_RE = re.compile(r"I:\s+(-?\d+(?:\.\d+)?) LUFS")
# the per-frame lines ("t: 12.3 ... S: -14.2 ...") give the loudness curve, one value per second,
# used to recognise the same recording under another name (find_duplicates in library_tools.py)
FRAME_RE = re.compile(r"t:\s*(\d+(?:\.\d+)?)\s.*?S:\s*(-?\d+(?:\.\d+)?)")
SILENT_LUFS = -60.0  # quieter than this = silence or a broken measure: no correction
LOUDNESS_WORKERS = max(1, min(6, (os.cpu_count() or 2) - 1))


def measure_loudness(path: Path) -> tuple[float | None, list[int]]:
    """(integrated loudness in LUFS or None if ffmpeg can't measure it, short-term loudness curve:
    one rounded value per second)."""
    res = run([FFMPEG, "-hide_banner", "-nostats", "-i", str(path), "-vn", "-sn", "-dn",
               "-af", "ebur128", "-f", "null", "-"])
    err = res.stderr or ""
    found = LOUDNESS_RE.findall(err)
    if res.returncode != 0 or not found:
        return None, []
    curve: list[int] = []
    for t, short in FRAME_RE.findall(err):
        if float(t) >= len(curve) + 1:  # the first frame past each whole second
            curve.append(max(-70, round(float(short))))
    return float(found[-1]), curve  # the summary comes last


def combined_loudness(values: list[tuple[float, float]]) -> float | None:
    """Loudness of several parts played one after the other: (lufs, seconds) averaged as energy."""
    usable = [(lufs, sec) for lufs, sec in values if lufs > SILENT_LUFS and sec > 0]
    total = sum(sec for _, sec in usable)
    if not total:
        return None
    return 10 * math.log10(sum(sec * 10 ** (lufs / 10) for lufs, sec in usable) / total)


def add_loudness(tracks: list[dict], stats: dict, measure_new: bool = True, progress=None) -> int:
    """Sets t["loudness"] on every track, measuring the ones not in the probe cache yet (in parallel;
    measure_new=False only uses the cache). A podcast episode gets one value for all its parts.
    Returns how many files were measured."""
    # the curve came in 2.0: tracks measured by 1.6 are measured again once
    todo = [t for t in tracks if not t.get("episode")
            and not {"lufs", "curve"} <= probe_cache_seen.get(t["file"], {"lufs": 0, "curve": 0}).keys()]
    todo += [t for t in tracks if t.get("episode") and "lufs" not in probe_cache_seen.get(t["file"], {"lufs": 0})]
    if measure_new and todo:
        print(f"\nMeasuring the volume of {len(todo)} track{'' if len(todo) == 1 else 's'} "
              f"(only once; {LOUDNESS_WORKERS} at a time) ...")
        done = 0
        with ThreadPoolExecutor(LOUDNESS_WORKERS) as pool:
            futures = {pool.submit(measure_loudness, DATA_DIR / t["file"].replace("\\", "/")): t for t in todo}
            for fut in as_completed(futures):
                t = futures[fut]
                try:
                    lufs, curve = fut.result()
                except Exception:  # noqa: BLE001
                    lufs, curve = None, []
                if lufs is None:
                    stats["warnings"].append(f"{t['file']}: the volume could not be measured")
                entry = probe_cache_seen[t["file"]]
                entry["lufs"] = lufs  # None is cached too: not retried every run
                if not t.get("episode"):
                    entry["curve"] = curve
                done += 1
                if progress:
                    progress(done, len(todo), t["folder"] or "(music)", "loudness")
                if done % 100 == 0:
                    print(f"  {done}/{len(todo)}")
    episodes: dict[str, list[tuple[float, float]]] = {}
    for t in tracks:
        lufs = probe_cache_seen.get(t["file"], {}).get("lufs")
        if t.get("episode"):
            if lufs is not None:
                episodes.setdefault(t["episode"], []).append((lufs, t["duration"]))
        elif lufs is not None and lufs > SILENT_LUFS:
            t["loudness"] = round(lufs, 1)
    for t in tracks:
        if t.get("episode") and t["episode"] in episodes:
            lufs = combined_loudness(episodes[t["episode"]])
            if lufs is not None:
                t["loudness"] = round(lufs, 1)
    return len(todo) if measure_new else 0


def load_cover_index() -> None:
    path = COVERS_DIR / COVER_INDEX_NAME
    if path.is_file():
        cover_index.update(json.loads(path.read_text(encoding="utf-8")))


def save_cover_index(prune: bool = True) -> None:
    """prune=False during the run: keeps every entry, so an interrupted run loses nothing."""
    kept = {k: v for k, v in cover_index.items() if k in seen_cover_keys} if prune else cover_index
    (COVERS_DIR / COVER_INDEX_NAME).write_text(json.dumps(kept, ensure_ascii=False, indent=1, sort_keys=True),
                                               encoding="utf-8")


def render_cover(src: Path, stream_index: int | None = None) -> str | None:
    """Extracts the image, scales it to 256x256 and saves it as covers/<pixel hash>.png."""
    args = [FFMPEG, "-hide_banner", "-loglevel", "error", "-i", str(src)]
    if stream_index is not None:
        args += ["-map", f"0:{stream_index}"]
    args += ["-frames:v", "1", "-vf", COVER_FILTER, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
    res = subprocess.run(args, capture_output=True, **NO_WINDOW)
    if res.returncode != 0 or len(res.stdout) != COVER_SIZE * COVER_SIZE * 3:
        return None
    name = hashlib.sha1(res.stdout).hexdigest()[:16] + ".png"
    dst = COVERS_DIR / name
    if not dst.exists():
        subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
                        "-s", f"{COVER_SIZE}x{COVER_SIZE}", "-i", "-", "-frames:v", "1", str(dst)],
                       input=res.stdout, capture_output=True, **NO_WINDOW)
    return name if dst.exists() else None


def cover_for(key: str, src: Path, stream_index: int | None = None) -> str | None:
    """Cover (file name in covers/) for the given key, reusing the index if src hasn't changed."""
    seen_cover_keys.add(key)
    mtime = src.stat().st_mtime
    entry = cover_index.get(key)
    if entry and entry.get("mtime") == mtime and entry.get("cover") and (COVERS_DIR / entry["cover"]).exists():
        return entry["cover"]
    name = render_cover(src, stream_index)
    cover_index[key] = {"cover": name, "mtime": mtime}
    return name


def cached_cover(key: str) -> str | None:
    """Already-known cover for a track whose source file is gone (e.g. an MP4 converted and deleted)."""
    entry = cover_index.get(key)
    if entry and entry.get("cover") and (COVERS_DIR / entry["cover"]).exists():
        seen_cover_keys.add(key)
        return entry["cover"]
    # migration from older versions: covers/<path hash>.png, one per track
    legacy = COVERS_DIR / f"{short_hash(key)}.png"
    if legacy.exists():
        return cover_for(key, legacy)
    return None


def remove_unused_covers(tracks: list[dict]) -> int:
    used = {Path(t["cover"]).name for t in tracks if t["cover"]}
    removed = 0
    for png in COVERS_DIR.glob("*.png"):
        if png.name not in used:
            png.unlink()
            removed += 1
    return removed


def converted_ok(dst: Path) -> bool:
    try:
        return dst.exists() and duration_of(probe(dst)) > 0
    except Exception:  # noqa: BLE001
        return False


def convert_to_ogg(src: Path, dst: Path) -> None:
    extra = []
    genre = mp4_genre(src) if src.suffix.lower() in MP4_EXT else None
    if genre:  # the right genre, not ffmpeg's misreading of a text 'gnre' atom
        extra = ["-metadata", f"genre={genre}"]
    res = run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-i", str(src),
               "-map", "0:a:0", "-vn", "-map_metadata", "0", *extra,
               "-c:a", "libvorbis", "-q:a", "5", str(dst)])
    if res.returncode != 0:
        dst.unlink(missing_ok=True)
        raise RuntimeError(res.stderr.strip() or "conversion failed")


def short_hash(text: str) -> str:
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:12]


def guess_from_filename(stem: str) -> tuple[str, str]:
    stem = re.sub(r"^\d{1,3}[\s._-]+", "", stem).strip()
    if " - " in stem:
        artist, title = stem.split(" - ", 1)
        return artist.strip(), title.strip()
    return "", stem


CONTROL_CHARS = re.compile(r"[\x00-\x1f\x7f]+")


def lua_str(s: str) -> str:
    """A Lua string literal. Tags come from any file or feed, so nothing may end the literal early:
    backslashes and quotes are escaped, control characters (newlines included) become a space."""
    s = CONTROL_CHARS.sub(" ", s.replace("\\", "\\\\").replace('"', '\\"'))
    return f'"{s}"'


def lua_text(s: str) -> str:
    """Displayed text: NFC, because WoW draws decomposed marks (e.g. macOS file names) as separate glyphs.
    '|' is doubled: WoW reads |c, |T, |H... as color, texture and link codes, '||' is a plain '|'.
    Not for `file`, which must match the name on disk and is the track id."""
    return lua_str(unicodedata.normalize("NFC", s).replace("|", "||"))


def wow_path(p: Path) -> str:
    return str(p.relative_to(DATA_DIR)).replace("/", "\\")


def folder_cover(folder: Path, root: Path | None = None) -> Path | None:
    """cover.jpg/folder.jpg/... in the folder or a parent folder, up to root (default: music/)."""
    root = root or MUSIC_DIR
    for d in (folder, *folder.parents):
        for name in FOLDER_COVERS:
            for ext in IMAGE_EXT:
                for candidate in (d / f"{name}{ext}", d / f"{name.capitalize()}{ext}"):
                    if candidate.exists():
                        return candidate
        if d == root:
            break
    return None


def is_skipped_dir(name: str) -> bool:
    return name.startswith(("_", "."))


# --- ASCII-only names ---------------------------------------------------------
# WoW may not open files with non-Latin characters in the path: we rename files and
# folders to ASCII and keep the original names to show them in-game.
NAMES_FILE_NAME = "_original_names.json"
LEGACY_NAMES_FILE_NAME = "_nomi_originali.json"  # name used by versions <= 0.4
SAFE_CHARS = re.compile(r"[^A-Za-z0-9 ._()\[\]&+,'!-]")
original_names: dict[str, str] = {}  # ASCII name (without extension for files) -> original name


def safe_name(name: str, is_file: bool) -> str:
    stem, ext = (os.path.splitext(name) if is_file else (name, ""))
    if stem.isascii() and ext.isascii():
        return name
    # NFKD: "é" -> "e", "（" -> "("; kana and kanji are dropped
    ascii_stem = unicodedata.normalize("NFKD", stem).encode("ascii", "ignore").decode()
    ascii_stem = SAFE_CHARS.sub("", ascii_stem)
    ascii_stem = re.sub(r"\(\s*\)|\[\s*\]", "", ascii_stem)        # parentheses left empty
    ascii_stem = re.sub(r"\s*,[\s,]*", ", ", ascii_stem)            # commas left in a row
    ascii_stem = re.sub(r"[\s_]+", " ", ascii_stem).strip(" ._-,")
    tag = hashlib.sha1(stem.encode("utf-8")).hexdigest()[:6]      # stable and collision-free
    ascii_stem = f"{ascii_stem} {tag}" if ascii_stem else f"{'track' if is_file else 'folder'} {tag}"
    return ascii_stem + ext.encode("ascii", "ignore").decode().lower()


def load_original_names() -> None:
    path = MUSIC_DIR / NAMES_FILE_NAME
    if path.is_file():
        original_names.update(json.loads(path.read_text(encoding="utf-8")))


def save_original_names() -> None:
    if original_names:
        (MUSIC_DIR / NAMES_FILE_NAME).write_text(
            json.dumps(original_names, ensure_ascii=False, indent=1, sort_keys=True), encoding="utf-8")


def asciify_tree(stats: dict) -> None:
    """Renames (bottom-up) non-ASCII files and folders inside music/."""
    for root, dirs, files in os.walk(MUSIC_DIR, topdown=False):
        rel = Path(root).relative_to(MUSIC_DIR)
        if any(is_skipped_dir(part) for part in rel.parts):
            continue
        entries = [(f, True) for f in files if f not in (NAMES_FILE_NAME, LEGACY_NAMES_FILE_NAME)] + [(d, False) for d in dirs if not is_skipped_dir(d)]
        for name, is_file in entries:
            new = safe_name(name, is_file)
            if new == name:
                continue
            src, dst = Path(root) / name, Path(root) / new
            if dst.exists():
                stats["warnings"].append(f"{rel.as_posix()}/{name}: not renamed, {new} already exists")
                continue
            src.rename(dst)
            key = os.path.splitext(new)[0] if is_file else new
            original_names[key] = os.path.splitext(name)[0] if is_file else name
            stats["renamed"] += 1
            print(f"  renaming {name} -> {new}")


def display_folder(rel_folder: str) -> str:
    return "/".join(original_names.get(part, part) for part in rel_folder.split("/")) if rel_folder else ""


# --- Podcast -------------------------------------------------------------------
# podcasts.txt (in the addon folder): one RSS feed or Apple Podcasts link per line, optionally
# followed by the number of episodes to keep. Each episode is split into PART_SECONDS-second
# parts (WoW can't resume a file halfway: the addon resumes from the part).
PODCAST_DIR_NAME = "Podcast"
EPISODE_FILE = "episode.json"
PART_SECONDS = 150
DEFAULT_KEEP = 3
USER_AGENT = "KalimdorZugZugRadio/1.0 (+https://github.com/MikeAymeric/KalimdorZugZugRadio)"
PODCASTS_TEMPLATE = """# Kalimdor ZugZug Radio - podcasts that Import music.py downloads (save this file, then import)
# One podcast per line: the RSS feed URL (or the Apple Podcasts link) and, optionally,
# how many recent episodes to keep (default 3). Lines starting with # are ignored.
#
# https://example.com/feed/my-podcast.xml 3
# https://podcasts.apple.com/us/podcast/name/id1234567890 2
"""


MAX_PAGE_BYTES = 50 * 1024 * 1024        # feeds and API answers
MAX_DOWNLOAD_BYTES = 2 * 1024 * 1024 * 1024  # one episode or cover


def http_get(url: str, dst: Path | None = None, timeout: int = 60, progress=None) -> bytes | None:
    """Downloads a web page (returned) or a file (saved to dst). Only http(s): a feed must not be able
    to make the script read local files (file://) or other protocols. Sizes are capped, so a broken or
    hostile server can't fill the disk."""
    import urllib.request
    from urllib.parse import urlsplit
    if urlsplit(url).scheme.lower() not in ("http", "https"):
        raise RuntimeError(f"not a web address: {url[:80]}")
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    limit = MAX_PAGE_BYTES if dst is None else MAX_DOWNLOAD_BYTES
    with urllib.request.urlopen(req, timeout=timeout) as r:
        if dst is None:
            data = r.read(limit + 1)
            if len(data) > limit:
                raise RuntimeError("the answer is too large")
            return data
        written = 0
        try:
            total = int(r.headers.get("Content-Length") or 0)
        except ValueError:
            total = 0
        with open(dst, "wb") as f:
            while chunk := r.read(1024 * 256):
                written += len(chunk)
                if written > limit:
                    raise RuntimeError("the file is too large")
                f.write(chunk)
                if progress:
                    progress(written, total)  # progress(bytes_done, bytes_total or 0)
    return None


def resolve_feed(url: str) -> str:
    """Apple Podcasts link -> RSS feed URL (via iTunes lookup); other URLs unchanged."""
    m = re.search(r"podcasts\.apple\.com/.*?id(\d+)", url)
    if not m:
        return url
    data = json.loads(http_get(f"https://itunes.apple.com/lookup?id={m.group(1)}&entity=podcast"))
    for result in data.get("results", []):
        if result.get("feedUrl"):
            return result["feedUrl"]
    raise RuntimeError("no RSS feed found for this Apple Podcasts link")


def parse_feed(xml_bytes: bytes) -> tuple[str, str | None, list[dict]]:
    import xml.etree.ElementTree as ET
    from email.utils import parsedate_to_datetime
    itunes = "{http://www.itunes.com/dtds/podcast-1.0.dtd}"
    channel = ET.fromstring(xml_bytes).find("channel")
    if channel is None:
        raise RuntimeError("not a valid RSS feed")
    show = (channel.findtext("title") or "Podcast").strip()
    image = channel.find(f"{itunes}image")
    image_url = image.get("href") if image is not None else channel.findtext("image/url")
    episodes = []
    for item in channel.findall("item"):
        enc = item.find("enclosure")
        if enc is None or not enc.get("url"):
            continue
        try:
            date = parsedate_to_datetime(item.findtext("pubDate") or "")
        except (TypeError, ValueError):
            date = None
        episodes.append({
            "guid": (item.findtext("guid") or enc.get("url")).strip(),
            "title": (item.findtext("title") or "?").strip(),
            "url": enc.get("url"),
            "date": date.strftime("%Y-%m-%d") if date else "0000-00-00",
            "sort": date.timestamp() if date else 0,
        })
    episodes.sort(key=lambda e: e["sort"], reverse=True)
    return show, image_url, episodes


def show_dir_name(show: str) -> str:
    """Windows-safe, ASCII-only folder name (the real name is kept in episode.json)."""
    name = safe_name(show, False)
    clean = re.sub(r'[<>:"/\\|?*]+', " ", name)
    clean = re.sub(r"\s+", " ", clean).strip(" .") or "podcast"
    if clean != name:
        clean = f"{clean} {hashlib.sha1(show.encode('utf-8')).hexdigest()[:6]}"
    return clean[:80]


def read_podcast_list(path: Path) -> list[tuple[str, int, str | None]]:
    """(url, episodes to keep, start) per podcast. start = "<date>:<key>" of the first episode not
    listened yet when the podcast is listened in order ("from:" on its line), else None (the latest)."""
    entries = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        keep = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else DEFAULT_KEEP
        start = next((p[5:] for p in parts[1:] if p.startswith("from:") and len(p) > 5), None)
        entries.append((parts[0], max(1, keep), start))
    return entries


def write_podcast_list(path: Path, entries: list[tuple[str, int, str | None]]) -> None:
    """Rewrites podcasts.txt: the explanation, then one podcast per line."""
    lines = [line for line in PODCASTS_TEMPLATE.splitlines() if line.startswith("#") and "example.com" not in line
             and "apple.com/us/podcast/name" not in line]
    lines += [f"{url} {keep}" + (f" from:{start}" if start else "") for url, keep, start in entries]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def episode_key(feed_url: str, guid: str) -> str:
    """Id of an episode: its folder name, its id in the game ("ep:<key>") and in podcasts.txt."""
    return hashlib.sha1((feed_url + "|" + guid).encode("utf-8")).hexdigest()[:12]


def read_podcast(url: str) -> tuple[str, list[dict]]:
    """A podcast's title and episodes (newest first, each with its "key"), also from an Apple Podcasts
    link. Raises if the address doesn't give a usable feed."""
    feed_url = resolve_feed(url)
    show, _, episodes = parse_feed(http_get(feed_url))
    if not episodes:
        raise RuntimeError("no episodes found at this address")
    for ep in episodes:
        ep["key"] = episode_key(feed_url, ep["guid"])
    return show, episodes


def check_podcast(url: str) -> tuple[str, int]:
    show, episodes = read_podcast(url)
    return show, len(episodes)


def finished_episodes() -> set[str]:
    """Keys of the episodes the addon marked as listened to the end (podcastProgress[...].done in the
    newest SavedVariables of the addon; the game writes them on logout or /reload)."""
    flavor = ADDON_DIR.parent.parent.parent  # <flavor>/Interface/AddOns/KalimdorZugZugRadio
    files = glob.glob(str(flavor / "WTF" / "Account" / "*" / "SavedVariables" / f"{ADDON_NAME}.lua"))
    if not files:
        return set()
    try:
        text = Path(max(files, key=os.path.getmtime)).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return set()
    return {m.group(1) for m in re.finditer(r'\["ep:([0-9a-f]{12})"\]\s*=\s*\{([^{}]*)\}', text)
            if re.search(r'\["done"\]\s*=\s*true', m.group(2))}


def plan_in_order(episodes: list[dict], start: str, keep: int, finished: set[str]) -> tuple[list[dict], str]:
    """Episodes to have on disk for a podcast listened in order, and the new start marker: from the
    start episode (or, if the feed dropped it, the first one published on or after its date), skipping
    the finished ones, the next `keep` in publishing order. The marker moves past finished episodes."""
    date, _, key = start.partition(":")
    chrono = list(reversed(episodes))  # oldest first
    i = next((n for n, ep in enumerate(chrono) if ep["key"] == key), None)
    if i is None:
        i = next((n for n, ep in enumerate(chrono) if ep["date"] >= date), len(chrono))
    while i < len(chrono) - 1 and chrono[i]["key"] in finished:
        i += 1
    if not chrono:
        return [], start
    first = chrono[min(i, len(chrono) - 1)]
    wanted = [ep for ep in chrono[i:] if ep["key"] not in finished][:keep]
    return wanted, f"{first['date']}:{first['key']}"


def split_episode(src: Path, out_dir: Path, progress=None) -> int:
    """Converts to OGG and splits into PART_SECONDS-second parts; returns the number of parts.
    progress(seconds_done, seconds_total) follows ffmpeg's -progress output."""
    out_dir.mkdir(parents=True, exist_ok=True)
    total = 0.0
    if progress:
        try:
            total = duration_of(probe(src))
        except Exception:  # noqa: BLE001 - no progress then, the split still runs
            total = 0.0
    proc = subprocess.Popen(
        [FFMPEG, "-hide_banner", "-loglevel", "error", "-nostats", "-progress", "pipe:1", "-y", "-i", str(src),
         "-map", "0:a:0", "-vn", "-c:a", "libvorbis", "-q:a", "3", "-f", "segment", "-segment_time",
         str(PART_SECONDS), "-reset_timestamps", "1", str(out_dir / "part_%03d.ogg")],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8", errors="replace", **NO_WINDOW)
    for line in proc.stdout:  # key=value lines; only errors go to stderr (-loglevel error), so no deadlock
        if progress and total and line.startswith("out_time_us="):
            try:
                progress(min(int(line[12:]) / 1e6, total), total)
            except ValueError:  # "N/A" at the start
                pass
    err = proc.stderr.read()
    if proc.wait() != 0:
        raise RuntimeError(err.strip() or "conversion failed")
    return len(list(out_dir.glob("part_*.ogg")))


PODCASTS_FILE_NAMES = ("podcasts.txt", "podcast.txt")
IN_ORDER_FILE = "_in_order"  # in a show's folder: listened in order (Library.lua serial = true)  # the singular is accepted too


def find_podcasts_file() -> Path | None:
    for name in PODCASTS_FILE_NAMES:
        if (DATA_DIR / name).is_file():
            return DATA_DIR / name
    return None


class ConsolePodcastProgress:
    """Download and conversion progress (they run at the same time) on one console line."""

    def __init__(self):
        self.parts: dict[tuple[str, str], str] = {}  # (stage, episode) -> text
        self.lock = __import__("threading").Lock()

    def __call__(self, stage: str, show: str, title: str, done: float, total: float) -> None:
        with self.lock:
            if stage.endswith("_end"):
                self.parts.pop((stage[:-4], title), None)
            elif stage == "download":
                self.parts[(stage, title)] = "downloading " + f"{done / 1048576:.0f}" + (
                    f" / {total / 1048576:.0f} MB" if total else " MB")
            else:
                self.parts[(stage, title)] = f"converting {int(done * 100 / total) if total else 0}%"
            line = "  |  ".join(t for (st, _), t in sorted(self.parts.items(), key=lambda i: i[0][0] != "download"))
            print(f"\r    {line}".ljust(60) + ("" if line else "\r"), end="", flush=True)


CONVERTERS = max(1, min(3, (os.cpu_count() or 2) // 2))  # episodes converted at the same time
_stats_lock = __import__("threading").Lock()


def convert_episode(job: dict, stats: dict, progress=None) -> None:
    """Second half of an episode's download, run by the converter thread while the next one downloads:
    split into OGG parts, move into place, write episode.json (last: it marks the episode complete)."""
    ep, show, tmp_dir, ep_dir = job["ep"], job["show"], job["tmp_dir"], job["ep_dir"]
    try:
        parts = split_episode(tmp_dir / "episode.bin", tmp_dir / "parts",
                              progress and (lambda d, t: progress("split", show, ep["title"], d, t)))
        shutil.rmtree(ep_dir, ignore_errors=True)
        shutil.move(str(tmp_dir / "parts"), str(ep_dir))
        (ep_dir / EPISODE_FILE).write_text(json.dumps(
            {"key": ep["key"], "guid": ep["guid"], "title": ep["title"], "show": show, "date": ep["date"],
             "feed": job["feed_url"]}, ensure_ascii=False, indent=1), encoding="utf-8")
        with _stats_lock:
            stats["podcast_new"] += 1
        print(f"  ready: {ep['date']} {ep['title']} ({parts} parts of {PART_SECONDS // 60}:{PART_SECONDS % 60:02d})")
    except Exception as exc:  # noqa: BLE001
        stats["warnings"].append(f"podcast {show} / {ep['title']}: {exc}")
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)
        if progress:
            progress("split_end", show, ep["title"], 0, 0)


def update_podcasts(stats: dict, progress=None) -> None:
    """progress(stage, show, episode_title, done, total): "download" (bytes) and "split" (seconds),
    then "download_end"/"split_end". Episodes convert in other threads while the next one downloads;
    ffmpeg's Vorbis encoder uses one core, so up to CONVERTERS episodes convert at once. Downloads wait
    when one more episode than that is already on disk, so big files don't pile up."""
    from concurrent.futures import ThreadPoolExecutor, wait
    converter = ThreadPoolExecutor(max_workers=CONVERTERS)
    pending = []
    try:
        _update_podcasts(stats, progress, converter, pending)
    finally:
        wait(pending)
        converter.shutdown()
        print()


def _update_podcasts(stats: dict, progress, converter, pending: list) -> None:
    from concurrent.futures import FIRST_COMPLETED, wait
    podcasts_file = find_podcasts_file()
    if not podcasts_file:
        podcasts_file = DATA_DIR / PODCASTS_FILE_NAMES[0]
        podcasts_file.write_text(PODCASTS_TEMPLATE, encoding="utf-8")
        print(f"Created {podcasts_file}: add your podcasts and run the script again.\n")
        return
    entries = read_podcast_list(podcasts_file)
    if not entries:
        print(f"No podcasts in {podcasts_file.name}.\n")
        return
    root = MUSIC_DIR / PODCAST_DIR_NAME
    finished = finished_episodes() if any(start for _, _, start in entries) else set()
    new_entries = list(entries)
    for n, (url, keep, start) in enumerate(entries):
        try:
            feed_url = resolve_feed(url)
            show, image_url, episodes = parse_feed(http_get(feed_url))
        except Exception as exc:  # noqa: BLE001
            stats["warnings"].append(f"podcast {url}: {exc}")
            continue
        for ep in episodes:
            ep["key"] = episode_key(feed_url, ep["guid"])
        show_dir = root / show_dir_name(show)
        show_dir.mkdir(parents=True, exist_ok=True)
        in_order = show_dir / IN_ORDER_FILE
        if start and episodes:
            selected, marker = plan_in_order(episodes, start, keep, finished)
            if marker != start:
                new_entries[n] = (url, keep, marker)
            in_order.write_text(marker + "\n", encoding="utf-8")
            print(f"[podcast] {show}: in order, {keep} episodes from {marker.partition(':')[0]}")
        else:
            selected = episodes[:keep]
            if in_order.exists():
                in_order.unlink()
            print(f"[podcast] {show}: latest {keep} episodes")
        has_own_cover = any((show_dir / f"cover{ext}").exists() for ext in IMAGE_EXT)
        if image_url and not has_own_cover:
            ext = os.path.splitext(image_url.split("?")[0])[1].lower()
            try:
                http_get(image_url, show_dir / ("cover" + (ext if ext in IMAGE_EXT else ".jpg")))
            except Exception as exc:  # noqa: BLE001
                stats["warnings"].append(f"podcast {show}: cover not downloaded ({exc})")

        wanted = set()
        for ep in selected:
            key = ep["key"]
            wanted.add(key)
            ep_dir = show_dir / f"{ep['date']} {key}"
            if (ep_dir / EPISODE_FILE).exists():
                continue
            # CONVERTERS converting and one downloaded waiting at most
            while len([f for f in pending if not f.done()]) > CONVERTERS:
                wait(pending, return_when=FIRST_COMPLETED)
            print(f"  downloading {ep['date']} {ep['title']}")
            tmp_dir = show_dir / f"_tmp_{key}"
            shutil.rmtree(tmp_dir, ignore_errors=True)
            tmp_dir.mkdir()
            try:
                http_get(ep["url"], tmp_dir / "episode.bin", timeout=300,
                         progress=progress and (lambda d, t: progress("download", show, ep["title"], d, t)))
            except Exception as exc:  # noqa: BLE001
                stats["warnings"].append(f"podcast {show} / {ep['title']}: {exc}")
                shutil.rmtree(tmp_dir, ignore_errors=True)
                continue
            finally:
                if progress:
                    progress("download_end", show, ep["title"], 0, 0)
            job = {"ep": ep, "show": show, "tmp_dir": tmp_dir, "ep_dir": ep_dir, "feed_url": feed_url}
            pending.append(converter.submit(convert_episode, job, stats, progress))

        # episodes older than the ones to keep (or, listening in order, finished) are deleted; not when
        # the feed came back empty: a server error page must not wipe the downloaded episodes
        for d in (show_dir.iterdir() if episodes else ()):
            meta = d / EPISODE_FILE
            if d.is_dir() and meta.exists():
                if json.loads(meta.read_text(encoding="utf-8")).get("key") not in wanted:
                    shutil.rmtree(d)
                    stats["podcast_removed"] += 1
                    print(f"  deleting old episode {d.name}")
    if new_entries != entries:  # in-order podcasts moved on past the finished episodes
        write_podcast_list(podcasts_file, new_entries)


def process_episode(folder: Path, stats: dict) -> list[dict]:
    """One episode = several OGG parts; in-game they become a single item ('episode' field)."""
    meta = json.loads((folder / EPISODE_FILE).read_text(encoding="utf-8"))
    parts = sorted(folder.glob("part_*.ogg"))
    cover_src = folder_cover(folder)
    cover = cover_for(f"folder:{cover_src.parent.relative_to(MUSIC_DIR).as_posix()}", cover_src) if cover_src else None
    tracks = []
    serial = (folder.parent / IN_ORDER_FILE).exists()
    for i, path in enumerate(parts, 1):
        try:
            duration = duration_of(cached_probe(path, wow_path(path))[0])
        except Exception as exc:  # noqa: BLE001
            stats["warnings"].append(f"{folder.name}/{path.name}: {exc}")
            continue
        tracks.append({
            "file": wow_path(path), "folder": f"{PODCAST_DIR_NAME}/{meta['show']}",
            "title": meta["title"], "artist": meta["show"], "album": meta["date"], "duration": duration,
            "cover": wow_path(COVERS_DIR / cover) if cover else None,
            "episode": meta["key"], "part": i, "parts": len(parts), "serial": serial,
        })
    return tracks


def process_folder(folder: Path, keep_originals: bool, stats: dict) -> list[dict]:
    if (folder / EPISODE_FILE).exists():
        return process_episode(folder, stats)
    rel_folder = folder.relative_to(MUSIC_DIR).as_posix()
    rel_folder = "" if rel_folder == "." else rel_folder
    label = rel_folder or "(music)"
    files = sorted(p for p in folder.iterdir() if p.is_file())

    # 1) convert unsupported formats
    for src in files:
        if src.suffix.lower() not in CONVERT:
            continue
        dst = src.with_suffix(".ogg")
        try:
            # take the cover from the original: the OGG doesn't contain it
            pic = attached_pic_index(probe(src))
            cover_ok = pic is None or cover_for(wow_path(dst), src, pic) is not None
            save_cover_index(prune=False)  # on disk before the original is deleted
            if not dst.exists():
                print(f"  converting {label}/{src.name} -> {dst.name}")
                convert_to_ogg(src, dst)
                stats["converted"] += 1
            if not converted_ok(dst):
                raise RuntimeError("the converted OGG is not readable: original left in place")
            if not cover_ok:
                raise RuntimeError("the embedded cover could not be extracted: original left in place")
            if keep_originals:
                target = ORIGINALS_DIR / rel_folder / (original_names.get(src.stem, src.stem) + src.suffix)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(src), str(target))
            else:
                src.unlink()
                stats["deleted"] += 1
        except Exception as exc:  # noqa: BLE001 - one broken track must not stop everything
            stats["warnings"].append(f"{label}/{src.name}: {exc}")

    # 2) catalog the playable files
    shared_cover = None
    shared_cover_src = folder_cover(folder)
    if shared_cover_src:
        shared_cover = cover_for(f"folder:{shared_cover_src.parent.relative_to(MUSIC_DIR).as_posix()}", shared_cover_src)

    tracks = []
    for path in sorted(p for p in folder.iterdir() if p.is_file() and p.suffix.lower() in NATIVE):
        rel = wow_path(path)
        try:
            info, genre = cached_probe(path, rel)
        except Exception as exc:  # noqa: BLE001
            stats["warnings"].append(f"{label}/{path.name}: {exc}")
            continue
        tags = tags_of(info)
        g_artist, g_title = guess_from_filename(original_names.get(path.stem, path.stem))

        pic = attached_pic_index(info)
        cover = cover_for(rel, path, pic) if pic is not None else cached_cover(rel)
        cover = cover or shared_cover or found_cover(rel)

        duration = duration_of(info)
        if duration <= 0:
            stats["warnings"].append(f"{label}/{path.name}: unknown duration (won't auto-advance)")
        if not rel.isascii():
            stats["warnings"].append(f"{label}/{path.name}: the path contains non-ASCII characters; "
                                     "if it doesn't play in-game, rename it")

        tracks.append({
            "file": rel,
            "folder": display_folder(rel_folder),
            "title": tags.get("title") or g_title,
            "artist": tags.get("artist") or tags.get("album_artist") or g_artist,
            "album": tags.get("album", ""),
            "duration": duration,
            "cover": wow_path(COVERS_DIR / cover) if cover else None,
            "genre": genre,
            "year": year_of(tags),
            "composer": (tags.get("composer") or "").strip(),
            "track": number_of(tags.get("track")),
            "disc": number_of(tags.get("disc")),
        })
    return tracks


def original_rel_path(rel_file: str) -> tuple[Path, str]:
    """music\\A 1a2b3c\\01 4d5e6f.ogg -> (Path("<original folders>"), "<original stem>"), undoing the renaming."""
    parts = Path(rel_file.replace("\\", "/")).relative_to(MUSIC_DIR.name).parts
    folders = [original_names.get(p, p) for p in parts[:-1]]
    stem = Path(parts[-1]).stem
    return Path(*folders) if folders else Path("."), original_names.get(stem, stem)


class OriginalFinder:
    """Finds the original of an imported track in another folder (same folders and file name, any
    audio extension, ASCII renaming undone). The folder is only read, never modified."""

    def __init__(self, source_root: Path):
        self.root = source_root
        self.listing: dict[Path, dict[str, Path]] = {}

    def folder_of(self, rel_file: str) -> Path:
        return self.root / original_rel_path(rel_file)[0]

    def find(self, rel_file: str) -> Path | None:
        rel_dir, stem = original_rel_path(rel_file)
        folder = self.root / rel_dir
        if folder not in self.listing:
            self.listing[folder] = {unicodedata.normalize("NFC", p.stem).casefold(): p for p in sorted(folder.iterdir())
                                    if p.is_file() and p.suffix.lower() in AUDIO_EXT} if folder.is_dir() else {}
        return self.listing[folder].get(unicodedata.normalize("NFC", stem).casefold())


def recover_genres(tracks: list[dict], finder: OriginalFinder) -> int:
    """Tracks converted before 1.0 carry ffmpeg's wrong genre ("Big Band" for "Game Soundtrack"):
    the right one is read from the MP4 original in your music library."""
    fixed = 0
    for t in tracks:
        if t.get("episode"):
            continue
        src = finder.find(t["file"])
        if src and src.suffix.lower() in MP4_EXT:
            g = cached_original(t["file"], src, "orig_genre", mp4_genre)
            if g and g != t.get("genre"):
                t["genre"] = g
                fixed += 1
    return fixed


def recover_covers(tracks: list[dict], source_root: Path, stats: dict, finder: OriginalFinder | None = None) -> int:
    """--covers-from: for tracks without a cover, extracts it from the matching original (same folders
    and file name, any extension) in source_root. source_root is only read, never modified."""
    finder = finder or OriginalFinder(source_root)
    recovered = 0
    for t in tracks:
        if t["cover"] or t.get("episode"):
            continue
        folder = finder.folder_of(t["file"])
        src = finder.find(t["file"])
        cover = None
        try:
            if src:
                pic = cached_original(t["file"], src, "orig_pic", lambda p: attached_pic_index(probe(p)))
                if pic is not None:
                    cover = cover_for(t["file"], src, pic)
            if not cover and folder.is_dir():
                img = folder_cover(folder, source_root)
                if img:
                    cover = cover_for(t["file"], img)
        except Exception as exc:  # noqa: BLE001
            stats["warnings"].append(f"{t['file']}: cover not recovered ({exc})")
        if cover:
            t["cover"] = wow_path(COVERS_DIR / cover)
            recovered += 1
    return recovered


# --- Library tools (2.0, library_tools.py) -------------------------------------------
# _library.json: the tracks of the last import, read by the duplicate finder and the cover search.
# _aliases.json: removed duplicate -> kept track id; Library.lua's "aliases" lets the addon move
#   playlists, favourites, ratings and stats to the kept track.
# _covers_found/: covers found online or chosen by hand for tracks without one (map.json: track id
#   -> image file), used when a track has no embedded cover and no cover file in its folder.
LIBRARY_INDEX_NAME = "_library.json"
ALIASES_NAME = "_aliases.json"
FOUND_COVERS_DIR_NAME = "_covers_found"
FOUND_COVERS_MAP = "map.json"
found_covers: dict[str, str] = {}


def read_json(path: Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return default


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    tmp.replace(path)


def load_found_covers() -> None:
    global found_covers
    data = read_json(MUSIC_DIR / FOUND_COVERS_DIR_NAME / FOUND_COVERS_MAP, {})
    found_covers = {k: v for k, v in data.items() if isinstance(k, str) and isinstance(v, str)}


def found_cover(rel: str) -> str | None:
    """Cover found online / chosen by hand for track rel (rendered like any other cover)."""
    name = found_covers.get(rel)
    img = MUSIC_DIR / FOUND_COVERS_DIR_NAME / name if name else None
    if not img or "/" in name or "\\" in name or not img.is_file():
        return None
    try:
        return cover_for(rel, img)
    except Exception:  # noqa: BLE001
        return None


def resolved_aliases(tracks: list[dict]) -> dict[str, str]:
    """_aliases.json with chains followed (a -> b -> c), only towards tracks still in the library."""
    raw = read_json(MUSIC_DIR / ALIASES_NAME, {})
    present = {t["file"] for t in tracks}
    out = {}
    for old in raw:
        new, seen = raw[old], {old}
        while new in raw and new not in seen:
            seen.add(new)
            new = raw[new]
        if isinstance(new, str) and new in present and old not in present:
            out[old] = new
    return out


def write_library_index(tracks: list[dict]) -> None:
    keys = ("file", "folder", "title", "artist", "album", "duration", "cover", "loudness", "episode")
    try:
        write_json(MUSIC_DIR / LIBRARY_INDEX_NAME, [{k: t.get(k) for k in keys} for t in tracks])
    except OSError as exc:
        print(f"  WARNING: {LIBRARY_INDEX_NAME} not saved ({exc})")


def write_library(tracks: list[dict]) -> None:
    lines = [
        "-- GENERATED by Import music.py (tools/import_music.py of Kalimdor ZugZug Radio): do not edit by hand.",
        "-- 'file' is also the track id used by the playlists saved in-game; paths are relative to this folder.",
        "KZZR_UserLibrary = {",
        f'  addon = "{DATA_ADDON_NAME}",',
        f'  generated = "{datetime.now():%Y-%m-%d %H:%M}",',
        "  tracks = {",
    ]
    for t in tracks:
        fields = [f"file = {lua_str(t['file'])}", f"folder = {lua_text(t['folder'])}",
                  f"title = {lua_text(t['title'])}", f"artist = {lua_text(t['artist'])}",
                  f"album = {lua_text(t['album'])}", f"duration = {t['duration']}"]
        if t["cover"]:
            fields.append(f"cover = {lua_str(t['cover'])}")
        for key in ("genre", "composer"):
            if t.get(key):
                fields.append(f"{key} = {lua_text(t[key])}")
        for key in ("year", "track", "disc"):
            if t.get(key):
                fields.append(f"{key} = {int(t[key])}")
        if t.get("loudness") is not None:
            fields.append(f"loudness = {float(t['loudness']):.1f}")
        if t.get("episode"):
            fields += [f"episode = {lua_str(t['episode'])}", f"part = {t['part']}", f"parts = {t['parts']}"]
            if t.get("serial"):
                fields.append("serial = true")
        lines.append("    { " + ", ".join(fields) + " },")
    lines.append("  },")
    aliases = resolved_aliases(tracks)
    if aliases:
        lines.append("  aliases = {")
        lines += [f"    [{lua_str(old)}] = {lua_str(new)}," for old, new in sorted(aliases.items())]
        lines.append("  },")
    lines += ["}", ""]
    LIBRARY_FILE.write_text("\n".join(lines), encoding="utf-8")


# --- Sync from the user's music library ---------------------------------------------
# --library: the user's own music folder (e.g. a Plex or iTunes library). Tracks that are not in
# music/ yet (compared by original folder and file name, ignoring the extension and the ASCII
# renaming) are copied into music/ and then converted as usual. The library is only read, and
# nothing is ever deleted from music/ because it is missing from the library.
SETTINGS_FILE_NAME = "import_settings.json"
AUDIO_EXT = NATIVE | CONVERT


def load_settings() -> dict:
    path = DATA_DIR / SETTINGS_FILE_NAME
    try:
        return json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {}
    except (OSError, ValueError):
        return {}


def save_settings(settings: dict) -> None:
    (DATA_DIR / SETTINGS_FILE_NAME).write_text(json.dumps(settings, ensure_ascii=False, indent=1),
                                                encoding="utf-8")


def track_key(parts: list[str]) -> str:
    """Comparable key of a path given as original names (folders..., file stem)."""
    return "/".join(unicodedata.normalize("NFC", p).casefold() for p in parts)


def music_index() -> tuple[set[str], dict[str, Path]]:
    """Keys of the tracks already in music/ and, for each original folder path, its real folder."""
    keys: set[str] = set()
    dirs: dict[str, Path] = {"": MUSIC_DIR}
    for root, subdirs, files in os.walk(MUSIC_DIR):
        subdirs[:] = [d for d in subdirs if not is_skipped_dir(d)]
        rel = Path(root).relative_to(MUSIC_DIR).parts
        folders = [original_names.get(p, p) for p in rel]
        dirs[track_key(folders)] = Path(root)
        for f in files:
            stem, ext = os.path.splitext(f)
            if ext.lower() in AUDIO_EXT:
                keys.add(track_key(folders + [original_names.get(stem, stem)]))
    return keys, dirs


def find_missing(library: Path) -> list[Path]:
    """Audio files of the library (relative paths) that music/ doesn't have yet."""
    have, _ = music_index()
    missing = []
    for root, subdirs, files in os.walk(library):
        subdirs[:] = sorted(d for d in subdirs if not is_skipped_dir(d))
        rel = Path(root).relative_to(library)
        for f in sorted(files):
            stem, ext = os.path.splitext(f)
            if ext.lower() in AUDIO_EXT and track_key(list(rel.parts) + [stem]) not in have:
                missing.append(rel / f)
    return missing


def describe_missing(missing: list[Path], limit: int = 15) -> None:
    by_folder = Counter(p.parent.as_posix() for p in missing)
    print(f" {len(missing)} new tracks in {len(by_folder)} folder{'' if len(by_folder) == 1 else 's'}:")
    for name, n in sorted(by_folder.items())[:limit]:
        print(f"   {n:4}  {'(top folder)' if name == '.' else name}")
    if len(by_folder) > limit:
        print(f"   ... and {len(by_folder) - limit} more folders")


def copy_missing(library: Path, missing: list[Path], stats: dict) -> None:
    """Copies the missing tracks (and the album's cover.jpg/folder.jpg) into music/, reusing the folders
    that already exist there under their ASCII names."""
    _, dirs = music_index()
    for rel in missing:
        parts = list(rel.parent.parts)
        # deepest folder that already exists in music/ (possibly renamed), then the new ones
        for i in range(len(parts), -1, -1):
            base = dirs.get(track_key(parts[:i]))
            if base is not None:
                dst_dir = base.joinpath(*parts[i:])
                break
        dst_dir.mkdir(parents=True, exist_ok=True)
        src = library / rel
        try:
            print(f"  copying {rel.as_posix()}")
            shutil.copy2(src, dst_dir / src.name)
            stats["copied"] += 1
            img = folder_cover(src.parent, src.parent)
            if img and not folder_cover(dst_dir, dst_dir):
                shutil.copy2(img, dst_dir / img.name)
        except OSError as exc:
            stats["warnings"].append(f"{rel.as_posix()}: not copied ({exc})")


# --- Interactive menu ------------------------------------------------------------
# Shown when the script starts with no options in an interactive window (e.g. a double-click on
# "Import music.py"), so people who never use a terminal can still pick the options.

def ask(prompt: str) -> str:
    try:
        return input(prompt).strip()
    except EOFError:
        return "q"


def ask_folder(prompt: str) -> Path | None:
    """A folder typed or dragged into the window (Windows adds quotes when dragging); None if empty."""
    text = ask(prompt).strip().strip('"').strip("'")
    return Path(text).expanduser() if text and text.lower() != "q" else None


def music_summary() -> str:
    tracks = to_convert = 0
    for root, dirs, files in os.walk(MUSIC_DIR):
        dirs[:] = [d for d in dirs if not is_skipped_dir(d)]
        for f in files:
            ext = os.path.splitext(f)[1].lower()
            tracks += ext in NATIVE
            to_convert += ext in CONVERT
    return f"{tracks} playable files" + (f", {to_convert} to convert" if to_convert else ", nothing to convert")


def interactive_menu(args: argparse.Namespace) -> bool:
    """Lets the user change args; False if they quit."""
    while True:
        podcasts_file = find_podcasts_file()
        if args.no_podcasts:
            podcasts = "skip"
        elif podcasts_file:
            podcasts = f"download the ones in {podcasts_file.name}"
        else:
            podcasts = "create podcasts.txt to fill in" if args.podcasts else "none (no podcasts.txt)"
        yes_no = lambda b: "yes" if b else "no "  # noqa: E731
        covers = args.covers_from or ("from your music library" if args.library else "no")
        print("=" * 72)
        print(" Kalimdor ZugZug Radio - music import")
        print("=" * 72)
        print(f" Addon: {ADDON_DIR}")
        print(f" Your music folder: {MUSIC_DIR}")
        print(f" Music: {music_summary()}\n")
        print(f"  1. Your music library, to copy what's missing      [{args.library or 'not set'}]")
        print(f"  2. Keep the original files after converting        [{yes_no(args.keep_originals)}]"
              + ("" if args.keep_originals else "  (deleted)"))
        print(f"  3. Rename non-Latin file names (recommended)       [{yes_no(not args.keep_names)}]")
        print(f"  4. Podcasts                                        [{podcasts}]")
        print(f"  5. Recover missing covers from a folder            [{covers}]")
        print("  6. Change the addon folder")
        print("  7. Open your music folder (put your files there)")
        choice = ask("\n Type a number to change an option, Enter to start, Q to quit: ").lower()
        print()
        if choice == "":
            return True
        if choice == "q":
            return False
        if choice == "1":
            print(" The folder where you keep your music (e.g. your Plex or iTunes library). Tracks that are")
            print(" not in the addon's music folder yet are copied there and converted; your library is only")
            print(" read. Type the path or drag the folder here, then press Enter (Enter alone: none).")
            folder = ask_folder(" > ")
            if folder and folder.is_dir():
                args.library = str(folder)
            elif folder:
                print(f" Folder not found: {folder}\n")
            else:
                args.library = None
            settings = load_settings()
            settings["library"] = args.library
            save_settings(settings)
        elif choice == "2":
            args.keep_originals = not args.keep_originals
        elif choice == "3":
            args.keep_names = not args.keep_names
        elif choice == "4":
            if podcasts_file:
                args.no_podcasts = not args.no_podcasts
            else:
                args.podcasts = not args.podcasts
        elif choice == "5":
            if args.covers_from:
                args.covers_from = None
                continue
            print(" Folder with the original files, with the same folders and file names as in music\\")
            print(" (it is only read). Type the path or drag the folder here, then press Enter.")
            folder = ask_folder(" > ")
            if folder and folder.is_dir():
                args.covers_from = str(folder)
            elif folder:
                print(f" Folder not found: {folder}\n")
        elif choice == "6":
            folder = ask_folder(f" Folder of the {ADDON_NAME} addon (type it or drag it here): ")
            found = _check_addon(folder.resolve()) if folder else None
            if found:
                set_addon_dir(found)
                ensure_data_addon()
                moved = {"moved": 0, "warnings": []}
                migrate_to_data_addon(moved)
                for w in moved["warnings"]:
                    print(f"  WARNING: {w}")
            elif folder:
                print(f" {ADDON_NAME}.toc was not found in {folder}\n")
        elif choice == "7":
            if hasattr(os, "startfile"):
                os.startfile(MUSIC_DIR)  # noqa: S606 - opens Explorer on Windows
            else:
                print(f" Your music folder: {MUSIC_DIR}\n")
        else:
            print(f" Unknown choice: {choice}\n")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--keep-names", action="store_true",
                        help="don't rename files and folders with non-Latin characters (Japanese, accents, ...)")
    parser.add_argument("--keep-originals", action="store_true",
                        help="keep converted originals in music/_originals (without this option they are "
                             "deleted, together with the _originals folder)")
    parser.add_argument("--podcasts", action="store_true",
                        help="create podcasts.txt if missing (podcasts listed in an existing podcasts.txt in the "
                             "addon folder are always downloaded)")
    parser.add_argument("--no-podcasts", action="store_true",
                        help="skip the podcast download even if podcasts.txt exists")
    parser.add_argument("--covers-from", metavar="FOLDER",
                        help="recover missing covers from a folder with the original files (same folders and "
                             "file names as in music/, any format); that folder is only read")
    parser.add_argument("--library", metavar="FOLDER",
                        help="your music library: tracks not yet in music/ are copied there and converted "
                             "(the library is only read; missing covers are also recovered from it)")
    parser.add_argument("--no-loudness", action="store_true",
                        help="don't measure the volume of new tracks (the addon evens out the volume only "
                             "of tracks already measured)")
    parser.add_argument("--find-duplicates", action="store_true",
                        help="list the tracks that look like duplicates and exit (the Import music window "
                             "can move them away)")
    parser.add_argument("--addon", metavar="FOLDER",
                        help=f"addon folder (the one with {ADDON_NAME}.toc), if it isn't found automatically")
    parser.add_argument("--no-menu", action="store_true",
                        help="don't show the interactive menu (it appears when the script starts with no options)")
    parser.add_argument("--menu", action="store_true",
                        help="show the text menu instead of the window (Import music.py opens a window)")
    return parser


def new_stats() -> dict:
    return {"converted": 0, "renamed": 0, "deleted": 0, "copied": 0, "moved": 0, "podcast_new": 0,
            "podcast_removed": 0, "warnings": []}


def prepare_addon(addon: Path, stats: dict) -> None:
    """Points the script at an addon folder: creates the data addon, moves old files there and loads
    the name map. Shared by the command line, the text menu and the window (import_gui.py)."""
    set_addon_dir(addon)
    ensure_data_addon()
    migrate_to_data_addon(stats)
    # migration from the Italian file/folder names used by versions <= 0.4
    legacy_names = MUSIC_DIR / LEGACY_NAMES_FILE_NAME
    if legacy_names.exists() and not (MUSIC_DIR / NAMES_FILE_NAME).exists():
        legacy_names.rename(MUSIC_DIR / NAMES_FILE_NAME)
    legacy_originals = MUSIC_DIR / "_originali"
    if legacy_originals.is_dir() and not ORIGINALS_DIR.exists():
        legacy_originals.rename(ORIGINALS_DIR)
    load_original_names()


def main() -> None:
    args = build_parser().parse_args()
    interactive = (len(sys.argv) == 1 or args.menu) and sys.stdin is not None and sys.stdin.isatty()
    setup_ffmpeg()

    addon = find_addon_dir(args.addon)
    while not addon and interactive:
        print(f"The {ADDON_NAME} addon was not found automatically.")
        folder = ask_folder("Folder of the addon (type it or drag it here; Enter to quit): ")
        if not folder:
            sys.exit(1)
        addon = _check_addon(folder.resolve())
    if not addon:
        sys.exit(f"ERROR: the {ADDON_NAME} addon was not found. Install it in "
                 f"World of Warcraft/_forever_/Interface/AddOns/ first, or pass its folder with "
                 f"--addon \"path\\{ADDON_NAME}\"")
    stats = new_stats()
    prepare_addon(addon, stats)
    if args.find_duplicates:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import library_tools
        library_tools.im = sys.modules[__name__]  # this module, also when run as a script (__main__)
        library_tools.print_duplicates()
        return
    if interactive:
        saved = load_settings().get("library")
        if saved and Path(saved).is_dir():
            args.library = saved
        if not interactive_menu(args):
            print("Nothing done.")
            return
    confirm = ((lambda n: ask(f" Copy these {n} new tracks into the addon and import them? [Y/n] ").lower()
                not in ("n", "no", "q")) if interactive else None)
    run_import(args, stats, confirm)


def run_import(args: argparse.Namespace, stats: dict, confirm=None, progress=None, podcast_progress=None) -> dict:
    """The import itself, after prepare_addon(). confirm(track_count) -> bool is asked before copying from
    the library (None: yes); progress(done, total, label) is called for each music folder and
    podcast_progress (see update_podcasts; on a console it defaults to one updating line) while
    episodes download and convert; while the volume is measured it is called as
    progress(done, total, label, "loudness"). Returns a summary for the window."""
    # tracks to copy from the user's library: listed (and confirmed in the menu) before any work
    library = Path(args.library).expanduser() if args.library else None
    missing: list[Path] = []
    if library:
        if not library.is_dir():
            sys.exit(f"ERROR: folder {library} not found (--library)")
        print(f"Comparing {library} with {MUSIC_DIR} ...")
        missing = find_missing(library)
        if missing:
            describe_missing(missing)
            if confirm and not confirm(len(missing)):
                missing = []
        else:
            print(" Nothing new: music/ already has every track of your library.")
        print()
    print(f"Addon: {ADDON_DIR}\n")
    COVERS_DIR.mkdir(exist_ok=True)

    # podcasts: always checked when podcasts.txt exists (unless --no-podcasts); --podcasts creates the template
    do_podcasts = not args.no_podcasts and (args.podcasts or find_podcasts_file() is not None)
    if do_podcasts:
        if podcast_progress is None and getattr(sys.stdout, "isatty", lambda: False)():
            podcast_progress = ConsolePodcastProgress()
        update_podcasts(stats, podcast_progress)
    if not args.keep_originals and ORIGINALS_DIR.is_dir():
        print(f"  deleting {ORIGINALS_DIR} (use --keep-originals to keep it)")
        shutil.rmtree(ORIGINALS_DIR)
    load_cover_index()
    load_probe_cache()
    load_found_covers()
    if missing:
        copy_missing(library, missing, stats)
    if not args.keep_names:
        asciify_tree(stats)
        save_original_names()
    folders = []
    for root, dirs, _ in os.walk(MUSIC_DIR):
        dirs[:] = sorted(d for d in dirs if not is_skipped_dir(d))
        folders.append(Path(root))

    tracks = []
    for i, folder in enumerate(folders):
        if progress:
            progress(i, len(folders), folder.relative_to(MUSIC_DIR).as_posix())
        found = process_folder(folder, args.keep_originals, stats)
        if found:
            print(f"[{folder.relative_to(MUSIC_DIR).as_posix()}] {len(found)} tracks")
        tracks.extend(found)

    recovered = genres_fixed = 0
    covers_source = args.covers_from or args.library
    if covers_source:
        source_root = Path(covers_source).expanduser()
        if not source_root.is_dir():
            sys.exit(f"ERROR: folder {source_root} not found (--covers-from)")
        finder = OriginalFinder(source_root)
        print(f"\nRecovering missing covers and genres from {source_root} ...")
        recovered = recover_covers(tracks, source_root, stats, finder)
        genres_fixed = recover_genres(tracks, finder)

    measured = add_loudness(tracks, stats, not getattr(args, "no_loudness", False), progress)

    if progress:
        progress(len(folders), len(folders), "")
    write_library(tracks)
    write_library_index(tracks)
    save_probe_cache()
    save_cover_index()
    removed = remove_unused_covers(tracks)
    unique = len({t["cover"] for t in tracks if t["cover"]})
    with_cover = sum(1 for t in tracks if t["cover"])
    print(f"\nLibrary.lua written: {len(tracks)} tracks, {stats['converted']} converted, "
          f"{stats['deleted']} originals deleted, {stats['renamed']} renamed"
          + (f", {stats['copied']} copied from your library" if library else "") + ".")
    print(f"Covers: {unique} distinct images for {with_cover} tracks"
          + (f", {recovered} recovered from {Path(covers_source)}" if covers_source else "")
          + (f" ({removed} unused files removed)" if removed else "") + ".")
    with_loudness = sum(1 for t in tracks if t.get("loudness") is not None)
    print(f"Volume: {with_loudness} of {len(tracks)} files measured"
          + (f" ({measured} new)" if measured else "") + ".")
    with_genre = sum(1 for t in tracks if t.get("genre") and not t.get("episode"))
    print(f"Genres: {with_genre} tracks have one"
          + (f", {genres_fixed} corrected from the originals in {Path(covers_source)}" if genres_fixed else "") + ".")
    missing = [t for t in tracks if not t["cover"] and not t.get("episode")]
    if missing:
        by_folder = Counter(t["folder"] or "(music)" for t in missing)
        print(f"Tracks without a cover: {len(missing)} in {len(by_folder)} folder{'' if len(by_folder) == 1 else 's'}"
              + ("" if covers_source else
                 " (if the originals still have it, run again with --covers-from \"<folder with the originals>\")")
              + ":")
        for name, n in sorted(by_folder.items(), key=lambda x: -x[1])[:15]:
            print(f"  {n:4}  {name}")
        if len(by_folder) > 15:
            print(f"  ... and {len(by_folder) - 15} more folders")
    if do_podcasts:
        episodes = len({t["episode"] for t in tracks if t.get("episode")})
        print(f"Podcasts: {episodes} episodes in the library ({stats['podcast_new']} new, "
              f"{stats['podcast_removed']} old ones deleted).")
    for w in stats["warnings"]:
        print(f"  WARNING: {w}")
    print(f"\nYour music is in {MUSIC_DIR} (addon updates never touch it).")
    print(f"In the game's AddOns list keep \"Kalimdor ZugZug Radio - My Music\" enabled.")
    print("If you added new files, RESTART the game client; if only Library.lua changed, /reload is enough.")
    print("Playlists are created in-game: /kzz lib")
    items = sum(1 for t in tracks if not t.get("episode")) + len({t["episode"] for t in tracks if t.get("episode")})
    return {"tracks": items, "converted": stats["converted"], "copied": stats["copied"],
            "no_cover": len(missing), "warnings": list(stats["warnings"])}


if __name__ == "__main__":
    main()
