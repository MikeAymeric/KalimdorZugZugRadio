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

local FISHING_SPELLS = { [7620] = true, [7731] = true, [7732] = true, [18248] = true, [33095] = true,
                         [51294] = true, [88868] = true, [131474] = true, [131490] = true }
local FISHING_GRACE = 20 -- seconds of "still fishing" between two casts
local NIGHT_START, NIGHT_END = 21, 6 -- game-time hours

local state = {
  encounter = false, combat = false, elite = false, taxi = false, campfire = false, dungeon = false,
  resting = false, levelup = false, pvp = false, dead = false, fishing = false, swimming = false,
  mounted = false, night = false,
}
local fishingUntil = 0
local pending, pendingKey

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

local function isFishingSpell(spellID)
  if type(spellID) ~= "number" then return false end
  if FISHING_SPELLS[spellID] then return true end
  local getName = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
  local name, fishing = ns.Safe(getName, spellID), ns.Safe(getName, 7620)
  return type(name) == "string" and name == fishing
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
  t.boss = state.encounter
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

-- First active condition (by priority) that has a playlist.
function R:Resolve()
  local active = self:ActiveSet()
  for _, s in ipairs(ns.SITUATIONS) do
    if active[s.key] then
      local pl = ns.PlaylistFor(s.key)
      if pl then return s.key, pl end
    end
  end
  return nil, nil
end

---------------------------------------------------------------------------
-- Evaluation: moving up in priority is immediate, moving down waits a few
-- seconds (avoids constant switching between pulls).
---------------------------------------------------------------------------
local function cancelPending()
  if pending then pending:Cancel() end
  pending, pendingKey = nil, nil
end

local function priority(key)
  return key and ns.PRIORITY[key] or 999
end

function R:Reset()
  cancelPending()
  self.current = nil
end

function R:Evaluate(immediate)
  ns.perfCount("Evaluate")
  if not ns.db or not ns.db.enabled or ns.db.mode ~= "auto" then return end
  local key, playlist = self:Resolve()

  local function apply()
    cancelPending()
    self.current = key
    ns.Player:SwitchTo(playlist, key) -- with a crossfade when enabled
    ns.Fire("SITUATION_CHANGED", key)
  end

  local P = ns.Player
  if key == self.current and playlist == P.playlist and (P.playing or P:IsHeld() or not playlist) then
    cancelPending()
    return
  end
  if immediate or self.current == nil or priority(key) < priority(self.current) then
    apply()
  elseif pendingKey ~= key then
    cancelPending()
    pendingKey = key
    pending = C_Timer.NewTimer(DOWNGRADE_DELAY, apply)
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
R.QueueEvaluate = queueEvaluate

local function on(event, fn)
  ns.RegisterEvent(event, ns.Profiled("event:" .. event, function(...)
    if fn(...) ~= false then queueEvaluate() end
  end))
end

function R:Start()
  self.started = true
  on("ENCOUNTER_START", function(encounterID, encounterName)
    state.encounter = true
    -- remember the boss, so a specific playlist can be assigned to it in the settings
    R.encounterID = ns.Safe(function() return encounterID end)
    local bossName = ns.Safe(function() return encounterName end)
    if type(R.encounterID) == "number" and type(bossName) == "string" then ns.db.seenBosses[R.encounterID] = bossName end
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
      levelupEnd = C_Timer.NewTimer(math.min(d, 120) + 0.2, endLevelup) -- before the player's own +0.5s advance
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
  for _, ev in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_MOUNT_DISPLAY_CHANGED" }) do
    on(ev, updateWorld)
  end
  on("ENCOUNTER_END", function() state.encounter = false R.encounterID = nil end)
  on("PLAYER_REGEN_DISABLED", function()
    state.combat = true
    state.campfire = false
    checkElite()
  end)
  on("PLAYER_REGEN_ENABLED", function()
    state.combat = false
    state.elite = false
    updateCampfire()
  end)
  on("PLAYER_TARGET_CHANGED", function()
    if state.combat then checkElite() end
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
    state.encounter = false
    updateWorld()
  end)
  for _, ev in ipairs({ "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_UPDATE_RESTING", "ZONE_CHANGED_NEW_AREA" }) do
    on(ev, updateWorld)
  end

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
