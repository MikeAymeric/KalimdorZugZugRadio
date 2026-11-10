"""Kalimdor ZugZug Radio - imports your music and podcasts.

Double-click this file to run it (Python from python.org opens .py files with a
double-click). It runs tools/import_music.py and keeps the window open at the end.
From a terminal you can add options: python "Import music.py" --keep-originals
"""
import os
import runpy
import sys
import traceback

here = os.path.dirname(os.path.abspath(__file__))
script = os.path.join(here, "tools", "import_music.py")
os.chdir(here)
sys.argv = [script] + sys.argv[1:]

try:
    runpy.run_path(script, run_name="__main__")
except SystemExit as e:
    if e.code not in (None, 0):
        print(e.code if isinstance(e.code, str) else f"Exit code {e.code}")
except KeyboardInterrupt:
    print("\nInterrupted.")
except Exception:
    traceback.print_exc()

try:
    input("\nPress Enter to close this window...")
except EOFError:
    pass
