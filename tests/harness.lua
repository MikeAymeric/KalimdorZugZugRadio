-- Stub minimale delle API WoW per testare la logica dell'addon fuori dal gioco.
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
function GetUnitSpeed() return G.speed end
function UnitClassification() return G.class end
function UnitCanAttack() return true end
function issecretvalue() return false end
C_UnitAuras = { GetPlayerAuraBySpellID = function(id)
  if G.combat then error("Auras cannot be accessed when secret") end
  return G.auras[id] and { spellId = id } or nil
end }
C_CVar = { GetCVar = function() return "1" end }
playing = nil
function PlayMusic(p) playing = p end
function StopMusic() playing = nil end
function fire(e, ...)
  for _, f in ipairs(eventFrames[e] or {}) do rawget(f, "_OnEvent")(f, e, ...) end
end

KZZR_Library = { tracks = {
  { file = "music\\a.ogg", folder = "", title = "A", artist = "X", duration = 10 },
  { file = "music\\b.ogg", folder = "", title = "B", duration = 10 },
  { file = "music\\c.mp3", folder = "Rock", title = "C", duration = 10 },
} }

local ns = {}
for _, f in ipairs({ "Locales", "Core", "Player", "Rules", "UI", "LibraryUI", "Settings", "Minimap" }) do
  assert(load(SRC[f], f))("KalimdorZugZugRadio", ns)
end
local fails = 0
local function check(label, cond)
  if not cond then fails = fails + 1 end
  print((cond and "PASS " or "FAIL ") .. label .. (cond and "" or
    ("   playing=" .. tostring(playing) .. " pl=" .. tostring(ns.Player.playlist) .. " cur=" .. tostring(ns.Rules.current))))
end
local function is(name) return playing ~= nil and playing:find(name, 1, true) ~= nil end

fire("ADDON_LOADED", "KalimdorZugZugRadio"); fire("PLAYER_LOGIN"); fire("PLAYER_ENTERING_WORLD", true, false)
check("nessuna assegnazione -> silenzio", playing == nil)
ns.db.shuffle = false
assert(ns.CreatePlaylist("Esplora")); assert(ns.CreatePlaylist("Botte"))
check("nome duplicato rifiutato", ns.CreatePlaylist("esplora") == nil)
ns.SetInPlaylist("Esplora", "music\\a.ogg", true); ns.SetInPlaylist("Esplora", "music\\b.ogg", true)
ns.SetManyInPlaylist("Botte", { "music\\c.mp3" }, true)
ns.Assign("idle", "Esplora"); ns.Assign("combat", "Botte")
check("nessuna condizione suona Esplora", is("music\\a.ogg"))
G.combat = true; fire("PLAYER_REGEN_DISABLED")
check("combattimento immediato -> Botte", is("c.mp3"))
G.combat = false; fire("PLAYER_REGEN_ENABLED"); advance(1)
check("ritorno ritardato", is("c.mp3"))
advance(5)
check("torna a Esplora e riparte A", is("a.ogg"))
advance(11)
check("avanza da solo a B", is("b.ogg"))

ns.CreatePlaylist("Fuoco"); ns.SetInPlaylist("Fuoco", "music\\c.mp3", true); ns.Assign("campfire", "Fuoco")
G.auras[1283391] = true; fire("UNIT_AURA", "player")
check("solo Campfire Nearby -> niente campfire", playing and not is("c.mp3"))
G.auras[1229739] = true; fire("UNIT_AURA", "player")
check("entrambe le aure -> campfire", is("c.mp3"))
G.auras[1229739] = nil; fire("UNIT_AURA", "player"); advance(20)
check("Welcoming scaduta, campfire resta", ns.Rules.current == "campfire")
G.speed = 7; advance(1.1); G.speed = 0; advance(5)
check("movimento chiude campfire", ns.Rules.current == "idle")
G.auras[1283391] = nil; fire("UNIT_AURA", "player")

