# FightingLab Overhaul 6 — "Make it feel like a real 3D fighter" (binding contract)

OV6 = `C:\Users\solim\.copilot\session-state\e3751321-5f48-4183-b62a-9577765df8cf\files\overhaul6`

The user played the Overhaul 5 duel lobby as a normal player and judged it bad. Their complaints, verbatim themes:
the fighting doesn't feel like Tekken at all; you move in circles (shouldn't be possible); moves look like crap,
goofy and unrealistic; controls aren't clear; the map isn't great; characters need more work; the CPU bot is crazy
for no reason; there are cheese moves; when you die you float; the menu sucks; the character select is goofy.
Every workstream exists to fix one or more of those. Judge your work as a general player would.

## 0. What a general player must feel (acceptance targets)

1. **Grounded 3D-fighter footwork.** Fighters always face each other on a fight line. Movement is deliberate:
   walk forward ≈ 5 studs/s, walk back ≈ 4 studs/s (style ±15%); forward dash (double-tap forward) ≈ 3 studs in
   ≈ 14 frames; backdash (double-tap back) ≈ 3 studs in ≈ 18 frames, chainable; **sidestep is a discrete step**
   (tap W = into the screen, tap S = toward the camera) ≈ 1.8 studs of arc in ≈ 16 frames + short recovery, one step
   per tap. **No continuous circling** — holding W/S must never orbit the opponent. Crouch (hold S) is stationary.
2. **Tekken-convention guarding** (a genre mechanic, not copied content): standing still or holding back = standing
   guard (blocks highs and mids, back also walks back); holding down = crouch guard (blocks lows, ducks highs, takes
   mids). There is no guard button.
3. **Four limbs + strings + throws.** Buttons 1/2/3/4 = left punch / right punch / left kick / right kick. Each
   fighter has an original moveset of ~12–16 moves including 2–4 strings (e.g. 1,2 / 1,1,2 / 2,1 / 3,4) that chain
   with natural timing, a fast poke, a mid check, a low, a launcher (unsafe), a power move, and a throw. Throws break
   with the matching punch within a window. Directional inputs (forward/down/back + button) select moves.
4. **Impacts that read.** Hitstop, counter-hit, distinct hit reactions by height/strength, knockdowns, getups.
5. **Realistic motion.** Motion-capture-based animation (legally reusable data only), weight shift, planted feet,
   follow-through. **Bodies always rest on the floor** when knocked down or KO'd — never floating.
6. **Clear controls.** One consistent scheme (section 2), shown on screen in fights, taught in the practice dojo,
   and every lobby interaction is an on-screen `E` prompt.
7. **A fair, human CPU.** Easy/Normal/Hard differ by reaction time, blocking, punishing, combo length and decision
   noise. It walks, pokes, blocks, punishes sometimes, uses strings and throws, and backs off. Never jittery, never
   sidestep-spamming, never frame-perfect below Hard.
8. **No cheese.** Launchers are unsafe on block, juggles are limited, wake-ups can't be looped, no move or loop
   beats the CPU or players by spamming. Proven by an automated exploit search.
9. **Polished, original UI.** Lobby menu and fighter select that look like a premium game (not goofy), HUD that
   reads instantly.
10. **A good map.** Compact, readable, arenas visible from spawn and reached in a few seconds, visible arena edges,
    no visual bugs (e.g. grass blades sticking through pavement — Terrain.Decoration is now OFF in the base).

## 1. Hard rules (all agents)

1. **Originality.** No TEKKEN (or any franchise) characters, names, move names, logos, UI art, music, stage
   replicas or ripped assets/animations, even with credit. Generic genre mechanics and conventions (4-button layout,
   back-to-guard, sidesteps, strings, frame data) are fine. Motion data must be legally reusable for a free or
   commercial Roblox game with modification (CC0, CC BY, CMU mocap terms). Never NC/ND, never "personal use only",
   never data from Bandai Namco or ripped from any game.
2. **Never steal focus.** The user may be gaming. Launch Studio minimized, then park it behind other windows without
   activating: `& "$OV6\tools\Show-StudioBehind.ps1" -ProcessId <pid>` (1920x1040). Never activate or raise windows,
   never send OS-level keystrokes.
3. **Never touch** the user's Studios (`FightingLab.rbxlx` id `6221599d-…`, `REALSTEEL.rbxlx`) or files outside OV6
   except reading. Only the integrator edits the main place.
