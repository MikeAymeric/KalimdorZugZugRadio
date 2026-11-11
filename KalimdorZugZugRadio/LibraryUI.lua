-- LibraryUI: window to create playlists and pick tracks (conditions and language live in Settings.lua).
local _, ns = ...
local L = ns.L

local LUI = { selected = nil } -- selected = selected playlist name (ns.ALL = whole library)
ns.LibraryUI = LUI

local ACCENT = { 1, 0.5, 0.1 }
local SMART_COLOR = { 0.55, 0.8, 1 }
local DEFAULT_COVER = "Interface\\Icons\\INV_Misc_QuestionMark"
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

  function list:ScrollToTop()
    self.offset = 0
    bar:SetValue(0)
  end

  return list
end

-- Right-click menu with "Play next" / "Add to queue" for a list of tracks (plus extra entries).
local function queueEntries(root, getTracks)
  ns.StyleMenuItem(root:CreateButton(L.PLAY_NEXT, function() ns.QueueTracks(getTracks(), true) end))
  ns.StyleMenuItem(root:CreateButton(L.ADD_TO_QUEUE, function() ns.QueueTracks(getTracks(), false) end))
end

---------------------------------------------------------------------------
-- Column 1: playlists
---------------------------------------------------------------------------
local function selectedIsUser()
  return LUI.selected and LUI.selected ~= ns.ALL and ns.db.playlists[LUI.selected] ~= nil
end

local function selectedIsSmart()
  return ns.IsSmart(LUI.selected)
end

