-- Onboarding: a short step-by-step guide shown once to everyone (db.onboardingSeen), and again
-- with the Tutorial button in the settings or /kzz tutorial.
-- Steps: welcome + language, music source, ready-made playlists with the game's music, tour.
-- It never changes existing playlists or assignments: a preset playlist that already exists is
-- not recreated, and a condition that already has a playlist keeps it.
local _, ns = ...
local L = ns.L

local O = {}
ns.Onboarding = O

-- Conditions that get a ready-made playlist (in this order), when the catalog has tracks for them.
local PRESET_KEYS = { "combat", "boss", "dungeon", "town", "campfire", "night", "dead", "levelup", "swimming", "pvp", "idle" }
local WIDTH, HEIGHT = 560, 430
local STEPS = 4

local f
local step = 1
local ticked = {} -- preset row -> true/false once the user clicked it (Refresh then leaves it alone)
O.source = "game" -- "game" | "own" | "both"

local function text(parent, template)
  local fs = parent:CreateFontString(nil, "OVERLAY", ns.Font(template))
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("TOP")
  if fs.SetWordWrap then fs:SetWordWrap(true) end
  return fs
end

local function paragraph(parent, template, y, height)
  local fs = text(parent, template or "GameFontHighlight")
  fs:SetPoint("TOPLEFT", 24, y)
  fs:SetWidth(WIDTH - 48)
  if height then fs:SetHeight(height) end
  return fs
end

local function check(parent, x, y, label, onClick)
  local c = ns.MakeCheckbox(parent, 24, label)
  c:SetPoint("TOPLEFT", x, y)
  c:SetScript("OnClick", function(self) onClick(self, self:GetChecked() and true or false) end)
  return c
end

-- Name of the ready-made playlist of a condition.
function O.PresetName(key)
  return L.OB_PLAYLIST_NAME:format(ns.SituationLabel(key))
end

-- Conditions with game tracks, with their track count.
function O.PresetList()
  local list = {}
  for _, key in ipairs(PRESET_KEYS) do
    local n = #ns.PresetTrackIds(key)
    if n > 0 then list[#list + 1] = { key = key, count = n } end
  end
  return list
end

-- Creates the chosen ready-made playlists and assigns them to conditions that have none.
-- Returns the number of playlists created.
function O.CreatePresets(keys)
  local made = 0
  for _, key in ipairs(keys) do
    local name = O.PresetName(key)
    local existing = ns.FindPlaylist(name)
    if not existing then
      local created = ns.CreatePlaylist(name)
      if created then
        ns.SetManyInPlaylist(created, ns.PresetTrackIds(key), true)
        existing = created
        made = made + 1
      end
    end
    if existing and not ns.db.assign[key] then ns.Assign(key, existing) end
  end
  return made
end

-- Track ids saved in playlists that the library doesn't have (e.g. music lost by an addon
-- manager update before 0.8). Game tracks and podcasts are not counted.
function ns.MissingUserTracks()
  local seen, n = {}, 0
  for _, ids in pairs(ns.db.playlists) do
    for _, id in ipairs(ids) do
      if type(id) == "string" and not seen[id] and not id:find("^game:") and not id:find("^ep:")
         and not ns.trackById[id] then
        seen[id] = true
        n = n + 1
      end
    end
  end
  return n
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
local function buildWelcome(p)
  paragraph(p, "GameFontHighlight", -6, 110):SetText(L.OB_WELCOME)
  local label = text(p, "GameFontNormal")
  label:SetPoint("TOPLEFT", 24, -134)
  label:SetText(L.LANGUAGE)
  p.lang = ns.LanguageDropdown(p, function() O:Refresh() end)
  if p.lang then p.lang:SetPoint("LEFT", label, "RIGHT", 12, 0) end
  p.reload = ns.MakeButton(p, L.RELOAD, 130, function() ReloadUI() end)
  p.reload:SetPoint("LEFT", p.lang or label, "RIGHT", 12, 0)
  p.langHint = paragraph(p, "GameFontDisableSmall", -164)
  p.langHint:SetText(L.LANG_RELOAD_HINT)
end

local function buildSource(p)
  paragraph(p, "GameFontNormal", -6):SetText(L.OB_SOURCE)
  p.options = {}
  local function choose(source)
    O.source = source
    for k, c in pairs(p.options) do c:SetChecked(k == source) end
    O:Refresh()
  end
  for i, opt in ipairs({ { "game", L.OB_SOURCE_GAME }, { "own", L.OB_SOURCE_OWN }, { "both", L.OB_SOURCE_BOTH } }) do
    p.options[opt[1]] = check(p, 24, -30 - (i - 1) * 28, opt[2], function() choose(opt[1]) end)
  end
  p.info = paragraph(p, "GameFontHighlightSmall", -124, 150)
end

