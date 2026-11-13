-- Settings: panel in Options > AddOns (modern Settings API) with general options, language and conditions.
-- If the Settings API is missing or doesn't show it, the same panel opens as a standalone window.
local ADDON, ns = ...
local L = ns.L

local S = {}
ns.Settings = S

local ACCENT = ns.ACCENT
local panel, category

local function text(parent, template)
  return parent:CreateFontString(nil, "OVERLAY", ns.Font(template))
end

-- Checkbox with a label; onToggle(checked).
local function checkOption(parent, label, x, y, onToggle, template, tooltip)
  local c = ns.MakeCheckbox(parent, 24, label, template)
  c:SetPoint("TOPLEFT", x, y)
  c:SetScript("OnClick", function(self) onToggle(self:GetChecked() and true or false) end)
  if tooltip then
    c:SetScript("OnEnter", function(self) ns.ShowTooltip(self, "ANCHOR_RIGHT", { label, tooltip }) end)
    c:SetScript("OnLeave", function() ns.HideTooltip() end)
  end
  return c
end

local function sectionHeader(parent, label, y)
  local h = text(parent, "GameFontNormalLarge")
  h:SetPoint("TOPLEFT", 16, y)
  h:SetText(label)
  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.5)
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -4)
  line:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
  return h
end

