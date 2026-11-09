-- LibraryUI: finestra per creare playlist e scegliere i brani (condizioni e lingua sono in Settings.lua).
local _, ns = ...
local L = ns.L

local LUI = { selected = nil } -- selected = nome playlist selezionata (ns.ALL = tutta la libreria)
ns.LibraryUI = LUI

local ACCENT = { 1, 0.5, 0.1 }
local f

---------------------------------------------------------------------------
-- Widget di base
---------------------------------------------------------------------------
local function button(parent, text, width, onClick, tooltip)
  return ns.MakeButton(parent, text, width, onClick, tooltip)
end

-- Allarga il pulsante quanto basta per il testo tradotto.
local function fitButton(b, minWidth)
  local fs = b:GetFontString()
  local w = fs and fs:GetStringWidth()
  if type(w) == "number" then b:SetWidth(math.max(minWidth, w + 24)) end
end

local function checkbox(parent, size)
  local c = CreateFrame("CheckButton", nil, parent)
  c:SetSize(size, size)
  c:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  c:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  c:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
  c:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  if c.SetDisabledCheckedTexture then c:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled") end
  return c
end

local function editbox(parent, width)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(width, 20)
  e:SetAutoFocus(false)
  if ns.useAddonFont then e:SetFontObject(ns.FontObject("ChatFontNormal")) end
  e:SetScript("OnEscapePressed", e.ClearFocus)
  e:SetScript("OnEnterPressed", e.ClearFocus)
  return e
end

local function text(parent, template)
  return parent:CreateFontString(nil, "OVERLAY", ns.Font(template))
end

local function header(parent, label, x, y)
  local h = text(parent, "GameFontNormal")
  h:SetPoint("TOPLEFT", x, y)
  h:SetText(label)
  return h
end

