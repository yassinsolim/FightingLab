# ui.md — OV6 UI handoff (lobby menu, fighter select, prompts, controls guide, practice lesson, fight HUD, boards)

Owner: ui. Exports: `OV6\handoff\ui-src\` (18 files, UTF-8, LF, no BOM, baseline file names). Evidence:
`OV6\work\ui\shots\` (captures at 1919x1080, 1365x768 and iPhone 14 749x389).

## Files

| file | what |
|---|---|
| `Client.UIHelpers` | legacy helpers kept + the UI kit: Theme (original palette "ember/gold/cool" on ink, Montserrat Heavy Italic display), Controls access (`controls()`, `keyLabel`, `keyCodes`, `keyMatches`, `legend`, `actionText`, `legendOptions`, `notationOf`, `notationTokens`, `notationText`, `formatMoveInput`; `_setControlsForTests`), glyphs (key caps / gamepad face buttons / pills / arrows), buttons, segment bars, `edgeCard`, `fitToScreen`, `holdPlayerList`, `attributes` (cast-relative select bars) |
| `Client.UIState` | pure models: lobby view (incl. the Quick Duel `Searching` mode), E-prompt specs, pickers (cpu / training / versus), practice lesson (10 steps), PLAY panel (`playRows`, `playNav`, `playRequest`, `playDefaultFocus`) |
| `Client.LobbyUI` | lobby HUD, bottom action bar (FIGHTERS · PLAY · MENU), PLAY panel, quick-travel fade, pickers, countdown, result card, toasts, practice panel, lesson card, Tab menu (Fighters / How to Play / Move List / Settings / Credits), fighter-select host, practice keys T / 1-3 / Backspace |
| `Client.LobbyPrompts` | (round 5, split out of LobbyUI) custom E-prompt style and the world prompt set (kiosk + pads); re-exported as `LobbyUI.PromptStyle` / `LobbyUI.worldPrompts` |
| `Client.LobbySprint` | (round 5) lobby-only sprint controller and its Controls bindings |
| `Client.FlashDetector` | (round 5) bare-frame / pose-pop detector: the reveal check every preview gate uses and the live QA recorder |
| `Client.FighterSelect` + `Client.SelectScene` | cinematic select: camera flies into the kiosk screen, cuts to a local showcase studio; pooled dressed rigs in their stance (`acquirePreview`/`posePreview`), light-cut switching, LOCKED IN confirm |
| `Client.MoveList` | numeric notation rows (1-4 + arrows), generated descriptions, height/property chips |
| `Client.HudController` | fight HUD: bars + damage trail, portraits, names/tags, diamond round pips, clock, combo counter, call-outs, banners, controls guide (G) |
| `Client.StationBoards`, `Client.Leaderboard`, `Client.CreditsScreen` | restyled boards; credits "MOTION CAPTURE & ADDITIONAL CREDITS" section (wrapping rows, licence + used-for line) |
| `Client.FrontEnd` | `start()` / `onSnapshot(entry)` / Studio-only DevMock (scenes for every screen, used for captures) |
| tests | `LobbyUI_Test`, `UIFrontend_Test`, `UIPrompts_Test`, `UIControls_Test`, `UITutorial_Test`, `HudController_Test`, `CreditsScreen_Test`, `FlashDetector_Test` |

## Controls (contract §2)

Every key/button shown comes from `RF.Controls` (`label`, `keyCode(s)`, `legend`, `formatMoveInput`, `notationOf`);
`UIHelpers.controls()` falls back to the §2 table only if the module is missing (never in the integrated build).
Lobby: every interaction is an `E` (gamepad X) ProximityPrompt with a custom billboard — kiosk "Choose Fighter",
duel pad "Fight CPU" (after `UIState.CPU_OFFER_DELAY` = 3.2 s alone), dojo "Start Training" / "Versus CPU". Round 5
brought back two lobby keys, now owned by the bottom action bar: `Controls.lobby` play F (gamepad RB) and fighters C
(LB), plus sprint LeftShift (L3); 1-3 stay practice-only. Menu: Tab (gamepad Y / Select in the lobby; in practice only Tab and the panel's
Menu button, so Y stays "2"). Practice keys: LobbyUI handles T, 1/2/3, Backspace; InputController handles R, Y, P,
Start and G. Panel buttons call `ctx.modules.Input.practice("Reset" | "Dummy" | "Pause", arg)`; the dummy chips show
`entry.dummy` (verified live: click Guard → Guard; Y cycles Guard → Fight → Stand → Guard and the chips follow).

**Practice labels cannot drift:** the practice panel and the How to Play "Practice dojo" card are generated from
`Controls.legend("practice", device)`: row order, key caps (`Controls.label`) and captions (the legend text, i.e.
`Controls.actionText`). "Prefix: a / b / c" texts become chip rows (Dummy: STAND / GUARD / FIGHT BACK), "a / b" the mode
switch (TRAINING / VERSUS CPU, also the header chip), rows sharing a first word collapse ("CPU Easy / Normal / Hard"); an
action the panel does not know is still listed as a key hint. The gamepad tab lists only gamepad-bound rows (START
pause). `UIControls_Test` renders both against a fake, rebound and renamed Controls (F/M/7/8/9/Q/L/DEL, "Partner: idle /
block / attack"...) and checks the new keys/texts appear, the old ones (R, T, 1-3, Y, P, BACKSPACE, "SPAR") do not, and
`handleKey` follows the rebinding. The ui exports never contained "K sparring" (that text is in the baseline LobbyUI /
UIState / StationBoards only).

## Practice panel: folds while you fight (round 2)

The practice panel sits top-right under the fight HUD (no longer mid-right over the fighters) and has two states:

- **Strip (folded)**: one line, about 300x38 design px: the Training / Versus CPU chip (legend `switchMode` texts), the dummy
  mode in Training (`DUMMY  GUARD` from the `dummy` legend text, following `entry.dummy`), and the key that opens the
  panel: `Controls.label("practice", "pause")` (P / START) plus the `actionText("pause")` caption and a ▼ chevron. A level
  key (1/2/3) while folded briefly flashes `CPU  HARD` in the strip instead of opening the panel; T / Y changes pulse it.
- **Full panel**: shown on entering practice (keyboard / gamepad) for `LobbyUI.PANEL_START_SECONDS` = 6 s, and as a
  **pause menu** whenever the session is paused (P / START through InputController, the panel's PAUSE row, or a click /
  tap on the strip, which sends `Pause true`). Resuming folds it; the header's ▲ button folds it and resumes.
- **Folds** on any fight input while not paused: a key of any `Controls` fight action (`handleKey`, processed or not),
  or the local fighter acting in a snapshot (`move` set or Walk / Backwalk / Crouch / Dash / Backdash / Sidestep /
  Startup / Active / Recovery), which covers the touch buttons; or after `LobbyUI.PANEL_IDLE_SECONDS` = 4 s without
  use (clicks, practice keys and `entry.dummy` changes count as use; the mouse resting on the panel keeps it open).
- **Touch**: starts folded (the open panel would sit over the touch fight buttons); a tap on the strip pauses and opens.
- No new Controls action was needed: pause is the open key. How to Play's practice card says so (from `actionText`).
- API: `panelOpen()`, `setPanelOpen(open)`, `togglePanel()`; `env.clock` injects time for tests. `LobbyUI_Test`
  "practice panel folds into a strip while fighting..." covers start, idle fold, strip texts / key, `entry.dummy`,
  pause open + no fold while paused, resume fold, strip toggle (`Pause true/false`), use keeps it open, fight key fold,
  snapshot fold (own fighter only), Versus level flash, touch start + tap; `UIControls_Test` checks the strip against
  the remapped / renamed fake Controls.
Round 2 evidence (`OV6\work\ui\shots\v8-*`): `v8-practice-open-start-1080` (first look), `v8-strip-training-1080-0*`
(strip while fighting, DUMMY FIGHT BACK), `v8-strip-versus-1080-0*` (strip in a CPU match), `v8-practice-paused-open-1080`
(P = pause menu), `v8-strip-768` / `v8-paused-open-768`, `v8-strip-phone` / `v8-paused-open-phone` (tap on the strip).

**Other round-2 changes.** `UIHelpers.attributes` REACH now ranks `stats.preferredRange` (designer spacing; fallback: longest
threat range `range + advance`), so the step-in Roster no longer makes the grappler look long-ranged (combat REQUEST 8;
test added). The lesson's throw-break step (`reset = true`) restarts from neutral spacing once: after the throw step the
fighting dummy could sit in a crouch and never grab with the new CombatAI, which `UITutorial_Test` caught for all six.
## Practice lesson

10 steps (walk, dash, backdash, sidestep in+out, standing guard, crouch guard, the fighter's string, a launcher,
a throw, a throw escape), each sets the dummy (`Stand` / `Fight` / `Guard`) and ticks from snapshot states/events
(`Walk/Backwalk`, `Dash`, `Backdash`, `Sidestep.stepDir`, `Block` (height), `guard == "Crouch"`, `move`, `Hit.launch`,
`ThrowHit/ThrowStart`, `ThrowBreak` with attacker ≠ me). The string is "1,2" when the fighter has it, else the first
plain button string; the launcher text shows the real keys (`formatMoveInput`, e.g. "S+D+I"). `UITutorial_Test`
plays the whole lesson for all six fighters against the real MatchRunner/CombatSim/CPU dummy: all 10 steps complete.

## Station boards (world REQUEST)

During the local player's fight/practice the own arena's StatusGui and **every** arena's floating pad tags are hidden
(physical boards of other arenas stay live); pad tags use MaxDistance 100 (readable from anywhere in the plaza).

## Round 5 — the lobby made easy (PLAY bar, quick play, sprint, travel, no bare frames)

Owner: lobbyux (branch `r5-lobbyux`). Evidence: `OV6\handoff\ui-shots\round5\`.

**Before → after.** Before, every fight started with a walk: from the plaza spawn 2.9 s to the nearest duel circle
(Midnight Rooftop P1, 44 studs at 16 studs/s) and 5.0 s to the farthest (Snow Summit P2), measured with Studio's
navigation; a CPU was offered only after `CPU_OFFER_DELAY` = 3.2 s alone on the circle, then E + Enter (0.8 s): about
7 s from spawn at best, and you had to know where to go. Now: PLAY → NORMAL is two clicks / presses from anywhere in the
lobby; measured click → `DuelState` Fighting **0.27 s**, picture back from the fade 0.9–1.3 s; PLAY → FREE TRAINING Enter →
Practice 0.22 s; Quick Duel with a waiting opponent: click → Matched 0.07 s → on circle P2 + countdown 0.28 s → fight
3.3 s (the 3 s countdown). Bare frames on the round-4 rigs: **53 bare frames + 1 pose pop → 0 + 0** (FlashDetector, see
below).

**Bottom action bar** (`Stage.ActionBar`): FIGHTERS · **PLAY** · MENU, each with its `Controls.lobby` glyph (keyboard
C · F · Tab; gamepad LB · RB · Y/Select; touch: no glyphs, tap). Shown in the lobby modes only (hidden in countdowns,
fights, results and practice) and behind every overlay; the old top-left MENU button is gone. While Quick Duel searches
the PLAY button is the queue clock (`SEARCHING 0:12`). First-time hint over PLAY ("Press PLAY to fight [F]" / "Tap PLAY to
fight"), in place of the objective pill, until PLAY has been opened once. The objective pill sits above the bar and
reads "PRESS PLAY TO FIGHT"; while searching it shows SEARCHING + clock with CANCEL, and FIGHT CPU after
`NetProtocol.QuickCpuOfferSeconds` = 12 s. Touch: a SPRINT toggle above the jump button.

**PLAY panel** (ScreenGui `FightingLabPlay`, DisplayOrder 35; pure model `UIState.playRows/playNav/playRequest/
playDefaultFocus`): VERSUS A PLAYER (QUICK DUEL; while searching FIGHT CPU INSTEAD + CANCEL SEARCH), FIGHT CPU (Easy /
Normal / Hard), PRACTICE (Free training / Guided lesson / Versus CPU), GO TO (every arena from the Stations folder in
`Order`, then PLAZA; three per line so every name fits). Every action is two steps (open PLAY, pick). Input: click /
tap; arrows, WASD, DPad or left stick move the focus; Enter / A picks; Backspace / B or the PLAY key closes; the menu key
switches to the menu and the FIGHTERS key to the select. A pick closes the panel and is debounced
(`LobbyUI.PLAY_PENDING_SECONDS` = 1.2 s). Greyed out: Fight CPU while every arena is busy (`FreeArenas` 0, "All arenas
busy"), Quick Duel while you already wait on a circle. A guided lesson starts once the practice session begins.

**Protocol** (`NetProtocol`, validated in `parseLobby`, served by `DuelService`):

| Lobby kind | payload | server |
|---|---|---|
| `QuickPlay` | `mode` Duel / Cpu / Practice, `difficulty`, `practice` Training / Cpu, `opponent` | Duel: join the matchmaking queue (`QuickQueue` = server time the search began, `QuickStatus` Searching / Busy / Matched). Cpu: a free duel arena is reserved, you are moved onto `PadP1` and the CPU match starts at once (already alone on a circle: the CPU joins there). Practice: moved onto the dojo pad, practice starts. Rejected: `TooFast`, `Busy`, `OnCircle` (Duel while on a circle), `ArenasBusy` (Cpu), `NoDojo` |
| `CancelQueue` | — | leaves the queue |
| `Travel` | `to` = ArenaId or `"Plaza"` | moved to the arena's `Arrival` point (`WorldIndex.arrivalFrame`; fallback 6 studs behind `PadP1` / `PadTraining`, facing the ring) or a plaza spawn. Rejected: `TooFast`, `Busy`, `NoArena` |

Duel kind `Teleport {reason, arenaId, delay}` warns the client (`FightSession.Teleport`) `TeleportDelay` = 0.2 s before
the server pivots the character (`AvatarService.teleport`: zero velocity + place; still dressing → spawn there; dead →
respawn there); LobbyUI fades to black (`FightingLabTravelFade`), back once the character moved, and for CPU / practice
starts 0.5 s after the fight camera took over. Matchmaking runs at `PadPollHz`: a searcher is first sent to a player
waiting alone on a duel circle, then searchers pair two by two into free arenas (in `Order`); a station is `reserved`
while players are on their way (walk-ins wait) and the pad poll ignores a moved player for `TravelGraceSeconds` = 1.5 s.
Standing on circles works exactly as before (same `claimPad` / countdown / CPU offer). Edge cases (Duel_Test): all arenas
busy → searchers stay queued with `Busy`, CPU rejected; a player leaving mid-queue or before the move → the other one
goes back to the front of the queue; changing fighter while queued keeps the queue (matched once the new avatar is
dressed); spam → `QuickPlayCooldown` 0.6 s / `TravelCooldown` 1 s server-side plus the client debounce. Stations attributes
`QuickSearching`, `FreeArenas`; station attribute `Order`. Studio debug hook: `quickStub(mode?, fighterId?, name?)` (a
stub player sends QuickPlay) and `quickState()`.

**Sprint** (`Client.LobbySprint`): walk 16 → 28 studs/s, smoothstep over 0.35 s (0.25 s back), camera FOV +6. Keyboard:
hold LeftShift (`Controls.lobby.keyboard.sprint`); gamepad: press L3 (toggle, off 0.6 s after you stop); touch: the SPRINT
toggle (waits up to 4 s for your first step). Lobby only: never in countdowns, fights, practice or while an overlay is
open; teleports and overlays stop it at once (the fighter select never captures a widened FOV). It only undoes its own
WalkSpeed / FOV writes. Moving = `MoveDirection` or a horizontal root speed above 4 studs/s (tap-to-move). The server
turns off `Player.DevEnableMouseLock` (Shift lock would take LeftShift). Measured: `r5-sprint-numbers.txt`.

**FIGHTERS anywhere**: the bar button / key opens the showcase fighter select wherever you are in the lobby (also from the
PLAY panel and the menu's Fighters page, which now says so); the kiosk prompt still works.

**Legacy main menu deleted**: `Client.ArcadeMode` and the title / arcade / versus state machine (`UIHelpers.MenuState`,
`menuReduce`, `initialMenuState`, `isValidPauseCommand`, `characterIndexToId`, `stageIndexToId`, `makeProtocol`;
`UIState.State`, `initial`, `reduce`, `validPause`) with their tests. `SelectScene` stays (FighterSelect uses it).
`ClientModules_Test` checks ArcadeMode is gone. LobbyUI had grown past Roblox's 200,000-character `Source` limit (setting
`Source` from Studio plugins / MCP fails above it), so the prompt style and world prompts moved to `Client.LobbyPrompts`
(LobbyUI is now ~191 KB: new UI should go into its own module).

**No naked or spazzing models** (`Client.FlashDetector`). A watched model is *bare* on a frame when it is visible but
incomplete: fewer accessories, wrap layers, rigid welded extras (`FightingLabExtra`: gloves, shoes, belts) or clothing than
its template, a mesh (incl. layered-clothing cages) not fetched, or a texture mid-fetch; a *pose pop* is a Motor6D turning
more than 30° between two visible frames. The live recorder watches every PlayerGui viewport (an opaque `Cover` sibling
counts as hidden), the select's pooled rigs on screen and every character, after all render steps, and treats a black
fade as hidden. What it found and how it was fixed:

| case | before | fix |
|---|---|---|
| fighter-select tiles | 25 bare frames (Lumi / Rhys hair still loading when the fixed warm-up ended) | opaque covers; revealed by `FighterSelect.gatePreview` → `AvatarGate.trackPreview` (template inventory + assets + 0.25 s settle) |
| select stage rigs | 25 bare frames | same gate before a rig is shown; pose changes blend over 0.22 s (the Lumi Stance → Intro pop) |
| lobby avatar on a fighter change | 3 bare frames (Goran beard texture) | AvatarGate waits for `ExtraCount` (published by AvatarService before `AccessoryCount`) and `FlashDetector.check` after the preload |
| identity portrait | fixed 0.6 s | gated like the tiles |
| fight HUD portraits | — | expected counts include the rigid extras |
| W / S / Up / Down in the select | did nothing | browse like A / D |

Two traps the detector also caught: a `PreloadAsync` of mesh id *strings* reports Failure in Studio and overwrote the
MeshParts' Success, and re-preloading finished ids flips them back to Loading (149 bare frames in the first after-run).
Gates now preload the instances plus only unfinished texture ids, and the detector's fetch status is sticky once
resolved. Pickers and result cards draw monogram tiles (no 3D model). Final run (`r5-flashdetector-report.txt`): 36,298
frames, 88,473 visible model frames, 0 bare, 0 pops, 0 failed assets — select opened with C and browsed with W/S/A/D,
arrows, Q/E, DPad, LB/RB and mouse clicks on four tiles, confirm, six lobby fighter changes, menu Fighters page, a CPU fight
(HUD portraits) and dojo pickers. Studio's VirtualInput cannot send DPadUp (core-bound key); the other inputs were real.
`FlashDetector_Test` runs the detector on fake models and on the real FighterSelect tiles (an uncovered loading clone is
caught as a bare frame, the gated tiles give 0).

**Tests (round 5)**: `LobbyUI_Test` (action bar, PLAY panel, Quick Duel queue, sprint incl. the touch arm), `Duel_Test`
(pairing, searcher → waiter, Fight CPU, Practice, travel, edge cases, PLAY on a circle), `DuelProtocol_Test`,
`DuelAppearance_Test` (ExtraCount, teleport), `FightSession_Test` (Teleport, quickPlay / cancelQueue / travel),
`Controls_Test`, `UIControls_Test` (How to Play LOBBY card), `UIFrontend_Test` (legacy deleted), `ClientModules_Test`
(new APIs, ArcadeMode gone), `FlashDetector_Test` (6).

## Tests

Round 5 (r5-lobbyux, Studio Play, every committed source identical to the tested place):
`[SUMMARY] 419 run, 419 passed, 0 failed` (main before round 5: 399).
Round 2: UI suites 67 run, 67 passed (LobbyUI 23 incl. the new fold/expand test, UIFrontend 11, UIPrompts 3, UIControls 9,
UITutorial 12, HudController 5, CreditsScreen 4). Full suite with every current export synced (combat-src incl. the
step-in Roster, integrator-src, characters-src, motioncore-src, motionstrikes-src, motionthrows-src, world-src):
`[SUMMARY] 341 run, 341 passed, 0 failed`.
Baseline modules only: `[SUMMARY] 247 run, 247 passed, 0 failed`.

## REQUESTs

1. integrator — `ClientModules_Test`: add `HudController` API `toggleGuide, setGuide, guideVisible, guideMode`, and
   `LobbyUI` `worldPrompts, richKeys`; `UIHelpers.holdPlayerList`.
2. ~~integrator — `CL.FightSession`: `Dummy` in `PRACTICE_COMMANDS`~~ done in integrator-src.
3. integrator — bootstrap: keep calling `FrontEnd.onSnapshot(entry)` for every entry (practice and fights).
4. integrator — `Credits.external`: real entries (stubbed locally from `credits-external.json` for the screenshot).
5. integrator (round 5) — delete `ReplicatedStorage.FightingLab.Client.ArcadeMode` from the place (apply_sources never
   deletes scripts) and regenerate `src/export-manifest.json` / `src/_classes.json` (they still list ArcadeMode; new
   ModuleScripts: `Client.FlashDetector`, `Client.LobbySprint`, `Client.LobbyPrompts`, `UnitTest.Cases.FlashDetector_Test`).
6. world (round 5) — an `Arrival` BasePart in every arena (anchored, CanCollide off, invisible; its front face looks at the
   ring) where quick travel lands; today every arena uses the fallback 6 studs behind `PadP1` / `PadTraining`.
7. all (round 5) — `Client.LobbyUI` is ~191 KB, close to the 200,000-character `Source` limit that plugins, MCP edits and
   live syncs hit: put new lobby UI in its own module.
