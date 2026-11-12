-- Player: per-playlist play queues, shuffle, timed advance.
-- Uses PlayMusic: it replaces the zone music, and StopMusic brings it back.
-- WoW exposes no position/duration: progress is GetTime() - startTime and the
-- end of a track is a timer on the duration stored in Library.lua.
local _, ns = ...

local P = {
  playlist = nil,      -- current playlist name
  track = nil,         -- current track table
  playing = false,
  userStopped = false, -- the user pressed stop: conditions don't restart the music
  startTime = 0,
}
ns.Player = P

local states = {} -- playlist name -> { queue = {indices}, pos = n, count = n }
-- PlayMusic opens the file from disk: measured, it's the most likely source of a hitch
local playMusic = ns.Profiled("PlayMusic", function(source) return PlayMusic(source) end)
local timer
-- Seconds before the stored duration at which a track counts as over (Rules' level-up end uses it)
local END_EARLY = 0.2
P.END_EARLY = END_EARLY

-- Queue of track indices. With shuffle: a random order, weighted when smart shuffle is on
-- (Efraimidis-Spirakis: sort by random^(1/weight), heavier tracks tend to come first).
local function buildQueue(tracks, first)
  local count = #tracks
  local q = {}
  for i = 1, count do q[i] = i end
  if ns.db.shuffle and ns.db.smartShuffle and count > 1 then
    local w, keys = ns.ShuffleWeights(tracks), {}
    for i = 1, count do keys[i] = math.random() ^ (1 / w[i]) end
    table.sort(q, function(a, b) return keys[a] > keys[b] end)
  elseif ns.db.shuffle then
    for i = count, 2, -1 do
      local j = math.random(i)
      q[i], q[j] = q[j], q[i]
    end
  end
  if ns.db.shuffle and first then
    for i, v in ipairs(q) do
      if v == first then q[1], q[i] = q[i], q[1] break end
    end
  end
  return q
end

-- Next position of a queue; past the end a new (reshuffled) queue starts.
local function advance(st, pl)
  st.pos = st.pos + 1
  if st.pos > #st.queue then
    st.queue = buildQueue(pl.tracks)
    st.pos = 1
  end
end

local function indexOf(tracks, track)
  for i, t in ipairs(tracks) do
    if t == track then return i end
  end
end

-- Builds the queue starting from startIndex (if given).
local function resetState(name, startIndex)
  local pl = ns.GetPlaylist(name)
  local st = { queue = buildQueue(pl.tracks, startIndex), count = #pl.tracks, pos = 1 }
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

-- queued = a track from the "Play next" queue: it plays without moving the playlist's queue,
-- which goes on from where it was once the queued tracks are over (P.fromQueue).
local function startTrack(queued)
  local st, pl = getState(P.playlist)
  local track, explicit
  if queued then
    track, explicit = queued, true -- chosen by the user: plays even if excluded
  else
    st.started = true
    track = pl.tracks[st.queue[st.pos]]
    explicit = P.explicitNext
  end
  P.fromQueue = queued ~= nil
  P.explicitNext = nil
  if not explicit and ns.IsExcluded(track) then
    -- skip the tracks the user never wants to hear; stop if they all are
    local found = false
    for _ = 1, #st.queue do
      st.pos = st.pos % #st.queue + 1
      track = pl.tracks[st.queue[st.pos]]
      if not ns.IsExcluded(track) then found = true break end
    end
    if not found then P:Stop() return end
  end
  ns.RecordPlay(P.track, track, P.playing and (GetTime() - P.startTime) or 0)
  cancelTimer()
  P.track = track
  local source, dur
  if track.parts then
    -- podcast: play the part to resume from; P.offset = duration of the previous parts
    local part = ns.EpisodePart(track)
    P.part, P.offset = part, 0
    for i = 1, part - 1 do P.offset = P.offset + track.parts[i].duration end
    ns.SetEpisodePart(track, part)
    source, dur = ns.LIB_ROOT .. track.parts[part].file, track.parts[part].duration
  else
    -- game music: PlayMusic takes the FileDataID; user tracks: path inside the data addon
    P.part, P.offset = nil, 0
    source, dur = track.fid or (ns.LIB_ROOT .. track.file), track.duration
  end
  local ok, err = pcall(playMusic, source)
  if not ok then ns.Print("MSG_PLAYMUSIC_ERROR", tostring(err)) end
  P.playing = true
  P.startTime = GetTime()
  dur = tonumber(dur) or 0
  if dur > 0 then
    -- PlayMusic loops the file: firing after the end replays its first moments
    -- (plus the time the client takes to open the next file), so end slightly early
    timer = C_Timer.NewTimer(math.max(dur - END_EARLY, 0.1), function()
      timer = nil
      -- the track ended while the music fades out after a fight: move on at once
      if ns.Rules and ns.Rules.TrackEnded and ns.Rules:TrackEnded() then return end
      if P:MaybeZoneBreak() then return end
      P:Next(true)
    end)
  end
  ns.Fire("TRACK_CHANGED", track)
  ns.Fire("STATE_CHANGED")
end

-- Elapsed time in the track (for podcasts: since the start of the episode).
function P:Elapsed()
  if not self.playing then return 0 end
  return (self.offset or 0) + GetTime() - self.startTime
end

-- Elapsed time in the current part (or track).
function P:ElapsedInPart()
  if not self.playing then return 0 end
  return GetTime() - self.startTime
end

-- Starts (or restarts from the beginning) the playlist's current track, or the queued track
-- being played (queued = a track just taken from the "Play next" queue).
function P:Play(name, queued)
  name = name or self.playlist
  if not playable(name) or not ns.db.enabled then return false end
  if not queued and self.fromQueue and name == self.playlist then queued = self.track end
  self:EndZoneBreak()
  self.playlist = name
  self.userStopped = false
  self.afkPaused = false
  startTrack(queued)
  return true
end

-- Plays a specific track of a playlist; the queue continues from there.
function P:PlayTrack(name, track)
  if not playable(name) then return end
  local pl = ns.GetPlaylist(name)
  resetState(name, indexOf(pl.tracks, track))
  self.explicitNext = true -- chosen by the user: plays even if excluded
  self.fromQueue = false
  self:Play(name)
end

-- The next track of the "Play next" queue, if it may play now: not during a fight or the
-- level-up jingle in automatic mode (the queue waits for the fight to end).
local function takeQueued()
  if #ns.db.upNext == 0 then return nil end
  local R = ns.Rules
  if ns.db.mode == "auto" and R and (R.FIGHT[R.current] or R.current == "levelup") then return nil end
  return ns.PopQueue()
end

-- Moves a playlist that already played to another track: every fight starts with a
-- different song (the next one of the shuffled queue, or a random one without shuffle).
local function freshTrack(name)
  local st, pl = getState(name)
  if not st.started or #st.queue < 2 then return end
  if ns.db.shuffle then
    advance(st, pl)
  else
    local r = math.random(#st.queue - 1)
    st.pos = r >= st.pos and r + 1 or r
  end
end

-- Switches playlist. Doesn't restart if it's already the one playing.
-- fresh = start a different track than the one the playlist stopped on.
function P:SetPlaylist(name, fresh)
  if not playable(name) then
    self.playlist = nil
    self.track = nil
    self:Stop()
    ns.Fire("TRACK_CHANGED", nil)
    return
  end
  if name == self.playlist and self.playing then return end
  if ns.db.mode ~= "auto" then self:EndZoneBreak() end -- the user picked a playlist
  if fresh then freshTrack(name) end
  self.playlist = name
  if self:IsHeld() or not ns.db.enabled then
    local st, pl = getState(name)
    self.fromQueue = false
    self.track = pl.tracks[st.queue[st.pos]]
    ns.Fire("TRACK_CHANGED", self.track)
    return
  end
  startTrack()
end

---------------------------------------------------------------------------
-- Volume controller. WoW has no per-track volume: everything goes through the Music
-- volume CVar. The user's volume (db.userVolume) is the only source of truth; what we
-- write is   user x condition volume x dialogue ducking x crossfade.
-- If the CVar is changed outside the addon (game Options), it is adopted as the new
-- user volume. On logout the plain user volume is written back.
---------------------------------------------------------------------------
local FADE_STEPS, FADE_TIME = 8, 0.8
local DUCK_LEVEL = 0.25
local V = { user = nil, cond = 1, duck = 1, fade = 1, lastWritten = nil, lastMul = 1 }
local tweens = {}

local function getVolume()
  local get = (C_CVar and C_CVar.GetCVar) or GetCVar
  return tonumber(get and get("Sound_MusicVolume")) or 1
end

local function setVolume(v)
  local set = (C_CVar and C_CVar.SetCVar) or SetCVar
  if set then pcall(set, "Sound_MusicVolume", tostring(v)) end
end

local function clamp(v) return math.max(0, math.min(1, v)) end

-- The CVar no longer holds what we wrote: the user changed it in the game options.
local function syncExternal()
  if not V.lastWritten then return end
  local cv = getVolume()
  if math.abs(cv - V.lastWritten) > 0.005 and V.lastMul > 0.01 then
    V.user = clamp(cv / V.lastMul)
    ns.db.userVolume = V.user
    V.lastWritten = cv
    ns.Fire("VOLUME_CHANGED", V.user)
  end
end

local function applyVolume()
  syncExternal()
  local mul = V.cond * V.duck * V.fade
  local eff = clamp((V.user or 1) * mul)
  setVolume(eff)
  V.lastWritten, V.lastMul = eff, mul
end

-- Animates factor V[field] to `to` in `time` seconds (default FADE_TIME), then calls done().
local function tween(field, to, done, time)
  if tweens[field] then tweens[field]:Cancel() end
  time = time or FADE_TIME
  local steps = math.max(FADE_STEPS, math.floor(time * 5)) -- at most 5 CVar writes per second
  local from, step = V[field], 0
  tweens[field] = C_Timer.NewTicker(time / steps, function()
    step = step + 1
    V[field] = from + (to - from) * step / steps
    applyVolume()
    if step >= steps then
      tweens[field]:Cancel()
      tweens[field] = nil
      if done then done() end
    end
  end, steps)
end

-- Sets V[field] at once, stopping its animation.
local function setFactor(field, value)
  if tweens[field] then tweens[field]:Cancel() tweens[field] = nil end
  V[field] = value
end

-- Called on load: recover from a /reload or crash in the middle of a fade/duck.
function P:InitVolume()
  if ns.db.fadeVolume then -- left over by version 0.5
    ns.db.userVolume = ns.db.userVolume or ns.db.fadeVolume
    ns.db.fadeVolume = nil
  end
  V.user = ns.db.userVolume or getVolume()
  ns.db.userVolume = V.user
  V.cond, V.duck, V.fade = 1, 1, 1
  applyVolume()
end

-- On logout: give the game back the plain user volume.
function P:RestoreVolume()
  for k, t in pairs(tweens) do t:Cancel() tweens[k] = nil end
  if V.user then setVolume(V.user) end
  V.lastWritten = nil
end

function P:GetVolume()
  syncExternal()
  return V.user or getVolume()
end

function P:SetVolume(v)
  V.user = clamp(tonumber(v) or 0)
  ns.db.userVolume = V.user
  applyVolume()
  ns.Fire("VOLUME_CHANGED", V.user)
end

-- Volume multiplier of the current condition (1 in free play).
function P:SetConditionVolume(mult)
  V.cond = clamp(tonumber(mult) or 1)
  applyVolume()
end

-- Lowers the music during cinematics and dialogues.
function P:SetDucked(on)
  if not ns.db.duck and on then return end
  tween("duck", on and DUCK_LEVEL or 1)
end

-- Switch playlist because the condition changed (fades if enabled and something is playing).
-- fresh: start a different track than last time (fights).
function P:SwitchTo(name, key, fresh)
  local mult = key and ns.ConditionVolume(key) or 1
  if not ns.db.crossfade or not self.playing or name == self.playlist then
    setFactor("fade", 1) -- a fight fade-out may have been interrupted
    self:SetConditionVolume(mult)
    self:SetPlaylist(name, fresh)
    return
  end
  local function switch()
    V.cond = mult
    self:SetPlaylist(name, fresh)
    tween("fade", 1)
  end
  if V.fade < 0.02 then -- already faded out (end of a fight): no second fade-out
    setFactor("fade", 0)
    switch()
  else
    tween("fade", 0, switch)
  end
end

-- After a fight: the music fades out slowly while the addon waits to leave the condition
-- (only with crossfade enabled).
function P:FadeOutSlowly(seconds)
  if ns.db.crossfade and self.playing then tween("fade", 0, nil, seconds) end
end

-- End of the fight tail (or its track ended): the fade-out is over, switch without a second one.
function P:EndFadeOut()
  if tweens.fade then setFactor("fade", 0) end
end

-- Back in the fight before the end of the fade-out: back to the previous volume.
function P:CancelFadeOut()
  if V.fade < 1 or tweens.fade then tween("fade", 1, nil, 1) end
end

-- For /kzz debug.
function P:DebugState()
  return ("playing %s, playlist %s, stopped %s, afk %s, zone break %s, volume x%.2f (cond %.2f duck %.2f fade %.2f)"):format(
    tostring(self.playing), tostring(self.playlist), tostring(self.userStopped), tostring(self.afkPaused),
    tostring(self.zoneBreakUntil ~= nil), V.cond * V.duck * V.fade, V.cond, V.duck, V.fade)
end

-- True when the music must stay silent: stopped by the user, paused while AFK, or during a
-- zone-music break.
function P:IsHeld()
  return self.userStopped or self.afkPaused or self.zoneBreakUntil ~= nil
end

---------------------------------------------------------------------------
-- Zone-music breaks (option, off by default): in calm conditions, every N tracks the game's
-- own zone music plays for M minutes (StopMusic gives it back). A more important condition,
-- Play, Next or a playlist choice end the break at once.
---------------------------------------------------------------------------
local CALM = { idle = true, zone = true, town = true, night = true, mounted = true }
P.CALM = CALM
local breakTimer
P.sinceBreak = 0

function P:InZoneBreak() return self.zoneBreakUntil ~= nil end

function P:EndZoneBreak()
  if breakTimer then breakTimer:Cancel() breakTimer = nil end
  if self.zoneBreakUntil then
    self.zoneBreakUntil = nil
    ns.Fire("STATE_CHANGED")
  end
end

-- Called when a track ends by itself: true if a break starts instead of the next track.
function P:MaybeZoneBreak()
  local t = self.track
  if not ns.db.zoneBreaks or ns.db.mode ~= "auto" or not CALM[ns.Rules.current] or (t and t.parts) then
    return false
  end
  self.sinceBreak = self.sinceBreak + 1
  if self.sinceBreak < (tonumber(ns.db.zoneBreakEvery) or 3) then return false end
  self.sinceBreak = 0
  self:Stop()
  local seconds = (tonumber(ns.db.zoneBreakMinutes) or 2) * 60
  self.zoneBreakUntil = GetTime() + seconds
  local from = self.playlist
  breakTimer = C_Timer.NewTimer(seconds, function()
    breakTimer = nil
    self.zoneBreakUntil = nil
    if ns.db.mode ~= "auto" or self:IsHeld() or not playable(self.playlist) then
      ns.Fire("STATE_CHANGED")
    elseif self.playlist == from then
      self:Next(true)
    else
      self:Play() -- the condition changed during the break: its playlist resumes where it was
    end
  end)
  ns.Fire("STATE_CHANGED")
  return true
end

function P:Stop(byUser)
  if self.playing and self.track then ns.RecordPlay(self.track, nil, GetTime() - self.startTime) end
  cancelTimer()
  if self.playing then pcall(StopMusic) end
  self.playing = false
  if byUser then self.userStopped = true end
  ns.Fire("STATE_CHANGED")
end

-- Play/Stop. With forcePlay it never stops.
function P:Toggle(forcePlay)
  if self.playing and not forcePlay then
    self:Stop(true)
    return
  end
  self.userStopped = false
  if not self:Play() then ns.Rules:Evaluate(true) end
end

-- A manual choice (next/previous) takes precedence over conditions:
-- in automatic mode we switch to free play of the current playlist,
-- until the user goes back to "Automatic".
local function takeManualControl()
  if ns.db.mode == "auto" and P.playlist then
    ns.db.mode = P.playlist
    ns.Rules:Reset()
    ns.Fire("MODE_CHANGED", P.playlist)
  end
end

-- auto = true when called by the end-of-track timer (not a user choice).
-- On a podcast it advances one part; after the last one the episode is done and we move on.
function P:Next(auto)
  if not playable(self.playlist) then return end
  if not auto then
    takeManualControl()
    if self.playing then ns.RecordSkip(self.track, self:ElapsedInPart()) end
  end
  local t = self.track
  if t and t.parts then
    local part = ns.EpisodePart(t)
    if part < #t.parts then
      ns.SetEpisodePart(t, part + 1)
      self:Play()
      return
    end
    ns.SetEpisodePart(t, 1, true) -- episode finished: next time it starts from the beginning
  end
  self.fromQueue = false
  local queued = takeQueued()
  if queued then self:Play(nil, queued) return end
  advance(getState(self.playlist))
  self:Play()
end

-- Jumps to the next (dir = 1) or previous (dir = -1) track of the queue, skipping the
-- remaining parts of a podcast episode (its progress is kept, to resume it later).
function P:SkipTrack(dir)
  if not playable(self.playlist) then return end
  takeManualControl()
  if dir > 0 and self.playing then ns.RecordSkip(self.track, self:ElapsedInPart()) end
  local wasQueued = self.fromQueue
  self.fromQueue = false
  if dir > 0 then
    local queued = takeQueued()
    if queued then self:Play(nil, queued) return end
  end
  if wasQueued and dir < 0 then self:Play() return end -- back to the playlist's own track
  local st = getState(self.playlist)
  st.pos = st.pos + (dir < 0 and -1 or 1)
  if st.pos < 1 then st.pos = #st.queue elseif st.pos > #st.queue then st.pos = 1 end
  self:Play()
end

-- Previous: restarts the part/track if a few seconds have passed, otherwise goes to the
-- previous part (podcast) or the previous track.
function P:Prev()
  if not playable(self.playlist) then return end
  takeManualControl()
  if self.playing and self:ElapsedInPart() > 3 then self:Play() return end
  local t = self.track
  if t and t.parts and ns.EpisodePart(t) > 1 then
    ns.SetEpisodePart(t, ns.EpisodePart(t) - 1)
    self:Play()
    return
  end
  if self.fromQueue then -- a queued track: back to the track the playlist was on
    self.fromQueue = false
    self:Play()
    return
  end
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

-- The client plays its own music on death / as a ghost / on resurrection and overrides
-- PlayMusic. We can't prevent it, so shortly after those events we start our track again
-- (WoW can't seek: a song restarts, a podcast resumes from its current part).
local REASSERT_DELAY = 1.5
local function reassert()
  C_Timer.After(REASSERT_DELAY, function()
    -- skip if a new track just started (e.g. the "dead" condition switched playlist)
    if P.playing and P.playlist and GetTime() - P.startTime > REASSERT_DELAY then
      ns.perfCount("reassert")
      startTrack(P.fromQueue and P.track or nil)
    end
  end)
end
for _, ev in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
  ns.RegisterEvent(ev, reassert)
end

-- AFK (/afk or the game's automatic AFK): pause, and resume when back.
ns.RegisterEvent("PLAYER_FLAGS_CHANGED", function(unit)
  if unit ~= "player" then return end
  local afk = ns.Safe(UnitIsAFK, "player") == true
  if afk and ns.db.afkPause and P.playing then
    P.afkPaused = true
    P:Stop()
  elseif not afk and P.afkPaused then
    P.afkPaused = false
    if not P:Play() then ns.Rules:Evaluate(true) end
  end
end)

-- Cinematics, movies and talking heads: lower the music, then bring it back.
for ev, on in pairs({ CINEMATIC_START = true, PLAY_MOVIE = true, TALKINGHEAD_REQUESTED = true,
                      CINEMATIC_STOP = false, STOP_MOVIE = false, TALKINGHEAD_CLOSE = false }) do
  ns.RegisterEvent(ev, function() P:SetDucked(on) end)
end

-- Playlist edited: rebuild the queue using the current track as the starting point.
ns.On("PLAYLISTS_CHANGED", function(name)
  if not name then wipe(states) return end
  states[name] = nil
  if P.playlist ~= name then return end
  if not playable(name) then
    P:SetPlaylist(nil)
    ns.Rules:Evaluate(true)
    return
  end
  if P.fromQueue then return end -- a queued track is playing: the queue is rebuilt when it ends
  local pl = ns.GetPlaylist(name)
  local idx = P.track and indexOf(pl.tracks, P.track)
  if idx then
    resetState(name, idx)
  elseif P.playing then
    P:Play(name) -- the current track was removed: switch to another
  end
end)