local function buildPresets(p)
  p.intro = paragraph(p, "GameFontHighlightSmall", -6, 44)
  p.rows = {}
  for i, item in ipairs(O.PresetList()) do
    local col, row = math.floor((i - 1) / 6), (i - 1) % 6
    -- a manual tick is remembered, so Refresh doesn't undo it
    local c = check(p, 24 + col * 260, -56 - row * 30, "", function(self, on) ticked[self] = on end)
    c.key = item.key
    c.label:SetText(("%s (%d)"):format(ns.SituationLabel(item.key), item.count))
    c.label:SetWidth(210)
    if c.label.SetWordWrap then c.label:SetWordWrap(false) end
    c.status = text(p, "GameFontDisableSmall")
    c.status:SetPoint("TOPLEFT", c.label, "BOTTOMLEFT", 0, -1)
    c.status:SetWidth(210)
    if c.status.SetWordWrap then c.status:SetWordWrap(false) end
    p.rows[#p.rows + 1] = c
  end
end

local function buildTour(p)
  paragraph(p, "GameFontHighlight", -6, 250):SetText(L.OB_TOUR)
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function build()
  if f then return end
  f = CreateFrame("Frame", "KalimdorZugZugOnboarding", UIParent, "BackdropTemplate")
  f:SetSize(WIDTH, HEIGHT)
  f:SetPoint("CENTER", 0, 40)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f.title = f:CreateFontString(nil, "OVERLAY", ns.Font("GameFontNormal"))
  f.title:SetText(L.OB_TITLE)
  f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  f.close:SetScript("OnClick", function() f:Hide() end)
  -- closing the guide in any way counts as seen
  f:SetScript("OnHide", function() ns.db.onboardingSeen = true end)

  f.pages = {}
  for i, builder in ipairs({ buildWelcome, buildSource, buildPresets, buildTour }) do
    local p = CreateFrame("Frame", nil, f)
    p:SetPoint("TOPLEFT", 0, -44)
    p:SetPoint("BOTTOMRIGHT", 0, 48)
    builder(p)
    f.pages[i] = p
  end

  f.stepLabel = f:CreateFontString(nil, "OVERLAY", ns.Font("GameFontDisableSmall"))
  f.stepLabel:SetPoint("BOTTOMLEFT", 24, 20)
  f.next = ns.MakeButton(f, L.OB_NEXT, 110, function() O:Next() end)
  f.next:SetPoint("BOTTOMRIGHT", -20, 14)
  f.back = ns.MakeButton(f, L.OB_BACK, 110, function() O:Go(step - 1) end)
  f.back:SetPoint("RIGHT", f.next, "LEFT", -8, 0)
  f:Hide()
  if UISpecialFrames then table.insert(UISpecialFrames, f:GetName()) end
end

function O:Refresh()
  if not f then return end
  ns.SkinWindow(f, f.title, f.close)
  for i, p in ipairs(f.pages) do p:SetShown(i == step) end
  f.stepLabel:SetText(L.OB_STEP:format(step, STEPS))
  f.back:SetShown(step > 1)
  f.next:SetText(step == STEPS and L.OB_FINISH or L.OB_NEXT)

  local src = f.pages[2]
  for k, c in pairs(src.options) do c:SetChecked(k == O.source) end
  local info
  if O.source == "game" then
    info = L.OB_GAME_INFO
  else
    info = L.OB_OWN_HOWTO
    if #ns.tracks > 0 then info = L.OB_OWN_COUNT:format(#ns.tracks) .. "\n\n" .. info end
    local missing = ns.MissingUserTracks()
    if missing > 0 then info = info .. "\n\n" .. L.MSG_LIBRARY_MISSING:format(missing) end
  end
  src.info:SetText(info)

  local pre = f.pages[3]
  pre.intro:SetText(O.source == "own" and L.OB_PRESETS_OWN or L.OB_PRESETS)
  for _, c in ipairs(pre.rows) do
    local assigned = ns.db.assign[c.key]
    ns.SetText(c.status, assigned and L.OB_ALREADY:format(ns.PlaylistLabel(assigned)) or "", "GameFontDisableSmall")
    if ticked[c] == nil then c:SetChecked(O.source ~= "own" and not assigned) end
  end
end

function O:Go(i)
  step = math.max(1, math.min(STEPS, i))
  self:Refresh()
end

function O:Next()
  if step < STEPS then self:Go(step + 1) return end
  -- Finish: create the checked playlists, back to automatic mode
  local keys = {}
  for _, c in ipairs(f.pages[3].rows) do
    if c:GetChecked() then keys[#keys + 1] = c.key end
  end
  local made = self.CreatePresets(keys)
  if ns.db.mode ~= "auto" and #keys > 0 then ns.SetMode("auto") end
  ns.Print("MSG_OB_DONE", made)
  f:Hide()
end

function O:Show()
  build()
  step = 1
  O.source = #ns.tracks > 0 and "own" or "game"
  wipe(ticked)
  self:Refresh()
  f:Show()
end

function O:IsShown() return f ~= nil and f:IsShown() end

-- First login with this version: show the guide once the loading screen and any fight are over.
-- Also tell the user when their playlists point to music the library no longer has.
ns.RegisterEvent("PLAYER_LOGIN", function()
  C_Timer.After(3, function()
    local ok, err = pcall(function()
      if #ns.tracks == 0 then
        local missing = ns.MissingUserTracks()
        if missing > 0 then ns.Print("MSG_LIBRARY_MISSING", missing) end
      end
      if ns.db.onboardingSeen then return end
      if InCombatLockdown() then
        local w = CreateFrame("Frame")
        w:RegisterEvent("PLAYER_REGEN_ENABLED")
        w:SetScript("OnEvent", function(self)
          self:UnregisterAllEvents()
          if not ns.db.onboardingSeen then O:Show() end
        end)
      else
        O:Show()
      end
    end)
    if not ok then table.insert(ns.startupErrors, "Onboarding: " .. tostring(err)) end
  end)
end)
