-- Core: namespace, SavedVariables, libreria, playlist dell'utente, bus di eventi, comandi slash.
local ADDON, ns = ...
local L, CL = ns.L, ns.CL

ns.ADDON = ADDON
ns.ROOT = "Interface\\AddOns\\" .. ADDON .. "\\"
ns.ALL = "__all" -- playlist virtuale con tutta la libreria

-- Condizioni in ordine di priorità: vince la prima attiva che ha una playlist assegnata.
-- "idle" è sempre attiva: è la musica quando non c'è nessun'altra condizione.
ns.SITUATIONS = {
  { key = "boss" }, { key = "elite" }, { key = "combat" }, { key = "flight" },
  { key = "campfire" }, { key = "dungeon" }, { key = "town" }, { key = "idle" },
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
  mode = "auto",   -- "auto" (condizioni) oppure il nome di una playlist (riproduzione libera)
  shuffle = true,
  playlists = {},  -- nome -> { file, file, ... } (file = id del brano in Library.lua)
  assign = {},     -- condizione -> nome playlist
  disabled = {},   -- condizione -> true se disattivata nelle impostazioni
  lang = nil,      -- nil = lingua del client
  ui = { shown = true, locked = false },
  minimap = { angle = 225, hide = false },
}

---------------------------------------------------------------------------
-- Utilità
---------------------------------------------------------------------------
-- Messaggio in chat. key è una chiave di traduzione (testi in ns.CL).
function ns.Print(key, ...)
  local msg = CL[key]
  if select("#", ...) > 0 then msg = msg:format(...) end
  print("|cffff7f00ZugZug Radio|r: " .. msg)
end

-- true se v è un "secret value" di Midnight (non confrontabile né usabile).
function ns.IsSecret(v)
  if issecretvalue then
    local ok, secret = pcall(issecretvalue, v)
    return ok and secret == true
  end
  return false
end

-- Chiama fn protetta; restituisce il primo valore solo se non è secret.
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

-- Tooltip dell'addon (separato da GameTooltip per poter cambiare font senza toccare quello di Blizzard).
-- lines = { "testo" | { "testo", r, g, b } , ... }; la prima riga è il titolo.
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
      local fo = ns.FontObject(template, ns.HasCJK(fs:GetText()))
      if fo then fs:SetFontObject(fo) end
    end
  end
  tip:Show()
end
function ns.HideTooltip()
  if tip then tip:Hide() end
end

---------------------------------------------------------------------------
-- Bus di eventi interno
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

-- Eventi di gioco: più moduli possono registrare lo stesso evento.
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
-- Libreria (generata da tools/import_music.py in Library.lua)
---------------------------------------------------------------------------
ns.tracks, ns.trackById = {}, {}

function ns.LoadLibrary()
  wipe(ns.tracks); wipe(ns.trackById)
  for _, t in ipairs((KZZR_Library and KZZR_Library.tracks) or {}) do
    if type(t.file) == "string" and not ns.trackById[t.file] then
      t.title = (t.title and t.title ~= "") and t.title or t.file:match("([^\\]+)%.%w+$") or t.file
      t.folder = t.folder or ""
      t._search = (t.title .. " " .. (t.artist or "") .. " " .. (t.album or "") .. " " .. t.folder):lower()
      table.insert(ns.tracks, t)
      ns.trackById[t.file] = t
    end
  end
  table.sort(ns.tracks, function(a, b)
    if a.folder ~= b.folder then return a.folder < b.folder end
    return a.title:lower() < b.title:lower()
  end)
end

---------------------------------------------------------------------------
-- Playlist
---------------------------------------------------------------------------
local cache = {} -- nome -> { name, tracks = {...}, has = { [file] = true } }

local function invalidate(name)
  if name then cache[name] = nil else wipe(cache) end
  ns.Fire("PLAYLISTS_CHANGED", name)
end

function ns.PlaylistLabel(name, chat)
  if name == ns.ALL then return (chat and CL or L).ALL_LIBRARY end
  return name
end

