-- Rules: detects the character's conditions and picks the playlist assigned by the user.
-- Constraints verified on WoW Forever 1.60.1 (see CLAUDE.md):
--  * auras can't be read in combat -> only read out of combat
--  * boss1 is never populated -> bosses are detected with ENCOUNTER_START/END
--  * UnitClassification stays readable in combat
local _, ns = ...

local R = { current = nil }
ns.Rules = R

local AURA_CAMPFIRE_NEARBY = 1283391 -- "Campfire Nearby": close to a fire
local AURA_WELCOMING_FIRE  = 1229739 -- "Welcoming Campfire": sitting, lasts ~60s
local ELITE_CLASSES = { elite = true, rare = true, rareelite = true, worldboss = true }
local DOWNGRADE_DELAY = 4 -- seconds before switching to a less important condition
-- Fights: after the combat the music keeps playing (and fades out) for a few seconds
-- before the next condition, so chained pulls don't restart it every time.
local FIGHT = { boss = true, elite = true, combat = true }
local FIGHT_TAIL_DEFAULT = 8
local ENCOUNTER_TAIL = 4 -- shorter tail once a boss encounter is over
R.FIGHT = FIGHT

local FISHING_SPELLS = { [7620] = true, [7731] = true, [7732] = true, [18248] = true, [33095] = true,
                         [51294] = true, [88868] = true, [131474] = true, [131490] = true }
local FISHING_GRACE = 20 -- seconds of "still fishing" between two casts
local NIGHT_START, NIGHT_END = 21, 6 -- game-time hours

local state = {
  encounter = false, bossTail = false, shortTail = false, combat = false, elite = false, taxi = false, campfire = false, dungeon = false,
  resting = false, levelup = false, pvp = false, dead = false, fishing = false, swimming = false,
  mounted = false, night = false,
}
local fishingUntil = 0
local pending, pendingKey -- pendingKey "__tail" = fading out after a fight
local TAIL = "__tail"

---------------------------------------------------------------------------
-- Detection
---------------------------------------------------------------------------
local function hasAura(spellId)
  if InCombatLockdown() or not C_UnitAuras or not C_UnitAuras.GetPlayerAuraBySpellID then return nil end
  local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellId)
  if not ok then return nil end
  return aura ~= nil
end

local function updateCampfire()
  local nearby = hasAura(AURA_CAMPFIRE_NEARBY)
  if nearby == nil then return end -- not readable right now: change nothing
  if not nearby then
    state.campfire = false
  elseif hasAura(AURA_WELCOMING_FIRE) then
    -- stays on even when Welcoming Campfire expires: moving turns it off
    state.campfire = true
  end
end

local function isMoving()
  local speed = ns.Safe(GetUnitSpeed, "player")
  return type(speed) == "number" and speed > 0
end

local function checkElite()
  local class = ns.Safe(UnitClassification, "target")
  if type(class) ~= "string" or not ELITE_CLASSES[class] then return end
  if ns.Safe(UnitCanAttack, "player", "target") == false then return end
  state.elite = true -- stays true until the end of combat
end

-- Enemy family/type for enemy-specific music: the first attackable target of a fight decides it,
-- and the fight keeps it (and its song) until the end of the combat. Out of combat, targeting
-- an enemy only records it, so it can be assigned before the fight.
local function readFoe()
  if ns.Safe(UnitCanAttack, "player", "target") ~= true then return nil end
  return ns.FoeKeys("target")
end

local function checkFoe()
  if R.foeFamily or R.foeType then return false end
  local family, ctype = readFoe()
  if not family and not ctype then return false end
  R.foeFamily, R.foeType = family, ctype
  R.lastFoeFamily, R.lastFoeType = family, ctype
  return true
end

local function isFishingSpell(spellID)
  if type(spellID) ~= "number" then return false end
  if FISHING_SPELLS[spellID] then return true end
  local getName = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
  local name, fishing = ns.Safe(getName, spellID), ns.Safe(getName, 7620)
  return type(name) == "string" and name == fishing
end

