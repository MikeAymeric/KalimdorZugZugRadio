-- Rules: rileva le condizioni del personaggio e sceglie la playlist assegnata dall'utente.
-- Vincoli verificati su WoW Forever 1.60.1 (vedi CLAUDE.md):
--  * le aure non sono leggibili in combattimento -> lette solo fuori combattimento
--  * boss1 non viene valorizzato -> i boss si rilevano con ENCOUNTER_START/END
--  * UnitClassification resta leggibile in combattimento
local _, ns = ...

local R = { current = nil }
ns.Rules = R

local AURA_CAMPFIRE_NEARBY = 1283391 -- "Campfire Nearby": vicino a un fuoco
local AURA_WELCOMING_FIRE  = 1229739 -- "Welcoming Campfire": seduto, dura ~60s
local ELITE_CLASSES = { elite = true, rare = true, rareelite = true, worldboss = true }
local DOWNGRADE_DELAY = 4 -- secondi prima di passare a una situazione meno importante

local state = {
  encounter = false, combat = false, elite = false,
  taxi = false, campfire = false, dungeon = false, resting = false,
}
local pending, pendingKey

---------------------------------------------------------------------------
-- Rilevamento
---------------------------------------------------------------------------
local function hasAura(spellId)
  if InCombatLockdown() or not C_UnitAuras or not C_UnitAuras.GetPlayerAuraBySpellID then return nil end
  local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellId)
  if not ok then return nil end
  return aura ~= nil
end

local function updateCampfire()
  local nearby = hasAura(AURA_CAMPFIRE_NEARBY)
  if nearby == nil then return end -- non leggibile ora: non cambiare nulla
  if not nearby then
    state.campfire = false
  elseif hasAura(AURA_WELCOMING_FIRE) then
    -- resta attivo anche quando Welcoming Campfire scade: lo spegne il movimento
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
  state.elite = true -- resta vero fino alla fine del combattimento
end

local function updateWorld()
  state.taxi = ns.Safe(UnitOnTaxi, "player") == true
  state.resting = ns.Safe(IsResting) == true
  local ok, _, instanceType = pcall(IsInInstance)
  state.dungeon = ok and not ns.IsSecret(instanceType)
    and (instanceType == "party" or instanceType == "raid") or false
end

function R:ActiveSet()
  return {
    boss = state.encounter,
    elite = state.combat and state.elite,
    combat = state.combat,
    flight = state.taxi,
    campfire = state.campfire,
    dungeon = state.dungeon,
    town = state.resting,
    idle = true, -- "Nessuna condizione": sempre attiva, priorità più bassa
  }
end

-- Prima situazione attiva (per priorità) che ha una playlist.
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
-- Valutazione: salire di priorità è immediato, scendere aspetta qualche
-- secondo (evita cambi continui tra un pull e l'altro).
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
  if not ns.db or not ns.db.enabled or ns.db.mode ~= "auto" then return end
  local key, playlist = self:Resolve()

  local function apply()
    cancelPending()
    self.current = key
    ns.Player:SetPlaylist(playlist)
    ns.Fire("SITUATION_CHANGED", key)
  end

  local P = ns.Player
  if key == self.current and playlist == P.playlist and (P.playing or P.userStopped or not playlist) then
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
-- Eventi
---------------------------------------------------------------------------
local function on(event, fn)
  ns.RegisterEvent(event, function(...)
    fn(...)
    R:Evaluate()
  end)
end

function R:Start()
  on("ENCOUNTER_START", function() state.encounter = true end)
  on("ENCOUNTER_END", function() state.encounter = false end)
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
  on("UNIT_AURA", function(unit)
    if unit == "player" then updateCampfire() end
  end)
  on("PLAYER_STARTED_MOVING", function() state.campfire = false end)
  on("PLAYER_ENTERING_WORLD", function()
    state.encounter = false
    updateWorld()
  end)
  for _, ev in ipairs({ "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_UPDATE_RESTING", "ZONE_CHANGED_NEW_AREA" }) do
    on(ev, updateWorld)
  end

  -- Rete di sicurezza: alcuni stati (taxi, movimento) non hanno eventi affidabili.
  C_Timer.NewTicker(1, function()
    updateWorld()
    if state.campfire and isMoving() then state.campfire = false end
    R:Evaluate()
  end)

  updateWorld()
  updateCampfire()
  self:Evaluate(true)
end
