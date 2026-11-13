-- Minimal WoW API stubs to test the addon logic outside the game.
local now = 0
local timers = {}
function GetTime() return now end
local function addTimer(sec, fn, rep)
  local t = { at = now + sec, fn = fn, rep = rep, sec = sec }
  t.Cancel = function(self) self.cancelled = true end
  table.insert(timers, t)
  return t
end
C_Timer = {
  After = function(s, f) addTimer(s, f) end,
  NewTimer = function(s, f) return addTimer(s, f) end,
  NewTicker = function(s, f) return addTimer(s, f, true) end,
}
function advance(sec)
  local target = now + sec
  while true do
    local nextT
    for _, t in ipairs(timers) do
      if not t.cancelled and t.at <= target and (not nextT or t.at < nextT.at) then nextT = t end
    end
    if not nextT then break end
    now = nextT.at
    if nextT.rep then nextT.at = now + nextT.sec else nextT.cancelled = true end
    nextT.fn()
  end
  now = target
end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function geterrorhandler() return function(e) print("LUA ERROR: " .. tostring(e)) end end
unpack = table.unpack
local eventFrames = {}
local stub
stub = function()
  local o = {}
  local mt = {}
  mt.__index = function(t, k)
    if k == "GetWidth" then return function() return rawget(t, "_w") or 100 end end
    if k == "SetSize" or k == "SetWidth" then return function(self, w) self._w = w end end
    if k == "RegisterEvent" then return function(self, e) eventFrames[e] = eventFrames[e] or {}; table.insert(eventFrames[e], self) end end
    if k == "SetScript" then return function(self, s, fn) rawset(self, "_" .. s, fn) end end
    if k == "IsShown" then return function(self) return rawget(self, "_shown") ~= false end end
    if k == "SetShown" then return function(self, v) rawset(self, "_shown", v and true or false) end end
    if k == "Show" then return function(self) rawset(self, "_shown", true); local s = rawget(self, "_OnShow"); if s then s(self) end end end
    if k == "Hide" then return function(self) rawset(self, "_shown", false) end end
    if k == "GetChecked" then return function(self) return rawget(self, "_checked") end end
    if k == "SetChecked" then return function(self, v) rawset(self, "_checked", v) end end
    if k == "GetText" then return function(self) return rawget(self, "_text") or "" end end
    if k == "SetText" then return function(self, v) rawset(self, "_text", v) end end
    if k == "GetMinMaxValues" then return function(self) return rawget(self, "_min") or 0, rawget(self, "_max") or 0 end end
    if k == "SetMinMaxValues" then return function(self, a, b) rawset(self, "_min", a); rawset(self, "_max", b) end end
    if k == "SetValue" then return function(self, v) local s = rawget(self, "_OnValueChanged"); if s then s(self, v) end end end
    if k == "SetupMenu" then return function(self, gen) rawset(self, "_gen", gen) end end
    if k == "GetPoint" then return function() return "CENTER", nil, "CENTER", 0, 0 end end
    if k == "NumLines" then return function() return 0 end end
    if k == "GetFrameLevel" then return function() return 5 end end
    if k == "GetFrameStrata" then return function() return "MEDIUM" end end
    if k == "GetHeight" then return function() return rawget(t, "_w") or 100 end end
    if k == "GetEffectiveAlpha" or k == "GetEffectiveScale" then return function() return 1 end end
    if k == "GetCenter" then return function() return 10, 10 end end
    if k == "IsVisible" then return function(self) return rawget(self, "_shown") ~= false end end
    if k == "SetObeyStepDrag" or k == "SetDisabledCheckedTexture" then return nil end
    if k:match("^Create") or k:match("^Get") then return function() return stub() end end
    return function() end
  end
  return setmetatable(o, mt)
end
function CreateFrame(_, name) local f = stub(); if name then _G[name] = f end; return f end
UIParent = stub(); GameTooltip = stub(); GameTooltip_Hide = function() end
SettingsPanel = stub(); rawset(SettingsPanel, "_shown", false)
UISpecialFrames = {}
clientLocale = "enUS"
function GetLocale() return clientLocale end
function CreateFont(name) local o = stub(); _G[name] = o; return o end
GameFontNormalSmall, GameFontHighlightSmall, GameTooltipText = stub(), stub(), stub()
Minimap = stub(); shift = false
function IsShiftKeyDown() return shift end
ctrl = false
function IsControlKeyDown() return ctrl end
function ReloadUI() reloaded = true end
GameFontHighlightHuge = stub()
settingsOpened = nil
Settings = { RegisterCanvasLayoutCategory = function(frame, name) return { GetID = function() return name end } end, RegisterAddOnCategory = function() end, OpenToCategory = function(id) if blizzardSettingsWorks then settingsOpened = id; rawset(SettingsPanel, "_shown", true) end end }
blizzardSettingsWorks = true
function GetCursorPosition() return 0, 0 end
function GetBuildInfo() return "1.60.1", "70862", "Nov 6 2026", 16001 end
function debugstack() return "" end
SlashCmdList = {}

G = { combat = false, taxi = false, resting = false, instance = "none", auras = {}, speed = 0, class = "normal" }
function InCombatLockdown() return G.combat end
function UnitOnTaxi() return G.taxi end
function IsResting() return G.resting end
function IsInInstance() return G.instance ~= "none", G.instance end
function GetInstanceInfo() return G.instanceName, G.instance, 1, "Normal", 5, 0, false, G.instanceID end
function GetUnitSpeed() return G.speed end
function UnitClassification() return G.class end
function UnitCanAttack() return true end
function issecretvalue() return false end
C_UnitAuras = { GetPlayerAuraBySpellID = function(id)
  if G.combat then error("Auras cannot be accessed when secret") end
  return G.auras[id] and { spellId = id } or nil
end }
playing = nil
function PlayMusic(p) playing = p end
function StopMusic() playing = nil end
function fire(e, ...)
  for _, f in ipairs(eventFrames[e] or {}) do rawget(f, "_OnEvent")(f, e, ...) end
  advance(0) -- next frame: coalesced evaluations run here
end
-- new APIs used by the newer conditions/features
function UnitName() return "Tester" end
function GetRealmName() return "Realm" end
G.hour = 12; G.map = 1411; G.swimming = false; G.mounted = false; G.flying = false; G.dead = false; G.channel = nil
function GetGameTime() return G.hour, 0 end
function IsSwimming() return G.swimming end
function IsMounted() return G.mounted end
function IsFlying() return G.flying end
function UnitIsDeadOrGhost() return G.dead end
function UnitChannelInfo() return G.channel end
MAPS = { [1411] = { name = "Durotar", mapType = 3, parentMapID = 12 }, [12] = { name = "Kalimdor", mapType = 2, parentMapID = 947 },
         [1454] = { name = "Orgrimmar", mapType = 3, parentMapID = 1411 } }
C_Map = { GetBestMapForUnit = function() return G.map end, GetMapInfo = function(id) return MAPS[id] end }
C_Spell = { GetSpellName = function(id) if id == 7620 or id == 131474 then return "Fishing" end return "Other" end }
musicVolume = "0.8"
C_CVar = { GetCVar = function(k) if k == "Sound_MusicVolume" then return musicVolume end return "1" end,
           SetCVar = function(k, v) if k == "Sound_MusicVolume" then musicVolume = v end end }
local fakeClock = 0
function debugprofilestop() fakeClock = fakeClock + 0.01 return fakeClock end
function UpdateAddOnMemoryUsage() end
G.afk = false
function UnitIsAFK() return G.afk end
function GetAddOnMemoryUsage() return 321 end
ChatFrame1 = stub()

KZZR_Library = { tracks = {
  { file = "music\\a.ogg", folder = "", title = "A", artist = "X", duration = 10, genre = "City Pop", year = 1983, track = 2 },
  { file = "music\\b.ogg", folder = "", title = "B", duration = 10, genre = "City Pop", year = 1985, track = 1, composer = "Yamashita" },
  { file = "music\\c.mp3", folder = "Rock", title = "C", duration = 10 },
  { file = "music/Podcast/P/e1/part_000.ogg", folder = "Podcast/Pod", title = "Ep 1", artist = "Pod", album = "2026-11-09", duration = 150, episode = "k1", part = 1, parts = 3 },
  { file = "music/Podcast/P/e1/part_001.ogg", folder = "Podcast/Pod", title = "Ep 1", artist = "Pod", album = "2026-11-09", duration = 150, episode = "k1", part = 2, parts = 3 },
  { file = "music/Podcast/P/e1/part_002.ogg", folder = "Podcast/Pod", title = "Ep 1", artist = "Pod", album = "2026-11-09", duration = 90, episode = "k1", part = 3, parts = 3 },
} }

KZZR_GameMusic = {
  { fid = 53198, title = "Orgrimmar 01 Zone", folder = "WoW Classic/Cities/Orgrimmar", duration = 68.89, icon = 135759, preset = "town" },
  { fid = 8158670, title = "Hyjal General A", folder = "WoW Forever/New zones", duration = 120, icon = 136096, preset = "idle" },
}