-- A playlist the user made (plain or smart): it can be renamed and deleted.
local function selectedIsOwn()
  return selectedIsUser() or selectedIsSmart()
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
      LUI.group = nil
      f.nameBox:SetText((ns.db.playlists[self.item] or ns.IsSmart(self.item)) and self.item or "")
      LUI:Refresh()
    end)
    row:SetScript("OnDoubleClick", function(self) ns.SetMode(self.item) end)
  end, function(row, name)
    ns.SetText(row.text, ns.PlaylistLabel(name), "GameFontHighlight")
    row.count:SetText(#ns.GetPlaylist(name).tracks)
    row.sel:SetShown(name == LUI.selected)
    if name == ns.db.mode then row.text:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    elseif ns.IsSmart(name) then row.text:SetTextColor(SMART_COLOR[1], SMART_COLOR[2], SMART_COLOR[3])
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
      LUI.group = nil
      f.onlyIn:SetChecked(false)
      LUI:Refresh()
    end
  end, L.TT_CREATE)
  f.create:SetPoint("TOPLEFT", f.nameBox, "BOTTOMLEFT", -6, -6)

  f.rename = button(f, L.RENAME, 70, function()
    if not selectedIsOwn() then return end
    local name, err = ns.RenamePlaylist(LUI.selected, f.nameBox:GetText())
    if report(name, err) then LUI.selected = name LUI:Refresh() end
  end, L.TT_RENAME)
  f.rename:SetPoint("LEFT", f.create, "RIGHT", 4, 0)

  f.delete = button(f, L.DELETE, 66, function(self)
    if not selectedIsOwn() then return end
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

  -- smart playlists: new / edit the rules of the selected one
  f.smartNew = button(f, L.SMART_NEW, 103, function() LUI:OpenSmartEditor(nil) end, L.TT_SMART_NEW)
  f.smartNew:SetPoint("TOPLEFT", f.export, "BOTTOMLEFT", 0, -4)
  f.smartEdit = button(f, L.SMART_EDIT, 103, function()
    if selectedIsSmart() then LUI:OpenSmartEditor(LUI.selected) end
  end, L.TT_SMART_EDIT)
  f.smartEdit:SetPoint("LEFT", f.smartNew, "RIGHT", 4, 0)
end

---------------------------------------------------------------------------
-- Column 2: tracks, or albums / artists
---------------------------------------------------------------------------
LUI.source = "all" -- with a user playlist selected: "all" | "mine" | "podcast" | "game"
LUI.view = "tracks" -- "tracks" | "album" | "artist"
LUI.group = nil     -- the album/artist opened in the album/artist view (an ns.Groups entry)

-- Tracks to work on: those of the selected virtual or smart playlist or, for a user playlist,
-- the user's tracks and/or the game music, according to the "source" filter.
local function baseTracks()
  if LUI.selected == ns.GAME then return ns.gameTracks end
  if LUI.selected == ns.PODCAST then return ns.episodes end
  if not selectedIsUser() then
    if LUI.selected == ns.ALL or not ns.GetPlaylist(LUI.selected) then return ns.tracks end
    return ns.GetPlaylist(LUI.selected).tracks -- favourites, history, most played, smart playlists
  end
  if LUI.source == "mine" then return ns.tracks end
  if LUI.source == "game" then return ns.gameTracks end
  if LUI.source == "podcast" then return ns.episodes end
  return ns.everyTrack
end

-- Plays a track: inside the open album/artist or the selected playlist if it contains it,
-- otherwise in its virtual playlist.
local function playTrack(t)
  local g = LUI.group and ns.GetPlaylist(LUI.group.name)
  local pl = ns.GetPlaylist(LUI.selected)
  if g and g.has[t.file] then
    ns.PlayFrom(LUI.group.name, t)
  elseif pl and pl.has[t.file] then
    ns.PlayFrom(LUI.selected, t)
  else
    ns.PlayFrom(t.game and ns.GAME or t.podcast and ns.PODCAST or ns.ALL, t)
  end
end

local function inGroupView() return LUI.view ~= "tracks" and LUI.group == nil end

-- Tracks of the base list that pass the "only in playlist" filter (and the open album/artist).
local function filteredTracks(withSearch)
  local data = {}
  local pl = ns.GetPlaylist(LUI.selected)
  local only = f.onlyIn:GetChecked() and selectedIsUser()
  local q = withSearch and (f.search:GetText() or ""):lower() or ""
  local g = LUI.group
  for _, t in ipairs(baseTracks()) do
    if (not only or pl.has[t.file]) and (q == "" or t._search:find(q, 1, true))
        and (not g or ns.GroupKey(g.kind, t) == g.key) then
      data[#data + 1] = t
    end
  end
  return data
end

local function visibleTracks()
  return filteredTracks(true)
end

local function visibleGroups()
  local q = (f.search:GetText() or ""):lower()
  local out = {}
  for _, g in ipairs(ns.Groups(filteredTracks(false), LUI.view)) do
    if q == "" or g._search:find(q, 1, true) then out[#out + 1] = g end
  end
  return out
end

local function trackMenu(row)
  local t = row.item
  MenuUtil.CreateContextMenu(row, function(_, root)
    queueEntries(root, function() return { t } end)
    root:CreateDivider()
    ns.StyleMenuItem(root:CreateButton(ns.IsFavorite(t) and L.FAV_REMOVE or L.FAV_ADD, function() ns.ToggleFavorite(t) end))
    ns.StyleMenuItem(root:CreateButton(ns.IsExcluded(t) and L.INCLUDE or L.EXCLUDE,
      function() ns.SetExcluded(t, not ns.IsExcluded(t)) end))
  end)
end

local function buildTrackRows()
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
    -- right-click: play next / queue / favourite / never play
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, mouseButton)
      if mouseButton ~= "RightButton" or not (MenuUtil and MenuUtil.CreateContextMenu) then return end
      trackMenu(self)
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
  f.tracks:SetPoint("TOPLEFT", 240, -110)
end

local function openGroup(g)
  LUI.group = g
  f.tracks:ScrollToTop()
  LUI:RefreshTracks()
end

local function buildGroupRows()
  f.groups = createList(f, 11, 30, 340, function(row)
    row.cover = row:CreateTexture(nil, "ARTWORK")
    row.cover:SetSize(26, 26)
    row.cover:SetPoint("LEFT", 2, 0)
    row.title = text(row, "GameFontHighlight")
    row.title:SetPoint("TOPLEFT", 34, -3)
    row.title:SetWidth(240)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row.sub = text(row, "GameFontDisableSmall")
    row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -1)
    row.sub:SetWidth(240)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)
    row.play = button(row, ">", 24, function() ns.SetMode(row.item.name) end, L.TT_PLAY_GROUP)
    row.play:SetHeight(20)
    row.play:SetPoint("RIGHT", -2, 0)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, mouseButton)
      if mouseButton ~= "RightButton" then openGroup(self.item) return end
      if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
      local g = self.item
      MenuUtil.CreateContextMenu(self, function(_, root)
        queueEntries(root, function() return ns.GetPlaylist(g.name).tracks end)
      end)
    end)
  end, function(row, g)
    row.cover:SetTexture(g.cover or DEFAULT_COVER)
    ns.SetText(row.title, g.label, "GameFontHighlight")
    local sub = L.GROUP_TRACKS_FMT:format(g.count)
    if g.kind == "album" then
      local by = g.various and L.VARIOUS_ARTISTS or g.artist
      if by and by ~= "" then sub = by .. "  ·  " .. sub end
    end
    ns.SetText(row.sub, sub, "GameFontDisableSmall")
    if ns.db.mode == g.name then row.title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
    else row.title:SetTextColor(1, 1, 1) end
  end)
  f.groups:SetPoint("TOPLEFT", 240, -110)
  f.groups:Hide()
