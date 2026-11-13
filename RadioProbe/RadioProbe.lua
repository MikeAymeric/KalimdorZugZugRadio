-- RadioProbe: checks which of the APIs/events Kalimdor ZugZug Radio needs work on the client.
-- Everything is wrapped in pcall: on an unknown client we don't want Lua errors.

local ADDON = ...
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\media\\"

local log = {}
local MAX_LOG = 800

local function safe(v)
  if issecretvalue then
    local ok, secret = pcall(issecretvalue, v)
    if ok and secret then return "<SECRET>" end
  end
  local ok, s = pcall(tostring, v)
  return ok and s or "<tostring error>"
end

local function out(fmt, ...)
  local n = select("#", ...)
  local args = {}
  for i = 1, n do args[i] = safe((select(i, ...))) end
  local ok, msg = pcall(string.format, fmt, unpack(args, 1, n))
  if not ok then msg = fmt end
  print("|cff33ccff[RadioProbe]|r " .. msg)
  local stamp = date and date("%H:%M:%S") or "?"
  log[#log + 1] = stamp .. " " .. msg
  if #log > MAX_LOG then table.remove(log, 1) end
end

local function resolve(path)
  local t = _G
  for part in path:gmatch("[^%.]+") do
    if type(t) ~= "table" then return nil end
    t = t[part]
  end
  return t
end

local function cvar(name)
  local getter = (C_CVar and C_CVar.GetCVar) or GetCVar
  if not getter then return "n/a" end
  local ok, v = pcall(getter, name)
  return ok and v or "<err>"
end

---------------------------------------------------------------------------
-- 1. Available APIs
---------------------------------------------------------------------------
local APIS = {
  -- audio
  "PlaySoundFile", "StopSound", "PlaySound", "PlayMusic", "StopMusic", "SOUNDKIT",
  -- conditions
  "UnitOnTaxi", "IsInInstance", "IsResting", "IsMounted", "IsSwimming", "IsFlying",
  "InCombatLockdown", "UnitAffectingCombat", "UnitClassification", "UnitExists",
  "GetZoneText", "GetSubZoneText", "C_Map.GetBestMapForUnit",
  -- auras
  "C_UnitAuras.GetAuraDataByIndex", "C_UnitAuras.GetPlayerAuraBySpellID", "UnitAura", "AuraUtil.ForEachAura",
  -- Midnight restrictions
  "issecretvalue", "canaccessvalue",
  -- creature family/type (per-species playlists)
  "UnitCreatureFamily", "UnitCreatureType", "UnitGUID", "UnitThreatSituation", "UnitCanAttack",
  -- utilities / UI
  "C_Timer.After", "C_Timer.NewTicker", "GetTime", "MenuUtil.CreateContextMenu",
  "UIDropDownMenu_Initialize", "C_XMLUtil.GetTemplateInfo", "Settings.RegisterCanvasLayoutCategory",
}

local function reportApis()
  local version, build, bdate, toc = GetBuildInfo()
  out("Build: %s (%s) %s  toc=%s  WOW_PROJECT_ID=%s", version, build, bdate, toc, WOW_PROJECT_ID)
  local missing = {}
  for _, name in ipairs(APIS) do
    if resolve(name) == nil then missing[#missing + 1] = name end
  end
  out("Missing APIs: %s", #missing == 0 and "none" or table.concat(missing, ", "))

  local getTpl = resolve("C_XMLUtil.GetTemplateInfo")
  for _, tpl in ipairs({ "WowStyle1DropdownTemplate", "UIDropDownMenuTemplate", "UIPanelButtonTemplate" }) do
    local found = "n/a"
    if getTpl then
      local ok, info = pcall(getTpl, tpl)
      found = (ok and info) and "si" or "no"
    end
    out("Template %s: %s", tpl, found)
  end
  out("CVar audio: EnableAllSound=%s EnableMusic=%s MusicVolume=%s MasterVolume=%s",
    cvar("Sound_EnableAllSound"), cvar("Sound_EnableMusic"), cvar("Sound_MusicVolume"), cvar("Sound_MasterVolume"))
end

---------------------------------------------------------------------------
-- 2. Events: registration + counting
---------------------------------------------------------------------------
local EVENTS = {
  "ENCOUNTER_START", "ENCOUNTER_END", "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "BOSS_KILL",
  "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
  "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "TAXIMAP_OPENED",
  "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
  "PLAYER_UPDATE_RESTING", "PLAYER_MOUNT_DISPLAY_CHANGED", "UNIT_AURA",
  "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT", "PLAYER_TARGET_CHANGED",
}
local QUIET = { UNIT_AURA = true, ZONE_CHANGED = true, ZONE_CHANGED_INDOORS = true, PLAYER_TARGET_CHANGED = true }

local frame = CreateFrame("Frame")
local counts, regFailed = {}, {}

for _, ev in ipairs(EVENTS) do
  local ok = pcall(frame.RegisterEvent, frame, ev)
  if not ok then regFailed[#regFailed + 1] = ev end
end
pcall(frame.RegisterEvent, frame, "ADDON_LOADED")

local function reportEvents()
  out("Events that can NOT be registered: %s", #regFailed == 0 and "none" or table.concat(regFailed, ", "))
  local parts = {}
  for _, ev in ipairs(EVENTS) do parts[#parts + 1] = ev .. "=" .. (counts[ev] or 0) end
  out("Events received: %s", table.concat(parts, " "))
end

---------------------------------------------------------------------------
-- 3. Auras (for the campfire condition)
---------------------------------------------------------------------------
local function scanAuras(tag)
  tag = tag or "auras"
  local get = resolve("C_UnitAuras.GetAuraDataByIndex")
  if not get then out("[%s] C_UnitAuras.GetAuraDataByIndex missing", tag) return end
  local n = 0
  for i = 1, 40 do
    local ok, a = pcall(get, "player", i, "HELPFUL")
    if not ok then out("[%s] error at index %d: %s", tag, i, a) return end
    if not a then break end
    n = n + 1
    out("[%s] %d: %s  spellId=%s", tag, i, a.name, a.spellId)
  end
  out("[%s] %d helpful auras found", tag, n)
end

---------------------------------------------------------------------------
-- 4. "Secret values" snapshot in combat
---------------------------------------------------------------------------
local function combatSnapshot()
  local function probe(label, fn, ...)
    -- no boolean tests on the value: a secret value could raise an error
    local ok, v = pcall(fn, ...)
    if ok then
      out("[combat] %s -> %s", label, v)
    else
      out("[combat] %s -> ERROR: %s", label, v)
    end
  end
  probe("UnitHealth(player)", UnitHealth, "player")
  probe("UnitExists(target)", UnitExists, "target")
  probe("UnitName(target)", UnitName, "target")
  probe("UnitClassification(target)", UnitClassification, "target")
  probe("UnitExists(boss1)", UnitExists, "boss1")
  probe("UnitAffectingCombat(player)", UnitAffectingCombat, "player")
  probe("InCombatLockdown()", InCombatLockdown)
  probe("IsInInstance()", IsInInstance)
  scanAuras("combat-auras")
end

---------------------------------------------------------------------------
-- 4b. Creature family/type of enemies (per-species playlists): are they readable in combat?
---------------------------------------------------------------------------
local MAX_CREATURES = 80

local function call(fn, ...)
  if not fn then return "n/a" end
  local ok, v = pcall(fn, ...)
  return ok and safe(v) or "<err>"
end

local function creatureSnapshot(unit, why)
  local okE, exists = pcall(UnitExists, unit)
  if not okE or safe(exists) ~= "true" then return end
  local guid = call(UnitGUID, unit)
  local npcID = "?"
  if guid ~= "<SECRET>" and guid ~= "<err>" and guid ~= "n/a" and strsplit then
    local okS, kind, _, _, _, _, id = pcall(strsplit, "-", guid)
    if okS then npcID = tostring(kind) .. ":" .. tostring(id) end
  end
  local inInst = call(IsInInstance)
  local row = {
    t = date and date("%H:%M:%S") or "?",
    why = why, unit = unit,
    combat = call(InCombatLockdown), instance = inInst,
    family = call(UnitCreatureFamily, unit),
    ctype = call(UnitCreatureType, unit),
    class = call(UnitClassification, unit),
    name = call(UnitName, unit),
    level = call(UnitLevel, unit),
    guid = guid, npc = npcID,
    attackable = call(UnitCanAttack, "player", unit),
    unitCombat = call(UnitAffectingCombat, unit),
    threat = call(UnitThreatSituation, "player", unit),
  }
  out("[creature] %s %s combat=%s inst=%s | family=%s type=%s class=%s | name=%s lvl=%s npc=%s | attackable=%s inCombat=%s threat=%s",
    why, unit, row.combat, row.instance, row.family, row.ctype, row.class, row.name, row.level, row.npc,
    row.attackable, row.unitCombat, row.threat)
  if RadioProbeDB then
    RadioProbeDB.creatures = RadioProbeDB.creatures or {}
    local list = RadioProbeDB.creatures
    list[#list + 1] = row
    while #list > MAX_CREATURES do table.remove(list, 1) end
  end
end

-- target plus the first few nameplates (can nameplates tell who is fighting us?)
local function creatureScan(why)
  creatureSnapshot("target", why)
  local shown = 0
  for i = 1, 40 do
    if shown >= 6 then break end
    local okE, exists = pcall(UnitExists, "nameplate" .. i)
    if okE and safe(exists) == "true" then
      shown = shown + 1
      creatureSnapshot("nameplate" .. i, why)
    end
  end
end

---------------------------------------------------------------------------
-- 5. State polling (flight, resting, mount, instance)
---------------------------------------------------------------------------
local lastState = {}
local STATE_FUNCS = {
  taxi = function() return UnitOnTaxi("player") end,
  resting = function() return IsResting() end,
  mounted = function() return IsMounted() end,
  swimming = function() return IsSwimming() end,
  instance = function() local i, t = IsInInstance(); return safe(i) .. "/" .. safe(t) end,
  zone = function() return (GetZoneText() or "?") .. " / " .. (GetSubZoneText() or "") end,
}

local function pollState()
  for key, fn in pairs(STATE_FUNCS) do
    local ok, v = pcall(fn)
    v = ok and safe(v) or "<err>"
    if lastState[key] ~= v then
      if lastState[key] ~= nil then out("State %s: %s -> %s", key, lastState[key], v) end
      lastState[key] = v
    end
  end
end

---------------------------------------------------------------------------
-- 6. Audio test
---------------------------------------------------------------------------
local function after(sec, fn)
  if C_Timer and C_Timer.After then C_Timer.After(sec, fn) end
end

local function testSoundFile(file, channel)
  local ok, willPlay, handle = pcall(PlaySoundFile, MEDIA .. file, channel)
  if not ok then out("PlaySoundFile(%s, %s) ERROR: %s", file, channel, willPlay) return end
  out("PlaySoundFile(%s, %s) -> willPlay=%s handle=%s", file, channel, willPlay, handle)
  if handle and StopSound then
    after(4, function()
      local okStop, err = pcall(StopSound, handle, 500)
      out("StopSound(%s) -> %s", handle, okStop and "ok" or err)
    end)
  end
end

local function testSounds()
  out("Music CVars: EnableMusic=%s MusicVolume=%s (must be >0 to hear the Music channel)",
    cvar("Sound_EnableMusic"), cvar("Sound_MusicVolume"))
  -- system sound: checks handle/StopSound independently of the custom files
  local kit = (SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960
  local ok, willPlay, handle = pcall(PlaySound, kit, "Master")
  out("PlaySound(READY_CHECK) -> ok=%s willPlay=%s handle=%s", ok, willPlay, handle)
  -- custom files, one every 5 seconds; each one is stopped after 4s
  local files = { "test.ogg", "test.mp3", "test.wav" }
  for i, f in ipairs(files) do
    after(1 + (i - 1) * 5, function() testSoundFile(f, "Music") end)
  end
  after(16, function() out("Audio test finished: note which files you HEARD and whether they stopped on their own.") end)
end

local function testMusic()
  local ok, err = pcall(PlayMusic, MEDIA .. "test.ogg")
  out("PlayMusic(test.ogg) -> %s. Did the zone music stop? Use /rprobe stopmusic", ok and "call ok" or err)
end

---------------------------------------------------------------------------
-- 7. Texture test (TGA and PNG)
---------------------------------------------------------------------------
local texFrame
local function testTextures()
  if texFrame then texFrame:SetShown(not texFrame:IsShown()) return end
  texFrame = CreateFrame("Frame", "RadioProbeTexFrame", UIParent, "BackdropTemplate")
  texFrame:SetSize(560, 310)
  texFrame:SetPoint("CENTER")
  texFrame:SetFrameStrata("DIALOG")
  if texFrame.SetBackdrop then
    texFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    texFrame:SetBackdropColor(0, 0, 0, 0.85)
  end
  texFrame:EnableMouse(true)
  texFrame:SetScript("OnMouseDown", function(self) self:Hide() end)

  local function addTex(file, x)
    local tex = texFrame:CreateTexture(nil, "ARTWORK")
    tex:SetSize(256, 256)
    tex:SetPoint("TOPLEFT", x, -16)
    local ok, res = pcall(tex.SetTexture, tex, MEDIA .. file)
    out("SetTexture(%s) -> ok=%s returned=%s", file, ok, res)
    local label = texFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOP", tex, "BOTTOM", 0, -6)
    label:SetText(file)
  end
  addTex("test.tga", 16)
  addTex("test.png", 288)
  out("Texture window open (click to close). Note which images you can see.")
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
frame:SetScript("OnEvent", function(_, ev, ...)
  if ev == "ADDON_LOADED" then
    if ... == ADDON then
      RadioProbeDB = RadioProbeDB or {}
      RadioProbeDB.runs = (RadioProbeDB.runs or 0) + 1
    end
    return
  end

  if ev == "UNIT_AURA" and ... ~= "player" then return end
  counts[ev] = (counts[ev] or 0) + 1

  if ev == "PLAYER_LOGOUT" then
    RadioProbeDB.lastLog = log
    RadioProbeDB.build = { GetBuildInfo() }
    return
  end

  if not QUIET[ev] or counts[ev] <= 3 then
    local n = select("#", ...)
    local args = {}
    for i = 1, math.min(n, 5) do args[i] = safe((select(i, ...))) end
    out("Event %s (#%d) args: %s", ev, counts[ev], table.concat(args, ", "))
  end

  if ev == "PLAYER_ENTERING_WORLD" and counts[ev] == 1 then
    reportApis()
    reportEvents()
    out("Commands: /rprobe report | sound | music | stopmusic | tex | auras | creature | clear")
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(2, pollState) end
  elseif ev == "PLAYER_REGEN_DISABLED" then
    after(1, combatSnapshot)
    after(1.5, function() creatureScan("pull+1s") end)
    after(5, function() creatureScan("pull+5s") end)
  elseif ev == "PLAYER_TARGET_CHANGED" then
    creatureSnapshot("target", "target")
  elseif ev == "PLAYER_CONTROL_LOST" then
    after(1, function() out("After CONTROL_LOST: UnitOnTaxi=%s", UnitOnTaxi and UnitOnTaxi("player")) end)
  end
end)

---------------------------------------------------------------------------
-- Slash
---------------------------------------------------------------------------
SLASH_RADIOPROBE1 = "/rprobe"
SlashCmdList.RADIOPROBE = function(msg)
  local cmd = (msg or ""):lower():match("^%s*(%S*)")
  if cmd == "sound" then testSounds()
  elseif cmd == "music" then testMusic()
  elseif cmd == "stopmusic" then pcall(StopMusic) out("StopMusic called")
  elseif cmd == "tex" then testTextures()
  elseif cmd == "auras" then scanAuras()
  elseif cmd == "creature" or cmd == "mob" then creatureScan("manual")
  elseif cmd == "clear" then wipe(log) if RadioProbeDB then RadioProbeDB.creatures = {} end out("Log cleared")
  else reportApis() reportEvents()
  end
end