local ns = {}
for _, f in ipairs({ "Locales", "Core", "Player", "Rules", "UI", "LibraryUI", "Settings", "Onboarding", "Minimap", "Banner" }) do
  assert(load(SRC[f], f))("KalimdorZugZugRadio", ns)
end
local fails = 0
local function check(label, cond)
  if not cond then fails = fails + 1 end
  print((cond and "PASS " or "FAIL ") .. label .. (cond and "" or
    ("   playing=" .. tostring(playing) .. " pl=" .. tostring(ns.Player.playlist) .. " cur=" .. tostring(ns.Rules.current))))
end
local function is(name) return playing ~= nil and tostring(playing):find(name, 1, true) ~= nil end

fire("ADDON_LOADED", "KalimdorZugZugRadio"); fire("PLAYER_LOGIN"); fire("PLAYER_ENTERING_WORLD", true, false)
ns.db.crossfade = false -- tested separately below
ns.db.fightTail = 4 -- the fight tail is tested separately below
check("no assignments -> silence", playing == nil)
ns.db.shuffle = false
assert(ns.CreatePlaylist("Explore")); assert(ns.CreatePlaylist("Fight"))
check("duplicate name rejected", ns.CreatePlaylist("explore") == nil)
ns.SetInPlaylist("Explore", "music\\a.ogg", true); ns.SetInPlaylist("Explore", "music\\b.ogg", true)
ns.SetManyInPlaylist("Fight", { "music\\c.mp3" }, true)
ns.Assign("idle", "Explore"); ns.Assign("combat", "Fight")
check("No condition plays Explore", is("music\\a.ogg"))
G.combat = true; fire("PLAYER_REGEN_DISABLED")
check("combat switches immediately -> Fight", is("c.mp3"))
G.combat = false; fire("PLAYER_REGEN_ENABLED"); advance(1)
check("delayed return", is("c.mp3"))
advance(5)
check("back to Explore, A restarts", is("a.ogg"))
advance(11)
check("auto-advances to B", is("b.ogg"))

ns.CreatePlaylist("Fire"); ns.SetInPlaylist("Fire", "music\\c.mp3", true); ns.Assign("campfire", "Fire")
G.auras[1283391] = true; fire("UNIT_AURA", "player")
check("only Campfire Nearby -> no campfire", playing and not is("c.mp3"))
G.auras[1229739] = true; fire("UNIT_AURA", "player")
check("both auras -> campfire", is("c.mp3"))
G.auras[1229739] = nil; fire("UNIT_AURA", "player"); advance(20)
check("Welcoming expired, campfire stays", ns.Rules.current == "campfire")
G.speed = 7; advance(1.1); G.speed = 0; advance(5)
check("moving ends the campfire", ns.Rules.current == "idle")
G.auras[1283391] = nil; fire("UNIT_AURA", "player")

ns.PlayFrom(ns.ALL, ns.trackById["music\\c.mp3"])
check("free play from track C", is("c.mp3") and ns.db.mode == ns.ALL)
G.combat = true; fire("PLAYER_REGEN_DISABLED")
check("free play ignores combat", ns.Player.playlist == ns.ALL)
G.combat = false; fire("PLAYER_REGEN_ENABLED")
ns.SetMode("auto"); advance(5)
check("back to automatic", ns.Rules.current == "idle")

ns.Player:Stop(true); G.combat = true; fire("PLAYER_REGEN_DISABLED")
check("user stop respected", playing == nil)
ns.Player:Toggle(); check("play resumes with combat", is("c.mp3"))
G.combat = false; fire("PLAYER_REGEN_ENABLED"); advance(5)

ns.RenamePlaylist("Explore", "Tour")
check("rename keeps the assignment", ns.db.assign.idle == "Tour" and ns.Player.playlist == "Tour")
ns.DeletePlaylist("Tour"); advance(5)
check("delete -> silence", playing == nil and ns.db.assign.idle == nil)

ns.Assign("idle", "Fight"); ns.SetInPlaylist("Fight", "music\\a.ogg", true)
ns.SetInPlaylist("Fight", "music\\c.mp3", false)
check("current track removed -> switches to another", is("a.ogg"))

