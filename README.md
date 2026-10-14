# FightingLab

An original, private Roblox 3D fighting game played as a duel lobby: you spawn in a plaza as your fighter, walk to
themed arenas, stand on glowing circles to duel other players or a CPU, and practise in a dojo. Six original fighters,
each with its own signature mechanic, 23-26 moves and tested combo routes; a low-health Surge with a once-per-round
cinematic Ultimate for every fighter; a CPU with three fair difficulty levels and an automated anti-cheese pass.

![Lobby](docs/gallery/01-lobby-spawn.jpg)

This repository holds the Roblox place (`FightingLab.rbxlx`), every game script exported as text (`src/`), the
fighter specs, the build tools and the design docs. More screenshots: [docs/gallery](docs/gallery/README.md).

## How to play
1. Open FightingLab.rbxlx in Roblox Studio and press Play. You spawn in the lobby plaza as your fighter.
2. For the full PC view, pick "Current device" in the device dropdown at the top-left of the game view, then maximize
   the Studio window. (A phone preset shrinks the game, adds a phone frame and touch buttons.)
3. To try player-vs-player in Studio, use Test > Clients and Servers with 2 players (solo Play has one player).

The lobby ("Ember Square"): every arena is a short walk from the spawn (at most about 33 studs). Press **PLAY** (F, or
RB on a gamepad) and answer one question per screen:
1. **Who do you want to fight?** VS PLAYER, VS CPU or PRACTICE.
2. **Pick a map.** Each map is shown on its own stage behind the cards while you browse (for VS CPU the Easy / Normal
   / Hard level sits on the same screen). VS PLAYER offers "Any map" first (matchmaking), or pick a map and wait on
   its circle; "Fight CPU" is offered after 12 s alone.
3. **Fight!** Your current fighter is shown with a CHANGE shortcut; confirm and you are taken straight there.

PRACTICE offers Free Training, Combo Trials, the Guided Lesson and Practice vs CPU. Backspace (or B, or the Back
button) goes back one screen; F closes the flow.
- **FIGHTERS** (C, or LB): change fighter from anywhere (the Fighter Kiosk still works too).
- **MENU** (Tab, or Y): Fighters, How to Play, Move List, Settings, Credits.
- Hold **Shift** to sprint in the lobby (L3 on a gamepad, an on-screen toggle on touch).

You can still walk instead:
- Duel arenas (Midnight Rooftop, Harbor Dusk, Jungle Ruins, Summit Observatory): two glowing circles each. Stand on
  one to wait; when someone stands on the other a countdown starts and you fight there, best of 3 rounds. Waiting
  alone? After a few seconds a "Fight CPU" prompt appears: press E and pick Easy / Normal / Hard.
- Training Bay dojo: the TRAIN circle opens free training or a 10-step guided lesson against a dummy (pick the dummy
  fighter); the CPU circle starts a practice match against the CPU.
- Wins and streaks go on the Hall of Champions board, and each arena's status board shows who is fighting.

## Controls
Lobby: WASD walk, Shift sprint, Space jump, F PLAY, C FIGHTERS, Tab MENU, E interact (kiosk, circles, dojo).

Fighting (keyboard). The same scheme is shown in the fight (G), in How to Play and taught in the guided lesson:
- D walk forward, A walk back. Holding A (or standing still) is your standing guard: it blocks highs and mids.
- Double-tap D: dash. Double-tap A: backdash (chainable).
- Tap W: sidestep into the screen. Tap S: sidestep toward the camera. One step per tap, no circling.
- Hold S: crouch (crouch guard: blocks lows, ducks highs, but mids hit you).
- U = 1 (left punch), I = 2 (right punch), J = 3 (left kick), K = 4 (right kick). Directions + buttons pick moves
  (e.g. down-forward + 2), and buttons in sequence make strings (e.g. 1,2).
