-- Settings: pannello in Opzioni > AddOns (API Settings moderna) con opzioni generali, lingua e condizioni.
-- Se l'API Settings non c'è, lo stesso pannello si apre come finestra autonoma.
local ADDON, ns = ...
local L = ns.L

local S = {}
ns.Settings = S

local ACCENT = { 1, 0.5, 0.1 }
local panel, category

local function text(parent, template)
  return parent:CreateFontString(nil, "OVERLAY", ns.Font(template))
end

-- Casella di spunta con etichetta; onToggle(checked).
local function checkOption(parent, label, x, y, onToggle)
  local c = CreateFrame("CheckButton", nil, parent)
  c:SetSize(24, 24)
  c:SetPoint("TOPLEFT", x, y)
  c:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  c:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  c:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
  c:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  c.label = text(parent, "GameFontHighlight")
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
-- Contenuto
---------------------------------------------------------------------------
local function build(p)
  local title = text(p, "GameFontHighlightHuge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("Kalimdor ZugZug Radio")

  p.openLib = ns.MakeButton(p, L.OPEN_LIBRARY, 130, function() ns.LibraryUI:Toggle(true) end, L.TT_LIBRARY)
  p.openLib:SetPoint("TOPRIGHT", -16, -16)

  -- Generale -----------------------------------------------------------------
  sectionHeader(p, L.SECTION_GENERAL, -56)
  p.optEnabled = checkOption(p, L.OPT_ENABLED, 16, -84, function(on) ns.SetEnabled(on) end)
  p.optShuffle = checkOption(p, L.OPT_SHUFFLE, 16, -110, function(on) ns.Player:SetShuffle(on) end)
  p.optMinimap = checkOption(p, L.OPT_MINIMAP, 300, -84, function(on) ns.Minimap:SetShown(on) end)
  p.optLock = checkOption(p, L.OPT_LOCK, 300, -110, function(on) ns.db.ui.locked = on end)

  local langLabel = text(p, "GameFontNormal")
  langLabel:SetPoint("TOPLEFT", 20, -146)
  langLabel:SetText(L.LANGUAGE)
  -- i nomi delle lingue CJK usano sempre il font dell'addon, così si leggono su ogni client
  p.lang = ns.MakeDropdown(p, 200, L.LANG_AUTO, function(_, root)
    ns.StyleMenuItem(root:CreateRadio(L.LANG_AUTO,
      function() return ns.db.lang == nil end,
      function() ns.SetLanguage(nil) S:Refresh() end))
    root:CreateDivider()
    for _, code in ipairs(ns.LANG_ORDER) do
      ns.StyleMenuItem(root:CreateRadio(ns.LANGUAGE_NAMES[code],
        function() return ns.db.lang == code end,
        function() ns.SetLanguage(code) S:Refresh() end), ns.CJK_LANG[code])
    end
  end)
  if p.lang then p.lang:SetPoint("LEFT", langLabel, "RIGHT", 12, 0) end
  p.reload = ns.MakeButton(p, L.RELOAD, 130, function() ReloadUI() end)
  p.reload:SetPoint("LEFT", p.lang or langLabel, "RIGHT", 12, 0)
  p.langHint = text(p, "GameFontDisableSmall")
  p.langHint:SetPoint("TOPLEFT", 20, -170)
  p.langHint:SetText(L.LANG_RELOAD_HINT)

  -- Condizioni ---------------------------------------------------------------
  sectionHeader(p, L.CONDITIONS, -200)
  local hint = text(p, "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", 16, -228)
  hint:SetPoint("RIGHT", p, "RIGHT", -16, 0)
  hint:SetJustifyH("LEFT")
  hint:SetText(L.COND_SETTINGS_HINT)

  p.conditions = {}
  for i, s in ipairs(ns.SITUATIONS) do
    local y = -262 - (i - 1) * 34
    local row = {}
    row.check = checkOption(p, ns.SituationLabel(s.key), 16, y, function(on) ns.SetConditionEnabled(s.key, on) end)
    row.check.label:SetWidth(190)
    row.check.label:SetJustifyH("LEFT")
    row.dropdown = ns.MakeDropdown(p, 220, L.NONE, function(_, root)
      ns.StyleMenuItem(root:CreateRadio(L.NONE,
        function() return ns.db.assign[s.key] == nil end,
        function() ns.Assign(s.key, nil) end))
      local names = ns.PlaylistNames()
      table.insert(names, 1, ns.ALL)
      for _, name in ipairs(names) do
        ns.StyleMenuItem(root:CreateRadio(("%s (%d)"):format(ns.PlaylistLabel(name), #ns.GetPlaylist(name).tracks),
          function() return ns.db.assign[s.key] == name end,
          function() ns.Assign(s.key, name) end), ns.HasCJK(name))
      end
    end)
    if row.dropdown then row.dropdown:SetPoint("TOPLEFT", 240, y + 2) end
    row.key = s.key
    p.conditions[i] = row
  end

  local throttle = 0
  p:SetScript("OnUpdate", function(_, dt)
    throttle = throttle + dt
    if throttle >= 1 then throttle = 0 S:RefreshConditions() end
  end)
  p:SetScript("OnShow", function() S:Refresh() end)
end

---------------------------------------------------------------------------
-- Aggiornamento
---------------------------------------------------------------------------
function S:RefreshConditions()
  if not panel or not panel:IsShown() then return end
  local active = ns.Rules:ActiveSet()
  for _, row in ipairs(panel.conditions) do
    local enabled = ns.IsConditionEnabled(row.key)
    row.check:SetChecked(enabled)
    local label = row.check.label
    if not enabled then label:SetTextColor(0.5, 0.5, 0.5)
    elseif ns.db.mode == "auto" and ns.Rules.current == row.key then label:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    elseif active[row.key] then label:SetTextColor(0.3, 1, 0.3)
    else label:SetTextColor(1, 1, 1) end
    if row.dropdown then
      if row.dropdown.SetEnabled then row.dropdown:SetEnabled(enabled) end
      if row.dropdown.GenerateMenu then row.dropdown:GenerateMenu() end
    end
  end
end

function S:Refresh()
  if not panel then return end
  panel.optEnabled:SetChecked(ns.db.enabled)
  panel.optShuffle:SetChecked(ns.db.shuffle)
  panel.optMinimap:SetChecked(not ns.db.minimap.hide)
  panel.optLock:SetChecked(ns.db.ui.locked)
  if panel.lang and panel.lang.GenerateMenu then panel.lang:GenerateMenu() end
  -- la lingua scelta diversa da quella attiva: evidenzia il pulsante di ricarica
  local pending = (ns.db.lang or "auto") ~= (S.loadedLang or "auto")
  panel.langHint:SetTextColor(pending and 1 or 0.5, pending and 0.82 or 0.5, pending and 0 or 0.5)
  self:RefreshConditions()
end

---------------------------------------------------------------------------
-- Costruzione e apertura
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
end

function S:HasCategory()
  return category ~= nil
end

-- Trasforma il pannello in una finestra autonoma (se il pannello Opzioni di Blizzard non è usabile).
function S:MakeStandalone()
  if self.standalone then return end
  self.standalone = true
  panel:SetParent(UIParent)
  panel:ClearAllPoints()
  panel:SetSize(620, 560)
  panel:SetPoint("CENTER")
  panel:SetFrameStrata("DIALOG")
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  local border = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
  border:SetAllPoints()
  border:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.8)
  local bg = panel:CreateTexture(nil, "BACKGROUND", nil, -7)
  bg:SetPoint("TOPLEFT", 1, -1)
  bg:SetPoint("BOTTOMRIGHT", -1, 1)
  bg:SetColorTexture(0.06, 0.05, 0.05, 0.97)
  local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  panel.openLib:ClearAllPoints()
  panel.openLib:SetPoint("TOPRIGHT", -30, -16)
  panel:Hide()
  if UISpecialFrames then table.insert(UISpecialFrames, panel:GetName()) end
end

local function blizzardPanelShown()
  return SettingsPanel and SettingsPanel:IsShown() and panel:IsVisible()
end

function S:Open()
  if not panel then
    print("|cffff4040ZugZug Radio|r: impostazioni non disponibili (errore all'avvio, vedi /kzz debug)")
    return
  end
  ns.LibraryUI:Toggle(false) -- la libreria (strata HIGH) potrebbe coprire il pannello
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
      -- alcune versioni vogliono il pannello già aperto prima di selezionare la categoria
      ok, err = pcall(function()
        if ShowUIPanel then ShowUIPanel(SettingsPanel) else SettingsPanel:Show() end
        if SettingsPanel.SelectCategory then SettingsPanel:SelectCategory(category) end
      end)
      attempts[#attempts + 1] = "ShowUIPanel+SelectCategory: " .. (ok and "ok" or tostring(err))
    end
    local shown = blizzardPanelShown()
    attempts[#attempts + 1] = "risultato: " .. (shown and "aperto nelle Opzioni" or "non visibile -> finestra autonoma")
    ns.db.lastSettingsOpen = attempts
    if shown then return end
    if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then pcall(HideUIPanel, SettingsPanel) end
    self:MakeStandalone()
  end
  panel:Show()
  panel:Raise()
  self:Refresh()
end
