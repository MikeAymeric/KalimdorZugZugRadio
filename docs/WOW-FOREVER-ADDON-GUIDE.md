# Writing addons for WoW Forever: what we learned

What the WoW Forever client lets an addon see and do, collected while building Kalimdor ZugZug Radio
(0.1 to 1.2, November 2026). It is meant as a starting point for another addon: what you can track,
how to read it safely, what is missing, and the tooling and publishing lessons.

**Status labels** used below:

- **Probed**: checked in game with the `RadioProbe` addon (in this repo), on the build noted.
- **In use**: used by a released version of the radio, working in game, but not probed on its own.
- **Unverified**: not checked; treat it as a guess.

Builds seen: 1.60.1.70862 (first probe, 2026-11-09) and 1.60.1.70888 (2026-11-13).

---

## 1. Which client this is

| Fact | Value | Status |
|---|---|---|
| `## Interface:` in the `.toc` | `16001` | Probed |
| `WOW_PROJECT_ID` | `18` | Probed |
| API family | Modern **Mainline (Midnight era)**, not Classic, despite the classic-style world | Probed |
| `UnitAura` | **Does not exist**. Use `C_UnitAuras.*` | Probed |
| Combat log | **No `COMBAT_LOG_EVENT_UNFILTERED`** | Probed |
| Network / IPC | None (addon sandbox). That is why Spotify was dropped | Known limitation |
| File access from Lua | None: no listing folders, no reading files, tags or durations | Known limitation |

Because it is Mainline, you get Midnight's **secret values** (section 3). That one rule shapes every
design decision.

---

## 2. What you can track: quick table

"World" = open world. "Inst." = dungeon or raid. "Combat" = while `InCombatLockdown()` is true.

| What | How | World | Combat | Inst. | Status |
|---|---|---|---|---|---|
| In combat | `PLAYER_REGEN_DISABLED` / `_ENABLED`, `InCombatLockdown()` | yes | yes | yes | Probed |
| Dungeon boss fight | `ENCOUNTER_START(id, name)` / `ENCOUNTER_END` | n/a | yes | yes, id and name readable | Probed |
| World rare / elite as a "boss" | `ENCOUNTER_*` **does not fire** for them | no | | | Probed |
| `boss1` unit, `INSTANCE_ENCOUNTER_ENGAGE_UNIT` | **Never populated / never fired** | no | no | no | Probed |
| Target classification (elite, rare, worldboss) | `UnitClassification("target")` | yes | yes | yes | Probed |
| Target attackable | `UnitCanAttack("player", "target")` | yes | yes | yes | Probed |
| Target name | `UnitName("target")` | yes | yes | **secret**, even out of combat | Probed |
| Target creature type (Beast, Humanoid...) | `UnitCreatureType("target")` → name, **id** | yes | yes | **secret** | Probed |
| Target beast family (Boar, Wolf...) | `UnitCreatureFamily("target")` → name, **id** (tameable beasts only) | yes | yes | secret / nil | Probed |
| Target NPC id | `UnitGUID("target")`, 6th `-` field | yes | yes | **secret** | Probed |
| Target level | `UnitLevel("target")` | yes | yes | yes | Probed |
| Threat on the target | `UnitThreatSituation("player", "target")` (3 = tanking) | yes | yes | yes | Probed |
| Player health | `UnitHealth("player")` | **always secret** | | | Probed |
| Player auras | `C_UnitAuras.GetPlayerAuraBySpellID` | yes | **errors** | out of combat only | Probed |
| On a flight path | `UnitOnTaxi("player")` + `PLAYER_CONTROL_LOST/GAINED` | yes | | | Probed |
| Mounted | `IsMounted()` (**also true on a taxi**) | yes | | | Probed |
| Flying | `IsFlying()` | yes | | | In use |
| Resting (city, inn) | `IsResting()`, `PLAYER_UPDATE_RESTING` | yes | | | Probed |
| Swimming | `IsSwimming()` (no event: poll) | yes | | | Probed |
| Instance type | `IsInInstance()` → `inInstance, "party"/"raid"/"pvp"/"arena"/"none"` | | | yes | Probed |
| Which dungeon | `GetInstanceInfo()` 8th value = instanceID, 1st = name | | | yes (Ragefire = 389) | In use |
| Zone | `C_Map.GetBestMapForUnit("player")` + `C_Map.GetMapInfo(id)` chain | yes | yes | | In use |
| Zone text | `GetZoneText()`, `GetSubZoneText()`, `ZONE_CHANGED*` events | yes | | | Probed |
| Dead / ghost | `UnitIsDeadOrGhost("player")`, `PLAYER_DEAD/ALIVE/UNGHOST` | yes | | | In use |
| Level up | `PLAYER_LEVEL_UP` | yes | | | In use |
| Fishing | `UNIT_SPELLCAST_CHANNEL_START/STOP` (player, fishing spell ids) | yes | | | In use |
| Game time (night) | `GetGameTime()` → hour, minute | yes | | | In use |
| Moving | `PLAYER_STARTED_MOVING`, `GetUnitSpeed("player")` | yes | | | In use |
| AFK | `PLAYER_FLAGS_CHANGED` + `UnitIsAFK("player")` | yes | | | In use |
| Cinematics / talking heads | `CINEMATIC_START/STOP`, `PLAY_MOVIE/STOP_MOVIE`, `TALKINGHEAD_REQUESTED/CLOSE` | yes | | | In use |
| Battleground / arena | `IsInInstance()` type `pvp` / `arena` | | | | Unverified (never tested) |
| Nameplate units | `nameplateN` | | | | Unverified: the probe saw none (nameplates were probably hidden) |

