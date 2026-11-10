-- UI: "now playing" window with cover, time, controls and playlist choice.
local _, ns = ...
local L = ns.L

local UI = {}
ns.UI = UI

local DEFAULT_COVER = "Interface\\Icons\\INV_Misc_QuestionMark"
local ACCENT = { 1, 0.5, 0.1 }
local f -- main frame
local c, buildCompact, skinCompact -- compact player (defined further down)

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

-- Button with small text (translations can be long) and the addon font when needed.
function ns.MakeButton(parent, text, width, onClick, tooltip)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetNormalFontObject(ns.FontObject("GameFontNormalSmall"))
  b:SetHighlightFontObject(ns.FontObject("GameFontHighlightSmall"))
  b:SetDisabledFontObject(ns.FontObject("GameFontDisableSmall"))
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  b.kzzTooltip = tooltip
  if tooltip then
    b:SetScript("OnEnter", function(self) ns.ShowTooltip(self, "ANCHOR_TOP", { self.kzzTooltip }) end)
    b:SetScript("OnLeave", ns.HideTooltip)
  end
  return b
end

-- Modern dropdown (Menu API) with the addon font when needed.
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
    for _, name in ipairs(ns.AllPlaylistNames()) do
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

  f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  f.close:SetSize(24, 24)
  f.close:SetPoint("TOPRIGHT", 2, 2)
  f.close:SetScript("OnClick", function() UI:Toggle(false) end)

  f.cover = f:CreateTexture(nil, "ARTWORK")
  f.cover:SetSize(96, 96)
  f.cover:SetPoint("TOPLEFT", 10, -10)

  local textWidth = f:GetWidth() - 96 - 10 - 10 - 12
  f.situation = f:CreateFontString(nil, "OVERLAY", ns.Font("GameFontNormalSmall"))
  f.situation:SetPoint("TOPLEFT", f.cover, "TOPRIGHT", 10, -2)
  f.situation:SetWidth(textWidth - 14) -- room for the close button
  f.situation:SetJustifyH("LEFT")
  f.situation:SetWordWrap(false)

  -- title/artist can be in any language, so they use the addon font when needed
  f.title = f:CreateFontString(nil, "OVERLAY", ns.Font("GameFontHighlightLarge"))
  f.title:SetPoint("TOPLEFT", f.situation, "BOTTOMLEFT", 0, -6)
  f.title:SetWidth(textWidth)
  f.title:SetJustifyH("LEFT")
  f.title:SetWordWrap(false)

  -- favourite star next to the title
  f.fav = CreateFrame("Button", nil, f)
  f.fav:SetSize(16, 16)
  f.fav:SetPoint("LEFT", f.title, "RIGHT", 4, 0)
  f.fav:SetNormalTexture("Interface\\Common\\FavoritesIcon")
  f.fav:SetScript("OnClick", function() ns.ToggleFavorite(ns.Player.track) end)
  f.fav:SetScript("OnEnter", function(self) ns.ShowTooltip(self, "ANCHOR_TOP", { L.TT_FAVORITE }) end)
  f.fav:SetScript("OnLeave", ns.HideTooltip)

  -- minimize to the compact player
  f.mini = CreateFrame("Button", nil, f)
  f.mini:SetSize(24, 24)
  f.mini:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
  f.mini:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
  f.mini:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
  f.mini:SetScript("OnClick", function() UI:SetCompact(true) end)
  f.mini:SetScript("OnEnter", function(self) ns.ShowTooltip(self, "ANCHOR_TOP", { L.TT_COMPACT }) end)
  f.mini:SetScript("OnLeave", ns.HideTooltip)

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
  f.barBg = f.bar:CreateTexture(nil, "BACKGROUND")
  f.barBg:SetAllPoints()
  f.barBg:SetColorTexture(1, 1, 1, 0.12)

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
  -- podcast only: whole-episode navigation (prev/next move by one 2:30 part)
  f.epPrev = ns.MakeButton(f, "|<<", 34, function() P:SkipTrack(-1) end, L.TT_PREV_EPISODE)
  f.epNext = ns.MakeButton(f, ">>|", 34, function() P:SkipTrack(1) end, L.TT_NEXT_EPISODE)
  f.lib = ns.MakeButton(f, L.LIBRARY, 70, function() ns.LibraryUI:Toggle() end, L.TT_LIBRARY)
  UI:LayoutButtons(false)

  -- volume (the game's Music volume), under the cover
  f.volIcon = f:CreateTexture(nil, "ARTWORK")
  f.volIcon:SetTexture("Interface\\Common\\VoiceChat-Speaker")
  f.volIcon:SetSize(16, 16)
  f.vol = CreateFrame("Slider", nil, f, "BackdropTemplate")
  f.vol:SetOrientation("HORIZONTAL")
  f.vol:SetHeight(14)
  f.vol:SetMinMaxValues(0, 100)
  f.vol:SetValueStep(1)
  if f.vol.SetObeyStepDrag then f.vol:SetObeyStepDrag(true) end -- missing on the Forever client
  if f.vol.SetBackdrop then
    f.vol:SetBackdrop({ bgFile = "Interface\\Buttons\\UI-SliderBar-Background", edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
                        tile = true, tileSize = 8, edgeSize = 8, insets = { left = 3, right = 3, top = 6, bottom = 6 } })
  end
  f.vol:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  local thumb = f.vol:GetThumbTexture()
  if thumb then thumb:SetSize(24, 24) end
  f.vol:EnableMouseWheel(true)
  f.vol:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self:GetValue() + delta * 5) end)
  f.vol:SetScript("OnValueChanged", function(self, value)
    if UI.syncingVolume then return end
    P:SetVolume(math.floor(value + 0.5) / 100)
  end)
  local function volTip(self)
    ns.ShowTooltip(self, "ANCHOR_TOP", { L.TT_VOLUME:format(math.floor(P:GetVolume() * 100 + 0.5)) })
  end
  f.vol:SetScript("OnEnter", volTip)
  f.vol:SetScript("OnLeave", ns.HideTooltip)
  ns.On("VOLUME_CHANGED", function() UI:SyncVolume() end)

  f.dropdown = setupDropdown()
  if f.dropdown then f.dropdown:SetPoint("BOTTOMLEFT", 8, 8) end

  self:ApplySkin()

  local throttle = 0
  f:SetScript("OnUpdate", function(_, dt)
    throttle = throttle + dt
    if throttle >= 0.25 then throttle = 0 UI:RefreshProgress() end
  end)

  local refresh = ns.Profiled("UI:Refresh", function() UI:Refresh() end)
  for _, ev in ipairs({ "TRACK_CHANGED", "STATE_CHANGED", "SITUATION_CHANGED", "MODE_CHANGED", "PLAYLISTS_CHANGED" }) do
    ns.On(ev, refresh)
  end
  -- the dropdown menu is only rebuilt when its content can change
  for _, ev in ipairs({ "MODE_CHANGED", "PLAYLISTS_CHANGED" }) do
    ns.On(ev, function() if f.dropdown and f.dropdown.GenerateMenu then f.dropdown:GenerateMenu() end end)
  end
  buildCompact()
  skinCompact()
  ns.On("SETTINGS_CHANGED", skinCompact)
  self:UpdateVisibility()
  self:Refresh()
