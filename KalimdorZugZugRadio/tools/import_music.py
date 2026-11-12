"""Imports music (and podcasts) for Kalimdor ZugZug Radio.

Your music lives in a separate folder next to the addon, AddOns/KalimdorZugZugRadio_Library/
(a tiny data addon created by this script), so updating the addon (e.g. with the CurseForge
app, which replaces the addon folder) never deletes it. Files dropped into the old
KalimdorZugZugRadio/music/ folder are moved there.

Recursively scans KalimdorZugZugRadio_Library/music/ (subfolders are only for organizing:
playlists are created in-game), converts formats WoW can't play (mp4, m4a, flac,
wav, ...) to OGG, extracts covers (embedded, or cover.jpg/folder.jpg in the folder)
as deduplicated 256x256 PNGs and generates KalimdorZugZugRadio_Library/Library.lua.

Usage:  python import_music.py [--addon FOLDER] [--keep-originals] [--keep-names] [--podcasts]
        (with no options, in a window, it shows a menu; --help lists every option)
The addon folder is found automatically: the folder you run the script from, then the
addon installed in World of Warcraft on this PC (Windows registry and usual locations,
WoW Forever first). If it isn't found, pass it with --addon "path/to/KalimdorZugZugRadio".
Requires ffmpeg and ffprobe (on PATH or installed with winget Gyan.FFmpeg).
"""
from __future__ import annotations

import argparse
import unicodedata
import glob
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from collections import Counter
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


def find_tool(name: str) -> str:
    found = shutil.which(name)
    if found:
        return found
    pattern = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Microsoft", "WinGet", "Packages",
                           "Gyan.FFmpeg*", "**", "bin", f"{name}.exe")
    matches = sorted(glob.glob(pattern, recursive=True))
    if matches:
        return matches[-1]
    sys.exit(f"ERROR: {name} not found. Install ffmpeg (winget install Gyan.FFmpeg).")


if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

FFMPEG = find_tool("ffmpeg")
FFPROBE = find_tool("ffprobe")


def run(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace")


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
    res = subprocess.run(args, capture_output=True)
    if res.returncode != 0 or len(res.stdout) != COVER_SIZE * COVER_SIZE * 3:
        return None
    name = hashlib.sha1(res.stdout).hexdigest()[:16] + ".png"
    dst = COVERS_DIR / name
    if not dst.exists():
        subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
                        "-s", f"{COVER_SIZE}x{COVER_SIZE}", "-i", "-", "-frames:v", "1", str(dst)],
                       input=res.stdout, capture_output=True)
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
PODCASTS_TEMPLATE = """# Kalimdor ZugZug Radio - podcasts to download with: python import_music.py --podcasts
# One podcast per line: the RSS feed URL (or the Apple Podcasts link) and, optionally,
# how many recent episodes to keep (default 3). Lines starting with # are ignored.
#
# https://example.com/feed/my-podcast.xml 3
# https://podcasts.apple.com/us/podcast/name/id1234567890 2
"""


MAX_PAGE_BYTES = 50 * 1024 * 1024        # feeds and API answers
MAX_DOWNLOAD_BYTES = 2 * 1024 * 1024 * 1024  # one episode or cover


def http_get(url: str, dst: Path | None = None, timeout: int = 60) -> bytes | None:
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
        with open(dst, "wb") as f:
            while chunk := r.read(1024 * 256):
                written += len(chunk)
                if written > limit:
                    raise RuntimeError("the file is too large")
                f.write(chunk)
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


def read_podcast_list(path: Path) -> list[tuple[str, int]]:
    entries = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        keep = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else DEFAULT_KEEP
        entries.append((parts[0], max(1, keep)))
    return entries


def split_episode(src: Path, out_dir: Path) -> int:
    """Converts to OGG and splits into PART_SECONDS-second parts; returns the number of parts."""
    out_dir.mkdir(parents=True, exist_ok=True)
    res = run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-i", str(src), "-map", "0:a:0", "-vn",
               "-c:a", "libvorbis", "-q:a", "3", "-f", "segment", "-segment_time", str(PART_SECONDS),
               "-reset_timestamps", "1", str(out_dir / "part_%03d.ogg")])
    if res.returncode != 0:
        raise RuntimeError(res.stderr.strip() or "conversion failed")
    return len(list(out_dir.glob("part_*.ogg")))


PODCASTS_FILE_NAMES = ("podcasts.txt", "podcast.txt")  # the singular is accepted too


def find_podcasts_file() -> Path | None:
    for name in PODCASTS_FILE_NAMES:
        if (DATA_DIR / name).is_file():
            return DATA_DIR / name
    return None