4. **Never write .rbxlx with Lune.** Your own Studio may save your own work file.
5. **Code is the deliverable.** Export every script you changed or created to `OV6\handoff\<agent>-src\
   <Full.Roblox.Path>.luau` (UTF-8, LF, no BOM). Existing scripts keep their exact baseline file name (see
   `OV6\baseline-src\`). NEW server Scripts end in `.server.luau`, NEW LocalScripts in `.client.luau`, NEW
   ModuleScripts are plain `.luau`. Anything the game needs at runtime must be created by code or be a script/module.
6. **Stay in your ownership** (section 5). For changes elsewhere write "REQUEST: <file>: <change>" in your report or
   `OV6\handoff\<agent>.md`; the integrator applies them.
7. **Tests**: keep the full suite green in your Studio (Play, Server: `require(game.ServerStorage.UnitTest.RunUnitTest)
   (nil,5)` → `[SUMMARY] N run, N passed, 0 failed`). Update tests whose expectations your change intentionally
   alters (only in files you own; otherwise REQUEST). Add tests for new behaviour.
8. **Look at your own screenshots/data** before reporting. Report problems honestly. Prefer evidence (numbers,
   contact sheets, burst captures) over claims.
9. **Memory**: one Studio per agent; close extras; check free RAM before launching
   (`(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1MB` GB). Below 4.5 GB: keep working offline and
   re-check every ~10 minutes. Stop Play when not testing. Close your Studio when done.
10. MCP `execute_luau` runs on Studio's main thread: chunk heavy work with `task.wait()`.
11. The shared SQL `todos` table belongs to everyone: only insert/update rows **you created** (prefix your ids with
    your agent name). Never bulk-update other rows.

## 2. Control scheme (binding — combat implements, UI displays, everyone uses these words)

Fight, keyboard (your fighter is always shown on the LEFT, so D is always toward the opponent):
- `D` walk forward, double-tap `D` dash · `A` walk back + guard, double-tap `A` backdash
- tap `W` sidestep into the screen · tap `S` sidestep toward the camera · hold `S` crouch (crouch guard)
- `U` = 1 left punch · `I` = 2 right punch · `J` = 3 left kick · `K` = 4 right kick
- `O` throw (also `U`+`J` or `I`+`K` together); break a throw with `U` or `I`
- standing still = standing guard; `G` toggles the on-screen controls guide
- practice dojo only: `R` reset positions · `T` switch Training ↔ Versus CPU · `1`/`2`/`3` CPU difficulty ·
  `Y` dummy behaviour (stand / guard / fight back) · `P` pause · `Backspace` leave
Fight, gamepad: left stick / D-pad move (same semantics), `X`=1, `Y`=2, `A`=3, `B`=4, `RB` throw, `Start` pause (practice).
Lobby: `WASD` walk, `Space` jump, `E` interact (every interaction is an on-screen ProximityPrompt: Fighter Kiosk
"Choose Fighter", duel pad "Fight CPU" once waiting alone, dojo pads "Start Training" / "Versus CPU"),
`Tab` lobby menu. No other lobby hotkeys.

Single source of truth: NEW module `ReplicatedStorage.FightingLab.Controls` (combat owns) exporting the bindings and
display labels, e.g. `{ fight = { keyboard = { forward = "D", back = "A", sidestepIn = "W", sidestepOut = "S",
crouch = "S", lp = "U", rp = "I", lk = "J", rk = "K", throw = "O", guide = "G" }, gamepad = {...} },
practice = {...}, lobby = { interact = "E", menu = "Tab", jump = "Space" }, notation = { lp = "1", rp = "2",
lk = "3", rk = "4" }, label = function(group, action, device) -> string }`. InputController reads it; UI renders
legends and prompts from it. UI may stub it locally for testing but must not export it.

## 3. Setup (each agent)

- Base place: `OV6\base\FightingLab-base.rbxlx` (= current game, Terrain.Decoration off). Baseline sources:
  `OV6\baseline-src\` (94 scripts). Tools: `OV6\tools\`.
- Copy the base to `OV6\work\<agent>\FightingLab-<agent>.rbxlx` and open it:
  `Start-Process "C:\Users\solim\AppData\Local\Roblox\Versions\version-9b554450a0fc4e65\RobloxStudioBeta.exe"
  -ArgumentList '"<path>"' -WindowStyle Minimized -PassThru`, then `Show-StudioBehind.ps1 -ProcessId <pid>`; find its
  studio id with `list_roblox_studios` (name = your file name).
- Live code sync (Edit mode only): serve a folder with `python -m http.server <port> --bind 127.0.0.1 --directory
  <folder>` (async shell), write `index.json` (array of file names), then in Edit mode `HttpService:GetAsync` each
  file and set `.Source` (normalise CRLF→LF; create missing scripts by suffix). Ports: motioncore 35301,
  combat 35302, ui 35303, world 35304, motionstrikes 35305, characters 35306, motionkicks 35307,
  motionthrows 35308. Stop your server when done.
- Screenshots in Play: calibrate once per window size with a full-screen magenta ScreenGui (IgnoreGuiInset,
  DisplayOrder 100000), then `& "$OV6\tools\Capture-StudioViewport.ps1" -PlacePath <your rbxlx> -CalibrationFile
  <your rect json> -OutPath <png> [-Burst n -IntervalMs ms] [-Calibrate]` (PrintWindow, no focus change). Remove the
  magenta GUI before real shots; never send MCP keys in parallel with a capture. If consecutive captures are
  identical while the game should change, the frame is stale — wait and retry. Edit mode: MCP `screen_capture`
  (camera_position/look_at_position) also works. A display keep-awake is running for the session.
- Play input: MCP `user_keyboard_input` / `user_mouse_input` (Client). It refuses `1` and `Tab` (core-bound).
- The game spawns you in the lobby (WorldBoot + Duel server). To fight: walk/teleport onto a duel pad
  (`workspace.FightingLabWorld.Arenas.Arena_MidnightRooftop.PadP1`) and request a CPU (current key `F`), or use a
  dojo pad. Server-side helpers exist in Studio: `ServerScriptService.FightingLabServer` creates a
  `FightingLabDuelDebug` BindableFunction (commands `stats`, `addStub`, `removeStubs`, `stubAi`, `startCpu`,
  `finish`, `setHealth`, `avatarSettle`; read that script for arguments) — e.g. `startCpu(arenaId, cpuSlot,
  difficulty)` runs a CPU-vs-CPU match you can watch and capture.

## 4. Interfaces between workstreams

- **Fight state → animation.** combat publishes `OV6\handoff\combat-states.md` early and keeps it current: every
  fighter `state`, its timing fields and any new snapshot fields (e.g. sidestep direction/frame, dash, guard kind,
  string index, throw phases, knockdown face-up/down, getup kind). The snapshot path is
  `MatchRunner.serialize` → `NetProtocol.packEntry/unpack` → `RenderBuffer.parse` → client `FighterView`.
  Changes must be additive where possible; renames/removals need a handoff note and a message to the integrator.
- **Animation clips.** motioncore defines the clip format, the mocap conversion tools and the runtime API for
  per-move clips, and announces "CLIP PIPELINE READY" in `OV6\handoff\motioncore.md` (format, how to convert,
  how to bind a clip to a move key with contact-frame alignment). Phase 2 (started later) builds every attack:
  motionstrikes, motionkicks and motionthrows, each in its own `Clips.Moves.<Category>` subfolder (no shared registry).
- **Controls.** `ReplicatedStorage.FightingLab.Controls` (section 2).
- **World anchors** (unchanged names): `workspace.FightingLabWorld.{Lobby,Arenas}`, `LobbySpawn`, `FighterKiosk.
  PromptPart.ChooseFighter`, `Leaderboard.LeaderboardGui`, per arena `FightOrigin`, `PadP1/PadP2` (duel) or
  `PadTraining/PadCpu` (dojo), `ExitP1/ExitP2` / `ExitTraining/ExitCpu`, `StatusBoard.StatusGui`, model attributes
  `ArenaId, StageId, DisplayName, Kind, Order`, `ReplicatedStorage.FightingLab.WorldReady`. Fight radius around
  FightOrigin is 21 studs (CombatConfig.ArenaRadius) unless combat changes it (then tell world via the integrator).
- **Duel/lobby protocol** (integrator-owned code, see OV5 `CONTRACTS-v5.md` §4): remotes `FightingLab.Command`,
  `FightingLab.Snapshot`, `FightingLab.Net.Lobby` (SelectFighter, RequestCpu, StartPractice, EndPractice,
  LeaveFight) and `Net.Duel`; Station and Player attributes. Command kinds from clients are limited to
  Move/Block/Crouch/Attack — interpret new mechanics inside the sim from those (e.g. sidestep from a Move z tap,
  guard from holding back). If you truly need a new command kind or remote, REQUEST it.

## 5. Ownership

| Owner | Files (`RF` = ReplicatedStorage.FightingLab, `CL` = RF.Client, `UT` = ServerStorage.UnitTest.Cases) |
|---|---|
| **combat** | `RF.CombatSim`, `RF.CombatConfig`, NEW `RF.CombatAI`, `RF.Roster`, `RF.MatchRunner`, `RF.RenderBuffer`, `RF.SnapshotTiming`, `RF.NetProtocol`, NEW `RF.Controls`, `CL.InputController`, tests `CombatSim_Test`, `CombatRoster_Test`, `Difficulty_Test`, `MatchRunner_Test`, `RenderBuffer_Test`, `SnapshotTiming_Test`, `DuelProtocol_Test`, `Controls_Test`, NEW `Combat*_Test`, `AI*_Test`, `Balance*_Test` |
| **motioncore** | `CL.MotionPlayer`, `CL.MotionLibrary`, `CL.Motion.States`, NEW `CL.Motion.Clips.Core.*` (all non-move clips: stances, locomotion, guards, reactions, falls, getups, KO, victory), NEW `CL.Motion.ClipPlayer` and/or `CL.Motion.ClipLibrary`, `CL.CharacterPresenter`, `CL.CameraDirector`, `CL.EffectsController`, `CL.AudioController`, `CL.FighterLighting`, `CL.FaceController`, tests `MotionPlayer_Test`, `VfxFeel_Test`, `VfxV2_Test`, `FaceController_Test`, NEW `MotionCore*_Test`, `MotionClip*_Test`, `MotionGround*_Test`, `Camera*_Test`, tools in `OV6\tools\mocap\` |
| **motionstrikes** (phase 2) | `CL.Motion.Strikes`, `CL.Motion.MoveAnimOverrides`, NEW `CL.Motion.Clips.Moves.Strikes.*` (punches, palms, elbows, backfists, parry, shoulder tackles — all fighters), tests `MotionStrikes*_Test`, NEW `MotionMovesStrikes*_Test` |
| **motionkicks** (phase 2) | `CL.Motion.Kicks`, NEW `CL.Motion.Clips.Moves.Kicks.*` (kicks, knees, sweeps — all fighters), tests `MotionKicks*_Test`, NEW `MotionMovesKicks*_Test` |
| **motionthrows** (phase 2) | `CL.Motion.Throws`, NEW `CL.Motion.Clips.Moves.Throws.*` (all 1+3 / 2+4 / command throws, attacker + defender), tests `MotionThrows*_Test`, NEW `MotionMovesThrows*_Test` |
| **ui** | `CL.FrontEnd`, `CL.LobbyUI`, `CL.FighterSelect`, `CL.StationBoards`, `CL.Leaderboard`, `CL.CreditsScreen`, `CL.MoveList`, `CL.UIHelpers`, `CL.UIState`, `CL.SelectScene`, `CL.ArcadeMode`, `CL.HudController`, tests `UIFrontend_Test`, `SelectScene_Test`, `CreditsScreen_Test`, `LobbyUI_Test`, NEW `UI*_Test`, `Hud*_Test` |
| **world** | `ServerScriptService.FightingLabWorldBoot`, `ServerStorage.FightingLab.World.*`, `CL.LobbyAmbience`, `CL.LightingProfile`, `World_Test` |
| **characters** (phase 2) | `ServerStorage.FightingLab.CharacterFactory`, `ServerStorage.FightingLab.CharacterSpecs` (generated from `OV6\handoff\characters\*.json` with `tools\json_to_luau.py`), `ServerScriptService.FightingLabCharacterBoot`, `CharacterLook_Test` |
| **integrator** | everything else: `FightingLabServer`, `ServerStorage.FightingLab.Duel.*`, `CL.FightSession`, `CL.AvatarGate`, `CL.SpectatorPresenter`, `CL.StageController`, client bootstrap `StarterPlayer.StarterPlayerScripts.FightingLabClient`, `RF.Credits`, `ClientModules_Test`, `Duel_Test`, `DuelAppearance_Test`, `FightSession_Test`, `World`-independent glue |

`ClientModules_Test` lists client module APIs; if you add/rename client module functions, REQUEST the entry.

## 6. Reporting

When done (or blocked) reply with: what you built (files), how it works, test summary line, evidence paths you
looked at (one-line verdict each), numbers that prove the acceptance targets you own, known issues, and REQUESTs.
Keep exports current in `OV6\handoff\<agent>-src\` and a short `OV6\handoff\<agent>.md`.

## 7. Surge and the Ultimate (round 6; owner: combat — `RF.CombatSim`, `RF.CombatConfig`, `RF.Roster`)

Binding for every workstream (round 6 brief, Contract A), as implemented on `r6-combat`. Original system; genre
convention only.

**Rules (sim).**
- `CombatConfig.SurgeThreshold = 0.25`, `SurgeDamageMultiplier = 1.1`, `UltComboScale = 0.7`.
- A fighter enters **Surge** on the first frame of a round its health is ≤ 25 % of its maximum and above 0 (event
  `{ kind = "Surge", attacker = i, target = i }`). Surge lasts until the round ends or the fighter starts its
  Ultimate; it adds 10 % to the damage the fighter deals.
- Every `CharacterDef` has `moves.Ultimate` (key `"Ultimate"`, last in `moveOrder`, input `"LP+RP"`, notation
  `"1+2"`, an original `name`): i18-22, armored through its startup against every strike (throws beat it; parries
  and the Bear Trap catch never stop it), 3 active frames, -15 on block (launch punishable), Mid, Heavy, `damage` 30-36
  spread over `cinematic = { duration, impacts = { { frame, share } }, endKind, endDistance, beats }` (shares sum to 1,
  4-6 impacts, 190-260 frames, `endDistance` 4.4-4.6 studs). Per-fighter timelines and beats: `movesets.md`.
- It can start once per round, only in Surge (`ultUsed` afterwards). Its first frame ends Surge and emits
  `{ kind = "UltStart", attacker = i, target = 3 - i, move = "Ultimate" }`.
- **On hit** (not blocked) both fighters enter state `"Ultimate"` for `cinematic.duration` frames; positions are locked
  with the defender `endDistance` studs in front of the attacker (the pair slides inward inside the arena). Damage
  lands at each impact: `{ kind = "UltHit", attacker, target, move = "Ultimate", damage, combo = <impact 1..n>,
  knockdown = true on the last }`, share × damage × scaling (× 0.7 when the defender was already in a combo or
  juggle; the parts add up exactly). The round clock waits. A KO is declared at the end of the cinematic (a `KO`
  event with `move = "Ultimate"`); otherwise the defender lies in `Landing` with `knockdown = endKind` and the
  attacker is `Idle`. **On block or whiff**: the normal `Block` / `Whiff` with `move = "Ultimate"` and its recovery.
  In every case the Ultimate is used for the round.
- **Free Training** (practice with the dummy on Stand or Guard): the player is always in Surge (no damage bonus, no
  `Surge` event) and the Ultimate is available again as soon as it ends. Versus CPU practice (dummy Fight) and real
  matches use the normal rule.

**Snapshot (codec v3, additive).** Fighter flag bit 32 = `surge`, bit 64 = `ultUsed` (bit 128 = `tumble`). During the
cinematic both fighters carry `throw = { archetype = "ultimate", move = "Ultimate", role = "Attacker" | "Defender",
frame = <cinematic frame>, duration, impactFrame = <first impact> }`. Client frames (RenderBuffer / MatchRunner
entries) expose `surge`, `ultUsed`, state `"Ultimate"` and that table; absent fields read as false / nil. Hit events
may carry `punish = true` (event flag bit 128): the hit landed on an opponent recovering from its own move or
staggered after a parry (integrator request, for a HUD call-out).

**Input.** `Controls.fight.keyboard.ultimate = "L"` (sends the Ultimate button), U+I pressed together (within 1
frame) also works; `Controls.fight.gamepad.ultimate = "ButtonR2"`; `Controls.notation.ultimate = "1+2"`; action text
"Ultimate (1+2)". A typed 1,2 is still the string; 1+2 is only the Ultimate while it is ready.

**CPU.** Easy almost never uses it (0 in 94 CPU-vs-CPU rounds), Normal as a juggle ender or a comeback gamble under
pressure, Hard as a juggle / combo-route ender and an armored answer to a seen attack, and Hard throws an
opponent's Ultimate startup (combat-balance.md R6.3).

**Presentation (motion, look; unchanged from the brief).** motion: freeze, flash and push-in on `UltStart`, a
cinematic camera and a two-role clip per fighter fitted to the impact frames, impact VFX/sound per `UltHit`, a Surge
aura on `surge = true` and a burst on `Surge`. look: HUD Surge glow + "SURGE" tag, an "ULTIMATE" ready indicator
(`surge and not ultUsed`) with the key label from Controls, an `UltStart` banner with the fighter's name and
`Roster.get(id).moves.Ultimate.name`. Everything must work when the fields are absent.