end

---------------------------------------------------------------------------
-- Skins: "classic" (original WoW dialog look, default) and "modern" (flat).
-- Only textures that exist in the client's listfile are used.
---------------------------------------------------------------------------
local CLASSIC_BACKDROP = {
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", tile = true, tileSize = 32,
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 26,
  insets = { left = 8, right = 8, top = 8, bottom = 8 },
}
local THIN_BORDER = { edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 }
local MODERN_BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }

-- Classic gold header in three slices (end caps + stretchable middle), so it can grow with
-- the text it holds. Texture coordinates of UI-DialogBox-Header as used by classic-style frames.
local HEADER_TEX = "Interface\\DialogFrame\\UI-DialogBox-Header"
local HEADER_CAP, HEADER_HEIGHT, HEADER_PAD = 30, 40, 24

local function textWidthOf(fs)
  local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()
  if type(w) ~= "number" or w <= 0 then w = fs:GetStringWidth() end
  return type(w) == "number" and w or 0
end

-- The textures live on the parent itself (ARTWORK) so the title font string (OVERLAY) stays on top.
function ns.CreateHeader(parent)
  local h = {}
  h.mid = parent:CreateTexture(nil, "ARTWORK", nil, 7)
  h.mid:SetTexture(HEADER_TEX)
  h.mid:SetTexCoord(0.31, 0.67, 0, 0.63)
  h.mid:SetHeight(HEADER_HEIGHT)
  h.left = parent:CreateTexture(nil, "ARTWORK", nil, 7)
  h.left:SetTexture(HEADER_TEX)
  h.left:SetTexCoord(0.21, 0.31, 0, 0.63)
  h.left:SetSize(HEADER_CAP, HEADER_HEIGHT)
  h.left:SetPoint("RIGHT", h.mid, "LEFT")
  h.right = parent:CreateTexture(nil, "ARTWORK", nil, 7)
  h.right:SetTexture(HEADER_TEX)
  h.right:SetTexCoord(0.67, 0.77, 0, 0.63)
  h.right:SetSize(HEADER_CAP, HEADER_HEIGHT)
  h.right:SetPoint("LEFT", h.mid, "RIGHT")
  function h:Place(owner)
    self.mid:ClearAllPoints()
    self.mid:SetPoint("TOP", owner, "TOP", 0, 12)
  end
  function h:SetShown(show)
    for _, t in ipairs({ self.mid, self.left, self.right }) do t:SetShown(show) end
  end
  -- Sizes the middle to fit fs's text (never wider than maxWidth overall) and puts fs inside.
  -- Returns the text width available, so the caller can truncate anything longer.
  function h:Fit(fs, maxWidth)
    local w = math.max(80, math.min(textWidthOf(fs) + HEADER_PAD, maxWidth - 2 * HEADER_CAP))
    self.mid:SetWidth(w)
    fs:ClearAllPoints()
    fs:SetPoint("TOP", self.mid, "TOP", 0, -13)
    fs:SetWidth(w - 8)
    return w
  end
  return h
