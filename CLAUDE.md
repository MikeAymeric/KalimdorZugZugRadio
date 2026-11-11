# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Kalimdor ZugZug Radio** (`KalimdorZugZugRadio/`) is a World of Warcraft addon for **WoW Forever**. Music lives in the addon's `music/` folder; its subfolders are only for organisation. Since 0.8 the user's files (music, covers, `Library.lua` defining `KZZR_UserLibrary`, `podcasts.txt`, `import_settings.json`) live in a separate data addon, `AddOns/KalimdorZugZugRadio_Library/`, created by the import script, because addon managers (the CurseForge app) replace the addon folder on update. The user builds playlists **in-game** and assigns one playlist per condition (boss, elite/rare, combat, flight, campfire, dungeon, town, and "idle" = no condition). They can also free-play a playlist and ignore the conditions. There are three UIs:
- a now-playing window: cover, title, remaining time, prev/play/next/shuffle, mode/playlist dropdown;
- a library window: playlist CRUD, track picker with search;
- a settings panel in Options > AddOns: general options, language, which conditions are enabled, and the playlist for each. The user communicates in Italian (reply in Italian), but **everything in the repository is English**: code comments, docs, script output, test labels. The project is meant to be published internationally. In-game strings are localized (see `Locales.lua`). Spotify was explicitly dropped because the addon sandbox has no network/IPC.

`RadioProbe/` is a throwaway API compatibility probe whose results are summarised below. Keep it only for re-testing after client patches.

## Commands

