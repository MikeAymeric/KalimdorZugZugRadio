# Kalimdor ZugZug Radio

A music radio addon for **World of Warcraft Forever**.

It plays **your own playlists** based on what your character is doing: a boss fight, combat, a flight path, sitting at a campfire, fishing, a dungeon, a city, a specific zone, the night. You can also simply pick a playlist and listen, with no conditions at all. Besides your own music it can play the **game's own soundtrack** and your **podcasts**.

## Features

- **Conditional music**: 16 conditions (boss, elite, combat, flight, campfire, zone, night and more), each with its own playlist and volume.
- **Your music library**: your own files (mp3, ogg, mp4, m4a, flac, wav...) with covers, organized in playlists created in-game.
- **Game soundtrack**: about 600 WoW Forever and classic tracks, ready to use, with an in-game icon as the cover.
- **Podcasts**: the latest episodes of your favourite podcasts, resumed where you left off.
- **Player**: cover, title, remaining time, controls, volume, favourites, a compact mode and a classic WoW look.
- **Comfort**: key bindings, minimap button, "Now playing" banner, pause when AFK, lower music during cinematics, per-character profiles.
- **11 languages**: English, Français, Deutsch, Español (EU), Español (AL), Português (BR), Italiano, Русский, 简体中文, 繁體中文, 日本語.

## Requirements