end

local decorated = false -- classic-only textures/frames created (lazily, once)
local function classicDecorations()
  if decorated then return end
  decorated = true
  f.header = ns.CreateHeader(f)
  f.coverBorder = CreateFrame("Frame", nil, f, "BackdropTemplate")
  f.coverBorder:SetPoint("TOPLEFT", f.cover, "TOPLEFT", -4, 4)
  f.coverBorder:SetPoint("BOTTOMRIGHT", f.cover, "BOTTOMRIGHT", 4, -4)
  f.barBorder = CreateFrame("Frame", nil, f.bar, "BackdropTemplate")
  f.barBorder:SetPoint("TOPLEFT", -3, 3)
  f.barBorder:SetPoint("BOTTOMRIGHT", 3, -3)
  for _, b in ipairs({ f.coverBorder, f.barBorder }) do
    if b.SetBackdrop then
      b:SetBackdrop(THIN_BORDER)
      b:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
    end
  end
end

function UI:ApplySkin()
  if not f then return end
  local classic = (ns.db.ui.skin or "classic") == "classic"
  local textWidth
  if classic then
    classicDecorations()
    f:SetSize(480, 188)
    f:SetBackdrop(CLASSIC_BACKDROP)
    f:SetBackdropColor(1, 1, 1, 1)
    f:SetBackdropBorderColor(1, 1, 1, 1)
    f.header:Place(f)
    f.header:SetShown(true)
    f.coverBorder:Show()
    f.barBorder:Show()
    f.close:ClearAllPoints()
    f.close:SetPoint("TOPRIGHT", -4, -4)
    f.cover:SetSize(88, 88)
    f.cover:ClearAllPoints()
    f.cover:SetPoint("TOPLEFT", 18, -30)
    textWidth = 480 - 18 - 88 - 12 - 18
    -- the status line goes inside the gold header, like a classic window title
    UI.statusFont = "GameFontNormal"
    f.situation:SetJustifyH("CENTER") -- position and width: header:Fit in UI:Refresh
    f.title:ClearAllPoints()
    f.title:SetPoint("TOPLEFT", f.cover, "TOPRIGHT", 12, -4)
    f.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    f.bar:SetStatusBarColor(1, 0.7, 0)
    f.bar:ClearAllPoints()
    f.bar:SetPoint("BOTTOMLEFT", f.cover, "BOTTOMRIGHT", 12, 16)
    f.bar:SetSize(textWidth, 10)
    f.barBg:SetColorTexture(0, 0, 0, 0.6)
    f.shuffle:ClearAllPoints()
    f.shuffle:SetPoint("BOTTOMRIGHT", -14, 12)
    f.volIcon:ClearAllPoints()
    f.volIcon:SetPoint("TOPLEFT", f.cover, "BOTTOMLEFT", -2, -8)
    f.vol:SetWidth(88 - 18)
    if f.dropdown then
      f.dropdown:ClearAllPoints()
      f.dropdown:SetPoint("BOTTOMLEFT", 12, 12)
    end
  else
    f:SetSize(470, 168)
    f:SetBackdrop(MODERN_BACKDROP)
    f:SetBackdropColor(0.06, 0.05, 0.05, 0.92)
    f:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.8)
    if decorated then f.header:SetShown(false) f.coverBorder:Hide() f.barBorder:Hide() end
    f.close:ClearAllPoints()
    f.close:SetPoint("TOPRIGHT", 2, 2)
    f.cover:SetSize(96, 96)
    f.cover:ClearAllPoints()
    f.cover:SetPoint("TOPLEFT", 10, -10)
    textWidth = 470 - 96 - 10 - 10 - 12
    UI.statusFont = "GameFontNormalSmall"
    f.situation:ClearAllPoints()
    f.situation:SetPoint("TOPLEFT", f.cover, "TOPRIGHT", 10, -2)
    f.situation:SetWidth(textWidth - 14) -- room for the close button
    f.situation:SetJustifyH("LEFT")
    f.title:ClearAllPoints()
    f.title:SetPoint("TOPLEFT", f.situation, "BOTTOMLEFT", 0, -6)
    f.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    f.bar:SetStatusBarColor(ACCENT[1], ACCENT[2], ACCENT[3])
    f.bar:ClearAllPoints()
    f.bar:SetPoint("BOTTOMLEFT", f.cover, "BOTTOMRIGHT", 10, 16)
    f.bar:SetSize(textWidth, 6)
    f.barBg:SetColorTexture(1, 1, 1, 0.12)
    f.shuffle:ClearAllPoints()
    f.shuffle:SetPoint("BOTTOMRIGHT", -10, 8)
    f.volIcon:ClearAllPoints()
    f.volIcon:SetPoint("TOPLEFT", f.cover, "BOTTOMLEFT", -2, -8)
    f.vol:SetWidth(96 - 18)
    if f.dropdown then
      f.dropdown:ClearAllPoints()
      f.dropdown:SetPoint("BOTTOMLEFT", 8, 8)
    end
  end
  f.title:SetWidth(textWidth - 22) -- room for the favourite star
  f.artist:SetWidth(textWidth)
  f.mini:ClearAllPoints()
  f.mini:SetPoint("RIGHT", f.close, "LEFT", 4, 0)
  f.vol:ClearAllPoints()
  f.vol:SetPoint("LEFT", f.volIcon, "RIGHT", 2, 0)
  f.situation.kzzFont = nil -- force the status font to be re-applied
  self:Refresh()
