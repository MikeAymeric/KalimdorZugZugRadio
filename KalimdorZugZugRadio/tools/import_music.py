"""Imports music (and podcasts) for Kalimdor ZugZug Radio.

Recursively scans KalimdorZugZugRadio/music/ (subfolders are only for organizing:
playlists are created in-game), converts formats WoW can't play (mp4, m4a, flac,
wav, ...) to OGG, extracts covers (embedded, or cover.jpg/folder.jpg in the folder)
as deduplicated 256x256 PNGs and generates Library.lua.

Usage:  python import_music.py [--addon FOLDER] [--keep-originals] [--keep-names] [--podcasts]
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
from datetime import datetime
from pathlib import Path

ADDON_NAME = "KalimdorZugZugRadio"
# Set by set_addon_dir() in main().
ADDON_DIR = MUSIC_DIR = COVERS_DIR = LIBRARY_FILE = ORIGINALS_DIR = Path()


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
    global ADDON_DIR, MUSIC_DIR, COVERS_DIR, LIBRARY_FILE, ORIGINALS_DIR
    ADDON_DIR = path
    MUSIC_DIR = ADDON_DIR / "music"
    COVERS_DIR = ADDON_DIR / "covers"
    LIBRARY_FILE = ADDON_DIR / "Library.lua"
    ORIGINALS_DIR = MUSIC_DIR / "_originals"

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


def save_cover_index() -> None:
    kept = {k: v for k, v in cover_index.items() if k in seen_cover_keys}
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
    res = run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-i", str(src),
               "-map", "0:a:0", "-vn", "-map_metadata", "0",
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


def lua_str(s: str) -> str:
    s = s.replace("\\", "\\\\").replace('"', '\\"').replace("\r", "").replace("\n", " ")
    return f'"{s}"'


def lua_text(s: str) -> str:
    """Displayed text: NFC, because WoW draws decomposed marks (e.g. macOS file names) as separate glyphs.
    Not for `file`, which must match the name on disk and is the track id."""
    return lua_str(unicodedata.normalize("NFC", s))


def wow_path(p: Path) -> str:
    return str(p.relative_to(ADDON_DIR)).replace("/", "\\")


def folder_cover(folder: Path) -> Path | None:
    """cover.jpg/folder.jpg/... in the folder or a parent folder (inside music/)."""
    for d in (folder, *folder.parents):
        for name in FOLDER_COVERS:
            for ext in IMAGE_EXT:
                for candidate in (d / f"{name}{ext}", d / f"{name.capitalize()}{ext}"):
                    if candidate.exists():
                        return candidate
        if d == MUSIC_DIR:
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


def http_get(url: str, dst: Path | None = None, timeout: int = 60) -> bytes | None:
    import urllib.request
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        if dst is None:
            return r.read()
        with open(dst, "wb") as f:
            shutil.copyfileobj(r, f, 1024 * 256)
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
        if (ADDON_DIR / name).is_file():
            return ADDON_DIR / name
    return None


def update_podcasts(stats: dict) -> None:
    podcasts_file = find_podcasts_file()
    if not podcasts_file:
        podcasts_file = ADDON_DIR / PODCASTS_FILE_NAMES[0]
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

        # episodes older than the ones to keep are deleted
        for d in show_dir.iterdir():
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
            if pic is not None:
                cover_for(wow_path(dst), src, pic)
            if not dst.exists():
                print(f"  converting {label}/{src.name} -> {dst.name}")
                convert_to_ogg(src, dst)
                stats["converted"] += 1
            if not converted_ok(dst):
                raise RuntimeError("the converted OGG is not readable: original left in place")
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
        })
    return tracks


def write_library(tracks: list[dict]) -> None:
    lines = [
        "-- GENERATED by tools/import_music.py: do not edit by hand.",
        "-- 'file' is also the track id used by the playlists saved in-game.",
        "KZZR_Library = {",
        f'  generated = "{datetime.now():%Y-%m-%d %H:%M}",',
        "  tracks = {",
    ]
    for t in tracks:
        fields = [f"file = {lua_str(t['file'])}", f"folder = {lua_text(t['folder'])}",
                  f"title = {lua_text(t['title'])}", f"artist = {lua_text(t['artist'])}",
                  f"album = {lua_text(t['album'])}", f"duration = {t['duration']}"]
        if t["cover"]:
            fields.append(f"cover = {lua_str(t['cover'])}")
        if t.get("episode"):
            fields += [f"episode = {lua_str(t['episode'])}", f"part = {t['part']}", f"parts = {t['parts']}"]
        lines.append("    { " + ", ".join(fields) + " },")
    lines += ["  },", "}", ""]
    LIBRARY_FILE.write_text("\n".join(lines), encoding="utf-8")


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
    parser.add_argument("--addon", metavar="FOLDER",
                        help=f"addon folder (the one with {ADDON_NAME}.toc), if it isn't found automatically")
    args = parser.parse_args()

    addon = find_addon_dir(args.addon)
    if not addon:
        sys.exit(f"ERROR: the {ADDON_NAME} addon was not found. Install it in "
                 f"World of Warcraft/_forever_/Interface/AddOns/ first, or pass its folder with "
                 f"--addon \"path\\{ADDON_NAME}\"")
    set_addon_dir(addon)
    print(f"Addon: {ADDON_DIR}\n")
    if not MUSIC_DIR.is_dir():
        sys.exit(f"ERROR: folder {MUSIC_DIR} not found")
    COVERS_DIR.mkdir(exist_ok=True)

    # migration from the Italian file/folder names used by versions <= 0.4
    legacy_names = MUSIC_DIR / LEGACY_NAMES_FILE_NAME
    if legacy_names.exists() and not (MUSIC_DIR / NAMES_FILE_NAME).exists():
        legacy_names.rename(MUSIC_DIR / NAMES_FILE_NAME)
    legacy_originals = MUSIC_DIR / "_originali"
    if legacy_originals.is_dir() and not ORIGINALS_DIR.exists():
        legacy_originals.rename(ORIGINALS_DIR)

    stats = {"converted": 0, "renamed": 0, "deleted": 0, "podcast_new": 0, "podcast_removed": 0, "warnings": []}
    # podcasts: always checked when podcasts.txt exists (unless --no-podcasts); --podcasts creates the template
    do_podcasts = not args.no_podcasts and (args.podcasts or find_podcasts_file() is not None)
    if do_podcasts:
        update_podcasts(stats)
    if not args.keep_originals and ORIGINALS_DIR.is_dir():
        print(f"  deleting {ORIGINALS_DIR.relative_to(ADDON_DIR)} (use --keep-originals to keep it)")
        shutil.rmtree(ORIGINALS_DIR)
    load_original_names()
    load_cover_index()
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

    write_library(tracks)
    save_cover_index()
    removed = remove_unused_covers(tracks)
    unique = len({t["cover"] for t in tracks if t["cover"]})
    with_cover = sum(1 for t in tracks if t["cover"])
    print(f"\nLibrary.lua written: {len(tracks)} tracks, {stats['converted']} converted, "
          f"{stats['deleted']} originals deleted, {stats['renamed']} renamed.")
    print(f"Covers: {unique} distinct images for {with_cover} tracks"
          + (f" ({removed} unused files removed)" if removed else "") + ".")
    if do_podcasts:
        episodes = len({t["episode"] for t in tracks if t.get("episode")})
        print(f"Podcasts: {episodes} episodes in the library ({stats['podcast_new']} new, "
              f"{stats['podcast_removed']} old ones deleted).")
    for w in stats["warnings"]:
        print(f"  WARNING: {w}")
    print("\nIf you added new files, RESTART the game client; if only Library.lua changed, /reload is enough.")
    print("Playlists are created in-game: /kzz lib")


if __name__ == "__main__":
    main()