-- Lista virtuale: numRows righe riciclate + barra di scorrimento + rotella.
local function createList(parent, numRows, rowHeight, width, initRow, updateRow)
  local list = CreateFrame("Frame", nil, parent)
  list:SetSize(width, numRows * rowHeight)
  list.rows, list.data, list.offset = {}, {}, 0

  local bg = list:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.35)

  for i = 1, numRows do
    local row = CreateFrame("Button", nil, list)
    row:SetSize(width - 12, rowHeight)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints()
    row.sel:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.25)
    row.sel:Hide()
    initRow(row)
    list.rows[i] = row
  end

  local bar = CreateFrame("Slider", nil, list)
  bar:SetOrientation("VERTICAL")
  bar:SetPoint("TOPRIGHT")
  bar:SetPoint("BOTTOMRIGHT")
  bar:SetWidth(10)
  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints()
  track:SetColorTexture(1, 1, 1, 0.06)
  bar:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
  local thumb = bar:GetThumbTexture()
  thumb:SetSize(10, 30)
  thumb:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.7)
  bar:SetValueStep(1)
  if bar.SetObeyStepDrag then bar:SetObeyStepDrag(true) end -- non esiste sul client Forever
  bar:SetMinMaxValues(0, 0)
  bar:SetScript("OnValueChanged", function(_, value)
    list.offset = math.floor(value + 0.5)
    list:Update()
  end)

  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(_, delta)
    local _, max = bar:GetMinMaxValues()
    bar:SetValue(math.max(0, math.min(max, list.offset - delta * 3)))
  end)

  function list:Update()
    for i, row in ipairs(self.rows) do
      local item = self.data[self.offset + i]
      if item ~= nil then
        row.item = item
        updateRow(row, item)
        row:Show()
      else
        row.item = nil
        row:Hide()
      end
    end
  end

  function list:SetData(data)
    self.data = data
    local max = math.max(0, #data - numRows)
    bar:SetMinMaxValues(0, max)
    bar:SetShown(max > 0)
    if self.offset > max then self.offset = max end
    bar:SetValue(self.offset)
    self:Update()
  end

  return list
end

---------------------------------------------------------------------------
-- Colonna 1: playlist
---------------------------------------------------------------------------
local function selectedIsUser()
  return LUI.selected and LUI.selected ~= ns.ALL and ns.db.playlists[LUI.selected] ~= nil
end

local function buildPlaylistColumn()
  header(f, L.PLAYLISTS, 14, -40)

  f.playlists = createList(f, 13, 24, 210, function(row)
    row.text = text(row, "GameFontHighlight")
    row.text:SetPoint("LEFT", 6, 0)
    row.text:SetWidth(150)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.count:SetPoint("RIGHT", -4, 0)
    row:SetScript("OnClick", function(self)
      LUI.selected = self.item
      f.nameBox:SetText(self.item ~= ns.ALL and self.item or "")
      LUI:Refresh()
    end)
    row:SetScript("OnDoubleClick", function(self) ns.SetMode(self.item) end)
  end, function(row, name)
    ns.SetText(row.text, ns.PlaylistLabel(name), "GameFontHighlight")
    row.count:SetText(#ns.GetPlaylist(name).tracks)
    row.sel:SetShown(name == LUI.selected)
    if name == ns.db.mode then row.text:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    else row.text:SetTextColor(1, 1, 1) end
  end)
  f.playlists:SetPoint("TOPLEFT", 12, -60)

  f.nameBox = editbox(f, 200)
  f.nameBox:SetPoint("TOPLEFT", f.playlists, "BOTTOMLEFT", 6, -10)

  local function report(ok, errKey)
    if not ok and errKey then ns.Print(errKey) end
    return ok
  end

  f.create = button(f, L.CREATE, 66, function()
    local name, err = ns.CreatePlaylist(f.nameBox:GetText())
    if report(name, err) then
      LUI.selected = name
      f.onlyIn:SetChecked(false)
      LUI:Refresh()
    end
  end, L.TT_CREATE)
  f.create:SetPoint("TOPLEFT", f.nameBox, "BOTTOMLEFT", -6, -6)

  f.rename = button(f, L.RENAME, 70, function()
    if not selectedIsUser() then return end
    local name, err = ns.RenamePlaylist(LUI.selected, f.nameBox:GetText())
    if report(name, err) then LUI.selected = name LUI:Refresh() end
  end, L.TT_RENAME)
  f.rename:SetPoint("LEFT", f.create, "RIGHT", 4, 0)

  f.delete = button(f, L.DELETE, 66, function(self)
    if not selectedIsUser() then return end
    if not self.armed then
      self.armed = true
      self:SetText(L.CONFIRM)
      C_Timer.After(3, function() self.armed = false self:SetText(L.DELETE) end)
      return
    end
    self.armed = false
    self:SetText(L.DELETE)
    ns.DeletePlaylist(LUI.selected)
    LUI.selected = ns.ALL
    f.nameBox:SetText("")
    LUI:Refresh()
  end, L.TT_DELETE)
  f.delete:SetPoint("LEFT", f.rename, "RIGHT", 4, 0)

  f.playSel = button(f, L.PLAY_THIS, 210, function()
    if LUI.selected then ns.SetMode(LUI.selected) end
  end, L.TT_PLAY_THIS)
  f.playSel:SetPoint("TOPLEFT", f.create, "BOTTOMLEFT", 0, -6)

  f.autoBtn = button(f, L.BACK_AUTO, 210, function() ns.SetMode("auto") end, L.TT_BACK_AUTO)
  f.autoBtn:SetPoint("TOPLEFT", f.playSel, "BOTTOMLEFT", 0, -4)
end

---------------------------------------------------------------------------
-- Colonna 2: brani
---------------------------------------------------------------------------
local function visibleTracks()
  local data = {}
  local pl = ns.GetPlaylist(LUI.selected)
  local only = f.onlyIn:GetChecked() and selectedIsUser()
  local q = (f.search:GetText() or ""):lower()
  for _, t in ipairs(ns.tracks) do
    if (not only or pl.has[t.file]) and (q == "" or t._search:find(q, 1, true)) then
      data[#data + 1] = t
    end
  end
  return data
end

local function buildTrackColumn()
  f.trackHeader = header(f, L.TRACKS_HEADER_ALL, 240, -40)
  f.trackHeader:SetWidth(345)
  f.trackHeader:SetJustifyH("LEFT")
  f.trackHeader:SetWordWrap(false)

  f.search = editbox(f, 180)
  f.search:SetPoint("TOPLEFT", 246, -58)
  f.search:SetScript("OnTextChanged", function() LUI:RefreshTracks() end)
  f.searchHint = text(f.search, "GameFontDisableSmall")
  f.searchHint:SetPoint("LEFT", 2, 0)
  f.searchHint:SetWidth(176)
  f.searchHint:SetJustifyH("LEFT")
  f.searchHint:SetWordWrap(false)
  f.searchHint:SetText(L.SEARCH_HINT)
  f.search:SetScript("OnEditFocusGained", function() f.searchHint:Hide() end)
  f.search:SetScript("OnEditFocusLost", function(self) f.searchHint:SetShown(self:GetText() == "") end)

  f.onlyIn = checkbox(f, 22)
  f.onlyIn:SetPoint("LEFT", f.search, "RIGHT", 10, 0)
  f.onlyIn:SetScript("OnClick", function() LUI:RefreshTracks() end)
  f.onlyInLabel = text(f, "GameFontHighlightSmall")
  f.onlyInLabel:SetPoint("LEFT", f.onlyIn, "RIGHT", 2, 0)
  f.onlyInLabel:SetWidth(118)
  f.onlyInLabel:SetJustifyH("LEFT")
  f.onlyInLabel:SetText(L.ONLY_IN)

  f.tracks = createList(f, 11, 30, 340, function(row)
    row.check = checkbox(row, 22)
    row.check:SetPoint("LEFT", 2, 0)
    row.check:SetScript("OnClick", function(self)
      if selectedIsUser() then ns.SetInPlaylist(LUI.selected, row.item.file, self:GetChecked()) end
    end)
    row.title = text(row, "GameFontHighlight")
    row.title:SetPoint("TOPLEFT", 28, -3)
    row.title:SetWidth(240)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row.sub = text(row, "GameFontDisableSmall")
    row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -1)
    row.sub:SetWidth(240)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)
    row.dur = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.dur:SetPoint("RIGHT", -30, 0)
    row.play = button(row, ">", 24, function() ns.PlayFrom(LUI.selected or ns.ALL, row.item) end)
    row.play:SetHeight(20)
    row.play:SetPoint("RIGHT", -2, 0)
    row:SetScript("OnDoubleClick", function(self) ns.PlayFrom(LUI.selected or ns.ALL, self.item) end)
  end, function(row, t)
    local user = selectedIsUser()
    row.check:SetShown(user)
    if user then row.check:SetChecked(ns.GetPlaylist(LUI.selected).has[t.file] == true) end
    ns.SetText(row.title, t.title, "GameFontHighlight")
    local sub = t.artist or ""
    if t.folder ~= "" then sub = sub ~= "" and (sub .. "  ·  " .. t.folder) or t.folder end
    ns.SetText(row.sub, sub, "GameFontDisableSmall")
    row.dur:SetText((tonumber(t.duration) or 0) > 0 and ns.FormatTime(t.duration) or "")
    if ns.Player.track == t then row.title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    else row.title:SetTextColor(1, 1, 1) end
  end)
  f.tracks:SetPoint("TOPLEFT", 240, -84)

  local function bulk(include)
    if not selectedIsUser() then return end
    local ids = {}
    for _, t in ipairs(visibleTracks()) do ids[#ids + 1] = t.file end
    ns.SetManyInPlaylist(LUI.selected, ids, include)
  end
  f.addAll = button(f, L.ADD_VISIBLE, 110, function() bulk(true) end, L.TT_ADD_VISIBLE)
  fitButton(f.addAll, 110)
  f.addAll:SetPoint("TOPLEFT", f.tracks, "BOTTOMLEFT", 0, -8)
  f.removeAll = button(f, L.REMOVE_VISIBLE, 100, function() bulk(false) end, L.TT_REMOVE_VISIBLE)
  fitButton(f.removeAll, 100)
  f.removeAll:SetPoint("LEFT", f.addAll, "RIGHT", 4, 0)
  f.trackCount = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.trackCount:SetPoint("LEFT", f.removeAll, "RIGHT", 8, 0)
end

---------------------------------------------------------------------------
-- Finestra
---------------------------------------------------------------------------
function LUI:Build()
  if f then return end
  self.selected = ns.ALL
  f = CreateFrame("Frame", "KalimdorZugZugLibraryFrame", UIParent, "BackdropTemplate")
  f:SetSize(600, 520)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  f:SetBackdropColor(0.06, 0.05, 0.05, 0.96)
  f:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.8)
  f:Hide()
  if UISpecialFrames then table.insert(UISpecialFrames, f:GetName()) end -- ESC chiude la finestra

  local title = text(f, "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 14, -12)
  title:SetText(L.LIB_TITLE)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  f.settingsBtn = button(f, L.SETTINGS, 90, function() ns.Settings:Open() end)
  fitButton(f.settingsBtn, 90)
  f.settingsBtn:SetPoint("TOPRIGHT", -30, -10)

  buildPlaylistColumn()
  buildTrackColumn()
  f:SetScript("OnShow", function() LUI:Refresh() end)

  ns.On("PLAYLISTS_CHANGED", function() if f:IsShown() then LUI:Refresh() end end)
  ns.On("MODE_CHANGED", function() if f:IsShown() then LUI:Refresh() end end)
  ns.On("TRACK_CHANGED", function() if f:IsShown() then f.tracks:Update() f.playlists:Update() end end)
end

function LUI:RefreshTracks()
  local data = visibleTracks()
  f.tracks:SetData(data)
  local user = selectedIsUser()
  f.addAll:SetEnabled(user)
  f.removeAll:SetEnabled(user)
  f.onlyIn:SetEnabled(user)
  if user then
    ns.SetText(f.trackHeader, L.TRACKS_HEADER_USER:format(LUI.selected), "GameFontNormal")
  else
    ns.SetText(f.trackHeader, L.TRACKS_HEADER_ALL, "GameFontNormal")
  end
  f.trackCount:SetText(("%d / %d"):format(#data, #ns.tracks))
end

function LUI:Refresh()
  if not f then return end
  if not ns.GetPlaylist(self.selected) then self.selected = ns.ALL end
  local names = ns.PlaylistNames()
  table.insert(names, 1, ns.ALL)
  f.playlists:SetData(names)
  local user = selectedIsUser()
  f.rename:SetEnabled(user)
  f.delete:SetEnabled(user)
  self:RefreshTracks()
end

function LUI:Toggle(show)
  if not f then return end
  if show == nil then show = not f:IsShown() end
  f:SetShown(show)
end