end

function UI:HasClassicDecorations() return decorated end

-- Skins any window (a BackdropTemplate frame): classic dialog border + gold header holding
-- the title, or the flat modern look. closeBtn is moved inside the classic border.
local windowHeaders = setmetatable({}, { __mode = "k" })
function ns.SkinWindow(win, titleFS, closeBtn)
  local classic = (ns.db.ui.skin or "classic") == "classic"
  local header = windowHeaders[win]
  if classic then
    if win.SetBackdrop then
      win:SetBackdrop(CLASSIC_BACKDROP)
      win:SetBackdropColor(1, 1, 1, 1)
      win:SetBackdropBorderColor(1, 1, 1, 1)
    end
    if not header then
      header = ns.CreateHeader(win)
      windowHeaders[win] = header
    end
    header:Place(win)
    header:SetShown(true)
    if titleFS then
      header:Fit(titleFS, (tonumber(win:GetWidth()) or 400) - 40)
    else
      header.mid:SetWidth(200)
    end
    if closeBtn then
      closeBtn:ClearAllPoints()
      closeBtn:SetPoint("TOPRIGHT", -4, -4)
    end
  else
    if win.SetBackdrop then
      win:SetBackdrop(MODERN_BACKDROP)
      win:SetBackdropColor(0.06, 0.05, 0.05, 0.96)
      win:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.8)
    end
    if header then header:SetShown(false) end
    if titleFS then
      titleFS:ClearAllPoints()
      titleFS:SetPoint("TOPLEFT", 14, -12)
    end
    if closeBtn then
      closeBtn:ClearAllPoints()
      closeBtn:SetPoint("TOPRIGHT", 2, 2)
    end
  end