### What you cannot track

- **Who is attacking you.** There is no combat log, and you can't enumerate enemies. The only handle on
  an enemy is a unit token: the **target** (and maybe nameplates, unverified).
- **Anything about enemies inside instances** except level and classification. Use `ENCOUNTER_START`
  for bosses and `GetInstanceInfo()` for the dungeon instead.
- **Player health and other secret numbers.** You can't test, compare or do arithmetic on them.
- **Auras during combat.** Read them before the pull or after it.

---

## 3. Secret values (Midnight restrictions)

In restricted contexts some API calls return a **secret value** instead of the real one. Comparing,
boolean-testing or doing arithmetic on it raises an error, and so does `tostring` in some cases. It does
not fail at the call: it fails later, wherever you touch the value.

Rules that worked:

1. **Wrap every call that might be restricted** and check the result with `issecretvalue` (it exists on
   Forever). The radio's helpers:

   ```lua
   function ns.IsSecret(v)
     if issecretvalue then
       local ok, secret = pcall(issecretvalue, v)
       return ok and secret == true
     end
     return false
   end

   -- Calls fn protected; returns the first value only if it isn't secret.
   function ns.Safe(fn, ...)
     if not fn then return nil end
     local ok, v = pcall(fn, ...)
     if not ok or ns.IsSecret(v) then return nil end
     return v
   end
   ```

2. **Check the type after `Safe`**, before using the value: `type(x) == "number"`, `type(s) == "string"`.
3. **Event arguments can be secret too.** Read them the same way:
   `ns.Safe(function() return encounterID end)`.
4. When you need more than the first return value, `pcall` the function yourself and check **each**
   value (see `readCreature` in section 5).
5. **Auras are a different failure**: `C_UnitAuras.*` throws "Auras cannot be accessed when secret
   while tainted" in combat. Guard with `InCombatLockdown()` and `pcall`, and treat "can't read" as
   "unchanged", not as "absent":

   ```lua
   local function hasAura(spellId)
     if InCombatLockdown() or not C_UnitAuras or not C_UnitAuras.GetPlayerAuraBySpellID then return nil end
     local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellId)
     if not ok then return nil end
     return aura ~= nil -- nil = unknown, keep the previous state
   end
   ```

---

## 4. Detection recipes

Patterns from `Rules.lua` that held up in game.

### Combat, elite, boss

- Combat: `PLAYER_REGEN_DISABLED` → on, `PLAYER_REGEN_ENABLED` → off.
- Elite: at `PLAYER_REGEN_DISABLED` and on `PLAYER_TARGET_CHANGED` while in combat, check
  `UnitClassification("target")` ∈ {elite, rare, rareelite, worldboss} and `UnitCanAttack`. **Latch** it
  until the end of combat: switching target must not drop it.
