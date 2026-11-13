# RadioProbe: client compatibility probe

A tiny addon that checks, on the WoW Forever client, which APIs Kalimdor ZugZug Radio relies on.
Use it again after a client patch to see whether anything changed.

## Installation
1. The test files are already in `media/`. The three audio files are tones of different pitch, so you can tell which one you hear:
   `test.mp3` is the lowest (330 Hz), `test.wav` the middle one (440 Hz), `test.ogg` the highest (523 Hz).
2. Copy the `RadioProbe` folder into `World of Warcraft/_forever_/Interface/AddOns/`.
3. **Restart the client completely** (new files aren't picked up by /reload).
4. In the character screen → AddOns, enable "Radio Probe".

## Test checklist
On login it prints the build, missing APIs and events in chat. Then:

| What to do | Command / action | Note down |
|---|---|---|
| Audio | `/rprobe sound` | Which files you **heard** (ogg/mp3/wav) and whether they stop on their own after ~4s |
| PlayMusic | `/rprobe music`, then `/rprobe stopmusic` | Can you hear it? Does the zone music stop? |
| Covers | `/rprobe tex` | Can you see the TGA square? And the PNG one? |
| Combat | attack a mob | `[combat]` lines appear, possibly with `<SECRET>` |
| Elite / rare | attack an elite or rare in the open world | `[combat] UnitClassification(target)` line: readable value or `<SECRET>`? |
| Boss | enter a dungeon and pull a boss | Does `ENCOUNTER_START` fire? (instance bosses only, not rares/elites) |
| Flight | take a flight path | Does `State taxi: false -> true` appear? |
| Campfire | light a campfire, sit down, `/rprobe auras` | Name and spellId of the fire's aura |
| Enemy species | target a boar or wolf out of combat, attack it; repeat in a dungeon | `[creature]` lines: are `family`/`type`/`npc` readable or `<SECRET>` with `combat=true`? Also `/rprobe creature` |
| Summary | `/rprobe report` | Count of events received |

## Sending the results
`/reload` or log out, then share the file:
`World of Warcraft/_forever_/WTF/Account/<ACCOUNT_NAME>/SavedVariables/RadioProbe.lua`