end

---------------------------------------------------------------------------
-- Share dialog: shows a playlist as text to copy, or takes a pasted one.
---------------------------------------------------------------------------
local dlg
local function shareDialog()
  if dlg then return dlg end
  dlg = CreateFrame("Frame", "KalimdorZugZugShareDialog", UIParent, "BackdropTemplate")
  dlg:SetSize(460, 220)
  dlg:SetPoint("CENTER")
  dlg:SetFrameStrata("DIALOG")
  dlg:EnableMouse(true)
  dlg:SetMovable(true)
  dlg:RegisterForDrag("LeftButton")
  dlg:SetScript("OnDragStart", dlg.StartMoving)
  dlg:SetScript("OnDragStop", dlg.StopMovingOrSizing)
  dlg.title = dlg:CreateFontString(nil, "OVERLAY", ns.Font("GameFontNormal"))
  dlg.close = CreateFrame("Button", nil, dlg, "UIPanelCloseButton")
  dlg.hint = dlg:CreateFontString(nil, "OVERLAY", ns.Font("GameFontHighlightSmall"))
  dlg.hint:SetPoint("TOPLEFT", 22, -36)
  dlg.hint:SetPoint("RIGHT", -22, 0)
  dlg.hint:SetJustifyH("LEFT")
  local box = CreateFrame("Frame", nil, dlg, "BackdropTemplate")
  box:SetPoint("TOPLEFT", 18, -56)
  box:SetPoint("BOTTOMRIGHT", -18, 44)
  if box.SetBackdrop then
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
                      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    box:SetBackdropColor(0, 0, 0, 0.6)
  end
  dlg.edit = CreateFrame("EditBox", nil, box)
  dlg.edit:SetMultiLine(true)
  dlg.edit:SetAutoFocus(false)
  dlg.edit:SetFontObject(ns.FontObject("ChatFontNormal") or ChatFontNormal)
  dlg.edit:SetPoint("TOPLEFT", 8, -8)
  dlg.edit:SetPoint("BOTTOMRIGHT", -8, 8)
  dlg.edit:SetScript("OnEscapePressed", function() dlg:Hide() end)
  dlg.ok = ns.MakeButton(dlg, L.OK, 90, function() if dlg.onOk then dlg.onOk(dlg.edit:GetText()) end end)
  dlg.ok:SetPoint("BOTTOMRIGHT", -18, 14)
  dlg:Hide()
  if UISpecialFrames then table.insert(UISpecialFrames, dlg:GetName()) end
  return dlg
end

