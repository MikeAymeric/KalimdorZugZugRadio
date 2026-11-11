# Changelog

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
