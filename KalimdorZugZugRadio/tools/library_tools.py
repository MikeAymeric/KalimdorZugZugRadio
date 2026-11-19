"""Library tools of Import music.py (2.0): duplicate tracks and covers from the internet.

Both work on the tracks of the last import (music/_library.json) and never delete anything:
- duplicates: the same song (same title and artist, about the same length) or the same recording
  under another name (same length and the same loudness curve, measured by the import). Removed
  files are moved to <data addon>/_duplicates/, and _aliases.json tells the addon which track was
  kept, so playlists, favourites, ratings and stats follow it.
- covers: albums without a cover are looked up on MusicBrainz (album and artist names only) and
  their front cover downloaded from the Cover Art Archive, after the user confirms it. Covers go to
  music/_covers_found/ and are used by the next import.
Uses only the standard library (and ffmpeg, for the previews).
"""
from __future__ import annotations

import hashlib
import json
import re
import shutil
import tempfile
import threading
import time
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path
from urllib.parse import urlencode

import import_music as im

DUPLICATES_DIR_NAME = "_duplicates"


def library_tracks() -> list[dict] | None:
    """The tracks of the last import, or None if music/ was never imported with 2.0."""
    data = im.read_json(im.MUSIC_DIR / im.LIBRARY_INDEX_NAME, None)
    return [t for t in data if isinstance(t, dict) and isinstance(t.get("file"), str)] if isinstance(data, list) else None


def mmss(seconds: float) -> str:
    seconds = int(round(seconds))
    return f"{seconds // 60}:{seconds % 60:02d}"


def track_path(t: dict) -> Path:
    return im.DATA_DIR / t["file"].replace("\\", "/")


def norm(text: str | None) -> str:
    """Letters and digits only, case and width folded: "Don't Stop (Remix)" -> "dontstopremix"."""
    return re.sub(r"[\W_]+", "", unicodedata.normalize("NFKC", text or "").casefold())


# --- Duplicates ---------------------------------------------------------------------
TITLE_SECONDS = 2.0   # same title and artist: lengths this close (a live or extended version is longer)
AUDIO_SECONDS = 1.0   # same recording: lengths this close...
AUDIO_LU = 1.0        # ... and loudness curves this close (mean difference, LU)
AUDIO_POINTS = 20     # ... over at least this many seconds of sound


def curve_distance(a: list[int], b: list[int]) -> float | None:
    """Mean difference of two loudness curves over the seconds where both have sound."""
    diffs = [abs(x - y) for x, y in zip(a, b) if x > -60 and y > -60]
    return sum(diffs) / len(diffs) if len(diffs) >= AUDIO_POINTS else None