-- mode "export": text to copy; mode "import": onOk(text) is called with the pasted text.
function ns.ShowShareDialog(mode, textOrNil, onOk)
  local d = shareDialog()
  d.title:SetText(mode == "export" and L.EXPORT_TITLE or L.IMPORT_TITLE)
  ns.SkinWindow(d, d.title, d.close)
  d.hint:SetText(mode == "export" and L.TT_EXPORT or L.TT_IMPORT)
  d.edit:SetText(textOrNil or "")
  d.onOk = onOk
  d.ok:SetShown(mode == "import")
  d:Show()
  d.edit:SetFocus()
  if mode == "export" then d.edit:HighlightText() end
end

-- Transport row, right to left: shuffle, [>>|], >|, >, |<, [|<<], Library.
-- The episode buttons only exist on podcasts; the row closes up without them.
function UI:LayoutButtons(podcast)
  if f.kzzPodcastLayout == podcast then return end
  f.kzzPodcastLayout = podcast
  f.epPrev:SetShown(podcast)
  f.epNext:SetShown(podcast)
  for _, b in ipairs({ f.epNext, f.next, f.play, f.prev, f.epPrev, f.lib }) do b:ClearAllPoints() end
  local right = f.shuffle
  local chain = podcast and { f.epNext, f.next, f.play, f.prev, f.epPrev } or { f.next, f.play, f.prev }
  for i, b in ipairs(chain) do
    b:SetPoint("RIGHT", right, "LEFT", i == 1 and -4 or -2, 0)
    right = b
  end
  f.lib:SetPoint("RIGHT", right, "LEFT", -6, 0)
end

-- Shows the current Music volume on the slider (without writing it back).
function UI:SyncVolume()
  if not f or not f.vol then return end
  UI.syncingVolume = true
  f.vol:SetValue(math.floor(ns.Player:GetVolume() * 100 + 0.5))
  UI.syncingVolume = false
end

