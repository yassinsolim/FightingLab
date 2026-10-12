# combat-balance.md — anti-cheese search, frame data and CPU numbers (OV6, combat agent)

All numbers come from the headless harness in `OV6\work\combat\harness\` (Lune 0.11, the real `RF.CombatSim`,
`RF.Roster` and `RF.CombatAI` modules, 60 Hz). "Before" = the OV5 baseline sources (`OV6\baseline-src`), "after" =
`OV6\handoff\combat-src` (now round 4). Re-run: `lune run exploit.luau <base|r1|new> all 8`,
`lune run stats.luau 24 [A B] [base]`, `lune run maxrange.luau`, `lune run behaviour.luau`, `lune run turtle.luau`,
`lune run beginner.luau Easy 16 seed=<n>`, `lune run cpuvs.luau <A> <B> 72`, `lune run testrun.luau "*" "<cases>"`,
`lune run lessonrepro.luau reset=0`, `lune run throwidle.luau throws=2 mode=wait|walk`.
`COMBAT_FIRST=<dir>` puts an A/B overlay dir (older modules) in front of the sources for any of these tools:
`OV6\work\combat\ab\round2` holds the round-2 `Roster` + `CombatAI`, `ab\round2-cpu` the round-2 `CombatAI` only,
`ab\round3` the round-3 `CombatAI` + `CombatSim`.
Raw outputs: `OV6\work\combat\exploit-base-all.txt`, `exploit-new-all-run.txt`, `stats-matrix.txt`, and for the
step-in round `OV6\work\combat\runs-stepin\` (`before-*` = round 2, `fallout-*` = step-in Roster + round-2 CPU,
`final-*` = this export).

## R4. Round 4: the CPU that stayed crouched (ui report) — latest

ui found it in Training with the dummy on Fight back: after the player threw it at close range, the dummy could stay
crouched for more than 2 minutes without attacking, with all six fighters (`UITutorial_Test`, seed 4242). The Versus
CPUs had the same lock (same brain). Raw outputs: `OV6\work\combat\runs-r4\` (`r3-*` / `before-*` = round 3,
`final\*` = this export). New tools: `lessonrepro.luau` (ui's lesson flow without its reset workaround),
`throwidle.luau` (land N throws, then wait or walk), and a passive-streak metric in `behaviour.luau`.

**Root cause (two bugs in `RF.CombatAI`, both fixed):**
1. **Perception counted one attack many times.** `AI.observe` computed a move's start as `frame - moveFrame + 1`.
   The move's frame counter stops during hitstop and during the whole throw (the throw has its own clock), so:
   - every blocked or landed attack was remembered twice;
   - a throw was remembered once per frame while the CPU watched it: the lesson log showed 6 of 6 "Throw" entries
     from a single throw.
2. **The reads built on that log never aged.** `throwStreak`, `lowStreak`, the crouch stance read, `ducks` and the
   spam read only looked at the last entries of the log, however old. So "two throws in a row" stayed true forever.
   - Whenever the player was in range, that kept the CPU "pressured": `pressure-guard` with a crouch, re-armed every
     12–26 frames, never attacking.
   - It only ended when the player attacked with something else.

**Fixes:**
- **Perception:** each fighter's move start is tracked across hitstop and throws (`moveStartOf`), so one attack is
  remembered once. A test proves this: a blocked jab and a landed throw are each logged once (round 3 logged the jab
  twice).
  - The double count had been part of every tuning round: a connecting attack weighed double in the pressure read.
  - To keep the accepted pace and pressure behaviour, an attack that connects (blocked, landed, grabbed) now
    explicitly counts twice in `rate`, while streak, spam and stance reads see each attack once.
- **Reads age on the opponent's free-time clock** (`foeClock`: frames it could act, so not while it lies on the
  floor after our punish):
  - only attacks from its last 240 free frames shape a read;
  - a low/throw streak is fresh for 120 free frames, and only while the player hasn't backed off or stepped for 45
    frames since;
  - habit counts also fade with time (half-life about 10 s);
  - the wake-up crouch guess uses the same window.
- **Nobody stays passive (all levels):**
  - A crouch held on a read ends after 72 frames (84 while a streak is fresh) without an attack from the opponent, and
    is not re-armed for 45 frames.
  - **Patience** (`Params.patience`: Easy 150, Normal 110, Hard 90 frames): this many neutral frames without an
    attack or a deliberate move, or 1.6× that in range without an attack, while the opponent is not attacking
    (nothing started for 40 frames), and the CPU acts whatever its reads say. In range it attacks; otherwise it steps
    in.
- **Wake-up guard:** while the opponent rises, the CPU holds its (low) guard where it stands instead of walking in
  standing.
- **Fight-back dummy:** switching the dummy to Fight starts a fresh brain (`Sim.setDummy`). It did not watch what
  happened while it stood or guarded.
- **Easy matchup table re-tuned for the corrected perception:** `vs` Kael 1.25, Lumi 1.0, Nia 1.2 (others unchanged).

| check | round 3 | round 4 |
|---|---|---|
| ui lesson, throw then Fight back (6 fighters, no reset) | **no attack in 120 s** for all six; 75–80 % of the time crouched, longest crouch 3.9–11.5 s | first attack 2.3–3.8 s, the dummy grabs and the break step completes in 4.6–29 s, longest crouch ≤ 0.9 s |
| 2 throws, then the player waits 10 s (Easy / Normal / Hard / dummy × 6 CPU fighters) | **0 attacks** at every level; longest crouch 10.0 s (Hard) | first attack or move ≤ 2.1 s, 3–10 attacks, longest crouch ≤ 1.4 s |
| 2 throws, then the player walks back and forth | first action up to 4.4 s, crouch up to 3.6 s | ≤ 1.9 s, crouch ≤ 1.2 s |
| 3 throws, then waits 20 s | — | ≤ 1.9 s, crouch ≤ 1.4 s |
| **longest passive streak**, CPU vs CPU, every pairing (free, in range of a standing opponent, no attack) Easy / Normal / Hard | **17.9 / 9.8 / 6.8 s** (p95 11.3 / 9.1 / 5.2) | **4.8 / 3.5 / 2.9 s** (p95 4.7 / 3.5 / 2.8) |
| longest unprovoked crouch, CPU vs CPU (opponent quiet for 40 f) | 1.9–2.1 s | 1.2 s |
| spam tail, 25 starters × 24 (vs Normal / Hard) | worst 17 % (Sierra LegKick) / 4 % | worst 12 % (Sierra LegKick, Rhys LowKick) / 4 %; Ram Slam 4 % / 0 % |
| full spam scan (8 per cell) | mean 0.8 / 0.2 % | mean 0.6 / 0.3 %, worst cell 1 of 8 |
| beginner vs Easy (384 per cell): beginner plays / Easy plays | 49–60 % / 42.5–63 %, overall 54.5 % | **47–65 % / 50–61 %, overall 56 %** |
| mash vs Easy / Normal / Hard (24 per cell) | 67 / 4 / 0 % | 62 / 1 / 1 % |
| CPU vs CPU (144 matches, sides alternate) | Normal beats Easy 89 %, Hard beats Normal 85 % | Normal beats Easy 88 %, Hard beats Normal 83 %, Hard beats Easy 96 % |
| pace, Normal vs Normal | 35–37 attacks/min, 38 s rounds | 39 attacks/min, 34 s rounds |
| max-range punishability | 15 × 6/6, DoubleHammer 5/6 | unchanged |
| juggle worst / wake-up / frame flags / edge | 34 % / 0 of 35 956 / 0 / OK | unchanged |
| crouch turtle / backdash run / jab pressure (vs Normal / Hard) | 10 / 0, 0 / 2, 0 / 0 % | 6 / 0, 0 / 2, 2 / 0 % |

What I tried and rejected:
- Fixing the perception alone, without weighting connected attacks: CPU vs CPU rounds dropped from 38 s to 23 s
  (48 attacks/min, nearly twice the hits). The CPU had stopped guarding after blocked attacks. Measured with A/B
  overlays that each turned off one fix; only the perception fix changed the pace.
- Aging reads on real time instead of the free-time clock: Ram Slam spam vs Normal rose 4 % → 17 %. The read expired
  while the spammer lay on the floor after a punish, so the CPU stopped ducking the next grab (360 grabs landed in
  48 matches instead of 276).

Tests (all pass headless, 126/127: the remaining case is the Studio-only FighterRig pose check):
- `CombatAI_Test` adds four cases. Each fails on the round-3 CPU:
  - "after landing throws on it, the CPU stands up and acts again" (Easy, Normal, Hard and the fighting dummy; every
    CPU fighter; the player waits or walks): first attack or deliberate move ≤ 3 s, no crouch longer than 1.5 s;
  - "old throw and low reads fade";
  - "one blocked attack or one throw is remembered once";
  - "CPU vs CPU: nobody stays in range for long without attacking" (≤ 6 s).
- `Difficulty_Test`: "levels are ordered" now plays 24 matches per pairing instead of 12; 12 left Normal vs Easy one
  unlucky seed from failing at 8/12, while it is 88 % over 144.

## R7. Step-in round (REQUEST 7)

Approved by the integrator: moves that visibly connected short get a real step-in. For each one, `advance` grows and
`range` shrinks by the same amount, so the threat range (`range + advance`) is unchanged. Keys, startup, active,
recovery, damage, on-block/on-hit and push are unchanged for every move. "Before" = the accepted round-2 export.

### R7.1 The table (57 moves)

Built from the motion agents' measurements (`harness\apply_stepin.py`, `work\combat\stepin-table.txt`):
- **tip** = the striking point (fist, palm, elbow, foot, knee, or torso corner for body charges) at the first active
  frame, in studs ahead of the sim root along facing, root fully advanced. motionstrikes measured on the real R15
  rigs; motionkicks measured its 60 fps clips offline.
- **new range** = tip + the defender's target surface: High 0.61 (head), Mid 0.47 (upper torso), Low 1.20 (front
  of the lead knee); knees +0.10 for the kneecap. Rounded to 0.05.
- **Floor 2.80** for knees and body charges (bodies touch at 2.60).
- Applied only where the range drops by at least 0.20. **New advance** = old threat range − new range.
- Every low kick stays as it was: the defender's lead knee sits about 1.0 stud ahead of their root.

| fighter | moves: old range + advance → new range + advance (threat range unchanged) |
|---|---|
| Kael | OneTwo 4.40+0.20 → 3.95+0.65 · Cross 4.40+0.20 → 3.60+1.00 · Overhand 4.40+0.60 → 3.60+1.40 · WeaveHook 4.00+0.40 → 3.70+0.70 · FrontKick 4.80+0.20 → 3.90+1.10 · Roundhouse 5.00+0.20 → 4.40+0.80 · ChargingCross 4.40+1.40 → 3.60+2.20 |
| Sierra | Jab 4.20+0.00 → 3.95+0.25 · JabKick 4.80+0.30 → 3.75+1.35 · Cross 4.40+0.20 → 3.80+0.80 · Teep 5.00+0.20 → 3.80+1.40 · HighRoundhouse 5.20+0.20 → 4.50+0.90 · DoubleRoundhouse 5.00+0.20 → 4.35+0.85 · SpinningBackKick 5.00+0.40 → 4.25+1.15 · KneeStrike 3.60+0.80 → 2.80+1.60 · SwitchKick 4.00+0.20 → 2.80+1.40 · HopCross 4.40+1.40 → 3.70+2.10 · AngleKick 4.80+0.20 → 3.25+1.75 |
| Goran | ShoulderTackle 3.80+1.20 → 2.80+2.20 · KneeLift 3.40+0.60 → 2.80+1.20 · PushKick 4.80+0.20 → 3.80+1.20 · Haymaker 4.20+0.30 → 3.95+0.55 · Bulldozer 3.80+2.00 → 2.80+3.00 |
| Lumi | Palm 4.20+0.00 → 3.95+0.25 · PalmHeel 4.60+0.30 → 3.50+1.40 · SpinBackfist 4.40+0.20 → 3.75+0.85 · SnapKick 4.60+0.20 → 3.80+1.00 · SnapCrescent 5.00+0.20 → 3.75+1.45 · CrescentKick 5.00+0.20 → 3.60+1.60 · CartwheelKick 4.60+0.60 → 3.70+1.50 · FlipKick 4.00+0.00 → 3.10+0.90 · TwirlKick 4.80+0.20 → 3.35+1.65 · KneeRush 3.60+0.80 → 2.80+1.60 · ScissorKick 4.40+0.80 → 3.50+1.70 · VaultKick 4.40+1.20 → 4.10+1.50 |
| Rhys | StraightPunch 4.40+0.20 → 3.80+0.80 · PunchKick 5.00+0.20 → 4.65+0.55 · FrontSnap 4.60+0.20 → 3.80+1.00 · AxeKick 4.60+0.30 → 3.25+1.65 · RisingKnee 3.60+0.30 → 2.80+1.10 · SpinBackfist 4.40+0.20 → 4.15+0.45 · LungePunch 4.20+1.40 → 3.65+1.95 · SideKick 5.00+0.30 → 3.85+1.45 · CrescentStep 4.60+0.20 → 4.25+0.55 |
| Nia | Chop 4.20+0.00 → 3.55+0.65 · DoubleChop 4.20+0.10 → 3.75+0.55 · FlurryKick 4.80+0.30 → 4.20+0.90 · PalmThrust 4.20+0.20 → 3.40+1.00 · PalmKick 4.60+0.20 → 3.80+1.00 · RisingFrontKick 4.60+0.20 → 3.60+1.20 · HighKick 5.00+0.20 → 4.55+0.65 · RisingTornado 4.40+0.20 → 3.10+1.50 · RisingPalm 3.90+0.20 → 3.20+0.90 · ButterflyKick 4.60+0.40 → 3.85+1.15 · Backfist 4.40+0.20 → 3.00+1.60 · Elbow 3.40+0.60 → 2.80+1.20 · TornadoKick 4.80+0.30 → 3.75+1.35 |

Motion sign-off:
- motionstrikes re-authored all 22 strikes with real step-ins. At the new ranges each one connects within 0.08 stud
  of the mean defender surface. Goran Shoulder Tackle now measures 2.34 + 0.47 = 2.81, exactly at the floor.
- motionkicks is rebuilding the 35 kicks and knees from this table. Nia Rising Tornado stays at 3.10 + 1.50: its
  polished tip reaches 0.15 further, which is within tolerance (agreed).
- The root motion the clips follow: the offset at moveFrame k is `advance × min(k − 1, startup) / startup` (the full
  advance on the first active frame). The attacker stops if the bodies meet and never shoves the defender.

### R7.2 Max-range punishability (`maxrange.luau`)

A step-in move ends `range` (not `range + advance`) away from the defender. So a move blocked at its maximum range
now leaves the attacker closer, and max-range punishes can only get easier. The unsafe moves (on block ≤ −13),
blocked at max range:

| move | on block | blocked at, before → after | punishable by (of 6), before → after |
|---|---|---|---|
| Sierra SwitchKick | −13 | 4.21 → **3.01** | 6 → 6 |
| Lumi FlipKick | −15 | 4.21 → **3.31** | 6 → 6 |
| Rhys RisingKnee | −13 | 3.81 → **3.01** | 6 → 6 |
| Nia RisingTornado | −15 | 4.61 → **3.31** | 6 → 6 |
| Nia RisingPalm | −14 | 4.11 → **3.41** | 6 → 6 |
| the other 10 launchers and power lows (no step-in) | −13…−18 | unchanged (3.50–4.11) | 6 → 6 |
| Goran DoubleHammer (2,2 ender) | −13 | 4.56, unchanged | 5 → 5 (not Goran himself; mirror only, accepted in round 1) |

Dynamic check (`exploit framedata`: the move is blocked, then the defender buffers its best answer): 0 flags before
and after. The best on-block advantage is still +1 (jabs only). The longest blockstun chain from repeating a plus move
is still 15 f.

### R7.3 Single-move spam tail (24 matches per cell, CPU character cycles)

The 19 round-2 tail starters, plus 6 more step-in or low starters from the new full scan. Columns: win rate vs
Normal / Hard.

| starter | before (round 2) | step-in Roster, round-2 CPU | after |
|---|---|---|---|
| Sierra LowSweep | 0 / 0 % | 4 / 0 % | 0 / 0 % |
| Kael RisingUppercut | 0 / 0 % | 0 / 0 % | 0 / 0 % |
| Rhys SpinBackfist | 0 / 4 % | 0 / 0 % | 0 / 0 % |
| Nia RisingPalm | 0 / 0 % | 0 / 0 % | 0 / 0 % |
| Goran RamSlam | 4 / 4 % | 4 / 0 % | 4 / 0 % |
| Rhys CrescentStep | 0 / 0 % | 0 / 0 % | 0 / 0 % |
| Nia LowSweep | 0 / 0 % | 0 / 0 % | 0 / 0 % |
| Goran ThrowB | 0 / 0 % | 0 / 0 % | 0 / 0 % |
| Goran Uppercut | 0 / 0 % | 0 / 0 % | 0 / 0 % |
| Rhys LowSweep | 0 / 0 % | 0 / 0 % | 0 / 0 % |
| Goran LegHook | 4 / 0 % | 8 / 0 % | 0 / 0 % |
| Sierra HighRoundhouse | 0 / 0 % | 0 / 0 % | 0 / 0 % |
| Kael BodyBlow | 0 / 4 % | 0 / 8 % | 0 / 0 % |
| Lumi SlideKick | 4 / 0 % | 0 / 0 % | 0 / 0 % |
| Kael ShinKick | 0 / 0 % | 0 / 0 % | 0 / 0 % |
| Sierra Teep | 0 / 0 % | 0 / 0 % | 0 / 0 % |
| Goran PushKick | 0 / 0 % | 0 / 0 % | 0 / 0 % |
| Sierra LegKick | 8 / 0 % | 17 / 0 % | **17** / 0 % |
| Rhys LowKick | 4 / 0 % | 4 / 0 % | 4 / 0 % |
| Nia LowSpin | 0 / 0 % | 0 / **12** % | 0 / 0 % |
| Goran Bulldozer | 0 / 0 % | 0 / 4 % | 0 / 4 % |
| Lumi ScissorKick | 0 / 0 % | 0 / 0 % | 0 / 0 % |
| Lumi VaultKick | 0 / 0 % | 0 / 0 % | 0 / 0 % |
| Goran ShoulderTackle | 0 / 0 % | 0 / 0 % | 0 / 0 % |
| Nia Backfist | 0 / 0 % | 0 / 0 % | 0 / 0 % |
| **worst** | **8 / 4 %** | **17 / 12 %** | **17 / 4 %** (targets 20 % / 10 %) |

- Full scan of every starter of every fighter (8 matches per cell): mean 0.3 / 0.0 % → **0.8 / 0.2 %**.
- The worst 8-match cells are 12 % (1 win in 8): Sierra LegKick vs Normal and Goran Bulldozer vs Hard. At 24 matches
  they are 17 % and 4 %.
- Sierra LegKick (a −13 low with no step-in) is 4 wins in 24 vs Normal, against 2 in 24 in round 2. That is within
  the noise of a 24-match cell (± 7 points) and inside the target.

### R7.4 CPU spacing sanity (`behaviour.luau`, CPU vs CPU at the same level, every pairing)

| level | out-of-range starts | launchers / throws (% of attacks) | sidesteps / min | dashes / min | walk-direction flips / s |
|---|---|---|---|---|---|
| Easy | 0 % → 0 % | 3.8 / 4.2 → 3.2 / 4.5 | 0.7 → 0.6 | 1.8 → 1.9 | 0.37 → 0.31 |
| Normal | 0 % → 0 % | 1.9 / 5.9 → 2.2 / 5.3 | 0.8 → 1.0 | 0.6 → 0.6 | 0.15 → 0.17 |
| Hard | 0 % → 0 % | 4.7 / 4.8 → 5.5 / 5.6 | 0.6 → 0.6 | 0.2 → 0.5 | 0.10 → 0.12 |

- "Out of range" = an attack started more than 0.6 stud beyond its threat range. The CPU measures reach as
  `range + advance` (`CombatAI.threatOf`), which the step-in left unchanged, so its spacing did not move.
- Ring edge: min distance 2.600 (separation 2.60), max radius 21.000, 0 NaN frames in CPU vs CPU. Jab pressure vs
  Normal and Hard: 0 % in the centre and 0 % with the CPU starting against the edge.

### R7.5 Fallout: step-ins bring attackers into grab range, so Easy was re-tuned

A step-in move now ends 0.25–1.55 studs closer than before when started from the same distance (until the bodies
touch), so after a block both fighters are often inside grab reach (3.2).
With the round-2 CPU, that made Easy far weaker against beginner-style play. Traced with `beginnerdetail.luau`
(the beginner bot vs Easy, 48 matches per fighter, grabs = throws that connected):

| | round 2 | step-in only | after |
|---|---|---|---|
| beginner's grabs on Easy | 1250 | **2459** | 1354 |
| … broken by Easy | 9 % | 8 % | **27 %** |
| share of the beginner's damage from throws | 33 % | **60 %** | 27 % |

Fixes, all in `RF.CombatAI` (no further Roster change):
- **Easy PARAMS:**
  - throw break attempt 0.18 → **0.50**; right break button 0.50 → **0.58** (Normal 0.55 × 0.60 stays above);
  - `turnTake` 0.23 → **0.30** (the per-fighter product stays capped at 0.38, below Normal's 0.40);
  - new **`crowdJab` = 1**. When the opponent has started at least 4 attacks in the last 2.5 s and stands inside grab
    reach + 0.2, Easy presses its fastest poke (at most once per 30 f) instead of only holding guard. A jab also beats
    a grab. Only real mashers trigger it: Normal and Hard CPUs start 1–3 attacks per 2.5 s. Normal and Hard have
    `crowdJab` = 0.
- **`CombatAI.Matchups.Easy`** re-tuned:
  - `vs` = Kael 1.0, Sierra 0.95, Goran 1.4, Lumi 0.6, Rhys 1.25, Nia 1.1;
  - `as` = Kael 0.85, Sierra 1.3, Goran 0.6, Lumi 1.2, Rhys 1.15, Nia 1.4;
  - new `crowdVs` = Goran 0 (his armored charges walk through jabs);
  - new `punishVs` = Goran ×4. Easy's block/whiff punish vs Goran becomes 0.40 / 0.32 (capped at 0.9 × Normal's,
    which a test checks).
- **All levels (bugs the same bots exposed):**
  - a high string follow-up is stopped (chance = readSkill) against an opponent who keeps ducking (`ducks` read);
  - while the CPU reads lows or grabs (`crouchRead`), it no longer "backs off" into a standing guard.

Beginner bot vs Easy per fighter (beginner's win rate). The after column pools 4 seed sets, so each cell is 384
matches. "Step-in only" is one seed set, 96 matches per cell.

| fighter | beginner plays it: round 2 → step-in only → **after** | Easy CPU plays it: round 2 → step-in only → **after** |
|---|---|---|
| Kael | 57 → 98 → **60 %** | 56 → 95 → **54.5 %** |
| Sierra | 49 → 93 → **49 %** | 53 → 95 → **58 %** |
| Goran | 52 → 70 → **55 %** | 52 → 90 → **42.5 %** |
| Lumi | 49 → 95 → **52.5 %** | 52 → 88 → **56 %** |
| Rhys | 51 → 97 → **54 %** | 47 → 90 → **52 %** |
| Nia | 53 → 98 → **55 %** | 52 → 94 → **63 %** |
| all | 52 → 92 → **54.5 %** | |

Every fighter is inside the 30–75 % target in both directions. The single 96-match runs span 35–67 % (round 2:
40–65 %).

What it cost (CPU vs CPU, A beats B with both sides played, 48 matches; then the 72-match `cpuvs.luau` check):

| pairing | round 2 | step-in only | after | after, `cpuvs` 72 |
|---|---|---|---|---|
| Normal beats Easy | 100 % | 92 % | **85 %** | 89 % |
| Hard beats Easy | 100 % | 100 % | **90 %** | 97 % |
| Hard beats Normal | 79 % | 81 % | **83 %** | 89 % |

Easy is still clearly the weakest level, but it now takes a match off Normal about 1 time in 8.

The masher bot (random buttons every few frames, a harsher test than the beginner): vs Easy 29 % → 86 % → **67 %**
(24 per cell: Kael 71, Sierra 58, Goran 38, Lumi 79, Rhys 79, Nia 75 %). vs Normal 0 → 3 → **4 %** (Goran 17 %, 4 of
24). vs Hard **0 %**. I left mash vs Easy here: there is no target for it, and Easy is meant to be beatable by
mashing. Raising Easy's reads and punishes further did lower it, but also brought Easy too close to Normal in CPU vs
CPU.

### R7.6 Other regression checks (after; round 2 in brackets)

- Juggle worst 34 % (34 %; cap 45 %). Wake-up: 0 unblockable in 35 956 (0). Frame-data flags 0 (0).
- Crouch turtle 10 / 0 % (8 / 0). Backdash run 0 / 2 % (0 / 4). Lead + run 0 / 2 % (0 / 4). Sidestep spam 0 / 0 %
  (0 / 0); sidestep invulnerable frames 0.
- Beginner bot vs Normal / Hard: 5 / 1 % (0 / 0) at 24 per cell.
- Tests: headless 122/123 (the remaining case is the Studio-only FighterRig pose check). `inputtest` 0 failures.
  New: `CombatRoster_Test` "step-in moves connect at body contact and keep their threat range". `CombatAI_Test`
  "Easy matchup adjustments touch only Easy" now also checks that Easy punishes less than Normal in every pairing
  and that only Easy mashes when crowded.

## 0. Round 2: the CPU as a general player meets it

Round-2 sources vs the accepted round-1 export (`r1`). Sections 1–5 below are updated to round 2 where numbers moved
(and to the step-in round where marked). The Easy matchup values in 0.1 are the round-2 ones; R7.5 has the current
values.

### 0.1 Beginner bot vs Easy, per fighter, both directions

Bot = `Bots.beginner`: walks in, and in range presses a random button (1/2/3/4/throw) every 8–20 frames, holding a
random direction (25 % forward, 10 % back, 15 % crouch). It never blocks on purpose. Command:
`lune run beginner.luau Easy 16 seed=<0|20000|50000|90000>` (`COMBAT_SRC=r1` for "before"). Each run plays every
pairing 16 times, so 96 matches per fighter per direction. The table pools 4 seed sets, so each cell is
**384 matches**. The range shows the lowest and highest single 96-match run.

| fighter | beginner plays it: before | after | Easy CPU plays it: before | after |
|---|---|---|---|---|
| Kael | 52 % (44–58) | **57 %** (53–65) | 53 % (47–60) | **56 %** (54–57) |
| Sierra | 40 % (34–43) | **49 %** (49–50) | 38 % (29–48) | **53 %** (48–57) |
| Goran | **77 %** (69–82) | **52 %** (50–54) | **29 %** (22–34) | **52 %** (48–55) |
| Lumi | 38 % (31–44) | **49 %** (46–51) | 46 % (39–52) | **52 %** (43–58) |
| Rhys | **29 %** (23–33) | **51 %** (45–54) | 39 % (33–44) | **47 %** (40–50) |
| Nia | **19 %** (16–23) | **53 %** (50–58) | 51 % (43–58) | **52 %** (48–56) |
| all | 43 % | **52 %** | | |

Target was 30–75 % per fighter in both directions. Every single 96-match run is now inside 40–65 %. In round 1,
three fighters were outside the target: Goran 77 %, Rhys 29 %, Nia 19 %.

**Why it was uneven.** Against a masher, almost all of Easy's damage came from counter-attacking right after
blocking (turn-taking): 60–75 % of it, traced by decision source with `AI.trace`. Easy stands in guard and blocks
~90 % of a masher's mids and highs, but it can't react to any low (its 36-frame perception is slower than every
low). So the result per fighter depended on how much of a masher's damage goes under the guard:
- Goran: 120 HP plus a 16-damage d+4 sweep.
- Kael and Lumi: d+4 knockdown sweeps.
- Nia: light mid/high strings, no d+4 sweep, and 95 HP.

**Fix (Easy only).** Normal and Hard are untouched by this part (`paramsFor` returns their shared tables).
- Easy `turnTake` 0.20 → 0.23.
- A per-fighter matchup table (`CombatAI.Matchups.Easy`) multiplies Easy's chance to counter-attack after blocking
  (`turnScale`).
- The product is capped so it stays below Normal (Easy ≤ 0.38, Normal 0.40); a test checks this.
- No frame data changed: no beginner trap was found, the kits simply differ for a masher.

| multiplier | Kael | Sierra | Goran | Lumi | Rhys | Nia |
|---|---|---|---|---|---|---|
| `vs` (the human plays it) | 1 | 0.85 | **1.6** | 0.85 | 0.8 | **0.6** |
| `as` (Easy plays it) | 1.05 | 0.9 | 0.8 | 1 | 0.9 | 1.2 |

Also tried and rejected:
- Guard drops under pressure: a 0.05 chance moved every fighter +25 points, and the spread stayed.
- Crouch guesses after taking lows: a crouching Easy eats mids, so it made Goran stronger (96–100 %).
- A rubber band on the round lead: too weak against Goran's lows, and visible when strong.

### 0.2 Single-move spam tail (24 matches per cell, CPU character cycles)

The 15 worst starters from the round-1 scan, plus the 4 worst cells that showed up in round-2 scans:

| starter | before vs Normal / Hard | after vs Normal / Hard |
|---|---|---|
| Goran RamSlam (f+1+3 command throw) | **29 %** / 0 % | 4 % / 4 % |
| Goran ThrowB (2+4) | **21 %** / 0 % | 0 % / 0 % |
| Sierra LowSweep | 8 % / **21 %** | 0 % / 0 % |
| Goran Uppercut | 0 % / **21 %** | 0 % / 0 % |
| Goran LegHook | 0 % / **21 %** | 4 % / 0 % |
| Kael BodyBlow | 0 % / **21 %** | 0 % / 4 % |
| Kael RisingUppercut | 0 % / **17 %** | 0 % / 0 % |
| Nia RisingPalm | 0 % / **17 %** | 0 % / 0 % |
| Rhys CrescentStep (ss+4) | 4 % / **17 %** (9 time-out rounds) | 0 % / 0 % |
| Rhys LowSweep | 4 % / **17 %** | 0 % / 0 % |
| Rhys SpinBackfist | 0 % / **12 %** | 0 % / 4 % |
| Nia LowSweep | 8 % / **12 %** | 0 % / 0 % |
| Lumi SlideKick | 0 % / **12 %** | 4 % / 0 % |
| Sierra HighRoundhouse | 0 % / 8 % | 0 % / 0 % |
| Kael ShinKick | 0 % / 4 % | 0 % / 0 % |
| Sierra Teep | 0 % / 0 % | 0 % / 0 % |
| Goran PushKick | 0 % / 0 % | 0 % / 0 % |
| Sierra LegKick | 0 % / 0 % | 8 % / 0 % |
| Rhys LowKick | 0 % / 0 % | 4 % / 0 % |
| **worst** | **29 % / 21 %** | **8 % / 4 %** (targets 20 % / 10 %) |

Full scan of every starter of every fighter (8 per cell): mean 1.5 % / 2.6 % → **0.3 % / 0.0 %**. The worst
cell is 12 % / 0 %, which is 1 win in 8 (Sierra LegKick; 8 % at 24 matches).

What the bots found and the fix (`RF.CombatAI`). These make Normal and Hard stronger; no frame data changed.
1. **Planned punishes were being overwritten.** A block punish is decided during blockstun and buffered. On the
   first free frame the turn-taking logic then replaced it with its fastest poke. Normal and Hard took their turn
   40–85 % of the time, so their launch punishes on blocked −14…−17 moves mostly became a jab. Fix: a buffered
   punish is now protected (`punishedFor`). Test: `CombatAI_Test` "a planned block punish comes out instead of a
   quick poke" fails without the fix (Hard Lumi launches a blocked Leg Hook ≥ 8/12).
2. **High pokes into crushing moves.** Rising launchers (high-crush frames) and crouching sweeps or body shots go
   under highs. After a plus hit the CPU kept jabbing, got crushed and was launched. Fix: a new `ducks` read
   (most recent attacks are crouching or high-crush moves). When attacking or taking its turn, the CPU then picks
   non-highs, with probability = readSkill.
3. **Low spammers mistaken for crouch turtles.** A sweep spammer is crouched most of the time, so the "crouch
   turtle → attack with mids" rule fired into the sweeps. Fix: a crouch turtle is now someone who crouches
   without attacking from there.
4. **Command-throw spam.**
   - A throw streak now counts as pressure, and the CPU crouches (ducks grabs) on that read.
   - Its wake-up crouch guess counts throws like lows: a whiffed throw on the getup was followed by a grab the
     moment the CPU stood.
5. **High spam (Spin Backfist).** The CPU used to attack out of its crouch read and trade into the i15 tracking
   high. It now stays down and lets `react` answer from the crouch. Also, against a busy opponent it only picks
   moves faster than their usual startup (−2 f, never stricter than i12).
6. **Max-range pokers (Crescent Step, ss+4).** After blocking a −7 kick out of reach, the CPU waited until time-out.
   It now steps in when it can arrive and hit before their usual next attack lands. The estimate uses its real
   turn-taking reach, its walk speed and the opponent's average attack lead time (sidestep/dash included). A naive
   step-in after any −5 made Teep spam win 62 %, so it is gated.
7. **Behind on health with less than 15 s left:** the CPU dashes or walks in instead of guarding out the clock.

### 0.3 Regression checks after round 2 (same harness)

- CPU vs CPU, 24 per pairing: Hard beats Normal 79 %, Normal beats Easy 100 %, Hard beats Easy 100 %
  (round 1: 67–83 / 96 / 96–100).
- Behaviour per level (Easy / Normal / Hard):
  - out-of-range starts 0 % / 0 % / 0 %;
  - launchers 3.8 % / 1.9 % / 4.7 % of attacks (Hard's extra launchers are block punishes);
  - sidesteps 0.6–0.8 per minute;
  - walk-direction flips 0.37 / 0.15 / 0.10 per second.
- Mash vs Easy / Normal / Hard: 29 / 0 / 0 %.
- Crouch turtle 8 / 0 %. Backdash run 0 / 4 %. Lead + run 0 / 4 %. Sidestep spam 0 / 0 %.
- Juggle worst 34 %. Wake-up 0 unblockable in 35 956. Frame-data flags 0. Ring edge OK.
- Tests: headless 121/122. The remaining case is the Studio-only FighterRig pose check, as in round 1.
  `inputtest` 0 failures.

## 1. Movement (contract 0.1)

| | before (OV5) | after (OV6) |
|---|---|---|
| hold W for 2 s | orbits 25.6 studs (156° around the opponent) at 12.8–14.5 studs/s | **one sidestep: 1.80 studs**, 16 f travel + 6 f recovery, then nothing more until W is pressed again |
| walk forward / back | 9.2–11.8 / 8.3–10.8 studs/s | 4.3–5.7 / 3.5–4.6 studs/s (per fighter) |
| dash | 22–28 studs/s burst, 13 f | 2.6–3.5 studs in 13–15 f, ease-out, attack cancel from f3 |
| backdash | (none: dash with moveX < 0) | 2.6–3.4 studs in 17–19 f (travel f1–14), chainable from f15 (~11.6 studs/s chained) |
| crouch | could crawl | stationary (`CrouchSpeed = 0`) |
| sidestep vs linear moves | n/a (orbit) | linear moves whiff a sidestep (`Whiff.evaded`); tracking/homing moves catch it; **0 invulnerable frames** (homing hook connects on every one of the 22 sidestep frames) |

## 2. Frame data

| | before | after |
|---|---|---|
| fastest jab | i8 (+1 / Nia +2) | **i10, +1 on block for all six** (Goran's heavy jab included) |
| best on-block advantage | +2 (Kael Overhand, Nia Chop) | **+1** (jabs only) |
| chip damage on block | 15 % | none (`BlockMultiplier 0`) |
| launchers | −13…−15, short to long range | −13…−15, all **punishable at their maximum range by all 6 characters** (`maxrange.luau`; step-in round: unchanged, blocked-at distances only shrank, R7.2) |
| power lows (KND) | long range (≤ 5.2), big push → effectively safe at range | −16…−18, range 3.4–4.0 + root advance, push 0.3 → **punishable at max range by 6/6** |
| quick lows | i12–13, −11/−12 at 4.2–4.8 range | same frames, range 4.0, push 0.3 → punishable by every jab at max range |
| root advance (step-in) | cosmetic lunges | real sim movement during startup; **57 moves step in** (REQUEST 7, R7.1) with the threat range `range + advance` unchanged |
| whiffed throw | 26 f recovery | 34 f (36 Ram Slam): a ducked/whiffed grab is punishable |
| throw reach | 2.65 (bodies touching) | 3.2 (close range, still shorter than every jab) |
| frame-data flags (`exploit framedata`: move blocked, defender buffers its best answer) | — | **0** |
| longest blockstun chain from repeating any plus move | — | 15 f (no lock; lock threshold 120 f) |

Only exception: Goran's own `DoubleHammer` (2,2 string ender, −13) is not punishable by Goran himself at max range
(5/6 characters punish it) — mirror only, accepted.

## 3. Exploit search (contract 0.8) — bot win rate vs the CPU

8 matches per cell (best of 3), CPU character cycles through the roster.

| exploit | before vs Normal / Hard | after vs Normal / Hard | fix |
|---|---|---|---|
| spam one move (every starter of every fighter, mean) | **59 % / 48 %**, worst 100 % / 100 % (Kael Cross, Kael BodyBlow) | round 1: 1.5 % / 2.6 %, worst 38 % / 25 %; round 2: 0.3 % / 0.0 %, worst 12 % / 0 %; **step-in round: 0.8 % / 0.2 %**, worst 12 % / 12 % (8-match cells; tail at 24 matches: 17 % / 4 %, R7.3) | CPU reads repeated moves (`recent` attack log, spam key, low/throw streaks, crushing-move `ducks` read), punishes blocked and whiffed moves with the right tool (buffered punish protected), takes its turn after blocking minus moves, ducks repeated grabs and punishes the whiff |
| mash random buttons | Easy 86 %, **Normal 92 %**, Hard 47 % | round 2: Easy 29 %, Normal 0 %, Hard 0 %; **step-in round (24 per cell): Easy 67 %, Normal 4 %, Hard 0 %** (R7.5) | real guard (standing = guard), punishes, no chip, slower jabs |
| beginner bot (walks in, random buttons in range, never blocks on purpose) | — | round 1: Easy 46 % (Kael 75 %, Goran 100 %, Nia 12 %, 8-match cells); round 2: Easy 52 %, every fighter 49–57 % both directions; **step-in round: Easy 54.5 %, every fighter 42.5–63 % both directions (384 matches each, R7.5)**, Normal 5 %, Hard 1 % | Easy fidgets forward instead of standing in guard, rarely punishes; per-fighter Easy matchup table; Easy breaks grabs and jabs back when a masher crowds it (R7.5) |
| jab pressure (centre / CPU against the edge) | Normal **89 % / 92 %**, Hard 67 % / 61 % | Normal 0 % / 0 %, Hard 0 % / 0 % | +1 jab, CPU interrupts walk-ins, ducks repeated highs, duck counters |
| crouch turtle (holds down, random lows/crouching moves) | 19 % / 31 % | 10 % / 0 % | CPU goes for mids against croucher habits (counts crouching moves too), throws only standing opponents |
| sidestep spam | 0 % / 3 % | 0 % / 0 % | discrete steps, homing moves |
| backdash run | 0 % / 0 % (41 / 24 time-out rounds) | 0 % / 2 % (28 / 16 time-out rounds of ~100) | CPU chases runners with dashes |
| take the lead, then run | — | 0 % / 2 % | as above |
| one power low forever (LegHook/LowSweep/SlideKick) | up to 100 % vs Normal | round 1 ≤ 25 %; round 2 ≤ 4 % / 0 %; **step-in round 0 % / 0 %** (24-match cells) | shorter range + small push (punishable), wake-up low guard, low-streak read, punish decided during blockstun and protected until it comes out |
| throw spam (after the reach change) | — | was 100 % vs Normal; round 1 ≤ 25 %; round 2 RamSlam 4 % / 4 %, ThrowB 0 % / 0 %; **step-in round RamSlam 4 % / 0 %, ThrowB 0 % / 0 %** | 34 f whiff recovery, CPU ducks repeated grabs and whiff-punishes, throw streak counts as pressure, wake-up crouch counts throws |
| standing turtle (never attacks) — time for Hard to KO | 46 s average (mostly mids into the guard) | **26 s** (lows and throws ≥ 30 %; step-in round 25.6 s) | "they only block" read shifts the CPU to lows/throws |
| juggles (beam search, every move × timing after every launcher) | — | worst **34 %** of the smallest health bar (cap 45 %); max 4 air hits, 4th forces knockdown, 0.7 × 0.82ⁿ scaling | |
| wake-up / okizeme | — | **0 unblockable setups in 35 956** move × timing tests (every knockdown move, every follow-up, delays 0–100 f, stand vs crouch wake-up): Landing (34 f) and Getup (26 f, +10 rolls) are invulnerable, the first free frame guards, back/side rolls; the CPU also learns wake-up attack habits and waits in guard for them | |
| throw loops | — | a throw knocks down → invulnerable getup; throws cannot grab lying, rising, hit- or blockstunned fighters; break = 16 f shared lock then neutral (nobody plus) | |
| ring edge | min distance **2.533** (overlap, separation 2.6) | min 2.600, max radius 21.000, 0 NaN frames in CPU vs CPU | `keepApart` after every root motion, radius clamp |

## 4. CPU vs CPU (24 matches per pairing, all characters)

| A vs B | before: A wins / avg round | after: A wins / avg round |
|---|---|---|
| Hard vs Normal | 54 % / 7.9 s | round 1 67–83 %; round 2 79 %; **step-in round 79 %** / 36 s (both sides: 83 %) |
| Normal vs Easy | 83 % / 7.2 s | round 1 96 %; round 2 100 %; **step-in round 88 %** / 40 s (both sides: 85 %) |
| Hard vs Easy | 88 % / 7.9 s | round 1 96–100 %; round 2 100 %; **step-in round 83 %** / 34 s (both sides: 90 %) |

The step-in round's Easy changes (R7.5) cost Easy's distance to Normal: Easy now takes a match off Normal about 1
time in 8. The 72-match `cpuvs.luau` check: Normal beats Easy 89 %, Hard beats Easy 97 %, Hard beats Normal 89 %.

Knockdowns now take 34 f on the floor + 26 f to stand (1.0 s, motioncore request) — all numbers in this file were re-measured after that change.

Behaviour per fighter per minute (after; before in brackets, Normal vs Normal):
attacks 34–38 (84–89) · hits 8–10 (44–48) · **blocks 20–22 (0)** · whiffs 1.4–1.8 (9–10) · throws 0.8–1.0 (0) ·
throw breaks 0.3–0.4 (0) · sidesteps 0.8–1.3 · dashes 0.1 (7–8) · backdashes 0.3 · walk-direction flips 9 (13–16;
Easy 21, Hard 5–7) · attacks started out of range 0 % (CPU vs CPU, all levels; test limit 6 %) · launcher share
1.7–3.6 % of attacks in round 1, 1.9–4.7 % in round 2, 2.2–5.5 % in the step-in round (Hard's extra launchers are
block punishes that used to be overwritten; test limit 12 %) · throws 5–6 % of attacks.

## 5. CPU difficulty parameters (`RF.CombatAI` PARAMS)

| | Easy | Normal | Hard |
|---|---|---|---|
| reaction delay (f) | 36–42 | 22–26 | 14–16 |
| decision interval (f) | 24–46 | 16–34 | 12–26 |
| guard discipline / stands in guard when idle | 0.25 / 0.25 (fidgets forward) | 0.70 / 0.90 | 0.90 / 1.0 |
| low reaction / reads (habits) | 0.20 / 0.15 | 0.55 / 0.55 | 0.85 / 0.85 |
| block punish / whiff punish | 0.10 / 0.08 (vs Goran 0.40 / 0.32; always below 0.9 × Normal's) | 0.50 / 0.40 | 0.85 / 0.70 |
| counter-attack after blocking a minus move (turnTake) | 0.30 × per-fighter matchup multiplier (`vs` × `as`, 0.57–1.96, capped at 0.38; R7.5, `vs` re-tuned in R4) | 0.40 | 0.55 |
| juggle hits after a launcher | 1 | 2 | 3 |
| throw break attempt × right button | 0.50 × 0.58 | 0.55 × 0.6 | 0.75 × 0.8 (reacts to the grab) |
| jabs back when a masher crowds it inside grab reach (`crowdJab`) | 1 (not vs Goran) | 0 | 0 |
| patience: neutral frames without an attack or move before it must act (in range: ×1.6 without an attack; round 4) | 150 (2.5 s) | 110 (1.8 s) | 90 (1.5 s) |
| decision noise | 0.45 | 0.15 | 0.06 |
| hit-confirms strings | no | no | yes |

Measured: Hard crouch-blocks a reactable i20 low ≥ 18/25 (Easy ≤ 8/25); punishes a blocked −14 launcher ≥ 18/30
(Normal in between, Easy ≤ 12/30); Hard turns a launcher into a ≥ 3-hit juggle ≥ 12/16.
