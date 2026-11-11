-- Core: namespace, SavedVariables, library, user playlists, event bus, slash commands.
local ADDON, ns = ...
local L, CL = ns.L, ns.CL

ns.ADDON = ADDON
ns.ROOT = "Interface\\AddOns\\" .. ADDON .. "\\"
-- Root of the user's files (tracks, covers): the KalimdorZugZugRadio_Library data addon written by
-- Import music.py (KZZR_UserLibrary), or this addon's folder for a library imported before 0.8.
ns.LIB_ROOT = ns.ROOT
ns.ALL = "__all" -- virtual playlist with the whole user library

-- Conditions in priority order: the first active one with an assigned playlist wins.
-- "idle" is always active: it's the music when no other condition applies.
ns.SITUATIONS = {
  { key = "levelup" }, { key = "boss" }, { key = "elite" }, { key = "pvp" }, { key = "combat" },
  { key = "dead" }, { key = "flight" }, { key = "fishing" }, { key = "swimming" }, { key = "campfire" },
  { key = "dungeon" }, { key = "mounted" }, { key = "zone" }, { key = "town" }, { key = "night" },
  { key = "idle" },
}
ns.SITUATION_BY_KEY, ns.PRIORITY = {}, {}
for i, s in ipairs(ns.SITUATIONS) do
  ns.SITUATION_BY_KEY[s.key] = s
  ns.PRIORITY[s.key] = i
end

function ns.SituationLabel(key, chat)
  return (chat and CL or L)["SIT_" .. key]
end

local DEFAULTS = {
  enabled = true,
  mode = "auto",   -- "auto" (conditions) or a playlist name (free play)
  shuffle = true,
  playlists = {},  -- name -> { file, file, ... } (file = track id)
  smartPlaylists = {}, -- name -> { match = "all" | "any", rules = { { field, op, value }, ... } }
  upNext = {},     -- track ids queued with "Play next" / "Add to queue"
  -- per-character profiles: name -> { assign = {condition -> playlist}, disabled = {condition -> true},
  -- zones = {mapID -> {playlist, name}}, bosses/dungeons = {id -> {playlist, name}}, volumes }.
  -- ns.db.assign/disabled/zones/bosses/dungeons/volumes point to the active profile.
  profiles = {},
  charProfiles = {}, -- "Name-Realm" -> profile name
  crossfade = true,  -- fade the music volume when the condition changes
  smartShuffle = true, -- weighted shuffle: skipped/recent tracks less often, unheard ones more
  zoneBreaks = false,   -- now and then let the game's zone music play between two tracks
  zoneBreakEvery = 3,   -- ... every N tracks
  zoneBreakMinutes = 2, -- ... for M minutes
  fightTail = 8,     -- seconds the fight music keeps playing (fading out) after the combat
  duck = true,       -- lower the music during cinematics and dialogues
  afkPause = true,   -- pause while AFK
  userVolume = nil,  -- the user's Music volume (the addon multiplies it, see Player.lua)
  favorites = {},    -- track id -> true
  excluded = {},     -- track id -> true (never played automatically)
  history = {},      -- track ids, most recent first (max 50)
  stats = {},        -- track id -> { plays = n, seconds = s, skips = n }
  totalSeconds = 0,
  seenBosses = {},   -- encounterID -> boss name (to assign boss-specific music)
  seenDungeons = {}, -- instanceID -> dungeon name (to assign dungeon-specific music)
  podcastProgress = {}, -- "ep:<key>" -> { part = n, done = true|nil, at = timestamp }
  lang = nil,      -- nil = client language
  ui = { shown = true, locked = false, skin = "classic", banner = true, compact = false }, -- skin: "classic" | "modern"
  minimap = { angle = 225, hide = false },
}

---------------------------------------------------------------------------
-- Utilities
---------------------------------------------------------------------------
-- Chat message. key is a translation key (texts in ns.CL).
function ns.Print(key, ...)
  local msg = CL[key]
  if select("#", ...) > 0 then msg = msg:format(...) end
  print("|cffff7f00ZugZug Radio|r: " .. msg)
end

---------------------------------------------------------------------------
-- Profiling: cheap CPU-time accounting of the addon's hot paths (/kzz perf).
---------------------------------------------------------------------------
ns.perf = {} -- name -> { calls, total (ms), max (ms) }
local clock = debugprofilestop

function ns.perfCount(name)
  local e = ns.perf[name]
  if not e then e = { calls = 0, total = 0, max = 0 } ns.perf[name] = e end
  e.calls = e.calls + 1
end

-- Wraps fn so that its calls and CPU time are recorded under `name`.
function ns.Profiled(name, fn)
  if not clock then return fn end
  return function(...)
    local t0 = clock()
    local a, b, c = fn(...)
    local dt = clock() - t0
    local e = ns.perf[name]
    if not e then e = { calls = 0, total = 0, max = 0 } ns.perf[name] = e end
    e.calls, e.total = e.calls + 1, e.total + dt
    if dt > e.max then e.max = dt end
    return a, b, c
  end
end