- The **WoW Forever** game client.
- To add your own music or podcasts (optional, the game soundtrack works without it):
  - [Python 3.10 or newer](https://www.python.org/downloads/). On Windows, tick **"Add python.exe to PATH"** during the installation.
  - [ffmpeg](https://ffmpeg.org/). On Windows, the easiest way is to open a terminal and run: `winget install Gyan.FFmpeg`

## Installation

1. Download this repository: the green **Code** button, then **Download ZIP** (or the latest release, if available).
2. Extract the ZIP.
3. Copy the **`KalimdorZugZugRadio`** folder into your game folder:
   ```
   World of Warcraft\_forever_\Interface\AddOns\
   ```
   The result must be `...\Interface\AddOns\KalimdorZugZugRadio\KalimdorZugZugRadio.toc`.
4. Start the game. In the character selection screen open **AddOns** and make sure **Kalimdor ZugZug Radio** is enabled.

In game, the player window appears and a drum button is added to the minimap. Type `/kzz` to show or hide the player.

You can already listen to the game soundtrack: open the library (the **Library** button on the player), select **WoW music** and press **>** on a track.

## Adding your own music

1. Put your music files in the addon's `music` folder:
   ```
   World of Warcraft\_forever_\Interface\AddOns\KalimdorZugZugRadio\music\
   ```
   You can use subfolders (for example one per album or artist): they only help you organize and search. Formats: anything ffmpeg can read (mp3, ogg, mp4, m4a, flac, wav...).
2. Open a terminal in the folder where you extracted this repository and run:
   ```
   python tools\import_music.py
   ```
   The script finds the addon in your game folder by itself. If it can't, tell it where the addon is:
   ```
   python tools\import_music.py --addon "D:\Path\To\World of Warcraft\_forever_\Interface\AddOns\KalimdorZugZugRadio"
   ```
3. **Restart the game client** (new files are only seen after a restart; if you only removed files, `/reload` is enough).

What the script does:

- **Conversion**: formats WoW can't play are converted to OGG. After a successful conversion the original file is deleted; add `--keep-originals` to keep the originals in `music\_originals\` instead.
- **Covers**: the cover embedded in each file is used, or a `cover.jpg` / `folder.jpg` in the folder. Identical covers are stored only once.
- **File names**: files and folders with non-Latin characters (Japanese, accents...) are renamed, because WoW may not be able to open them. The original names are still shown in-game. Use `--keep-names` to disable this.
- Run the script again every time you add or remove music.

## Podcasts

1. Create a file named **`podcasts.txt`** in the addon folder (`...\AddOns\KalimdorZugZugRadio\podcasts.txt`), or run `python tools\import_music.py --podcasts` once to create a template.
2. Add one podcast per line: the RSS feed address or the Apple Podcasts page link, followed by how many recent episodes to keep (3 if omitted):
   ```
   https://example.com/feed/my-podcast.xml 3
   https://podcasts.apple.com/us/podcast/name/id1234567890 2
   ```
3. Run `python tools\import_music.py` before playing: it downloads the new episodes, deletes the older ones and updates the library. Then restart the game client.

In game the episodes are in the **Podcasts** playlist. WoW can't resume a file halfway, so each episode is split into 2:30 parts: the addon remembers the part you reached (even after logging out) and resumes from there.

- **|<** and **>|** move back and forward by one part (2:30).
- **|<<** and **>>|** go to the previous and next episode.

Spotify-exclusive podcasts have no RSS feed and can't be downloaded.

## Using the addon

### The player

- **Cover, title, artist** and the remaining time of the current track.
- **|<  >  >|**: previous, play/stop, next. WoW can't pause a track: stop and play restart it from the beginning.
- **Shuffle**, and the **volume** slider under the cover (it is the game's Music volume).
- The **star** next to the title adds the track to your favourites.
- The **dropdown** on the left chooses between *Automatic (conditions)* and a playlist to listen to freely.
- The **minimize** button turns the player into a small bar; the button on the bar brings it back.

### Automatic music and free play

- **Automatic (conditions)**: the music follows what your character is doing, using the playlists assigned in the settings.
- **Free play**: as soon as you choose the music yourself (a playlist from the dropdown, **>** on a track, or next/previous), your choice wins over every condition, bosses included, until you select *Automatic (conditions)* again. The player shows *Free play* in orange.

### The library

Open it with the **Library** button, with `/kzz lib`, or by right-clicking the minimap button.

- **Playlists** (left): create, rename, delete, export and import. The virtual playlists are always there: *Whole library*, *WoW music*, *Podcasts*, *Favourites*, *Recently played*, *Most played*.
- **Tracks** (right): select one of your playlists and tick the tracks to include. The search filters by title, artist, album or folder; *Add visible* adds every track in the list. The *Source* menu shows your music, podcasts or the game music.
- **>** or a double-click plays a track. The **star** adds it to your favourites. **Right-click** a track for *Never play this track* (it is skipped unless you choose it yourself).
- **Export / Import**: share a playlist as text. Game music works for everyone; your own files only if the other player has the same files.

### Settings

*Options > AddOns > Kalimdor ZugZug Radio*, or `/kzz config`, or Ctrl-click on the minimap button.

- **General**: radio on/off, shuffle, classic style, fade between conditions, minimap button, lock the player, "Now playing" banner, pause when AFK, lower the music in cinematics and dialogues, compact player, **profile** and **language**.
- **Conditions**: tick the ones you want and choose a playlist for each. The first active condition from the top wins:

  | Priority | Condition | When |
  |---|---|---|
  | 1 | Level up | One track (a jingle) when you level up, then the normal music comes back |
  | 2 | Boss | Dungeon and raid bosses. *Specific bosses* lets you give a boss its own playlist |
  | 3 | Elite / Rare | Fighting an elite or rare enemy |
  | 4 | Battleground / Arena | Inside a battleground or an arena |
  | 5 | Combat | Any fight |
  | 6 | Dead / Ghost | While dead or as a ghost |
  | 7 | Flight | On a flight path |
  | 8 | Fishing | While fishing (and between casts) |
  | 9 | Swimming | In the water |
  | 10 | Campfire | Sitting at a campfire, until you move |
  | 11 | Dungeon | Inside a dungeon or raid |
  | 12 | Mounted (ground) | On a ground mount |
  | 13 | Zone music | In a zone that has its own playlist (assign it while you are in the zone) |
  | 14 | City / Resting | In a city or an inn |
  | 15 | Night | From 21:00 to 6:00, game time |
  | 16 | No condition | Everything else |

  Each condition's menu also has a **Volume** submenu (100% to 20%). If no active condition has a playlist, the game's own zone music plays.
- **Profiles**: the condition settings belong to a profile. *Default* is shared by all your characters; *New profile for this character* creates one just for the current character. Playlists are always shared.

Settings can't be opened during combat (a limitation of the game's Options window).

### Minimap button

Left-click: player. Right-click: library. Shift-click: play/stop. Ctrl-click: settings. Drag it to move it around the minimap.

### Key bindings

*Options > Key Bindings > AddOns > Kalimdor ZugZug Radio*: play/stop, next and previous, skip episode, volume up and down, show the player, open the library, favourite the current track.

### Chat commands

| Command | What it does |
|---|---|
| `/kzz` | Show or hide the player |
| `/kzz lib` | Open the library |
| `/kzz config` | Open the settings |
| `/kzz play`, `stop`, `next`, `prev`, `shuffle` | Player controls |
| `/kzz auto` | Back to automatic music |
| `/kzz playlist <name>` | Play a playlist freely (`all`, `wow`, `podcast` also work) |
| `/kzz on`, `off` | Turn the radio on or off |
| `/kzz status` | Active conditions and their playlists |
| `/kzz stats` | Listening time and most played tracks |
| `/kzz lang <code>` | Addon language (`auto`, `en`, `fr`, `de`, `es`, `pt`, `it`, `ru`, `zh`, `ja`...), then `/reload` |
| `/kzz minimap`, `lock`, `reset` | Minimap button, lock or reset the player position |
| `/kzz perf`, `debug` | Performance and diagnostic information |

## Troubleshooting

- **No sound**: check that *Music* is enabled and not at zero in the game's sound options. The radio uses the Music channel.
- **The conditions don't change the music**: the player is probably in *Free play* (shown in orange). Choose *Automatic (conditions)* in the player's dropdown or type `/kzz auto`.
- **New tracks or episodes don't appear**: run the import script again and restart the game client (not just `/reload`).
- **A song restarts from the beginning after a fight or after dying**: WoW can't resume a song halfway. Podcasts resume from their current part.
- **Japanese or Chinese titles**: they use a font bundled with the addon, so they are readable on any client.
- **Something looks broken**: type `/kzz debug`, then `/reload`, and include the output when you report the problem.

## Development

- `tools/import_music.py`: imports music and podcasts (see above).
- `tools/build_game_music.py`: regenerates the game soundtrack catalog (`GameMusic.lua`) from the WoW community listfile. For developers only: the generated file is already included.
- `tests/`: run `npm install`, then `npm test` (the addon logic in a Lua VM with simulated WoW APIs) and `npm run lint` (Lua syntax check).
- `RadioProbe/`: a small addon that checks which game APIs work on the client.

## License

Code: [MIT](LICENSE) © 2026 MikeAymeric.

The font `KalimdorZugZugRadio/fonts/MPLUS1p-Regular.ttf` (M+ 1p, © The M+ Project Authors) is **not** covered by the MIT license: it is distributed under the SIL Open Font License 1.1 (`KalimdorZugZugRadio/fonts/OFL-MPLUS1p.txt`).

Music is not part of this project: everyone uses their own files. World of Warcraft is a trademark of Blizzard Entertainment; this addon is not affiliated with Blizzard.