ns.PlayFrom(ns.ALL, ns.trackById["music\\c.mp3"])
check("riproduzione libera dal brano C", is("c.mp3") and ns.db.mode == ns.ALL)
G.combat = true; fire("PLAYER_REGEN_DISABLED")
check("riproduzione libera ignora il combattimento", ns.Player.playlist == ns.ALL)
G.combat = false; fire("PLAYER_REGEN_ENABLED")
ns.SetMode("auto"); advance(5)
check("torna ad automatico", ns.Rules.current == "idle")

ns.Player:Stop(true); G.combat = true; fire("PLAYER_REGEN_DISABLED")
check("stop dell'utente rispettato", playing == nil)
ns.Player:Toggle(); check("play riprende col combattimento", is("c.mp3"))
G.combat = false; fire("PLAYER_REGEN_ENABLED"); advance(5)

ns.RenamePlaylist("Esplora", "Giro")
check("rinomina mantiene l'assegnazione", ns.db.assign.idle == "Giro" and ns.Player.playlist == "Giro")
ns.DeletePlaylist("Giro"); advance(5)
check("elimina -> silenzio", playing == nil and ns.db.assign.idle == nil)

ns.Assign("idle", "Botte"); ns.SetInPlaylist("Botte", "music\\a.ogg", true)
ns.SetInPlaylist("Botte", "music\\c.mp3", false)
check("tolto il brano in corso -> passa a un altro", is("a.ogg"))

