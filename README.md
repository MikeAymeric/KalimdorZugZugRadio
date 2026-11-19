<p align="center"><img src="docs/logo.svg" alt="Kalimdor ZugZug Radio" width="180"></p>

<p align="center">
  <a href="https://github.com/MikeAymeric/KalimdorZugZugRadio/releases/latest"><img src="https://img.shields.io/github/v/release/MikeAymeric/KalimdorZugZugRadio?label=version&color=ff7f00" alt="Latest version"></a>
  <img src="https://img.shields.io/badge/WoW%20Forever-1.60.1%20(16001)-148eff" alt="WoW Forever 1.60.1, Interface 16001">
  <img src="https://img.shields.io/badge/Retail-12.1.5%20(120105)-148eff" alt="Retail 12.1.5, Interface 120105">
  <a href="https://github.com/MikeAymeric/KalimdorZugZugRadio/releases"><img src="https://img.shields.io/github/downloads/MikeAymeric/KalimdorZugZugRadio/total?label=downloads" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/languages-12-2ea44f" alt="12 languages">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/MikeAymeric/KalimdorZugZugRadio" alt="MIT license"></a>
  <a href="https://github.com/MikeAymeric/KalimdorZugZugRadio/commits/main"><img src="https://img.shields.io/github/last-commit/MikeAymeric/KalimdorZugZugRadio" alt="Last commit"></a>
</p>

# Kalimdor ZugZug Radio

A music radio addon for **World of Warcraft Forever** and **Retail** (Midnight).

It plays **your own playlists** based on what your character is doing: a boss fight, combat, a flight path, sitting at a campfire, fishing, a dungeon, a city, a specific zone, the night. You can also simply pick a playlist and listen, with no conditions at all. Besides your own music it can play the **game's own soundtrack** and your **podcasts**.

## Features

- **Conditional music**: 16 conditions (boss, elite, combat, flight, campfire, zone, night and more), each with its own playlist and volume, plus playlists for specific zones, dungeons and bosses. Fight music fades out gently after the fight, and every fight starts a new song.
- **Your music library**: your own files (mp3, ogg, mp4, m4a, flac, wav...) with covers, organized in playlists created in-game, browsable by album, artist and genre.
- **Smart playlists** that fill themselves by rules (artist, genre, year, plays, favourites...), a **play-next queue**, a **smart shuffle** that plays skipped tracks less often and your 5-star tracks more, and **even volume** across your tracks.
- **Listening stats**: your "Azeroth Wrapped" by month, year or all time, with your boss song, your combat song and the zones where you listened most.
- **Import window tools**: find duplicate tracks (nothing is deleted, playlists follow the kept copy) and covers for albums without one, from MusicBrainz.
- **Game soundtrack**: about 600 WoW Forever and classic tracks, plus on Retail about 5,700 tracks of every expansion from The Burning Crusade to Midnight, ready to use, with an in-game icon as the cover, and ready-made playlists for each condition.
- **Welcome guide**: sets everything up in a minute the first time you log in.
- **Podcasts**: the latest episodes of your favourite podcasts, resumed where you left off.
- **Player**: cover, title, remaining time, controls, volume, favourites, a compact mode and a classic WoW look.
- **Comfort**: key bindings, minimap button, movable "Now playing" banner, pause when AFK, lower music during cinematics, per-character profiles.
- **12 languages**: English, Français, Deutsch, Español (EU), Español (AL), Português (BR), Italiano, Русский, 简体中文, 繁體中文, 日本語, 한국어.

## Requirements

