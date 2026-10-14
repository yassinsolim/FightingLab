# ui.md — OV6 UI handoff (lobby menu, fighter select, prompts, controls guide, practice lesson, fight HUD, boards)

Owner: ui. Exports: `OV6\handoff\ui-src\` (18 files, UTF-8, LF, no BOM, baseline file names). Evidence:
`OV6\work\ui\shots\` (captures at 1919x1080, 1365x768 and iPhone 14 749x389).

## Files

| file | what |
|---|---|
| `Client.UIHelpers` | legacy helpers kept + the UI kit: Theme (original palette "ember/gold/cool" on ink, Montserrat Heavy Italic display), Controls access (`controls()`, `keyLabel`, `keyCodes`, `keyMatches`, `legend`, `actionText`, `legendOptions`, `notationOf`, `notationTokens`, `notationText`, `formatMoveInput`; `_setControlsForTests`), glyphs (key caps / gamepad face buttons / pills / arrows), buttons, segment bars, `edgeCard`, `fitToScreen`, `holdPlayerList`, `attributes` (cast-relative select bars) |
| `Client.UIState` | pure models: lobby view (incl. the Quick Duel `Searching` mode), E-prompt specs, pickers (cpu / training / versus), practice lesson (10 steps); round 7: `offerDelay` (the PLAY panel model moved to `Client.PlayFlow`) |
| `Client.LobbyUI` | lobby HUD, bottom action bar (FIGHTERS · PLAY · MENU), quick-travel fade, pickers, countdown, result card, toasts, practice panel, lesson card, Tab menu (Fighters / How to Play / Move List / Settings / Credits), fighter-select host, practice keys T / 1-3 / Backspace; hosts `PlayFlow` and `PracticeTools` |
| `Client.PlayFlow` | (round 7) the PLAY flow: one decision per screen (who → map with a live camera preview → FIGHT!), pure step model + view |
| `Client.PracticeTools` | (round 7) input display, frame advantage readout, combo trials (Contract C) with SHOW ME |
| `Client.LobbyPrompts` | (round 5, split out of LobbyUI) custom E-prompt style and the world prompt set (kiosk + pads); re-exported as `LobbyUI.PromptStyle` / `LobbyUI.worldPrompts` |
| `Client.LobbySprint` | (round 5) lobby-only sprint controller and its Controls bindings |
| `Client.FlashDetector` | (round 5) bare-frame / pose-pop detector: the reveal check every preview gate uses and the live QA recorder |
| `Client.FighterSelect` + `Client.SelectScene` | cinematic select: camera flies into the kiosk screen, cuts to a local showcase studio; pooled dressed rigs in their stance (`acquirePreview`/`posePreview`), light-cut switching, LOCKED IN confirm |
| `Client.MoveList` | numeric notation rows (1-4 + arrows), generated descriptions, height/property chips |
| `Client.HudController` | fight HUD: bars + damage trail, portraits, names/tags, diamond round pips, clock, combo counter, call-outs, banners, controls guide (G) |
| `Client.StationBoards`, `Client.Leaderboard`, `Client.CreditsScreen` | restyled boards; credits "MOTION CAPTURE & ADDITIONAL CREDITS" section (wrapping rows, licence + used-for line) |
| `Client.FrontEnd` | `start()` / `onSnapshot(entry)` / Studio-only DevMock (scenes for every screen, used for captures) |
| tests | `LobbyUI_Test`, `UIFrontend_Test`, `UIPrompts_Test`, `UIControls_Test`, `UITutorial_Test`, `HudController_Test`, `CreditsScreen_Test`, `FlashDetector_Test`, `PlayFlow_Test`, `PracticeTools_Test` |

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

**PLAY panel** (round 5; replaced in round 7 by the PLAY flow, see "Round 7" below) (ScreenGui `FightingLabPlay`, DisplayOrder 35; pure model `UIState.playRows/playNav/playRequest/
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

## Round 6 (look): premium fight HUD, Surge and the Ultimate (Contract A), fighter select, one theme

Round 6 adds two modules and rewrites the HUD controller:

