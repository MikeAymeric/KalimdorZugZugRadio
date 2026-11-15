"""Kalimdor ZugZug Radio - imports your music and podcasts.

Double-click this file to run it (Python from python.org opens .py files with a
double-click). It opens a window (tools/import_gui.py) where you add your music and
press Import; ffmpeg is downloaded the first time if it is missing.
From a terminal you can pass options instead: python "Import music.py" --keep-originals
(--menu shows the old text menu, --help lists every option).
"""
import os
import runpy
import subprocess
import sys
import traceback

ISSUES_URL = "https://github.com/MikeAymeric/KalimdorZugZugRadio/issues"


def wait_and_close():
    try:
        input("\nPress Enter to close this window...")
    except (EOFError, KeyboardInterrupt):
        pass


if sys.version_info < (3, 8):
    print("This script needs Python 3.8 or newer, and this PC has Python %d.%d." % sys.version_info[:2])
    print("Install the latest Python from https://www.python.org/downloads/ and try again.")
    wait_and_close()
    sys.exit(1)

here = os.path.dirname(os.path.abspath(__file__))
os.chdir(here)


def start_window():
    """Opens the window; False if this Python has no tkinter (then the text menu is used)."""
    try:
        import tkinter  # noqa: F401
    except ImportError:
        return False
    gui = os.path.join(here, "tools", "import_gui.py")
    # On Windows, reopen it with pythonw so no black console window stays behind it.
    pythonw = os.path.join(os.path.dirname(sys.executable), "pythonw.exe")
    if os.name == "nt" and os.path.isfile(pythonw):
        try:
            subprocess.Popen([pythonw, gui], cwd=here, close_fds=True,
                             creationflags=getattr(subprocess, "DETACHED_PROCESS", 0))
            return True
        except OSError:
            pass
    runpy.run_path(gui, run_name="__main__")
    return True


try:
    if len(sys.argv) == 1 and start_window():
        sys.exit(0)  # the window is open (in its own process when started with pythonw)
    script = os.path.join(here, "tools", "import_music.py")
    sys.argv = [script] + sys.argv[1:]
    runpy.run_path(script, run_name="__main__")
except SystemExit as e:
    if e.code not in (None, 0):
        print(e.code if isinstance(e.code, str) else f"Exit code {e.code}")
    elif os.path.basename(sys.argv[0]) == os.path.basename(__file__) and len(sys.argv) == 1:
        sys.exit(0)  # only the window: nothing to wait for
except KeyboardInterrupt:
    print("\nInterrupted.")
except Exception:
    traceback.print_exc()
    print("\nSomething went wrong. Nothing you did caused it: please report it at")
    print(f"  {ISSUES_URL}")
    print("and include the text above (select it with the mouse and copy it with Ctrl+C).")

wait_and_close()
