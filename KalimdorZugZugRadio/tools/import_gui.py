"""Kalimdor ZugZug Radio - the window of Import music.py.

A small tkinter window (tkinter ships with Python on Windows and macOS) over import_music.py, for
people who never used a terminal: add files or folders with the usual Windows dialogs, pick the
options with checkboxes, manage podcasts, press Import, follow the progress. ffmpeg is downloaded on
first use. The window speaks the addon's language (import_strings.py); the detailed log stays English.
The import itself runs in a worker thread; its printed output goes to the log in the window.
Started by "Import music.py" when it gets no options (python "Import music.py" --menu shows the
text menu instead). Uses only the standard library.
"""
from __future__ import annotations

import os
import queue
import shutil
import subprocess
import sys
import threading
import time
import traceback
from pathlib import Path

import tkinter as tk
from tkinter import filedialog, messagebox, simpledialog, ttk
from tkinter.scrolledtext import ScrolledText

sys.path.insert(0, str(Path(__file__).resolve().parent))
import import_music as im  # noqa: E402
from import_strings import Texts, detect_language  # noqa: E402

ISSUES_URL = "https://github.com/MikeAymeric/KalimdorZugZugRadio/issues"
WRAP = 620
T = Texts(detect_language(None))  # replaced once the addon (and its SavedVariables) is found


def open_path(path: Path) -> None:
    """Opens a folder in Explorer, or a file in its usual program."""
    if hasattr(os, "startfile"):
        os.startfile(path)  # noqa: S606
    else:
        subprocess.Popen(["open" if sys.platform == "darwin" else "xdg-open", str(path)])


def music_counts() -> tuple[int, int]:
    tracks = to_convert = 0
    for _, dirs, files in os.walk(im.MUSIC_DIR):
        dirs[:] = [d for d in dirs if not im.is_skipped_dir(d)]
        for f in files:
            ext = os.path.splitext(f)[1].lower()
            tracks += ext in im.NATIVE
            to_convert += ext in im.CONVERT
    return tracks + to_convert, to_convert


class LogWriter:
    """sys.stdout/stderr replacement: the text goes to the window's queue, from any thread."""

    def __init__(self, q: queue.Queue):
        self.q = q

    def write(self, text: str) -> int:
        if text:
            self.q.put(("log", text))
        return len(text)

    def flush(self) -> None:
        pass


class Dialog(simpledialog.Dialog):
    """simpledialog.Dialog with ttk, translated buttons."""

    def buttonbox(self):
        box = ttk.Frame(self)
        ttk.Button(box, text=T("ok"), command=self.ok, default="active").pack(side="left", padx=5, pady=8)
        ttk.Button(box, text=T("cancel"), command=self.cancel).pack(side="left", padx=5, pady=8)
        self.bind("<Return>", self.ok)
        self.bind("<Escape>", self.cancel)
        box.pack()


class PodcastDialog(Dialog):
    """Address (fixed when editing), episodes to keep, latest or in order from a chosen episode."""

    def __init__(self, parent, title, url=None, keep=3, in_order=False):
        self.init = (url, keep, in_order)
        super().__init__(parent, title)

    def body(self, master):
        url, keep, in_order = self.init
        ttk.Label(master, text=T("podcast_add_prompt"), wraplength=460).grid(row=0, column=0, columnspan=2,
                                                                            sticky="w", pady=(0, 6))
        self.url = ttk.Entry(master, width=62)
        self.url.grid(row=1, column=0, columnspan=2, sticky="ew")
        if url:
            self.url.insert(0, url)
            self.url.state(["readonly"])
        else:
            try:  # a copied link is pasted for you
                clip = self.clipboard_get().strip()
                if clip.lower().startswith(("http://", "https://")) and "\n" not in clip:
                    self.url.insert(0, clip)
            except tk.TclError:
                pass
        ttk.Label(master, text=T("podcast_keep_label")).grid(row=2, column=0, sticky="w", pady=(8, 0))
        self.keep = ttk.Spinbox(master, from_=1, to=50, width=5)
        self.keep.set(keep)
        self.keep.grid(row=2, column=1, sticky="w", pady=(8, 0))
        self.mode = tk.BooleanVar(value=in_order)
        ttk.Radiobutton(master, text=T("podcast_mode_latest"), variable=self.mode, value=False).grid(
            row=3, column=0, columnspan=2, sticky="w", pady=(8, 0))
        ttk.Radiobutton(master, text=T("podcast_mode_order"), variable=self.mode, value=True).grid(
            row=4, column=0, columnspan=2, sticky="w")
        return self.keep if url else self.url

    def apply(self):
        try:
            keep = max(1, int(self.keep.get()))
        except ValueError:
            keep = im.DEFAULT_KEEP
        self.result = (self.url.get().strip(), keep, self.mode.get())


