# ui.md — OV6 UI handoff (lobby menu, fighter select, prompts, controls guide, practice lesson, fight HUD, boards)

Owner: ui. Exports: `OV6\handoff\ui-src\` (18 files, UTF-8, LF, no BOM, baseline file names). Evidence:
`OV6\work\ui\shots\` (captures at 1919x1080, 1365x768 and iPhone 14 749x389).

## Files

| file | what |
|---|---|
| `Client.UIHelpers` | legacy helpers kept + the UI kit: Theme (original palette "ember/gold/cool" on ink, Montserrat Heavy Italic display), Controls access (`controls()`, `keyLabel`, `keyCodes`, `keyMatches`, `legend`, `actionText`, `legendOptions`, `notationOf`, `notationTokens`, `notationText`, `formatMoveInput`; `_setControlsForTests`), glyphs (key caps / gamepad face buttons / pills / arrows), buttons, segment bars, `edgeCard`, `fitToScreen`, `holdPlayerList`, `attributes` (cast-relative select bars) |
| `Client.UIState` | pure models: lobby view, E-prompt specs, pickers (cpu / training / versus), practice lesson (10 steps) |
| `Client.LobbyUI` | lobby HUD, custom E prompts (kiosk + pads), pickers, countdown, result card, toasts, practice panel, lesson card, Tab menu (Fighters / How to Play / Move List / Settings / Credits), fighter-select host, practice keys T / 1-3 / Backspace |
| `Client.FighterSelect` + `Client.SelectScene` | cinematic select: camera flies into the kiosk screen, cuts to a local showcase studio; pooled dressed rigs in their stance (`acquirePreview`/`posePreview`), light-cut switching, LOCKED IN confirm |
| `Client.MoveList` | numeric notation rows (1-4 + arrows), generated descriptions, height/property chips |
| `Client.HudController` | fight HUD: bars + damage trail, portraits, names/tags, diamond round pips, clock, combo counter, call-outs, banners, controls guide (G) |
| `Client.StationBoards`, `Client.Leaderboard`, `Client.CreditsScreen` | restyled boards; credits "MOTION CAPTURE & ADDITIONAL CREDITS" section (wrapping rows, licence + used-for line) |
| `Client.FrontEnd` | `start()` / `onSnapshot(entry)` / Studio-only DevMock (scenes for every screen, used for captures) |
| tests | `LobbyUI_Test`, `UIFrontend_Test`, `UIPrompts_Test`, `UIControls_Test`, `UITutorial_Test`, `HudController_Test`, `CreditsScreen_Test` |

## Controls (contract §2)

Every key/button shown comes from `RF.Controls` (`label`, `keyCode(s)`, `legend`, `formatMoveInput`, `notationOf`);
`UIHelpers.controls()` falls back to the §2 table only if the module is missing (never in the integrated build).
Lobby: every interaction is an `E` (gamepad X) ProximityPrompt with a custom billboard — kiosk "Choose Fighter",
duel pad "Fight CPU" (after `UIState.CPU_OFFER_DELAY` = 3.2 s alone), dojo "Start Training" / "Versus CPU". The old
lobby hotkeys C, F, 1-3 are gone. Menu: Tab (gamepad Y / Select in the lobby; in practice only Tab and the panel's
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

## Tests

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
