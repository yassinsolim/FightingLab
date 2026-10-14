# combat.md — OV6 combat handoff (sim, controls, movesets, CPU, balance)

Exports: `OV6\handoff\combat-src\` (UTF-8, LF, no BOM). Details: `movesets.md` (round 6: every move, stance,
Ultimate timeline and combo route, generated from the Roster), `combat-states.md` (states, snapshot fields, rules),
`combat-balance.md` (exploit search, frame data, CPU numbers), `CONTRACTS-v6.md` (Surge and the Ultimate).

## Files

| file | status |
|---|---|
| `ReplicatedStorage.FightingLab.CombatSim.luau` | rewritten: guard system, discrete sidestep, committed dash/backdash, chords + throw breaks, tracking/homing, root advance, getup rolls, KO fall, throw-break window, practice dummy |
| `ReplicatedStorage.FightingLab.CombatAI.luau` | **NEW ModuleScript** (the CPU; `Sim.trainerInput` requires it lazily) |
| `ReplicatedStorage.FightingLab.Controls.luau` | **NEW ModuleScript** (single source of truth for keys + labels) |
| `ReplicatedStorage.FightingLab.ComboTrial.luau` | **NEW ModuleScript** (round 7, Contract C: combo trials and demo inputs for practice; pure) |
| `ReplicatedStorage.FightingLab.CombatConfig.luau`, `Roster.luau`, `MatchRunner.luau`, `NetProtocol.luau`, `RenderBuffer.luau` | updated (additive snapshot fields, `Dummy` command, codec v2) |
| `ReplicatedStorage.FightingLab.Client.InputController.luau` | rewritten for the contract §2 scheme |
| tests `CombatSim_Test`, `CombatRoster_Test`, `Difficulty_Test`, `MatchRunner_Test`, `DuelProtocol_Test`, `RenderBuffer_Test` (updated), `Controls_Test`, `CombatAI_Test`, `Balance_Test` (NEW; round 2 updated `CombatAI_Test` and `Balance_Test`; the step-in round updated `CombatRoster_Test` and `CombatAI_Test`; round 4 updated `CombatAI_Test` and `Difficulty_Test`) | |

`SnapshotTiming` is unchanged (not exported).

## Round 7 (`r7-combat`): combos that land, fair fighters and CPUs — latest

The user: "its difficult to combo the moves but maybe its a skill issue lets look more into this" and "lets make sure
its fair, some characters seem stronger than other atleast from playing the bots". Everything was measured first with
a headless harness (`OV6\work\r7-combat\harness\`: the real `InputController` driven by key events, `MatchRunner`,
`CombatSim`, `CombatAI`), then fixed; tables in combat-balance.md, Round 7.

**Why combos were hard (measured on `main`).** Every listed combo, performed with keys against all six opponents with
human-like timing noise, landed 5-43 % of the time with ±2 to ±6 frames of noise (Ultimate enders 29-62 %) and 0 % when every press came 1-7 frames early (180 performances per combo and noise level). The causes: (1) `AttackBuffer` 8: the next hit pressed more than 8 frames
before the fighter could act was dropped, and during a launcher's recovery, hitstop or a juggle most presses are that
early, so every step's window started exactly at its earliest frame; (2) the J+K signature needed both keys within 2
frames (33 ms): 83-86 % of keyboard presses up to 50 ms apart registered; (3) 13 of 22 strings were natural
combos from every range at which their first hit connects (pushback carried the opponent out of the follow-up's
reach); (4) routes with tight links (juggle hits that had to be pressed inside 2-4 frames).

**Input (`CombatSim`, `CombatConfig`).**
- Recovery buffer: a press made during the fighter's own move after its startup (active frames, recovery, hitstop) is
  kept up to `RecoveryBuffer` 30 frames; presses in neutral still expire after `AttackBuffer` 8, so nothing stale comes
  out of neutral (`CombatInput_Test`).
- Follow-up queue: a string follow-up, stance cancel or stance follow-up typed while the previous press is still
  waiting queues behind it (`input.queue`, up to 3) instead of replacing it; orphans are cleared once the fighter is
  free. A chord's first key that already queued is undone when the chord forms.
- J+K window 2 → 4 frames (`ChordWindow.Kicks`): a first kick that already started its move is upgraded in place to
  the signature before its active frames; a 3,4 string typed with a gap of 5+ frames stays a string, and after a
  chord forms the next key cannot form another one. J+K pressed up to 50 ms apart now registers 100 % of the time (was 83-86 %), even up to 67 ms.
- Juggle follow-ups turn to the airborne body before they start (no whiffs behind a body that drifted sideways).
- String step-in: a string follow-up whose previous hit (same string) put the opponent in hitstun or a juggle steps in
  during its startup (`Sim.stringStep`: real travel the animation shows, up to `StringStepFrame` 0.2 studs per frame
  and `StringStepIn` 1.6 per move, aiming `StringStepMargin` 0.1 inside its range, never through the opponent) and may
  connect at most `StringReach` 0.3 studs past its own range (`Sim.stringReach`); on block or whiff nothing changes.
  22 of 22 strings are now natural combos from every range at which hit 1 connects, and no strike connects
  past its range (an intermediate version reached 1.3 studs further without travel; motion's request).
- Nia's d+3,4 routes press the 4 ten-plus frames after the 3 (was 3 frames): with the 4-frame J+K window a 3-frame gap
  would now be her signature.

**Combo routes (Roster `combos`).** Each fighter's first route is an easy one (difficulty 1, 3-4 presses, no tight
links, 26-34 damage); 2-3 harder routes follow, then the Ultimate ender. Every route was re-timed for human rhythm
(string follow-ups 10 frames apart, juggle steps cued by the launch), single-button steps that could form a chord are
kept apart (3/4, 1/3 and 2/4 at least 12 frames, 1/2 at least 8) so they never come out as a throw or the signature, and each
difficulty is now measured: 1, +1 for 5+ presses, +1 for a stance entry or cancel, +1 for a counter-hit opener, +1 if it
lands under 95 % with ±5-frame noise, +1 more under 90 %. Goran's list is Hammer Down (new, easy), Forearm Finish,
Counter Haymaker and Landslide Finish (Lift And Hammer, Forearm Finish one hit shorter, is gone). Result: every listed combo lands 100 % of the time with ±2 and ±3 frames of noise and with early presses; at ±5 the lowest is Sierra's difficulty-5 Knee To Southpaw (93 %) and every difficulty 1-2 route is 100 % (before 5-43 % and 0 % early); the median window per step grew from 18 to 41 frames, and none of the steps is without early tolerance any more (80 of 83 before)
(tables per combo and per step in combat-balance.md and movesets.md).

**ComboTrial (Contract C, NEW `ReplicatedStorage.FightingLab.ComboTrial`, pure).** `ComboTrial.list(id)` →
`{ index, name, notation, difficulty, damage, kind, counter, surge, steps = { { label, notation, move } } }` from
`Roster.get(id).combos`; `ComboTrial.new(id, index)` → trial; `trial:feed(entry)` takes each practice `MatchRunner`
entry (raw or `RenderBuffer.parse`d: `fighters`, `events`, `frame`) and returns `{ state = "Ready" | "Running" |
"Success" | "Failed", step, total, reason = nil | "Early" | "Late" | "Wrong" | "Blocked" | "Whiffed" | "Dropped",
damage }`; `trial:reset()` (call it on a practice reset), `trial:status()`. Player = slot 1, dummy = slot 2. A trial
starts on step 1's hit (counter routes: a counter hit; stance routes: the stance entry) and fails as soon as the combo
breaks; a new opener restarts it after Success/Failed. `ComboTrial.demo(id, index)` → `{ { frame, press?, hold?,
step?, notation? } }`: from the practice start (walk in, settle) the route with its timing; apply `hold` (Move +
Crouch) first, then `press` (the sim button name); counter routes need the dummy to attack ("Fight"). Committed first
as `C1:` (42c6862); the API is unchanged since.

**Fairness (Roster data, `CombatAI`).** Measured before tuning: CPU vs CPU matrices at every level (60 matches per
ordered pairing after, 40 before), a human-like reference player (harness `refbot.luau`, no CombatAI: sees 20 frames
late, blocks 70 % of what it sees, punishes 45 %, plays its fighter's first route with ±3-frame noise) against every
fighter's CPU, the reference player against itself (pure character strength), and AI-independent power metrics.
Findings and fixes:
- Hard's hit-confirm pressed string follow-ups after the last frame that still combos: only 5 % of Hard's follow-up
  hits on `main` were combos (Nia's d+3,4 launcher got blocked and launch-punished, Nia's Hard CPU won 21 %). A confirm
  that cannot be in time is now decided before that frame without seeing the result (`blindString`, Hard 0.5: a safe
  follow-up half the time, an unsafe one 21 %): 98 % of Hard's follow-up hits combo (`CombatAIRound7_Test`). Hard is
  harder for the reference player than in round 6 (the reference player wins 5.4 % of its matches against Hard, 9.0 % before).
- Character data: Goran was the strongest kit (CPU vs CPU 63 % at Normal, the hardest CPU for a person, 69 % in
  reference vs reference); Sierra, Lumi and Kael the weakest. Changes: Goran HP 120 → 104, Jab-Hammer 12 → 11, Leg Hook
  i21 → i23 and 16 → 15, the 2+4 throw 20 → 18 (his juggles keep Forearm Finish, 38: juggles decide CPU-vs-CPU fights far more than fights against a person); Sierra HP 95 → 102, Jab and
  Duck Jab 5 → 6, Teep 11 → 12; Lumi HP 90 → 98, Palm 5 → 6; Nia Low Spin 8 → 7, Palm Thrust 11 → 10 (the best mid
  poke in the cast), Rising Whirlwind (d+3,4) 12 → 10 (her low-into-launcher gave her CPU 1.9 launches per match
  against CPUs, 3-6 × anyone else's).
- Per-fighter CPU skill (`CombatAI.FighterSkill`, `AI.SkillLimit` 0.4): a level plays some kits better than others, so
  each fighter's CPU gets an offset k per level that blends its parameters toward the level below (k < 0) or above
  (k > 0); chances are clamped, reaction never below 13 frames, Easy-only mashing stays Easy-only, and |k| ≤ 0.4 keeps
  every fighter's Hard sharper than every fighter's Normal, sharper than every fighter's Easy (`CombatAI_Test`). Tuned
  by `optimize.ps1` (damped steps on CPU vs CPU win rate and the reference player's win rate per CPU, level means held
  at round 6's Easy and Normal; Easy also weighs CPU vs CPU). Values: Easy Kael +0.15, Sierra −0.10, Lumi −0.05;
  Normal Kael +0.14, Sierra +0.03, Lumi +0.05, Rhys +0.06, Nia −0.02; Hard Kael −0.12, Sierra −0.18, Goran +0.20,
  Lumi +0.04, Rhys −0.09, Nia +0.12 (the rest 0).
- Result: CPU vs CPU, every fighter 46-54 % at Normal and 46-53 % at Hard (before 40-63 % and 21-71 %), 45-56 % at Easy (41-61 %); no matchup outside 38-62 % at Normal and Hard (35-65 % at Easy); every fighter's CPU within ±7 points of the mean for the reference player at each level (spread Easy 13.3 → 9.6, Normal 23.8 → 12.1, Hard 12.5 → 7.1 points; Goran's Normal CPU 9 → 17 %); Hard > Normal > Easy (the reference player wins 5.4 / 23.8 / 80.5 %; `Difficulty_Test` green).

**Move list (`Client.MoveList`).** The COMBOS page shows each route's measured difficulty as a word and a score
(`MoveList.difficultyText`: EASY / MEDIUM / TRICKY / HARD / EXPERT n/5, coloured), marks the first route "START HERE",
and the note says how difficulty is measured.

**Tests.** New: `ComboTrial_Test` (every combo's demo completes its trial for all six fighters; late, dropped, wrong and
blocked attempts fail with the right reason), `CombatInput_Test` (early presses kept, stale neutral presses dropped,
J+K 4-frame chord, typed 3,4 stays a string, queued follow-ups, no chord chains), `CombatAIRound7_Test` (Hard's
follow-ups combo). Updated: `CombatCombo_Test` (first route easy, chord-safe spacing, natural strings from every range),
`CombatSignature_Test` (finds Kael's tumble route by its b+1 step), `CombatMoveList_Test` (difficulty text, START HERE).
Retuned with justification (in the files): `CombatAI_Test` "per-fighter skill offsets and Easy matchup adjustments
keep the levels ordered" (was: Normal and Hard identical for every fighter), `Difficulty_Test` perception delay (the
CPU's own delay, which can now differ by a frame or two per fighter), `CombatAIRound6_Test` signature use (up to three
seeds per level instead of one).

## Round 6 (`r6-combat`): six distinct movesets, signatures, combos, Surge and the Ultimate

The user asked for "each character have different movesets and combos, also at low hp there should be an ult".
Everything below is original (names, moves, the Surge / Ultimate system); genre conventions only.

**Movesets (Roster, `movesets.md`).** 16-17 template moves per fighter became 23-26 distinct moves: three 3-hit strings
with different enders, two launchers (a standard one and a unique one: from the stance, on counter hit, a low or a
string ender), one **tumble** juggle extender, a good low and a power low, an i10-12 punisher, the **3+4 signature**
and the **1+2 Ultimate**. Signatures: Kael **Pocket** (bob-and-weave crouch, crushes highs, +1 body shovel, uppercut
launcher), Sierra **Southpaw** (switch stance that guards highs/mids, long head kick, tumble body kick, low kick),
Goran **Bear Trap** (catches a high or mid strike into an unbreakable Belly Suplex; plus armored power moves and the
f+1+3 command grab), Lumi **Aerial** (committed no-hands cartwheel travel, airborne over lows, three kicks out of
it), Rhys **Still Water** (parries every high or mid while held) plus Deflect / Low Deflect parries, Nia **Coil**
(three-kick whirl with delayable 2nd/3rd hits, a coil sweep). Ultimates: Kael *Final Bell*, Sierra *Eight Limbs*,
Goran *Landslide*, Lumi *Skyline*, Rhys *Last Kata*, Nia *Monsoon* (190-260 frame cinematics, 4-6 impacts, beats in
movesets.md). Template sameness (same archetype, height, hit and counter-hit result and property on a shared input):
**33 of 113 shared inputs (29.2 %) → 6 of 118 (5.1 %)**, the 6 being the plain i10 jab on 1 (`CombatCombo_Test`).

**Sim (`CombatSim`, `CombatConfig`).** State `Stance` (3+4 entry or a stance cancel from a `stanceCancel` move's
recovery; follow-ups by the stance tag, buffered until `cancelFrom`; exits by back, 3+4 again, timeout; travel /
drift; guard, crush and parry windows; open stances take counter hits). Tumble (once per juggle: lift, +1 air hit,
face-down ending). Bear Trap catch (event `Catch`, unbreakable throw). Parries free the parrying fighter at once.
Ground combo scaling from the 4th consecutive hit. Juggle physics: launch 16 → 19, re-lift 7.5 → 9, tumble lift 12,
air time 86 → 110 frames (launchers carry 4-6 hits; juggles stay under 45 % of the smallest bar, `Balance_Test`).
Chords: 1+2 within 1 frame (the Ultimate, only while it is ready) and 3+4 within 2 frames; a typed 1,2 or 3,4 stays a
string. **Surge and the Ultimate exactly per Contract A** (CONTRACTS-v6.md, Surge and the Ultimate): Surge at ≤ 25 %
(× 1.1 damage, event `Surge`), the Ultimate once per round in Surge, armored startup (throws beat it; parries and the
catch do not), on hit both fighters in state `Ultimate` for the cinematic with the defender `endDistance` in front,
damage per impact (`UltHit`), KO declared at the end, the round clock waits, × 0.7 when it ends a combo; Free
Training keeps the player in Surge with the Ultimate refilled. `Sim.comboRun / comboTick` play a combo route.

**Combos as data.** `Roster.get(id).combos` (4-5 per fighter: launch bread-and-butter, signature / counter-hit / low
route, max damage, Ultimate ender) with frame-timed inputs; `CombatCombo_Test` drives every combo against all six
fighters (true combo, damage ±1). Damage 31-40 on a 100 HP bar (≤ 44 % of Lumi's 90), Ultimate enders 35-44
(table in combat-balance.md R6).

**Netcode.** Codec v3 (`surge` bit 32, `ultUsed` bit 64, `tumble` bit 128, `stance`, `stanceFrame`, the cinematic
`throw` table, event `tumble`, and `punish` on hits that land in the opponent's recovery or parry stagger); MatchRunner / RenderBuffer fields; debug attributes `LearnerSurge`, `LearnerUltUsed`,
`LearnerStance`.

**Controls / input.** `fight.keyboard.ultimate = "L"`, `fight.gamepad.ultimate = "ButtonR2"`, notation
`ultimate = "1+2"`, `stance = "3+4"`, action texts "Ultimate (1+2)" / "Signature (3+4)", legend rows; L / RT send the
Ultimate button, U+I together reach the sim as the 1+2 chord, J+K is the 3+4 chord; an ULT touch button.

**CPU (`CombatAI`).** New skills per level (Easy / Normal / Hard): `signature` 0.25 / 0.6 / 0.85 (stance entries,
stance follow-ups chosen by reads, stance cancels, Bear Trap / Still Water as reads), `routeSkill` 0 / 0.45 / 0.95
(listed combo routes after launches), `ultimateUse` 0.03 / 0.6 / 0.9 (juggle ender, punish, Hard's armored answer to
a seen attack that lasts past its impact, Normal's comeback gamble under pressure; Hard throws an opponent's
Ultimate). Stagger punish after parries, stance reads (no highs into Pocket, no highs/mids into Still Water). One
retune with justification: a pressured CPU now also takes a turn after 2 × patience free frames in range (the old
rule needed a quiet opponent; with the new movesets Easy guarded 6.5 s under steady pokes and failed the passivity
test). Numbers in combat-balance.md R6.

**Move list (`Client.MoveList`).** `fillList` groups the moves (signature, strings, launchers, lows, other strikes,
throws, Ultimate) with property chips (LAUNCH, CH LAUNCH, TUMBLE, STANCE, CATCH, PARRY, CRUSH, ULTIMATE) and frame
numbers, then a COMBOS section (name, kind, notation, damage, difficulty) reached by scrolling or the "COMBOS" jump
button; `fillCombos(scroll, def)` renders the combo page alone (`opts.combos = false` leaves it out of `fillList`),
`groups(def)`, `describe(move, def)`; the fighter-select highlights are the signature, a launcher and the Ultimate.

**Tests.** New: `CombatCombo_Test`, `CombatUltimate_Test`, `CombatSignature_Test`, `CombatAIRound6_Test`,
`CombatMoveList_Test`; updated: `CombatRoster_Test`, `CombatSim_Test`, `Controls_Test`, `DuelProtocol_Test`,
`RenderBuffer_Test`, `MatchRunner_Test`.

## Integrator requests done

- Knockdown timing (motioncore request): `CombatConfig.LandingFrames` 26 → **34**, `GetupFrames` 18 → **26** (rolls +10):
  1.0 s from the floor to standing. CPU wake-up/okizeme logic reads the config; tests and `Balance_Test` updated; the
  wake-up search re-run: 0 unblockable setups in 35 956 tests. combat-states.md regenerated, motioncore told.
- `NetProtocol.SpectatorRadius` 150 → **85** (arenas sit 66–70 studs from the plaza centre: the centre still sees every
  arena, a player at one arena no longer streams the far ones). `DuelProtocol_Test` pins it to 75–100.
- motionthrows REQUEST 1 (text only): the animation intents of Kael ThrowB, Goran Throw/ThrowB, Lumi Throw/ThrowB,
  Rhys Throw/ThrowB and Nia Throw now use the §8 wording (what is animated, since the sim never swaps sides).

## Round 2 (CPU for a general player) — changes

Numbers: `combat-balance.md` section 0. Only `CombatAI`, `Roster` (looks/heights) and two tests changed; **no move
key, startup/active or other frame-data change**.

- **Beginner vs Easy fairness (Easy only).** Easy `turnTake` 0.20 → 0.23, plus a per-fighter matchup table
  `CombatAI.Matchups.Easy` (`vs` = the human's fighter, `as` = the CPU's fighter). It scales Easy's chance to
  counter-attack after blocking (`turnScale`), capped at 0.38 so Easy stays below Normal's 0.40.
  - New API: `CombatAI.paramsFor(level, meId, foeId)`. Each brain stores its params at creation.
  - Normal and Hard get their unchanged shared tables.
  - Result: every fighter wins 49–57 % as the beginner and 47–56 % as the Easy CPU (384 matches per cell).
- **Spam tail (Normal and Hard get stronger).** All 19 tail cells ≤ 8 % vs Normal and ≤ 4 % vs Hard at 24 matches
  (worst was 29 % / 21 %). Fixes:
  - a buffered block punish can no longer be replaced by the turn-taking poke (`punishedFor`);
  - a `ducks` read: the opponent's attacks go under highs, so the CPU picks non-highs;
  - a crouch turtle no longer means a crouching attacker;
  - throw streaks count as pressure (the CPU ducks grabs), and the wake-up crouch counts throws;
  - against high spam the CPU stays down and answers;
  - the busy-opponent filter picks moves faster than their usual startup;
  - a reach- and timing-aware step-in after blocking an out-of-reach minus move;
  - when behind with less than 15 s left, the CPU dashes or walks in instead of guarding out the clock.
- **Tools:** setting `CombatAI.trace = true` (or `"full"`) records which decision pressed each CPU move
  (`brain.why`). It's off in the game.
- **Optional Roster add-on (characters.md REQUESTs):** `look` strings for Sierra, Goran, Lumi, Rhys and Nia now
  match the new outfits (Kael unchanged). `stats.height` follows the round-2 statures: Kael 5.95, Sierra 5.85,
  Goran 6.75, Lumi 5.9, Rhys 5.9, Nia 5.5. These are MotionPlayer fallback only; the sim doesn't read them.
- `combat-states.md` regenerated: the frame-number note now says the impact column is the Roster source literal
  (`def.impact`, runtime `def.startup + 1`). This answers a motionkicks question; there was no off-by-one.
- Tests:
  - `CombatAI_Test` +2 cases: "a planned block punish comes out instead of a quick poke" (fails without the fix)
    and "Easy matchup adjustments touch only Easy".
  - `Balance_Test` spam case: now separate targets (Normal ≤ 20 %, Hard ≤ 10 %), plus the old tail moves (Ram Slam,
    Spin Backfist, Teep, Rising Uppercut).

## Step-in round (REQUEST 7, approved) — changes

Numbers: `combat-balance.md` section R7. Only `Roster` (range/advance), `CombatAI` (Easy re-tune + two read fixes)
and two tests changed. **No move key, startup, active, recovery, damage, advantage or push changed.**

- **57 moves step in.** `advance` grows and `range` shrinks by the same amount, so the threat range is unchanged.
  - Built from the motion agents' tip measurements: new range = tip + target surface (High 0.61, Mid 0.47, Low 1.20,
    knees +0.10), rounded to 0.05, floor 2.80. Applied only where the range drops by ≥ 0.20.
  - Table: `combat-balance.md` R7.1 and `OV6\work\combat\stepin-table.txt`. Every low kick is unchanged.
  - motionkicks and motionstrikes got one consolidated table (plus Lumi's three late kicks). motionstrikes has
    re-authored its 22 strikes (contact within 0.08 stud). Nia Rising Tornado stays at 3.10 + 1.50 by agreement.
- **Re-checked:**
  - max-range punishability: unchanged (every launcher and power low 6/6; DoubleHammer 5/6, mirror);
  - spam tail (25 starters, 24 per cell): worst 17 % vs Normal, 4 % vs Hard;
  - CPU spacing: 0 % out-of-range starts at every level; flips, sidesteps and dashes as before.
- **Fallout fixed in `CombatAI`.** Step-ins end closer, inside grab reach: the beginner bot's landed grabs doubled
  and it beat Easy 92 % of the time. Changes:
  - Easy throw break 0.18 → 0.50 (right button 0.58) and `turnTake` 0.23 → 0.30;
  - new Easy-only `crowdJab`: jab back when a masher crowds it;
  - `CombatAI.Matchups.Easy` re-tuned, with new `crowdVs` (Goran 0) and `punishVs` (Goran ×4, capped below Normal);
  - all levels: no high string follow-up into a ducking opponent, and no back-off out of a crouch read.
  - Result: the beginner wins 54.5 % against Easy, and every fighter is at 42.5–63 % in both directions.
  - Cost: Normal now beats Easy 85 % (was 100 %); mash vs Easy 67 % (was 29 %).
- `combat-states.md` regenerated: reach column prints exact values (e.g. `3.55 + 0.65`); the Startup row documents the
  root-motion formula and the step-in.
- Tests:
  - `CombatRoster_Test` + "step-in moves connect at body contact and keep their threat range";
  - `CombatAI_Test` "Easy matchup adjustments touch only Easy" also checks Easy punishes less than Normal and only
    Easy uses `crowdJab`.

## Round 4: the CPU that stayed crouched (ui report) — changes

Numbers: `combat-balance.md` section R4. Changed: `CombatAI` (perception, reads, patience), `CombatSim` (one line:
`setDummy("Fight")` starts a fresh brain), tests `CombatAI_Test` (+4 cases) and `Difficulty_Test` (24 matches per
pairing). **No move, frame data, Roster or protocol change.**

- **Root cause:**
  - `AI.observe` derived a move's start from `frame - moveFrame`, which drifts during hitstop and throws. A single
    throw was remembered as up to 6 throws, and every blocked hit twice.
  - The streak/stance reads (`throwStreak`, `lowStreak`, crouch stance, `ducks`, spam) never aged. "Two throws in a
    row" stayed true forever, and kept the CPU in a crouching `pressure-guard` that never attacked.
- **Fix:**
  - The move start is tracked across hitstop and throws (one attack = one memory). A connected attack still weighs
    double in the pressure `rate`, which keeps the accepted round-3 pace.
  - Reads age on the opponent's free-time clock: 240 free frames for any read, 120 for a low/throw streak, and a
    streak is dropped once the player backs off or sidesteps. Habits fade with time too.
  - A crouch held on a read ends after 1.2 s (1.4 s with a fresh streak) without an attack from the opponent.
  - A new `Params.patience` (Easy 150, Normal 110, Hard 90 frames) makes the CPU act once it has been passive that
    long while the opponent isn't attacking.
  - Wake-up guard no longer walks in standing into a wake-up low.
  - Easy matchup `vs` re-tuned for the corrected perception (Kael 1.25, Lumi 1.0, Nia 1.2).
- **Results:**
  - The lesson flow without ui's reset: all six dummies attack within 2.3–3.8 s and grab the player.
  - After 2 throws, Versus CPUs at every level act within ≤ 2.1 s and never crouch longer than 1.4 s. Before, they
    made no attack at all in 10 s.
  - Longest passive streak in range (CPU vs CPU): 17.9 / 9.8 / 6.8 s → 4.8 / 3.5 / 2.9 s (Easy / Normal / Hard).
  - Spam, beginner, mash, CPU ordering and maxrange targets are all kept.
- **Tools:**
  - `lessonrepro.luau`, `throwidle.luau`;
  - `behaviour.luau` now reports the longest passive streak and unprovoked crouch for every pairing
    (`BEHAVIOUR_DIAG=1` lists the CPU intents of the worst streak);
  - `COMBAT_FIRST` overlays work in every tool, including `testrun.luau`.

## Verification

- Round 4 headless: 126/127 of my cases (the remaining one is the Studio-only FighterRig pose case),
  `inputtest.luau` 0 failures, and every check in `combat-balance.md` R4 re-run (`OV6\work\combat\runs-r4\final\`).
  The new `CombatAI_Test` cases fail on the round-3 CPU (overlay `ab\round3`), as intended.
  - I didn't re-run the Studio suite this round.
  - ui's `UITutorial_Test` plays the lesson against the real CPU dummy, so it should be re-run at integration. My
    headless replica of that flow passes with and without ui's reset.
- Step-in round headless: 122/123 of my cases (the remaining one is the Studio-only FighterRig pose case),
  `inputtest.luau` 0 failures, full exploit search, spam tail, maxrange, behaviour, beginner (4 seeds) and CPU
  matrices re-run (`OV6\work\combat\runs-stepin\`). I didn't re-run the Studio suite: the changes are Roster numbers,
  CPU logic and tests, all run headless.
- Round 2 headless: 121/122 of my cases (the remaining one is the Studio-only FighterRig pose case),
  `inputtest.luau` 0 failures, and the full exploit search re-run (combat-balance.md 0.3). I didn't re-run the
  Studio suite this round: the changes are CPU logic, Roster text/heights and tests, all run headless.
- Round 1 headless (Lune, `OV6\work\combat\harness`): 123/124 of my cases (the FighterRig pose case needs Studio),
  37 + 10 InputController checks (`inputtest.luau`: keys → commands → sim states), exploit search, CPU matrices.
- My Studio (`OV6\work\combat\FightingLab-combat.rbxlx`, base place + combat-src + motioncore-src): full suite
  **272 run, 272 passed, 0 failed** (before and after the knockdown/spectator change). Practice dojo with real key
  input (render positions traced): tap W = one 1.7–2.1 stud step, holding W 2 s = still one step, S tap = step
  toward the camera on release, S hold = stationary crouch, D D = 3.7-stud dash into contact, A A = 3.2-stud
  backdash, chained A A A A = 6.6 studs in 0.9 s. CPU vs CPU on Midnight Rooftop: both stay facing on the fight line
  near the centre, no circling (`OV6\work\combat\shots\cpu-burst-sheet.png`).

## Controls (contract §2) — `RF.Controls`

`Controls.fight.keyboard/gamepad` (forward, back, sidestepIn, sidestepOut, crouch, lp, rp, lk, rk, throw, guide, and
round 6 `ultimate` = L / ButtonR2),
`Controls.practice.keyboard/gamepad` (reset, switchMode, easy, normal, hard, dummy, pause, leave),
`Controls.lobby` (interact, menu, jump), `Controls.notation` (lp = "1" …), `Controls.buttons` (sim button names),
`Controls.label(group, action, device?)` (also "dash" = "D D", "backdash", "throw1" = "U+J", "throw2" = "I+K",
"breakThrow" = "U / I", "guard", round 6 "stance" = "J+K"), `Controls.legend(group, device?)` rows `{action, keys, text}`
(round 6 adds the fight rows `stance` and `ultimate`),
`Controls.formatMoveInput(rosterInput, device?)` ("df+RP" → "S+D+I" / "↘+Y"), `Controls.notationOf(input)`,
`Controls.keyCode(s)`, `Controls.actionText`, `Controls.tapMs` (150).

InputController: S press = crouch immediately; releasing S within 150 ms with nothing else pressed = one sidestep
toward the camera (a `Move z=-1` pulse); W press = one sidestep in. Double taps and chords are detected in the sim
(`DashTapWindow` 14 f, `ChordFrames` 3 f), so online and practice behave the same. Owned keys: D/A/W/S, U/I/J/K/O,
G (→ `ctx.modules.Hud.toggleGuide()`), practice R (Reset), Y (Dummy cycle), P / Start (Pause). LobbyUI keeps T,
1/2/3 and Backspace. New APIs: `Input.practice(action, arg)` ("Reset" | "Dummy" [mode or nil = cycle] | "Pause"
[bool or nil = toggle]) and `Input.bindPractice(handler)` (optional override). Nothing fires while
`setGameplayEnabled(false)`.

Server commands stay Move/Block/Crouch/Attack (`Block` still means "hold back to guard" for old clients).

## REQUESTs

1. **integrator — `ServerStorage.UnitTest.Cases.ClientModules_Test`**: add `"practice", "bindPractice"` to the
   `InputController` API list.
2. **integrator — place setup**: create ModuleScripts `ReplicatedStorage.FightingLab.CombatAI` and
   `ReplicatedStorage.FightingLab.Controls` and the test cases `Controls_Test`, `CombatAI_Test`, `Balance_Test`.
3. **integrator — `CL.FightSession`** (optional): add `Dummy = true` to `PRACTICE_COMMANDS` so
   `FightSession.practiceCommand("Dummy", mode)` works too (InputController already reaches the runner through
   `ctx.send("Dummy")`, which works without this change).
4. ~~motioncore — `VfxFeel_Test` "hitstop freezes both fighters"~~: done by motioncore (P2 dummy "Stand" before the
   jab, exported in motioncore-src).
5. motioncore / move agents (FYI, motioncore confirmed): new states `Sidestep`, `Backdash`, `Getup` rolls
   (`getupKind`, `rollDir`); KO bodies and juggle-ending knockdowns keep falling (`Airborne` with `knockdown` set)
   instead of snapping to the floor; root `advance` is real sim movement (drop cosmetic lunges for moves with
   `advance`); after `ThrowBreak` both fighters stay in `Throw` for 16 f with `throw.broken = true` /
   `throw.breakFrame`, then return to Idle. Sierra's `HopCross` still uses archetype id `superman_punch` (motion-owned
   id; rename optional).
6. **ui**: read keys/labels from `RF.Controls` (labels above), show the practice dummy from `entry.dummy`
   ("Stand" | "Guard" | "Fight") and switch it with `ctx.modules.Input.practice("Dummy", mode)`.
7. ~~**integrator — proposal (from motionkicks)**: long kicks connect at max range while the animated foot is short~~:
   **approved and done** (step-in round above, `combat-balance.md` R7). Motion agents have the final table.
8. **ui — `UIHelpers.rawAttributes` REACH bar** (FYI, sent to ui too): it ranks `max(mv.range)`. After the step-in,
   `range` alone no longer measures reach: Sierra 5.2, Goran 4.8, Rhys 4.65, Nia 4.55, Kael 4.4, Lumi 4.1, so the
   grappler would show the 2nd longest reach. Suggest `stats.preferredRange` (Sierra 4.4, Lumi 4.2, Rhys 4.0, Nia
   3.8, Kael 3.6, Goran 3.2; unchanged), or the threat range `mv.range + (mv.advance or 0)`. (Done by ui in round 2.)
9. **ui (optional, round 4)**: the lesson's throw-break step no longer needs `reset = true` to get a fighting dummy that
   grabs. Without it, my replica of `playLessonInSim` completes all ten steps for all six fighters. Keeping the reset
   is harmless: it restarts from neutral spacing.