class EpisodePicker(Dialog):
    """The first episode to listen to, in a podcast listened in order. Result: "<date>:<key>"."""

    def __init__(self, parent, title, episodes, start=None):
        self.episodes = list(reversed(episodes))  # oldest first
        self.start = start
        super().__init__(parent, title)

    def body(self, master):
        ttk.Label(master, text=T("podcast_pick_prompt"), wraplength=520).pack(anchor="w", pady=(0, 6))
        frame = ttk.Frame(master)
        frame.pack(fill="both", expand=True)
        self.list = tk.Listbox(frame, width=80, height=14, activestyle="dotbox", exportselection=False)
        bar = ttk.Scrollbar(frame, orient="vertical", command=self.list.yview)
        self.list.configure(yscrollcommand=bar.set)
        self.list.pack(side="left", fill="both", expand=True)
        bar.pack(side="right", fill="y")
        for ep in self.episodes:
            self.list.insert("end", f"{ep['date']}   {ep['title']}")
        key = (self.start or "").partition(":")[2]
        index = next((n for n, ep in enumerate(self.episodes) if ep["key"] == key), 0)
        self.list.selection_set(index)
        self.list.see(index)
        self.list.bind("<Double-1>", lambda e: self.ok())
        return self.list

    def validate(self):
        return bool(self.list.curselection())

    def apply(self):
        ep = self.episodes[self.list.curselection()[0]]
        self.result = f"{ep['date']}:{ep['key']}"


