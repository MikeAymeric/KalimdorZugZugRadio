-- Player: code di riproduzione per playlist, shuffle, avanzamento a tempo.
-- Usa PlayMusic: sostituisce la musica di zona e la fa ripartire con StopMusic.
-- WoW non espone posizione/durata: il progresso è GetTime() - startTime e la
-- fine del brano è un timer sulla durata scritta in Library.lua.
local _, ns = ...

local P = {
  playlist = nil,      -- nome della playlist corrente
  track = nil,         -- tabella del brano corrente
  playing = false,
  userStopped = false, -- l'utente ha premuto stop: le condizioni non fanno ripartire la musica
  startTime = 0,
}
ns.Player = P

local states = {} -- nome playlist -> { queue = {indici}, pos = n, count = n }
local timer

local function buildQueue(count, first)
  local q = {}
  for i = 1, count do q[i] = i end
  if ns.db.shuffle then
    for i = count, 2, -1 do
      local j = math.random(i)
      q[i], q[j] = q[j], q[i]
    end
    if first then
      for i, v in ipairs(q) do
        if v == first then q[1], q[i] = q[i], q[1] break end
      end
    end
  end
  return q
end

local function indexOf(tracks, track)
  for i, t in ipairs(tracks) do
    if t == track then return i end
  end
end

-- Crea la coda partendo da startIndex (se dato).
local function resetState(name, startIndex)
  local pl = ns.GetPlaylist(name)
  local st = { queue = buildQueue(#pl.tracks, startIndex), count = #pl.tracks, pos = 1 }
  if startIndex and not ns.db.shuffle then st.pos = startIndex end
  states[name] = st
  return st, pl
end

local function getState(name)
  local pl = ns.GetPlaylist(name)
  local st = states[name]
  if not st or st.count ~= #pl.tracks then return resetState(name) end
  return st, pl
end

local function playable(name)
  return name and ns.IsPlayable(name)
end

local function cancelTimer()
  if timer then timer:Cancel() timer = nil end
end

local function startTrack()
  local st, pl = getState(P.playlist)
  local track = pl.tracks[st.queue[st.pos]]
  cancelTimer()
  P.track = track
  local ok, err = pcall(PlayMusic, ns.ROOT .. track.file)
  if not ok then ns.Print("MSG_PLAYMUSIC_ERROR", tostring(err)) end
  P.playing = true
  P.startTime = GetTime()
  local dur = tonumber(track.duration) or 0
  if dur > 0 then
    timer = C_Timer.NewTimer(dur + 0.5, function()
      timer = nil
      P:Next()
    end)
  end
  ns.Fire("TRACK_CHANGED", track)
  ns.Fire("STATE_CHANGED")
end

function P:Elapsed()
  if not self.playing then return 0 end
  return GetTime() - self.startTime
end

-- Avvia (o riavvia dall'inizio) il brano corrente della playlist.
function P:Play(name)
  name = name or self.playlist
  if not playable(name) or not ns.db.enabled then return false end
  self.playlist = name
  self.userStopped = false
  startTrack()
  return true
end

-- Suona un brano preciso di una playlist; la coda continua da lì.
function P:PlayTrack(name, track)
  if not playable(name) then return end
  local pl = ns.GetPlaylist(name)
  resetState(name, indexOf(pl.tracks, track))
  self:Play(name)
end

-- Cambia playlist. Non riavvia se è già quella in riproduzione.
function P:SetPlaylist(name)
  if not playable(name) then
    self.playlist = nil
    self.track = nil
    self:Stop()
    ns.Fire("TRACK_CHANGED", nil)
    return
  end
  if name == self.playlist and self.playing then return end
  self.playlist = name
  if self.userStopped or not ns.db.enabled then
    local st, pl = getState(name)
    self.track = pl.tracks[st.queue[st.pos]]
    ns.Fire("TRACK_CHANGED", self.track)
    return
  end
  startTrack()
end

function P:Stop(byUser)
  cancelTimer()
  if self.playing then pcall(StopMusic) end
  self.playing = false
  if byUser then self.userStopped = true end
  ns.Fire("STATE_CHANGED")
end

-- Play/Stop. Con forcePlay non ferma mai.
function P:Toggle(forcePlay)
  if self.playing and not forcePlay then
    self:Stop(true)
    return
  end
  self.userStopped = false
  if not self:Play() then ns.Rules:Evaluate(true) end
end

function P:Next()
  if not playable(self.playlist) then return end
  local st, pl = getState(self.playlist)
  st.pos = st.pos + 1
  if st.pos > #st.queue then
    st.queue = buildQueue(#pl.tracks)
    st.pos = 1
  end
  self:Play()
end

function P:Prev()
  if not playable(self.playlist) then return end
  if self.playing and self:Elapsed() > 3 then self:Play() return end
  local st = getState(self.playlist)
  st.pos = st.pos - 1
  if st.pos < 1 then st.pos = #st.queue end
  self:Play()
end

function P:SetShuffle(on)
  ns.db.shuffle = on and true or false
  for name in pairs(states) do
    if playable(name) then
      local pl = ns.GetPlaylist(name)
      local current = (name == self.playlist and self.track) and indexOf(pl.tracks, self.track) or nil
      resetState(name, current)
    else
      states[name] = nil
    end
  end
  ns.Fire("STATE_CHANGED")
end

function P:Rename(old, new)
  states[new], states[old] = states[old], nil
  if self.playlist == old then self.playlist = new end
end

-- Playlist modificata: ricostruisce la coda tenendo il brano in corso come punto di partenza.
ns.On("PLAYLISTS_CHANGED", function(name)
  if not name then wipe(states) return end
  states[name] = nil
  if P.playlist ~= name then return end
  if not playable(name) then
    P:SetPlaylist(nil)
    ns.Rules:Evaluate(true)
    return
  end
  local pl = ns.GetPlaylist(name)
  local idx = P.track and indexOf(pl.tracks, P.track)
  if idx then
    resetState(name, idx)
  elseif P.playing then
    P:Play(name) -- il brano in corso è stato tolto: passa a un altro
  end
end)