- O, U+J or I+K: throw. Break an incoming throw by pressing U or I as it starts (matching the throw's punch).
- J+K (3+4): your fighter's signature (a stance or a catch, see the roster below).
- L (or U+I together, 1+2): your Ultimate, once per round while in Surge (health at 25% or less).
- G: controls guide.
- Practice: R reset positions, T Training / Versus CPU, 1 / 2 / 3 CPU difficulty, Y dummy mode (Stand / Guard /
  Fight back), P pause (opens the practice panel), Backspace leave practice. In Free Training you are always in
  Surge, so the Ultimate can be tried any time. The practice panel also has an input display (your last 10 inputs
  with their frame gaps), a frame-advantage readout (e.g. "+1 ON BLOCK") and Combo Trials: pick one of your fighter's
  listed combos, each step lights up as it lands, a miss tells you why (too early, too late, wrong move, blocked,
  missed), and SHOW ME plays it for you.

Fighting (gamepad): stick or D-pad move, X / Y / A / B = 1 / 2 / 3 / 4, RB throw, RT Ultimate, Start pause, Select guide.

## Roster and arenas
Every fighter is an original character with a signature on J+K (3+4), strings with different enders, two launchers, a
tumble extender for juggles, a cinematic Ultimate and three or four listed combos (Move List → COMBOS):

| Fighter | Style | Signature (3+4) | Ultimate |
|---|---|---|---|
| Kael | Street boxing, pressure | Pocket: a bob-and-weave stance that ducks highs, with a body shovel and an uppercut launcher | Final Bell |
| Sierra | Kickboxing, range | Southpaw: switches the lead leg, which changes her kick follow-ups | Eight Limbs |
| Goran | Heavyweight grappler, armor | Bear Trap: catches a high or mid strike into a suplex; armored moves and a command grab | Landslide |
| Lumi | Acrobatic freerunning | Aerial: a cartwheel that is airborne over lows, with kick follow-ups | Skyline |
| Rhys | Karate counter-striker | Still Water: a counter stance that parries highs and mids; high/mid and low parries | Last Kata |
| Nia | Kung-fu-inspired whirlwind | Coil: a spring stance into three spinning kicks whose 2nd and 3rd hits can be delayed | Monsoon |

Arenas: Midnight Rooftop, Harbor Dusk, Jungle Ruins, Summit Observatory (duels) and Training Bay (practice dojo).

## Repository layout

| Path | What it is |
|---|---|
| `FightingLab.rbxlx` | The game. Open it in Roblox Studio and press Play. |
| `src/` | Every game script exported as text (`<Full.Roblox.Path>.luau`), including the motion clip modules. `_classes.json` records each script's class; `export-manifest.json` lists them. |
| `characters/` | Fighter specs (body, head, outfit, hair, tints, gear and the catalog items they use): the source of `CharacterSpecs`. |
| `data/` | Credits inputs for the motion-capture libraries and arena sounds. |
| `tools/` | Script export/apply, data generation, credits and Studio capture helpers. `tools/mocap/` builds and checks motion clips; `tools/integration/` merged the parallel workstreams of Overhaul 6. |
| `docs/design/` | Design docs: controls and acceptance targets (`CONTRACTS-v6.md`), every move with frame data (`combat-states.md`), balance numbers, the motion clip format (`motioncore.md`), characters, world and UI notes. |
| `docs/research/motion/` | The licensed motion-capture catalog and research notes (the raw capture data is not stored here). |
| `docs/gallery/` | Screenshots of the current build. |
| `CREDITS.md` | Credits for every marketplace item, sound and motion-capture source. |

## Working on the game

The tools need Python 3 (standard library only; the motion tools in `tools/mocap` also use numpy, scipy and
matplotlib). If Windows blocks the scripts, run them as `powershell -ExecutionPolicy Bypass -File tools\<script>.ps1`.

- **Editing in Studio:** open `FightingLab.rbxlx`, make your changes and save to the same file. Then run
  `tools\export-sources.ps1` so script changes show up in `src/`, check them with `git diff`, and commit the place and
  `src/` together.
- **Editing scripts in VS Code:** edit the files in `src/`, close the place in Studio, run `tools\apply-sources.ps1`,
  then open the place and test. New files become ModuleScripts; name them `<Path>.server.luau` or `<Path>.client.luau`
  for a Script or LocalScript.
- **Changing a fighter's look:** edit `characters/<Id>.json`, run `tools\build-data.ps1` (regenerates `CharacterSpecs`
  and the credits), then `tools\apply-sources.ps1`. The server rebuilds that fighter on the next Play.
