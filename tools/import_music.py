"""Importa la musica per Kalimdor ZugZug Radio.

Scansiona ricorsivamente KalimdorZugZugRadio/music/ (le sottocartelle servono solo
a organizzare: le playlist si creano in gioco), converte in OGG i formati che
WoW non suona (mp4, m4a, flac, wav, ...), estrae le copertine (incorporate o
cover.jpg/folder.jpg della cartella) in PNG 256x256 e genera Library.lua.

Uso:  python import_music.py [--addon CARTELLA] [--keep-originals]
La cartella dell'addon si trova da sola se lanci lo script da dentro l'addon (o una
sua sottocartella) oppure dalla cartella del progetto; altrimenti indicala con --addon.
Richiede ffmpeg e ffprobe (PATH o installazione winget Gyan.FFmpeg).
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
# Impostati da set_addon_dir() in main().
ADDON_DIR = MUSIC_DIR = COVERS_DIR = LIBRARY_FILE = ORIGINALS_DIR = Path()


def find_addon_dir(explicit: str | None) -> Path | None:
    """La cartella che contiene KalimdorZugZugRadio.toc, cercando da cwd e dalla posizione dello script."""
    def check(p: Path) -> Path | None:
        if (p / f"{ADDON_NAME}.toc").is_file():
            return p
        if (p / ADDON_NAME / f"{ADDON_NAME}.toc").is_file():
            return p / ADDON_NAME
        return None

    if explicit:
        return check(Path(explicit).expanduser().resolve())
    for start in (Path.cwd().resolve(), Path(__file__).resolve().parent):
        for p in (start, *start.parents):
            found = check(p)
            if found:
                return found
    return None


def set_addon_dir(path: Path) -> None:
    global ADDON_DIR, MUSIC_DIR, COVERS_DIR, LIBRARY_FILE, ORIGINALS_DIR
    ADDON_DIR = path
    MUSIC_DIR = ADDON_DIR / "music"
    COVERS_DIR = ADDON_DIR / "covers"
    LIBRARY_FILE = ADDON_DIR / "Library.lua"
    ORIGINALS_DIR = MUSIC_DIR / "_originali"

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
    sys.exit(f"ERRORE: {name} non trovato. Installa ffmpeg (winget install Gyan.FFmpeg).")


if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

FFMPEG = find_tool("ffmpeg")
FFPROBE = find_tool("ffprobe")


def run(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace")


def probe(path: Path) -> dict:
    res = run([FFPROBE, "-v", "error", "-print_format", "json", "-show_format", "-show_streams", str(path)])
    if res.returncode != 0:
        raise RuntimeError(res.stderr.strip() or "ffprobe fallito")
    return json.loads(res.stdout or "{}")


def tags_of(info: dict) -> dict:
    """Tag in minuscolo da formato + stream audio (OGG li mette sullo stream)."""
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


# --- Copertine deduplicate ---------------------------------------------------
# Ogni copertina viene ridotta a 256x256 e identificata dall'hash dei suoi pixel:
# brani con la stessa immagine puntano allo stesso PNG. covers/_index.json ricorda
# quale copertina ha ogni brano, così non si riestrae a ogni esecuzione.
COVER_INDEX_NAME = "_index.json"
cover_index: dict[str, dict] = {}  # chiave (percorso brano o "folder:<cartella>") -> {"cover", "mtime"}
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
    """Estrae l'immagine, la porta a 256x256 e la salva come covers/<hash pixel>.png."""
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
    """Copertina (nome file in covers/) per la chiave data, riusando l'indice se src non è cambiato."""
    seen_cover_keys.add(key)
    mtime = src.stat().st_mtime
    entry = cover_index.get(key)
    if entry and entry.get("mtime") == mtime and entry.get("cover") and (COVERS_DIR / entry["cover"]).exists():
        return entry["cover"]
    name = render_cover(src, stream_index)
    cover_index[key] = {"cover": name, "mtime": mtime}
    return name


def cached_cover(key: str) -> str | None:
    """Copertina già nota per un brano il cui file sorgente non c'è più (es. MP4 convertito ed eliminato)."""
    entry = cover_index.get(key)
    if entry and entry.get("cover") and (COVERS_DIR / entry["cover"]).exists():
        seen_cover_keys.add(key)
        return entry["cover"]
    # migrazione dalle versioni precedenti: covers/<hash del percorso>.png, una per brano
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
        raise RuntimeError(res.stderr.strip() or "conversione fallita")


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


