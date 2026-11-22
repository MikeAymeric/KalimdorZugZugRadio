# Changelog

## 2.0.2

- **Fixed: the music stayed low after a voiced dialogue** with **Spoken** or **VivaVoce** (voiceover addons for quests and gossip). They lower the music while a line plays and put it back afterwards, but if the radio changed track or condition during the line, it took the lowered volume as yours and the music stayed low until you raised it by hand. Now the radio waits for the line to end and the music comes back to your volume by itself.
- A change of the Music volume in the game's options is still taken as your new volume at once; a change made by another addon is taken only if it stays for a few seconds.
- `/kzz debug` shows when another addon is holding the music volume.

## 2.0.1

Smoother music between pulls.

- **The fight music no longer dips while you cast your next pull**: after a fight the music now stays at full volume and only fades out in the last seconds before the next condition (the last 40% of the time you chose, at least 3 s). Before, it started fading at once, so a caster pulling the next enemy heard it fade during the cast and swell back when the spell hit.
- **Casting at an enemy counts as fighting**: if you start casting at a living enemy while the fight music is winding down, it comes back to full volume and waits again from the start.
- **Longer fight music**: *Music after a fight* in the settings now also offers 12, 15 and 20 seconds.

## 2.0.0

The biggest update so far: your listening stats, star ratings, even volume across your tracks, and two new tools in the import window to clean up your library.