-- The dungeon we are in (GetInstanceInfo's 8th value), remembered so a playlist can be
-- assigned to it. Leaving it also forgets the last boss met there.
local function updateDungeon()
  local id, name
  if state.dungeon and GetInstanceInfo then
    local ok, n, _, _, _, _, _, _, i = pcall(GetInstanceInfo)
    if ok and not ns.IsSecret(i) and type(i) == "number" then
      id = i
      name = (not ns.IsSecret(n) and type(n) == "string") and n or nil
    end
  end
  if id ~= R.dungeonID then
    R.dungeonID, R.lastBossID = id, nil
    if id and name then ns.db.seenDungeons[id] = name end
  end
end

local function updateWorld()
  state.taxi = ns.Safe(UnitOnTaxi, "player") == true
  state.resting = ns.Safe(IsResting) == true
  local ok, _, instanceType = pcall(IsInInstance)
  local known = ok and not ns.IsSecret(instanceType)
  state.dungeon = known and (instanceType == "party" or instanceType == "raid") or false
  state.pvp = known and (instanceType == "pvp" or instanceType == "arena") or false
  state.dead = ns.Safe(UnitIsDeadOrGhost, "player") == true
  state.swimming = ns.Safe(IsSwimming) == true
  -- ground mount: mounted, not on a taxi and not flying
  state.mounted = ns.Safe(IsMounted) == true and not state.taxi and ns.Safe(IsFlying) ~= true
  updateDungeon()
  local hour = GetGameTime and ns.Safe(GetGameTime)
  state.night = type(hour) == "number" and (hour >= NIGHT_START or hour < NIGHT_END) or false
  if state.fishing and GetTime() > fishingUntil and not ns.Safe(UnitChannelInfo, "player") then
    state.fishing = false
  end
end

-- Reused table: Evaluate runs often, don't allocate a new one every time.
local activeSet = {}
function R:ActiveSet()
  local t = activeSet
  t.levelup = state.levelup
  t.boss = state.encounter or state.bossTail -- the boss theme lasts while adds are still fighting
  t.elite = state.combat and state.elite
  t.pvp = state.pvp
  t.combat = state.combat
  t.dead = state.dead
  t.flight = state.taxi
  t.fishing = state.fishing
  t.swimming = state.swimming
  t.campfire = state.campfire
  t.dungeon = state.dungeon
  t.mounted = state.mounted
  t.zone = ns.ZonePlaylist() ~= nil -- active where the current zone has its own playlist
  t.town = state.resting
  t.night = state.night
  t.idle = true -- "No condition": always active, lowest priority
  return t
end

-- First active condition (by priority) that has a playlist. A condition set to the game's zone
-- music wins like any other, with no playlist: the player stops and the game's music plays.
function R:Resolve()
  local active = self:ActiveSet()
  for _, s in ipairs(ns.SITUATIONS) do
    if active[s.key] then
      local pl = ns.PlaylistFor(s.key)
      if pl == ns.ZONEMUSIC then return s.key, nil end
      if pl then return s.key, pl end
    end
  end
  return nil, nil
end

---------------------------------------------------------------------------
-- Evaluation: moving up in priority is immediate, moving down waits a few
-- seconds (avoids constant switching between pulls).
---------------------------------------------------------------------------
-- restore = the fight goes on (or the rules stop): bring back the volume of a fight tail.
local function cancelPending(restore)
  if pending then pending:Cancel() end
  if restore and pendingKey == TAIL then ns.Player:CancelFadeOut() end
  pending, pendingKey = nil, nil
end

function R:FightTailLength()
  if state.shortTail then return ENCOUNTER_TAIL end
  return tonumber(ns.db.fightTail) or FIGHT_TAIL_DEFAULT
end

local function priority(key)
  return key and ns.PRIORITY[key] or 999
end

-- For /kzz debug: the raw state flags and what the rules are waiting for.
function R:DebugState()
  local on = {}
  for k, v in pairs(state) do if v then on[#on + 1] = k end end
  table.sort(on)
  return ("flags {%s}, pending %s"):format(table.concat(on, " "), tostring(pendingKey))
end

function R:Reset()
  cancelPending(true)
  self.current = nil
end

function R:Apply(key, playlist)
  cancelPending()
  -- a zone-music break only lasts while the conditions stay calm
  if ns.Player:InZoneBreak() and not ns.Player.CALM[key] then ns.Player:EndZoneBreak() end
  -- every fight starts with a new track; a fight that goes on keeps its song
  local fresh = FIGHT[key] and key ~= self.current
  self.current = key
  ns.Player:SwitchTo(playlist, key, fresh) -- with a crossfade when enabled
  ns.Fire("SITUATION_CHANGED", key)
end

-- End of the fight tail: switch to whatever condition is active now.
local function finishTail()
  pending, pendingKey = nil, nil
  ns.Player:EndFadeOut()
  R:Apply(R:Resolve())
end

-- Called by the player when a track ends: during a fight tail, don't start another fight
-- track at low volume.
function R:TrackEnded()
  if pendingKey ~= TAIL then return false end
  pending:Cancel()
  finishTail()
  return true
end

function R:Evaluate(immediate)
  ns.perfCount("Evaluate")
  if not ns.db or not ns.db.enabled or ns.db.mode ~= "auto" then return end
  local key, playlist = self:Resolve()

  local P = ns.Player
  if key == self.current and playlist == P.playlist and (P.playing or P:IsHeld() or not playlist) then
    cancelPending(true) -- back in the fight during the tail: the song goes on
    return
  end
  if immediate or self.current == nil or priority(key) < priority(self.current) then
    self:Apply(key, playlist)
  elseif FIGHT[self.current] and key ~= self.current and P.playing then
    if pendingKey ~= TAIL then
      cancelPending()
      local length = self:FightTailLength()
      pendingKey = TAIL
      pending = C_Timer.NewTimer(length, finishTail)
      P:FadeOutSlowly(length)
    end
  elseif pendingKey ~= key then
    cancelPending()
    pendingKey = key
    pending = C_Timer.NewTimer(DOWNGRADE_DELAY, function() self:Apply(key, playlist) end)
  end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- Events only update the state; the evaluation is coalesced into one call on the next
-- frame, so a burst of events (e.g. UNIT_AURA at the start of a fight) costs one Evaluate.
local evalQueued = false
local function queueEvaluate()
  if evalQueued then return end
  evalQueued = true
  C_Timer.After(0, function()
    evalQueued = false
    R:Evaluate()
  end)
end

local function on(event, fn)
  ns.RegisterEvent(event, ns.Profiled("event:" .. event, function(...)
    if fn(...) ~= false then queueEvaluate() end
  end))
end

function R:Start()
  self.started = true
  on("ENCOUNTER_START", function(encounterID, encounterName)
    state.encounter = true
    state.shortTail = false
    -- remember the boss, so a specific playlist can be assigned to it in the settings
    R.encounterID = ns.Safe(function() return encounterID end)
    local bossName = ns.Safe(function() return encounterName end)
    if type(R.encounterID) == "number" and type(bossName) == "string" then ns.db.seenBosses[R.encounterID] = bossName end
    if type(R.encounterID) == "number" then R.lastBossID = R.encounterID end
  end)
  -- level up: the "levelup" playlist plays one track (a jingle), then the normal music comes back.
  -- The end is scheduled when the jingle actually starts (after a crossfade, if any);
  -- a 30s fallback covers "no playlist assigned".
  local levelupEnd
  local function endLevelup()
    levelupEnd = nil
    state.levelup = false
    R:Evaluate(true)
  end
  on("PLAYER_LEVEL_UP", function()
    state.levelup = true
    if levelupEnd then levelupEnd:Cancel() end
    levelupEnd = C_Timer.NewTimer(30, endLevelup)
  end)
  ns.On("TRACK_CHANGED", function(track)
    local d = track and tonumber(track.duration) or 0
    if state.levelup and R.current == "levelup" and d > 0 then
      if levelupEnd then levelupEnd:Cancel() end
      -- just before the player's own end-of-track advance, or it would start another jingle
      local early = (ns.Player and ns.Player.END_EARLY or 0) + 0.1
      levelupEnd = C_Timer.NewTimer(math.max(math.min(d, 120) - early, 0.1), endLevelup)
    end
  end)
  on("UNIT_SPELLCAST_CHANNEL_START", function(unit, _, spellID)
    if unit == "player" and isFishingSpell(ns.Safe(function() return spellID end)) then
      state.fishing = true
      fishingUntil = math.huge
    end
  end)
  on("UNIT_SPELLCAST_CHANNEL_STOP", function(unit)
    if unit == "player" and state.fishing then fishingUntil = GetTime() + FISHING_GRACE end
  end)
  for _, ev in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_MOUNT_DISPLAY_CHANGED",
                        "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_UPDATE_RESTING", "ZONE_CHANGED_NEW_AREA" }) do
    on(ev, updateWorld)
  end
  on("ENCOUNTER_END", function()
    state.encounter = false
    state.bossTail = state.combat -- adds still fighting: keep the boss theme until the combat ends
    state.shortTail = true
    R.encounterID = nil
  end)
  on("PLAYER_REGEN_DISABLED", function()
    state.combat = true
    state.campfire = false
    if not state.encounter and not state.bossTail then state.shortTail = false end
    checkElite()
    checkFoe()
  end)
  on("PLAYER_REGEN_ENABLED", function()
    state.combat = false
    state.elite = false
    state.bossTail = false
    R.foeFamily, R.foeType = nil, nil
    updateCampfire()
  end)
  on("PLAYER_TARGET_CHANGED", function()
    if not state.combat then readFoe() return false end
    local before = state.elite
    checkElite()
    if not checkFoe() and state.elite == before then return false end
  end)
  -- auras are unreadable in combat anyway: ignore UNIT_AURA there (it fires constantly)
  on("UNIT_AURA", function(unit)
    if unit ~= "player" or state.combat or InCombatLockdown() then return false end
    local before = state.campfire
    updateCampfire()
    if state.campfire == before then return false end -- nothing changed: no evaluation
  end)
  on("PLAYER_STARTED_MOVING", function() state.campfire = false end)
  on("PLAYER_ENTERING_WORLD", function()
    state.encounter, state.bossTail = false, false
    updateWorld()
  end)

  -- Safety net: some states (taxi, movement) have no reliable events.
  C_Timer.NewTicker(1, ns.Profiled("ticker", function()
    updateWorld()
    if state.campfire and isMoving() then state.campfire = false end
    R:Evaluate()
  end))

  updateWorld()
  updateCampfire()
  self:Evaluate(true)
end
