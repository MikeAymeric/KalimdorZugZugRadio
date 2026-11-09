-- UI: finestra "now playing" con copertina, tempo, controlli e scelta playlist.
local _, ns = ...
local L = ns.L

local UI = {}
ns.UI = UI

local DEFAULT_COVER = "Interface\\Icons\\INV_Misc_QuestionMark"
local ACCENT = { 1, 0.5, 0.1 }
local f -- frame principale

local function savePosition()
  local point, _, relPoint, x, y = f:GetPoint(1)
  ns.db.ui.point = { point, relPoint, x, y }
end

local function applyPosition()
  f:ClearAllPoints()
  local p = ns.db.ui.point
  if p then
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -260, 220)
  end
end

-- Pulsante con testo piccolo (le traduzioni possono essere lunghe) e font dell'addon se serve.
function ns.MakeButton(parent, text, width, onClick, tooltip)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetNormalFontObject(ns.FontObject("GameFontNormalSmall"))
  b:SetHighlightFontObject(ns.FontObject("GameFontHighlightSmall"))
  b:SetDisabledFontObject(ns.FontObject("GameFontDisableSmall"))
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  if tooltip then
    b:SetScript("OnEnter", function(self) ns.ShowTooltip(self, "ANCHOR_TOP", { tooltip }) end)
    b:SetScript("OnLeave", ns.HideTooltip)
  end
  return b
end

-- Dropdown moderno (Menu API) con il font dell'addon se serve.
function ns.MakeDropdown(parent, width, defaultText, generator)
  local ok, dd = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
  if not ok or not dd or not dd.SetupMenu then return nil end
  dd:SetWidth(width)
  dd:SetDefaultText(defaultText)
  if ns.useAddonFont and dd.Text then dd.Text:SetFontObject(ns.FontObject("GameFontHighlightSmall")) end
  dd:SetupMenu(generator)
  return dd
end

local function setupDropdown()
  return ns.MakeDropdown(f, 140, L.PLAYLIST, function(_, root)
    ns.StyleMenuItem(root:CreateRadio(L.AUTO_CONDITIONS,
      function() return ns.db.mode == "auto" end,
      function() ns.SetMode("auto") end))
    root:CreateDivider()
    local names = ns.PlaylistNames()
    table.insert(names, 1, ns.ALL)
    for _, name in ipairs(names) do
      local count = #ns.GetPlaylist(name).tracks
      local radio = root:CreateRadio(("%s (%d)"):format(ns.PlaylistLabel(name), count),
        function() return ns.db.mode == name end,
        function() ns.SetMode(name) end)
      ns.StyleMenuItem(radio, ns.HasCJK(name))
      if count == 0 and radio.SetEnabled then radio:SetEnabled(false) end
    end
    root:CreateDivider()
    ns.StyleMenuItem(root:CreateButton(L.MANAGE_LIBRARY, function() ns.LibraryUI:Toggle(true) end))
    ns.StyleMenuItem(root:CreateButton(L.MENU_SETTINGS, function() ns.Settings:Open() end))
  end)
end

function UI:Build()
  if f then return end
  f = CreateFrame("Frame", "KalimdorZugZugRadioFrame", UIParent, "BackdropTemplate")
  f:SetSize(410, 146)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) if not ns.db.ui.locked then self:StartMoving() end end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() savePosition() end)
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  f:SetBackdropColor(0.06, 0.05, 0.05, 0.92)
  f:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.8)
  applyPosition()

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetSize(24, 24)
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() UI:Toggle(false) end)

  f.cover = f:CreateTexture(nil, "ARTWORK")
  f.cover:SetSize(96, 96)
  f.cover:SetPoint("TOPLEFT", 10, -10)

  local textWidth = f:GetWidth() - 96 - 10 - 10 - 12
  f.situation = f:CreateFontString(nil, "OVERLAY", ns.Font("GameFontNormalSmall"))
  f.situation:SetPoint("TOPLEFT", f.cover, "TOPRIGHT", 10, -2)
  f.situation:SetWidth(textWidth - 14) -- spazio per il pulsante di chiusura
  f.situation:SetJustifyH("LEFT")
  f.situation:SetWordWrap(false)

  -- titolo/artista: possono essere in qualsiasi lingua, quindi usano il font dell'addon se serve
  f.title = f:CreateFontString(nil, "OVERLAY", ns.Font("GameFontHighlightLarge"))
  f.title:SetPoint("TOPLEFT", f.situation, "BOTTOMLEFT", 0, -6)
  f.title:SetWidth(textWidth)
  f.title:SetJustifyH("LEFT")
  f.title:SetWordWrap(false)

  f.artist = f:CreateFontString(nil, "OVERLAY", ns.Font("GameFontHighlightSmall"))
  f.artist:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
  f.artist:SetWidth(textWidth)
  f.artist:SetJustifyH("LEFT")
  f.artist:SetWordWrap(false)
  f.artist:SetTextColor(0.75, 0.75, 0.75)

  f.bar = CreateFrame("StatusBar", nil, f)
  f.bar:SetPoint("BOTTOMLEFT", f.cover, "BOTTOMRIGHT", 10, 16)
  f.bar:SetSize(textWidth, 6)
  f.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  f.bar:SetStatusBarColor(ACCENT[1], ACCENT[2], ACCENT[3])
  f.bar:SetMinMaxValues(0, 1)
  local barBg = f.bar:CreateTexture(nil, "BACKGROUND")
  barBg:SetAllPoints()
  barBg:SetColorTexture(1, 1, 1, 0.12)

  f.elapsed = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.elapsed:SetPoint("TOPLEFT", f.bar, "BOTTOMLEFT", 0, -3)
  f.remaining = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.remaining:SetPoint("TOPRIGHT", f.bar, "BOTTOMRIGHT", 0, -3)

  local P = ns.Player
  f.prev = ns.MakeButton(f, "|<", 32, function() P:Prev() end, L.TT_PREV)
  f.play = ns.MakeButton(f, ">", 32, function() P:Toggle() end, L.TT_PLAY)
  f.next = ns.MakeButton(f, ">|", 32, function() P:Next() end, L.TT_NEXT)
  f.shuffle = ns.MakeButton(f, L.SHUFFLE, 64, function() P:SetShuffle(not ns.db.shuffle) end, L.TT_SHUFFLE)
  f.shuffle:SetPoint("BOTTOMRIGHT", -10, 8)
  f.next:SetPoint("RIGHT", f.shuffle, "LEFT", -4, 0)
  f.play:SetPoint("RIGHT", f.next, "LEFT", -2, 0)
  f.prev:SetPoint("RIGHT", f.play, "LEFT", -2, 0)
  f.lib = ns.MakeButton(f, L.LIBRARY, 70, function() ns.LibraryUI:Toggle() end, L.TT_LIBRARY)
  f.lib:SetPoint("RIGHT", f.prev, "LEFT", -6, 0)

  f.dropdown = setupDropdown()
  if f.dropdown then f.dropdown:SetPoint("BOTTOMLEFT", 8, 8) end

  local throttle = 0
  f:SetScript("OnUpdate", function(_, dt)
    throttle = throttle + dt
    if throttle >= 0.25 then throttle = 0 UI:RefreshProgress() end
  end)

  for _, ev in ipairs({ "TRACK_CHANGED", "STATE_CHANGED", "SITUATION_CHANGED", "MODE_CHANGED", "PLAYLISTS_CHANGED" }) do
    ns.On(ev, function() UI:Refresh() end)
  end
  f:SetShown(ns.db.ui.shown)
  self:Refresh()