function UI:SetSkin(skin)
  ns.db.ui.skin = skin
  self:ApplySkin()
  ns.Fire("SETTINGS_CHANGED")
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
    if track.parts then -- podcast: which part we're at
      sub = sub .. "  ·  " .. L.PART_FMT:format(ns.EpisodePart(track), #track.parts)
    end
    ns.SetText(f.artist, sub, "GameFontHighlightSmall")
    f.artist:SetTextColor(0.75, 0.75, 0.75)
    f.cover:SetTexture(ns.CoverOf(track) or DEFAULT_COVER)
  else
    f.title:SetText(L.NO_TRACK)
    if #ns.tracks == 0 and #ns.episodes == 0 then
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
    -- orange: free play ignores the conditions, make it obvious
    status = "|cffff9a1a" .. L.STATUS_FREE .. "|r  ·  " .. ns.PlaylistLabel(ns.db.mode)
  end
  ns.SetText(f.situation, status, UI.statusFont or "GameFontNormalSmall")
  if decorated and (ns.db.ui.skin or "classic") == "classic" then
    -- the gold header grows with the status text (truncated only beyond the player's width)
    f.header:Fit(f.situation, f:GetWidth() - 40)
  end

  f.play:SetText(P.playing and "||" or ">")
  f.fav:SetShown(track ~= nil)
  local favTex = f.fav:GetNormalTexture()
  if favTex then
    local isFav = ns.IsFavorite(track)
    favTex:SetDesaturated(not isFav)
    favTex:SetAlpha(isFav and 1 or 0.45)
  end
  self:RefreshCompact()
  local podcast = track and track.parts ~= nil
  UI:LayoutButtons(podcast)
  f.prev.kzzTooltip = podcast and L.TT_PREV_PART or L.TT_PREV
  f.next.kzzTooltip = podcast and L.TT_NEXT_PART or L.TT_NEXT
  self:SyncVolume()
  local fs = f.shuffle:GetFontString()
  if fs then
    if ns.db.shuffle then fs:SetTextColor(0.3, 1, 0.3) else fs:SetTextColor(0.6, 0.6, 0.6) end
  end
  self:RefreshProgress()
end

function UI:Toggle(show)
  if not f then return end
  if show == nil then show = not ns.db.ui.shown end
  ns.db.ui.shown = show
  self:UpdateVisibility()
end

function UI:UpdateVisibility()
  local compact = ns.db.ui.compact
  f:SetShown(ns.db.ui.shown and not compact)
  if self.compactFrame then self.compactFrame:SetShown(ns.db.ui.shown and compact) end
end

---------------------------------------------------------------------------
-- Compact player: a small bar with cover, title and the transport buttons.
---------------------------------------------------------------------------
function buildCompact()
  if c then return end
  c = CreateFrame("Frame", "KalimdorZugZugRadioCompact", UIParent, "BackdropTemplate")
  UI.compactFrame = c
  c:SetSize(330, 36)
  c:SetFrameStrata("MEDIUM")
  c:SetClampedToScreen(true)
  c:SetMovable(true)
  c:EnableMouse(true)
  c:RegisterForDrag("LeftButton")
  c:SetScript("OnDragStart", function(self) if not ns.db.ui.locked then self:StartMoving() end end)
  c:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint(1)
    ns.db.ui.compactPoint = { point, relPoint, x, y }
  end)
  local pt = ns.db.ui.compactPoint
  if pt then c:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4]) else c:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -260, 260) end
  c.cover = c:CreateTexture(nil, "ARTWORK")
  c.cover:SetSize(26, 26)
  c.cover:SetPoint("LEFT", 6, 0)
  local P = ns.Player
  c.expand = CreateFrame("Button", nil, c)
  c.expand:SetSize(22, 22)
  c.expand:SetPoint("RIGHT", -4, 0)
  c.expand:SetNormalTexture("Interface\\Buttons\\UI-Panel-ExpandButton-Up")
  c.expand:SetScript("OnClick", function() UI:SetCompact(false) end)
  c.expand:SetScript("OnEnter", function(self) ns.ShowTooltip(self, "ANCHOR_TOP", { L.TT_EXPAND }) end)
  c.expand:SetScript("OnLeave", ns.HideTooltip)
  c.next = ns.MakeButton(c, ">|", 28, function() P:Next() end, L.TT_NEXT)
  c.next:SetPoint("RIGHT", c.expand, "LEFT", -2, 0)
  c.play = ns.MakeButton(c, ">", 28, function() P:Toggle() end, L.TT_PLAY)
  c.play:SetPoint("RIGHT", c.next, "LEFT", -2, 0)
  c.prev = ns.MakeButton(c, "|<", 28, function() P:Prev() end, L.TT_PREV)
  c.prev:SetPoint("RIGHT", c.play, "LEFT", -2, 0)
  c.title = c:CreateFontString(nil, "OVERLAY", ns.Font("GameFontHighlightSmall"))
  c.title:SetPoint("LEFT", c.cover, "RIGHT", 6, 0)
  c.title:SetPoint("RIGHT", c.prev, "LEFT", -6, 0)
  c.title:SetJustifyH("LEFT")
  c.title:SetWordWrap(false)
end

function skinCompact()
  if not c or not c.SetBackdrop then return end
  if (ns.db.ui.skin or "classic") == "classic" then
    c:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    c:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
    c:SetBackdropBorderColor(1, 0.82, 0, 1)
  else
    c:SetBackdrop(MODERN_BACKDROP)
    c:SetBackdropColor(0.06, 0.05, 0.05, 0.92)
    c:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.8)
  end
end

function UI:RefreshCompact()
  if not c then return end
  local P = ns.Player
  local t = P.track
  c.cover:SetTexture(ns.CoverOf(t) or DEFAULT_COVER)
  ns.SetText(c.title, t and ns.TrackLabel(t) or L.NO_TRACK, "GameFontHighlightSmall")
  c.play:SetText(P.playing and "||" or ">")
end

function UI:SetCompact(on)
  ns.db.ui.compact = on and true or false
  buildCompact()
  skinCompact()
  self:RefreshCompact()
  self:UpdateVisibility()
  ns.Fire("SETTINGS_CHANGED")
end

function UI:ResetPosition()
  ns.db.ui.point = nil
  if f then applyPosition() f:Show() ns.db.ui.shown = true end
end
