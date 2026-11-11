# Store listing (CurseForge and Wago)

Texts to paste into the project pages. Keep them in sync with the README.

## Project name

Kalimdor ZugZug Radio

## Summary (short description)

Your own music, the WoW soundtrack and your podcasts, played by what you are doing: boss, combat, flight, campfire, zone, night and more.

## Logo

`docs/logo-400.png` (400x400, CurseForge avatar) and `docs/logo-1024.png` (larger, for Wago). Source: `docs/logo.svg`, an original drawing (no Blizzard artwork).

## Categories

- CurseForge: Audio & Video (secondary: Miscellaneous)
- Wago: Audio & Video

## Game version

WoW Forever 1.60.1 (Interface 16001)

## License

MIT (the bundled KZZR Sans (M+ 1p + Noto symbols) and Nanum Gothic fonts are under the SIL Open Font License 1.1)

## Source / issues

https://github.com/MikeAymeric/KalimdorZugZugRadio

## Description

**Kalimdor ZugZug Radio** is a music radio for World of Warcraft Forever.

It plays your own playlists based on what your character is doing: a boss fight, combat, a flight path, sitting at a campfire, fishing, a dungeon, a city, a specific zone, the night. Or just pick a playlist and listen, with no conditions at all. Besides your own music it plays the game's own soundtrack and your podcasts.

### Features

- **16 conditions**, each with its own playlist and volume: level up, boss (and a playlist for each specific boss), elite, battleground, combat, dead, flight, fishing, swimming, campfire, dungeon, ground mount, zone, city, night, no condition.
- **Free play**: choose a playlist yourself and it wins over every condition until you go back to automatic.
- **Game soundtrack**: about 600 WoW Forever and classic tracks, ready to use, with an in-game icon as the cover.
- **Your music**: mp3, ogg, mp4, m4a, flac, wav and more, with covers, organized in playlists you create in game.
- **Podcasts**: the latest episodes of your podcasts (RSS or Apple Podcasts links), resumed where you left off.
- **Player**: cover, title, remaining time, controls, volume slider, favourites, compact mode and a classic WoW look.
- **Library**: playlists, search, favourites, "never play this track", recently played, most played, export and import playlists as text.
- **Comfort**: key bindings, minimap button, "Now playing" banner, fade between conditions, lower music during cinematics, pause when AFK, per-character profiles.
- **12 languages**: English, Français, Deutsch, Español (EU), Español (AL), Português (BR), Italiano, Русский, 简体中文, 繁體中文, 日本語, 한국어.
- **Titles in any script**: Japanese, Chinese and Korean titles, and symbols like ★ ♪ ❤ ✿ ➡, are readable on any client thanks to the bundled fonts.

### Getting started

1. Install the addon and start the game: the player and a drum button on the minimap appear.
2. Open the library (**Library** button), select **WoW music** and press **>** on a track: the game soundtrack works right away.
3. Open the settings (`/kzz config`) and choose a playlist for each condition.

### Your own music and podcasts

Double-click **Import music.py** in the addon folder (it needs [Python](https://www.python.org/downloads/) and ffmpeg: `winget install Gyan.FFmpeg`). A small menu lets you pick the options and opens your music folder (`AddOns\KalimdorZugZugRadio_Library\music`): put your files there, then the script converts them, extracts the covers and builds the library. Then restart the game client.

Your music lives in that separate folder (shown in the AddOns list as *Kalimdor ZugZug Radio - My Music*), so **updating the addon never deletes it**. Updating from 0.7 or older: back up `AddOns\KalimdorZugZugRadio\music` and `covers` first, then run Import music.py once to move them.

Already have a music library somewhere else (Plex, iTunes, a folder of albums)? Choose it in the menu: the script copies and converts only the tracks the addon doesn't have yet, after showing you the list, and never modifies your library.

For podcasts, list them in `podcasts.txt` in your music library folder (one link per line) and run the same script.

The full guide is on [GitHub](https://github.com/MikeAymeric/KalimdorZugZugRadio#readme).

### Commands

`/kzz` player, `/kzz lib` library, `/kzz config` settings, `/kzz auto` automatic music, `/kzz stats` listening stats, `/kzz help` all commands.

### Notes

- WoW can't pause or seek a track: stop and play restart it from the beginning. Podcasts resume from their current 2:30 part.
- The radio uses the game's Music volume channel.
- Music is not included: everyone uses their own files. World of Warcraft is a trademark of Blizzard Entertainment; this addon is not affiliated with Blizzard.

## Screenshots to upload

Files in `docs/screenshots/`:

1. `1-campfire-auto.png`: automatic mode, sitting at a campfire switches to the Campfire playlist.
2. `2-library.png`: the library, with playlists, search and the game soundtrack.
3. `3-settings.png`: the settings panel, with a playlist and a volume for each condition.
4. `4-player.png`: the player, with cover, title, remaining time, volume and controls.
5. `5-compact-tirisfal.png`: the compact player.

## Release package

Build it from the release tag so no personal music, covers or podcast list ends up in it: `git archive --format=zip <tag> KalimdorZugZugRadio`, plus the root `LICENSE` copied in as `KalimdorZugZugRadio/LICENSE.txt`. The zip must contain only the `KalimdorZugZugRadio` folder, with the empty placeholder `Library.lua`.