ns.LibraryUI:Toggle(true); ns.LibraryUI:Refresh(); ns.UI:Refresh(); ns.UI:RefreshProgress()
SlashCmdList.KZZRADIO("status"); SlashCmdList.KZZRADIO("playlist tutti"); SlashCmdList.KZZRADIO("shuffle")
check("/kzz playlist tutti", ns.db.mode == ns.ALL)
-- minimappa / addon compartment
local uiShown = KalimdorZugZugRadioFrame:IsShown()
KZZR_OnCompartmentClick("KalimdorZugZugRadio", "LeftButton")
check("compartment clic sinistro -> player", KalimdorZugZugRadioFrame:IsShown() ~= uiShown)
local libShown = KalimdorZugZugLibraryFrame:IsShown()
KZZR_OnCompartmentClick("KalimdorZugZugRadio", "RightButton")
check("compartment clic destro -> libreria", KalimdorZugZugLibraryFrame:IsShown() ~= libShown)
local wasPlaying = ns.Player.playing
shift = true; KZZR_OnCompartmentClick("KalimdorZugZugRadio", "LeftButton"); shift = false
check("shift+clic -> play/stop", ns.Player.playing ~= wasPlaying)
KZZR_OnCompartmentEnter("KalimdorZugZugRadio", stub()); KZZR_OnCompartmentLeave()
SlashCmdList.KZZRADIO("minimap")
check("/kzz minimap nasconde", ns.db.minimap.hide == true)
-- impostazioni: condizioni attivabili e apertura del pannello
ns.SetMode("auto"); ns.Assign("idle", "Botte"); advance(5)
check("auto con Nessuna condizione = Botte", is("a.ogg"))
ns.SetConditionEnabled("idle", false); advance(5)
check("condizione disattivata -> silenzio", playing == nil and ns.PlaylistFor("idle") == nil)
ns.SetConditionEnabled("idle", true); advance(5)
check("condizione riattivata -> riprende", is("a.ogg"))
ns.db.disabled.combat = true; G.combat = true; fire("PLAYER_REGEN_DISABLED")
check("combattimento disattivato non interrompe", is("a.ogg"))
G.combat = false; fire("PLAYER_REGEN_ENABLED"); ns.db.disabled.combat = nil
ctrl = true; KZZR_OnCompartmentClick("KalimdorZugZugRadio", "LeftButton"); ctrl = false
check("ctrl+clic apre le impostazioni", settingsOpened == "Kalimdor ZugZug Radio")
settingsOpened = nil; SlashCmdList.KZZRADIO("config")
check("/kzz config apre le impostazioni", settingsOpened == "Kalimdor ZugZug Radio")
settingsOpened = nil; G.combat = true; SlashCmdList.KZZRADIO("config"); G.combat = false
check("in combattimento non apre", settingsOpened == nil)
blizzardSettingsWorks = false; rawset(SettingsPanel, "_shown", false); settingsOpened = nil
KalimdorZugZugSettingsPanel:Hide() -- il canvas resta nascosto se Blizzard non seleziona la categoria
SlashCmdList.KZZRADIO("config")
check("Opzioni Blizzard non si aprono -> finestra autonoma", ns.Settings.standalone and KalimdorZugZugSettingsPanel:IsShown()
  and ns.db.lastSettingsOpen[#ns.db.lastSettingsOpen]:find("finestra autonoma"))
KalimdorZugZugSettingsPanel:Show(); ns.Settings:Refresh(); ns.Minimap:SetShown(true)
check("minimappa visibile dalle impostazioni", ns.db.minimap.hide == false)

-- traduzioni: ogni lingua ha tutte le chiavi inglesi con gli stessi segnaposto
local function placeholders(str) local n = 0; for _ in str:gmatch("%%[sd]") do n = n + 1 end; return n end
for _, code in ipairs(ns.LANG_ORDER) do
  local missing, bad = {}, {}
  for key, en in pairs(ns.LOCALES.enUS) do
    local v = ns.LOCALES[code][key]
    if v == nil then missing[#missing + 1] = key
    elseif placeholders(v) ~= placeholders(en) then bad[#bad + 1] = key end
  end
  check(code .. " completa" .. (#missing > 0 and (" (mancano: " .. table.concat(missing, ",") .. ")") or "")
    .. (#bad > 0 and (" (segnaposto: " .. table.concat(bad, ",") .. ")") or ""), #missing == 0 and #bad == 0)
end
clientLocale = "deDE"; ns.InitLanguage(nil)
check("lingua dal client (deDE)", ns.lang == "deDE" and ns.L.SIT_combat == "Kampf" and not ns.useAddonFont)
clientLocale = "enGB"; ns.InitLanguage(nil)
check("enGB -> enUS", ns.lang == "enUS")
clientLocale = "enUS"; ns.InitLanguage("jaJP")
check("giapponese su client enUS: font addon, chat in inglese", ns.useAddonFont and ns.chatLang == "enUS" and ns.L.SIT_boss == "ボス" and ns.CL.SIT_boss == "Boss")
check("font addon creato", ns.Font("GameFontNormalSmall") == "KZZR_GameFontNormalSmall")
clientLocale = "zhCN"; ns.InitLanguage(nil)
check("zhCN su client zhCN: font del gioco", ns.lang == "zhCN" and not ns.useAddonFont and ns.chatLang == "zhCN")
clientLocale = "koKR"; ns.InitLanguage(nil)
check("koKR (non tradotto) -> inglese", ns.lang == "enUS")
ns.InitLanguage("esMX")
check("esMX eredita da esES", ns.L.SIT_campfire == "Fogata" and ns.L.SIT_combat == "Combate")
clientLocale = "enUS"; ns.InitLanguage(nil)
SlashCmdList.KZZRADIO("lang ja"); check("/kzz lang ja", ns.db.lang == "jaJP")
SlashCmdList.KZZRADIO("lang auto"); check("/kzz lang auto", ns.db.lang == nil)
SlashCmdList.KZZRADIO("help")
SlashCmdList.KZZRADIO("debug")
clientLocale = "enUS"; ns.InitLanguage(nil)
check("testo giapponese su client enUS -> font addon", ns.HasCJK("夜に駆ける") and not ns.HasCJK("Ado - Café"))
check("font CJK forzato anche con UI inglese", ns.Font("GameFontHighlightSmall", ns.HasCJK("ナニダト")) == "KZZR_GameFontHighlightSmall")
clientLocale = "zhCN"; ns.InitLanguage(nil)
check("su client cinese usa i font del gioco", not ns.HasCJK("夜に駆ける"))
clientLocale = "enUS"; ns.InitLanguage(nil)
check("nessun errore all'avvio", #ns.startupErrors == 0)
print(fails == 0 and "TUTTI I TEST OK" or (fails .. " TEST FALLITI"))