| file | what |
|---|---|
| `Client.HudKit` (new) | angled shapes: slanted caps, slabs, chips; the health bar (fill, recoverable-damage trail, halo, glow, sheen, low-health pulse, ticks); `stepTrail`; `fillColors` |
| `Client.HudBanners` (new) | round intro / end texts, the centre banner, flash, cinematic letterbox, Ultimate title card, winner card |
| `Client.HudController` | rewritten on top of the two modules; same public API plus `ultimateKey`, `statusFor`, `stanceName` |

### Fight HUD

**Health bars**
- Angled bars, 500 px each so they fit a phone. Each bar has slanted caps, ticks every 10 %, a sheen and a
  low-health pulse.
- Recoverable-damage trail: the lost health stays white for a beat, then drains (`HudKit.stepTrail`).

**Fighter cards**
- A slanted portrait card in the fighter's colour.
- The name, the YOU / CPU / DUMMY tag and the player name.
- Diamond round markers.

**Timer plate:** the clock with ROUND n under it.

**Combo counter:** hits, damage and the kind of combo (COMBO, ULTIMATE, ...).

**Call-outs:** COUNTER HIT, PUNISH, LAUNCH, THROW, THROW ESCAPE, PARRY, ARMOR, CRUSH, EVADE, KNOCKDOWN.
- PUNISH fires on the first hit (combo ? 1) against a target that was in Recovery in the last snapshot before the
  hit's frame. The HUD keeps a history of 40 snapshots for this. An event field `punish` also works.

**Round flow**
- ROUND n, or FINAL ROUND, holds through the whole Ready phase. FIGHT replaces it. It is a state, not only an edge:
  if anything clears the centre during Ready (the first Ready runs while the fight is set up), it comes back.
- Round end: K.O., DOUBLE K.O., TIME or DRAW. A winner at full health gets PERFECT after the K.O.
- Winner card: VICTORY, DEFEAT, `<NAME> WINS` or DRAW, over the fighter, the player and the score.

**Readability:** checked at 1920 x 1080 and in an 844 x 390 viewport, the size of an iPhone 14 in landscape (Studio window, keyboard device).

**Contract A.** The HUD reads `entry.fighters[i].surge / ultUsed / state / throw / stance` and the `Surge`, `UltStart`
and `UltHit` events. When the fields are absent, nothing extra shows and nothing errors (tested).
- **Surge:** the bar turns red with a pulsing halo and a SURGE chip.
- **Ultimate ready** (in Surge and `ultUsed` false): an ULTIMATE chip with its key from Controls.
  - keyboard L, gamepad RT;
  - the notation "1+2" when Controls has no binding;
  - no key on touch.
