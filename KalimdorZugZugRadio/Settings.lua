-- Settings: panel in Options > AddOns (modern Settings API) with general options, language and conditions.
-- If the Settings API is missing or doesn't show it, the same panel opens as a standalone window.
local ADDON, ns = ...
local L = ns.L

local S = {}
ns.Settings = S

local ACCENT = { 1, 0.5, 0.1 }
local panel, category

local function text(parent, template)
  return parent:CreateFontString(nil, "OVERLAY", ns.Font(template))
end

-- Checkbox with a label; onToggle(checked).
local function checkOption(parent, label, x, y, onToggle, template)
  local c = CreateFrame("CheckButton", nil, parent)
  c:SetSize(24, 24)
  c:SetPoint("TOPLEFT", x, y)
  c:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  c:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  c:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
  c:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  c.label = text(parent, template or "GameFontHighlight")
  c.label:SetPoint("LEFT", c, "RIGHT", 4, 0)
  c.label:SetText(label)
  c:SetScript("OnClick", function(self) onToggle(self:GetChecked() and true or false) end)
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
local CONTENT_WIDTH, CONTENT_HEIGHT = 640, 710
local ROWS_PER_COLUMN = 8

local function playlistMenu(root, isSelected, select)
  ns.StyleMenuItem(root:CreateRadio(L.NONE, function() return isSelected(nil) end, function() select(nil) end))
  for _, name in ipairs(ns.AllPlaylistNames()) do
    ns.StyleMenuItem(root:CreateRadio(("%s (%d)"):format(ns.PlaylistLabel(name), #ns.GetPlaylist(name).tracks),
      function() return isSelected(name) end, function() select(name) end), ns.TextFont(name))
  end
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

  -- profile: the condition settings below belong to it
  local profLabel = text(c, "GameFontNormal")
  profLabel:SetPoint("TOPLEFT", 20, -226)
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
  tailLabel:SetPoint("TOPLEFT", 334, -226)
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
  langLabel:SetPoint("TOPLEFT", 20, -262)
  langLabel:SetText(L.LANGUAGE)
  -- CJK language names always use a bundled font, so they are readable on any client
  p.lang = ns.MakeDropdown(c, 200, L.LANG_AUTO, function(_, root)
    ns.StyleMenuItem(root:CreateRadio(L.LANG_AUTO,
      function() return ns.db.lang == nil end,
      function() ns.SetLanguage(nil) S:Refresh() end))
    root:CreateDivider()
    for _, code in ipairs(ns.LANG_ORDER) do
      ns.StyleMenuItem(root:CreateRadio(ns.LANGUAGE_NAMES[code],
        function() return ns.db.lang == code end,
        function() ns.SetLanguage(code) S:Refresh() end), code == "koKR" and "ko" or ns.CJK_LANG[code])
    end
  end)
  if p.lang then p.lang:SetPoint("LEFT", langLabel, "RIGHT", 12, 0) end
  p.reload = ns.MakeButton(c, L.RELOAD, 130, function() ReloadUI() end)
  p.reload:SetPoint("LEFT", p.lang or langLabel, "RIGHT", 12, 0)
  p.langHint = text(c, "GameFontDisableSmall")
  p.langHint:SetPoint("TOPLEFT", 20, -286)
  p.langHint:SetText(L.LANG_RELOAD_HINT)

  -- Conditions ---------------------------------------------------------------
  sectionHeader(c, L.CONDITIONS, -316)
  -- free play warning: while a playlist is chosen manually, conditions are ignored
  p.freeBack = ns.MakeButton(c, L.BACK_AUTO, 150, function() ns.SetMode("auto") S:Refresh() end, L.TT_BACK_AUTO)
  p.freeBack:SetPoint("TOPRIGHT", -16, -340)
  p.freeWarn = text(c, "GameFontNormal")
  p.freeWarn:SetPoint("TOPLEFT", 16, -344)
  p.freeWarn:SetPoint("RIGHT", p.freeBack, "LEFT", -10, 0)
  p.freeWarn:SetJustifyH("LEFT")
  p.freeWarn:SetTextColor(1, 0.6, 0.1)
  local hint = text(c, "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", 16, -372)
  hint:SetPoint("RIGHT", c, "RIGHT", -16, 0)
  hint:SetJustifyH("LEFT")
  hint:SetText(L.COND_SETTINGS_HINT)

  -- two columns, read top to bottom then left to right (= priority order)
  p.conditions = {}
  for i, s in ipairs(ns.SITUATIONS) do
    local col = math.floor((i - 1) / ROWS_PER_COLUMN)
    local y = -400 - ((i - 1) % ROWS_PER_COLUMN) * 34
    local x = 16 + col * 316
    local row = {}
    row.check = checkOption(c, ns.SituationLabel(s.key), x, y, function(on) ns.SetConditionEnabled(s.key, on) end,
      "GameFontHighlightSmall")
    row.check.label:SetWidth(122)
    row.check.label:SetJustifyH("LEFT")
    row.check.label:SetWordWrap(false)
    row.dropdown = ns.MakeDropdown(c, 150, L.NONE, function(_, root)
      playlistMenu(root, function(name) return ns.AssignedTo(s.key) == name end,
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
        -- a playlist for each boss met so far
        local bosses = root:CreateButton(L.BOSS_SPECIFIC)
        ns.StyleMenuItem(bosses)
        local ids = {}
        for id in pairs(ns.db.seenBosses) do ids[#ids + 1] = id end
        table.sort(ids, function(a, b) return ns.db.seenBosses[a] < ns.db.seenBosses[b] end)
        if #ids == 0 then ns.StyleMenuItem(bosses:CreateTitle(L.BOSS_NONE_SEEN)) end
        for _, id in ipairs(ids) do
          local assigned = ns.db.bosses[id] and ns.db.bosses[id].playlist
          local entry = bosses:CreateButton(ns.db.seenBosses[id] .. (assigned and ("  -  " .. ns.PlaylistLabel(assigned)) or ""))
          ns.StyleMenuItem(entry, ns.TextFont(ns.db.seenBosses[id]))
          playlistMenu(entry, function(name) return (ns.db.bosses[id] and ns.db.bosses[id].playlist) == name end,
            function(name) ns.AssignBoss(id, name) end)
        end
      end
    end)
    if row.dropdown then row.dropdown:SetPoint("TOPLEFT", x + 150, y + 2) end
    row.key = s.key
    p.conditions[i] = row
  end

  p.zoneLine = text(c, "GameFontHighlightSmall")
  p.zoneLine:SetPoint("TOPLEFT", 20, -400 - ROWS_PER_COLUMN * 34 - 6)
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
  for _, dd in ipairs({ panel.lang, panel.profile, panel.fightTail }) do
    if dd and dd.GenerateMenu then dd:GenerateMenu() end
  end
end

function S:Refresh()
  if not panel then return end
  panel.optEnabled:SetChecked(ns.db.enabled)
  panel.optShuffle:SetChecked(ns.db.shuffle)
  panel.optMinimap:SetChecked(not ns.db.minimap.hide)
  panel.optLock:SetChecked(ns.db.ui.locked)
  panel.optClassic:SetChecked((ns.db.ui.skin or "classic") == "classic")
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
