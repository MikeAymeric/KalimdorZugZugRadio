-- LibraryUI: window to create playlists and pick tracks (conditions and language live in Settings.lua).
local _, ns = ...
local L = ns.L

local LUI = { selected = nil } -- selected = selected playlist name (ns.ALL = whole library)
ns.LibraryUI = LUI

local ACCENT = { 1, 0.5, 0.1 }
local f

---------------------------------------------------------------------------
-- Basic widgets
---------------------------------------------------------------------------
local function button(parent, text, width, onClick, tooltip)
  return ns.MakeButton(parent, text, width, onClick, tooltip)
end

-- Widens the button enough for the translated text.
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

-- Virtual list: numRows recycled rows + scroll bar + mouse wheel.
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
  if bar.SetObeyStepDrag then bar:SetObeyStepDrag(true) end -- missing on the Forever client
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
-- Column 1: playlists
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
      f.nameBox:SetText(ns.db.playlists[self.item] and self.item or "")
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

  -- share playlists as text
  f.export = button(f, L.EXPORT, 103, function()
    if not selectedIsUser() then return end
    ns.ShowShareDialog("export", ns.ExportPlaylist(LUI.selected))
  end, L.TT_EXPORT)
  f.export:SetPoint("TOPLEFT", f.autoBtn, "BOTTOMLEFT", 0, -4)
  f.import = button(f, L.IMPORT, 103, function()
    ns.ShowShareDialog("import", "", function(textValue)
      local name, found, total = ns.ImportPlaylist(textValue)
      if not name then ns.Print(found or "MSG_IMPORT_BAD") return end
      ns.Print("MSG_IMPORTED", name, found, total)
      LUI.selected = name
      _G.KalimdorZugZugShareDialog:Hide()
      LUI:Refresh()
    end)
  end, L.TT_IMPORT)
  f.import:SetPoint("LEFT", f.export, "RIGHT", 4, 0)
end

---------------------------------------------------------------------------
-- Column 2: tracks
---------------------------------------------------------------------------
LUI.source = "all" -- with a user playlist selected: "all" | "mine" | "podcast" | "game"

-- Tracks to work on: those of the selected virtual playlist or, for a user playlist,
-- the user's tracks and/or the game music, according to the "source" filter.
local function baseTracks()
  if LUI.selected == ns.GAME then return ns.gameTracks end
  if LUI.selected == ns.PODCAST then return ns.episodes end
  if LUI.selected == ns.FAV or LUI.selected == ns.HISTORY or LUI.selected == ns.TOP then
    return ns.GetPlaylist(LUI.selected).tracks
  end
  if not selectedIsUser() then return ns.tracks end
  if LUI.source == "mine" then return ns.tracks end
  if LUI.source == "game" then return ns.gameTracks end
  if LUI.source == "podcast" then return ns.episodes end
  return ns.everyTrack
end

-- Plays a track: inside the selected playlist if it contains it, otherwise in its virtual playlist.
local function playTrack(t)
  local pl = ns.GetPlaylist(LUI.selected)
  if pl and pl.has[t.file] then
    ns.PlayFrom(LUI.selected, t)
  else
    ns.PlayFrom(t.game and ns.GAME or t.podcast and ns.PODCAST or ns.ALL, t)
  end
end