- Boss: `ENCOUNTER_START` / `ENCOUNTER_END`. **Adds can outlive the boss**: after `ENCOUNTER_END`, keep
  "boss" until `PLAYER_REGEN_ENABLED` if you are still in combat.
- Both `ENCOUNTER_START` arguments are readable (id and name). Store `id → name` the first time you see
  a boss, so the user can configure it later by name.

### Flight vs mounted

`IsMounted()` is **true on a taxi**. Check `UnitOnTaxi("player")` first, and treat "ground mount" as
`IsMounted() and not taxi and not IsFlying()`. Flight-path start/end fire `PLAYER_CONTROL_LOST/GAINED`.

### Campfire (an aura-based condition)

There is no "near a campfire" API. The radio uses two auras, read only out of combat:

- `Campfire Nearby` (spell 1283391): near a fire;
- `Welcoming Campfire` (spell 1229739): appears when you **sit** by it and expires after about 60 s.

It turns on when both are present and stays on after the second expires. It turns off when you move
(`PLAYER_STARTED_MOVING`, or `GetUnitSpeed` > 0 in a ticker), when `Campfire Nearby` goes, or when
combat starts. Use `/rprobe auras` to find the spell ids of other auras you want to use.

### Zone

`C_Map.GetBestMapForUnit("player")`, then walk `GetMapInfo(id).parentMapID` up to the continent. Use
the first map whose `mapType == Enum.UIMapType.Zone` (3) as "the zone". Then:

- micro maps (caves, floors) inherit it;
- a city that is a zone of its own (Orgrimmar inside Durotar) does not.

Map ids are language-independent; store those, not zone names. Cache the chain and invalidate it on
`ZONE_CHANGED`, `ZONE_CHANGED_INDOORS`, `ZONE_CHANGED_NEW_AREA` and `PLAYER_ENTERING_WORLD`.

### Fishing

`UNIT_SPELLCAST_CHANNEL_START(unit, castGUID, spellID)` for the player with a fishing spell id
(7620, 7731, 7732, 18248, 33095, 51294, 88868, 131474, 131490, or a spell with the same name as 7620).
Keep it on for a 20 s grace after `CHANNEL_STOP`, so re-casting doesn't flicker.

### States without reliable events

Taxi, swimming and movement need polling. A **1 s `C_Timer.NewTicker`** that re-reads the cheap
states was enough and costs almost nothing.

---

## 5. Enemy information (open world only)

Probed on 1.60.1.70888 in Stonetalon/Barrens and Ragefire Chasm:

| | Open world, out of combat | Open world, in combat | Instance (any time) |
|---|---|---|---|
| `UnitCreatureFamily` | name + id | name + id | nil |
| `UnitCreatureType` | name + id | name + id | **secret** |
| `UnitName` | readable | readable | **secret** |
| `UnitGUID` (npc id) | readable | readable | **secret** |
| `UnitClassification`, `UnitLevel` | readable | readable | readable |
| `UnitThreatSituation` | nil (no threat) | 3 = you have aggro | readable |

**Ids are returned as the 2nd value**, so you can key data by id and not depend on the client
language. Seen so far: `family 5` = Boar, `family 20` = Scorpid, `type 1` = Beast. Wind Serpent is a
family as well.

Things to know:

- **Only tameable beasts have a family.** A non-tameable beast (e.g. *Stormsnout*) has a type but no
  family. Quilboars (*Bristleback*) are **Humanoid**, not Boar.
- The **first attackable target of a fight** is a reasonable "who am I fighting". Latch it for the
  whole fight; with several enemies, the target is the only one you can see.
- Read the target **out of combat** too (`PLAYER_TARGET_CHANGED`), so the user can configure an enemy
  before fighting it.
- Keep a fallback key for clients that return no id: the name tagged with `GetLocale()`
  (`"family:enUS:Wind Serpent"`), ignored when the client language changes.