end

function UI:RefreshProgress()
  local P = ns.Player
  local dur = P.track and tonumber(P.track.duration) or 0
  local el = math.min(P:Elapsed(), dur > 0 and dur or math.huge)
  f.bar:SetMinMaxValues(0, dur > 0 and dur or 1)
  f.bar:SetValue(dur > 0 and el or 0)
  if P.track and P.playing then
    f.elapsed:SetText(ns.FormatTime(el))
    f.remaining:SetText(dur > 0 and ("-" .. ns.FormatTime(dur - el)) or "")
  else
    f.elapsed:SetText("")
    f.remaining:SetText(dur > 0 and ns.FormatTime(dur) or "")
  end
end

function UI:Refresh()
  if not f then return end
  local P = ns.Player
  local track = P.track

  if track then
    ns.SetText(f.title, track.title or "?", "GameFontHighlightLarge")
    local sub = track.artist or ""
    if track.album and track.album ~= "" then
      sub = sub ~= "" and (sub .. "  -  " .. track.album) or track.album
    end
    ns.SetText(f.artist, sub, "GameFontHighlightSmall")
    f.artist:SetTextColor(0.75, 0.75, 0.75)
    f.cover:SetTexture(track.cover and (ns.ROOT .. track.cover) or DEFAULT_COVER)
  else
    f.title:SetText(L.NO_TRACK)
    if #ns.tracks == 0 then
      f.artist:SetText(L.HINT_EMPTY_LIBRARY)
    elseif ns.db.mode == "auto" then
      f.artist:SetText(L.HINT_NO_PLAYLIST)
    else
      f.artist:SetText("")
    end
    f.cover:SetTexture(DEFAULT_COVER)
  end

  local status
  if not ns.db.enabled then
    status = "|cff808080" .. L.STATUS_RADIO_OFF .. "|r  (/kzz on)"
  elseif ns.db.mode == "auto" then
    local key = ns.Rules.current
    status = L.STATUS_AUTO .. "  ·  " .. (key and ns.SituationLabel(key) or L.ZONE_MUSIC)
    if P.playlist then status = status .. "  ·  " .. ns.PlaylistLabel(P.playlist) end
  else
    status = L.STATUS_FREE .. "  ·  " .. ns.PlaylistLabel(ns.db.mode)
  end
  ns.SetText(f.situation, status, "GameFontNormalSmall")

  f.play:SetText(P.playing and "||" or ">")
  local fs = f.shuffle:GetFontString()
  if fs then
    if ns.db.shuffle then fs:SetTextColor(0.3, 1, 0.3) else fs:SetTextColor(0.6, 0.6, 0.6) end
  end
  if f.dropdown and f.dropdown.GenerateMenu then f.dropdown:GenerateMenu() end
  self:RefreshProgress()
end

function UI:Toggle(show)
  if not f then return end
  if show == nil then show = not f:IsShown() end
  f:SetShown(show)
  ns.db.ui.shown = show
end

function UI:ResetPosition()
  ns.db.ui.point = nil
  if f then applyPosition() f:Show() ns.db.ui.shown = true end
end