- **Tests:** press Play in Studio, then run `require(game.ServerStorage.UnitTest.RunUnitTest)(nil, 5)` in the server
  command bar. The result should end with `[SUMMARY] N run, N passed, 0 failed`.

## Architecture
- World: ServerScriptService.FightingLabWorldBoot sets the global lighting and builds workspace.FightingLabWorld from
  ServerStorage.FightingLab.World.* at server start (a compact ring district: central plaza, five arenas 66-70 studs
  from the centre, about 3,900 parts). Each arena has FightOrigin, pads, exits, a StatusBoard and a fight radius of
  21 studs with a visible edge. Client.LobbyAmbience animates pads, lights and arena ambience.
- Duels (server): ServerScriptService.FightingLabServer + ServerStorage.FightingLab.Duel.*. AvatarService spawns
  players as their fighter and keeps new characters hidden until dressed. DuelService watches the pads, offers CPU
  matches, handles forfeits, results and leaderstats (Wins, Streak). MatchHost runs a MatchRunner per arena at 60 Hz
  and sends snapshots to both fighters (and to players within NetProtocol.SpectatorRadius of the arena).
- Fight session (client): Client.FightSession switches between lobby mode and fight mode. Online duels are
  server-authoritative (inputs reach the screen after a network round trip); practice runs the MatchRunner locally,
  so it is instant. Client.SpectatorPresenter shows fights near you in the lobby.
- Controls: ReplicatedStorage.FightingLab.Controls is the single source of truth for keys and on-screen labels
  (Controls.legend / label / formatMoveInput). Client.InputController turns keys into sim commands (a sidestep is a
  one-frame pulse, so holding never orbits).
- Combat: ReplicatedStorage.FightingLab.CombatSim is deterministic and frame-based: automatic standing / crouching
  guard, discrete sidesteps, committed dash / backdash, strings and chords, throws with break windows, tracking and
  homing moves, real step-in root motion, hitstop, counter hits, launches, limited juggles (max 4 air hits, plus one
  per tumble extender), combo damage scaling from the 4th hit, knockdowns, invulnerable getups and rolls, signature
  stances / catches / parries on 3+4, Surge (25% health) and the once-per-round Ultimate (armored startup, then a
  locked two-person cinematic with damage on each impact), and practice-dummy modes. Moves, combos and frame data live
  in Roster (each move also carries an animation-intent sentence; `docs/design/movesets.md` documents every fighter);
  global tuning in CombatConfig.
- CPU: ReplicatedStorage.FightingLab.CombatAI perceives the opponent through a reaction delay per difficulty, blocks,
  punishes, uses strings, throws and footwork, reads repeated habits (with reads that fade over time) and has a
  per-difficulty patience timer so it never stays passive. Easy has a per-fighter matchup table so every fighter is
  winnable for a beginner.
- Animation: Client.Motion.ClipLibrary decodes motion clips (format FLClip1) and Client.Motion.ClipPlayer samples
  them; Client.MotionPlayer turns clip poses into R15 joint transforms with two-bone IK, a ground solver (lying bodies
  rest on the floor, nothing goes below it), planted-foot locking and a reach net (a grounded foot the leg cannot
  reach goes onto its ball and slides along the floor instead of lifting into the air). Clip modules:
  Client.Motion.Clips.Core.* (stances, walking, dashes, sidesteps, guards, hit reactions, falls, getups, rolls, KO,
  victory, defeat) and Client.Motion.Clips.Moves.Strikes / Kicks / Throws.* (one clip per move; throws and the six
  Ultimates have synchronised attacker and defender tracks, hand grips on the partner's body and break tracks;
  Client.Motion.Cinematic plays the Ultimates with their camera shots). Clips are
  proportional, so one clip fits every fighter, and each attack clip is time-warped so its impact pose lands exactly on
  the move's first active frame. The older procedural Client.Motion.Strikes / Kicks / Throws remain as a fallback for
  any move without a clip.