```lua
local function readCreature(fn, unit)
  if not fn then return nil end
  local ok, name, id = pcall(fn, unit)
  if not ok or ns.IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
  if ns.IsSecret(id) or type(id) ~= "number" or id <= 0 then id = nil end
  return name, id
end
-- local famName, famId = readCreature(UnitCreatureFamily, "target")
-- local typeName, typeId = readCreature(UnitCreatureType, "target")
```

Parsing the npc id from a GUID (`Creature-0-server-instance-zoneUID-npcID-spawnUID`): check
`IsSecret(guid)` first, then `select(6, strsplit("-", guid))`.

---

## 6. Audio

| Fact | Status |
|---|---|
| `PlaySoundFile(path, "Music")` returns `willPlay, handle`; `StopSound(handle, fadeMs)` stops it with a fade | Probed |
| OGG, MP3 and WAV play from an addon folder | Probed |
| `PlayMusic(pathOrFileDataID)` replaces the zone music; `StopMusic()` gives it back | Probed |
| `PlayMusic(fid)` plays game soundtrack files by FileDataID | In use |
| **`PlayMusic` loops the file**: if you advance after the end, the start of the song plays again. Schedule the next track ~0.2 s **before** the end (0.3 s cut audible audio, 0.1 s still let a blip through) | In use |
| No position, seek or duration API. Elapsed time = `GetTime() - start`; durations must come from outside (the import script measures them with ffprobe) | Known limitation |
| Music volume = CVar `Sound_MusicVolume` (0-1). A crossfade is a tween of that CVar. Restore the user's value on load/logout in case a fade was interrupted | In use |
| **New media files need a full client restart**; `/reload` only reloads Lua | Probed |
| Non-ASCII file paths | Unverified: the radio renames files to ASCII to be safe |

Keep one place that writes the volume CVar (the radio multiplies user × condition × duck × fade) and
adopt external changes made in the game options; otherwise two writers fight.

---

## 7. Textures, fonts and text

- **TGA and PNG textures** both load from an addon folder (Probed). The radio renders covers to
  256×256 PNG.
- Game icons by FileDataID work as textures (`SetTexture(fid)`).
- **No per-glyph font fallback**: a font string shows only the glyphs of its own font. Text in another
  script (kana, kanji, hangul, ★ ♪) shows as boxes unless you switch that font string to a font that
  has them. The radio bundles OFL fonts (M+ 1p plus Noto symbols; Nanum Gothic for Korean) and
  picks a font per string from its content (`ns.TextFont`, `ns.SetText`).
- WoW has **no Japanese client**, and non-CJK clients lack CJK fonts. The **chat font can't be
  changed per message**, so chat output falls back to English for those languages.
- `SetFontObject` resets the text color: re-apply colors after switching fonts.
- **Escape codes**: WoW reads `|c` (color), `|T` (texture), `|H` (link) in any text. Double every `|`
  in untrusted text (file tags, feeds, names typed by users, pasted strings) before showing it.

---

## 8. UI and API availability

| Item | Status |
|---|---|
| Settings panel: `Settings.RegisterCanvasLayoutCategory` + `RegisterAddOnCategory` | Probed |
| `Settings.OpenToCategory(id)` **may silently not show the panel**, and is refused in combat. Try several ways and fall back to a standalone window | In use |
| Modern Menu API dropdowns: `CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")` + `SetupMenu`, `CreateRadio`, nested `CreateButton`, `GenerateMenu()` to refresh | Probed (template), In use |
| The Menu API **runs the generator on every open**: menus can follow live state for free | In use |
| `BackdropTemplate`, `UIPanelScrollFrameTemplate`, `UIPanelButtonTemplate` | In use |
| **`Slider:SetObeyStepDrag` does not exist** (it broke a window). Guard optional widget methods: `if obj.Method then` | Probed (crash) |
| Minimap button: needs a **frame level above `Minimap:GetFrameLevel()`** or it renders underneath | In use |
| Addon Compartment (`## AddonCompartmentFunc` etc. in the `.toc`) | In use |
| Key bindings: `Bindings.xml` is auto-loaded; set `BINDING_NAME_*` globals | In use |
| `C_Timer.After`, `C_Timer.NewTimer`, `C_Timer.NewTicker` | Probed |
| `debugprofilestop()` for CPU timing | In use |
| `C_AddOns.GetAddOnMetadata` | In use |
| Movable frames: `SetMovable`, `RegisterForDrag`, `StartMoving`/`StopMovingOrSizing`, save `GetPoint(1)` | In use |