def update_podcasts(stats: dict) -> None:
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
    for url, keep in entries:
        try:
            feed_url = resolve_feed(url)
            show, image_url, episodes = parse_feed(http_get(feed_url))
        except Exception as exc:  # noqa: BLE001
            stats["warnings"].append(f"podcast {url}: {exc}")
            continue
        show_dir = root / show_dir_name(show)
        show_dir.mkdir(parents=True, exist_ok=True)
        print(f"[podcast] {show}: latest {keep} episodes")
        has_own_cover = any((show_dir / f"cover{ext}").exists() for ext in IMAGE_EXT)
        if image_url and not has_own_cover:
            ext = os.path.splitext(image_url.split("?")[0])[1].lower()
            try:
                http_get(image_url, show_dir / ("cover" + (ext if ext in IMAGE_EXT else ".jpg")))
            except Exception as exc:  # noqa: BLE001
                stats["warnings"].append(f"podcast {show}: cover not downloaded ({exc})")

        wanted = set()
        for ep in episodes[:keep]:
            key = hashlib.sha1((feed_url + "|" + ep["guid"]).encode("utf-8")).hexdigest()[:12]
            wanted.add(key)
            ep_dir = show_dir / f"{ep['date']} {key}"
            if (ep_dir / EPISODE_FILE).exists():
                continue
            print(f"  downloading {ep['date']} {ep['title']}")
            tmp_dir = show_dir / f"_tmp_{key}"
            shutil.rmtree(tmp_dir, ignore_errors=True)
            tmp_dir.mkdir()
            try:
                audio = tmp_dir / "episode.bin"
                http_get(ep["url"], audio, timeout=300)
                parts = split_episode(audio, tmp_dir / "parts")
                shutil.rmtree(ep_dir, ignore_errors=True)
                shutil.move(str(tmp_dir / "parts"), str(ep_dir))
                # episode.json last: marks the episode as complete
                (ep_dir / EPISODE_FILE).write_text(json.dumps(
                    {"key": key, "guid": ep["guid"], "title": ep["title"], "show": show, "date": ep["date"],
                     "feed": feed_url}, ensure_ascii=False, indent=1), encoding="utf-8")
                stats["podcast_new"] += 1
                print(f"    {parts} parts of {PART_SECONDS // 60}:{PART_SECONDS % 60:02d}")
            except Exception as exc:  # noqa: BLE001
                stats["warnings"].append(f"podcast {show} / {ep['title']}: {exc}")
            finally:
                shutil.rmtree(tmp_dir, ignore_errors=True)

        # episodes older than the ones to keep are deleted (not when the feed came back empty:
        # a server error page must not wipe the downloaded episodes)
        for d in (show_dir.iterdir() if wanted else ()):
            meta = d / EPISODE_FILE
            if d.is_dir() and meta.exists():
                if json.loads(meta.read_text(encoding="utf-8")).get("key") not in wanted:
                    shutil.rmtree(d)
                    stats["podcast_removed"] += 1
                    print(f"  deleting old episode {d.name}")
    print()


def process_episode(folder: Path, stats: dict) -> list[dict]:
    """One episode = several OGG parts; in-game they become a single item ('episode' field)."""
    meta = json.loads((folder / EPISODE_FILE).read_text(encoding="utf-8"))
    parts = sorted(folder.glob("part_*.ogg"))
    cover_src = folder_cover(folder)
    cover = cover_for(f"folder:{cover_src.parent.relative_to(MUSIC_DIR).as_posix()}", cover_src) if cover_src else None
    tracks = []
    for i, path in enumerate(parts, 1):
        try:
            duration = duration_of(probe(path))
        except Exception as exc:  # noqa: BLE001
            stats["warnings"].append(f"{folder.name}/{path.name}: {exc}")
            continue
        tracks.append({
            "file": wow_path(path), "folder": f"{PODCAST_DIR_NAME}/{meta['show']}",
            "title": meta["title"], "artist": meta["show"], "album": meta["date"], "duration": duration,
            "cover": wow_path(COVERS_DIR / cover) if cover else None,
            "episode": meta["key"], "part": i, "parts": len(parts),
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
        try:
            info = probe(path)
        except Exception as exc:  # noqa: BLE001
            stats["warnings"].append(f"{label}/{path.name}: {exc}")
            continue
        tags = tags_of(info)
        g_artist, g_title = guess_from_filename(original_names.get(path.stem, path.stem))
        rel = wow_path(path)

        pic = attached_pic_index(info)
        cover = cover_for(rel, path, pic) if pic is not None else cached_cover(rel)
        cover = cover or shared_cover

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
            "genre": genre_of(path, tags),
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
            g = mp4_genre(src)
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
                pic = attached_pic_index(probe(src))
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
        if t.get("episode"):
            fields += [f"episode = {lua_str(t['episode'])}", f"part = {t['part']}", f"parts = {t['parts']}"]
        lines.append("    { " + ", ".join(fields) + " },")
    lines += ["  },", "}", ""]
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


def main() -> None:
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
    parser.add_argument("--addon", metavar="FOLDER",
                        help=f"addon folder (the one with {ADDON_NAME}.toc), if it isn't found automatically")
    parser.add_argument("--no-menu", action="store_true",
                        help="don't show the interactive menu (it appears when the script starts with no options)")
    args = parser.parse_args()
    interactive = len(sys.argv) == 1 and sys.stdin is not None and sys.stdin.isatty()

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
    set_addon_dir(addon)
    stats = {"converted": 0, "renamed": 0, "deleted": 0, "copied": 0, "moved": 0, "podcast_new": 0,
             "podcast_removed": 0, "warnings": []}
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
    if interactive:
        saved = load_settings().get("library")
        if saved and Path(saved).is_dir():
            args.library = saved
        if not interactive_menu(args):
            print("Nothing done.")
            return

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
            if interactive and ask(" Copy them into the addon and import them? [Y/n] ").lower() in ("n", "no", "q"):
                missing = []
        else:
            print(" Nothing new: music/ already has every track of your library.")
        print()
    print(f"Addon: {ADDON_DIR}\n")
    COVERS_DIR.mkdir(exist_ok=True)

    # podcasts: always checked when podcasts.txt exists (unless --no-podcasts); --podcasts creates the template
    do_podcasts = not args.no_podcasts and (args.podcasts or find_podcasts_file() is not None)
    if do_podcasts:
        update_podcasts(stats)
    if not args.keep_originals and ORIGINALS_DIR.is_dir():
        print(f"  deleting {ORIGINALS_DIR} (use --keep-originals to keep it)")
        shutil.rmtree(ORIGINALS_DIR)
    load_cover_index()
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
    for folder in folders:
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

    write_library(tracks)
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


if __name__ == "__main__":
    main()