- **UltStart** shows a title card:
  - the fighter's name, and the Ultimate's name from `Roster.get(id).moves.Ultimate.name` in upper case;
  - "ULTIMATE" when the roster has no name;
  - a tab in the fighter's colour with the monogram, an accent streak and glow across the screen, and a small
    ULTIMATE tag (hidden when the name already falls back to ULTIMATE);
  - it slides off at the cinematic's first impact (`HudBanners.dismissUltimate`, after at least
    `ULT_TITLE_MIN_SECONDS` = 0.9 s so the name reads), or after `ULT_TITLE_SECONDS` = 2.1 s when the Ultimate is
    blocked or whiffs, so it never covers the action (it used to cover the defender at Goran's suplex landing).
- **Letterbox:** black bars while a fighter is in state `"Ultimate"`. The HUD bars stay above them, and the controls
  guide steps aside.
- **UltHit:** the impacts count on the attacker's combo counter with their damage, kind ULTIMATE.
- **Stance chip:** POCKET, SOUTHPAW, AERIAL, STILL WATER or COIL while a fighter is in state `"Stance"`.

**Checked with real data** (r6-combat merged, Free Training, Kael):
1. The HUD shows SURGE and [L] ULTIMATE.
2. L starts the FINAL BELL card and the letterbox.
3. The counter reads 1 ? 3 ? 4 ? 5 HITS, 3 ? 32 DAMAGE, ULTIMATE.
4. Sierra goes down; Surge and the Ultimate come back (Free Training refills them).

A real CPU fight with the `forceKo` hook showed FIGHT, K.O., PERFECT, ROUND 2 and VICTORY "KAEL WINS 2 ? 0".

**Controls guide and How to Play**
- The HUD guide is driven by the legend, so it shows the new `stance` (J+K) and `ultimate` (L) rows.
- How to Play's ATTACK card adds a line for each of those rows, only when Controls lists them.

### Fighter select (`FighterSelect`, `SelectScene`)

**Layout**
- A SELECT YOUR FIGHTER header over a slanted ember rule, with the roster position ("03 / 06").
- A big name.
- The fighting style on a slanted chip in the fighter's colour, then the tagline.
- An optional look note: the template's `Signature` attribute (`FighterSelect.signatureOf`), hidden when the attribute
  is missing.
- Four slanted stat bars with their 1-10 values, and the signature moves.
- On the right, a roster grid of portrait cards, two columns. The selected card lifts out with an accent corner.
- The info column and the grid slide in as the camera settles.

**Studio**
- The camera is closer (14 studs, FOV 29) and the fighter stands at 0.6 of the screen width.
- The camera fits the shown fighter's measured height (head, hair and hats). Goran is no longer cropped, and a push
  ends on the head and chest.
- Two accent light pillars and a glossy marble floor frame the fighter.

**Unchanged:** navigation, the preview gate, the light cuts and the confirm flow.

**Live FlashDetector** over a full browse (slow and fast, close and reopen warm): 1,303 frames, 7,403 visible
model-frames, **0 bare frames, 0 pose pops**.

### One lobby theme ("Ember & Steel", `UIHelpers`)

The fight HUD's angled language now runs through every lobby panel, menu, picker and prompt built with the kit.
LobbyUI's own code is unchanged, apart from How to Play.
- **Buttons:**
  - crisp 3 px corners;
  - a slanted accent notch in the top-right corner (primary, selected or focused buttons; hidden when disabled);
  - a diagonal light sweep across primary buttons.
- **Panels:** a 4 px radius. The hairline turns ember round one corner. It is a gradient on the stroke, not an extra
  frame, so the callers' list layouts are untouched.
- **Segment bars:** slanted blocks.
- `UIHelpers.slantCap`: a corner triangle cut by a pixel-space UIGradient.

LobbyUI is 192,105 characters. Everything new went into new modules (HudKit, HudBanners) or into UIHelpers.

### Tests (round 6)

| test | result | covers |
|---|---|---|
| HudController_Test | 13 | HUD states, Contract A with and without the fields, the Ultimate card and letterbox, the guide during cinematics, the round flow, the stance chip |
| UITheme_Test (new) | 7 | the theme, the select layout and transitions, the camera fit for fighters 4.6 to 7.6 studs tall, the look note |
| LobbyUI_Test | 27 | |
| UIControls_Test | 9 | every legend key, including L |
| UITutorial_Test | 12 | |
| FlashDetector_Test | 6 | |
| SelectScene_Test | 3 | |
| UIFrontend_Test | 7 | |
| UIPrompts_Test | 3 | |
| CreditsScreen_Test | 4 | |
| ClientModules_Test | 3 | |

Full suite on `r6-look` with `r6-combat` merged (2cf7518): `[SUMMARY] 579 run, 563 passed, 16 failed`. All 16 are
motion and characters tests that the new movesets break until the motion clips land:
- MotionMovesKicksCoverage 4, MotionMovesStrikesCoverage 3;
- MotionQA 5, MotionQARound5 2;
- MotionGround 1;
- CharacterLook 1 (Sierra's SlashElbow glove).

**Evidence:** `OV6\handoff\look-shots\round6\`.

### Known issues

- The phone check used a keyboard device in an 844 x 390 Studio viewport, not a real touch device. At that size the
  combo counter's damage line is small (about 7 px).
- During the Ultimate, the camera and the poses come from the motion branch. With r6-combat alone, the fallback
  camera is very close.

## Round 6 follow-up (integrated build, main @ a8cd197)

Fixes from the integrator's playtest. Evidence: `OV6\handoff\look-shots\round6\followup\`.

- **Ultimate key on the opponent's side.** In Free Training the dummy reaches Surge after a few Ultimates, and its
  side showed the player's "[L] ULTIMATE". The key now shows only on the local player's own side, which is always
  drawn on the left (`HudController.OWN_SIDE`). The opponent gets a plain ULTIMATE tag, and the chip carries a
  `KeyShown` attribute.
- **Tags over tall fighters' heads.** The SURGE, ULTIMATE and stance chips are now 17 px (were 22-24) and sit right
  under the bar's accent edge (`LAYOUT.statusY` = 51). They never reach below the name row, so Goran's eyes stay
  clear at the Free Training start. The fight camera's headroom belongs to motion (CameraDirector).
- **ROSTER label.** It was ember text on the studio's ember light pillar. It is now white on its own dark plate with an
  ember outline (contrast at least 7:1).
- **Select stat bars.** Only real attacks count (`UIHelpers.isAttack`): damage above 0, and not a throw, stance
  entry, parry, catch or the Ultimate. The round-6 utility moves start in 3-10 frames and had become the "fastest
  startup", so Goran showed SPEED 6 and Kael 4.
  - SPEED averages movement and attack tempo (mean startup), each ranked against the cast.
  - DEFENSE adds every defensive tool: armor, parries, the catch, guarding or parrying stances.

  | fighter | POWER | SPEED | REACH | DEFENSE |
  |---|---|---|---|---|
  | Kael | 4 | 8 | 5 | 4 |
  | Sierra | 4 | 8 | 10 | 4 |
  | Goran | 10 | 3 | 3 | 10 |
  | Lumi | 3 | 10 | 8 | 3 |
  | Rhys | 4 | 7 | 7 | 6 |
  | Nia | 3 | 8 | 6 | 4 |

- **Lobby camera after a return** (new `Client.LobbyCamera`, driven by FrontEnd). After a fight, a practice or a
  quick travel, once the character stands on its exit or Arrival, the camera is framed once over the player's
  shoulder toward the arena. Before, it kept the fight camera's direction and could start behind a lamp post. See
  world.md for the moved exits.

**Tests**
- HudController_Test (15): own-side key as P1 and P2; status row geometry.
- UITheme_Test (8): ROSTER contrast.
- UIFrontend_Test (8): the stats follow the design.
- LobbyCamera_Test (4, new).
- ClientModules_Test: the new APIs.

Full suite on the integrated build with these fixes: `[SUMMARY] 601 run, 600 passed, 1 failed`. The one failure is
the known VfxUltimate_Test timeout, which motion is fixing.

## Round 7 (play): PLAY in a few clear steps, the map you want, practice tools for combos

Owner: play (branch `r7-play`). Evidence: `OV6\handoff\play-shots\round7\` (README there has a verdict per image).

The user's feedback: the F panel was "so hard to navigate, a lot to look at instead of just play, vs someone, or cpu,
then pick map, then go fight". Combos were "difficult". Round 7 replaces the panel with a step-by-step flow, lets the
server honor the map you pick, and adds practice tools that make combos learnable.

**Before → after.**

| | before (round 5 panel) | after (round 7 flow) |
|---|---|---|
| CPU fight, keyboard | F, ↓, →, Enter (a level card on the grid): 4 presses, map chosen for you | F, →, Enter, Enter, Enter: VS CPU → map → FIGHT! (5 presses; the map is now yours to pick, the level rides along) |
| CPU fight, mouse | 2 clicks (PLAY, a level) on a 13-button grid | 4 clicks (PLAY, VS CPU, a map, FIGHT!) on 2–4 big cards, one decision per screen |
| on screen at once | 4 rows (VERSUS A PLAYER, FIGHT CPU, PRACTICE, GO TO), 13 buttons + tabs + help | 3 cards (who), 4 map cards + CPU level (map), 2 cards (ready), 4 cards (practice) |
| VS PLAYER | QUICK DUEL only (any arena) | ANY MAP (recommended) or a map: you wait on its free circle |
| bottom bar | FIGHTERS 186x54 · PLAY 236x68 · MENU 160x54 | FIGHTERS 148x44 · **PLAY 286x78** · MENU 124x44 |
| LobbyUI | 192,060 characters | 187,821 characters (the panel moved out; the flow lives in `PlayFlow`, the tools in `PracticeTools`) |

Captures: `00-before-r5-play-panel.png` / `00-before-r5-lobby-bar.png` (round 5) against `01-after-lobby-bar.png`,
`02`–`14` (every step of the flow), `27`–`34` (the map picker on each map's own stage, FIGHT! from it, CHANGE FIGHTER
and back) and `15`–`25`, `35`–`39` (practice tools and combo trials).

### The PLAY flow (`Client.PlayFlow`)

ScreenGui `FightingLabPlay` (DisplayOrder 35). The pure step model (`PlayFlow.new / cards / act / rejected`) is tested
without Instances; `PlayFlow.mount(env)` builds the view and drives the preview camera. LobbyUI hosts it (`openPlay`,
`closePlay`, `isPlayOpen`, `playFlow`, `playAction`, `playSelect(id)`) and owns the keys.

1. **WHO DO YOU WANT TO FIGHT?** VS PLAYER · VS CPU · PRACTICE.
2. **VS CPU → PICK A MAP.** One card per duel arena from `Stations` (in `Order`; dojo excluded) with the world's
   `DisplayName`, `Tagline` and `ThemeColor` (Contract D; fallbacks: `AccentColor`, ember, the Stations name, no
   tagline) and its state (OPEN / PLAYER WAITING / LIVE FIGHT / BUSY). Behind the panel the focused map is shown the
   way its fighters see it: `StageController.previewArena(arena)` (world, Contract D) puts up the arena's fight set and
   mood and hides the district, and the camera sits on the arena's `PreviewCam` at its `FieldOfView` attribute
   (fallback without a PreviewCam: a shot computed from `FightOrigin` and `Arrival` of the plain world). Every map is
   its own stage, so moving between maps cuts under a short dip to dark (`DIP_IN` 0.09 s, `DIP_OUT` 0.2 s, ScreenGui
   `FightingLabPlayDip` under the panel) instead of gliding through the hidden city; leaving the map screens dips
   back to the lobby view and `previewArena(nil)` puts the district back. Only thin top and bottom shades cover the
   scene. A big name, tagline and state chip
   sit over the preview. **CPU LEVEL** (Easy / Normal / Hard, default Normal, remembered) is a chip row under the header
   (Up to reach it, or click), on a dark backing so its one-line hint reads over any map. Your fighter is shown top
   right with CHANGE.
3. **READY?** FIGHT! (one confirm; "Kael vs CPU (Hard) at Harbor Dusk") or CHANGE FIGHTER (the preview ends before
   the select takes the camera; the flow and its preview come back on READY). FIGHT! sends
   `QuickPlay {mode = "Cpu", arena, difficulty}` once; the travel fade holds black until the fight camera has taken
   over. The stage and the shot are handed to the fight: its `StageController.setArena` replaces the preview and the
   fight camera glides from the shot (if no fight takes the stage within `HANDOVER_SECONDS` = 6 s, the district and the
   lobby camera come back).
4. **VS PLAYER → PICK A MAP.** ANY MAP first and RECOMMENDED (today's matchmaking), then the four arenas ("OPEN · WAIT
   THERE", or "1 WAITING · FIGHT NOW" when someone already waits there). A map sends you onto its free circle to wait; the lobby camera is framed once
   over your shoulder at the ring (`LobbyCamera` knows the duel circles). The objective pill reads WAITING FOR A
   CHALLENGER with CANCEL, and FIGHT CPU after `UIState.QUICK_CPU_OFFER` = 12 s (`offerDelay`; a walk-in on a circle
   keeps the short offer). The PLAY button is the clock (`SEARCHING 0:07` / `WAITING 0:07`). F while waiting opens the
   **search screen**: FIGHT CPU INSTEAD (after 12 s) and CANCEL (focused until then).
5. **PRACTICE.** FREE TRAINING · COMBO TRIALS · GUIDED LESSON · PRACTICE VS CPU (all at the dojo; COMBO TRIALS opens
   the trial list once practice starts).

Back steps back one screen (Backspace / gamepad B / the BACK button; on the first screen it closes). F (PLAY key)
toggles the flow from any screen, C opens the select, Tab the menu. Keyboard (arrows / WASD + Enter), gamepad (DPad /
left stick + A / B), mouse and touch (every card is a button); the first press is never dropped (the flow owns the
keys from the frame it opens). A busy map is refused by the server with the next free one offered: on READY the card
swaps to it ("HARBOR DUSK IS BUSY · NEXT FREE: JUNGLE RUINS"); a VS PLAYER pick reopens the flow on the map screen.

The preview camera never hands back a frozen camera (`PlayFlow.lobbyCameraType`): a preview that starts while a
practice exit still holds the fight camera for a few frames used to restore that Scriptable shot, and the lobby
camera stayed stuck (found in live QA, regression test in LobbyUI_Test).

### Server: the map you pick (`NetProtocol`, `DuelService`)

| Lobby kind | payload (new in round 7) | server |
|---|---|---|
| `QuickPlay` | `arena` (optional ArenaId, `NetProtocol.validArenaId`; Duel and Cpu) | **Cpu + arena**: that arena if free, else rejected `ArenaBusy {arena, next}` (the next free duel arena, or ""). Unknown arena or the dojo: `NoArena`. Already alone on a circle at that arena: the CPU joins there (`NotAlone` if a challenger is on the way). **Duel + arena**: you are moved onto its free circle (Teleport reason `Wait`) and wait there; `ArenaBusy {arena, next}` if both circles are taken or a match runs. **No arena**: unchanged (any free arena / the matchmaking queue). |

Stations publish `Reserved`; a circle a player is being moved to counts as taken (`incoming[side]`) for pad polling,
matchmaking and CPU requests, so two players can never be sent to the same circle. Debug: `FightingLabDuelDebug`
`quickStub(mode, fighter, name, arenaId)` (a stub player picking a map) and `quickState()` (reserved / incoming).

### Practice tools (`Client.PracticeTools`)

ScreenGui `FightingLabPractice` (DisplayOrder 12), practice sessions only. The practice panel gains a COMBO TRIALS
row and a SHOW: INPUTS / FRAME DATA chip row.

- **Input display** (left, under the HUD): the last `INPUT_ROWS` = 10 inputs as notation icons (1-4, arrows, chords)
  with the frame gap since the previous input (`+8`); a pause over `LONG_GAP` = 90 frames shows "—". Fed by
  `HudController.recordInput` → `HudController.inputLog()`. Turns on by itself during a trial.
- **Frame advantage** (top centre, under the clock): on hit / block, `+3` (green), `−3` (gold), `−12 · PUNISHABLE`
  (red) with ON HIT / ON BLOCK / ON COUNTER HIT and the move name, from the player's side (the opponent's moves read
  with the sign flipped, "THEIRS ON BLOCK"); launchers and knockdowns read LAUNCH / DOWN; juggle hits show nothing.
  From the sim's own event `advantage`. Shows `FRAME_SECONDS` = 3 s.
- **Combo trials** (Contract C, `ComboTrial` from combat): the list (`COMBO TRIALS · KAEL`) has one row per listed
  combo: name; difficulty stars, damage, COUNTER HIT / SURGE tags and CLEARED; the notation; TRY IT and SHOW ME.
  A trial card (right) lists the steps vertically; each step lights green when it lands, the next one is outlined. A
  failure shows a big banner with the reason in plain words for `FAIL_SECONDS` = 1.3 s, then the trial resets:
  TOO EARLY · TOO LATE · WRONG MOVE · BLOCKED · MISSED · TOO SLOW (`PracticeTools.REASONS`). Success: COMBO CLEAR! with
  the damage for `CLEAR_SECONDS` = 2.4 s, the row is marked CLEARED. NEXT / ALL / END on the card; P during a trial
  opens the list. **SHOW ME** plays `ComboTrial.demo` through the real practice runner (player input blocked, the
  steps light as it plays, "WATCH: the combo plays itself"), then "YOUR TURN!". A demo's success is not counted as a
  clear. Without the module (`ComboTrial` missing) the list says so and nothing breaks.

### Tests (round 7)

- **PlayFlow_Test (7, new)**: the four-press CPU route with map and level; Back; busy map + next free (in place and by
  reopening); VS PLAYER (Any map first, a waiting map = fight now); PRACTICE options; search / wait offers after 12 s;
  map facts with Contract D fallbacks; `previewFov`.
- **PracticeTools_Test (5, new)**: input rows and gaps; the readout from both sides; trial list / steps / failure
  reasons / reset / success against a stub with Contract C's exact API; SHOW ME plays the demo frame by frame with
  player input off; with the real `ComboTrial`, SHOW ME through a practice MatchRunner clears every standing combo of
  all six fighters.
- **LobbyUI_Test**: the old panel tests replaced by flow tests (first press never dropped, Back, CHANGE FIGHTER comes
  back, VS PLAYER search / wait / CANCEL / FIGHT CPU, busy map, PRACTICE → trials, the practice panel tools), the
  frozen-camera regression, and the stage preview (each map on its own stage via a fake `StageController`: the
  PreviewCam shot and field of view, `previewArena(nil)` on Back, kept for the fight, ended for CHANGE FIGHTER and
  back on READY); the bar test checks the new sizes.
- **Duel_Test (+3)**: Cpu + arena (taken there and held while the move is pending; busy → ArenaBusy + the next free
  map, which then works; every map busy → no offer; dojo / unknown → NoArena; malformed → Invalid); Duel + arena (wait
  on its circle; a second player there or an Any map searcher starts the duel); waiting on a chosen map (cancel, a CPU
  right there, switching maps, two players arriving at once). **DuelProtocol_Test (+1)**: `arena` validation.
  **FightSession_Test**: `quickPlay` passes `arena`.
- **LobbyCamera_Test (+1)**: a wait on a chosen map frames the ring from the circle.
- **ClientModules_Test**: the new APIs (PlayFlow, PracticeTools, LobbyCamera.facingOf, and world's
  `StageController.previewArena / previewing / animOffset / hidesInOwnFight`).

Full suite on `r7-play` (r7-combat at 5aec8a5 and the final r7-world 2e85639 merged, in Play):
`[SUMMARY] 673 run, 673 passed, 0 failed`.

FlashDetector during the flow (CPU fights started from the flow and from the stage preview, VS PLAYER wait and cancel,
CHANGE FIGHTER and the fighter select, practice, trials, SHOW ME): **0 bare frames, 0 pose pops** over 49,414 frames
(run 2) and 29,435 frames (run 4, with the stage preview) (`flashdetector-round7.txt`). One earlier run flagged 14
frames on the CPU opponent's HUD portrait (a texture briefly reported "Loading"); the burst captures of those frames
show the portrait dressed, and the case did not reproduce from a cold start (details in the evidence file).

### Known issues

- Counter-hit trials (`COUNTER HIT` tag) set the dummy to fight back; their SHOW ME only plays the inputs, it cannot
  make the dummy attack on cue (combat's documented limitation of `ComboTrial.demo`).
- Practice keys in a trial: R resets the attempt; P opens the trial list instead of a plain pause.
- The PreviewCam shots and the stage preview are world's (Contract D; D2 moved the PreviewCams inside each fight set,
  `StageController.previewArena` shows the set); the flow uses them as given.

### REQUESTs

- combat: `Controls.actionText.play` still reads "Play: Quick Duel, Fight CPU, Practice, Arenas"; with the flow it
  should read "Play: VS Player, VS CPU, Practice" (How to Play and legends show it).