A frame that must never block clicks (a toast over the chat) should keep `EnableMouse(false)` and
only take the mouse in an explicit "move" mode.

---

## 9. Data, files and SavedVariables

- **Lua can't read the disk.** Anything about files (which exist, tags, durations, covers) must be
  produced by an **external script** that writes a Lua manifest the addon loads (the radio's
  `tools/import_music.py` → `Library.lua`). Make it stdlib-only and ship it inside the addon so store
  users get it.
- **Addon managers replace the addon folder on update** (the CurseForge app deletes files you added).
  Keep user content in a **separate data addon** (`KalimdorZugZugRadio_Library/`, with its own
  `.toc`) and reference it with `## OptionalDeps:`. Ids relative to the data folder survive the move.
- **SavedVariables are written on `/reload` and logout**, not live. They live in
  `WTF\Account\<account>\SavedVariables\<Addon>.lua`, which you can read from outside the game.
- **Diagnose through SavedVariables**: store startup errors, a timestamped debug dump (`/kzz debug`)
  and a login snapshot in the DB. After one `/reload` you read the file directly, with nothing to
  copy from chat.
- Wrap every startup step in `xpcall`, so one error doesn't stop the rest; keep the errors.
- Store **ids, not names**, for anything localized: map ids, encounter ids, instance ids, creature
  family/type ids. Keep a `seen[id] = name` table for display.
- Profiles: keep per-character settings in `profiles[name]` and make the active profile's tables
  aliases, nil'ed on `PLAYER_LOGOUT` so they aren't saved twice.

---

## 10. Performance patterns

- Event handlers only **update state**. Coalesce evaluations into one `C_Timer.After(0, ...)`, so a
  burst of events costs one evaluation.
- **Ignore `UNIT_AURA` in combat**: it fires constantly and auras are unreadable then anyway.
- Reuse tables in hot paths. Cache expensive lookups (map chain) and invalidate them on events.
- Rebuild menus only when their data changes.
- Measure: wrap handlers in a profiler (`debugprofilestop`) and expose a `/perf` command.

---

## 11. Testing without the game

There is no local Lua and no game in CI, so the radio tests with **fengari** (Lua 5.3 VM in Node):

- `tests/harness.lua` stubs the WoW API: frames return a metatable stub that accepts any call, plus a
  `G` table of game state, `fire(event, ...)`, `advance(seconds)` for timers;
- `tests/lint.js` checks Lua 5.1 syntax for every addon file.

Stubs accept any widget call, so the harness **does not replace in-game testing**. Mark methods that
are missing on Forever as missing in the stubs too (e.g. `SetObeyStepDrag` returns nil).

### Re-checking the client: RadioProbe

`RadioProbe/` is a throwaway addon that prints and logs (to its SavedVariables) the build, missing
APIs, events that can't be registered, combat snapshots of secret values, auras, audio and texture
tests, and `[creature]` lines for the target and nameplates (`/rprobe creature`). Run it after a
client patch, or copy its pattern for a new question: **probe first, then design**.

---

## 12. Publishing (CurseForge, Wago, GitHub)

- The zip must contain **only the addon folder(s)**.
- **CurseForge rejects `.bat`** (and other scripts like `.exe`, `.cmd`, `.ps1`) in the zip. Ship a
  `.py` launcher instead.
- Line endings: `.toc` CRLF, `.lua`/`.py` LF (set in `.gitattributes`).
- Build the zip **from the tag** (`git archive <tag>`), then add the license, so local files never leak in.
- The user's data addon is created by the import script, never shipped.

---

## 13. Open questions

- Do **nameplate units** expose the same enemy info, and can they tell which enemies are fighting you?
  The probe saw no nameplates (probably hidden in the options).
- Do **non-ASCII file paths** play?
- **Battleground and arena** detection was never tested.
- `UnitCreatureFamily` inside instances returned nil; whether it would be secret for a beast there is
  unknown.