- Fighters: ServerStorage.FightingLab.CharacterSpecs (generated from the JSON specs in `characters/` by
  `tools/build-data.ps1`) holds each fighter's body, head, clothing, hair, tints and gear. CharacterFactory builds the
  R15 avatar; ServerScriptService.FightingLabCharacterBoot rebuilds any saved template whose hash changed. To change a
  look by hand: edit the fighter's entry in CharacterSpecs AND change their string in `hashes`.
- Presentation: CharacterPresenter (fight rigs, pool, previews, contact-aim heights), CameraDirector, EffectsController,
  AudioController, FighterLighting, FaceController, HudController with HudKit / HudBanners (health bars, timer, round
  pips, combo counter, call-outs, Surge / Ultimate indicators, round and K.O. banners, controls guide),
  StageController + LightingProfile (per-arena lighting moods) and ServerStorage.FightingLab.World.FightSets (the
  client-only scenery around each fight), LobbyUI (prompts, CPU picker, training picker, practice strip / pause panel,
  results, Tab menu), FighterSelect (showcase room), StationBoards, Leaderboard, CreditsScreen (renders
  ReplicatedStorage.FightingLab.Credits, generated by `tools/gen_credits.py` together with CREDITS.md).
- Making motion clips: `tools/mocap` (convert.py turns licensed motion capture into clip modules, keyed.py
  builds hand-keyed clips and two-person throws, clipsheet.py renders a clip offline exactly as the game plays it,
  cliplint.py checks credits headers, decoding and move keys). See `docs/design/motioncore.md`.
- Tests: ServerStorage.UnitTest. In Play, on the server: `require(game.ServerStorage.UnitTest.RunUnitTest)(nil, 5)`
  Final result: `[SUMMARY] 687 run, 687 passed, 0 failed`

## Update: easier combos, fair fighters, a simple PLAY flow, better maps (2026-10-13)

- Combos are learnable: presses made early during your own move are kept for 30 frames (was 8), string follow-ups
  typed early queue up, juggle follow-ups turn toward the airborne opponent, and J+K (the signature) accepts presses
  up to 4 frames apart (was 2; 100% registered at 50 ms apart, was 83-86%). Every fighter's first listed combo is an
  easy route (START HERE on the COMBOS page) and the difficulty labels come from measurements: typed through the real
  input path with ±3 frames of timing noise every listed combo lands 100% of the time (main: 5-43%), and every easy
  route lands 100% at any noise tested. Strings are natural combos on hit from every range (13 of 22 -> 22 of 22): a
  follow-up steps in during its startup instead of hitting from out of reach.
- Fair fighters: CPU vs CPU over every matchup, each fighter's overall win rate is now 46-54% at Normal and 46-53% at
  Hard (main: 21-71%), no matchup is worse than 38/62 at Normal or Hard, and every fighter's CPU is about equally hard
  for a human-like player. Hard's strings are real hit-confirmed combos (5% -> 98%), and Goran's health went from 120
  to 104.
- PLAY is one decision per screen: who (VS PLAYER / VS CPU / PRACTICE), pick a map (each map shown on its own stage
  behind the cards), fight. Practice adds Combo Trials (step-by-step checks with plain-word failure reasons and SHOW
  ME), an input display and a frame-advantage readout.
- Maps: every fight is surrounded by its arena's own stage (a landmark behind the fighters, depth layers, a moving 3D
  crowd, credited free trees, ferns and rocks) at the same frame rate.
- Animation: the boxers' feet stand naturally in the fighter select (the body bobs over planted feet), feet no longer
  skate in the fight stance and walks, a tumbling body rolls instead of passing through upright, and juggle hits,
  tumbles and air landings hit harder visually and audibly.

## Update: distinct fighters, combos, Surge and the Ultimate, a premium look (2026-10-12)

- Every fighter plays differently: a signature on 3+4 (Kael's Pocket weave, Sierra's Southpaw switch, Goran's Bear Trap
  catch, Lumi's Aerial cartwheel, Rhys's Still Water counter stance, Nia's Coil spins), 23-26 moves each (strings with
  different enders, two launchers, a tumble extender, lows, punishers, throws). Fighters sharing the same kind of move
  on the same input dropped from 29% to 5% (only the jabs).