---------------------------------------------------------------------------
-- Content (inside a scroll frame: with 16 conditions it's taller than the Options canvas)
---------------------------------------------------------------------------
local CONTENT_WIDTH, CONTENT_HEIGHT = 640, 762
local ROWS_PER_COLUMN = 8

-- Submenu with a playlist for each boss / dungeon met so far (seen: id -> name).
local function specificMenu(root, title, emptyLabel, seen, assigned, assign)
  local menu = root:CreateButton(title)
  ns.StyleMenuItem(menu)
  local ids = {}
  for id in pairs(seen) do ids[#ids + 1] = id end
  table.sort(ids, function(a, b) return seen[a] < seen[b] end)
  if #ids == 0 then ns.StyleMenuItem(menu:CreateTitle(emptyLabel)) end
  for _, id in ipairs(ids) do
    local pl = assigned[id] and assigned[id].playlist
    local entry = menu:CreateButton(seen[id] .. (pl and ("  -  " .. ns.PlaylistLabel(pl)) or ""))
    ns.StyleMenuItem(entry, ns.TextFont(seen[id]))
    ns.PlaylistMenu(entry, function(name) return (assigned[id] and assigned[id].playlist) == name end,
      function(name) assign(id, name) end, L.ASSIGN_GENERAL)
  end
end

-- "Specific enemies" of the combat/elite conditions: beast families and creature types met in
-- the open world (only those of the current client language when names had to be used).
local function foeMenu(root, cond)
  local menu = root:CreateButton(L.FOE_SPECIFIC)
  ns.StyleMenuItem(menu)
  ns.StyleMenuItem(menu:CreateTitle(L.FOE_HINT))
  local groups = { family = {}, type = {} }
  for key in pairs(ns.db.seenFoes) do
    local kind = key:match("^(%a+):")
    if groups[kind] and ns.FoeUsable(key) then table.insert(groups[kind], key) end
  end
  local any = false
  for _, g in ipairs({ { "family", L.FOE_FAMILIES }, { "type", L.FOE_TYPES } }) do
    local keys = groups[g[1]]
    if #keys > 0 then
      any = true
      table.sort(keys, function(a, b) return ns.FoeName(a) < ns.FoeName(b) end)
      menu:CreateDivider()
      ns.StyleMenuItem(menu:CreateTitle(g[2]))
      for _, key in ipairs(keys) do
        local name, pl = ns.FoeName(key), ns.FoePlaylist(cond, key)
        local entry = menu:CreateButton(name .. (pl and ("  -  " .. ns.PlaylistLabel(pl)) or ""))
        ns.StyleMenuItem(entry, ns.TextFont(name))
        ns.PlaylistMenu(entry, function(n) return ns.FoePlaylist(cond, key) == n end,
          function(n) ns.AssignFoe(cond, key, n) end, L.ASSIGN_GENERAL)
      end
    end
  end
  if not any then ns.StyleMenuItem(menu:CreateTitle(L.FOE_NONE_SEEN)) end
end

local function build(p)
  local c = p
  local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
  if ok and scroll and scroll.SetScrollChild then
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    c = CreateFrame("Frame", nil, scroll)
    c:SetSize(CONTENT_WIDTH, CONTENT_HEIGHT)
    scroll:SetScrollChild(c)
    p.scroll = scroll
  end
  p.content = c

  local title = text(c, "GameFontHighlightHuge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("Kalimdor ZugZug Radio")

  p.openLib = ns.MakeButton(c, L.OPEN_LIBRARY, 130, function() ns.LibraryUI:Toggle(true) end, L.TT_LIBRARY)
  p.openLib:SetPoint("TOPRIGHT", -16, -16)
  p.tutorial = ns.MakeButton(c, L.TUTORIAL, 110, function() ns.Onboarding:Show() end, L.TT_TUTORIAL)
  p.tutorial:SetPoint("RIGHT", p.openLib, "LEFT", -8, 0)

  -- General -------------------------------------------------------------------
  sectionHeader(c, L.SECTION_GENERAL, -56)
  p.optEnabled = checkOption(c, L.OPT_ENABLED, 16, -84, function(on) ns.SetEnabled(on) end)
  p.optShuffle = checkOption(c, L.OPT_SHUFFLE, 16, -110, function(on) ns.Player:SetShuffle(on) end)
  p.optClassic = checkOption(c, L.OPT_CLASSIC, 16, -136, function(on) ns.UI:SetSkin(on and "classic" or "modern") end)
  p.optCrossfade = checkOption(c, L.OPT_CROSSFADE, 16, -162, function(on) ns.db.crossfade = on end)
  p.optMinimap = checkOption(c, L.OPT_MINIMAP, 330, -84, function(on) ns.Minimap:SetShown(on) end)
  p.optLock = checkOption(c, L.OPT_LOCK, 330, -110, function(on) ns.db.ui.locked = on end)
  p.optBanner = checkOption(c, L.OPT_BANNER, 330, -136, function(on) ns.db.ui.banner = on end)
  p.optAfk = checkOption(c, L.OPT_AFK, 330, -162, function(on) ns.db.afkPause = on end)
  p.optDuck = checkOption(c, L.OPT_DUCK, 16, -188, function(on) ns.db.duck = on if not on then ns.Player:SetDucked(false) end end)
  p.optCompact = checkOption(c, L.OPT_COMPACT, 330, -188, function(on) ns.UI:SetCompact(on) end)
  p.optSmartShuffle = checkOption(c, L.OPT_SMART_SHUFFLE, 16, -214, function(on)
    ns.db.smartShuffle = on
    ns.Player:SetShuffle(ns.db.shuffle) -- rebuild the queues with the new order
  end, nil, L.TT_SMART_SHUFFLE)
  p.optZoneBreaks = checkOption(c, L.OPT_ZONE_BREAKS, 330, -214, function(on)
    ns.db.zoneBreaks = on
    if not on then ns.Player:EndZoneBreak() ns.Rules:Evaluate(true) end
  end, nil, L.TT_ZONE_BREAKS)
  p.moveBanner = ns.MakeButton(c, L.MOVE_BANNER, 150, function() ns.Banner:ToggleMoving() end, L.TT_MOVE_BANNER)
  p.moveBanner:SetPoint("TOPLEFT", 20, -242)
  -- how often and how long: a few presets
  local BREAKS = { { 2, 1 }, { 3, 2 }, { 5, 3 }, { 8, 5 } }
  p.zoneBreakFreq = ns.MakeDropdown(c, 230, L.ZONE_BREAK_FREQ:format(3, 2), function(_, root)
    for _, b in ipairs(BREAKS) do
      ns.StyleMenuItem(root:CreateRadio(L.ZONE_BREAK_FREQ:format(b[1], b[2]),
        function() return ns.db.zoneBreakEvery == b[1] and ns.db.zoneBreakMinutes == b[2] end,
        function() ns.db.zoneBreakEvery, ns.db.zoneBreakMinutes = b[1], b[2] end))
    end
  end)
  if p.zoneBreakFreq then p.zoneBreakFreq:SetPoint("TOPLEFT", 358, -238) end

  -- profile: the condition settings below belong to it
  local profLabel = text(c, "GameFontNormal")
  profLabel:SetPoint("TOPLEFT", 20, -278)
  profLabel:SetText(L.PROFILE)
  p.profile = ns.MakeDropdown(c, 220, L.PROFILE_DEFAULT, function(_, root)
    for _, name in ipairs(ns.ProfileNames()) do
      ns.StyleMenuItem(root:CreateRadio(name == ns.DEFAULT_PROFILE and L.PROFILE_DEFAULT or name,
        function() return ns.profileName == name end,
        function() ns.SetCharacterProfile(name) S:Refresh() S:RefreshMenus() end), ns.TextFont(name))
    end
    root:CreateDivider()
    ns.StyleMenuItem(root:CreateButton(L.PROFILE_NEW, function() ns.NewCharacterProfile() S:Refresh() S:RefreshMenus() end))
    if ns.profileName ~= ns.DEFAULT_PROFILE then
      ns.StyleMenuItem(root:CreateButton(L.PROFILE_DELETE, function()
        ns.DeleteProfile(ns.profileName) S:Refresh() S:RefreshMenus()
      end))
    end
  end)
  if p.profile then p.profile:SetPoint("LEFT", profLabel, "RIGHT", 12, 0) end

  -- how long the fight music lasts (fading out) after the combat
  local tailLabel = text(c, "GameFontNormal")
  tailLabel:SetPoint("TOPLEFT", 334, -278)
  tailLabel:SetText(L.OPT_FIGHT_TAIL)
  p.fightTail = ns.MakeDropdown(c, 80, L.FIGHT_TAIL_SECONDS:format(8), function(_, root)
    for _, sec in ipairs({ 4, 6, 8, 10 }) do
      ns.StyleMenuItem(root:CreateRadio(L.FIGHT_TAIL_SECONDS:format(sec),
        function() return (ns.db.fightTail or 8) == sec end,
        function() ns.db.fightTail = sec end))
    end
  end)
  if p.fightTail then
    p.fightTail:SetPoint("LEFT", tailLabel, "RIGHT", 10, 0)
    if p.fightTail.HookScript then
      p.fightTail:HookScript("OnEnter", function(self)
        ns.ShowTooltip(self, "ANCHOR_TOP", { L.OPT_FIGHT_TAIL, L.TT_FIGHT_TAIL:format(4) })
      end)
      p.fightTail:HookScript("OnLeave", function() ns.HideTooltip() end)
    end
  end

  local langLabel = text(c, "GameFontNormal")
  langLabel:SetPoint("TOPLEFT", 20, -314)
  langLabel:SetText(L.LANGUAGE)
  p.lang = ns.LanguageDropdown(c, function() S:Refresh() end)
  if p.lang then p.lang:SetPoint("LEFT", langLabel, "RIGHT", 12, 0) end
  p.reload = ns.MakeButton(c, L.RELOAD, 130, function() ReloadUI() end)
  p.reload:SetPoint("LEFT", p.lang or langLabel, "RIGHT", 12, 0)
  p.langHint = text(c, "GameFontDisableSmall")
  p.langHint:SetPoint("TOPLEFT", 20, -338)
  p.langHint:SetText(L.LANG_RELOAD_HINT)

  -- Conditions ---------------------------------------------------------------
  sectionHeader(c, L.CONDITIONS, -368)
  -- free play warning: while a playlist is chosen manually, conditions are ignored
  p.freeBack = ns.MakeButton(c, L.BACK_AUTO, 150, function() ns.SetMode("auto") S:Refresh() end, L.TT_BACK_AUTO)
  p.freeBack:SetPoint("TOPRIGHT", -16, -392)
  p.freeWarn = text(c, "GameFontNormal")
  p.freeWarn:SetPoint("TOPLEFT", 16, -396)
  p.freeWarn:SetPoint("RIGHT", p.freeBack, "LEFT", -10, 0)
  p.freeWarn:SetJustifyH("LEFT")
  p.freeWarn:SetTextColor(1, 0.6, 0.1)
  local hint = text(c, "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", 16, -424)
  hint:SetPoint("RIGHT", c, "RIGHT", -16, 0)
  hint:SetJustifyH("LEFT")
  hint:SetText(L.COND_SETTINGS_HINT)

  -- two columns, read top to bottom then left to right (= priority order)
  p.conditions = {}
  for i, s in ipairs(ns.SITUATIONS) do
    local col = math.floor((i - 1) / ROWS_PER_COLUMN)
    local y = -452 - ((i - 1) % ROWS_PER_COLUMN) * 34
    local x = 16 + col * 316
    local row = {}
    row.check = checkOption(c, ns.SituationLabel(s.key), x, y, function(on) ns.SetConditionEnabled(s.key, on) end,
      "GameFontHighlightSmall")
    row.check.label:SetWidth(122)
    row.check.label:SetJustifyH("LEFT")
    row.check.label:SetWordWrap(false)
    row.dropdown = ns.MakeDropdown(c, 150, L.NONE, function(_, root)
      ns.PlaylistMenu(root, function(name) return ns.AssignedTo(s.key) == name end,
        function(name) ns.Assign(s.key, name) end)
      root:CreateDivider()
      -- volume of this condition (multiplies the player's volume)
      local vol = root:CreateButton(L.COND_VOLUME:format(math.floor(ns.ConditionVolume(s.key) * 100 + 0.5)))
      ns.StyleMenuItem(vol)
      for _, pct in ipairs({ 100, 80, 60, 40, 20 }) do
        ns.StyleMenuItem(vol:CreateRadio(pct .. "%",
          function() return math.floor(ns.ConditionVolume(s.key) * 100 + 0.5) == pct end,
          function() ns.SetConditionVolume(s.key, pct / 100) end))
      end
      if s.key == "boss" then
        specificMenu(root, L.BOSS_SPECIFIC, L.BOSS_NONE_SEEN, ns.db.seenBosses, ns.db.bosses, ns.AssignBoss)
      elseif s.key == "dungeon" then
        specificMenu(root, L.DUNGEON_SPECIFIC, L.DUNGEON_NONE_SEEN, ns.db.seenDungeons, ns.db.dungeons, ns.AssignDungeon)
      elseif ns.FOE_CONDITIONS[s.key] then
        foeMenu(root, s.key)
      end
    end)
    if row.dropdown then row.dropdown:SetPoint("TOPLEFT", x + 150, y + 2) end
    row.key = s.key
    p.conditions[i] = row
  end

  p.zoneLine = text(c, "GameFontHighlightSmall")
  p.zoneLine:SetPoint("TOPLEFT", 20, -452 - ROWS_PER_COLUMN * 34 - 6)
  p.zoneLine:SetPoint("RIGHT", c, "RIGHT", -16, 0)
  p.zoneLine:SetJustifyH("LEFT")

  local throttle = 0
  p:SetScript("OnUpdate", function(_, dt)
    throttle = throttle + dt
    if throttle >= 1 then throttle = 0 S:RefreshConditions() end
  end)
  p:SetScript("OnShow", function() S:Refresh() S:RefreshMenus() end)
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
function S:RefreshConditions()
  if not panel or not panel:IsShown() then return end
  local free = ns.db.mode ~= "auto"
  panel.freeWarn:SetShown(free)
  panel.freeBack:SetShown(free)
  if free then ns.SetText(panel.freeWarn, L.FREE_PLAY_WARNING:format(ns.PlaylistLabel(ns.db.mode)), "GameFontNormal") end
  panel.freeWarn:SetTextColor(1, 0.6, 0.1)
  local zone = ns.CurrentZone()
  ns.SetText(panel.zoneLine, L.ZONE_LINE:format(zone and zone.name or L.ZONE_UNKNOWN, ns.ZoneCount()), "GameFontHighlightSmall")
  local active = ns.Rules:ActiveSet()
  for _, row in ipairs(panel.conditions) do
    local enabled = ns.IsConditionEnabled(row.key)
    row.check:SetChecked(enabled)
    local label = row.check.label
    if not enabled then label:SetTextColor(0.5, 0.5, 0.5)
    elseif ns.db.mode == "auto" and ns.Rules.current == row.key then label:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    elseif active[row.key] then label:SetTextColor(0.3, 1, 0.3)
    else label:SetTextColor(1, 1, 1) end
    if row.dropdown and row.dropdown.SetEnabled then row.dropdown:SetEnabled(enabled) end
  end
end

-- Rebuilds the dropdown menus (only on events, not on the 1s colour refresh).
function S:RefreshMenus()
  if not panel then return end
  for _, row in ipairs(panel.conditions) do
    if row.dropdown and row.dropdown.GenerateMenu then row.dropdown:GenerateMenu() end
  end
  for _, dd in ipairs({ panel.lang, panel.profile, panel.fightTail, panel.zoneBreakFreq }) do
    if dd and dd.GenerateMenu then dd:GenerateMenu() end
  end
end

function S:Refresh()
  if not panel then return end
  panel.optEnabled:SetChecked(ns.db.enabled)
  panel.optShuffle:SetChecked(ns.db.shuffle)
  panel.optSmartShuffle:SetChecked(ns.db.smartShuffle)
  panel.optZoneBreaks:SetChecked(ns.db.zoneBreaks)
  panel.optMinimap:SetChecked(not ns.db.minimap.hide)
  panel.optLock:SetChecked(ns.db.ui.locked)
  panel.optClassic:SetChecked(ns.IsClassicSkin())
  panel.optCrossfade:SetChecked(ns.db.crossfade)
  panel.optBanner:SetChecked(ns.db.ui.banner)
  panel.optAfk:SetChecked(ns.db.afkPause)
  panel.optDuck:SetChecked(ns.db.duck)
  panel.optCompact:SetChecked(ns.db.ui.compact)
  -- chosen language differs from the active one: highlight the reload hint
  local pending = (ns.db.lang or "auto") ~= (S.loadedLang or "auto")
  panel.langHint:SetTextColor(pending and 1 or 0.5, pending and 0.82 or 0.5, pending and 0 or 0.5)
  self:RefreshConditions()
end

---------------------------------------------------------------------------
-- Build and open
---------------------------------------------------------------------------
function S:Build()
  if panel then return end
  S.loadedLang = ns.db.lang
  local hasSettings = Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory
  if hasSettings then
    panel = CreateFrame("Frame", "KalimdorZugZugSettingsPanel")
    build(panel)
    local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Kalimdor ZugZug Radio")
    if ok and cat then
      category = cat
      pcall(Settings.RegisterAddOnCategory, cat)
    end
  end
  if not category then
    panel = panel or CreateFrame("Frame", "KalimdorZugZugSettingsPanel", UIParent)
    if not panel.conditions then build(panel) end
    S:MakeStandalone()
  end

  for _, ev in ipairs({ "STATE_CHANGED", "PLAYLISTS_CHANGED", "SETTINGS_CHANGED", "MODE_CHANGED", "SITUATION_CHANGED" }) do
    ns.On(ev, function() if panel:IsShown() then S:Refresh() end end)
  end
  for _, ev in ipairs({ "PLAYLISTS_CHANGED", "SETTINGS_CHANGED", "MODE_CHANGED" }) do
    ns.On(ev, function() if panel:IsShown() then S:RefreshMenus() end end)
  end
end

function S:HasCategory()
  return category ~= nil
end

-- Turns the panel into a standalone window (if Blizzard's Options panel isn't usable).
function S:MakeStandalone()
  if self.standalone then return end
  self.standalone = true
  panel:SetParent(UIParent)
  panel:ClearAllPoints()
  panel:SetSize(680, 640)
  panel:SetPoint("CENTER")
  panel:SetFrameStrata("DIALOG")
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  -- the canvas frame has no backdrop: put a BackdropTemplate frame behind the content
  local skin = CreateFrame("Frame", nil, panel, "BackdropTemplate")
  skin:SetAllPoints()
  skin:SetFrameLevel(math.max(0, panel:GetFrameLevel() - 1))
  local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  ns.SkinWindow(skin, nil, close)
  ns.On("SETTINGS_CHANGED", function() ns.SkinWindow(skin, nil, close) end)
  panel:Hide()
  if UISpecialFrames then table.insert(UISpecialFrames, panel:GetName()) end
end

local function blizzardPanelShown()
  return SettingsPanel and SettingsPanel:IsShown() and panel:IsVisible()
end

function S:Open()
  if not panel then
    print("|cffff4040ZugZug Radio|r: settings unavailable (startup error, see /kzz debug)")
    return
  end
  ns.LibraryUI:Toggle(false) -- the library (strata HIGH) could cover the panel
  if category and not self.standalone then
    if InCombatLockdown() then ns.Print("MSG_SETTINGS_COMBAT") return end
    local id = category.GetID and category:GetID() or category.ID
    local attempts = {}
    local ok, err = pcall(Settings.OpenToCategory, id)
    attempts[#attempts + 1] = "OpenToCategory(id=" .. tostring(id) .. "): " .. (ok and "ok" or tostring(err))
    if not blizzardPanelShown() then
      ok, err = pcall(Settings.OpenToCategory, category)
      attempts[#attempts + 1] = "OpenToCategory(category): " .. (ok and "ok" or tostring(err))
    end
    if not blizzardPanelShown() and SettingsPanel then
      -- some versions want the panel already open before selecting the category
      ok, err = pcall(function()
        if ShowUIPanel then ShowUIPanel(SettingsPanel) else SettingsPanel:Show() end
        if SettingsPanel.SelectCategory then SettingsPanel:SelectCategory(category) end
      end)
      attempts[#attempts + 1] = "ShowUIPanel+SelectCategory: " .. (ok and "ok" or tostring(err))
    end
    local shown = blizzardPanelShown()
    attempts[#attempts + 1] = "result: " .. (shown and "opened in Options" or "not visible -> standalone window")
    ns.db.lastSettingsOpen = attempts
    if shown then return end
    if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then pcall(HideUIPanel, SettingsPanel) end
    self:MakeStandalone()
  end
  panel:Show()
  panel:Raise()
  self:Refresh()
end