class App:
    def __init__(self, root: tk.Tk, addon: Path):
        self.root = root
        self.q: queue.Queue = queue.Queue()
        self.busy = False
        self.ready = False
        self.stats = im.new_stats()
        self.args = im.build_parser().parse_args([])
        self.library: str | None = None
        self.covers_from: str | None = None
        self.podcast_names: dict[str, str] = {}
        self.keep_originals = tk.BooleanVar(value=False)
        self.rename = tk.BooleanVar(value=True)
        self.podcasts = tk.BooleanVar(value=True)
        self.controls: list[ttk.Widget] = []

        root.title(T("title"))
        root.minsize(720, 760)
        root.protocol("WM_DELETE_WINDOW", self.on_close)
        root.report_callback_exception = self.on_tk_error
        self.build()
        sys.stdout = sys.stderr = LogWriter(self.q)
        root.after(50, self.poll)
        self.set_busy(True, T("status_preparing"))
        self.work(self.prepare_step, addon)

    # --- layout ------------------------------------------------------------------

    def build(self) -> None:
        style = ttk.Style(self.root)
        style.configure("Big.TButton", font=("Segoe UI", 12, "bold"), padding=(24, 8))
        style.configure("Head.TLabel", font=("Segoe UI", 14, "bold"))
        style.configure("Hint.TLabel", foreground="#666666")
        style.configure("Note.TLabel", foreground="#8a5a00")

        main = ttk.Frame(self.root, padding=14)
        main.pack(fill="both", expand=True)
        main.columnconfigure(0, weight=1)
        main.rowconfigure(7, weight=1)

        ttk.Label(main, text=T("heading"), style="Head.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Label(main, text=T("steps"), wraplength=WRAP, style="Hint.TLabel").grid(
            row=1, column=0, sticky="w", pady=(2, 8))

        music = ttk.LabelFrame(main, text=f" {T('music_frame')} ", padding=8)
        music.grid(row=2, column=0, sticky="ew", pady=3)
        self.summary = ttk.Label(music, text="...", wraplength=WRAP)
        self.summary.grid(row=0, column=0, sticky="w")
        ttk.Label(music, text=T("music_hint"), style="Hint.TLabel", wraplength=WRAP).grid(
            row=1, column=0, sticky="w", pady=(0, 6))
        bar = ttk.Frame(music)
        bar.grid(row=2, column=0, sticky="w")
        self.button(bar, T("add_files"), self.add_files).pack(side="left", padx=(0, 6))
        self.button(bar, T("add_folder"), self.add_folder).pack(side="left", padx=(0, 6))
        self.button(bar, T("open_music"), self.open_music).pack(side="left")

        lib = ttk.LabelFrame(main, text=f" {T('library_frame')} ", padding=8)
        lib.grid(row=3, column=0, sticky="ew", pady=3)
        lib.columnconfigure(0, weight=1)
        ttk.Label(lib, text=T("library_hint"), style="Hint.TLabel", wraplength=WRAP).grid(
            row=0, column=0, columnspan=3, sticky="w")
        self.library_label = ttk.Label(lib, text=T("not_set"))
        self.library_label.grid(row=1, column=0, sticky="w", pady=(6, 0))
        self.button(lib, T("choose"), self.choose_library).grid(row=1, column=1, padx=6, pady=(6, 0))
        self.button(lib, T("remove"), self.clear_library).grid(row=1, column=2, pady=(6, 0))

        pod = ttk.LabelFrame(main, text=f" {T('podcasts_frame')} ", padding=8)
        pod.grid(row=4, column=0, sticky="ew", pady=3)
        pod.columnconfigure(0, weight=1)
        ttk.Label(pod, text=T("podcasts_hint"), style="Hint.TLabel", wraplength=WRAP).grid(
            row=0, column=0, columnspan=2, sticky="w")
        self.tree = ttk.Treeview(pod, columns=("name", "keep", "from"), show="headings", height=3,
                                 selectmode="browse")
        self.tree.heading("name", text=T("col_podcast"))
        self.tree.heading("keep", text=T("col_keep"))
        self.tree.heading("from", text=T("col_from"))
        self.tree.column("name", width=340)
        self.tree.column("keep", width=90, anchor="center", stretch=False)
        self.tree.column("from", width=110, anchor="center", stretch=False)
        self.tree.grid(row=1, column=0, sticky="ew", pady=(6, 0))
        self.tree.bind("<Double-1>", lambda e: self.podcast_edit())
        side = ttk.Frame(pod)
        side.grid(row=1, column=1, sticky="n", padx=(6, 0), pady=(6, 0))
        self.button(side, T("podcast_add"), self.podcast_add).pack(fill="x")
        self.button(side, T("podcast_edit"), self.podcast_edit).pack(fill="x", pady=3)
        self.button(side, T("remove"), self.podcast_remove).pack(fill="x")
        self.check(pod, self.podcasts, T("podcasts_download")).grid(row=2, column=0, sticky="w", pady=(4, 0))

        opts = ttk.LabelFrame(main, text=f" {T('options_frame')} ", padding=8)
        opts.grid(row=5, column=0, sticky="ew", pady=3)
        opts.columnconfigure(1, weight=1)
        self.check(opts, self.rename, T("opt_rename")).grid(row=0, column=0, columnspan=3, sticky="w")
        self.check(opts, self.keep_originals, T("opt_keep")).grid(row=1, column=0, columnspan=3, sticky="w")
        ttk.Label(opts, text=T("covers_from")).grid(row=2, column=0, sticky="w", pady=(6, 0))
        self.covers_label = ttk.Label(opts, style="Hint.TLabel")
        self.covers_label.grid(row=2, column=1, sticky="w", padx=6, pady=(6, 0))
        cov = ttk.Frame(opts)
        cov.grid(row=2, column=2, sticky="e", pady=(6, 0))
        self.button(cov, T("choose"), self.choose_covers).pack(side="left", padx=(0, 6))
        self.button(cov, T("remove"), self.clear_covers).pack(side="left")

        run = ttk.Frame(main, padding=(0, 8, 0, 4))
        run.grid(row=6, column=0, sticky="ew")
        run.columnconfigure(1, weight=1)
        ttk.Label(run, text="⏳ " + T("import_note"), style="Note.TLabel", wraplength=WRAP).grid(
            row=0, column=0, columnspan=2, sticky="w", pady=(0, 8))
        self.import_button = self.button(run, T("import"), self.start_import, style="Big.TButton")
        self.import_button.grid(row=1, column=0, rowspan=2, padx=(0, 12))
        self.progress = ttk.Progressbar(run, mode="determinate")
        self.progress.grid(row=1, column=1, sticky="ew")
        self.status = ttk.Label(run, text="", wraplength=WRAP - 160)
        self.status.grid(row=2, column=1, sticky="w")

        self.log = ScrolledText(main, height=7, wrap="word", font=("Consolas", 9), state="disabled")
        self.log.grid(row=7, column=0, sticky="nsew", pady=(4, 0))

    def button(self, parent, text, command, style="TButton") -> ttk.Button:
        b = ttk.Button(parent, text=text, command=command, style=style)
        self.controls.append(b)
        return b

    def check(self, parent, var, text) -> ttk.Checkbutton:
        c = ttk.Checkbutton(parent, variable=var, text=text)
        self.controls.append(c)
        return c

    # --- threads -----------------------------------------------------------------

    def poll(self) -> None:
        try:
            while True:
                kind, item = self.q.get_nowait()
                if kind == "log":
                    self.append_log(item)
                else:
                    item()
        except queue.Empty:
            pass
        self.root.after(50, self.poll)

    def append_log(self, text: str) -> None:
        self.log.configure(state="normal")
        self.log.insert("end", text.replace("\r", ""))
        self.log.see("end")
        self.log.configure(state="disabled")

    def ui(self, fn) -> None:
        """Runs fn in the window's thread (widgets must only be touched there)."""
        self.q.put(("call", fn))

    def ask_ui(self, fn):
        """From the worker: runs fn (a dialog) in the window's thread and waits for its answer."""
        done = threading.Event()
        box = []
        self.ui(lambda: (box.append(fn()), done.set()))
        done.wait()
        return box[0]

    def work(self, fn, *args) -> None:
        threading.Thread(target=self._run, args=(fn, args), daemon=True).start()

    def _run(self, fn, args) -> None:
        try:
            fn(*args)
        except SystemExit as e:  # the import's own errors (folder not found...)
            if isinstance(e.code, str):
                print(e.code)
            self.ui(lambda: self.failed(T("error_stopped")))
        except Exception:  # noqa: BLE001
            traceback.print_exc()
            self.ui(lambda: self.failed(T("error_generic", url=ISSUES_URL)))

    def failed(self, message: str) -> None:
        self.set_busy(False, T("status_stopped"))
        messagebox.showerror(T("title"), message, parent=self.root)

    def on_tk_error(self, *exc) -> None:
        traceback.print_exception(*exc)
        self.failed(T("error_generic", url=ISSUES_URL))

    def set_busy(self, busy: bool, status: str | None = None) -> None:
        self.busy = busy
        for w in self.controls:
            w.state(["disabled"] if busy else ["!disabled"])
        if status is not None:
            self.status.configure(text=status)
        if busy:
            self.progress.configure(mode="indeterminate")
            self.progress.start(12)
        else:
            self.progress.stop()
            self.progress.configure(mode="determinate", value=0)
            self.refresh()

    def set_progress(self, done: float, total: float, status: str) -> None:
        if self.progress["mode"] != "determinate":
            self.progress.stop()
            self.progress.configure(mode="determinate")
        self.progress.configure(maximum=max(total, 1), value=done)
        self.status.configure(text=status)

    def set_activity(self, status: str) -> None:
        """Something is running but its size is unknown: a moving bar."""
        if self.progress["mode"] != "indeterminate":
            self.progress.configure(mode="indeterminate")
            self.progress.start(12)
        self.status.configure(text=status)

    def on_close(self) -> None:
        if self.busy and not messagebox.askyesno(T("title"), T("close_running"), parent=self.root):
            return
        self.root.destroy()

    # --- start-up: data folder, ffmpeg -------------------------------------------------

    def prepare_step(self, addon: Path) -> None:
        im.prepare_addon(addon, self.stats)
        self.ui(self.after_prepare)

    def after_prepare(self) -> None:
        settings = im.load_settings()
        lib = settings.get("library")
        self.library = lib if lib and Path(lib).is_dir() else None
        cov = settings.get("covers_from")
        self.covers_from = cov if cov and Path(cov).is_dir() else None
        self.keep_originals.set(bool(settings.get("keep_originals", False)))
        self.rename.set(not settings.get("keep_names", False))
        self.podcasts.set(bool(settings.get("podcasts", True)))
        self.podcast_names = dict(settings.get("podcast_names") or {})
        print(f"Addon: {im.ADDON_DIR}\nYour music folder: {im.MUSIC_DIR}\n")
        self.check_ffmpeg()

    def has_ffmpeg(self) -> bool:
        im.FFMPEG, im.FFPROBE = im.find_tool("ffmpeg") or "", im.find_tool("ffprobe") or ""
        return bool(im.FFMPEG and im.FFPROBE)

    def check_ffmpeg(self) -> None:
        if self.has_ffmpeg():
            self.finish_startup()
            return
        if os.name != "nt":
            messagebox.showwarning(T("title"), T("ffmpeg_other_os"), parent=self.root)
            self.finish_startup()
            return
        if messagebox.askyesno(T("title"), T("ffmpeg_ask", folder=im.LOCAL_FFMPEG_DIR), parent=self.root):
            self.set_busy(True, T("download_ffmpeg"))
            self.work(self.download_step)
        else:
            self.finish_startup()

    def download_step(self) -> None:
        def progress(done: int, total: int) -> None:
            text = T("ffmpeg_downloading", done=f"{done / 1048576:.0f}", total=f"{total / 1048576:.0f}")
            self.ui(lambda: self.set_progress(done, total, text))
        ok = im.download_ffmpeg(progress)
        self.ui(lambda: self.download_done(ok))

    def download_done(self, ok: bool) -> None:
        if ok and self.has_ffmpeg():
            print("ffmpeg is ready.\n")
        else:
            messagebox.showerror(T("title"), T("ffmpeg_failed"), parent=self.root)
        self.finish_startup()

    def finish_startup(self) -> None:
        self.ready = True
        self.set_busy(False, T("status_ready") if im.FFMPEG else T("status_no_ffmpeg"))
        unnamed = [u for u, _, _ in self.podcast_list() if u not in self.podcast_names]
        if unnamed:  # podcasts added by hand to podcasts.txt: their names, quietly, in the background
            threading.Thread(target=self.name_podcasts, args=(unnamed,), daemon=True).start()

    def name_podcasts(self, urls: list[str]) -> None:
        names = {}
        for url in urls:
            try:
                names[url] = im.check_podcast(url)[0]
            except Exception:  # noqa: BLE001 - offline or a broken feed: the address stays shown
                pass
        if names:
            def apply() -> None:
                self.podcast_names.update(names)
                self.save_settings()
                if not self.busy:
                    self.refresh()
            self.ui(apply)

    # --- state ---------------------------------------------------------------------

    def refresh(self) -> None:
        if not self.ready:
            return
        tracks, convert = music_counts()
        self.summary.configure(text=T("music_count_convert", tracks=tracks, convert=convert) if convert
                               else T("music_count", tracks=tracks))
        self.library_label.configure(text=self.library or T("not_set"))
        self.covers_label.configure(text=self.covers_from or (T("covers_library") if self.library else "-"))
        self.tree.delete(*self.tree.get_children())
        for url, keep, start in self.podcast_list():
            since = start.partition(":")[0] if start else T("from_latest")
            self.tree.insert("", "end", iid=url, values=(self.podcast_names.get(url, url), keep, since))
        self.import_button.configure(text=T("import") if im.FFMPEG else T("download_ffmpeg"))

    def save_settings(self) -> None:
        settings = im.load_settings()
        settings.update(library=self.library, covers_from=self.covers_from,
                        keep_originals=self.keep_originals.get(), keep_names=not self.rename.get(),
                        podcasts=self.podcasts.get(), podcast_names=self.podcast_names)
        im.save_settings(settings)

    # --- music -----------------------------------------------------------------------

    def open_music(self) -> None:
        open_path(im.MUSIC_DIR)

    def inside_data(self, folder: Path) -> bool:
        try:
            folder.resolve().relative_to(im.DATA_DIR.resolve())
            return True
        except ValueError:
            return False

    def add_files(self) -> None:
        types = [(T("filetype_music"), " ".join("*" + e for e in sorted(im.AUDIO_EXT))), (T("filetype_all"), "*.*")]
        files = filedialog.askopenfilenames(title=T("add_files_title"), filetypes=types, parent=self.root)
        if files:
            self.set_busy(True, T("status_copying"))
            self.work(self.copy_step, [Path(f) for f in files], None)

    def add_folder(self) -> None:
        folder = filedialog.askdirectory(title=T("add_folder_title"), parent=self.root)
        if not folder:
            return
        folder = Path(folder)
        if self.inside_data(folder) or folder.parent == folder:
            messagebox.showwarning(T("title"), T("bad_folder"), parent=self.root)
            return
        self.set_busy(True, T("status_copying"))
        self.work(self.copy_step, None, folder)

    def copy_step(self, files: list[Path] | None, folder: Path | None) -> None:
        stats = im.new_stats()
        have, _ = im.music_index()
        skipped = 0
        if folder:
            found = []  # audio files of the folder, relative to it
            for root, dirs, names in os.walk(folder):
                dirs[:] = sorted(d for d in dirs if not im.is_skipped_dir(d))
                rel = Path(root).relative_to(folder)
                found += [Path(os.path.normpath(rel / f)) for f in sorted(names)
                          if os.path.splitext(f)[1].lower() in im.AUDIO_EXT]

            def present(prefix: list[str], rel_file: Path) -> bool:
                return im.track_key(prefix + list(rel_file.parent.parts) + [rel_file.stem]) in have

            # A folder laid out like the music folder (e.g. the music library it was filled from) is
            # merged into it; any other folder becomes a subfolder named after it.
            as_root = sum(present([], r) for r in found)
            as_sub = sum(present([folder.name], r) for r in found)
            if as_root > as_sub:
                base, prefix, missing = folder, [], [r for r in found if not present([], r)]
                print(f"Adding {folder} (same layout as your music folder: merged into it) ...")
            else:
                base, prefix = folder.parent, [folder.name]
                missing = [Path(folder.name) / r for r in found if not present(prefix, r)]
                print(f"Adding {folder} as the subfolder {folder.name} ...")
            skipped = len(found) - len(missing)
            im.copy_missing(base, missing, stats)
        else:
            for src in files or []:
                if im.track_key([src.stem]) in have or (im.MUSIC_DIR / src.name).exists():
                    skipped += 1
                    continue
                try:
                    print(f"  copying {src.name}")
                    shutil.copy2(src, im.MUSIC_DIR / src.name)
                    stats["copied"] += 1
                except OSError as exc:
                    stats["warnings"].append(f"{src.name}: not copied ({exc})")
        for w in stats["warnings"]:
            print(f"  WARNING: {w}")
        print(f"{stats['copied']} files added" + (f", {skipped} already there" if skipped else "") + ".\n")
        self.ui(lambda: self.copy_done(stats["copied"], skipped))

    def copy_done(self, copied: int, skipped: int) -> None:
        self.set_busy(False, T("status_added", count=copied) if copied else T("status_nothing_new"))
        if copied and messagebox.askyesno(T("title"), T("files_added_ask", count=copied), parent=self.root):
            self.start_import()
        elif not copied and skipped:
            messagebox.showinfo(T("title"), T("already_there"), parent=self.root)

    def choose_library(self) -> None:
        folder = filedialog.askdirectory(title=T("library_title"), parent=self.root)
        if not folder:
            return
        if self.inside_data(Path(folder)):
            messagebox.showwarning(T("title"), T("library_is_addon"), parent=self.root)
            return
        self.library = folder
        self.save_settings()
        self.refresh()

    def clear_library(self) -> None:
        self.library = None
        self.save_settings()
        self.refresh()

    def choose_covers(self) -> None:
        folder = filedialog.askdirectory(title=T("covers_title"), parent=self.root)
        if folder:
            self.covers_from = folder
            self.save_settings()
            self.refresh()

    def clear_covers(self) -> None:
        self.covers_from = None
        self.save_settings()
        self.refresh()

    # --- podcasts ----------------------------------------------------------------------
    # The list stays in podcasts.txt (also used from the command line); the shows' names, known
    # only after reading their feeds, are kept in import_settings.json.

    def podcast_file(self) -> Path:
        return im.find_podcasts_file() or im.DATA_DIR / im.PODCASTS_FILE_NAMES[0]

    def podcast_list(self) -> list[tuple[str, int, str | None]]:
        path = im.find_podcasts_file()
        return im.read_podcast_list(path) if path else []

    def selected_podcast(self) -> tuple[str, int, str | None] | None:
        sel = self.tree.selection()
        return next((e for e in self.podcast_list() if sel and e[0] == sel[0]), None)

    def save_podcast(self, url: str, keep: int, start: str | None) -> None:
        """Adds the podcast, or replaces its line if it is already in the list."""
        entries = self.podcast_list()
        if any(u == url for u, _, _ in entries):
            entries = [(u, keep, start) if u == url else (u, k, s) for u, k, s in entries]
        else:
            entries.append((url, keep, start))
        im.write_podcast_list(self.podcast_file(), entries)

    def podcast_add(self) -> None:
        self.podcast_dialog(None)

    def podcast_edit(self) -> None:
        entry = self.selected_podcast()
        if entry and not self.busy:
            self.podcast_dialog(entry)

    def podcast_dialog(self, entry: tuple[str, int, str | None] | None) -> None:
        url0, keep0, start0 = entry or (None, im.DEFAULT_KEEP, None)
        dialog = PodcastDialog(self.root, T("podcast_edit_title" if entry else "podcast_add_title"),
                               url0, keep0, bool(start0))
        if not dialog.result or not dialog.result[0]:
            return
        url, keep, in_order = dialog.result
        if not entry:
            if not url.lower().startswith(("http://", "https://")):
                url = "https://" + url
            if any(u == url for u, _, _ in self.podcast_list()):
                messagebox.showinfo(T("title"), T("podcast_dup"), parent=self.root)
                return
        elif not in_order:  # only the number or "latest": nothing to read from the feed
            self.save_podcast(url, keep, None)
            self.refresh()
            return
        self.set_busy(True, T("podcast_checking"))
        self.work(self.podcast_check_step, url, keep, in_order, start0)

    def podcast_check_step(self, url: str, keep: int, in_order: bool, start0: str | None) -> None:
        print(f"Checking {url} ...")
        try:
            name, episodes = im.read_podcast(url)
        except Exception as exc:  # noqa: BLE001
            error = str(exc)  # exc is cleared when the except block ends, before the lambda runs
            print(f"  {error}\n")
            self.ui(lambda: self.podcast_checked(url, keep, in_order, start0, None, [], error))
            return
        print(f"  {name}: {len(episodes)} episodes in the feed\n")
        self.ui(lambda: self.podcast_checked(url, keep, in_order, start0, name, episodes, ""))

    def podcast_checked(self, url: str, keep: int, in_order: bool, start0: str | None, name: str | None,
                        episodes: list[dict], error: str) -> None:
        self.set_busy(False, T("status_ready"))
        if name is None:
            messagebox.showerror(T("title"), T("podcast_bad", error=error), parent=self.root)
            return
        start = None
        if in_order:
            start = EpisodePicker(self.root, T("podcast_pick_title"), episodes, start0).result
            if not start:
                return
        self.save_podcast(url, keep, start)
        self.podcast_names[url] = name
        self.podcasts.set(True)
        self.save_settings()
        self.set_busy(False, T("podcast_added", name=name))

    def podcast_remove(self) -> None:
        entry = self.selected_podcast()
        if not entry:
            return
        url = entry[0]
        name = self.podcast_names.get(url, url)
        if not messagebox.askyesno(T("title"), T("podcast_remove_ask", name=name), parent=self.root):
            return
        im.write_podcast_list(self.podcast_file(), [e for e in self.podcast_list() if e[0] != url])
        show_dir = im.MUSIC_DIR / im.PODCAST_DIR_NAME / im.show_dir_name(name) if url in self.podcast_names else None
        if show_dir and show_dir.is_dir() and messagebox.askyesno(
                T("title"), T("podcast_delete_ask", name=name), parent=self.root):
            shutil.rmtree(show_dir, ignore_errors=True)
            print(f"Deleted {show_dir}\n")
        self.podcast_names.pop(url, None)
        self.save_settings()
        self.refresh()

    # --- import ------------------------------------------------------------------------

    def start_import(self) -> None:
        if not im.FFMPEG:
            self.check_ffmpeg()
            return
        self.save_settings()
        a = self.args
        a.library = self.library
        a.covers_from = self.covers_from
        a.keep_originals = self.keep_originals.get()
        a.keep_names = not self.rename.get()
        a.no_podcasts = not self.podcasts.get()
        a.podcasts = False
        self.set_busy(True, T("status_importing"))
        self.work(self.import_step)

    def import_step(self) -> None:
        self.stats = im.new_stats()

        def confirm(count: int) -> bool:
            return self.ask_ui(lambda: messagebox.askyesno(T("title"), T("copy_confirm", count=count),
                                                           parent=self.root))

        def progress(done: int, total: int, label: str) -> None:
            text = T("status_importing_folder", folder=label) if label else T("status_writing")
            self.ui(lambda: self.set_progress(done, total, text))

        # download and conversion run at the same time (two threads): both lines are shown, the bar
        # follows the download, or the conversion when nothing is downloading
        state: dict[tuple[str, str], tuple[str, float, float]] = {}  # (stage, episode) -> text, done, total
        lock = threading.Lock()
        last = [0.0]

        def podcast_progress(stage: str, show: str, title: str, done: float, total: float) -> None:
            with lock:
                if stage.endswith("_end"):
                    state.pop((stage[:-4], title), None)
                else:
                    if stage == "download":
                        mb = f"{done / 1048576:.0f}"
                        text = (T("status_podcast_download", show=show, episode=title, done=mb,
                                  total=f"{total / 1048576:.0f}") if total
                                else T("status_podcast_download_nosize", show=show, episode=title, done=mb))
                    else:
                        text = T("status_podcast_convert", show=show, episode=title,
                                 percent=int(done * 100 / total) if total else 0)
                    state[(stage, title)] = (text, done, total)
                    now = time.monotonic()
                    if now - last[0] < 0.2 and not (total and done >= total):
                        return  # at most 5 updates a second
                    last[0] = now
                shown = [v for k, v in sorted(state.items(), key=lambda i: i[0][0] != "download")]
            if not shown:
                return
            text = "\n".join(t for t, _, _ in shown)
            _, done, total = shown[0]
            if total:
                self.ui(lambda: self.set_progress(done, total, text))
            else:
                self.ui(lambda: self.set_activity(text))

        result = im.run_import(self.args, self.stats, confirm, progress, podcast_progress)
        self.ui(lambda: self.import_done(result))

    def import_done(self, result: dict) -> None:
        self.set_busy(False, T("status_done", tracks=result["tracks"]))
        lines = [T("done", tracks=result["tracks"])]
        if result["converted"]:
            lines.append(T("done_converted", count=result["converted"]))
        if result["copied"]:
            lines.append(T("done_copied", count=result["copied"]))
        if result["warnings"]:
            lines.append(T("done_warnings", count=len(result["warnings"])))
        lines.append("\n" + T("done_restart"))
        messagebox.showinfo(T("title"), "\n".join(lines), parent=self.root)