ns.LibraryUI:Toggle(true); ns.LibraryUI:Refresh(); ns.UI:Refresh(); ns.UI:RefreshProgress()
SlashCmdList.KZZRADIO("status"); SlashCmdList.KZZRADIO("playlist tutti"); SlashCmdList.KZZRADIO("shuffle")
check("/kzz playlist tutti (any language's 'all' keyword)", ns.db.mode == ns.ALL)
-- minimap / addon compartment
local uiShown = KalimdorZugZugRadioFrame:IsShown()
KZZR_OnCompartmentClick("KalimdorZugZugRadio", "LeftButton")
check("compartment left-click -> player", KalimdorZugZugRadioFrame:IsShown() ~= uiShown)
local libShown = KalimdorZugZugLibraryFrame:IsShown()
KZZR_OnCompartmentClick("KalimdorZugZugRadio", "RightButton")
check("compartment right-click -> library", KalimdorZugZugLibraryFrame:IsShown() ~= libShown)
local wasPlaying = ns.Player.playing
shift = true; KZZR_OnCompartmentClick("KalimdorZugZugRadio", "LeftButton"); shift = false
check("shift-click -> play/stop", ns.Player.playing ~= wasPlaying)
KZZR_OnCompartmentEnter("KalimdorZugZugRadio", stub()); KZZR_OnCompartmentLeave()
SlashCmdList.KZZRADIO("minimap")
check("/kzz minimap hides the button", ns.db.minimap.hide == true)
-- settings: toggleable conditions and opening the panel
ns.SetMode("auto"); ns.Assign("idle", "Fight"); advance(5)
check("auto with No condition = Fight", is("a.ogg"))
ns.SetConditionEnabled("idle", false); advance(5)
check("disabled condition -> silence", playing == nil and ns.PlaylistFor("idle") == nil)
ns.SetConditionEnabled("idle", true); advance(5)
check("re-enabled condition -> resumes", is("a.ogg"))
ns.db.disabled.combat = true; G.combat = true; fire("PLAYER_REGEN_DISABLED")
check("disabled combat condition doesn't interrupt", is("a.ogg"))
G.combat = false; fire("PLAYER_REGEN_ENABLED"); ns.db.disabled.combat = nil
ctrl = true; KZZR_OnCompartmentClick("KalimdorZugZugRadio", "LeftButton"); ctrl = false
check("ctrl-click opens the settings", settingsOpened == "Kalimdor ZugZug Radio")
settingsOpened = nil; SlashCmdList.KZZRADIO("config")
check("/kzz config opens the settings", settingsOpened == "Kalimdor ZugZug Radio")
settingsOpened = nil; G.combat = true; SlashCmdList.KZZRADIO("config"); G.combat = false
check("doesn't open in combat", settingsOpened == nil)
blizzardSettingsWorks = false; rawset(SettingsPanel, "_shown", false); settingsOpened = nil
KalimdorZugZugSettingsPanel:Hide() -- the canvas stays hidden if Blizzard doesn't select the category
SlashCmdList.KZZRADIO("config")
check("Blizzard Options don't open -> standalone window", ns.Settings.standalone and KalimdorZugZugSettingsPanel:IsShown()
  and ns.db.lastSettingsOpen[#ns.db.lastSettingsOpen]:find("standalone window"))
KalimdorZugZugSettingsPanel:Show(); ns.Settings:Refresh(); ns.Minimap:SetShown(true)
check("minimap button shown from the settings", ns.db.minimap.hide == false)

-- in-game music
check("game music loaded and WoW music playlist", #ns.gameTracks == 2 and ns.IsPlayable(ns.GAME)
  and ns.AllPlaylistNames()[2] == ns.GAME and ns.FindPlaylist("wow") == ns.GAME)
ns.PlayFrom(ns.GAME, ns.trackById["game:53198"])
check("game music played via FileDataID", playing == 53198 and ns.CoverOf(ns.Player.track) == 135759)
ns.CreatePlaylist("Horde"); ns.SetInPlaylist("Horde", "game:53198", true); ns.SetInPlaylist("Horde", "music\\b.ogg", true)
ns.SetMode("auto"); ns.Assign("idle", "Horde"); advance(5)
check("user playlist with game music and own tracks", ns.Player.playlist == "Horde" and (playing == 53198 or is("b.ogg")))
-- precedence: manual next/previous = free play, conditions don't interrupt
ns.Player:Next()
check("manual next -> free play", ns.db.mode == "Horde")
local before = playing
G.combat = true; ns.Assign("combat", "Fight"); fire("PLAYER_REGEN_DISABLED")
check("elite/combat doesn't interrupt the manual choice", playing == before and ns.Player.playlist == "Horde")
G.combat = false; fire("PLAYER_REGEN_ENABLED")
ns.SetMode("auto"); advance(5)
check("returned to automatic", ns.db.mode == "auto")
advance(130)
check("automatic end of track doesn't switch to free play", ns.db.mode == "auto")

-- podcast: an episode split into parts, resumed from the saved part
local ep = ns.trackById["ep:k1"]
check("episode = a single item with 3 parts", ep and #ep.parts == 3 and ep.duration == 390 and #ns.episodes == 1
  and ns.IsPlayable(ns.PODCAST) and ns.FindPlaylist("podcast") == ns.PODCAST and ns.trackById[ep.parts[1].file] == nil)
check("podcasts are not in Whole library", not ns.GetPlaylist(ns.ALL).has[ep.file] and ns.GetPlaylist(ns.PODCAST).has[ep.file])
ns.CreatePlaylist("Mix"); ns.SetInPlaylist("Mix", ep.file, true)
check("an episode can still be added to a user playlist", ns.IsPlayable("Mix") and ns.GetPlaylist("Mix").tracks[1] == ep)
ns.DeletePlaylist("Mix")
ns.PlayFrom(ns.PODCAST, ep)
check("part 1", is("part_000") and ns.Player.part == 1)
advance(150) -- parts end 0.2 s early (PlayMusic loops)
check("end of part -> part 2, progress saved", is("part_001") and ns.db.podcastProgress["ep:k1"].part == 2)
advance(10)
check("time since the start of the episode", math.abs(ns.Player:Elapsed() - 160) < 1)
ns.Player:Stop(true); ns.SetMode("auto"); advance(5)
ns.PlayFrom(ns.PODCAST, ep)
check("resumes from part 2 after stop/switch", is("part_001"))
ns.Player:Next()
check("next = next part", is("part_002"))
advance(1); ns.Player:Prev()
check("previous within 3s = previous part", is("part_001"))
advance(10); ns.Player:Prev()
check("previous after 3s = restart the part", is("part_001") and ns.Player:ElapsedInPart() < 1)
ns.Player:Next(); advance(91)
-- the only episode in the queue: once finished, the queue starts it again from part 1
check("episode finished -> starts over", is("part_000") and ns.Player.part == 1)
ns.Player:Stop(true); ns.SetEpisodePart(ep, 1, true)
ns.PlayFrom(ns.PODCAST, ep)
check("episode marked done restarts from the beginning", is("part_000"))
ns.SetMode("auto"); advance(5)

-- free play warning in the settings
ns.SetMode(ns.ALL); KalimdorZugZugSettingsPanel:Show(); ns.Settings:Refresh()
check("free play -> warning shown in the settings", KalimdorZugZugSettingsPanel.freeWarn:IsShown())
ns.SetMode("auto"); ns.Settings:Refresh()
check("automatic -> warning hidden", not KalimdorZugZugSettingsPanel.freeWarn:IsShown())

-- player skins
check("classic skin by default", (ns.db.ui.skin or "classic") == "classic" and ns.UI:HasClassicDecorations())
ns.UI:SetSkin("modern"); ns.UI:Refresh()
check("switch to modern skin", ns.db.ui.skin == "modern" and ns.UI.statusFont == "GameFontNormalSmall")
ns.UI:SetSkin("classic"); ns.UI:Refresh()
check("back to classic skin", ns.db.ui.skin == "classic" and ns.UI.statusFont == "GameFontNormal")

-- new conditions
ns.SetMode("auto")
ns.CreatePlaylist("Special"); ns.SetInPlaylist("Special", "music\\c.mp3", true)
for _, key in ipairs({ "swimming", "mounted", "night", "dead", "fishing", "pvp", "levelup" }) do ns.Assign(key, "Special") end
advance(5)
local function cur() return ns.Rules.current end
G.swimming = true; advance(1.1)
check("swimming condition", cur() == "swimming")
G.swimming = false; advance(5.1)
G.mounted = true; advance(1.1)
check("ground mount condition", cur() == "mounted")
G.flying = true; advance(5.1)
check("flying mount is not 'mounted (ground)'", cur() ~= "mounted")
G.flying = false; G.mounted = false; advance(5.1)
G.hour = 23; advance(1.1)
check("night condition (game time 23:00)", cur() == "night")
G.hour = 12; advance(5.1)
G.dead = true; fire("PLAYER_DEAD")
check("dead / ghost condition", cur() == "dead")
G.dead = false; fire("PLAYER_ALIVE"); advance(5)
G.channel = "Fishing"; fire("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 131474)
check("fishing condition", cur() == "fishing")
G.channel = nil; fire("UNIT_SPELLCAST_CHANNEL_STOP", "player"); advance(10)
check("still fishing between two casts", cur() == "fishing")
advance(16)
check("fishing ends after the grace period", cur() ~= "fishing")
G.instance = "pvp"; fire("PLAYER_ENTERING_WORLD", false, false)
check("battleground condition", cur() == "pvp")
G.instance = "none"; fire("PLAYER_ENTERING_WORLD", false, false); advance(5)
fire("PLAYER_LEVEL_UP", 20)
check("level up jingle has top priority", cur() == "levelup")
advance(11)
check("after the jingle the normal music comes back", cur() ~= "levelup")

-- zone music (by map ID, with parent maps)
ns.CreatePlaylist("Durotar"); ns.SetInPlaylist("Durotar", "music\\b.ogg", true)
G.map = 1411; fire("ZONE_CHANGED_NEW_AREA")
ns.Assign("zone", "Durotar"); advance(5)
check("zone music in Durotar", cur() == "zone" and ns.Player.playlist == "Durotar" and ns.db.zones[1411].name == "Durotar")
G.map = 1454; fire("ZONE_CHANGED_NEW_AREA"); advance(5)
check("Orgrimmar (child map of Durotar) has its own zone level", ns.CurrentZone().id == 1454)
check("unassigned zone falls back", cur() ~= "zone")
G.map = 1411; fire("ZONE_CHANGED_NEW_AREA"); advance(5)

-- profiles
ns.NewCharacterProfile()
local idleBefore = ns.db.profiles.Default.assign.idle
check("new character profile copies the settings", ns.profileName == "Tester-Realm" and idleBefore ~= nil
  and ns.db.assign.idle == idleBefore and ns.db.charProfiles["Tester-Realm"] == "Tester-Realm")
ns.Assign("idle", nil)
check("profiles are independent", ns.db.profiles.Default.assign.idle == idleBefore and ns.db.assign.idle == nil)
ns.SetCharacterProfile(ns.DEFAULT_PROFILE)
check("back to Default", ns.db.assign.idle == idleBefore and ns.db.charProfiles["Tester-Realm"] == nil)
ns.DeleteProfile("Tester-Realm")
check("profile deleted", ns.db.profiles["Tester-Realm"] == nil)

-- sharing
local txt = ns.ExportPlaylist("Horde")
check("export text", type(txt) == "string" and txt:sub(1, 7) == "!KZZR1!")
local name, found, total = ns.ImportPlaylist(txt)
check("import creates a copy", name == "Horde (2)" and found == total and total >= 1)
check("base64 round trip", ns.Base64Decode(ns.Base64Encode("Orda ナニダト ab")) == "Orda ナニダト ab")
check("invalid text rejected", ns.ImportPlaylist("hello") == nil)
ns.ShowShareDialog("export", txt); ns.ShowShareDialog("import", "", function() end)

-- crossfade: volume ramps down, playlist switches, volume comes back
ns.db.crossfade = true
ns.Assign("combat", "Special"); advance(5)
G.combat = true; fire("PLAYER_REGEN_DISABLED"); advance(0.3)
check("crossfade: volume going down", tonumber(musicVolume) < 0.8 and ns.db.userVolume == 0.8)
advance(2)
check("crossfade: switched and volume restored", cur() == "combat" and math.abs(tonumber(musicVolume) - 0.8) < 0.001
  and ns.db.userVolume == 0.8)
G.combat = false; fire("PLAYER_REGEN_ENABLED"); advance(6)
ns.db.crossfade = false

-- banner
ns.db.ui.banner = true
ns.PlayFrom(ns.GAME, ns.trackById["game:8158670"])
check("now playing banner shown", ns.Banner:IsShown())
ns.SetMode("auto"); advance(5)

-- performance accounting
local report = ns.PerfReport()
check("perf report", report[1]:find("321 KB", 1, true) ~= nil and #report > 1)
SlashCmdList.KZZRADIO("perf")
check("/kzz perf saves the report", type(ns.db.lastPerf) == "table")
check("UNIT_AURA in combat costs no evaluation", (function()
  G.combat = true; fire("PLAYER_REGEN_DISABLED")
  local before = ns.perf.Evaluate.calls
  for _ = 1, 50 do fire("UNIT_AURA", "player") end
  local after = ns.perf.Evaluate.calls
  G.combat = false; fire("PLAYER_REGEN_ENABLED"); advance(6)
  return after == before
end)())

-- death: the client overrides our music, so the current track is started again
ns.PlayFrom(ns.GAME, ns.trackById["game:53198"]); advance(5)
playing = "zone music of the game"  -- what the client does on death
G.dead = true; fire("PLAYER_DEAD"); advance(2)
check("after death our track plays again (free play)", playing == 53198 and ns.db.mode == ns.GAME)
playing = "ghost music of the game"
fire("PLAYER_ALIVE"); advance(2)
check("after releasing the spirit it plays again", playing == 53198)
G.dead = false; playing = "game music"; fire("PLAYER_UNGHOST"); advance(2)
check("after resurrection it plays again", playing == 53198)
ns.SetMode("auto"); advance(5)

-- podcast: episode navigation buttons, and next/prev still move by one part
ns.CreatePlaylist("Shows"); ns.SetInPlaylist("Shows", "ep:k1", true); ns.SetInPlaylist("Shows", "music\\a.ogg", true)
ns.db.shuffle = false
ns.SetEpisodePart(ns.trackById["ep:k1"], 2)
ns.PlayFrom("Shows", ns.trackById["ep:k1"])
check("podcast resumes at part 2", is("part_001"))
ns.UI:Refresh()
check("episode buttons shown on a podcast", KalimdorZugZugRadioFrame.epNext:IsShown())
ns.Player:Next()
check("next on a podcast = next part", is("part_002"))
ns.Player:SkipTrack(1)
check("next episode skips the remaining parts", ns.Player.track == ns.trackById["music\\a.ogg"]
  and ns.db.podcastProgress["ep:k1"].part == 3 and not ns.db.podcastProgress["ep:k1"].done)
ns.UI:Refresh()
check("episode buttons hidden on a song", not KalimdorZugZugRadioFrame.epNext:IsShown())
ns.Player:SkipTrack(-1)
check("previous episode resumes where it was", ns.Player.track == ns.trackById["ep:k1"] and is("part_002"))
ns.SetMode("auto"); ns.DeletePlaylist("Shows"); advance(5)

-- volume
ns.Player:SetVolume(0.35)
check("volume slider sets the Music volume", math.abs(tonumber(musicVolume) - 0.35) < 0.001)
ns.Player:SetVolume(2)
check("volume is clamped to 100%", tonumber(musicVolume) == 1)
ns.db.crossfade = true
ns.Assign("combat", "Special"); ns.Player:SetVolume(0.6); advance(5)
G.combat = true; fire("PLAYER_REGEN_DISABLED"); advance(0.3)
ns.Player:SetVolume(0.2) -- user moves the slider during the fade
advance(2)
check("volume changed during a fade becomes its target", math.abs(tonumber(musicVolume) - 0.2) < 0.001)
G.combat = false; fire("PLAYER_REGEN_ENABLED"); advance(6)
ns.db.crossfade = false; ns.Player:SetVolume(0.8)

-- v0.6: favourites, exclusions, history, stats
ns.SetMode("auto"); advance(5)
local A, B, C = ns.trackById["music\\a.ogg"], ns.trackById["music\\b.ogg"], ns.trackById["music\\c.mp3"]
ns.ToggleFavorite(B)
check("favourite -> Favourites playlist", ns.IsFavorite(B) and ns.IsPlayable(ns.FAV) and ns.GetPlaylist(ns.FAV).tracks[1] == B)
ns.ToggleFavorite(B)
check("unfavourite", not ns.IsFavorite(B))
ns.CreatePlaylist("ABC"); ns.SetManyInPlaylist("ABC", { A.file, B.file, C.file }, true)
ns.SetExcluded(B, true)
ns.PlayFrom("ABC", A); advance(11)
check("excluded track is skipped automatically", ns.Player.track == C)
ns.PlayFrom("ABC", B)
check("an excluded track still plays when chosen explicitly", ns.Player.track == B)
ns.SetExcluded(B, false)
check("history: most recent first", ns.db.history[1] == B.file and ns.IsPlayable(ns.HISTORY))
check("stats: plays counted", (ns.db.stats[A.file].plays or 0) >= 1 and ns.IsPlayable(ns.TOP))
advance(3); ns.Player:Stop(true)
check("stats: listening time counted", (ns.db.totalSeconds or 0) > 0)
SlashCmdList.KZZRADIO("stats")
ns.DeletePlaylist("ABC"); ns.SetMode("auto"); advance(5)

-- AFK pause / resume
ns.Player:Toggle(true); advance(1)
G.afk = true; fire("PLAYER_FLAGS_CHANGED", "player"); advance(2)
check("AFK pauses the music", not ns.Player.playing and ns.Player.afkPaused)
advance(5)
check("conditions don't restart it while AFK", not ns.Player.playing)
G.afk = false; fire("PLAYER_FLAGS_CHANGED", "player"); advance(1)
check("back from AFK: music resumes", ns.Player.playing and not ns.Player.afkPaused)

-- cinematics: the music is lowered, then restored
ns.Player:SetVolume(0.8)
fire("CINEMATIC_START"); advance(1)
check("cinematic lowers the music", math.abs(tonumber(musicVolume) - 0.2) < 0.01)
fire("CINEMATIC_STOP"); advance(1)
check("after the cinematic the volume is back", math.abs(tonumber(musicVolume) - 0.8) < 0.01)

-- per-condition volume
local condKey = ns.Rules.current
ns.SetConditionVolume(condKey, 0.5); ns.Rules:Reset(); ns.Rules:Evaluate(true); advance(1)
check("condition volume multiplies the user volume", ns.Rules.current == condKey and math.abs(tonumber(musicVolume) - 0.4) < 0.01
  and ns.Player:GetVolume() == 0.8)
ns.SetMode(ns.ALL)
check("free play uses the user's own volume", math.abs(tonumber(musicVolume) - 0.8) < 0.01)
ns.SetMode("auto"); ns.SetConditionVolume(condKey, 1); advance(5)

-- volume changed in the game options is adopted
musicVolume = "0.3"; ns.Player:GetVolume()
check("external volume change becomes the user volume", math.abs(ns.Player:GetVolume() - 0.3) < 0.01)
ns.Player:SetVolume(0.8)

-- boss-specific music
ns.CreatePlaylist("Rag"); ns.SetInPlaylist("Rag", "music\\a.ogg", true)
G.combat = true; fire("ENCOUNTER_START", 672, "Ragnaros", 1, 40); fire("PLAYER_REGEN_DISABLED")
check("boss seen is remembered", ns.db.seenBosses[672] == "Ragnaros")
ns.AssignBoss(672, "Rag"); advance(1)
check("boss-specific playlist", ns.Rules.current == "boss" and ns.Player.playlist == "Rag")
fire("ENCOUNTER_END", 672); G.combat = false; fire("PLAYER_REGEN_ENABLED"); advance(6)
G.combat = true; fire("ENCOUNTER_START", 999, "Other boss", 1, 5); fire("PLAYER_REGEN_DISABLED"); advance(1)
check("other bosses use the generic boss playlist", ns.Player.playlist ~= "Rag")
fire("ENCOUNTER_END", 999); G.combat = false; fire("PLAYER_REGEN_ENABLED"); advance(6)

-- 1.0: after a fight the music lasts (fading out) for a few seconds; every fight starts a new track
local function vol() return tonumber(musicVolume) end
ns.db.fightTail = 8; ns.db.crossfade = true; ns.db.shuffle = true
ns.CreatePlaylist("Pulls"); ns.SetManyInPlaylist("Pulls", { "music\\a.ogg", "music\\b.ogg", "music\\c.mp3" }, true)
ns.Assign("combat", "Pulls"); ns.SetMode("auto"); advance(5)
local calm = ns.Player.playlist -- the playlist out of combat
G.combat = true; fire("PLAYER_REGEN_DISABLED"); advance(2)
local first = ns.Player.track
check("fight: combat music", ns.Player.playlist == "Pulls" and math.abs(vol() - 0.8) < 0.001)
G.combat = false; fire("PLAYER_REGEN_ENABLED"); advance(3)
check("fight tail: same song, fading out", ns.Player.playlist == "Pulls" and ns.Player.track == first
  and vol() < 0.75 and vol() > 0.05 and ns.db.userVolume == 0.8)
G.combat = true; fire("PLAYER_REGEN_DISABLED"); advance(1.5)
check("back in the fight: same song, volume restored", ns.Player.track == first and math.abs(vol() - 0.8) < 0.001)
G.combat = false; fire("PLAYER_REGEN_ENABLED"); advance(3.7)
check("tail still running", ns.Player.playlist == "Pulls")
advance(1.5)
check("track ended during the tail: next condition at once", ns.Player.playlist == calm and ns.Rules.current ~= "combat")
advance(2)
check("volume back after the tail", math.abs(vol() - 0.8) < 0.001)
G.combat = true; fire("PLAYER_REGEN_DISABLED"); advance(1)
local second = ns.Player.track
check("a new fight starts a different track", ns.Player.playlist == "Pulls" and second ~= first)
G.combat = false; fire("PLAYER_REGEN_ENABLED"); advance(7.5)
check("the tail lasts the chosen 8 s", ns.Player.playlist == "Pulls" and ns.Player.track == second and vol() < 0.1)
advance(1); advance(1)
check("after the tail: back to the calm music, full volume", ns.Player.playlist == calm and math.abs(vol() - 0.8) < 0.001)
G.combat = true; fire("PLAYER_REGEN_DISABLED"); advance(1)
G.combat = false; fire("PLAYER_REGEN_ENABLED"); advance(3)
ns.SetMode(ns.ALL); advance(1.5)
check("free play during the tail restores the volume", math.abs(vol() - 0.8) < 0.001)
ns.SetMode("auto"); advance(5)
-- boss: the theme goes on while adds are alive, then a short 4 s tail
ns.CreatePlaylist("BossPL"); ns.SetInPlaylist("BossPL", "music\\c.mp3", true); ns.Assign("boss", "BossPL")
G.combat = true; fire("ENCOUNTER_START", 1, "Some boss", 1, 5); fire("PLAYER_REGEN_DISABLED"); advance(1)
check("boss music", ns.Player.playlist == "BossPL")
fire("ENCOUNTER_END", 1); advance(2)
check("boss dead, adds still fighting: boss theme goes on", ns.Rules.current == "boss" and ns.Player.playlist == "BossPL")
G.combat = false; fire("PLAYER_REGEN_ENABLED"); advance(3.5)
check("short tail after an encounter: still the boss theme", ns.Player.playlist == "BossPL")
advance(1)
check("short tail is 4 s", ns.Player.playlist == calm)
G.combat = true; fire("PLAYER_REGEN_DISABLED"); advance(1)
G.combat = false; fire("PLAYER_REGEN_ENABLED"); advance(5)
check("a normal fight after a boss uses the long tail again", ns.Player.playlist == "Pulls")
advance(5)
ns.DeletePlaylist("Pulls"); ns.DeletePlaylist("BossPL"); ns.db.fightTail = 4; ns.db.crossfade = false; advance(5)

-- 1.0: weighted shuffle (skips, never heard, recently played)
do
  ns.db.shuffle = true
  local a, b, c = ns.trackById["music\\a.ogg"], ns.trackById["music\\b.ogg"], ns.trackById["music\\c.mp3"]
  ns.PlayFrom(ns.ALL, c); advance(1)
  local before = (ns.db.stats[c.file].skips or 0)
  ns.Player:Next(); advance(0)
  check("Next early in a track counts as a skip", (ns.db.stats[c.file].skips or 0) == before + 1)
  ns.PlayFrom(ns.ALL, c); advance(5)
  local skips = ns.db.stats[c.file].skips
  ns.Player:Next(); advance(0)
  check("Next after 30% of the track is not a skip", ns.db.stats[c.file].skips == skips)
  ns.PlayFrom(ns.ALL, c); advance(10.6)
  check("listening to the end forgives one skip", (ns.db.stats[c.file].skips or 0) == skips - 1)
  ns.db.stats[c.file].skips = 4
  local fake = { file = "music\\never.ogg" }
  wipe(ns.db.history); for i = 1, 30 do table.insert(ns.db.history, "x" .. i) end
  table.insert(ns.db.history, 1, b.file)
  local w = ns.ShuffleWeights({ a, c, fake, b })
  check("weights: skipped < normal < never heard, recent much less", w[2] < w[1] and w[1] < w[3] and w[4] < w[2] + 0.5
    and math.abs(w[3] - 1.5) < 0.001 and math.abs(w[2] - 1 / 3) < 0.001 and w[4] >= 0.1)
  local firstA, firstC = 0, 0
  for _ = 1, 400 do
    wipe(ns.db.history)
    ns.PlayFrom(ns.ALL, nil)
    if ns.Player.track == a then firstA = firstA + 1 elseif ns.Player.track == c then firstC = firstC + 1 end
  end
  check("a track skipped 4 times comes first much less often (" .. firstA .. " vs " .. firstC .. ")", firstC * 1.8 < firstA)
  ns.db.smartShuffle = false
  firstA, firstC = 0, 0
  for _ = 1, 400 do
    ns.PlayFrom(ns.ALL, nil)
    if ns.Player.track == a then firstA = firstA + 1 elseif ns.Player.track == c then firstC = firstC + 1 end
  end
  check("plain shuffle ignores the skips (" .. firstA .. " vs " .. firstC .. ")", firstC * 1.8 > firstA)
  ns.db.smartShuffle = true
  ns.db.stats[c.file].skips = nil
  ns.SetMode("auto"); advance(5)
end

-- 1.0: dungeon-specific music and "Assign here" in the player's menu
do
  -- a fake Menu API root that records what the generator builds
  local function node(text, fn, sel)
    local n = { text = text, fn = fn, sel = sel, kids = {} }
    function n:CreateButton(t, f) local c = node(t, f) table.insert(self.kids, c) return c end
    function n:CreateRadio(t, s2, f) local c = node(t, f, s2) table.insert(self.kids, c) return c end
    function n:CreateTitle(t) local c = node(t) c.title = true table.insert(self.kids, c) return c end
    function n:CreateDivider() end
    return n
  end
  local function find(n, pattern)
    for _, k in ipairs(n.kids) do
      if k.text and tostring(k.text):find(pattern, 1, true) then return k end
    end
  end
  local function menu() local r = node() KalimdorZugZugRadioFrame.dropdown._gen(nil, r) return r end

  ns.CreatePlaylist("RFC"); ns.SetInPlaylist("RFC", "music\\a.ogg", true)
  ns.CreatePlaylist("Dgn"); ns.SetInPlaylist("Dgn", "music\\b.ogg", true)
  ns.Assign("dungeon", "Dgn"); ns.SetMode("auto"); advance(5)
  local r = menu()
  check("open world: Assign here shows the zone", find(r, "Zone: Durotar") ~= nil and not find(r, "Dungeon:"))
  G.instance = "party"; G.instanceName = "Ragefire Chasm"; G.instanceID = 389
  fire("PLAYER_ENTERING_WORLD", false, false); advance(1)
  check("dungeon remembered", ns.Rules.dungeonID == 389 and ns.db.seenDungeons[389] == "Ragefire Chasm")
  check("generic dungeon playlist", ns.Player.playlist == "Dgn")
  r = menu()
  local d = find(r, "Dungeon: Ragefire Chasm")
  check("in a dungeon: Assign here shows the dungeon, not the zone", d ~= nil and not find(r, "Zone:"))
  ns.SetMode("RFC"); advance(1)
  r = menu(); d = find(r, "Dungeon: Ragefire Chasm")
  local use = find(d, "Use the current playlist")
  check("one click offers the current playlist", use ~= nil and use.text:find("RFC", 1, true) ~= nil)
  use.fn()
  check("dungeon-specific playlist assigned", ns.db.dungeons[389] and ns.db.dungeons[389].playlist == "RFC")
  ns.SetMode("auto"); advance(1)
  check("dungeon-specific playlist wins over the generic one", ns.Player.playlist == "RFC")
  G.combat = true; fire("ENCOUNTER_START", 1443, "Taragaman", 1, 5); fire("PLAYER_REGEN_DISABLED"); advance(1)
  fire("ENCOUNTER_END", 1443); G.combat = false; fire("PLAYER_REGEN_ENABLED"); advance(6)
  r = menu()
  local b = find(r, "Boss: Taragaman")
  check("the last boss met is offered after the fight", b ~= nil)
  find(b, "Dgn (").fn()
  check("boss-specific playlist from the player's menu", ns.db.bosses[1443] and ns.db.bosses[1443].playlist == "Dgn")
  find(find(menu(), "Dungeon: Ragefire"), "None (use the general one)").fn(); advance(1)
  check("dungeon back to the generic playlist", ns.db.dungeons[389] == nil and ns.Player.playlist == "Dgn")
  ns.AssignDungeon(389, "RFC")
  ns.NewCharacterProfile()
  check("new profile copies dungeon playlists", ns.db.dungeons[389] and ns.db.dungeons[389].playlist == "RFC")
  ns.SetCharacterProfile(ns.DEFAULT_PROFILE)
  G.instance = "none"; G.instanceName = nil; G.instanceID = nil
  fire("PLAYER_ENTERING_WORLD", false, false); advance(5)
  check("leaving the dungeon forgets it and its last boss", ns.Rules.dungeonID == nil and ns.Rules.lastBossID == nil)
  ns.AssignBoss(1443, nil); ns.AssignDungeon(389, nil)
  ns.DeletePlaylist("RFC"); ns.DeletePlaylist("Dgn"); advance(5)
end

-- 1.0: zone-music breaks (option, off by default)
do
  local P = ns.Player
  check("zone breaks are off by default", ns.db.zoneBreaks == false)
  ns.db.zoneBreaks = true; ns.db.zoneBreakEvery = 2; ns.db.zoneBreakMinutes = 1
  ns.SetMode("auto"); advance(5)
  check("calm condition for the break test", P.CALM[ns.Rules.current] == true)
  P.sinceBreak = 0; P:Play(); advance(10.6)
  check("first track ended: next one plays", playing ~= nil and not P:InZoneBreak())
  advance(10.6)
  check("every 2 tracks: the zone music plays", P:InZoneBreak() and playing == nil)
  check("the player shows the break", KalimdorZugZugRadioFrame.title:GetText() == ns.L.ZONE_BREAK_TITLE)
  advance(30)
  check("the rules don't restart the music during the break", P:InZoneBreak() and playing == nil)
  advance(31)
  check("after 1 min our music comes back", not P:InZoneBreak() and playing ~= nil)
  ns.CreatePlaylist("BreakFight"); ns.SetInPlaylist("BreakFight", "music\\c.mp3", true); ns.Assign("combat", "BreakFight")
  advance(1)
  P.sinceBreak = 1; P:Play(); advance(10.6)
  check("break again", P:InZoneBreak())
  G.combat = true; fire("PLAYER_REGEN_DISABLED"); advance(1)
  check("a fight ends the break at once", not P:InZoneBreak() and playing ~= nil and ns.Rules.current == "combat")
  G.combat = false; fire("PLAYER_REGEN_ENABLED"); advance(6)
  P.sinceBreak = 1; P:Play(); advance(10.6)
  P:Toggle()
  check("Play ends the break", not P:InZoneBreak() and P.playing)
  P.sinceBreak = 1; P:Play(); advance(10.6)
  ns.SetMode(ns.ALL); advance(1)
  check("choosing a playlist ends the break", not P:InZoneBreak() and P.playing)
  advance(30)
  check("no breaks in free play", P.playing)
  ns.SetMode("auto"); advance(5)
  P.sinceBreak = 1; P:Play(); advance(10.6)
  ns.db.zoneBreaks = false; P:EndZoneBreak(); ns.Rules:Evaluate(true); advance(1)
  check("turning the option off brings the music back", not P:InZoneBreak() and P.playing)
  ns.db.zoneBreakEvery, ns.db.zoneBreakMinutes = 3, 2
  ns.DeletePlaylist("BreakFight"); advance(5)
end

-- 1.0: presets of the game music catalog (ready-made playlists)
check("preset tracks of a condition", #ns.PresetTrackIds("town") == 1 and ns.PresetTrackIds("town")[1] == "game:53198"
  and #ns.PresetTrackIds("boss") == 0)
do
  local saved = KZZR_GameMusic
  KZZR_GameMusic = nil
  assert(load(SRC.GameMusic, "GameMusic"))()
  local n, bad, keys = 0, {}, {}
  for _, g in ipairs(KZZR_GameMusic) do
    n = n + 1
    if g.preset then keys[g.preset] = (keys[g.preset] or 0) + 1 end
    if not g.preset or not ns.SITUATION_BY_KEY[g.preset] then bad[#bad + 1] = g.title end
  end
  check("every track of GameMusic.lua has a valid preset (" .. n .. " tracks"
    .. (#bad > 0 and ("; bad: " .. table.concat(bad, ", ")) or "") .. ")", n > 500 and #bad == 0)
  check("presets cover the main conditions", keys.combat and keys.boss and keys.town and keys.dungeon and keys.idle
    and keys.night and keys.campfire and keys.dead and keys.levelup)
  KZZR_GameMusic = saved
end

-- 1.0: onboarding (shown once, ready-made playlists, never overwrites)
do
  local O = ns.Onboarding
  local win = KalimdorZugZugOnboarding
  check("the guide opened by itself at the first login", win ~= nil and win:IsShown())
  rawget(win, "_OnHide")(win)
  check("closing the guide marks it as seen", ns.db.onboardingSeen == true)
  local idleBefore = ns.db.assign.idle
  ns.db.assign.town = nil
  SlashCmdList.KZZRADIO("tutorial")
  check("/kzz tutorial opens it again", O:IsShown())
  O.source = "game"; O:Refresh(); O:Go(4); O:Next()
  local name = O.PresetName("town")
  local pl = ns.GetPlaylist(name)
  check("finish creates the ready-made playlist", pl ~= nil and #pl.tracks == 1 and pl.tracks[1].file == "game:53198")
  check("and assigns it to its condition", ns.db.assign.town == name)
  check("conditions that had a playlist keep it", ns.db.assign.idle == idleBefore)
  check("presets don't overwrite: running it again creates nothing", O.CreatePresets({ "town" }) == 0
    and ns.db.assign.town == name and #ns.GetPlaylist(name).tracks == 1)
  ns.SetInPlaylist(name, "game:8158670", true)
  O.CreatePresets({ "town" })
  check("a ready-made playlist edited by the user is kept as it is", #ns.GetPlaylist(name).tracks == 2)
  check("the settings have a Tutorial button", ns.Settings and KalimdorZugZugSettingsPanel ~= nil)
  ns.DeletePlaylist(name); advance(5)
  -- playlists pointing to music the library no longer has
  local before = ns.MissingUserTracks()
  ns.CreatePlaylist("Lost"); table.insert(ns.db.playlists.Lost, "music/gone.ogg"); table.insert(ns.db.playlists.Lost, "game:1")
  check("missing user tracks are counted (game ids ignored)", ns.MissingUserTracks() == before + 1)
  ns.DeletePlaylist("Lost"); advance(1)
end

-- death in a dungeon boss fight, ghost run outside, back in and alive: dungeon music again
do
  ns.db.fightTail = 8; ns.db.crossfade = true
  ns.CreatePlaylist("RDgn"); ns.SetInPlaylist("RDgn", "game:8158670", true); ns.Assign("dungeon", "RDgn")
  ns.CreatePlaylist("RDead"); ns.SetInPlaylist("RDead", "game:53198", true); ns.Assign("dead", "RDead")
  ns.CreatePlaylist("RFight"); ns.SetManyInPlaylist("RFight", {"music\\c.mp3"}, true); ns.Assign("combat", "RFight")
  G.instance = "party"; G.instanceName = "Ragefire Chasm"; G.instanceID = 389
  fire("PLAYER_ENTERING_WORLD", false, false); advance(6)
  check("death test: dungeon music", ns.Rules.current == "dungeon")
  ns.CreatePlaylist("RBoss"); ns.SetInPlaylist("RBoss", "game:53198", true); ns.Assign("boss", "RBoss")
  G.combat = true; fire("ENCOUNTER_START", 1443, "Oggleflint", 1, 5); fire("PLAYER_REGEN_DISABLED"); advance(3)
  check("death test: boss music", ns.Player.playlist == "RBoss")
  G.dead = true; fire("PLAYER_DEAD"); advance(0.5); G.combat = false; fire("PLAYER_REGEN_ENABLED"); advance(1); fire("ENCOUNTER_END", 1443, "Oggleflint", 1, 5, 0); advance(12)
  check("dead in the fight: dead music", ns.Rules.current == "dead" and ns.Player.playlist == "RDead")
  fire("PLAYER_ALIVE"); advance(2) -- released: ghost
  G.instance = "none"; G.instanceName = nil; G.instanceID = nil
  fire("PLAYER_ENTERING_WORLD", false, false); advance(30)
  check("ghost outside the dungeon: still dead music", ns.Player.playlist == "RDead")
  G.instance = "party"; G.instanceName = "Ragefire Chasm"; G.instanceID = 389
  fire("PLAYER_ENTERING_WORLD", false, false); advance(1)
  G.dead = false; fire("PLAYER_UNGHOST"); advance(10)
  check("alive again in the dungeon: dungeon music, still automatic", ns.Rules.current == "dungeon"
    and ns.Player.playlist == "RDgn" and ns.db.mode == "auto" and math.abs(tonumber(musicVolume) - 0.8) < 0.001)
  for _, n in ipairs({ "RDgn", "RDead", "RFight", "RBoss" }) do ns.DeletePlaylist(n) end
  G.instance = "none"; G.instanceName = nil; G.instanceID = nil
  fire("PLAYER_ENTERING_WORLD", false, false)
  ns.db.fightTail = 4; ns.db.crossfade = false; advance(6)
end

-- key bindings
check("binding names defined", BINDING_HEADER_KZZR == "Kalimdor ZugZug Radio" and BINDING_NAME_KZZR_PLAY ~= nil)
local v0 = ns.Player:GetVolume(); KZZR_Binding("voldown")
check("binding: volume down", math.abs(ns.Player:GetVolume() - (v0 - 0.1)) < 0.01)
KZZR_Binding("volup"); KZZR_Binding("favorite"); KZZR_Binding("favorite")

-- compact player
ns.UI:Toggle(true)
ns.UI:SetCompact(true)
check("compact player shown, full player hidden", KalimdorZugZugRadioCompact:IsShown() and not KalimdorZugZugRadioFrame:IsShown())
ns.UI:SetCompact(false)
check("back to the full player", KalimdorZugZugRadioFrame:IsShown() and not KalimdorZugZugRadioCompact:IsShown())

-- translations: every language has all the English keys with the same placeholders
local function placeholders(str) local n = 0; for _ in str:gmatch("%%[sd]") do n = n + 1 end; return n end
for _, code in ipairs(ns.LANG_ORDER) do
  local missing, bad = {}, {}
  for key, en in pairs(ns.LOCALES.enUS) do
    local v = ns.LOCALES[code][key]
    if v == nil then missing[#missing + 1] = key
    elseif placeholders(v) ~= placeholders(en) then bad[#bad + 1] = key end
  end
  check(code .. " complete" .. (#missing > 0 and (" (missing: " .. table.concat(missing, ",") .. ")") or "")
    .. (#bad > 0 and (" (placeholders: " .. table.concat(bad, ",") .. ")") or ""), #missing == 0 and #bad == 0)
end
clientLocale = "deDE"; ns.InitLanguage(nil)
check("language from the client (deDE)", ns.lang == "deDE" and ns.L.SIT_combat == "Kampf" and not ns.useAddonFont)
clientLocale = "enGB"; ns.InitLanguage(nil)
check("enGB -> enUS", ns.lang == "enUS")
clientLocale = "enUS"; ns.InitLanguage("jaJP")
check("Japanese on an enUS client: addon font, chat in English", ns.useAddonFont and ns.chatLang == "enUS" and ns.L.SIT_boss == "ボス" and ns.CL.SIT_boss == "Boss")
check("addon font created", ns.Font("GameFontNormalSmall") == "KZZR_GameFontNormalSmall")
clientLocale = "zhCN"; ns.InitLanguage(nil)
check("zhCN on a zhCN client: game font", ns.lang == "zhCN" and not ns.useAddonFont and ns.chatLang == "zhCN")
clientLocale = "koKR"; ns.InitLanguage(nil)
check("koKR client -> Korean with the game font", ns.lang == "koKR" and ns.L.SIT_boss == "보스" and not ns.useAddonFont
  and ns.chatLang == "koKR" and ns.Font("GameFontNormalSmall") == "GameFontNormalSmall")
clientLocale = "enUS"; ns.InitLanguage("koKR")
check("Korean on an enUS client: Nanum Gothic, chat in English", ns.useAddonFont and ns.uiFont == "ko"
  and ns.chatLang == "enUS" and ns.CL.SIT_boss == "Boss"
  and ns.Font("GameFontNormalSmall") == "KZZR_KO_GameFontNormalSmall"
  and ns.Font("GameFontNormalSmall", ns.TextFont("夜に駆ける")) == "KZZR_GameFontNormalSmall")
clientLocale = "zhCN"; ns.InitLanguage("koKR")
check("Korean on a Chinese client still uses Nanum Gothic", ns.uiFont == "ko")
clientLocale = "koKR"; ns.InitLanguage("zhCN")
check("Chinese on a Korean client uses KZZR Sans", ns.uiFont == "cjk")
clientLocale = "koKR"; ns.InitLanguage("jaJP")
check("Japanese on a Korean client uses KZZR Sans", ns.uiFont == "cjk")
clientLocale = "enUS"; ns.InitLanguage(nil)
SlashCmdList.KZZRADIO("lang ko"); check("/kzz lang ko", ns.db.lang == "koKR")
SlashCmdList.KZZRADIO("lang auto")
ns.InitLanguage("esMX")
check("esMX inherits from esES", ns.L.SIT_campfire == "Fogata" and ns.L.SIT_combat == "Combate")
clientLocale = "enUS"; ns.InitLanguage(nil)
SlashCmdList.KZZRADIO("lang ja"); check("/kzz lang ja", ns.db.lang == "jaJP")
SlashCmdList.KZZRADIO("lang auto"); check("/kzz lang auto", ns.db.lang == nil)
SlashCmdList.KZZRADIO("help")
SlashCmdList.KZZRADIO("debug")
clientLocale = "enUS"; ns.InitLanguage(nil)
check("Japanese text on an enUS client -> addon font", ns.TextFont("夜に駆ける") == "cjk" and not ns.TextFont("Ado - Café"))
check("CJK font forced even with an English UI", ns.Font("GameFontHighlightSmall", ns.TextFont("ナニダト")) == "KZZR_GameFontHighlightSmall")
check("Latin punctuation keeps the game font", not ns.TextFont("Don’t Stop — Live…") and not ns.TextFont("Plain ASCII"))
check("symbols the game font lacks -> KZZR Sans", ns.TextFont("↑↓←→BBAB") == "cjk" and ns.TextFont("Love ❤ ✨") == "cjk" and ns.TextFont("k1ll◎iLL") == "cjk"
  and ns.TextFont("ΛSHES") == "cjk" and ns.TextFont("Shōwa 59") == "cjk" and ns.TextFont("ＡＢＣ") == "cjk")
check("Cyrillic -> KZZR Sans", ns.TextFont("Кино") == "cjk")
check("Korean hangul -> Nanum Gothic", ns.TextFont("뉴진스") == "ko" and ns.TextFont("NewJeans (뉴진스) - Hype Boy") == "ko"
  and ns.TextFont("ㅋㅋ") == "ko")
check("Korean font object", ns.Font("GameFontHighlightSmall", "ko") == "KZZR_KO_GameFontHighlightSmall"
  and ns.Font("GameFontHighlightSmall", true) == "KZZR_GameFontHighlightSmall")
do
  local fs = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ns.SetText(fs, "뉴진스", "GameFontHighlightSmall")
  local ko = fs.kzzFont == _G.KZZR_KO_GameFontHighlightSmall
  ns.SetText(fs, "夜に駆ける", "GameFontHighlightSmall")
  local ja = fs.kzzFont == _G.KZZR_GameFontHighlightSmall
  ns.SetText(fs, "Hype Boy", "GameFontHighlightSmall")
  check("SetText switches between Korean, Japanese and game fonts", ko and ja and fs.kzzFont == _G.GameFontHighlightSmall)
end
clientLocale = "zhCN"; ns.InitLanguage(nil)
check("on a Chinese client the game fonts are used", not ns.TextFont("夜に駆ける") and not ns.TextFont("↑↓"))
check("on a Chinese client hangul still uses Nanum Gothic", ns.TextFont("뉴진스") == "ko")
clientLocale = "koKR"; ns.InitLanguage(nil)
check("on a Korean client the game fonts are used", not ns.TextFont("뉴진스") and not ns.TextFont("夜に駆ける"))
clientLocale = "ruRU"; ns.InitLanguage(nil)
check("on a Russian client Cyrillic keeps the game font", not ns.TextFont("Кино") and ns.TextFont("夜") == "cjk")
clientLocale = "enUS"; ns.InitLanguage(nil)
-- 0.8: the user's library lives in the KalimdorZugZugRadio_Library data addon (KZZR_UserLibrary)
KZZR_UserLibrary = { addon = "KalimdorZugZugRadio_Library", tracks = {
  { file = "music\\u.ogg", folder = "", title = "U", duration = 10, cover = "covers\\x.png" },
} }
ns.LoadLibrary()
local u = ns.trackById["music\\u.ogg"]
check("user library loaded from the data addon", ns.LIB_ROOT == "Interface\\AddOns\\KalimdorZugZugRadio_Library\\"
  and u ~= nil and not ns.trackById["music\\a.ogg"]
  and ns.CoverOf(u) == "Interface\\AddOns\\KalimdorZugZugRadio_Library\\covers\\x.png")
ns.PlayFrom(ns.ALL, u)
check("tracks play from the data addon", playing == "Interface\\AddOns\\KalimdorZugZugRadio_Library\\music\\u.ogg")
KZZR_UserLibrary = nil
ns.LoadLibrary()
check("library imported before 0.8: still read from the addon folder",
  ns.LIB_ROOT == "Interface\\AddOns\\KalimdorZugZugRadio\\" and ns.trackById["music\\a.ogg"] ~= nil)
-- 1.0 block 7: smart playlists, albums/artists, "Play next" queue, status line
do
  local a, b, c = ns.trackById["music\\a.ogg"], ns.trackById["music\\b.ogg"], ns.trackById["music\\c.mp3"]
  local orgri = ns.trackById["game:53198"]
  ns.SetEnabled(true); ns.SetMode("auto"); ns.db.shuffle = false; ns.Player:SetShuffle(false); ns.ClearQueue()
  wipe(ns.db.stats); wipe(ns.db.favorites); wipe(ns.db.excluded)
  ns.CreatePlaylist("Explore")
  local name = ns.SaveSmartPlaylist(nil, "Rocky", { match = "all", rules = { { field = "folder", op = "has", value = "rock" } } })
  local pl = ns.GetPlaylist("Rocky")
  check("smart playlist: folder contains", name == "Rocky" and #pl.tracks == 1 and pl.tracks[1] == c and ns.IsSmart("Rocky"))
  check("smart playlist listed with the others", (function()
    for _, n in ipairs(ns.AllPlaylistNames()) do if n == "Rocky" then return true end end end)())
  local _, err = ns.SaveSmartPlaylist(nil, "explore", { rules = {} })
  check("smart playlist name must be unique", err == "ERR_EXISTS")
  ns.SaveSmartPlaylist(nil, "AnyOf", { match = "any", rules = { { field = "artist", op = "is", value = "x" },
    { field = "source", op = "is", value = "game" } } })
  local any = ns.GetPlaylist("AnyOf").tracks
  check("smart playlist: match any (artist X or game music)", #any == 3 and ns.GetPlaylist("AnyOf").has[a.file]
    and ns.GetPlaylist("AnyOf").has["game:53198"] and not ns.GetPlaylist("AnyOf").has[b.file])
  ns.db.stats[b.file] = { plays = 3, seconds = 30 }
  ns.db.favorites[c.file] = true
  ns.SaveSmartPlaylist(nil, "Played", { rules = { { field = "plays", op = "ge", value = "2" }, { field = "source", op = "is", value = "mine" } } })
  ns.SaveSmartPlaylist(nil, "FavNew", { rules = { { field = "favorite", op = "yes" }, { field = "minutes", op = "le", value = "1" } } })
  check("smart playlist: plays at least / favourite + length", #ns.GetPlaylist("Played").tracks == 1
    and ns.GetPlaylist("Played").tracks[1] == b and #ns.GetPlaylist("FavNew").tracks == 1 and ns.GetPlaylist("FavNew").tracks[1] == c)
  ns.SaveSmartPlaylist(nil, "Fresh", { rules = { { field = "never", op = "yes" }, { field = "source", op = "isnot", value = "podcast" },
    { field = "title", op = "not", value = "hyjal" } } })
  local fresh = ns.GetPlaylist("Fresh")
  check("smart playlist: never played, source is not, title doesn't contain", not fresh.has[b.file] and fresh.has[a.file]
    and fresh.has["game:53198"] and not fresh.has["game:8158670"] and not fresh.has["ep:k1"])
  ns.Assign("night", "Rocky")
  ns.db.zones[999] = { playlist = "Rocky", name = "Somewhere" }
  local renamed = ns.SaveSmartPlaylist("Rocky", "Rock only", { rules = { { field = "folder", op = "is", value = "rock" } } })
  check("renaming a smart playlist moves its assignments", renamed == "Rock only" and ns.db.assign.night == "Rock only"
    and ns.db.zones[999].playlist == "Rock only" and not ns.GetPlaylist("Rocky") and #ns.GetPlaylist("Rock only").tracks == 1)
  ns.DeletePlaylist("Rock only")
  check("deleting a smart playlist clears its assignments", ns.db.assign.night == nil and ns.db.zones[999] == nil
    and not ns.IsSmart("Rock only"))
  ns.db.favorites[c.file] = nil
  ns.SetMode("Fresh")
  check("a smart playlist plays in free play", ns.Player.playlist == "Fresh" and playing ~= nil)
  ns.SetMode("auto")
  for _, n in ipairs({ "AnyOf", "Played", "FavNew", "Fresh" }) do ns.DeletePlaylist(n) end

  -- genre, composer, year (from the tags)
  ns.SaveSmartPlaylist(nil, "Eighties", { rules = { { field = "year", op = "ge", value = "1980" },
    { field = "year", op = "le", value = "1984" } } })
  ns.SaveSmartPlaylist(nil, "ByComposer", { rules = { { field = "composer", op = "has", value = "yama" },
    { field = "genre", op = "is", value = "city pop" } } })
  check("smart playlist: year range (tracks without a year left out), composer + genre",
    #ns.GetPlaylist("Eighties").tracks == 1 and ns.GetPlaylist("Eighties").tracks[1] == a
    and #ns.GetPlaylist("ByComposer").tracks == 1 and ns.GetPlaylist("ByComposer").tracks[1] == b)
  ns.DeletePlaylist("Eighties"); ns.DeletePlaylist("ByComposer")
  local genres = ns.Groups(ns.tracks, "genre")
  check("genre view: City Pop and unknown genre", #genres == 2 and genres[1].label == "City Pop" and genres[1].count == 2
    and genres[2].label == "Unknown genre")
  local cityPop = ns.GetPlaylist(ns.GroupPlaylistName("genre", a))
  check("tracks in album order (track number before title)", cityPop.tracks[1] == b and cityPop.tracks[2] == a)
  check("search finds the genre and the composer", a._search:find("city pop", 1, true) and b._search:find("yamashita", 1, true))

  -- albums and artists
  local albumName = ns.GroupPlaylistName("album", orgri)
  check("album playlist of a game track", ns.GetPlaylist(albumName) and #ns.GetPlaylist(albumName).tracks == 1
    and ns.PlaylistLabel(albumName) == "Orgrimmar")
  local artists = ns.Groups(ns.tracks, "artist")
  check("artists of the library (unknown artist grouped)", #artists == 2 and artists[1].label == "Unknown artist"
    and artists[1].count == 2 and artists[2].label == "X")
  check("podcasts are left out of the album view", #ns.Groups(ns.episodes, "album") == 0)
  ns.SetMode(ns.GroupPlaylistName("artist", a))
  check("an artist plays as a playlist", ns.Player.playlist == "__artist:x" and is("a.ogg")
    and ns.FindPlaylist("__artist:x") == "__artist:x")
  ns.SetMode("auto")

  -- "Play next" queue
  ns.PlayFrom(ns.ALL, b) -- library order: b (track 1), a (track 2), c
  ns.QueueTracks({ orgri }, true)
  check("queued track listed", #ns.QueuedTracks() == 1 and ns.QueuedTracks()[1] == orgri)
  ns.Player:Next()
  check("Next plays the queued track", playing == 53198 and ns.Player.fromQueue and #ns.db.upNext == 0)
  ns.Player:Next()
  check("then the playlist goes on after the track it was on", is("a.ogg") and not ns.Player.fromQueue)
  ns.QueueTracks({ orgri, ns.trackById["game:8158670"] }, false)
  ns.QueueTracks({ c }, true)
  check("Play next goes before what is queued", ns.db.upNext[1] == c.file and #ns.db.upNext == 3)
  ns.Player:Next()
  check("queued track from the same playlist", is("c.mp3") and ns.Player.fromQueue)
  ns.Player:Prev()
  check("Prev on a queued track goes back to the playlist's track", is("a.ogg") and not ns.Player.fromQueue)
  ns.UnqueueTrack(orgri)
  check("a track can be taken out of the queue", #ns.db.upNext == 1 and ns.db.upNext[1] == "game:8158670")
  advance(11) -- a ends by itself: the queue goes first
  check("end of a track plays the queue", playing == 8158670)
  ns.ClearQueue()
  ns.SetMode("auto")
  ns.Assign("combat", "Fight")
  G.combat = true; fire("PLAYER_REGEN_DISABLED")
  ns.QueueTracks({ orgri }, false)
  advance(11)
  check("the queue waits during a fight", ns.Player.playlist == "Fight" and playing ~= 53198 and #ns.db.upNext == 1)
  G.combat = false; fire("PLAYER_REGEN_ENABLED"); advance(10)
  ns.ClearQueue()

  -- status line
  check("status line: no repeated condition", ns.UI.AutoStatus("campfire", "Fire") == "Auto  ·  Campfire  ·  Fire"
    and ns.UI.AutoStatus("campfire", nil) == "Auto  ·  Campfire")
  ns.CreatePlaylist("OST - Campfire")
  check("status line: playlist named after the condition", ns.UI.AutoStatus("campfire", "OST - Campfire") == "Auto  ·  OST - Campfire")
  ns.DeletePlaylist("OST - Campfire")

  -- library window: views and the smart editor build without errors
  ns.LibraryUI:Toggle(true)
  local ok = pcall(function()
    ns.LibraryUI.view = "album"; ns.LibraryUI:Refresh()
    ns.LibraryUI.view = "artist"; ns.LibraryUI:Refresh()
    ns.LibraryUI.view = "genre"; ns.LibraryUI:Refresh()
    ns.LibraryUI.view = "tracks"; ns.LibraryUI:Refresh()
    ns.LibraryUI:OpenSmartEditor(nil)
  end)
  check("library views and smart editor", ok)
  ns.LibraryUI:Toggle(false)
end
do
  -- a shared playlist can't smuggle WoW escape codes (|c colors, |H links) or control characters
  local evil = "!KZZR1!" .. ns.Base64Encode("|cffff0000Fake|r\r|Hurl:x|hlink|h\nmusic\\a.ogg")
  local name = ns.ImportPlaylist(evil)
  check("imported name: escape codes neutralized", name == "||cffff0000Fake||r||Hurl:x||hlink||h")
  check("typed '||' stays a single literal pipe", ns.CreatePlaylist("Rock || Metal") == "Rock || Metal")
  -- removing an id the library no longer has still works
  table.insert(ns.db.playlists[name], "music\\gone.ogg")
  ns.SetInPlaylist(name, "music\\gone.ogg", false)
  local left = false
  for _, id in ipairs(ns.db.playlists[name]) do if id == "music\\gone.ogg" then left = true end end
  check("missing track can be removed from a playlist", not left)
  ns.DeletePlaylist(name); ns.DeletePlaylist("Rock || Metal")
end
-- movable banner: move mode keeps it visible, the position is saved and can be reset
do
  ns.Banner:SetMoving(true)
  check("banner move mode shows the banner", ns.Banner:IsMoving() and ns.Banner:IsShown())
  advance(10)
  check("banner stays visible while moving", ns.Banner:IsShown())
  ns.db.ui.bannerPos = { "CENTER", "CENTER", 10, 20 }
  ns.Banner:Show(ns.trackById["game:8158670"])
  check("banner keeps showing in move mode on a new track", ns.Banner:IsMoving())
  ns.Banner:ToggleMoving()
  check("banner move mode ends", not ns.Banner:IsMoving())
  ns.db.ui.bannerPos = nil
end
check("no startup errors", #ns.startupErrors == 0)
print(fails == 0 and "ALL TESTS PASSED" or (fails .. " TESTS FAILED"))