- Combos: three or four listed routes per fighter on the new COMBOS page of the Move List, every one verified against
  all six opponents (31-40 damage out of 100, 35-44 when ending in the Ultimate).
- Surge and the Ultimate: at 25% health or less a fighter enters Surge (a coloured aura, a SURGE tag and slightly
  stronger hits) and can fire their Ultimate once per round with L (U+I, RT). It has armor while it starts and is
  punishable on block; on hit a cinematic plays with designed camera shots, effects and sound (Final Bell, Eight
  Limbs, Landslide, Skyline, Last Kata, Monsoon). The CPU uses it too: Easy never, Normal as a punish, Hard well.
- Look: each arena has its own lighting mood and fight-only scenery; a new fight HUD (angled health bars with a
  damage trail, combo damage, ROUND / FIGHT / K.O. / PERFECT banners, Surge and Ultimate indicators, the Ultimate's
  title card); a bigger fighter select with a roster grid; one theme across the lobby panels.
- Fighters: refined outfits and one signature detail each (Kael's taped glove cuffs, Sierra's braided armbands, Goran's
  forearm chain and beard, Lumi's grip gloves, Rhys's loose bun, Nia's gold armlets).

## Update: cleaner knockdowns, close hits and a visible face (2026-10-12)

- Getting up no longer spins: a fighter who lands face down rolls onto their back first (new `ProneTurnOver` clip)
  and then stands up. The worst whole-body turn per frame dropped from 53 to about 12 degrees, and the arm and leg
  whips during getups are gone (QA `getup.spin` / `getup.whip` defects 42 / 839 -> 0 / 0).
- Strikes stop on the opponent's body at any distance: the runtime scales each clip's forward lunge to the real
  distance, so point-blank hits that used to sink up to 0.77 studs into the body now land within 0.05-0.14.
- Fighters on the floor (landings, getups, rolls, KO) and fighters being thrown no longer push their gloves or
  forearms through their own bodies, and the side roll was rebuilt.
- Kael's face stays visible behind his guard in the fight camera (worst-case visibility 0.00 -> 0.85, every other
  fighter 1.00); his gloves sit at chin height with the elbows tucked.
- `MotionQARound5_Test` checks all four on all six real rigs, and no QA defect category got worse for any fighter.

## Update: easier lobby and a compact map (2026-10-12)

- A bottom bar with PLAY, FIGHTERS and MENU: PLAY takes you straight into a Quick Duel (server matchmaking), a CPU
  fight, practice or any arena, with no walking (a CPU fight starts about 0.3 s after the click).
- Sprint in the lobby (Shift / L3 / touch toggle, 16 -> 28 studs/s with a smooth ramp).
- The map is compact: the worst walk from a spawn to any arena's circles dropped from 87.6 to 33.4 studs.
- The legacy pre-lobby main menu code (title screen, Arcade) is gone, and an automated detector (`FlashDetector`)
  proves that no fighter model is ever shown half-dressed or snapping in the fighter select, portraits or lobby avatar
  swaps (53 bare frames found before, 0 after).

## Update: proportions and smoother animation (2026-10-12)

- Every fighter was measured against real adult proportions (heads tall, head vs shoulder width, neck, hands, hair
  volume, gear) and corrected: Kael's and Sierra's boxing gloves are real-glove size (they no longer cover the face in
  guard), Rhys has a smaller head and slimmer hands, Goran's shoulders and lifting belt are less extreme (his knee pads
  became compression tights), Lumi's hair is less oversized, Nia wears a draped waist wrap, and the women are slightly
  broader in the shoulders. `CharacterLook_Test` checks all of it; legs are unchanged so every animation still fits.
- Animation is smoother: hit reactions blend in through the hitstop, transitions no longer snap, elbows and knees no
  longer flip, gloves and arms stay out of the fighter's own head and torso, fists stop at the opponent's body,
  face-down knockdowns fall and get up without a 180-degree spin, all 13 throws were re-timed, and the fight camera
  follows with eased acceleration. `MotionQA_Test` plays every state, move and transition on all six real rigs and
  checks pops, flips, joint limits and clipping (defects across 598 cases: 12,051 -> 5,599; severe 8,096 -> 2,724).