def find_addon(root: tk.Tk) -> Path | None:
    """The addon folder: found automatically, else chosen by the user (None if they give up)."""
    addon = im.find_addon_dir(None)
    while not addon:
        hint = f"World of Warcraft\\_forever_\\Interface\\AddOns\\{im.ADDON_NAME}"
        if not messagebox.askokcancel(T("title"), T("addon_not_found", addon=im.ADDON_NAME, path=hint)):
            return None
        folder = filedialog.askdirectory(title=T("addon_folder_title", addon=im.ADDON_NAME), parent=root)
        addon = im._check_addon(Path(folder).resolve()) if folder else None
    return addon


def main() -> None:
    global T
    if sys.platform == "win32":
        try:  # sharp text on high-DPI screens
            import ctypes
            ctypes.windll.shcore.SetProcessDpiAwareness(1)
        except (AttributeError, OSError):
            pass
    root = tk.Tk()
    root.withdraw()
    addon = find_addon(root)
    if not addon:
        root.destroy()
        return
    T = Texts(detect_language(addon))
    root.deiconify()
    App(root, addon)
    root.mainloop()


if __name__ == "__main__":
    try:
        main()
    except Exception:  # noqa: BLE001 - started with pythonw there is no console to show it
        text = traceback.format_exc()
        try:
            log = im.LOCAL_FFMPEG_DIR.parent / "import_error.txt"
            log.parent.mkdir(parents=True, exist_ok=True)
            log.write_text(text, encoding="utf-8")
            messagebox.showerror(T("title"), T("crash", text=text[-800:], url=ISSUES_URL))
        except Exception:  # noqa: BLE001
            pass
        raise