end

local function buildViewBar()
  -- Tracks / Albums / Artists
  f.viewBtns = {}
  local prev
  for _, v in ipairs({ { "tracks", L.VIEW_TRACKS }, { "album", L.VIEW_ALBUMS }, { "artist", L.VIEW_ARTISTS } }) do
    local b = button(f, v[2], 80, function()
      LUI.view, LUI.group = v[1], nil
      f.groups:ScrollToTop()
      LUI:RefreshTracks()
    end)
    fitButton(b, 80)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 240, -84) end
    b.view = v[1]
    f.viewBtns[#f.viewBtns + 1] = b
    prev = b
  end
  -- inside an album / artist: back, its name, play it
  f.groupBack = button(f, "< " .. L.OB_BACK, 70, function() LUI.group = nil LUI:RefreshTracks() end)
  fitButton(f.groupBack, 70)
  f.groupBack:SetPoint("TOPLEFT", 240, -84)
  f.groupPlay = button(f, L.PLAY, 60, function() if LUI.group then ns.SetMode(LUI.group.name) end end, L.TT_PLAY_GROUP)
  fitButton(f.groupPlay, 60)
  f.groupPlay:SetPoint("TOPRIGHT", f, "TOPLEFT", 580, -84)
  f.groupTitle = text(f, "GameFontHighlight")
  f.groupTitle:SetPoint("LEFT", f.groupBack, "RIGHT", 8, 0)
  f.groupTitle:SetPoint("RIGHT", f.groupPlay, "LEFT", -8, 0)
  f.groupTitle:SetJustifyH("LEFT")
  f.groupTitle:SetWordWrap(false)
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
        function() LUI.source = opt[1] LUI.group = nil LUI:RefreshTracks() end))
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

  buildViewBar()
  buildTrackRows()
  buildGroupRows()

  local function bulk(include)
    if not selectedIsUser() or inGroupView() then return end
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
-- Smart playlist editor: name, all/any, up to ns.SMART_MAX_RULES rules, live match count.
---------------------------------------------------------------------------
local E -- editor frame

local function sourceLabel(v)
  return v == "game" and L.GAME_MUSIC or v == "podcast" and L.PODCASTS or L.SOURCE_MINE
end

local function defaultRule(field)
  local kind = ns.SmartFieldKind(field)
  return { field = field, op = ns.SMART_OPS[kind][1], value = kind == "source" and "mine" or nil }
end

local function editorDef()
  return { match = E.match, rules = E.rules }
end

