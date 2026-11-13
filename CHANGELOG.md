# Changelog

## 1.2.0

- **Music for each kind of enemy**: in the Combat and Elite conditions, *Specific enemies* gives a beast family (boar, wolf, wind serpent, spider...) or a creature type (beast, humanoid, undead, demon, elemental...) its own playlist. The first enemy you target in a fight decides it, and the song lasts the whole fight. A family wins over a type, and enemies without a playlist of their own use the normal combat music.
- Enemies appear in the list once you target them, also out of combat, so you can set them up before the fight. *Assign here* in the player's menu offers the enemy of the current or last fight.
- Open world only: in dungeons the game hides what kind of enemy you are fighting.
- The names come from your game client: if you play the client in another language, the enemies are listed again in that language.

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
