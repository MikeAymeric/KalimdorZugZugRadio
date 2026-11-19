-- Stats: the listening stats window ("Azeroth Wrapped"): hours listened, top tracks, artists and
-- genres, the most played track of each condition and where you listened, for this month, this
-- year or all time. The data is recorded by ns.RecordListen (Core.lua) in db.listen["YYYY-MM"].
local _, ns = ...
local L = ns.L

local ST = { period = "month" }
ns.Stats = ST

local PERIODS = { { "month", "STATS_MONTH" }, { "year", "STATS_YEAR" }, { "all", "STATS_ALL" } }
local TOP_TRACKS, TOP_ARTISTS, TOP_GENRES, TOP_CONDS, TOP_ZONES = 6, 5, 3, 6, 4
local w

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
local function add(into, key, value) into[key] = (into[key] or 0) + value end

-- The months of a period: "month" = the current one, "year" = this year's, "all" = every month.
local function monthsOf(period)
  local now = ns.MonthKey()
  local out = {}
  for key, m in pairs(ns.db.listen) do
    if type(m) == "table" and (period == "all" or (period == "month" and key == now)
        or (period == "year" and key:sub(1, 4) == now:sub(1, 4))) then
      out[#out + 1] = m
    end
  end
  return out
end

-- Sorted { {key, value}, ... } of a key -> number table, largest first, at most n.
local function topOf(map, n)
  local list = {}
  for k, v in pairs(map) do if v > 0 then list[#list + 1] = { k, v } end end
  table.sort(list, function(a, b)
    if a[2] ~= b[2] then return a[2] > b[2] end
    return tostring(a[1]) < tostring(b[1])
  end)
  for i = #list, n + 1, -1 do list[i] = nil end
  return list
end

-- Everything the window shows, for a period.
-- { seconds, plays, podcastSeconds, tracks = {{t, sec}}, artists = {{name, sec}}, genres, conds = {{key, sec, t}}, zones }
function ST.Summary(period)
  local trackSec, condSec, condTracks, zoneSec = {}, {}, {}, {}
  local seconds, plays = 0, 0
  for _, m in ipairs(monthsOf(period)) do
    seconds, plays = seconds + (m.s or 0), plays + (m.p or 0)
    for id, sec in pairs(m.t or {}) do add(trackSec, id, sec) end
    for key, c in pairs(m.c or {}) do
      add(condSec, key, c.s or 0)
      condTracks[key] = condTracks[key] or {}
      for id, sec in pairs(c.t or {}) do add(condTracks[key], id, sec) end
    end
    for zone, sec in pairs(m.z or {}) do add(zoneSec, zone, sec) end
  end
  if period == "all" then
    -- tracks, plays and time also count what was heard before 2.0 (db.stats)
    seconds, plays, trackSec = math.max(seconds, ns.db.totalSeconds or 0), 0, {}
    for id, st in pairs(ns.db.stats) do
      plays = plays + (st.plays or 0)
      if (st.seconds or 0) > 0 then trackSec[id] = st.seconds end
    end
  end
  local s = { seconds = seconds, plays = plays, podcastSeconds = 0, tracks = {}, artists = {}, genres = {},
              conds = {}, zones = topOf(zoneSec, TOP_ZONES) }
  local artistSec, genreSec, music = {}, {}, {}
  for id, sec in pairs(trackSec) do
    local t = ns.trackById[id]
    if t and t.podcast then
      s.podcastSeconds = s.podcastSeconds + sec
    elseif t then
      music[id] = sec
      if t.artist and t.artist ~= "" then add(artistSec, t.artist, sec) end
      if t.genre and t.genre ~= "" then add(genreSec, t.genre, sec) end
    end
  end
  for _, e in ipairs(topOf(music, TOP_TRACKS)) do s.tracks[#s.tracks + 1] = { ns.trackById[e[1]], e[2] } end
  s.artists, s.genres = topOf(artistSec, TOP_ARTISTS), topOf(genreSec, TOP_GENRES)
  for _, e in ipairs(topOf(condSec, TOP_CONDS)) do
    local best
    for _, te in ipairs(topOf(condTracks[e[1]] or {}, 5)) do
      local t = ns.trackById[te[1]]
      if t and not t.podcast then best = t break end
    end
    s.conds[#s.conds + 1] = { e[1], e[2], best }
  end
  return s
end

function ST.ConditionLabel(key)
  if key == "free" then return L.STATS_FREE_PLAY end
  return ns.SITUATION_BY_KEY[key] and ns.SituationLabel(key) or tostring(key)
end

local function periodLabel(period)
  for _, p in ipairs(PERIODS) do if p[1] == period then return L[p[2]] end end
  return period
end

-- Plain-text summary to paste in chat or Discord.
function ST.ShareText(period)
  local s = ST.Summary(period)
  local lines = { L.STATS_SHARE_HEADER:format(periodLabel(period)),
                  L.STATS_SUMMARY:format(ns.FormatDuration(s.seconds), s.plays) }
  if #s.tracks > 0 then
    lines[#lines + 1] = L.STATS_TOP_TRACKS .. ":"
    for i, e in ipairs(s.tracks) do lines[#lines + 1] = ("%d. %s"):format(i, ns.TrackLabel(e[1])) end
  end
  if #s.artists > 0 then
    local names = {}
    for _, e in ipairs(s.artists) do names[#names + 1] = e[1] end
    lines[#lines + 1] = L.STATS_TOP_ARTISTS .. ": " .. table.concat(names, ", ")
  end
  for _, c in ipairs(s.conds) do
    if c[3] then lines[#lines + 1] = ("%s: %s"):format(ST.ConditionLabel(c[1]), ns.TrackLabel(c[3])) end
  end
  return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function text(parent, template)
  return parent:CreateFontString(nil, "OVERLAY", ns.Font(template))
end

local function header(parent, label, x, y)
  local h = text(parent, "GameFontNormal")
  h:SetPoint("TOPLEFT", x, y)
  h:SetText(label)
  return h
end

-- A line with an optional small cover, a main text, a sub text and a value on the right.
local function makeLine(parent, x, y, width, withCover)
  local line = CreateFrame("Frame", nil, parent)
  line:SetSize(width, withCover and 30 or 16)
  line:SetPoint("TOPLEFT", x, y)
  local left = 0
  line.withCover = withCover == true -- not "if line.sub": the test stubs answer every key
  if withCover then
    line.cover = line:CreateTexture(nil, "ARTWORK")
    line.cover:SetSize(26, 26)
    line.cover:SetPoint("LEFT", 0, 0)
    left = 32
  end
  line.value = text(line, "GameFontHighlightSmall")
  line.value:SetPoint("RIGHT", 0, 0)
  line.main = text(line, withCover and "GameFontHighlight" or "GameFontHighlightSmall")
  line.main:SetPoint(withCover and "TOPLEFT" or "LEFT", left, withCover and -2 or 0)
  line.main:SetPoint("RIGHT", line.value, "LEFT", -6, 0)
  line.main:SetJustifyH("LEFT")
  line.main:SetWordWrap(false)
  if withCover then
    line.sub = text(line, "GameFontDisableSmall")
    line.sub:SetPoint("TOPLEFT", line.main, "BOTTOMLEFT", 0, -1)
    line.sub:SetPoint("RIGHT", line.value, "LEFT", -6, 0)
    line.sub:SetJustifyH("LEFT")
    line.sub:SetWordWrap(false)
  end
  return line
end

local function lines(parent, n, x, y, width, withCover)
  local out = {}
  for i = 1, n do out[i] = makeLine(parent, x, y - (i - 1) * (withCover and 32 or 17), width, withCover) end
  return out
end

local function build()
  w = CreateFrame("Frame", "KalimdorZugZugStats", UIParent, "BackdropTemplate")
  w:SetSize(580, 520)
  w:SetPoint("CENTER", 0, 20)
  w:SetFrameStrata("DIALOG")
  w:SetClampedToScreen(true)
  w:SetMovable(true)
  w:EnableMouse(true)
  w:RegisterForDrag("LeftButton")
  w:SetScript("OnDragStart", w.StartMoving)
  w:SetScript("OnDragStop", w.StopMovingOrSizing)
  w:Hide()
  if UISpecialFrames then table.insert(UISpecialFrames, w:GetName()) end

  w.titleFS = text(w, "GameFontNormal")
  w.titleFS:SetText(L.STATS_TITLE)
  w.closeBtn = CreateFrame("Button", nil, w, "UIPanelCloseButton")
  w.closeBtn:SetPoint("TOPRIGHT", 2, 2)

  w.period = ns.MakeDropdown(w, 150, L.STATS_MONTH, function(_, root)
    for _, p in ipairs(PERIODS) do
      ns.StyleMenuItem(root:CreateRadio(L[p[2]], function() return ST.period == p[1] end,
        function() ST.period = p[1] ST:Refresh() end))
    end
  end)
  if w.period then w.period:SetPoint("TOPLEFT", 16, -38) end
  w.summary = text(w, "GameFontHighlight")
  w.summary:SetPoint("TOPLEFT", 190, -44)
  w.summary:SetPoint("RIGHT", w, "RIGHT", -16, 0)
  w.summary:SetJustifyH("LEFT")

  header(w, L.STATS_TOP_TRACKS, 20, -78)
  w.tracks = lines(w, TOP_TRACKS, 20, -98, 290, true)
  header(w, L.STATS_TOP_ARTISTS, 330, -78)
  w.artists = lines(w, TOP_ARTISTS, 330, -98, 230)
  header(w, L.STATS_TOP_GENRES, 330, -196)
  w.genres = lines(w, TOP_GENRES, 330, -216, 230)

  header(w, L.STATS_SOUNDTRACK, 20, -300)
  w.conds = lines(w, TOP_CONDS, 20, -320, 290)
  header(w, L.STATS_TOP_ZONES, 330, -300)
  w.zones = lines(w, TOP_ZONES, 330, -320, 230)

  w.empty = text(w, "GameFontDisable")
  w.empty:SetPoint("CENTER", 0, 20)
  w.empty:SetText(L.STATS_EMPTY)
  w.note = text(w, "GameFontDisableSmall")
  w.note:SetPoint("BOTTOMLEFT", 20, 46)
  w.note:SetPoint("RIGHT", w, "RIGHT", -20, 0)
  w.note:SetJustifyH("LEFT")
  w.note:SetText(L.STATS_NOTE)

  w.close = ns.MakeButton(w, L.CLOSE, 90, function() w:Hide() end)
  w.close:SetPoint("BOTTOMRIGHT", -16, 14)
  w.share = ns.MakeButton(w, L.STATS_SHARE, 110, function()
    ns.ShowShareDialog("export", ST.ShareText(ST.period), nil, L.STATS_TITLE, L.TT_STATS_SHARE, true)
  end, L.TT_STATS_SHARE)
  w.share:SetPoint("RIGHT", w.close, "LEFT", -6, 0)

  ns.SkinWindow(w, w.titleFS, w.closeBtn)
  ns.On("SETTINGS_CHANGED", function() ns.SkinWindow(w, w.titleFS, w.closeBtn) end)
  w:SetScript("OnShow", function() ST:Refresh() end)
end

local function setLine(line, main, value, sub, cover)
  if not main then line:Hide() return end
  line:Show()
  ns.SetText(line.main, main, line.withCover and "GameFontHighlight" or "GameFontHighlightSmall")
  line.value:SetText(value or "")
  if line.withCover then
    ns.SetText(line.sub, sub or "", "GameFontDisableSmall")
    line.cover:SetTexture(cover or ns.DEFAULT_COVER)
  end
end

function ST:Refresh()
  if not w or not w:IsShown() then return end
  if w.period and w.period.GenerateMenu then w.period:GenerateMenu() end
  local s = ST.Summary(ST.period)
  local summary = L.STATS_SUMMARY:format(ns.FormatDuration(s.seconds), s.plays)
  if s.podcastSeconds >= 60 then summary = summary .. L.STATS_PODCASTS:format(ns.FormatDuration(s.podcastSeconds)) end
  w.summary:SetText(summary)
  for i, line in ipairs(w.tracks) do
    local e = s.tracks[i]
    if e then setLine(line, e[1].title, ns.FormatDuration(e[2]), e[1].artist, ns.CoverOf(e[1])) else setLine(line) end
  end
  for i, line in ipairs(w.artists) do
    local e = s.artists[i]
    setLine(line, e and (i .. ". " .. e[1]), e and ns.FormatDuration(e[2]))
  end
  for i, line in ipairs(w.genres) do
    local e = s.genres[i]
    setLine(line, e and (i .. ". " .. e[1]), e and ns.FormatDuration(e[2]))
  end
  for i, line in ipairs(w.conds) do
    local c = s.conds[i]
    setLine(line, c and (ST.ConditionLabel(c[1]) .. ":  " .. (c[3] and ns.TrackLabel(c[3]) or "-")),
      c and ns.FormatDuration(c[2]))
  end
  for i, line in ipairs(w.zones) do
    local z = s.zones[i]
    setLine(line, z and (i .. ". " .. z[1]), z and ns.FormatDuration(z[2]))
  end
  w.empty:SetShown(s.seconds < 1 and #s.tracks == 0)
  w.note:SetShown(ST.period ~= "month")
end

function ST:Toggle(show)
  if not w then build() end
  if show == nil then show = not w:IsShown() end
  if show then w:Show() ST:Refresh() else w:Hide() end
end

function ST:IsShown() return w ~= nil and w:IsShown() end