def find_duplicates(tracks: list[dict], curves: dict[str, list[int]]) -> list[dict]:
    """Groups of duplicates: [{"reason": "title"|"audio", "tracks": [track, ...]}], largest first.
    curves: track id -> loudness curve (from the probe cache)."""
    music = [t for t in tracks if not t.get("episode") and (t.get("duration") or 0) > 0]
    parent = list(range(len(music)))
    reason: dict[int, str] = {}

    def root(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    def join(i: int, j: int, why: str) -> None:
        ri, rj = root(i), root(j)
        if ri != rj:
            parent[rj] = ri
            reason[ri] = "audio" if "audio" in (why, reason.get(ri), reason.get(rj)) else why

    by_name: dict[tuple[str, str], list[int]] = defaultdict(list)
    for i, t in enumerate(music):
        title = norm(t.get("title"))
        if title:
            by_name[(norm(t.get("artist")), title)].append(i)
    for idx in by_name.values():
        for a in range(len(idx)):
            for b in range(a + 1, len(idx)):
                if abs(music[idx[a]]["duration"] - music[idx[b]]["duration"]) <= TITLE_SECONDS:
                    join(idx[a], idx[b], "title")

    order = sorted(range(len(music)), key=lambda i: music[i]["duration"])
    for pos, i in enumerate(order):
        ci = curves.get(music[i]["file"])
        if not ci or music[i]["duration"] < 30:
            continue
        for j in order[pos + 1:]:
            if music[j]["duration"] - music[i]["duration"] > AUDIO_SECONDS:
                break
            cj = curves.get(music[j]["file"])
            d = curve_distance(ci, cj) if cj else None
            if d is not None and d <= AUDIO_LU:
                join(i, j, "audio")

    groups: dict[int, list[dict]] = defaultdict(list)
    for i, t in enumerate(music):
        groups[root(i)].append(t)
    out = [{"reason": reason.get(r, "title"), "tracks": g} for r, g in groups.items() if len(g) > 1]
    out.sort(key=lambda g: (-len(g["tracks"]), norm(g["tracks"][0].get("title"))))
    return out


def quality(t: dict) -> tuple:
    """Higher is better: has a cover, then bitrate (file size per second), then a shorter path."""
    try:
        size = track_path(t).stat().st_size
    except OSError:
        size = 0
    return (1 if t.get("cover") else 0, size / max(t.get("duration") or 1, 1), -len(t["file"]))


def bitrate_kbps(t: dict) -> int:
    try:
        return round(track_path(t).stat().st_size * 8 / 1000 / max(t.get("duration") or 1, 1))
    except OSError:
        return 0


def best_of(group: list[dict]) -> dict:
    return max(group, key=quality)


def duplicate_groups() -> list[dict] | None:
    """find_duplicates over the last import (None: import first)."""
    tracks = library_tracks()
    if tracks is None:
        return None
    cache = im.read_json(im.MUSIC_DIR / im.PROBE_CACHE_NAME, {})
    curves = {k: e["curve"] for k, e in cache.items() if isinstance(e, dict) and isinstance(e.get("curve"), list)}
    return find_duplicates(tracks, curves)


def move_duplicates(pairs: list[tuple[dict, dict]]) -> int:
    """pairs = (track to remove, track kept). Moves the files to _duplicates/ (same subfolders) and
    records the aliases. Returns how many files were moved."""
    aliases = im.read_json(im.MUSIC_DIR / im.ALIASES_NAME, {})
    target_root = im.DATA_DIR / DUPLICATES_DIR_NAME
    moved = 0
    for gone, kept in pairs:
        if gone["file"] == kept["file"]:
            continue
        src = track_path(gone)
        if src.is_file():
            dst = target_root / gone["file"].replace("\\", "/")
            dst.parent.mkdir(parents=True, exist_ok=True)
            n = 1
            while dst.exists():  # never overwrite an earlier removed copy
                dst = dst.with_name(f"{dst.stem} ({n}){dst.suffix}")
                n += 1
            shutil.move(str(src), str(dst))
            moved += 1
        aliases[gone["file"]] = kept["file"]
    im.write_json(im.MUSIC_DIR / im.ALIASES_NAME, aliases)
    return moved


def print_duplicates() -> None:
    """--find-duplicates: lists the groups (nothing is moved from the command line)."""
    groups = duplicate_groups()
    if groups is None:
        print("Import your music once first: duplicates are searched among the imported tracks.")
        return
    if not groups:
        print("No duplicates found.")
        return
    print(f"{len(groups)} groups of duplicates (move them with the Import music window):")
    for g in groups:
        keep = best_of(g["tracks"])
        print(f"\n  [{'same recording' if g['reason'] == 'audio' else 'same title'}]")
        for t in g["tracks"]:
            mark = "keep" if t is keep else "    "
            print(f"   {mark}  {mmss(t.get('duration') or 0)}  {bitrate_kbps(t):4} kbps  {t['file']}")


# --- Covers from the internet ---------------------------------------------------------
MB_SEARCH = "https://musicbrainz.org/ws/2/release/"
CAA = "https://coverartarchive.org"
MB_INTERVAL = 1.1  # MusicBrainz allows one request per second
MAX_CANDIDATES = 4
_mb_lock = threading.Lock()
_mb_last = [0.0]


def albums_without_cover(tracks: list[dict]) -> list[dict]:
    """[{"key", "folder", "album", "artist", "ids"}] for the tracks that have no cover, grouped by
    their folder and album tag. Tracks that already have a found cover waiting for the import are left out."""
    im.load_found_covers()
    groups: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for t in tracks:
        if t.get("cover") or t.get("episode") or t["file"] in im.found_covers:
            continue
        folder = t["file"].replace("\\", "/").rsplit("/", 1)[0]
        groups[(folder, norm(t.get("album")))].append(t)
    out = []
    for (folder, _), ts in groups.items():
        album = Counter(t.get("album") for t in ts if t.get("album")).most_common(1)
        artist = Counter(t.get("artist") for t in ts if t.get("artist")).most_common(1)
        shown = ts[0].get("folder") or folder
        out.append({"key": f"{folder}|{norm(ts[0].get('album'))}", "folder": shown,
                    "album": album[0][0] if album else shown.rsplit("/", 1)[-1],
                    "artist": artist[0][0] if artist else "", "ids": [t["file"] for t in ts]})
    out.sort(key=lambda a: (a["folder"].casefold(), a["album"].casefold()))
    return out


def lucene(text: str) -> str:
    return text.replace("\\", "\\\\").replace('"', '\\"')


def search_releases(album: str, artist: str) -> list[dict]:
    """MusicBrainz releases matching album (and artist): [{"title", "artist", "date", "release", "group"}]."""
    query = f'release:"{lucene(album)}"' + (f' AND artist:"{lucene(artist)}"' if artist else "")
    url = MB_SEARCH + "?" + urlencode({"query": query, "fmt": "json", "limit": "10"})
    import urllib.error
    data: dict = {}
    with _mb_lock:
        for attempt in range(4):  # 503 = too many requests: wait longer and try again
            wait = _mb_last[0] + MB_INTERVAL * (1 + 2 * attempt) - time.monotonic()
            if wait > 0:
                time.sleep(wait)
            try:
                data = json.loads(im.http_get(url, timeout=30) or b"{}")
                break
            except urllib.error.HTTPError as exc:
                if exc.code != 503 or attempt == 3:
                    raise
            finally:
                _mb_last[0] = time.monotonic()
    out, groups = [], set()
    for r in data.get("releases", []):
        if (r.get("score") or 0) < 70:
            continue
        group = (r.get("release-group") or {}).get("id")
        if group in groups:
            continue
        groups.add(group)
        credit = " ".join((c.get("name") or "") + (c.get("joinphrase") or "") for c in r.get("artist-credit") or [])
        out.append({"title": r.get("title") or "", "artist": credit.strip(), "date": (r.get("date") or "")[:4],
                    "release": r.get("id"), "group": group})
        if len(out) >= MAX_CANDIDATES:
            break
    return out


def image_kind(data: bytes) -> str | None:
    if data[:3] == b"\xff\xd8\xff":
        return ".jpg"
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return ".png"
    return None


def download_cover(candidate: dict) -> bytes | None:
    """The front cover of a release (or of its release group), 250 px, or None."""
    import urllib.error
    for kind, mbid in (("release-group", candidate.get("group")), ("release", candidate.get("release"))):
        if not mbid or not re.fullmatch(r"[0-9a-f-]{36}", mbid):
            continue
        try:
            data = im.http_get(f"{CAA}/{kind}/{mbid}/front-250", timeout=30)
        except (urllib.error.URLError, OSError, RuntimeError):
            continue
        if data and image_kind(data):
            return data
    return None


def preview_png(data: bytes, size: int = 200) -> Path | None:
    """A PNG copy of an image for the window (tkinter can't show JPEG), in a temporary folder."""
    folder = Path(tempfile.mkdtemp(prefix="kzzr_cover_"))
    src = folder / ("cover" + (image_kind(data) or ".jpg"))
    src.write_bytes(data)
    dst = folder / "preview.png"
    res = im.run([im.FFMPEG, "-y", "-v", "error", "-i", str(src), "-vf",
                  f"scale={size}:{size}:force_original_aspect_ratio=decrease", str(dst)])
    return dst if res.returncode == 0 and dst.is_file() else None


def save_found_cover(ids: list[str], data: bytes) -> str | None:
    """Stores an image for the given tracks; the next import renders it as their cover."""
    ext = image_kind(data)
    if not ext:
        return None
    folder = im.MUSIC_DIR / im.FOUND_COVERS_DIR_NAME
    folder.mkdir(parents=True, exist_ok=True)
    name = hashlib.sha1(data).hexdigest()[:16] + ext
    (folder / name).write_bytes(data)
    mapping = im.read_json(folder / im.FOUND_COVERS_MAP, {})
    for track_id in ids:
        mapping[track_id] = name
    im.write_json(folder / im.FOUND_COVERS_MAP, mapping)
    return name