function ns.PlaylistNames()
  local names = {}
  for name in pairs(ns.db.playlists) do names[#names + 1] = name end
  table.sort(names, function(a, b) return a:lower() < b:lower() end)
  return names
end

-- { name, tracks, has } oppure nil se la playlist non esiste.
function ns.GetPlaylist(name)
  if not name then return nil end
  if cache[name] then return cache[name] end
  local pl
  if name == ns.ALL then
    pl = { name = name, tracks = ns.tracks, has = ns.trackById }
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

-- Ricerca case-insensitive per i comandi slash ("all" o la parola tradotta = tutta la libreria).
function ns.FindPlaylist(name)
  if type(name) ~= "string" or name == "" then return nil end
  local lower = name:lower()
  if name == ns.ALL then return ns.ALL end
  for _, loc in pairs(ns.LOCALES) do
    if loc.ALL_KEYWORD and lower == loc.ALL_KEYWORD:lower() then return ns.ALL end
  end
  if ns.db.playlists[name] then return name end
  for n in pairs(ns.db.playlists) do
    if n:lower() == lower then return n end
  end
end

local function cleanName(name)
  name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" or name == ns.ALL then return nil end
  return name
end

-- Le funzioni di modifica restituiscono il nome, oppure nil + chiave di errore traducibile.
function ns.CreatePlaylist(name)
  name = cleanName(name)
  if not name then return nil, "ERR_BAD_NAME" end
  if ns.FindPlaylist(name) then return nil, "ERR_EXISTS" end
  ns.db.playlists[name] = {}
  invalidate(name)
  return name
end

function ns.RenamePlaylist(old, new)
  new = cleanName(new)
  if not new or not ns.db.playlists[old] then return nil, "ERR_BAD_NAME" end
  if new == old then return new end
  local existing = ns.FindPlaylist(new)
  if existing and existing ~= old then return nil, "ERR_EXISTS" end
  ns.db.playlists[new], ns.db.playlists[old] = ns.db.playlists[old], nil
  for key, v in pairs(ns.db.assign) do
    if v == old then ns.db.assign[key] = new end
  end
  if ns.db.mode == old then ns.db.mode = new end
  ns.Player:Rename(old, new)
  cache[old] = nil
  invalidate(new)
  return new
end

function ns.DeletePlaylist(name)
  if not ns.db.playlists[name] then return end
  ns.db.playlists[name] = nil
  for key, v in pairs(ns.db.assign) do
    if v == name then ns.db.assign[key] = nil end
  end
  invalidate(name)
  if ns.db.mode == name then ns.SetMode("auto") else ns.Rules:Evaluate(true) end
end

-- Aggiunge/toglie un brano da una playlist dell'utente.
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

-- Versione in blocco (es. "aggiungi tutti i brani visibili").
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

function ns.IsConditionEnabled(key)
  return not ns.db.disabled[key]
end

function ns.SetConditionEnabled(key, on)
  if not ns.SITUATION_BY_KEY[key] then return end
  ns.db.disabled[key] = (not on) or nil
  ns.Fire("PLAYLISTS_CHANGED")
  ns.Rules:Evaluate(true)
end

-- Playlist assegnata a una condizione (nil = nessuna, vuota o condizione disattivata).
function ns.PlaylistFor(key)
  if ns.db.disabled[key] then return nil end
  local name = ns.db.assign[key]
  if name and ns.IsPlayable(name) then return name end
  return nil
end

function ns.Assign(key, name)
  if not ns.SITUATION_BY_KEY[key] then return end
  ns.db.assign[key] = name
  ns.Fire("PLAYLISTS_CHANGED")
  ns.Rules:Evaluate(true)
end

---------------------------------------------------------------------------
-- Modalità: "auto" (condizioni) o riproduzione libera di una playlist
---------------------------------------------------------------------------
function ns.SetMode(mode)
  if mode ~= "auto" and not ns.GetPlaylist(mode) then return false end
  ns.db.mode = mode
  ns.Player.userStopped = false
  ns.Rules:Reset()
  if mode == "auto" then
    ns.Rules:Evaluate(true)
  else
    ns.Player:SetPlaylist(mode)
  end
  ns.Fire("MODE_CHANGED", mode)
  return true
end

-- Riproduzione libera a partire da un brano preciso.
function ns.PlayFrom(name, track)
  if not ns.GetPlaylist(name) then return end
  ns.db.mode = name
  ns.Rules:Reset()
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

-- Salva la lingua scelta (nil = automatica). Serve /reload per applicarla.
function ns.SetLanguage(code)
  if code ~= nil and not ns.LOCALES[code] then return false end
  ns.db.lang = code
  local name = code and ns.LANGUAGE_NAMES[code] or "auto"
  if code and ns.CJK_LANG[code] then name = code end -- in chat i caratteri CJK potrebbero non vedersi
  ns.Print("MSG_LANG_SET", name)
  return true
end

---------------------------------------------------------------------------
-- Inizializzazione
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

-- Stato interno per la diagnosi (/kzz debug); viene anche salvato in KZZR_DB.lastDebug.
function ns.DebugLines()
  local function s(v) return tostring(v) end
  local lines = {
    ("ZugZug Radio debug: versione %s, build %s, lingua %s (client %s), font addon %s"):format(
      s(C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")),
      s((select(2, GetBuildInfo()))), s(ns.lang), s(GetLocale and GetLocale()), s(ns.useAddonFont)),
    ("  KZZR_Library: %s, brani in Library.lua: %s, brani caricati: %d, playlist: %d"):format(
      s(KZZR_Library ~= nil), s(KZZR_Library and KZZR_Library.tracks and #KZZR_Library.tracks),
      #ns.tracks, ns.db and #ns.PlaylistNames() or -1),
    ("  finestre: player %s, libreria %s, impostazioni %s, minimappa %s, minimappa visibile %s"):format(
      s(_G.KalimdorZugZugRadioFrame ~= nil), s(_G.KalimdorZugZugLibraryFrame ~= nil),
      s(_G.KalimdorZugZugSettingsPanel ~= nil), s(_G.KalimdorZugZugRadioMinimapButton ~= nil),
      s(_G.KalimdorZugZugRadioMinimapButton and _G.KalimdorZugZugRadioMinimapButton:IsVisible())),
    ("  Settings API: %s, categoria registrata: %s, Minimap: %s"):format(
      s(Settings ~= nil and Settings.RegisterCanvasLayoutCategory ~= nil), s(ns.Settings and ns.Settings:HasCategory()),
      s(Minimap ~= nil)),
  }
  local ok, mm = pcall(ns.Minimap.DebugInfo, ns.Minimap)
  table.insert(lines, "  minimappa: " .. (ok and mm or ("errore: " .. tostring(mm))))
  if #ns.startupErrors == 0 then table.insert(lines, "  nessun errore all'avvio") end
  for _, e in ipairs(ns.startupErrors) do table.insert(lines, "|cffff4040  " .. e .. "|r") end
  return lines
end

-- Ogni fase dell'avvio è isolata: un errore non blocca le altre e viene mostrato in chat
-- (WoW di default nasconde gli errori Lua).
ns.startupErrors = {}
local function step(label, fn)
  local ok, err = xpcall(fn, function(e) return tostring(e) .. "\n" .. (debugstack and debugstack(2, 6, 0) or "") end)
  if not ok then
    table.insert(ns.startupErrors, label .. ": " .. err)
    print("|cffff4040ZugZug Radio - errore in " .. label .. "|r: " .. err)
  end
end

ns.RegisterEvent("ADDON_LOADED", function(name)
  if name ~= ADDON then return end
  KZZR_DB = copyDefaults(KZZR_DB or {}, DEFAULTS)
  ns.db = KZZR_DB
  ns.db.startupErrors = ns.startupErrors -- salvato su disco al /reload o logout, per la diagnosi
  step("InitLanguage", function() ns.InitLanguage(ns.db.lang) end)
  step("LoadLibrary", ns.LoadLibrary)
  if ns.db.mode ~= "auto" and not ns.GetPlaylist(ns.db.mode) then ns.db.mode = "auto" end
end)

ns.RegisterEvent("PLAYER_LOGIN", function()
  step("UI", function() ns.UI:Build() end)
  step("LibraryUI", function() ns.LibraryUI:Build() end)
  step("Settings", function() ns.Settings:Build() end)
  step("Minimap", function() ns.Minimap:Build() end)
  step("Rules", function() ns.Rules:Start() end)
  step("Debug", function() ns.db.lastDebug = ns.DebugLines() end)
  if #ns.tracks == 0 then
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
-- Comandi slash
---------------------------------------------------------------------------
local function printStatus()
  ns.Print("STATUS_LINE", ns.db.mode == "auto" and CL.MODE_CONDITIONS or ns.PlaylistLabel(ns.db.mode, true),
    ns.db.enabled and CL.RADIO_ENABLED or CL.RADIO_DISABLED, ns.db.shuffle and CL.ON or CL.OFF)
  local active = ns.Rules:ActiveSet()
  for _, s in ipairs(ns.SITUATIONS) do
    local assigned = ns.db.assign[s.key]
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
  elseif cmd == "debug" then
    ns.db.lastDebug = ns.DebugLines()
    for _, line in ipairs(ns.db.lastDebug) do print(line) end
    print("  (salvato: fai /reload per scriverlo nel file SavedVariables\\KalimdorZugZugRadio.lua)")
  else
    for i = 1, 10 do ns.Print("HELP_" .. i) end
  end
end