local function visibleTracks()
  local data = {}
  local pl = ns.GetPlaylist(LUI.selected)
  local only = f.onlyIn:GetChecked() and selectedIsUser()
  local q = (f.search:GetText() or ""):lower()
  for _, t in ipairs(baseTracks()) do
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

  -- source filter (only with a user playlist selected): all / my tracks / WoW music
  f.source = ns.MakeDropdown(f, 118, L.SOURCE_ALL, function(_, root)
    for _, opt in ipairs({ { "all", L.SOURCE_ALL }, { "mine", L.SOURCE_MINE }, { "podcast", L.PODCASTS }, { "game", L.GAME_MUSIC } }) do
      ns.StyleMenuItem(root:CreateRadio(opt[2],
        function() return LUI.source == opt[1] end,
        function() LUI.source = opt[1] LUI:RefreshTracks() end))
    end
  end)
  if f.source then f.source:SetPoint("TOPRIGHT", f, "TOPLEFT", 582, -34) end

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
    row.title:SetWidth(218)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row.sub = text(row, "GameFontDisableSmall")
    row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -1)
    row.sub:SetWidth(218)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)
    row.dur = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.dur:SetPoint("RIGHT", -30, 0)
    row.play = button(row, ">", 24, function() playTrack(row.item) end)
    row.play:SetHeight(20)
    row.play:SetPoint("RIGHT", -2, 0)
    row:SetScript("OnDoubleClick", function(self) playTrack(self.item) end)
    -- favourite star
    row.fav = CreateFrame("Button", nil, row)
    row.fav:SetSize(14, 14)
    row.fav:SetPoint("RIGHT", -64, 0)
    row.fav:SetNormalTexture("Interface\\Common\\FavoritesIcon")
    row.fav:SetScript("OnClick", function() ns.ToggleFavorite(row.item) end)
    -- right-click: favourite / never play
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, mouseButton)
      if mouseButton ~= "RightButton" or not (MenuUtil and MenuUtil.CreateContextMenu) then return end
      local t = self.item
      MenuUtil.CreateContextMenu(self, function(_, root)
        ns.StyleMenuItem(root:CreateButton(ns.IsFavorite(t) and L.FAV_REMOVE or L.FAV_ADD, function() ns.ToggleFavorite(t) end))
        ns.StyleMenuItem(root:CreateButton(ns.IsExcluded(t) and L.INCLUDE or L.EXCLUDE,
          function() ns.SetExcluded(t, not ns.IsExcluded(t)) end))
      end)
    end)
  end, function(row, t)
    local user = selectedIsUser()
    row.check:SetShown(user)
    if user then row.check:SetChecked(ns.GetPlaylist(LUI.selected).has[t.file] == true) end
    ns.SetText(row.title, t.title, "GameFontHighlight")
    local sub = t.artist or ""
    if t.parts then
      -- podcast: episode date and, if started, the part it resumes from
      sub = sub .. "  ·  " .. (t.album or "")
      local prog = ns.db.podcastProgress[t.file]
      if prog and not prog.done and (prog.part or 1) > 1 then
        sub = sub .. "  ·  " .. L.PART_FMT:format(ns.EpisodePart(t), #t.parts)
      end
    elseif t.folder ~= "" then
      sub = sub ~= "" and (sub .. "  ·  " .. t.folder) or t.folder
    end
    ns.SetText(row.sub, sub, "GameFontDisableSmall")
    row.dur:SetText((tonumber(t.duration) or 0) > 0 and ns.FormatTime(t.duration) or "")
    if LUI.selected == ns.TOP and ns.db.stats[t.file] then
      ns.SetText(row.sub, sub .. "  ·  " .. L.PLAYS_FMT:format(ns.db.stats[t.file].plays or 0), "GameFontDisableSmall")
    end
    local favTex = row.fav:GetNormalTexture()
    if favTex then
      local isFav = ns.IsFavorite(t)
      favTex:SetDesaturated(not isFav)
      favTex:SetAlpha(isFav and 1 or 0.3)
    end
    if ns.IsExcluded(t) then row.title:SetTextColor(0.45, 0.45, 0.45)
    elseif ns.Player.track == t then row.title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
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
-- Window
---------------------------------------------------------------------------
function LUI:Build()
  if f then return end
  self.selected = ns.ALL
  f = CreateFrame("Frame", "KalimdorZugZugLibraryFrame", UIParent, "BackdropTemplate")
  f:SetSize(600, 556)
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
  if UISpecialFrames then table.insert(UISpecialFrames, f:GetName()) end -- ESC closes the window

  f.titleFS = text(f, "GameFontNormal")
  f.titleFS:SetText(L.LIB_TITLE)
  f.closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  f.closeBtn:SetPoint("TOPRIGHT", 2, 2)

  f.settingsBtn = button(f, L.SETTINGS, 90, function() ns.Settings:Open() end)
  fitButton(f.settingsBtn, 90)
  f.settingsBtn:SetPoint("BOTTOMRIGHT", -16, 14)

  buildPlaylistColumn()
  buildTrackColumn()
  f:SetScript("OnShow", function() LUI:Refresh() end)
  ns.SkinWindow(f, f.titleFS, f.closeBtn)
  ns.On("SETTINGS_CHANGED", function() ns.SkinWindow(f, f.titleFS, f.closeBtn) end)

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
  if f.source then
    f.source:SetShown(user)
    if f.source.GenerateMenu then f.source:GenerateMenu() end
  end
  f.trackHeader:SetWidth(user and f.source and 220 or 345)
  if user then
    ns.SetText(f.trackHeader, L.TRACKS_HEADER_USER:format(LUI.selected), "GameFontNormal")
  elseif LUI.selected == ns.GAME then
    ns.SetText(f.trackHeader, L.TRACKS_HEADER_GAME, "GameFontNormal")
  elseif LUI.selected == ns.PODCAST then
    ns.SetText(f.trackHeader, L.TRACKS_HEADER_PODCAST, "GameFontNormal")
  else
    ns.SetText(f.trackHeader, L.TRACKS_HEADER_ALL, "GameFontNormal")
  end
  f.trackCount:SetText(("%d / %d"):format(#data, #baseTracks()))
end

function LUI:Refresh()
  if not f then return end
  ns.InvalidateDynamic() -- history / most played are recomputed when the library is looked at
  if not ns.GetPlaylist(self.selected) then self.selected = ns.ALL end
  f.playlists:SetData(ns.AllPlaylistNames())
  local user = selectedIsUser()
  f.rename:SetEnabled(user)
  f.delete:SetEnabled(user)
  f.export:SetEnabled(user)
  self:RefreshTracks()
end

function LUI:Toggle(show)
  if not f then return end
  if show == nil then show = not f:IsShown() end
  f:SetShown(show)
end