- Import music / regenerate the library: `python KalimdorZugZugRadio/tools/import_music.py [--addon DIR] [--keep-originals] [--keep-names] [--covers-from DIR] [--library DIR] [--no-menu]` (or double-click `Import music.py` in the addon folder, a launcher that pauses at the end; CurseForge rejects `.bat` files in the zip). With no arguments and an interactive stdin it shows a numbered menu (`interactive_menu`) that edits the same `args` before running, and asks for the addon folder if it isn't found; any argument skips the menu, so scripted/CLI use is unchanged.
  - `--library DIR` (menu option 1, remembered in the gitignored `<addon>/import_settings.json`): `find_missing` compares the library with `music/` by `track_key` (original folder names + file stem via `_original_names.json`, NFC + casefold, extension ignored) and `copy_missing` copies the missing files (plus the album's cover image) into the matching existing, possibly ASCII-renamed folder before `asciify_tree`/conversion. Add-only: nothing is deleted from `music/` or the library. It is also the default `--covers-from` source. The interactive run lists the tracks and asks for confirmation before copying. The script ships inside the addon so CurseForge/Wago users get it; the store zip must contain only the `KalimdorZugZugRadio` folder. It uses only the stdlib plus ffmpeg/ffprobe.
  - Data addon (0.8): `DATA_DIR = ADDON_DIR.parent / "KalimdorZugZugRadio_Library"`; `MUSIC_DIR`, `COVERS_DIR`, `LIBRARY_FILE`, podcasts.txt and import_settings.json are all under it, and `wow_path` is relative to it. `ensure_data_addon()` writes its `.toc` (Interface copied from the main toc, Title "Kalimdor ZugZug Radio - My Music") and an empty Library.lua. `migrate_to_data_addon()` moves `music`, `covers`, podcasts and settings from the addon folder (0.7 layout, or files dropped into `KalimdorZugZugRadio/music`, kept as a drop folder) with `move_merge` (folders merged, `_original_names.json`/`_index.json` merged, never overwriting) and resets the addon's `Library.lua` to the legacy placeholder. In Lua, `ns.LoadLibrary` reads `KZZR_UserLibrary` (with `addon` = data addon name) and sets `ns.LIB_ROOT` to that folder; without it it falls back to the legacy `KZZR_Library` and `ns.ROOT`. Track ids (`file`) are relative to the root, so playlists survive the move. The main `.toc` has `## OptionalDeps: KalimdorZugZugRadio_Library`; its own `Library.lua` is a placeholder that must stay `KZZR_Library = KZZR_Library or {...}`.
  - It finds the addon dir in this order, looking for `KalimdorZugZugRadio.toc`:
    1. `--addon`;
    2. the cwd and its parents;
    3. the addon installed in WoW on this PC, via `wow_roots()`: the Windows registry `InstallPath` of Blizzard, then the usual folders on every drive, with flavors ordered `_forever_` first;
    4. the script's own location (the repo copy, for development).

    The user's real install is a **copy** in the game's AddOns folder (not a junction), and their music lives there. Never put personal paths in the repo.
  - Originals: after a conversion succeeds (the OGG is probed and has a duration) the source is **deleted**, and an existing `music/_originals/` is removed. `--keep-originals` moves the sources there instead.
  - Covers are deduplicated by content: each one is rendered to raw 256×256 RGB, named `covers/<sha1 of pixels>.png`, and shared by every track with identical art. `covers/_index.json` maps track path (or `folder:<dir>`) → cover + source mtime, so covers survive the source deletion and aren't re-extracted. Unreferenced PNGs are deleted at the end. Legacy per-track `sha1(path)[:12].png` covers are migrated.
  - The index is written unpruned (`save_cover_index(prune=False)`) before each original is deleted: before 0.7.1 it was only written at the end, so an interrupted run lost the mapping and the next run deleted the "unused" PNGs (the user lost ~900 covers that way). An original whose embedded cover fails to extract is converted but not deleted. `--covers-from DIR` recovers missing covers from originals kept elsewhere (`original_rel_path` undoes the ASCII renaming via `_original_names.json`; stems are matched NFC + casefold, any audio extension); DIR is only read. The run ends with a list of folders whose tracks have no cover.
  - By default it renames non-ASCII files and folders to ASCII plus a short sha1 tag before converting, because WoW may not open non-ASCII paths. The original names go to `music/_original_names.json` and are used for the displayed folder name and the title fallback. Versions ≤ 0.4 used Italian names (`_nomi_originali.json`, `_originali/`); the script migrates them automatically.
- Game music catalog (dev-only; the output is committed): `python tools/build_game_music.py [--listfile community-listfile.csv] [--limit N]`. It works as follows:
  - selects tracks from the wowdev community listfile: `sound/music/forever/*`, `citymusic`, `musical moments`, and the classic `zonemusic` dirs in `CLASSIC_ZONES`;
  - measures durations by downloading each file once from `wago.tools/api/casc/<fid>?download` (cached in `tools/game_music_durations.json`, committed, so reruns only fetch new IDs);
  - picks a cover icon via `ICON_RULES` (keyword → icon names, only icons present in the listfile, stored as FileDataID);
  - tags each track with a `preset` = the condition it suits, via `PRESET_RULES` (title/folder regexes, first match wins); `--retag` redoes only this step on the committed GameMusic.lua, with no download;
  - writes `KalimdorZugZugRadio/GameMusic.lua` (`KZZR_GameMusic = { {fid, title, folder, duration, icon, preset} }`, LF line endings). The harness loads the real file and fails if a track has no valid preset.
- Tests (from `tests/`, after `npm install` once):
  - `npm test` runs `harness.lua` in the fengari Lua VM against stubbed WoW APIs. It loads the addon files, simulates events/auras/timers (`fire(...)`, `advance(sec)`, the `G` game-state table) and prints PASS/FAIL scenarios. To add a scenario, append `check(label, cond)` steps at the end of `harness.lua`. When you add a new addon file or WoW API call, also add it to the load list in `run.js`/`harness.lua` and to the stubs.
  - `npm run lint` does a Lua 5.1 syntax check of every addon `.lua` file. There is no local Lua interpreter.
  - Neither replaces in-game testing: stubs accept any widget call.
- There is no build step. Testing is in-game: the addon folder is linked or copied into `<WoW>\_forever_\Interface\AddOns\`. New media files need a **full client restart**; Lua changes only need `/reload`. SavedVariables (`KZZR_DB`) live in `..._forever_\WTF\Account\<acct>\SavedVariables\`.
- ffmpeg 9.0.2 was installed via winget (`Gyan.FFmpeg`). It may not be on PATH in an already-open shell; `find_tool()` in the import script falls back to `%LOCALAPPDATA%\Microsoft\WinGet\Packages\Gyan.FFmpeg*\...\bin`. Don't bundle ffmpeg in the repo.

## Architecture

Game music (OST): `GameMusic.lua` tracks are merged by `ns.LoadLibrary` into `ns.gameTracks`.
- Their id is `"game:<fid>"`, so user playlists can mix them with their own files.
- `ns.GAME` (`"__game"`) is a virtual playlist next to `ns.ALL`. `ns.ALL` = the user's own files only.
- `Player` plays `PlayMusic(track.fid)` for these.
- `ns.CoverOf(t)` returns the icon FileDataID or the addon PNG path.
- `ns.everyTrack` = user tracks + game tracks, used by the library's "source" filter.

Podcasts:
- **Download.** `import_music.py` reads `<addon>/podcasts.txt` (or `podcast.txt`; gitignored) on every run when it exists; `--podcasts` creates it from a template, `--no-podcasts` skips the download. Each line is an RSS feed URL or an Apple Podcasts link, resolved via the iTunes lookup API, plus an optional number of episodes to keep.
- **Storage.** It downloads the newest N episodes and splits each into `PART_SECONDS` (150 s) OGG parts with the ffmpeg segment muxer, in `music/Podcast/<show>/<date> <key>/part_NNN.ogg`. `episode.json` is written last, as the completeness marker. Older episodes are pruned.
- **Library format.** In `Library.lua` each part is a row carrying `episode`/`part`/`parts`. `ns.LoadLibrary` groups the rows into one track: `t.parts`, id `"ep:<key>"`, total duration. `ns.PODCAST` (`"__podcast"`) is a virtual playlist, newest first.
- **Playback.** The Player plays `parts[ns.EpisodePart(t)]`, with resume state in `db.podcastProgress["ep:<key>"] = {part, done}`. `Next`/`Prev` move by one part, and `P.offset` makes `Elapsed()` count from the start of the episode.

v0.5 additions:
- **Conditions.** There are 16, in `ns.SITUATIONS` priority order. `levelup` is a one-track jingle: its end is scheduled on the `TRACK_CHANGED` of the jingle, with a 30s fallback. `fishing` uses channel events plus a 20s grace between casts. `mounted` = ground mount (not taxi, not `IsFlying`). `night` uses `GetGameTime`. `zone` = playlist per zone-level mapID: `ns.CurrentZone()`; micro maps inherit it, but city zones like Orgrimmar don't.
- **Profiles.** `db.profiles[name] = {assign, disabled, zones}` and `db.charProfiles["Name-Realm"]`. `ns.db.assign/disabled/zones` are aliases of the active profile's tables; they are nil'ed on `PLAYER_LOGOUT` so they aren't saved twice. The pre-0.5 `db.assign` is migrated into `Default`.
- **Crossfade.** `Player:SwitchTo` ramps the `Sound_MusicVolume` CVar. The original value is kept in `db.fadeVolume` and restored on load/logout if a fade was interrupted. Tests disable it globally and cover it in a dedicated scenario.
- **Banner.lua.** A "Now playing" toast anchored above `ChatFrame1`.
- **Share.** `ns.ExportPlaylist`/`ImportPlaylist` = `"!KZZR1!" .. base64(name\nids...)`. `ns.ShowShareDialog`.
- **Skins.** `ns.SkinWindow(frame, title, close)` gives any BackdropTemplate frame the classic or modern look. Player: `UI:ApplySkin`, setting `db.ui.skin`. Settings content lives in a `UIPanelScrollFrameTemplate`, with conditions in 2 columns.
- **Performance.**
  - Event handlers only update state; `Rules` coalesces evaluations into one `C_Timer.After(0)`.
  - `UNIT_AURA` is ignored in combat. `ActiveSet` reuses one table. The map chain and the zone are cached, invalidated on zone events.
  - Menus are rebuilt only on `PLAYLISTS_CHANGED`/`MODE_CHANGED`/`SETTINGS_CHANGED`.
  - `ns.Profiled(name, fn)` records CPU time (`debugprofilestop`); `/kzz perf` prints it and stores it in `db.lastPerf`, which is also saved on logout.

v0.6 additions:
- **Volume controller** (Player.lua). `db.userVolume` is the only source of truth. The CVar is written as `user × V.cond (per-condition, profile.volumes) × V.duck (cinematics/talking heads) × V.fade (crossfade)`, animated by `tween(field)`. An external CVar change (game options) is detected against the last written value and adopted. The user volume is written back on logout; `InitVolume` recovers on load. Don't call SetCVar for the music volume anywhere else.
- **Held state.** `P:IsHeld()` = `userStopped` or `afkPaused` (PLAYER_FLAGS_CHANGED + UnitIsAFK). Rules and SetPlaylist don't restart music while held.
- **Exclusions.** `startTrack` skips `db.excluded` tracks unless `P.explicitNext` (set by `PlayTrack`). `ns.RecordPlay` feeds `db.history` (50, newest first), `db.stats[id] = {plays, seconds}` and `db.totalSeconds`.
- **Dynamic playlists.** `ns.FAV/HISTORY/TOP` are virtual playlists. Their cache is refreshed by `ns.InvalidateDynamic()` (menus, library refresh), but never while one of them is the playing queue.
- **Boss music.** `Rules.encounterID` comes from `ENCOUNTER_START`; `db.seenBosses[id] = name`; `profile.bosses[id] = {playlist}` wins in `ns.PlaylistFor("boss")`. Condition dropdowns have Volume and (boss) Specific-bosses submenus, using the Menu API's nested `CreateButton`.
- **Key bindings.** `Bindings.xml` (auto-loaded, header `KZZR`) calls the global `KZZR_Binding(action)`. `BINDING_NAME_*` are set in `ns.SetupBindings()` after the language is known.
- **Compact player.** `KalimdorZugZugRadioCompact` (UI.lua) shows when `db.ui.compact`; `UI:UpdateVisibility` handles both frames.

v1.0 additions (branch `v1.0`):
- **Fight tail** (Rules.lua `FIGHT` = boss/elite/combat; pvp is a location, not a fight). Leaving a fight for a lower condition starts a tail of `db.fightTail` seconds (4/6/8/10, default 8; Settings dropdown) instead of `DOWNGRADE_DELAY`; after `ENCOUNTER_END` it is `ENCOUNTER_TAIL` (4 s). During the tail `P:FadeOutSlowly` ramps `V.fade` to 0 (only with crossfade on); re-entering the fight cancels it and `P:CancelFadeOut` brings the volume back in 1 s, same song. `finishTail` calls `P:EndFadeOut` so `SwitchTo` doesn't fade out twice. If the track ends during the tail, the player's end timer calls `Rules:TrackEnded()` and the switch happens at once. `state.bossTail`: after `ENCOUNTER_END` with adds still in combat the boss theme lasts until `PLAYER_REGEN_ENABLED`. Pending key `"__tail"` marks a running tail; `Rules:Reset()` restores the volume.
- **New track every fight**: `Rules:Apply` passes `fresh` for a fight condition entered from another one; `P:SetPlaylist(name, fresh)` moves an already started queue (`st.started`) to the next shuffled track, or a random other one without shuffle. A fight that goes on keeps its song.
- **Weighted shuffle** (`db.smartShuffle`, default on, Settings checkbox with tooltip). `ns.RecordSkip(track, elapsed)` counts a skip in `db.stats[id].skips` when the user presses Next/SkipTrack before min(30 s, 30 %) of a track (podcasts excluded); listening to ≥ 90 % in `ns.RecordPlay` forgives one. `ns.ShuffleWeights(tracks)`: never heard ×1.5, ÷(1 + 0.5 × skips), history top 10 ×0.25, top 25 ×0.6, floor 0.1. `buildQueue(tracks, first)` sorts by `random()^(1/w)` (Efraimidis–Spirakis); weights are read only when a queue is (re)built.
- **Dungeon-specific music**: `Rules.updateDungeon()` (in `updateWorld`) reads the 8th value of `GetInstanceInfo()` (instanceID; **not yet verified on Forever**, `/kzz debug` prints it on the "conditions" line) into `Rules.dungeonID` and `db.seenDungeons[id] = name`; `profile.dungeons[id] = {playlist, name}` wins in `ns.PlaylistFor("dungeon")` (`ns.AssignDungeon`). Settings has a "Specific dungeons" submenu built by the shared `specificMenu` (also used for bosses). `Rules.lastBossID` = last `ENCOUNTER_START` in this dungeon, cleared when the dungeon changes.
- **Assign here** (UI.lua `assignHereMenu`, in the player dropdown): in a dungeon it offers the dungeon and the current/last boss, elsewhere the current zone. Each entry has "Use the current playlist (X)" plus `ns.PlaylistMenu` (shared radio list, moved from Settings.lua), and prints `MSG_ASSIGNED_HERE`/`MSG_UNASSIGNED_HERE`. The Menu API runs the generator on every open, so the entries follow the player's position.
- **Zone-music breaks** (`db.zoneBreaks`, default **off**; `zoneBreakEvery`/`zoneBreakMinutes`, Settings checkbox + preset dropdown 2/1, 3/2, 5/3, 8/5). When a track ends by itself in auto mode under a calm condition (`P.CALM`: idle, zone, town, night, mounted; not podcasts), `P:MaybeZoneBreak()` counts it and every N tracks calls `Stop()` (StopMusic = game zone music) for M minutes; `P.zoneBreakUntil` makes `P:IsHeld()` true so the rules don't restart the music, and calm→calm switches only change the playlist. A non-calm condition (`Rules:Apply`), `Play`, or a playlist choice in free play (`SetPlaylist` when `mode ~= "auto"`) call `P:EndZoneBreak()`. At the end it plays the next track, or resumes the new playlist if the condition changed. The player and compact player show `ZONE_BREAK_TITLE` and the time left.
- **Game-music presets**: game tracks keep `preset`; `ns.PresetTrackIds(key)` lists the ids for a condition (used by the onboarding's ready-made playlists).
- The harness sets `db.fightTail = 4` globally (old timing) and covers the tail in a dedicated scenario.

Manual precedence: a user choice: a playlist from the dropdown, `PlayFrom`, or `Next`/`Prev` while in auto mode (`takeManualControl` in Player.lua): switches to free play (`db.mode = playlist`). Conditions are then ignored until the user picks "Automatic". The end-of-track timer calls `Next(true)`, which doesn't count as manual.

Load order (`.toc`): `Library.lua` → `GameMusic.lua` → `Locales.lua` → `Core.lua` → `Player.lua` → `Rules.lua` → `UI.lua` → `LibraryUI.lua` → `Settings.lua` → `Minimap.lua`. `Settings.lua` is the settings panel, registered with `Settings.RegisterCanvasLayoutCategory` under Options > AddOns, with a standalone-window fallback if that API is missing. It holds the general toggles, the language dropdown (+ `ReloadUI`), and per-condition enable checkboxes (`db.disabled[key]`, checked in `ns.PlaylistFor`) with playlist dropdowns. `Settings.OpenToCategory` is refused in combat. `Minimap.lua` contains the hand-rolled minimap button (angle saved in `db.minimap`, no LibDBIcon) and the global `KZZR_OnCompartment*` handlers referenced by the `.toc` Addon Compartment fields. They share the addon namespace (`local _, ns = ...`).

- **`Library.lua`** of the data addon (`KalimdorZugZugRadio_Library/Library.lua`) is GENERATED by `KalimdorZugZugRadio/tools/import_music.py`; never hand-edit it. It defines a flat global `KZZR_UserLibrary = { addon = "KalimdorZugZugRadio_Library", tracks = { {file, folder, title, artist, album, duration, cover} } }` with paths relative to the data addon root. The addon's own `KalimdorZugZugRadio/Library.lua` is only a legacy placeholder (`KZZR_Library`, the pre-0.8 global). **`file` is the track id**: user playlists in SavedVariables reference tracks by it. Moving or renaming a file silently drops it from playlists, and tracks missing from the library are skipped. Lua cannot list directories or read file contents/tags/duration, so all metadata comes from the script: tags via ffprobe; non-OGG/MP3 files converted to OGG with libvorbis q5 and the originals deleted (or moved to `music/_originals/`); covers (an embedded `attached_pic` or `cover.jpg`/`folder.jpg`) rendered to 256×256 PNG in `covers/`.
- **`Locales.lua`** holds every user-visible string in 12 languages: enUS (the fallback and reference key set), frFR, deDE, esES, esMX (inherits from esES via a metatable), ptBR, itIT, ruRU, zhCN, zhTW, jaJP and koKR.
  - Never hardcode UI text. Add the key to `LOCALES.enUS` **and every other locale**: the test harness fails on missing keys or mismatched `%s`/`%d` counts.
  - `ns.L` is for UI text and `ns.CL` is for chat. `ns.Print(key, ...)` takes a translation key, not a literal.
  - The language is `db.lang` or `GetLocale()` (enGB is mapped to enUS). It is applied on `/reload`.
  - WoW has no Japanese client, so for jaJP, for koKR on a non-Korean client and for zh on a non-Chinese client, `ns.useAddonFont` is true, and `ns.uiFont` (`"ko"` for koKR, else `"cjk"`) is the default font of `ns.Font`. Our widgets then use copies of Blizzard font objects pointing at the bundled `fonts/KZZRSans-Regular.ttf` (OFL; M+ 1p plus Noto symbols in U+2100-2BFF and U+3200-33FF, generated by the dev-only `python tools/build_fonts.py`, which needs `fonttools` and downloads its sources into the gitignored `tools/.font-cache/`; WoW has no per-glyph font fallback, so missing symbols must be merged in): `ns.Font(template)` / `ns.FontObject`, `ns.StyleMenuItem` for Menu entries, and the separate `KZZR_Tooltip`. Chat falls back to English (`ns.CL`) because the chat font can't render the glyphs.
  - `fonts/NanumGothic-Regular.ttf` (OFL) is the Korean font: KZZR Sans has no hangul, and Nanum Gothic has no kana or kanji. `ns.TextFont(text)` returns `"ko"` (hangul, except on a koKR client), `"cjk"` (kana/kanji, or symbols the Latin game fonts lack: Latin Ext-A, Greek, U+2070-2FFF, fullwidth; Cyrillic except on ruRU) or `false`. `ns.Font(template, force)` takes that value (`true` = `"cjk"`); font objects are `KZZR_<template>` and `KZZR_KO_<template>`. On zh/ko clients the game fonts are used for everything but hangul (zh). The selected text of `ns.MakeDropdown` is hooked (`hooksecurefunc` on `dd.Text.SetText`) to follow the same rule.
  - User-provided text (titles, artists, folders, playlist names; the user's library is mostly Japanese) must go through `ns.SetText(fs, text, template)`. It switches that font string to the font `ns.TextFont` picks. The import script writes displayed fields in NFC (`lua_text`), never the `file` id. `SetFontObject` resets the color, so re-apply colors after it.
  - Create font strings with `ns.Font("GameFont…")`, buttons with `ns.MakeButton`, dropdowns with `ns.MakeDropdown`, and tooltips with `ns.ShowTooltip`, so the font handling stays consistent.
- **`Core.lua`** holds:
  - `ns.SITUATIONS`, the conditions in priority order; `idle` is always active and lowest.
  - SavedVariables `KZZR_DB`: `playlists[name] = {fileIds}`, `assign[condition] = playlistName`, `mode`.
  - The playlist model: `ns.GetPlaylist(name)` returns a cached `{tracks, has}`. `ns.ALL` (`"__all"`) is the virtual whole-library playlist. Edits go through `ns.CreatePlaylist/RenamePlaylist/DeletePlaylist/SetInPlaylist/SetManyInPlaylist/Assign`, which invalidate the cache and fire `PLAYLISTS_CHANGED`.
  - `ns.SetMode("auto" | playlistName)`: free play when it is not `"auto"`. `ns.PlayFrom(playlist, track)`.
  - An internal event bus `ns.On`/`ns.Fire` (`TRACK_CHANGED`, `STATE_CHANGED`, `SITUATION_CHANGED`, `MODE_CHANGED`, `PLAYLISTS_CHANGED`) and a multi-handler game-event registry `ns.RegisterEvent`.
  - The `/kzz` slash commands.
  - The startup steps (`ADDON_LOADED`/`PLAYER_LOGIN`) are each wrapped in `step()` (xpcall): an error doesn't stop the remaining steps, and it is printed in chat and kept in `ns.startupErrors`. `/kzz debug` prints the library, frames, Settings-category and error state. Ask the user for its output first when something is missing in-game.
- **`Player.lua`** keeps per-playlist queues (`states[name] = {queue, pos, count}`), so returning to a playlist after combat restarts the interrupted track. On `PLAYLISTS_CHANGED` it rebuilds the edited playlist's queue around the current track. Playback uses `PlayMusic`, which replaces zone music; `StopMusic` restores zone music. There is no position/seek API: progress is `GetTime() - startTime`, and auto-advance is a `C_Timer` on the manifest duration. `userStopped` stops the rules from auto-restarting after the user presses stop.
- **`Rules.lua`** tracks state flags from events plus a 1s ticker. `Resolve()` returns the first active situation, in priority order, that has a playlist. `Evaluate()` switches to a higher priority immediately and waits `DOWNGRADE_DELAY` (4s) before switching to a lower one. It only acts in `mode == "auto"`.
- **`UI.lua`** is the now-playing frame. **`LibraryUI.lua`** is the library window: two columns (playlists, and tracks with checkboxes and search), with conditions living in Settings. It is built on a small recycled-row virtual list helper (`createList`). Both refresh via bus events. Dropdowns use the modern Menu API (`CreateFrame("DropdownButton", …, "WowStyle1DropdownTemplate")` + `SetupMenu`/`CreateRadio`, refreshed with `GenerateMenu()`).

### Campfire rule (user-specified)

The rule latches on when **both** `Campfire Nearby` (1283391) and `Welcoming Campfire` (1229739) are present. `Welcoming Campfire` appears when the character sits and expires after ~60s; the latch stays on after it expires. It latches off when the character moves (`PLAYER_STARTED_MOVING` or `GetUnitSpeed` in the ticker), when `Campfire Nearby` disappears, or when combat starts.

## Client facts (verified in-game with RadioProbe, build 1.60.1.70862, 2026-11-09)

- `## Interface: 16001`, `WOW_PROJECT_ID == 18`. Modern Mainline (Midnight-era) API, **not** Classic. `UnitAura` does not exist; use `C_UnitAuras`.
- **Audio**: `PlaySoundFile(path, "Music")` returns a handle and `StopSound(handle, fadeMs)` works. OGG, MP3 and WAV play. `PlayMusic`/`StopMusic` work with custom files. **Textures**: TGA and PNG both load.
- **Boss detection**: `ENCOUNTER_START`/`END` fire for dungeon bosses with a readable id and name; they do not fire for world rares/elites. `boss1` is **never** populated and `INSTANCE_ENCOUNTER_ENGAGE_UNIT` never fired.
- **Other working signals**:
  - combat: `PLAYER_REGEN_*`;
  - flight: `UnitOnTaxi` + `PLAYER_CONTROL_LOST`/`GAINED`. `IsMounted()` is also true on a taxi, so flight outranks mounted;
  - `IsResting`, `IsSwimming`, `IsInInstance`, zone events.
- **Secret values in combat** (Midnight restrictions):
  - `UnitHealth` is always secret.
  - `UnitName(target)` is secret in instances but readable in the open world.
  - `UnitClassification(target)` stays readable.
  - Never boolean-test, compare or do arithmetic on possibly-secret values: go through `ns.Safe()`/`ns.IsSecret()`.
- **Auras are unreadable in combat**: `C_UnitAuras.*` errors with "Auras cannot be accessed when secret while tainted". Only query them out of combat (`InCombatLockdown()` guard + `pcall`).
- No `COMBAT_LOG_EVENT_UNFILTERED`. Wrap uncertain APIs in `pcall`.

## In-game status

v0.4.0 (git tag) was confirmed working in-game by the user on 2026-11-10: player, library, settings panel and minimap button. Lessons learned on Forever:
- **Some modern widget methods don't exist.** `Slider:SetObeyStepDrag` is missing (it broke the library window). Guard optional methods with `if obj.Method then`, and mark them absent in the harness stubs.
- **The minimap button needs** a frame level above `Minimap:GetFrameLevel()`, or it renders underneath.
- **`Settings.OpenToCategory` may silently not show the panel.** `ns.Settings:Open()` tries several methods, falls back to a standalone window, and records the attempts in `KZZR_DB.lastSettingsOpen`.
- **For diagnosis**, `KZZR_DB.startupErrors` and `KZZR_DB.lastDebug` are written to `WTF\Account\<acct>\SavedVariables\KalimdorZugZugRadio.lua` on `/reload`, so read that file instead of asking the user to copy chat.
- **Deploying:** the user's game install is a copy, so after code changes, copy the changed `.lua`/`.toc`/`.xml` files to the game's AddOns copy (the path is in Claude's local memory, not in the repo). Never copy over `music\`, `covers\` or `Library.lua` there.

Still unverified: whether non-ASCII file paths play (the import script avoids them by renaming).

## Git

The repo is on `main`. `music/*` and `covers/` are gitignored because they hold user content, often copyrighted; `Library.lua` is committed as the empty placeholder.