## Update: shoes and hair (2026-10-12)

- Every fighter's shoes are sized like real shoes as worn (length, width and height checked against the fighter's
  height and bare foot by `CharacterLook_Test`): Kael wears sleek black high-top boxing boots, Lumi slim split-toe
  boots, Goran smaller combat boots, and Nia's slip-ons are now rigid and sized to her feet.
- Hair covers the whole scalp from every angle: Kael's cornrows reach the nape and Rhys wears a bun (Goran keeps his
  shaved head). A ray test checks the back, sides and top of every head.
- Shoes rest on the floor through knockdowns, rolls and getups: the ground solver now rests a visible foot on its
  shoe's ground box instead of the smaller bare foot inside it.

## Overhaul 6 changes (2026-10-12)
- Fighting that feels like a modern 3D fighter: deliberate walking, committed dashes and backdashes, one sidestep
  per tap (no more circling), guard by holding back or standing still and crouch guard by holding down (no guard
  button), throws you can break, strings, launchers that are punishable, limited juggles, invulnerable getups.
- New, clear control scheme (U / I / J / K = 1 / 2 / 3 / 4, O throw, G guide) used identically in fights, the guide,
  How to Play and the lesson; every lobby interaction is an E prompt.
- Motion-captured animation: stances, footwork, reactions, falls and getups from licensed motion capture (ACCAD,
  CMU, Quaternius), and all 100 attacks rebuilt as real clips (motion capture where it exists, careful hand-keying
  for the rest, including every two-person throw). Knocked-down and KO'd fighters lie on the floor.
- A fair CPU: Easy / Normal / Hard differ in reaction time, blocking, punishing and decision-making; a beginner can
  beat Easy with every fighter; the CPU no longer freezes in a crouch or gets cheesed by spamming one move.
- Anti-cheese pass backed by an automated exploit search: button mashing, jab pressure, single-move spam, turtling,
  wake-up loops and throw loops no longer beat the CPU.
- New compact map ("Ember Square") with every arena a short walk from the spawn, visible arena edges, and lighting
  tuned so fighters never wash out.
- Fighters re-proportioned (about 7 heads tall) with fitted fightwear that follows the body in every pose.
- New UI: premium fighter-select showcase, lobby menu, CPU picker, training picker and guided lesson, a practice
  panel that folds into a small strip while you fight, and a cleaner fight HUD with call-outs.

## Overhaul 5 changes (2026-10-10)
- The game is now a duel lobby: no title screen or menus. You spawn in a plaza as your fighter, walk to themed
  arenas, stand on glowing circles to duel other players (server-run, best of 3) or a CPU, and practise in the dojo.
- New world built in code: lobby plaza with Fighter Kiosk and Hall of Champions leaderboard, four duel arenas and a
  practice dojo, golden-hour lighting with Future lighting and textured 2022 materials.
- Fighters re-dressed with textured, detailed outfits (trims, prints, camo, knit, embroidery, belts, pads, tape,
  textured shoes); Sierra got colour; Goran's body was replaced for originality; Rhys's gi was changed so it doesn't
  resemble a well-known fighting-game outfit.
- No more bare-body flashes: new characters stay hidden until dressed and loaded, fight rigs are pooled, and HUD
  portraits wait for their clothing.
- Lobby UI: identity card with wins and streak, prompts, CPU offer, countdown, practice panel, result cards, toasts
  for other duels, Tab menu (fighters, move list, controls, credits, settings), arena status boards, leaderboard.
- Your own fighter is always on the left, including when you are player 2; other players who block the fight
  camera fade out. The new Roblox chat (TextChatService) replaces the legacy chat.

## Overhaul 4 changes (2026-10-10)
- New realistic cast: catalog bodies and heads chosen per fighter, style outfits (boxing gear, compression tops,
  a blue judo-style gi, a frog-button jacket with martial-arts trousers, grappler kit), hair, beard and gloves.
  Every costume was checked to stay original (no franchise or brand items, no look-alikes of existing characters).