- **Listening stats ("Azeroth Wrapped")**: a new window (*Listening stats* in the player's menu, or `/kzz stats`) for this month, this year or all time: hours listened, tracks played, top tracks with their covers, top artists and genres, the track you heard most under each condition (your boss song, your combat song, free play...) and the zones where you listened most. *Share* copies a text summary to paste in the chat or on Discord. Conditions and zones are counted from this version on; the all-time tracks include what you heard before.
- **Star ratings**: rate tracks from 1 to 5 stars (right-click in the library, *Rate this track* in the player's menu, `/kzz rate 1-5`). The stars show under the title in the library; smart shuffle plays 5-star tracks about twice as often and 1-star tracks rarely; smart playlists have a new *Rating* rule.
- **Even volume**: some tracks were much louder than others (up to 12 dB apart in a real library). Import music.py now measures the loudness of every track and podcast episode (EBU R128, with ffmpeg), and the addon corrects the volume of each track towards the middle of your library. The files are not changed. Option *Even out the volume* in the settings, on by default. A quiet track can only be raised if your Music volume is below 100%. `--no-loudness` skips the measure.
- **Find duplicates** (Import music window, *Library tools*): the same song twice (same title and artist, about the same length) or the same recording under another name (recognised by its loudness, second by second). The best copy is kept; the others are moved to `KalimdorZugZugRadio_Library\_duplicates\`, never deleted, and your playlists, favourites, ratings and stats move to the copy you keep. `--find-duplicates` lists them in a terminal.
- **Covers from the internet** (Import music window, *Library tools*): for albums without a cover, the cover is looked up on MusicBrainz and the Cover Art Archive and shown to you before it is used; you can also pick another result, choose an image from your PC, or skip. Only album and artist names are sent, after you agree.
- **Run Import music.py once after updating**: it measures the volume of every track (about 0.3 s per track, only this time; then only new files). Until then the addon works as before.
- Fixed: the smart playlist editor failed to open the first time (`LibraryUI.lua:585: attempt to index field 'rules'`).

## 1.5.0

Kalimdor ZugZug Radio now runs on **Retail** too (The War Within / Midnight, 12.1.5), with the same download as WoW Forever.

- **Retail support**: the same addon folder works on WoW Forever and on Retail. Playlists, conditions, the welcome guide, podcasts, your own music and the import window all work the same way. Tested in game on Retail: your music and the game soundtrack, the welcome guide, music for each kind of enemy, dungeons and bosses, flight paths.
- **The whole Retail soundtrack**: on Retail the library offers about 5,700 more game tracks, from The Burning Crusade to Midnight (Outland, Northrend, Cataclysm, Pandaria, Draenor, Legion, Battle for Azeroth, Shadowlands, Dragonflight, The War Within, Midnight), plus events, pet battles and the main themes. They are sorted by expansion and zone, and the welcome guide's ready-made playlists use them too (combat, dungeon, city, night...). Short jingles are left out.
- The **Campfire** condition exists only on WoW Forever: Retail has no campfire auras to detect, so it is hidden there.
- On WoW Forever nothing changes: the expansion tracks are not offered, because that client doesn't have them.

## 1.4.0

Adding your own music no longer needs a terminal.

- **Import music.py opens a window**: add files or whole folders with the usual Windows dialogs, tick the options, press *Import* and follow the progress bar. No numbered menu, no paths to type, and your choices are remembered. The window speaks the language you chose in the addon (or the game's, or Windows'), in all 12 languages of the addon. The text menu is still there with `--menu`, and the command line options work as before.
- **No more ffmpeg to install by hand**: if it is missing, Import music.py offers to download it (about 110 MB, the same builds winget installs, from GitHub, checked against their checksum) into `%LOCALAPPDATA%\KalimdorZugZugRadio\ffmpeg`. Nothing else on the PC is changed; delete that folder to remove it. On macOS and Linux it explains how to install it.
- **Podcasts in the window**: add a podcast by pasting its link (RSS or Apple Podcasts), checked at once and shown by name; change it or remove it with a click. The list is still saved in `podcasts.txt`.
- **Podcasts in order, from the episode you choose**: choose *Listen in order* and pick the first episode from the feed's list. The import downloads it and the next ones; at every import the episodes you finished in game are deleted and the following ones downloaded, so you can go through a whole series. In the Podcasts playlist these episodes stay together, oldest first.
- **Faster imports**: what was read from each track (tags, duration, cover, the genre of the original in your music library) is remembered, so the next imports only read new or changed files. A library of 2000 tracks no longer takes minutes when nothing changed.
- **Faster podcast downloads, with progress**: the next episode downloads while the previous ones convert, and up to 3 episodes convert at the same time on processors with several cores (three episodes took about half the time in our tests). The window shows the megabytes downloaded and how far each conversion is, instead of looking stuck.
- The window reminds you that converting a large library or podcasts can take a while and is best done before starting the game.
- Import music.py says clearly when Python is too old, and asks to report unexpected errors instead of only showing them.

## 1.3.0

- **Game zone music as a choice**: every condition (and every zone, boss, dungeon or enemy) can be set to *Game zone music*. The game's own soundtrack then plays there, and the addon only takes over where you gave a playlist, for example combat, swimming or dungeons. Unlike *None*, it doesn't fall back to a lower condition: a city set to *Game zone music* plays the city's music even if *No condition* has a playlist.
- **Next and Previous no longer switch to free play**: they only change the track, and the conditions keep choosing the music, so combat music still starts after you skipped a song. Free play still starts when you pick a playlist.
- `/kzz debug` now lists the playlist of every condition, to help with bug reports.

## 1.2.0

- **Music for each kind of enemy**: in the Combat and Elite conditions, *Specific enemies* gives a beast family (boar, wolf, wind serpent, spider...) or a creature type (beast, humanoid, undead, demon, elemental...) its own playlist. The first enemy you target in a fight decides it, and the song lasts the whole fight. A family wins over a type, and enemies without a playlist of their own use the normal combat music.
- Enemies appear in the list once you target them, also out of combat, so you can set them up before the fight. *Assign here* in the player's menu offers the enemy of the current or last fight.
- Open world only: in dungeons the game hides what kind of enemy you are fighting.
- Enemies are recognised by the game's own ids, so your choices keep working if you switch the client language; the names follow the client language.

## 1.1.0

- **Movable "Now playing" banner**: the *Move banner* button in the settings (or `/kzz banner`) keeps the banner on screen so you can drag it anywhere. Right-click puts it back above the chat, a click finishes. Outside this mode it still never blocks clicks on the chat.

## 1.0.2

- **No more replay at the end of a song**: when a track ended, about a second of its beginning played again before the next one. The game loops the music it plays, and the addon moved on just after the end; it now moves on a fraction of a second before.
- The level-up jingle ends at the same moment, so it never starts a second jingle.

## 1.0.1

- **Safer podcast downloads**: Import music.py only downloads from web addresses (http/https), so a podcast feed can no longer make it copy a file from your PC into the music folder, and downloads have a size limit (2 GB per episode).
- A podcast feed that comes back empty (for example a temporary server error) no longer deletes the episodes you already downloaded.
- Titles, artists, albums and playlist names containing `|` are shown as written. WoW reads `|c`, `|T` and `|H` as color, icon and link codes, so a file's tags or a shared playlist could show fake colored text or links. Run Import music.py again to apply it to your library.
- A track that is no longer in the library can now be removed from a playlist.
- Code cleanup: shared widgets for the windows, less duplicated logic. Nothing changes in how the addon works.

## 1.0.0

- **Welcome guide**: a short step-by-step window (language, music source, ready-made playlists, tour) opens once for everyone. The *Tutorial* button in the settings and `/kzz tutorial` open it again.
- **Ready-made playlists** of the game soundtrack, one per condition (boss, combat, dungeon, city, campfire, night...), created by the guide. Existing playlists and assignments are never overwritten.
- **Music after a fight**: the fight music keeps playing and slowly fades out (4 to 10 s, default 8; Settings) before the next condition. If another fight starts meanwhile, the song goes on. After a boss the boss theme lasts while adds are still in combat.
- **A new song every fight**, instead of resuming the one interrupted last time.
- **Smart shuffle** (on by default): tracks you skip and the ones you just heard come up less often, tracks you never heard more often.
- **Dungeon-specific music**: give a dungeon its own playlist (*Specific dungeons* in the Dungeon condition).
- **Assign here** in the player's menu: give the current zone, dungeon or boss the playing playlist with one click.
- **Zone music between tracks** (optional, off by default): in calm conditions the game's own zone music plays now and then between two tracks.
- **Smart playlists**: playlists that fill themselves with the tracks matching their rules (title, artist, album, genre, composer, year, folder, source, plays, length, favourite, never played). They update by themselves and can be assigned to conditions like any other.
- **Albums, Artists and Genres** views in the library, with covers: open one, play it whole or queue it.
- **Play next / Add to queue** from the right-click menu; the player's menu shows what is *Up next*. The queue waits during fights.
- **Import music.py reads the genre, year, composer and track numbers**. Many store-bought MP4 files used to show a wrong genre (for example "Big Band" for a game soundtrack, a decoding bug of ffmpeg): the right one is now read from the files, and from the originals in your music library for tracks converted before. **Run Import music.py again** once to add these fields; nothing is converted again.
- Albums play in track order.
- Renaming or deleting a playlist now updates its zone, dungeon and boss assignments in every profile.
- The player's status line no longer repeats the condition ("Auto · Campfire" instead of "Auto · Campfire · Campfire").
- If your playlists refer to tracks that are no longer in the library (for example after an update deleted your music), a message tells you to run Import music.py again.
- `/kzz debug` shows more state for bug reports.

## 0.8.0

- **Your music is safe when you update the addon.** Music, covers, `Library.lua`, `podcasts.txt` and the import settings now live in a separate folder, `AddOns\KalimdorZugZugRadio_Library` (shown in the AddOns list as *Kalimdor ZugZug Radio - My Music*), which addon updates, including the CurseForge app's, never touch.
- **Updating from 0.7 or older: back up `AddOns\KalimdorZugZugRadio\music` and `covers` before updating**, because the old layout kept them inside the addon folder. Then run Import music.py once: it moves everything to the new folder. Your playlists keep working.
- Files dropped into the old `KalimdorZugZugRadio\music` folder are moved to the new one by the import.
- Import menu: option 7 opens your music folder.
- The button that shrinks the player to the compact player shows a dash instead of an X.

## 0.7.1

- **Import music.py shows a menu** with the options (keep originals, rename, podcasts, recover covers, addon folder): no terminal needed.
- **Covers are no longer lost**: the cover list is saved before each original is deleted (an interrupted import used to lose the covers of the files converted so far), and an original whose cover can't be extracted is not deleted.
- New option `--covers-from "folder"` (also in the menu): recovers missing covers from your original files kept elsewhere, without modifying them.
- The import ends with a list of the folders whose tracks have no cover.
- **Sync with your music library**: choose the folder where you keep your music (menu option 1, or `--library`); the import copies and converts only the tracks that are not in the addon yet, after showing you the list. Your library is only read.

## 0.7.0

- **Korean translation** (한국어), with the bundled Nanum Gothic font on non-Korean clients.
- **Korean titles** are readable: Nanum Gothic is bundled for hangul.
- Symbols the game font lacks (arrows, stars, Greek, fullwidth punctuation, ō...) use the bundled font instead of showing boxes.
- The bundled font is now **KZZR Sans**: M+ 1p plus about 2,600 symbols from the Noto fonts (❤ ✿ ☀ ⚡ ✨ ➡ ㊙ ...).
- The dropdowns show Japanese and Korean playlist names with the right font.
- The import script writes titles in composed form (NFC), so names from macOS files show ジ instead of シ + ゛. Run it again to fix an existing library.

## 0.6.2

- **Import music.bat** is replaced by **Import music.py** (CurseForge does not accept .bat files). Double-click it to import your music and podcasts.

## 0.6.1

- The music import script now ships inside the addon folder (`tools/import_music.py`), with **Import music.bat** to run it with a double-click. Users installing from CurseForge or Wago have it too.
- The script finds the addon in your World of Warcraft install by itself.
- Addon metadata (author, website, license, category) in the .toc.

## 0.6.0

- 16 conditions with per-condition volume, boss-specific and zone-specific music, per-character profiles.
- Game soundtrack: about 600 WoW Forever and classic tracks.
- Podcasts, resumed where you left off, with episode navigation.
- Favourites, "never play", recently played, most played and listening stats.
- Classic WoW look, compact player, volume slider, crossfade, lower music in cinematics, pause when AFK.
- Settings panel in Options > AddOns, playlist export and import, "Now playing" banner, key bindings.
- 11 languages.

## 0.4.0

- First working version: conditional playlists, player, library, minimap button.