local function updatePreview()
  E.preview:SetText(L.SMART_MATCHES:format(#ns.SmartTracks(editorDef())))
end

local function refreshEditorRows()
  E.syncing = true
  for i, row in ipairs(E.rows) do
    local r = E.rules[i]
    row:SetShown(r ~= nil)
    if r then
      local kind = ns.SmartFieldKind(r.field)
      row.valueBox:SetShown(kind == "text" or kind == "number")
      if row.valueDD then row.valueDD:SetShown(kind == "source") end
      if kind == "text" or kind == "number" then row.valueBox:SetText(r.value and tostring(r.value) or "") end
      for _, dd in ipairs({ row.fieldDD, row.opDD, row.valueDD }) do
        if dd and dd.GenerateMenu then dd:GenerateMenu() end
      end
    end
  end
  E.addRule:SetEnabled(#E.rules < ns.SMART_MAX_RULES)
  if E.matchDD and E.matchDD.GenerateMenu then E.matchDD:GenerateMenu() end
  E.syncing = false
  updatePreview()
end

local function buildEditorRow(i)
  local row = CreateFrame("Frame", nil, E)
  row:SetSize(440, 26)
  row:SetPoint("TOPLEFT", 16, -104 - (i - 1) * 30)
  local function rule() return E.rules[i] end
  row.fieldDD = ns.MakeDropdown(row, 124, L.SMART_F_title, function(_, root)
    for _, fd in ipairs(ns.SMART_FIELDS) do
      ns.StyleMenuItem(root:CreateRadio(L["SMART_F_" .. fd.key],
        function() return rule() and rule().field == fd.key end,
        function()
          if rule() and rule().field ~= fd.key then E.rules[i] = defaultRule(fd.key) refreshEditorRows() end
        end))
    end
  end)
  row.opDD = ns.MakeDropdown(row, 120, "", function(_, root)
    local r = rule()
    if not r then return end
    for _, op in ipairs(ns.SMART_OPS[ns.SmartFieldKind(r.field)]) do
      ns.StyleMenuItem(root:CreateRadio(L["SMART_OP_" .. op],
        function() return rule() and rule().op == op end,
        function() if rule() then rule().op = op updatePreview() end end))
    end
  end)
  row.valueDD = ns.MakeDropdown(row, 124, L.SOURCE_MINE, function(_, root)
    for _, v in ipairs(ns.SMART_SOURCES) do
      ns.StyleMenuItem(root:CreateRadio(sourceLabel(v),
        function() return rule() and rule().value == v end,
        function() if rule() then rule().value = v updatePreview() end end))
    end
  end)
  row.valueBox = editbox(row, 118)
  row.valueBox:SetScript("OnTextChanged", function(self)
    if E.syncing or not rule() then return end
    local v = self:GetText()
    rule().value = v ~= "" and v or nil
    updatePreview()
  end)
  row.remove = button(row, "X", 24, function()
    table.remove(E.rules, i)
    refreshEditorRows()
  end)
  if row.fieldDD then row.fieldDD:SetPoint("LEFT", 0, 0) end
  if row.opDD then row.opDD:SetPoint("LEFT", 130, 0) end
  if row.valueDD then row.valueDD:SetPoint("LEFT", 256, 0) end
  row.valueBox:SetPoint("LEFT", 262, 0)
  row.remove:SetPoint("LEFT", 388, 0)
  return row
end

local function buildSmartEditor()
  E = CreateFrame("Frame", "KalimdorZugZugSmartEditor", UIParent, "BackdropTemplate")
  E:SetSize(470, 410)
  E:SetPoint("CENTER", 0, 20)
  E:SetFrameStrata("DIALOG")
  E:SetClampedToScreen(true)
  E:SetMovable(true)
  E:EnableMouse(true)
  E:RegisterForDrag("LeftButton")
  E:SetScript("OnDragStart", E.StartMoving)
  E:SetScript("OnDragStop", E.StopMovingOrSizing)
  E:Hide()
  if UISpecialFrames then table.insert(UISpecialFrames, E:GetName()) end

  E.titleFS = text(E, "GameFontNormal")
  E.titleFS:SetText(L.SMART_TITLE)
  E.closeBtn = CreateFrame("Button", nil, E, "UIPanelCloseButton")
  E.closeBtn:SetPoint("TOPRIGHT", 2, 2)

  local nameLabel = text(E, "GameFontHighlightSmall")
  nameLabel:SetPoint("TOPLEFT", 20, -44)
  nameLabel:SetText(L.SMART_NAME)
  E.name = editbox(E, 260)
  E.name:SetPoint("LEFT", nameLabel, "RIGHT", 10, 0)

  E.matchDD = ns.MakeDropdown(E, 200, L.SMART_MATCH_ALL, function(_, root)
    for _, m in ipairs({ { "all", L.SMART_MATCH_ALL }, { "any", L.SMART_MATCH_ANY } }) do
      ns.StyleMenuItem(root:CreateRadio(m[2], function() return E.match == m[1] end,
        function() E.match = m[1] updatePreview() end))
    end
  end)
  if E.matchDD then E.matchDD:SetPoint("TOPLEFT", 16, -68) end

  E.rows = {}
  for i = 1, ns.SMART_MAX_RULES do E.rows[i] = buildEditorRow(i) end

  E.addRule = button(E, L.SMART_ADD_RULE, 110, function()
    if #E.rules < ns.SMART_MAX_RULES then
      table.insert(E.rules, defaultRule("artist"))
      refreshEditorRows()
    end
  end)
  fitButton(E.addRule, 110)
  E.addRule:SetPoint("TOPLEFT", 16, -104 - ns.SMART_MAX_RULES * 30 - 4)

  E.preview = text(E, "GameFontHighlightSmall")
  E.preview:SetPoint("LEFT", E.addRule, "RIGHT", 12, 0)

  E.hint = text(E, "GameFontDisableSmall")
  E.hint:SetPoint("TOPLEFT", E.addRule, "BOTTOMLEFT", 2, -8)
  E.hint:SetWidth(430)
  E.hint:SetJustifyH("LEFT")
  E.hint:SetText(L.SMART_HINT)

  E.cancel = button(E, L.CANCEL, 80, function() E:Hide() end)
  fitButton(E.cancel, 80)
  E.cancel:SetPoint("BOTTOMRIGHT", -16, 14)
  E.save = button(E, L.SMART_SAVE, 80, function()
    local name, err = ns.SaveSmartPlaylist(E.editing, E.name:GetText(), editorDef())
    if not name then ns.Print(err) return end
    E:Hide()
    LUI.selected, LUI.group = name, nil
    if f then f.nameBox:SetText(name) LUI:Refresh() end
  end)
  fitButton(E.save, 80)
  E.save:SetPoint("RIGHT", E.cancel, "LEFT", -6, 0)

  ns.SkinWindow(E, E.titleFS, E.closeBtn)
  ns.On("SETTINGS_CHANGED", function() ns.SkinWindow(E, E.titleFS, E.closeBtn) end)
end

-- Opens the editor on smart playlist `name`, or on a new one (nil).
function LUI:OpenSmartEditor(name)
  if not E then buildSmartEditor() end
  local def = name and ns.db.smartPlaylists[name]
  E.editing = def and name or nil
  E.match = def and def.match or "all"
  E.rules = {}
  for _, r in ipairs(def and def.rules or { defaultRule("artist") }) do
    E.rules[#E.rules + 1] = { field = r.field, op = r.op, value = r.value }
  end
  E.syncing = true
  E.name:SetText(E.editing or "")
  E.syncing = false
  refreshEditorRows()
  E:Show()
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
function LUI:Build()
  if f then return end
  self.selected = ns.ALL
  f = CreateFrame("Frame", "KalimdorZugZugLibraryFrame", UIParent, "BackdropTemplate")
  f:SetSize(600, 582)
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
  ns.On("TRACK_CHANGED", function()
    if f:IsShown() then f.tracks:Update() f.groups:Update() f.playlists:Update() end
  end)
end

function LUI:RefreshTracks()
  local user = selectedIsUser()
  local groups = inGroupView()
  f.tracks:SetShown(not groups)
  f.groups:SetShown(groups)
  for _, b in ipairs(f.viewBtns) do
    b:SetShown(LUI.group == nil)
    local fs = b:GetFontString()
    if fs then
      if b.view == LUI.view then fs:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3]) else fs:SetTextColor(1, 0.82, 0) end
    end
  end
  f.groupBack:SetShown(LUI.group ~= nil)
  f.groupPlay:SetShown(LUI.group ~= nil)
  f.groupTitle:SetShown(LUI.group ~= nil)
  if LUI.group then ns.SetText(f.groupTitle, LUI.group.label, "GameFontHighlight") end

  if groups then
    local data = visibleGroups()
    f.groups:SetData(data)
    f.trackCount:SetText(("%d"):format(#data))
  else
    local data = visibleTracks()
    f.tracks:SetData(data)
    f.trackCount:SetText(("%d / %d"):format(#data, LUI.group and LUI.group.count or #baseTracks()))
  end
  f.addAll:SetEnabled(user and not groups)
  f.removeAll:SetEnabled(user and not groups)
  f.onlyIn:SetEnabled(user)
  if f.source then
    f.source:SetShown(user)
    if f.source.GenerateMenu then f.source:GenerateMenu() end
  end
  f.trackHeader:SetWidth(user and f.source and 220 or 345)
  if user then
    ns.SetText(f.trackHeader, L.TRACKS_HEADER_USER:format(LUI.selected), "GameFontNormal")
  elseif selectedIsSmart() then
    ns.SetText(f.trackHeader, L.TRACKS_HEADER_SMART:format(LUI.selected), "GameFontNormal")
  elseif LUI.selected == ns.GAME then
    ns.SetText(f.trackHeader, L.TRACKS_HEADER_GAME, "GameFontNormal")
  elseif LUI.selected == ns.PODCAST then
    ns.SetText(f.trackHeader, L.TRACKS_HEADER_PODCAST, "GameFontNormal")
  else
    ns.SetText(f.trackHeader, L.TRACKS_HEADER_ALL, "GameFontNormal")
  end
end

function LUI:Refresh()
  if not f then return end
  ns.InvalidateDynamic() -- history / most played / smart playlists are recomputed when looked at
  if not ns.GetPlaylist(self.selected) then self.selected = ns.ALL end
  f.playlists:SetData(ns.AllPlaylistNames())
  local own = selectedIsOwn()
  f.rename:SetEnabled(own)
  f.delete:SetEnabled(own)
  f.export:SetEnabled(selectedIsUser())
  f.smartEdit:SetEnabled(selectedIsSmart())
  self:RefreshTracks()
end

function LUI:Toggle(show)
  if not f then return end
  if show == nil then show = not f:IsShown() end
  f:SetShown(show)
end