def wow_path(p: Path) -> str:
    return str(p.relative_to(ADDON_DIR)).replace("/", "\\")


def folder_cover(folder: Path) -> Path | None:
    for name in FOLDER_COVERS:
        for ext in IMAGE_EXT:
            for candidate in (folder / f"{name}{ext}", folder / f"{name.capitalize()}{ext}"):
                if candidate.exists():
                    return candidate
    return None


def is_skipped_dir(name: str) -> bool:
    return name.startswith(("_", "."))


# --- Nomi solo ASCII ---------------------------------------------------------
# WoW potrebbe non aprire file con caratteri non latini nel percorso: rinominiamo
# file e cartelle in ASCII e salviamo i nomi originali per mostrarli in gioco.
NAMES_FILE_NAME = "_nomi_originali.json"
SAFE_CHARS = re.compile(r"[^A-Za-z0-9 ._()\[\]&+,'!-]")
original_names: dict[str, str] = {}  # nome ASCII (senza estensione per i file) -> nome originale


def safe_name(name: str, is_file: bool) -> str:
    stem, ext = (os.path.splitext(name) if is_file else (name, ""))
    if stem.isascii() and ext.isascii():
        return name
    # NFKD: "é" -> "e", "（" -> "("; kana e kanji spariscono
    ascii_stem = unicodedata.normalize("NFKD", stem).encode("ascii", "ignore").decode()
    ascii_stem = SAFE_CHARS.sub("", ascii_stem)
    ascii_stem = re.sub(r"\(\s*\)|\[\s*\]", "", ascii_stem)        # parentesi rimaste vuote
    ascii_stem = re.sub(r"\s*,[\s,]*", ", ", ascii_stem)            # virgole rimaste in fila
    ascii_stem = re.sub(r"[\s_]+", " ", ascii_stem).strip(" ._-,")
    tag = hashlib.sha1(stem.encode("utf-8")).hexdigest()[:6]      # stabile e senza collisioni
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
    """Rinomina (dal basso verso l'alto) file e cartelle non ASCII dentro music/."""
    for root, dirs, files in os.walk(MUSIC_DIR, topdown=False):
        rel = Path(root).relative_to(MUSIC_DIR)
        if any(is_skipped_dir(part) for part in rel.parts):
            continue
        entries = [(f, True) for f in files if f != NAMES_FILE_NAME] + [(d, False) for d in dirs if not is_skipped_dir(d)]
        for name, is_file in entries:
            new = safe_name(name, is_file)
            if new == name:
                continue
            src, dst = Path(root) / name, Path(root) / new
            if dst.exists():
                stats["warnings"].append(f"{rel.as_posix()}/{name}: non rinominato, esiste già {new}")
                continue
            src.rename(dst)
            key = os.path.splitext(new)[0] if is_file else new
            original_names[key] = os.path.splitext(name)[0] if is_file else name
            stats["renamed"] += 1
            print(f"  rinomino {name} -> {new}")


def display_folder(rel_folder: str) -> str:
    return "/".join(original_names.get(part, part) for part in rel_folder.split("/")) if rel_folder else ""