- Facial expressions in fights, menus and the VS splash (FaceController).
- Kung-fu, flow and grappler stances retuned for the new bodies (no more "praying hands" or covering the mouth).
- New 3D character select: lit fighters on stage, style stats, portrait tiles, lock-in pose, CPU roulette, stage
  preview, VS splash.
- CREDITS screen and CREDITS.md.
- Fixes: the client could hang before the menu appeared when an asset preload stalled (preloads now run in the
  background); select tiles showed the fighters' backs and were ordered differently from the cursor; the VS overlay
  stayed over the fight when the splash timed out; menu titles crossed the header line; the mode list overflowed.

## Overhaul 3 changes (2026-10-10)
- Instant controls: local 60 Hz simulation instead of a server round trip with 20 Hz snapshots.
- New fighter looks: realistic bodies, layered outfits, hair, closed fists (gloves / wraps); bent-knee guards.
- Competitive CPU: fixed the long-range whiff-jab standoff; spacing, punishes, juggles; rounds end by KO.
- Snappier launches and juggles; the camera keeps both fighters (feet included) in frame.
- Brighter, readable stages and per-fighter lighting; duplicate saved stage effects removed.
- Local 2P VERSUS mode.
- Fixes: health bars now go down (the HUD rebuilt both portraits every frame and reset the bars, which also leaked
  memory up to ~29 GB on menus); menu previews show full outfits; the VS splash no longer runs a hidden match and
  can be skipped with Enter; pause really pauses; no more HIT / BLOCK / WHIFF popup spam; Roblox player list hidden.


## Known limitations
- Fighters are assembled from Roblox catalog / UGC avatar assets when the server starts, so Studio needs Roblox
  asset access (about 1-2 s on first Play).
- Online duels are server-authoritative, so inputs reach the screen after a network round trip (about 0.08-0.09 s
  in Studio, more on a real server). Practice in the dojo runs locally and is instant.
- No licensed two-person motion capture exists, so throws are hand-keyed; the fastest spins and flips are compressed
  to fit their frame data and move quicker than a real athlete would.
- A few close-range moves still pass slightly into the body during startup (Goran's Hammer and JabHammer), Goran's
  Uppercut sinks a little into a launched opponent, and in two throws a hand briefly grazes the thrown fighter (Rhys
  on Goran's RamSlam, Nia on Rhys's Throw). The rebuilt side roll bends the kneeling foot past its natural range.
- In the Ultimates a few frames still overlap a little: Goran's drag-up (0.2-0.4 studs) and Kael's overhand finisher,
  whose glove grazes the opponent's head. A launched fighter's ankle snaps on the first airborne frame, and the
  fighter-select confirm pose holds still instead of animating.
- The fighters' faces are the best free catalog heads found so far (no better free head was available); Goran's beard
  does not follow his jaw when his mouth opens.
- The arena crowds look toy-like up close, the plaza towers are plain boxes, and the stages look the same as before
  from the plaza (the new stage dressing shows in fights and the map picker).
- Balance is measured CPU vs CPU; for a human the fighters are not perfectly even yet (a simulated player does a little
  better with Goran than with Nia, and does not use Sierra's and Rhys's stances).
- Gamepad, touch and a real two-player session of the new PLAY flow are covered by automated tests only; SHOW ME for a
  counter-hit combo plays your inputs but cannot make the dummy attack on cue.
- R15 rigs have no finger bones: open-hand fighters keep the catalog hand shape and Kael / Sierra wear gloves.
- Studio-only review hooks exist (the FightingLabDuelDebug bindable and a stub world that is only built when the real
  world is missing); they are ignored outside Studio.

## History and backups

- Every change is tracked in this repository (GitHub `yassinsolim/FightingLab`, private).
- Full copies of the place from before each overhaul (`backup-before-overhaul3.rbxlx` to
  `backup-before-overhaul6.rbxlx`) are kept outside the repository, in `C:\Users\solim\.copilot\session-state\e3751321-5f48-4183-b62a-9577765df8cf\files`.