- The **WoW Forever** or **Retail** game client (one download works on both).
- To add your own music or podcasts (optional, the game soundtrack works without it):
  - [Python](https://www.python.org/downloads/) (3.8 or newer): download it and install it with the default choices. If the installer shows **"Add python.exe to PATH"**, tick it.
  - [ffmpeg](https://ffmpeg.org/): nothing to do on Windows. The first time, **Import music.py** offers to download it (about 110 MB, into `%LOCALAPPDATA%\KalimdorZugZugRadio\ffmpeg`; delete that folder to remove it). If you prefer, install it yourself with `winget install Gyan.FFmpeg`. On macOS: `brew install ffmpeg`.

## Installation

**From CurseForge or Wago**: install *Kalimdor ZugZug Radio* with the CurseForge app or the Wago app, choosing WoW Forever or Retail as the game version.

**Manually**:

1. Download **`KalimdorZugZugRadio-vX.Y.Z.zip`** from the [latest release](https://github.com/MikeAymeric/KalimdorZugZugRadio/releases/latest).
2. Extract the ZIP.
3. Copy the **`KalimdorZugZugRadio`** folder into your game folder:
   ```
   World of Warcraft\_forever_\Interface\AddOns\
   ```
   On Retail the folder is `World of Warcraft\_retail_\Interface\AddOns\`. The result must be `...\Interface\AddOns\KalimdorZugZugRadio\KalimdorZugZugRadio.toc`.
4. Start the game. In the character selection screen open **AddOns** and make sure **Kalimdor ZugZug Radio** is enabled.

In game, the player window appears and a drum button is added to the minimap. Type `/kzz` to show or hide the player.

The first time, a **welcome guide** opens: it lets you choose the language and the music source, and creates ready-made playlists of the game soundtrack for the conditions you tick. Open it again with the *Tutorial* button in the settings or `/kzz tutorial`.

You can already listen to the game soundtrack: open the library (the **Library** button on the player), select **WoW music** and press **>** on a track.

**Updating**: your music, covers and podcasts live in a separate folder, `AddOns\KalimdorZugZugRadio_Library` (it appears in the AddOns list as *Kalimdor ZugZug Radio - My Music*: keep it enabled). Addon updates, including the CurseForge app's, never touch it. Your playlists and settings are saved by the game in `WTF` and are kept too.

> Updating from 0.7 or older? There, your music was inside the addon folder, which an update can replace. **Back up `AddOns\KalimdorZugZugRadio\music` and `covers` before updating.** Then run **Import music.py** once: it moves everything to the new folder.

## Adding your own music

1. In the addon folder (`AddOns\KalimdorZugZugRadio`), double-click **`Import music.py`** (it needs [Python](https://www.python.org/downloads/)). A window opens. The first time, it offers to download ffmpeg if it is missing.
2. Press **Add files...** or **Add a folder...** and choose your music. Formats: anything ffmpeg can read (mp3, ogg, mp4, m4a, flac, wav...). Folders are kept as they are (for example one per album): they only help you organize and search. Your music is copied to
   ```
   World of Warcraft\_forever_\Interface\AddOns\KalimdorZugZugRadio_Library\music\
   ```
   (**Open the music folder** shows it; you can also copy files there yourself). Files you put in the addon's own `KalimdorZugZugRadio\music` folder are moved there too.
3. Press **Import**. The window shows the progress and tells you when it has finished. Converting a large library, or downloading and converting podcasts, can take a while (especially the first time): do it before starting the game, since new music only appears after a restart and the game saves which episodes you finished when you log out. Your choices (options, music library) are remembered for the next time.

   The window speaks the language you chose in the addon (or the game's, or Windows'), in all 12 languages of the addon; the detailed log below stays in English.

   If double-clicking opens the file in an editor instead, right-click it and choose *Open with* > *Python*. If your Python has no tkinter (some Linux installations), the script shows a text menu instead (also with `python "Import music.py" --menu`).

   You can also run the script from a terminal opened in the addon folder and pass the options directly (the window then doesn't appear; `--help` lists them):
   ```
   python tools\import_music.py --keep-originals
   ```
   The script finds the addon by itself. If you run it from somewhere else and it can't find it, pass the folder:
   ```
   python tools\import_music.py --addon "D:\Path\To\World of Warcraft\_forever_\Interface\AddOns\KalimdorZugZugRadio"
   ```
4. **Restart the game client** (new files are only seen after a restart; if you only removed files, `/reload` is enough).

What the script does:

- **Conversion**: formats WoW can't play are converted to OGG. After a successful conversion the original file (a copy inside the music folder) is deleted; tick *Keep the original files* (or add `--keep-originals`) to keep the originals in `music\_originals\` instead.
- **Covers**: the cover embedded in each file is used, or a `cover.jpg` / `folder.jpg` in the folder. Identical covers are stored only once. An original whose cover can't be extracted is not deleted. At the end the script lists the folders whose tracks have no cover.
- **Your music library**: if you keep your music in another folder (for example a Plex or iTunes library), choose it in the window (*Keep in sync with your music library*), or pass `--library "D:\path\to\library"`. The script compares it with the `music` folder, lists the tracks that are missing and, after you confirm, copies and converts them. The folder is remembered for the next time and is only read. It only adds: a track you delete from `music` but keep in the library is copied again next time. Missing covers are also recovered from it.
- **Recovering covers**: if tracks lost their cover (for example after an interrupted import of an older version) and you still have the original files elsewhere, with the same folders and file names, choose that folder in *Recover missing covers from* (or pass `--covers-from "D:\path\to\originals"`). That folder is only read.
- **Tags**: title, artist, album, genre, year, composer and track numbers are read from each file. Many store-bought MP4 files keep the genre in a way ffmpeg misreads (a game soundtrack shows up as "Big Band"): the script reads the right genre from the file itself, and for tracks converted by an older version from the originals in your music library.
- **File names**: files and folders with non-Latin characters (Japanese, accents...) are renamed, because WoW may not be able to open them. The original names are still shown in-game. Untick *Rename files with non-Latin names* (or pass `--keep-names`) to disable this.
- **Duplicates**: *Find duplicates...* (in the *Library tools* row) lists the tracks that look like the same song: the same title and artist with about the same length, or the same recording under another name (recognised by its loudness, second by second). For each group, the best copy (with a cover, higher quality) is kept and the others are marked *move away*; double-click a track to change it. The ones you move go to `KalimdorZugZugRadio_Library\_duplicates\`: nothing is deleted, and your playlists, favourites, ratings and stats move to the track you keep. `--find-duplicates` lists them in a terminal without moving anything.
- **Covers from the internet**: *Find covers online...* looks up the albums that have no cover on [MusicBrainz](https://musicbrainz.org) and shows the cover found on the [Cover Art Archive](https://coverartarchive.org): *Use this cover*, *Another result*, *Choose an image...* (any image on your PC) or *Skip*. Only the album and artist names are sent, after you agree. The covers are kept in `music\_covers_found\` and used by the import, which starts by itself at the end.
- **Where things go**: the music, `covers`, `Library.lua`, `podcasts.txt` and the script's settings are all in `AddOns\KalimdorZugZugRadio_Library`, a small data addon created by the script, so that addon updates never delete them.
- Run the script again every time you add or remove music.

## Podcasts

1. In the window of **Import music.py**, press **Add...** in the *Podcasts* box and paste the address of the podcast (its RSS feed or its Apple Podcasts page; a link you just copied is pasted for you), with how many episodes to keep, and choose:
   - **Keep the latest episodes**: the newest ones, for news and weekly shows;
   - **Listen in order, from an episode I choose**: after reading the feed the window lists its episodes and you pick the first one. The import downloads that one and the next ones in publishing order; at every import the episodes you finished in game are deleted and the following ones downloaded, so you can go through a whole series. Import with the game closed: the game saves which episodes you finished when you log out.

   The window checks the address at once and shows the podcast's name. *Edit...* changes the number or the mode (or the starting episode), *Remove* takes a podcast off the list (and, if you want, deletes its downloaded episodes).
2. Press **Import** (with *Download new episodes when importing* ticked) before playing: it downloads the new episodes, deletes the older ones and updates the library. Then restart the game client.

The list is saved in `...\AddOns\KalimdorZugZugRadio_Library\podcasts.txt`, which you can also edit by hand: one podcast per line, the address followed by how many episodes to keep (3 if omitted) and, for a podcast listened in order, `from:` and the first episode not finished yet (the window writes it, and the import moves it forward):
```
https://example.com/feed/my-podcast.xml 3
https://podcasts.apple.com/us/podcast/name/id1234567890 2
```

In game the episodes are in the **Podcasts** playlist, newest first; the episodes of a podcast listened in order stay together, oldest first. WoW can't resume a file halfway, so each episode is split into 2:30 parts: the addon remembers the part you reached (even after logging out) and resumes from there.

- **|<** and **>|** move back and forward by one part (2:30).
- **|<<** and **>>|** go to the previous and next episode.

Spotify-exclusive podcasts have no RSS feed and can't be downloaded.

## Using the addon

### The player

- **Cover, title, artist** and the remaining time of the current track.
- **|<  >  >|**: previous, play/stop, next. WoW can't pause a track: stop and play restart it from the beginning.
- **Shuffle**, and the **volume** slider under the cover (it is the game's Music volume).
- The **star** next to the title adds the track to your favourites.
- The **dropdown** on the left chooses between *Automatic (conditions)* and a playlist to listen to freely. It also has:
  - **Assign here**: give the playing playlist to the zone you are in, or to the current dungeon and its boss, or to the enemy you are fighting, with one click (or pick another playlist from its submenu);
  - **Up next**: the tracks you queued; click one to take it out, or clear the queue.
- The **minimize** button turns the player into a small bar; the button on the bar brings it back.

### Automatic music and free play

- **Automatic (conditions)**: the music follows what your character is doing, using the playlists assigned in the settings.
- **Free play**: as soon as you choose the music yourself (a playlist from the dropdown, or **>** on a track), your choice wins over every condition, bosses included, until you select *Automatic (conditions)* again. The player shows *Free play* in orange.

### The library

Open it with the **Library** button, with `/kzz lib`, or by right-clicking the minimap button.

- **Playlists** (left): create, rename, delete, export and import. The virtual playlists are always there: *Whole library*, *WoW music*, *Podcasts*, *Favourites*, *Recently played*, *Most played*.
- **Tracks** (right): select one of your playlists and tick the tracks to include. The search filters by title, artist, album, folder, genre or composer; *Add visible* adds every track in the list. The *Source* menu shows your music, podcasts or the game music.
- **Tracks / Albums / Artists / Genres**: the buttons above the list switch view. Click an album, artist or genre to see its tracks (*< Back* returns to the list), press **>** or *Play* to listen to all of it. With one of your playlists selected, *Add visible* inside an album adds the whole album.
- **>** or a double-click plays a track. The **star** adds it to your favourites. **Right-click** a track for *Play next*, *Add to queue*, *Never play this track* (it is skipped unless you choose it yourself) and **Rating** (1 to 5 stars, shown under the title). Right-click an album for *Play next* and *Add to queue*.
- **Ratings**: rate a track from its right-click menu, from the player's menu (*Rate this track*) or with `/kzz rate 1-5`. With smart shuffle on, 5-star tracks come up about twice as often and 1-star tracks rarely; smart playlists can use the rating (*Rating (stars)* at least 4, for example).
- **Listening stats**: *Listening stats* in the player's menu, or `/kzz stats`, opens your "Azeroth Wrapped" for this month, this year or all time: hours listened, top tracks, artists and genres, the track you heard most under each condition (your boss song, your combat song...) and the zones where you listened most. *Share* copies a text summary for the chat or Discord. Conditions and zones are counted from version 2.0.
- **Smart playlists** (shown in blue): *New smart* opens the rules editor. Give it a name, choose *Match all the rules* or *Match any rule*, and add up to 6 rules: title, artist, album, genre, composer, year, folder, source, plays, length, rating, favourite, never played. The editor shows how many tracks match. The playlist updates by itself as you listen and import music, and can be assigned to conditions like any other. *Edit rules* changes the selected one.
- **Export / Import**: share a playlist as text. Game music works for everyone; your own files only if the other player has the same files.

### Settings

*Options > AddOns > Kalimdor ZugZug Radio*, or `/kzz config`, or Ctrl-click on the minimap button.

- **General**: radio on/off, shuffle, classic style, fade between conditions, minimap button, lock the player, "Now playing" banner (the *Move banner* button lets you drag it anywhere), pause when AFK, lower the music in cinematics and dialogues, compact player, **profile** and **language**, and the *Tutorial* button.
- **Smart shuffle** (on by default): tracks you skip early and the ones you just heard come up less often, tracks you have never heard more often. No track is ever left out.
- **Even out the volume** (on by default): Import music.py measures how loud each of your tracks is (the files are not changed), and the addon plays them all at about the same volume. Tracks imported before 1.6 are measured the next time you run Import music.py. A quiet track can only be raised if your Music volume is below 100%, so if quiet tracks still sound quiet, lower the Music volume a little. The game's own music is not changed.
- **Music after a fight**: how long the fight music keeps playing, slowly fading out, before the next condition (4 to 10 seconds; 4 after a boss). If you start another fight meanwhile, the song goes on. Every new fight starts a different song.
- **Zone music between tracks** (off by default): in calm conditions (no condition, zone, city, night, mounted) the game's own zone music plays every few tracks for a few minutes. Some areas have long silences or no zone music.
- **Next / previous** only change the track: in automatic mode the conditions keep choosing the music.
- **Conditions**: tick the ones you want and choose a playlist for each. The first active condition from the top wins:

  | Priority | Condition | When |
  |---|---|---|
  | 1 | Level up | One track (a jingle) when you level up, then the normal music comes back |
  | 2 | Boss | Dungeon and raid bosses. *Specific bosses* lets you give a boss its own playlist |
  | 3 | Elite / Rare | Fighting an elite or rare enemy. *Specific enemies* works as in Combat |
  | 4 | Battleground / Arena | Inside a battleground or an arena |
  | 5 | Combat | Any fight. *Specific enemies* gives a beast family (boar, wolf, spider...) or a creature type (beast, undead, demon...) its own playlist, chosen by your target; open world only |
  | 6 | Dead / Ghost | While dead or as a ghost |
  | 7 | Flight | On a flight path |
  | 8 | Fishing | While fishing (and between casts) |
  | 9 | Swimming | In the water |
  | 10 | Campfire | Sitting at a campfire, until you move (WoW Forever only) |
  | 11 | Dungeon | Inside a dungeon or raid. *Specific dungeons* lets you give a dungeon its own playlist |
  | 12 | Mounted (ground) | On a ground mount |
  | 13 | Zone music | In a zone that has its own playlist (assign it while you are in the zone) |
  | 14 | City / Resting | In a city or an inn |
  | 15 | Night | From 21:00 to 6:00, game time |
  | 16 | No condition | Everything else |

  Each condition's menu also has a **Volume** submenu (100% to 20%). If no active condition has a playlist, the game's own zone music plays.
  Instead of a playlist you can choose **Game zone music** for a condition (or a zone, boss, dungeon or enemy): the game's own soundtrack plays there. Unlike *None*, it doesn't fall back to a lower condition, so a city set to *Game zone music* plays the city's music even if *No condition* has a playlist.
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
| `/kzz tutorial` | Open the welcome guide again |
| `/kzz play`, `stop`, `next`, `prev`, `shuffle` | Player controls |
| `/kzz auto` | Back to automatic music |
| `/kzz playlist <name>` | Play a playlist freely (`all`, `wow`, `podcast` also work) |
| `/kzz on`, `off` | Turn the radio on or off |
| `/kzz status` | Active conditions and their playlists |
| `/kzz stats` | Open the listening stats |
| `/kzz rate <1-5>` | Rate the track playing (`0` removes the rating) |
| `/kzz lang <code>` | Addon language (`auto`, `en`, `fr`, `de`, `es`, `pt`, `it`, `ru`, `zh`, `ja`...), then `/reload` |
| `/kzz minimap`, `lock`, `reset` | Minimap button, lock or reset the player position |
| `/kzz banner` | Move the "Now playing" banner (drag it; right-click resets it, click to finish) |
| `/kzz perf`, `debug` | Performance and diagnostic information |

## Troubleshooting

- **No sound**: check that *Music* is enabled and not at zero in the game's sound options. The radio uses the Music channel.
- **The conditions don't change the music**: the player is probably in *Free play* (shown in orange). Choose *Automatic (conditions)* in the player's dropdown or type `/kzz auto`.
- **New tracks or episodes don't appear**: run the import script again and restart the game client (not just `/reload`).
- **Your music disappeared after updating from 0.7 or older**: your playlists are safe (the game keeps them in `WTF`). Run **Import music.py** again on the same files, for example choosing your music library in the window: the tracks get the same ids back and reappear in your playlists. The addon tells you at login when playlists refer to missing tracks.
- **Genres look wrong** ("Big Band", "Porn Groove" on a soundtrack): run Import music.py again with your music library set; the right genre is read from the original files.
- **A song restarts from the beginning after a fight or after dying**: WoW can't resume a song halfway. Podcasts resume from their current part.
- **Japanese, Chinese or Korean titles**: they use fonts bundled with the addon (KZZR Sans, and Nanum Gothic for Korean), so they are readable on any client. So are symbols the game font lacks: arrows, stars, hearts, dingbats like ✿ ☀ ⚡ ✨, Greek letters, fullwidth punctuation. Emoji outside the basic plane (😂 🔥) are not supported.
- **Something looks broken**: type `/kzz debug`, then `/reload`, and include the output when you report the problem.

## Development

- `KalimdorZugZugRadio/tools/import_music.py`: imports music and podcasts (see above). It lives inside the addon folder so that users installing from CurseForge or Wago have it too; `Import music.py` runs it with a double-click.
- `tools/build_game_music.py`: regenerates the game soundtrack catalog (`GameMusic.lua`) from the WoW community listfile. For developers only: the generated file is already included.
- `tests/`: run `npm install`, then `npm test` (the addon logic in a Lua VM with simulated WoW APIs) and `npm run lint` (Lua syntax check).
- `RadioProbe/`: a small addon that checks which game APIs work on the client.

## AI disclosure

This addon was built with the help of an AI coding assistant (Anthropic's Claude, through Claude Code). The idea, the design and every decision about features are mine, and I test each version in game on WoW Forever and Retail, reporting bugs back until things work the way I want. Most of the code, the test suite and the translations were written by the AI under my direction, and checked with the automated tests and in-game play.

The addon ships no AI-generated music, covers or artwork: you play your own music files or the game's official soundtrack. The translations into the 11 languages other than English were machine-generated: if you are a native speaker and spot something odd, please open an issue.

## License

Code: [MIT](LICENSE) © 2026 MikeAymeric.

The fonts are **not** covered by the MIT license. `KalimdorZugZugRadio/fonts/KZZRSans-Regular.ttf` (KZZR Sans) is M+ 1p (© The M+ Project Authors) with symbols merged from Noto Sans Symbols, Symbols 2, Math, JP and Emoji (© The Noto Project Authors, Adobe, Google) by `tools/build_fonts.py`; it is distributed under the SIL Open Font License 1.1 (`KalimdorZugZugRadio/fonts/OFL-KZZRSans.txt`). The same applies to `KalimdorZugZugRadio/fonts/NanumGothic-Regular.ttf` (Nanum Gothic, © 2010 NHN Corporation), under the SIL Open Font License 1.1 (`KalimdorZugZugRadio/fonts/OFL-NanumGothic.txt`).

Music is not part of this project: everyone uses their own files. World of Warcraft is a trademark of Blizzard Entertainment; this addon is not affiliated with Blizzard.