def process_folder(folder: Path, keep_originals: bool, stats: dict) -> list[dict]:
    rel_folder = folder.relative_to(MUSIC_DIR).as_posix()
    rel_folder = "" if rel_folder == "." else rel_folder
    label = rel_folder or "(music)"
    files = sorted(p for p in folder.iterdir() if p.is_file())

    # 1) conversione dei formati non supportati
    for src in files:
        if src.suffix.lower() not in CONVERT:
            continue
        dst = src.with_suffix(".ogg")
        try:
            # la copertina va presa dall'originale: l'OGG non la contiene
            pic = attached_pic_index(probe(src))
            if pic is not None:
                cover_for(wow_path(dst), src, pic)
            if not dst.exists():
                print(f"  converto {label}/{src.name} -> {dst.name}")
                convert_to_ogg(src, dst)
                stats["converted"] += 1
            if not converted_ok(dst):
                raise RuntimeError("l'OGG convertito non è leggibile: originale lasciato al suo posto")
            if keep_originals:
                target = ORIGINALS_DIR / rel_folder / (original_names.get(src.stem, src.stem) + src.suffix)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(src), str(target))
            else:
                src.unlink()
                stats["deleted"] += 1
        except Exception as exc:  # noqa: BLE001 - un brano rotto non deve fermare tutto
            stats["warnings"].append(f"{label}/{src.name}: {exc}")

    # 2) catalogo dei file suonabili
    shared_cover = None
    shared_cover_src = folder_cover(folder)
    if shared_cover_src:
        shared_cover = cover_for(f"folder:{rel_folder}", shared_cover_src)

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
            stats["warnings"].append(f"{label}/{path.name}: durata sconosciuta (non avanzerà da solo)")
        if not rel.isascii():
            stats["warnings"].append(f"{label}/{path.name}: il percorso contiene caratteri non ASCII; "
                                     "se in gioco non suona, rinominalo")

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
        "-- File GENERATO da tools/import_music.py: non modificarlo a mano.",
        "-- 'file' è anche l'identificativo del brano usato dalle playlist salvate in gioco.",
        "KZZR_Library = {",
        f'  generated = "{datetime.now():%Y-%m-%d %H:%M}",',
        "  tracks = {",
    ]
    for t in tracks:
        fields = [f"file = {lua_str(t['file'])}", f"folder = {lua_str(t['folder'])}",
                  f"title = {lua_str(t['title'])}", f"artist = {lua_str(t['artist'])}",
                  f"album = {lua_str(t['album'])}", f"duration = {t['duration']}"]
        if t["cover"]:
            fields.append(f"cover = {lua_str(t['cover'])}")
        lines.append("    { " + ", ".join(fields) + " },")
    lines += ["  },", "}", ""]
    LIBRARY_FILE.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--keep-names", action="store_true",
                        help="non rinominare file e cartelle con caratteri non latini (giapponese, accenti, ...)")
    parser.add_argument("--keep-originals", action="store_true",
                        help="conserva gli originali convertiti in music/_originali (senza questa opzione vengono "
                             "eliminati, insieme alla cartella _originali)")
    parser.add_argument("--addon", metavar="CARTELLA",
                        help=f"cartella dell'addon (quella con {ADDON_NAME}.toc), se non viene trovata da sola")
    args = parser.parse_args()

    addon = find_addon_dir(args.addon)
    if not addon:
        sys.exit(f"ERRORE: non trovo la cartella dell'addon ({ADDON_NAME}.toc). "
                 f"Lancia lo script da dentro l'addon oppure usa --addon \"percorso\\{ADDON_NAME}\"")
    set_addon_dir(addon)
    print(f"Addon: {ADDON_DIR}\n")
    if not MUSIC_DIR.is_dir():
        sys.exit(f"ERRORE: cartella {MUSIC_DIR} non trovata")
    COVERS_DIR.mkdir(exist_ok=True)

    stats = {"converted": 0, "renamed": 0, "deleted": 0, "warnings": []}
    if not args.keep_originals and ORIGINALS_DIR.is_dir():
        print(f"  elimino {ORIGINALS_DIR.relative_to(ADDON_DIR)} (usa --keep-originals per conservarla)")
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
            print(f"[{folder.relative_to(MUSIC_DIR).as_posix()}] {len(found)} brani")
        tracks.extend(found)

    write_library(tracks)
    save_cover_index()
    removed = remove_unused_covers(tracks)
    unique = len({t["cover"] for t in tracks if t["cover"]})
    with_cover = sum(1 for t in tracks if t["cover"])
    print(f"\nLibrary.lua scritto: {len(tracks)} brani, {stats['converted']} convertiti, "
          f"{stats['deleted']} originali eliminati, {stats['renamed']} rinominati.")
    print(f"Copertine: {unique} immagini diverse per {with_cover} brani"
          + (f" ({removed} file inutilizzati rimossi)" if removed else "") + ".")
    for w in stats["warnings"]:
        print(f"  ATTENZIONE: {w}")
    print("\nSe hai aggiunto file nuovi RIAVVIA il client; se è cambiato solo Library.lua basta /reload.")
    print("Le playlist si creano in gioco: /kzz lib")


if __name__ == "__main__":
    main()