function ns.PerfReport()
  local rows = {}
  for name, e in pairs(ns.perf) do rows[#rows + 1] = { name = name, e = e } end
  table.sort(rows, function(a, b) return a.e.total > b.e.total end)
  local lines = {}
  local mem = 0
  if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
    pcall(UpdateAddOnMemoryUsage)
    local ok, kb = pcall(GetAddOnMemoryUsage, ns.ADDON)
    mem = ok and kb or 0
  end
  lines[1] = ("ZugZug Radio perf: memory %.0f KB, since %.0fs ago"):format(mem, GetTime() - (ns.perfSince or 0))
  for i = 1, math.min(#rows, 15) do
    local r = rows[i]
    lines[#lines + 1] = ("  %-34s calls %6d   total %8.2f ms   max %6.2f ms"):format(r.name, r.e.calls, r.e.total, r.e.max)
  end
  return lines
end

-- true if v is a Midnight "secret value" (cannot be compared or used).
function ns.IsSecret(v)
  if issecretvalue then
    local ok, secret = pcall(issecretvalue, v)
    return ok and secret == true
  end
  return false
end

-- Calls fn protected; returns the first value only if it isn't secret.
function ns.Safe(fn, ...)
  if not fn then return nil end
  local ok, v = pcall(fn, ...)
  if not ok or ns.IsSecret(v) then return nil end
  return v
end

function ns.FormatTime(sec)
  sec = math.max(0, math.floor(sec + 0.5))
  return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end

function ns.TrackLabel(t)
  if not t then return "" end
  if t.artist and t.artist ~= "" then return t.title .. "  -  " .. t.artist end
  return t.title
end

-- Addon tooltip (separate from GameTooltip so we can change fonts without touching Blizzard's).
-- lines = { "text" | { "text", r, g, b } , ... }; the first line is the title.
local tip
function ns.ShowTooltip(owner, anchor, lines)
  if not tip then
    tip = CreateFrame("GameTooltip", "KZZR_Tooltip", UIParent, "GameTooltipTemplate")
  end
  tip:SetOwner(owner, anchor or "ANCHOR_TOP")
  tip:ClearLines()
  for i, line in ipairs(lines) do
    local text, r, g, b = line, nil, nil, nil
    if type(line) == "table" then text, r, g, b = line[1], line[2], line[3], line[4] end
    if i == 1 then tip:AddLine(text, r or 1, g or 0.82, b or 0) else tip:AddLine(text, r or 1, g or 1, b or 1, true) end
  end
  for i = 1, tip:NumLines() do
    local fs = _G["KZZR_TooltipTextLeft" .. i]
    if fs then
      local template = i == 1 and "GameTooltipHeaderText" or "GameTooltipText"
      local fo = ns.FontObject(template, ns.TextFont(fs:GetText()))
      if fo then fs:SetFontObject(fo) end
    end
  end
  tip:Show()
end
function ns.HideTooltip()
  if tip then tip:Hide() end
end

---------------------------------------------------------------------------
-- Internal event bus
-- TRACK_CHANGED, STATE_CHANGED, SITUATION_CHANGED, MODE_CHANGED, PLAYLISTS_CHANGED(name?)
---------------------------------------------------------------------------
local listeners = {}
function ns.On(event, fn)
  listeners[event] = listeners[event] or {}
  table.insert(listeners[event], fn)
end
function ns.Fire(event, ...)
  for _, fn in ipairs(listeners[event] or {}) do
    local ok, err = pcall(fn, ...)
    if not ok then geterrorhandler()(err) end
  end
end

-- Game events: several modules can register the same event.
local frame = CreateFrame("Frame")
local gameHandlers = {}
function ns.RegisterEvent(event, fn)
  if not gameHandlers[event] then
    gameHandlers[event] = {}
    if not pcall(frame.RegisterEvent, frame, event) then
      gameHandlers[event] = nil
      return false
    end
  end
  table.insert(gameHandlers[event], fn)
  return true
end
frame:SetScript("OnEvent", function(_, event, ...)
  for _, fn in ipairs(gameHandlers[event] or {}) do fn(...) end
end)

---------------------------------------------------------------------------
-- Library (generated by tools/import_music.py into Library.lua)
---------------------------------------------------------------------------
-- ns.tracks = the user's music (Library.lua), ns.episodes = podcast episodes, ns.gameTracks = in-game music (GameMusic.lua).
-- Every track has a stable id in t.file: the path for user tracks, "game:<FileDataID>" for game music.
ns.tracks, ns.gameTracks, ns.everyTrack, ns.episodes = {}, {}, {}, {}
ns.trackById, ns.userById, ns.gameById, ns.episodeById = {}, {}, {}, {}
ns.GAME = "__game"       -- virtual playlist with all the in-game music
ns.PODCAST = "__podcast" -- virtual playlist with podcast episodes, newest first
ns.FAV = "__fav"         -- favourites
ns.HISTORY = "__history" -- recently played
ns.TOP = "__top"         -- most played
-- Podcast episodes are split into parts (Library.lua: episode/part/parts fields): here they become
-- a single track with t.parts = { {file, duration}, ... } and id "ep:<key>".

-- Folder, then album order (disc and track number, when the tags have them), then title.
local function byFolderTitle(a, b)
  if a.folder ~= b.folder then return a.folder < b.folder end
  local da, db = tonumber(a.disc) or 0, tonumber(b.disc) or 0
  if da ~= db then return da < db end
  local ta, tb = tonumber(a.track) or 0, tonumber(b.track) or 0
  if ta ~= tb then return ta < tb end
  return a.title:lower() < b.title:lower()
end

local function indexTrack(t, list, byId)
  t.folder = t.folder or ""
  t._search = (t.title .. " " .. (t.artist or "") .. " " .. (t.album or "") .. " " .. t.folder .. " "
    .. (t.genre or "") .. " " .. (t.composer or "")):lower()
  table.insert(list, t)
  byId[t.file] = t
  ns.trackById[t.file] = t
end

function ns.LoadLibrary()
  for _, t in ipairs({ ns.tracks, ns.gameTracks, ns.everyTrack, ns.episodes, ns.trackById, ns.userById,
                       ns.gameById, ns.episodeById }) do wipe(t) end
  local episodes = {}
  local lib = KZZR_UserLibrary
  if type(lib) == "table" and type(lib.addon) == "string" then
    ns.LIB_ROOT = "Interface\\AddOns\\" .. lib.addon .. "\\"
  else
    lib, ns.LIB_ROOT = KZZR_Library, ns.ROOT -- library imported before 0.8, inside this addon
  end
  ns.library = lib
  for _, t in ipairs((type(lib) == "table" and lib.tracks) or {}) do
    if type(t.file) == "string" and type(t.episode) == "string" then
      local ep = episodes[t.episode]
      if not ep then
        ep = { file = "ep:" .. t.episode, episode = t.episode, podcast = true, title = t.title or "?",
               artist = t.artist, album = t.album, folder = t.folder, cover = t.cover, parts = {}, duration = 0 }
        episodes[t.episode] = ep
      end
      table.insert(ep.parts, { file = t.file, duration = tonumber(t.duration) or 0, index = t.part or #ep.parts + 1 })
    elseif type(t.file) == "string" and not ns.trackById[t.file] then
      t.title = (t.title and t.title ~= "") and t.title or t.file:match("([^\\]+)%.%w+$") or t.file
      indexTrack(t, ns.tracks, ns.userById)
    end
  end
  for _, ep in pairs(episodes) do
    table.sort(ep.parts, function(a, b) return a.index < b.index end)
    for _, part in ipairs(ep.parts) do ep.duration = ep.duration + part.duration end
    -- podcasts have their own category: not part of "Whole library" (ns.tracks)
    indexTrack(ep, ns.episodes, ns.episodeById)
  end
  table.sort(ns.episodes, function(a, b)
    if (a.album or "") ~= (b.album or "") then return (a.album or "") > (b.album or "") end -- date, newest first
    return a.title < b.title
  end)
  for _, g in ipairs(KZZR_GameMusic or {}) do
    local id = "game:" .. tostring(g.fid)
    if type(g.fid) == "number" and not ns.trackById[id] then
      indexTrack({ file = id, fid = g.fid, game = true, title = g.title or tostring(g.fid), artist = "World of Warcraft",
        album = "", folder = g.folder, duration = g.duration, icon = g.icon, preset = g.preset },
        ns.gameTracks, ns.gameById)
    end
  end
  table.sort(ns.tracks, byFolderTitle)
  table.sort(ns.gameTracks, byFolderTitle)
  for _, list in ipairs({ ns.tracks, ns.episodes, ns.gameTracks }) do
    for _, t in ipairs(list) do table.insert(ns.everyTrack, t) end
  end
end

-- Ids of the game tracks suited to a condition (the `preset` field of GameMusic.lua), used to
-- create ready-made playlists.
function ns.PresetTrackIds(key)
  local ids = {}
  for _, t in ipairs(ns.gameTracks) do
    if t.preset == key then ids[#ids + 1] = t.file end
  end
  return ids
end

-- Cover texture: game icon (FileDataID) for game music, the addon's PNG for the rest.
function ns.CoverOf(t)
  if not t then return nil end
  if t.icon then return t.icon end
  if t.cover then return ns.LIB_ROOT .. t.cover end
  return nil
end

---------------------------------------------------------------------------
-- Playlist
---------------------------------------------------------------------------
local cache = {} -- name -> { name, tracks = {...}, has = { [file] = true } }

local function invalidate(name)
  if name then cache[name] = nil else wipe(cache) end
  ns.Fire("PLAYLISTS_CHANGED", name)
end

function ns.PlaylistLabel(name, chat)
  if name == ns.ALL then return (chat and CL or L).ALL_LIBRARY end
  if name == ns.GAME then return (chat and CL or L).GAME_MUSIC end
  if name == ns.PODCAST then return (chat and CL or L).PODCASTS end
  if name == ns.FAV then return (chat and CL or L).FAVORITES end
  if name == ns.HISTORY then return (chat and CL or L).HISTORY end
  if name == ns.TOP then return (chat and CL or L).TOP end
  local kind = ns.GroupKind(name)
  if kind then
    local pl = ns.GetPlaylist(name)
    local t = pl and pl.tracks[1]
    return t and ns.GroupLabel(kind, t) or "?"
  end
  return name
end

-- Part to resume an episode from (1 if never played or already finished).
function ns.EpisodePart(t)
  local prog = t and t.parts and ns.db.podcastProgress[t.file]
  if not prog or prog.done then return 1 end
  return math.max(1, math.min(#t.parts, tonumber(prog.part) or 1))
end

function ns.SetEpisodePart(t, part, done)
  if not (t and t.parts) then return end
  ns.db.podcastProgress[t.file] = { part = part, done = done or nil, at = time and time() or 0 }
end

-- All playlists to show in menus: the virtual ones (if they have tracks) + the user's.
function ns.AllPlaylistNames()
  ns.InvalidateDynamic()
  local names = ns.PlaylistNames()
  for _, virtual in ipairs({ ns.TOP, ns.HISTORY, ns.FAV }) do
    if ns.IsPlayable(virtual) then table.insert(names, 1, virtual) end
  end
  if #ns.episodes > 0 then table.insert(names, 1, ns.PODCAST) end
  if #ns.gameTracks > 0 then table.insert(names, 1, ns.GAME) end
  table.insert(names, 1, ns.ALL)
  return names
end

function ns.PlaylistNames()
  local names = {}
  for name in pairs(ns.db.playlists) do names[#names + 1] = name end
  for name in pairs(ns.db.smartPlaylists) do
    if not ns.db.playlists[name] then names[#names + 1] = name end
  end
  table.sort(names, function(a, b) return a:lower() < b:lower() end)
  return names
end

-- { name, tracks, has } or nil if the playlist doesn't exist.
function ns.GetPlaylist(name)
  if not name then return nil end
  if cache[name] then return cache[name] end
  local pl
  if name == ns.ALL then
    pl = { name = name, tracks = ns.tracks, has = ns.userById }
  elseif name == ns.GAME then
    pl = { name = name, tracks = ns.gameTracks, has = ns.gameById }
  elseif name == ns.PODCAST then
    pl = { name = name, tracks = ns.episodes, has = ns.episodeById }
  elseif name == ns.FAV or name == ns.HISTORY or name == ns.TOP then
    pl = { name = name, tracks = {}, has = {} }
    local ids = {}
    if name == ns.FAV then
      for _, t in ipairs(ns.everyTrack) do if ns.db.favorites[t.file] then ids[#ids + 1] = t.file end end
    elseif name == ns.HISTORY then
      ids = ns.db.history
    else
      for id, st in pairs(ns.db.stats) do if (st.plays or 0) > 0 and ns.trackById[id] then ids[#ids + 1] = id end end
      table.sort(ids, function(a, b) return ns.db.stats[a].plays > ns.db.stats[b].plays end)
      for i = #ids, 51, -1 do ids[i] = nil end
    end
    for _, id in ipairs(ids) do
      local t = ns.trackById[id]
      if t and not pl.has[id] then table.insert(pl.tracks, t) pl.has[id] = true end
    end
  elseif ns.GroupKind(name) then
    pl = { name = name, tracks = {}, has = {} }
    local kind, key = ns.GroupKind(name)
    for _, list in ipairs({ ns.tracks, ns.gameTracks }) do
      for _, t in ipairs(list) do
        if ns.GroupKey(kind, t) == key then table.insert(pl.tracks, t) pl.has[t.file] = true end
      end
    end
  elseif ns.IsSmart(name) then
    pl = { name = name, tracks = ns.SmartTracks(ns.db.smartPlaylists[name]), has = {} }
    for _, t in ipairs(pl.tracks) do pl.has[t.file] = true end
  else
    local ids = ns.db.playlists[name]
    if type(ids) ~= "table" then return nil end
    pl = { name = name, tracks = {}, has = {} }
    for _, id in ipairs(ids) do
      local t = ns.trackById[id]
      if t and not pl.has[id] then
        table.insert(pl.tracks, t)
        pl.has[id] = true
      end
    end
  end
  cache[name] = pl
  return pl
end

function ns.IsPlayable(name)
  local pl = ns.GetPlaylist(name)
  return pl ~= nil and #pl.tracks > 0
end

-- Case-insensitive lookup for slash commands ("all" or its translation = the whole library).
function ns.FindPlaylist(name)
  if type(name) ~= "string" or name == "" then return nil end
  local lower = name:lower()
  if name == ns.ALL then return ns.ALL end
  if name == ns.GAME or lower == "wow" or lower == "game" or lower == L.GAME_MUSIC:lower() then return ns.GAME end
  if name == ns.PODCAST or lower == "podcast" or lower == "podcasts" or lower == L.PODCASTS:lower() then return ns.PODCAST end
  if name == ns.FAV or lower == "fav" or lower == "favorites" or lower == L.FAVORITES:lower() then return ns.FAV end
  if name == ns.HISTORY or lower == "history" or lower == L.HISTORY:lower() then return ns.HISTORY end
  if name == ns.TOP or lower == "top" or lower == L.TOP:lower() then return ns.TOP end
  for _, loc in pairs(ns.LOCALES) do
    if loc.ALL_KEYWORD and lower == loc.ALL_KEYWORD:lower() then return ns.ALL end
  end
  if ns.db.playlists[name] or ns.db.smartPlaylists[name] then return name end
  if ns.GroupKind(name) and ns.GetPlaylist(name) then return name end
  for _, store in ipairs({ ns.db.playlists, ns.db.smartPlaylists }) do
    for n in pairs(store) do
      if n:lower() == lower then return n end
    end
  end
end

local function cleanName(name)
  name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" or name:sub(1, 2) == "__" then return nil end -- "__..." are the virtual playlists
  return name
end

-- Editing functions return the name, or nil + a translatable error key.
function ns.CreatePlaylist(name)
  name = cleanName(name)
  if not name then return nil, "ERR_BAD_NAME" end
  if ns.FindPlaylist(name) then return nil, "ERR_EXISTS" end
  ns.db.playlists[name] = {}
  invalidate(name)
  return name
end

-- Points every assignment of every profile (conditions, zones, bosses, dungeons) from playlist
-- `old` to `new` (nil = remove the assignment).
local function replaceAssignments(old, new)
  for _, prof in pairs(ns.db.profiles) do
    if type(prof.assign) == "table" then
      for key, v in pairs(prof.assign) do
        if v == old then prof.assign[key] = new end
      end
    end
    for _, field in ipairs({ "zones", "bosses", "dungeons" }) do
      local map = prof[field]
      if type(map) == "table" then
        for id, e in pairs(map) do
          if type(e) == "table" and e.playlist == old then
            if new then e.playlist = new else map[id] = nil end
          end
        end
      end
    end
  end
end

-- The table holding a user playlist (plain or smart), or nil.
local function storeOf(name)
  if name == nil then return nil end
  if ns.db.playlists[name] then return ns.db.playlists end
  if ns.db.smartPlaylists[name] then return ns.db.smartPlaylists end
end

function ns.RenamePlaylist(old, new)
  new = cleanName(new)
  local store = storeOf(old)
  if not new or not store then return nil, "ERR_BAD_NAME" end
  if new == old then return new end
  local existing = ns.FindPlaylist(new)
  if existing and existing ~= old then return nil, "ERR_EXISTS" end
  store[new], store[old] = store[old], nil
  replaceAssignments(old, new)
  if ns.db.mode == old then ns.db.mode = new end
  ns.Player:Rename(old, new)
  cache[old] = nil
  invalidate(new)
  return new
end

function ns.DeletePlaylist(name)
  local store = storeOf(name)
  if not store then return end
  store[name] = nil
  replaceAssignments(name, nil)
  invalidate(name)
  if ns.db.mode == name then ns.SetMode("auto") else ns.Rules:Evaluate(true) end
end

-- Adds/removes a track from a user playlist.
function ns.SetInPlaylist(name, id, include)
  local ids = ns.db.playlists[name]
  if type(ids) ~= "table" or not ns.trackById[id] then return end
  for i = #ids, 1, -1 do
    if ids[i] == id then table.remove(ids, i) end
  end
  if include then table.insert(ids, id) end
  invalidate(name)
  ns.Rules:Evaluate()
end

-- Bulk version (e.g. "add all visible tracks").
function ns.SetManyInPlaylist(name, ids, include)
  local list = ns.db.playlists[name]
  if type(list) ~= "table" then return end
  local remove = {}
  for _, id in ipairs(ids) do remove[id] = true end
  for i = #list, 1, -1 do
    if remove[list[i]] then table.remove(list, i) end
  end
  if include then
    for _, id in ipairs(ids) do
      if ns.trackById[id] then table.insert(list, id) end
    end
  end
  invalidate(name)
  ns.Rules:Evaluate()
end

---------------------------------------------------------------------------
-- Smart playlists: filled by rules on the tracks' tags and listening data. Like history, they
-- are recomputed when looked at (ns.InvalidateDynamic), never while they are playing.
---------------------------------------------------------------------------
ns.SMART_FIELDS = {
  { key = "title", kind = "text" }, { key = "artist", kind = "text" }, { key = "album", kind = "text" },
  { key = "genre", kind = "text" }, { key = "composer", kind = "text" }, { key = "year", kind = "number" },
  { key = "folder", kind = "text" }, { key = "source", kind = "source" }, { key = "plays", kind = "number" },
  { key = "minutes", kind = "number" }, { key = "favorite", kind = "flag" }, { key = "never", kind = "flag" },
}
ns.SMART_OPS = { text = { "has", "not", "is" }, source = { "is", "isnot" }, number = { "ge", "le" }, flag = { "yes", "no" } }
ns.SMART_SOURCES = { "mine", "game", "podcast" }
ns.SMART_MAX_RULES = 6
local FIELD_KIND = {}
for _, fd in ipairs(ns.SMART_FIELDS) do FIELD_KIND[fd.key] = fd.kind end
function ns.SmartFieldKind(field) return FIELD_KIND[field] end

function ns.SourceOf(t)
  return t.game and "game" or t.podcast and "podcast" or "mine"
end

-- true if track t satisfies rule r. Rules with an empty or invalid value are ignored (true).
local function matchRule(t, r)
  local kind = FIELD_KIND[r.field]
  if kind == "text" then
    local q = tostring(r.value or ""):lower()
    if q == "" then return true end
    local v = tostring(t[r.field] or ""):lower()
    if r.op == "is" then return v == q end
    local found = v:find(q, 1, true) ~= nil
    if r.op == "not" then return not found end
    return found
  elseif kind == "source" then
    if r.value == nil then return true end
    local same = ns.SourceOf(t) == r.value
    if r.op == "isnot" then return not same end
    return same
  elseif kind == "number" then
    local n = tonumber(r.value)
    if not n then return true end
    local v
    if r.field == "plays" then
      local st = ns.db.stats[t.file]
      v = st and st.plays or 0
    elseif r.field == "year" then
      v = tonumber(t.year)
      if not v then return false end -- no year in the tags: never matches a year rule
    else
      v = (tonumber(t.duration) or 0) / 60
    end
    if r.op == "le" then return v <= n end
    return v >= n
  elseif kind == "flag" then
    local on
    if r.field == "favorite" then
      on = ns.db.favorites[t.file] == true
    else
      local st = ns.db.stats[t.file]
      on = not st or (st.plays or 0) == 0
    end
    if r.op == "no" then return not on end
    return on
  end
  return true
end

-- The tracks matched by a smart playlist definition { match, rules }.
function ns.SmartTracks(def)
  local out = {}
  local rules = type(def) == "table" and type(def.rules) == "table" and def.rules or {}
  local any = type(def) == "table" and def.match == "any"
  for _, t in ipairs(ns.everyTrack) do
    local ok
    if #rules == 0 then
      ok = true
    elseif any then
      ok = false
      for _, r in ipairs(rules) do if matchRule(t, r) then ok = true break end end
    else
      ok = true
      for _, r in ipairs(rules) do if not matchRule(t, r) then ok = false break end end
    end
    if ok then out[#out + 1] = t end
  end
  return out
end

function ns.IsSmart(name)
  return name ~= nil and ns.db.smartPlaylists[name] ~= nil and not ns.db.playlists[name]
end

-- Creates (old = nil) or updates a smart playlist. Returns its name, or nil + error key.
function ns.SaveSmartPlaylist(old, name, def)
  name = cleanName(name)
  if not name then return nil, "ERR_BAD_NAME" end
  local existing = ns.FindPlaylist(name)
  if existing and existing ~= old then return nil, "ERR_EXISTS" end
  if old and old ~= name then
    if not ns.IsSmart(old) then return nil, "ERR_BAD_NAME" end
    local renamed, err = ns.RenamePlaylist(old, name)
    if not renamed then return nil, err end
  end
  local rules = {}
  for _, r in ipairs(type(def) == "table" and type(def.rules) == "table" and def.rules or {}) do
    if FIELD_KIND[r.field] and #rules < ns.SMART_MAX_RULES then
      rules[#rules + 1] = { field = r.field, op = r.op, value = r.value }
    end
  end
  ns.db.smartPlaylists[name] = { match = type(def) == "table" and def.match == "any" and "any" or "all", rules = rules }
  invalidate(name)
  ns.Rules:Evaluate()
  return name
end

---------------------------------------------------------------------------
-- Albums, artists and genres: virtual playlists "__album:<key>" / "__artist:<key>" /
-- "__genre:<key>". They are not listed in the menus, but can be played and assigned like any other.
---------------------------------------------------------------------------
local GROUP_PREFIX = { album = "__album:", artist = "__artist:", genre = "__genre:" }

function ns.GroupKey(kind, t)
  if kind == "artist" then return (t.artist or ""):lower() end
  if kind == "genre" then return (t.genre or ""):lower() end
  return (t.album or ""):lower() .. " @ " .. (t.folder or "")
end

function ns.GroupLabel(kind, t)
  if kind == "artist" then
    return (t.artist and t.artist ~= "") and t.artist or L.UNKNOWN_ARTIST
  end
  if kind == "genre" then
    return (t.genre and t.genre ~= "") and t.genre or L.UNKNOWN_GENRE
  end
  if t.album and t.album ~= "" then return t.album end
  return (t.folder or ""):match("([^/\\]+)$") or L.UNKNOWN_ALBUM
end

function ns.GroupPlaylistName(kind, t)
  return GROUP_PREFIX[kind] .. ns.GroupKey(kind, t)
end

-- "album" | "artist" | "genre" and the group key, if name is a group playlist.
function ns.GroupKind(name)
  if type(name) ~= "string" or name:sub(1, 2) ~= "__" then return nil end
  for kind, prefix in pairs(GROUP_PREFIX) do
    if name:sub(1, #prefix) == prefix then return kind, name:sub(#prefix + 1) end
  end
end

-- The albums or artists of a track list (podcasts excluded):
-- { kind, key, name (its playlist), label, artist, various, count, cover, _search }, sorted by label.
function ns.Groups(tracks, kind)
  local byKey, out = {}, {}
  for _, t in ipairs(tracks) do
    if not t.parts then
      local key = ns.GroupKey(kind, t)
      local g = byKey[key]
      if not g then
        g = { kind = kind, key = key, name = GROUP_PREFIX[kind] .. key, label = ns.GroupLabel(kind, t),
              count = 0, artist = t.artist }
        byKey[key] = g
        out[#out + 1] = g
      end
      g.count = g.count + 1
      if not g.cover then g.cover = ns.CoverOf(t) end
      if kind == "album" and g.artist ~= t.artist then g.various = true end
    end
  end
  for _, g in ipairs(out) do g._search = (g.label .. " " .. (g.artist or "")):lower() end
  table.sort(out, function(a, b) return a.label:lower() < b.label:lower() end)
  return out
end

function ns.IsConditionEnabled(key)
  return not ns.db.disabled[key]
end

function ns.SetConditionEnabled(key, on)
  if not ns.SITUATION_BY_KEY[key] then return end
  ns.db.disabled[key] = (not on) or nil
  ns.Fire("PLAYLISTS_CHANGED")
  ns.Rules:Evaluate(true)
end

---------------------------------------------------------------------------
-- Zone music: playlists assigned to map IDs (language independent).
---------------------------------------------------------------------------
-- Chain of map IDs for the player's position: the best map, then its parents up to the continent.
-- Cached: it only changes with the zone (refreshed on zone events, or every 10s as a fallback).
local cachedChain, chainTime = nil, 0
local function invalidateZone() cachedChain = nil end
for _, ev in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
  ns.RegisterEvent(ev, invalidateZone)
end
local function mapChain()
  if cachedChain and GetTime() - chainTime < 10 then return cachedChain end
  local chain = {}
  local id = C_Map and ns.Safe(C_Map.GetBestMapForUnit, "player")
  local guard = 0
  while type(id) == "number" and id > 0 and guard < 8 do
    table.insert(chain, id)
    local info = ns.Safe(C_Map.GetMapInfo, id)
    if type(info) ~= "table" then break end
    id = info.parentMapID
    guard = guard + 1
  end
  cachedChain, chainTime = chain, GetTime()
  return chain
end

-- The zone-level map of the current position: { id, name } (or nil). Cached with the chain.
local zoneFor, cachedZone
function ns.CurrentZone()
  local chain = mapChain()
  if zoneFor == chain then return cachedZone end
  zoneFor, cachedZone = chain, ns.ComputeZone(chain)
  return cachedZone
end

function ns.ComputeZone(chain)
  if #chain == 0 then return nil end
  local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
  for _, id in ipairs(chain) do
    local info = ns.Safe(C_Map.GetMapInfo, id)
    if type(info) == "table" and info.mapType == zoneType then return { id = id, name = info.name } end
  end
  local info = ns.Safe(C_Map.GetMapInfo, chain[1])
  return { id = chain[1], name = type(info) == "table" and info.name or tostring(chain[1]) }
end

-- Playlist of the current zone. Only the zone-level map counts: its micro maps (caves, floors)
-- inherit it, but a city that is a zone of its own (Orgrimmar inside Durotar) does not.
function ns.ZonePlaylist()
  local zone = ns.CurrentZone()
  local z = zone and ns.db.zones[zone.id]
  return z and z.playlist or nil
end

function ns.AssignZone(name)
  local zone = ns.CurrentZone()
  if not zone then return end
  ns.db.zones[zone.id] = name and { playlist = name, name = zone.name } or nil
end

function ns.ZoneCount()
  local n = 0
  for _ in pairs(ns.db.zones) do n = n + 1 end
  return n
end

-- Playlist assigned to a condition (nil = none, empty, or condition disabled).
function ns.PlaylistFor(key)
  if ns.db.disabled[key] then return nil end
  local name
  if key == "zone" then
    name = ns.ZonePlaylist()
  elseif key == "boss" or key == "dungeon" then
    -- a playlist for this specific boss / dungeon wins over the generic one
    local id = key == "boss" and ns.Rules.encounterID or (key == "dungeon" and ns.Rules.dungeonID)
    local specific = id and (key == "boss" and ns.db.bosses or ns.db.dungeons)[id]
    name = (specific and ns.IsPlayable(specific.playlist)) and specific.playlist or ns.db.assign[key]
  else
    name = ns.db.assign[key]
  end
  if name and ns.IsPlayable(name) then return name end
  return nil
end

-- Playlist shown in a condition's dropdown (for "zone": the current zone's playlist).
function ns.AssignedTo(key)
  if key == "zone" then return ns.ZonePlaylist() end
  return ns.db.assign[key]
end

-- Boss-specific music: encounterID -> { playlist, name }.
function ns.AssignBoss(id, playlist)
  ns.db.bosses[id] = playlist and { playlist = playlist, name = ns.db.seenBosses[id] } or nil
  ns.Fire("PLAYLISTS_CHANGED")
  ns.Rules:Evaluate(true)
end

-- Dungeon-specific music: instanceID -> { playlist, name }.
function ns.AssignDungeon(id, playlist)
  ns.db.dungeons[id] = playlist and { playlist = playlist, name = ns.db.seenDungeons[id] } or nil
  ns.Fire("PLAYLISTS_CHANGED")
  ns.Rules:Evaluate(true)
end

-- Volume of a condition, as a multiplier of the user's volume (default 1 = 100%).
function ns.ConditionVolume(key)
  return ns.db.volumes[key] or 1
end

function ns.SetConditionVolume(key, mult)
  ns.db.volumes[key] = (mult and mult < 1) and mult or nil
  if ns.db.mode == "auto" and ns.Rules.current == key then ns.Player:SetConditionVolume(ns.ConditionVolume(key)) end
  ns.Fire("PLAYLISTS_CHANGED")
end

---------------------------------------------------------------------------
-- Favourites, exclusions, history and listening statistics
---------------------------------------------------------------------------
local dynamicCache = { [ns.FAV] = true, [ns.HISTORY] = true, [ns.TOP] = true }

-- History and "most played" change with every track: they are recomputed when looked at,
-- but never while they are the playing queue (it would reshuffle under the player's feet).
function ns.InvalidateDynamic()
  for name in pairs(dynamicCache) do
    if ns.Player.playlist ~= name then cache[name] = nil end
  end
  for name in pairs(ns.db.smartPlaylists) do
    if ns.Player.playlist ~= name then cache[name] = nil end
  end
end

function ns.IsFavorite(t) return t and ns.db.favorites[t.file] == true end
function ns.IsExcluded(t) return t and ns.db.excluded[t.file] == true end

function ns.ToggleFavorite(t)
  if not t then return end
  ns.db.favorites[t.file] = (not ns.db.favorites[t.file]) or nil
  invalidate(ns.FAV)
end

function ns.SetExcluded(t, on)
  if not t then return end
  ns.db.excluded[t.file] = on or nil
  ns.Fire("PLAYLISTS_CHANGED")
end

-- Called by the player when a track starts (new) and/or stops (prev, with the seconds played).
local lastRecorded
function ns.RecordPlay(prev, new, seconds)
  if prev and (seconds or 0) > 0 then
    local st = ns.db.stats[prev.file] or { plays = 0, seconds = 0 }
    st.seconds = (st.seconds or 0) + seconds
    -- listened to the end: forgive one old skip
    local dur = tonumber(prev.duration) or 0
    if st.skips and dur > 0 and seconds >= dur * 0.9 then st.skips = st.skips > 1 and st.skips - 1 or nil end
    ns.db.stats[prev.file] = st
    ns.db.totalSeconds = (ns.db.totalSeconds or 0) + seconds
  end
  if new and new ~= lastRecorded then -- podcast parts of the same episode count once
    lastRecorded = new
    local st = ns.db.stats[new.file] or { plays = 0, seconds = 0 }
    st.plays = (st.plays or 0) + 1
    ns.db.stats[new.file] = st
    local h = ns.db.history
    for i = #h, 1, -1 do if h[i] == new.file then table.remove(h, i) end end
    table.insert(h, 1, new.file)
    for i = #h, 51, -1 do h[i] = nil end
  end
end

-- The user pressed Next early in a track: it counts as skipped (weighted shuffle).
-- Podcasts move by parts and are not counted.
local SKIP_SECONDS, SKIP_SHARE = 30, 0.3
function ns.RecordSkip(track, elapsed)
  if not track or track.parts or not track.file then return end
  local dur = tonumber(track.duration) or 0
  if dur <= 0 or elapsed >= math.min(SKIP_SECONDS, dur * SKIP_SHARE) then return end
  local st = ns.db.stats[track.file] or { plays = 0, seconds = 0 }
  st.skips = (st.skips or 0) + 1
  ns.db.stats[track.file] = st
end

-- Weighted shuffle: how likely each track is to come early in the queue.
-- Never heard x1.5, each skip divides by 1 + 0.5 x skips, recently played much less.
-- No track is ever left out (excluding is a separate, explicit choice).
local RECENT_STRONG, RECENT_WEAK = 10, 25
function ns.ShuffleWeights(tracks)
  local recent = {}
  for i, id in ipairs(ns.db.history) do
    if i > RECENT_WEAK then break end
    recent[id] = i <= RECENT_STRONG and 0.25 or 0.6
  end
  local w = {}
  for i, t in ipairs(tracks) do
    local st = ns.db.stats[t.file]
    local v = (not st or (st.plays or 0) == 0) and 1.5 or 1
    if st and st.skips then v = v / (1 + 0.5 * st.skips) end
    v = v * (recent[t.file] or 1)
    w[i] = math.max(v, 0.1)
  end
  return w
end

---------------------------------------------------------------------------
-- "Play next" queue: tracks played before the playlist goes on (ids in db.upNext).
---------------------------------------------------------------------------
ns.QUEUE_MAX = 100

-- front = "Play next" (before what is already queued), otherwise "Add to queue".
function ns.QueueTracks(tracks, front)
  local q = ns.db.upNext
  local pos = 1
  for _, t in ipairs(tracks) do
    if t and t.file and #q < ns.QUEUE_MAX then
      if front then table.insert(q, pos, t.file) pos = pos + 1 else table.insert(q, t.file) end
    end
  end
  ns.Fire("QUEUE_CHANGED")
end

-- The queued tracks that are still in the library.
function ns.QueuedTracks()
  local out = {}
  for _, id in ipairs(ns.db.upNext) do
    if ns.trackById[id] then out[#out + 1] = ns.trackById[id] end
  end
  return out
end

function ns.UnqueueTrack(t)
  local q = ns.db.upNext
  for i = 1, #q do
    if q[i] == t.file then table.remove(q, i) ns.Fire("QUEUE_CHANGED") return end
  end
end

function ns.ClearQueue()
  wipe(ns.db.upNext)
  ns.Fire("QUEUE_CHANGED")
end

-- Takes the first queued track (dropping ids no longer in the library).
function ns.PopQueue()
  local q = ns.db.upNext
  while #q > 0 do
    local t = ns.trackById[table.remove(q, 1)]
    if t then ns.Fire("QUEUE_CHANGED") return t end
  end
end

function ns.FormatDuration(sec)
  sec = math.floor(sec or 0)
  local h, m = math.floor(sec / 3600), math.floor(sec % 3600 / 60)
  return h > 0 and ("%dh %02dm"):format(h, m) or ("%dm"):format(m)
end

function ns.Assign(key, name)
  if not ns.SITUATION_BY_KEY[key] then return end
  if key == "zone" then ns.AssignZone(name) else ns.db.assign[key] = name end
  ns.Fire("PLAYLISTS_CHANGED")
  ns.Rules:Evaluate(true)
end

---------------------------------------------------------------------------
-- Profiles (per character): condition settings; playlists stay shared.
---------------------------------------------------------------------------
ns.DEFAULT_PROFILE = "Default"

function ns.CharacterKey()
  local name = UnitName and ns.Safe(UnitName, "player")
  local realm = GetRealmName and ns.Safe(GetRealmName)
  if type(name) ~= "string" or name == "" then return nil end
  return name .. "-" .. (type(realm) == "string" and realm or "")
end

local function ensureProfile(name)
  local prof = ns.db.profiles[name]
  if type(prof) ~= "table" then prof = {} ns.db.profiles[name] = prof end
  prof.assign = type(prof.assign) == "table" and prof.assign or {}
  prof.disabled = type(prof.disabled) == "table" and prof.disabled or {}
  prof.zones = type(prof.zones) == "table" and prof.zones or {}
  prof.bosses = type(prof.bosses) == "table" and prof.bosses or {}
  prof.dungeons = type(prof.dungeons) == "table" and prof.dungeons or {}
  prof.volumes = type(prof.volumes) == "table" and prof.volumes or {}
  return prof
end

function ns.ActivateProfile(name)
  if not ns.db.profiles[name] then name = ns.DEFAULT_PROFILE end
  local prof = ensureProfile(name)
  ns.profileName = name
  ns.db.assign, ns.db.disabled, ns.db.zones = prof.assign, prof.disabled, prof.zones
  ns.db.bosses, ns.db.volumes, ns.db.dungeons = prof.bosses, prof.volumes, prof.dungeons
  ns.Fire("PLAYLISTS_CHANGED")
  if ns.Rules.started then ns.Rules:Evaluate(true) end
end

function ns.ProfileNames()
  local names = {}
  for name in pairs(ns.db.profiles) do names[#names + 1] = name end
  table.sort(names, function(a, b)
    if a == ns.DEFAULT_PROFILE then return true elseif b == ns.DEFAULT_PROFILE then return false end
    return a:lower() < b:lower()
  end)
  return names
end

-- Uses profile `name` for the current character.
function ns.SetCharacterProfile(name)
  local char = ns.CharacterKey()
  if char then ns.db.charProfiles[char] = (name ~= ns.DEFAULT_PROFILE) and name or nil end
  ns.ActivateProfile(name)
  ns.Print("MSG_PROFILE_SET", name == ns.DEFAULT_PROFILE and CL.PROFILE_DEFAULT or name)
end

-- Creates a profile named after the character, copying the current settings, and switches to it.
function ns.NewCharacterProfile()
  local char = ns.CharacterKey() or "Character"
  local src = ensureProfile(ns.profileName or ns.DEFAULT_PROFILE)
  local copy = { assign = {}, disabled = {}, zones = {}, bosses = {}, volumes = {}, dungeons = {} }
  for k, v in pairs(src.assign) do copy.assign[k] = v end
  for k, v in pairs(src.disabled) do copy.disabled[k] = v end
  for k, v in pairs(src.zones) do copy.zones[k] = { playlist = v.playlist, name = v.name } end
  for k, v in pairs(src.bosses) do copy.bosses[k] = { playlist = v.playlist, name = v.name } end
  for k, v in pairs(src.dungeons) do copy.dungeons[k] = { playlist = v.playlist, name = v.name } end
  for k, v in pairs(src.volumes) do copy.volumes[k] = v end
  ns.db.profiles[char] = copy
  ns.SetCharacterProfile(char)
end

function ns.DeleteProfile(name)
  if name == ns.DEFAULT_PROFILE or not ns.db.profiles[name] then return end
  ns.db.profiles[name] = nil
  for char, p in pairs(ns.db.charProfiles) do
    if p == name then ns.db.charProfiles[char] = nil end
  end
  if ns.profileName == name then ns.ActivateProfile(ns.DEFAULT_PROFILE) end
end

---------------------------------------------------------------------------
-- Sharing playlists as text (base64 of "name\nid\nid...")
---------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64encode(data)
  local out = {}
  for i = 1, #data, 3 do
    local a, b, c = data:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local s = ""
    for j = 3, 0, -1 do
      local idx = math.floor(n / 64 ^ j) % 64 + 1
      s = s .. B64:sub(idx, idx)
    end
    if not b then s = s:sub(1, 2) .. "==" elseif not c then s = s:sub(1, 3) .. "=" end
    out[#out + 1] = s
  end
  return table.concat(out)
end
local function b64decode(data)
  data = data:gsub("[^%w%+/=]", "")
  local out = {}
  for i = 1, #data, 4 do
    local chunk = data:sub(i, i + 3)
    local n, pad = 0, 0
    for j = 1, 4 do
      local ch = chunk:sub(j, j)
      local v
      if ch == "=" or ch == "" then v = 0 pad = pad + 1 else v = (B64:find(ch, 1, true) or 1) - 1 end
      n = n * 64 + v
    end
    local bytes = string.char(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
    out[#out + 1] = bytes:sub(1, 3 - pad)
  end
  return table.concat(out)
end
ns.Base64Encode, ns.Base64Decode = b64encode, b64decode

local SHARE_PREFIX = "!KZZR1!"

function ns.ExportPlaylist(name)
  local ids = ns.db.playlists[name]
  if type(ids) ~= "table" then return nil end
  return SHARE_PREFIX .. b64encode(name .. "\n" .. table.concat(ids, "\n"))
end

-- Returns the new playlist name, the number of tracks found and the total, or nil + error key.
function ns.ImportPlaylist(text)
  text = (text or ""):gsub("%s", "")
  if text:sub(1, #SHARE_PREFIX) ~= SHARE_PREFIX then return nil, "MSG_IMPORT_BAD" end
  local ok, raw = pcall(b64decode, text:sub(#SHARE_PREFIX + 1))
  if not ok or not raw or raw == "" then return nil, "MSG_IMPORT_BAD" end
  local lines = {}
  for line in (raw .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
  local base = lines[1] ~= "" and lines[1] or "Imported"
  local name, n = base, 2
  while ns.FindPlaylist(name) do name = ("%s (%d)"):format(base, n) n = n + 1 end
  local created = ns.CreatePlaylist(name)
  if not created then return nil, "MSG_IMPORT_BAD" end
  local found = {}
  for i = 2, #lines do
    if ns.trackById[lines[i]] then found[#found + 1] = lines[i] end
  end
  ns.SetManyInPlaylist(created, found, true)
  return created, #found, #lines - 1
end

---------------------------------------------------------------------------
-- Mode: "auto" (conditions) or free play of a playlist
---------------------------------------------------------------------------
function ns.SetMode(mode)
  if mode ~= "auto" and not ns.GetPlaylist(mode) then return false end
  ns.db.mode = mode
  ns.Player.userStopped = false
  ns.Rules:Reset()
  if mode == "auto" then
    ns.Rules:Evaluate(true)
  else
    ns.Player:SetConditionVolume(1) -- free play: the user's own volume
    ns.Player:SetPlaylist(mode)
  end
  ns.Fire("MODE_CHANGED", mode)
  return true
end

-- Free play starting from a specific track.
function ns.PlayFrom(name, track)
  if not ns.GetPlaylist(name) then return end
  ns.db.mode = name
  ns.Rules:Reset()
  ns.Player:SetConditionVolume(1)
  ns.Player:PlayTrack(name, track)
  ns.Fire("MODE_CHANGED", name)
end

function ns.SetEnabled(on)
  ns.db.enabled = on and true or false
  if on then
    ns.SetMode(ns.db.mode)
  else
    ns.Player:Stop()
  end
  ns.Fire("STATE_CHANGED")
end

-- Saves the chosen language (nil = automatic). Needs /reload to apply.
function ns.SetLanguage(code)
  if code ~= nil and not ns.LOCALES[code] then return false end
  ns.db.lang = code
  local name = code and ns.LANGUAGE_NAMES[code] or "auto"
  if code and ns.CJK_LANG[code] then name = code end -- CJK characters may not render in chat
  ns.Print("MSG_LANG_SET", name)
  return true
end

---------------------------------------------------------------------------
-- Initialization
---------------------------------------------------------------------------
local function copyDefaults(dst, src)
  for k, v in pairs(src) do
    if dst[k] == nil then
      dst[k] = type(v) == "table" and copyDefaults({}, v) or v
    elseif type(v) == "table" and type(dst[k]) == "table" then
      copyDefaults(dst[k], v)
    end
  end
  return dst
end

-- Internal state for diagnosis (/kzz debug); also saved to KZZR_DB.lastDebug.
function ns.DebugLines()
  local function s(v) return tostring(v) end
  local lines = {
    ("ZugZug Radio debug: version %s, build %s, language %s (client %s), addon font %s"):format(
      s(C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")),
      s((select(2, GetBuildInfo()))), s(ns.lang), s(GetLocale and GetLocale()), s(ns.useAddonFont)),
    ("  library: %s, tracks in Library.lua: %s, tracks loaded: %d, game music: %d, playlists: %d, mode: %s"):format(
      s(ns.LIB_ROOT), s(ns.library and ns.library.tracks and #ns.library.tracks),
      #ns.tracks, #ns.gameTracks, ns.db and #ns.PlaylistNames() or -1, s(ns.db and ns.db.mode)),
    ("  frames: player %s, library %s, settings %s, minimap button %s, minimap button visible %s"):format(
      s(_G.KalimdorZugZugRadioFrame ~= nil), s(_G.KalimdorZugZugLibraryFrame ~= nil),
      s(_G.KalimdorZugZugSettingsPanel ~= nil), s(_G.KalimdorZugZugRadioMinimapButton ~= nil),
      s(_G.KalimdorZugZugRadioMinimapButton and _G.KalimdorZugZugRadioMinimapButton:IsVisible())),
    ("  Settings API: %s, category registered: %s, Minimap: %s"):format(
      s(Settings ~= nil and Settings.RegisterCanvasLayoutCategory ~= nil), s(ns.Settings and ns.Settings:HasCategory()),
      s(Minimap ~= nil)),
    ("  conditions: current %s, zone %s, dungeon %s (%s), encounter %s, last boss %s"):format(
      s(ns.Rules.current), s(ns.CurrentZone() and ns.CurrentZone().id), s(ns.Rules.dungeonID),
      s(ns.Rules.dungeonID and ns.db.seenDungeons[ns.Rules.dungeonID]), s(ns.Rules.encounterID), s(ns.Rules.lastBossID)),
    "  rules: " .. (ns.Rules.DebugState and ns.Rules:DebugState() or "?"),
    "  player: " .. (ns.Player.DebugState and ns.Player:DebugState() or "?"),
  }
  local ok, mm = pcall(ns.Minimap.DebugInfo, ns.Minimap)
  table.insert(lines, "  minimap: " .. (ok and mm or ("error: " .. tostring(mm))))
  if #ns.startupErrors == 0 then table.insert(lines, "  no startup errors") end
  for _, e in ipairs(ns.startupErrors) do table.insert(lines, "|cffff4040  " .. e .. "|r") end
  return lines
end

-- Each startup step is isolated: an error doesn't block the others and is shown in chat
-- (WoW hides Lua errors by default).
ns.startupErrors = {}
local function step(label, fn)
  local ok, err = xpcall(fn, function(e) return tostring(e) .. "\n" .. (debugstack and debugstack(2, 6, 0) or "") end)
  if not ok then
    table.insert(ns.startupErrors, label .. ": " .. err)
    print("|cffff4040ZugZug Radio - error in " .. label .. "|r: " .. err)
  end
end

ns.RegisterEvent("ADDON_LOADED", function(name)
  if name ~= ADDON then return end
  ns.perfSince = GetTime()
  KZZR_DB = copyDefaults(KZZR_DB or {}, DEFAULTS)
  ns.db = KZZR_DB
  ns.db.startupErrors = ns.startupErrors -- written to disk on /reload or logout, for diagnosis
  -- migration (<= 0.4): assignments lived directly in the DB; they become the Default profile
  if not ns.db.profiles[ns.DEFAULT_PROFILE] then
    ns.db.profiles[ns.DEFAULT_PROFILE] = { assign = ns.db.assign or {}, disabled = ns.db.disabled or {}, zones = {} }
  end
  ns.ActivateProfile(ns.DEFAULT_PROFILE) -- the character's profile is activated at PLAYER_LOGIN
  ns.Player:InitVolume() -- also recovers from a fade/duck interrupted by a /reload
  step("InitLanguage", function() ns.InitLanguage(ns.db.lang) end)
  step("Bindings", function() ns.SetupBindings() end)
  step("LoadLibrary", ns.LoadLibrary)
  if ns.db.mode ~= "auto" and not ns.GetPlaylist(ns.db.mode) then ns.db.mode = "auto" end
end)

-- The active profile's tables are only aliases: don't write them twice to SavedVariables.
ns.RegisterEvent("PLAYER_LOGOUT", function()
  pcall(function() ns.db.lastPerf = ns.PerfReport() end)
  ns.Player:RestoreVolume()
  ns.db.assign, ns.db.disabled, ns.db.zones, ns.db.bosses, ns.db.volumes, ns.db.dungeons = nil, nil, nil, nil, nil, nil
end)

ns.RegisterEvent("PLAYER_LOGIN", function()
  step("Profile", function()
    local char = ns.CharacterKey()
    ns.ActivateProfile(char and ns.db.charProfiles[char] or ns.DEFAULT_PROFILE)
  end)
  step("UI", function() ns.UI:Build() end)
  step("LibraryUI", function() ns.LibraryUI:Build() end)
  step("Settings", function() ns.Settings:Build() end)
  step("Minimap", function() ns.Minimap:Build() end)
  step("Banner", function() ns.Banner:Build() end)
  step("Rules", function() ns.Rules:Start() end)
  -- startup state in its own field, so a /kzz debug taken before a /reload isn't overwritten
  step("Debug", function() ns.db.startupDebug = ns.DebugLines() end)
  if #ns.tracks == 0 and #ns.episodes == 0 then
    ns.Print("MSG_EMPTY_LIBRARY")
  elseif next(ns.db.playlists) == nil then
    ns.Print("MSG_NO_PLAYLISTS", #ns.tracks)
  end
  local getCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
  if getCVar and getCVar("Sound_EnableMusic") == "0" then
    ns.Print("MSG_MUSIC_DISABLED")
  end
end)

---------------------------------------------------------------------------
-- Key bindings (Bindings.xml) - names shown in the game's Key Bindings menu
---------------------------------------------------------------------------
local BINDINGS = {
  KZZR_PLAY = "BIND_PLAY", KZZR_NEXT = "BIND_NEXT", KZZR_PREV = "BIND_PREV", KZZR_SKIP = "BIND_SKIP",
  KZZR_VOLUP = "BIND_VOLUP", KZZR_VOLDOWN = "BIND_VOLDOWN", KZZR_PLAYER = "BIND_PLAYER",
  KZZR_LIBRARY = "BIND_LIBRARY", KZZR_FAVORITE = "BIND_FAVORITE",
}
function ns.SetupBindings()
  _G.BINDING_HEADER_KZZR = "Kalimdor ZugZug Radio"
  for binding, key in pairs(BINDINGS) do _G["BINDING_NAME_" .. binding] = L[key] end
end

function KZZR_Binding(action)
  local P = ns.Player
  if action == "play" then P:Toggle()
  elseif action == "next" then P:Next()
  elseif action == "prev" then P:Prev()
  elseif action == "skip" then P:SkipTrack(1)
  elseif action == "volup" then P:SetVolume(P:GetVolume() + 0.1)
  elseif action == "voldown" then P:SetVolume(P:GetVolume() - 0.1)
  elseif action == "player" then ns.UI:Toggle()
  elseif action == "library" then ns.LibraryUI:Toggle()
  elseif action == "favorite" then ns.ToggleFavorite(P.track)
  end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function printStatus()
  ns.Print("STATUS_LINE", ns.db.mode == "auto" and CL.MODE_CONDITIONS or ns.PlaylistLabel(ns.db.mode, true),
    ns.db.enabled and CL.RADIO_ENABLED or CL.RADIO_DISABLED, ns.db.shuffle and CL.ON or CL.OFF)
  local active = ns.Rules:ActiveSet()
  for _, s in ipairs(ns.SITUATIONS) do
    local assigned = ns.AssignedTo(s.key)
    print(("   %s%s|r -> %s"):format(active[s.key] and "|cff40ff40" or "|cff808080", ns.SituationLabel(s.key, true),
      assigned and (ns.PlaylistLabel(assigned, true) .. (ns.IsPlayable(assigned) and "" or CL.EMPTY_SUFFIX)) or "-"))
  end
  ns.Print("STATUS_COUNTS", #ns.tracks, #ns.PlaylistNames())
end

local function languageCommand(arg)
  arg = (arg or ""):lower()
  if arg == "auto" then ns.SetLanguage(nil) return end
  for _, code in ipairs(ns.LANG_ORDER) do
    if code:lower() == arg or code:sub(1, 2):lower() == arg then -- "es" = esES, "zh" = zhCN
      ns.SetLanguage(code)
      return
    end
  end
  ns.Print("MSG_LANG_LIST", table.concat(ns.LANG_ORDER, ", "))
end

SLASH_KZZRADIO1, SLASH_KZZRADIO2 = "/kzz", "/zugzug"
SlashCmdList.KZZRADIO = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  local P = ns.Player
  if cmd == "" or cmd == "show" then ns.UI:Toggle()
  elseif cmd == "lib" or cmd == "library" then ns.LibraryUI:Toggle()
  elseif cmd == "play" then P:Toggle(true)
  elseif cmd == "stop" then P:Stop(true)
  elseif cmd == "next" then P:Next()
  elseif cmd == "prev" then P:Prev()
  elseif cmd == "shuffle" then P:SetShuffle(not ns.db.shuffle); ns.Print("MSG_SHUFFLE", ns.db.shuffle and CL.ON or CL.OFF)
  elseif cmd == "on" then ns.SetEnabled(true)
  elseif cmd == "off" then ns.SetEnabled(false)
  elseif cmd == "auto" then ns.SetMode("auto")
  elseif cmd == "playlist" then
    local found = ns.FindPlaylist(rest)
    if not found or not ns.SetMode(found) then ns.Print("MSG_PLAYLIST_NOT_FOUND", rest) end
  elseif cmd == "status" then printStatus()
  elseif cmd == "lock" then
    ns.db.ui.locked = not ns.db.ui.locked
    ns.Print(ns.db.ui.locked and "MSG_PLAYER_LOCKED" or "MSG_PLAYER_UNLOCKED")
  elseif cmd == "reset" then ns.UI:ResetPosition()
  elseif cmd == "minimap" then ns.Minimap:Toggle()
  elseif cmd == "lang" or cmd == "language" then languageCommand(rest)
  elseif cmd == "config" or cmd == "settings" or cmd == "options" then ns.Settings:Open()
  elseif cmd == "tutorial" or cmd == "guide" or cmd == "welcome" then ns.Onboarding:Show()
  elseif cmd == "stats" then
    local played = 0
    for _, st in pairs(ns.db.stats) do played = played + (st.plays or 0) end
    ns.Print("MSG_STATS", ns.FormatDuration(ns.db.totalSeconds), played)
    local top = ns.GetPlaylist(ns.TOP)
    for i = 1, math.min(5, top and #top.tracks or 0) do
      local t = top.tracks[i]
      print(("   %d. %s  (%s)"):format(i, ns.TrackLabel(t), CL.PLAYS_FMT:format(ns.db.stats[t.file].plays)))
    end
  elseif cmd == "perf" then
    if rest == "reset" then wipe(ns.perf) ns.perfSince = GetTime() end
    ns.db.lastPerf = ns.PerfReport()
    for _, line in ipairs(ns.db.lastPerf) do print(line) end
  elseif cmd == "debug" then
    ns.db.lastDebug = ns.DebugLines()
    table.insert(ns.db.lastDebug, 1, "taken at " .. (date and date("%Y-%m-%d %H:%M:%S") or "?"))
    for _, line in ipairs(ns.db.lastDebug) do print(line) end
    print("  (saved: /reload to write it to SavedVariables\\KalimdorZugZugRadio.lua)")
  else
    for i = 1, 13 do ns.Print("HELP_" .. i) end
  end
end
