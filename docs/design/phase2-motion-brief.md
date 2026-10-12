# OV6 phase 2 — move animation brief (motionstrikes, motionkicks, motionthrows)

OV6 = `C:\Users\solim\.copilot\session-state\e3751321-5f48-4183-b62a-9577765df8cf\files\overhaul6`

The user played the current game and said the moves "look like crap, goofy and unrealistic". Every attack is still a
procedural pose generator (`CL.Motion.Strikes` / `CL.Motion.Kicks` / `CL.Motion.Throws`). Phase 2 replaces every
attack of all six fighters with real, weighty animation: motion capture where licensed data exists, careful
hand-keying where it doesn't. Three agents work in parallel, split by category across all fighters.

## 1. Read first (in this order)

1. `OV6\CONTRACTS-v6.md` — binding rules (originality, never steal focus, ownership, memory, tests, reporting).
2. `OV6\handoff\motioncore.md` — **CLIP PIPELINE READY spec** (authoritative): FLClip1 format, conversion and
   offline review tools in `OV6\tools\mocap\`, runtime API (`CL.Motion.ClipLibrary`, `CL.Motion.ClipPlayer`),
   how a clip binds to `fighter` + `move` key, contact-frame time warp, root-motion rule, throw two-role format.
   If something you need is missing, ask the integrator (REQUEST) — do not edit motioncore's files or tools; copy
   a tool into your own work folder if you must experiment.
3. `OV6\handoff\combat-states.md` — every fighter state and every move: key, input, height, impact frame
   (`startup + 1`), active, recovery, reach + root advance, flags, archetype and an **animation intent** sentence.
   Combat keeps regenerating it (keys can be renamed, e.g. Sierra's `SupermanPunch` is now `HopCross`); re-read it before your
   final export and never bind to a key that no longer exists. The live Roster is in
   `OV6\handoff\combat-src\ReplicatedStorage.FightingLab.Roster.luau` once combat exports it.
4. `OV6\research\motion\report.md` (§3 coverage, §4 retarget notes), `catalog.json` (263 licensed segments with
   contact frames and quality), `sheets\*.png` (contact sheets), `handoff\mocap-research.md`, and the raw data
   in `research\motion\raw\`.

## 2. Quality bar (what "looks real" means here)

- **Mocap first.** Use a catalog clip when one fits the intent (ACCAD/CMU/Quaternius only — the three accepted
  sources). Retarget with motioncore's tools. Mocap is usually slower than a fighting game: time-warp so the
  **contact pose lands exactly on the move's impact frame** and recovery fills the remaining frames, keeping the
  natural motion (no linear slow-motion look, no snapping).
- **Hand-keyed moves must read like mocap**: anticipation → weight transfer → hips and shoulders rotate into the
  strike → full extension at contact → retraction/follow-through → settle back into **that fighter's stance**
  (motioncore's `Clips.Core` stance for the fighter, so there is no pop at the blend). Kicks need a chamber,
  a pivot on the support foot (heel turns over on roundhouses), the support foot planted (no sliding), arms
  counter-balancing, head over the support base. The non-striking hand guards the chin.
- **No broken limbs.** Elbows/knees bend only the natural way and never hyper-extend; no limb passes through the
  torso; feet never go below the floor; hands/feet don't pop between frames. (The user previously complained the
  limbs "look broken" — this is a hard gate.)
- **Reach reads.** At the contact frame the striking hand/foot reaches the move's `reach` (± 10%, measured from the
  attacker's root along the fight line, after the sim's root `advance`), at the move's height (High = head,
  Mid = chest/stomach, Low = shin/knee), so hits visibly connect at the fighter's preferred range.
- **Root motion obeys motioncore's rule** — the sim already moves the root by `advance` during startup; never
  double it with clip translation; no cosmetic lunges that disagree with the sim.
- **Strings flow.** A follow-up (`stringIndex` 2/3) starts from the previous hit's contact/recovery pose. Review
  each whole string as one sheet.
- **Fast and sharp.** Modern 3D-fighter speed: a jab is a snap (impact frame 10), power moves have a visible
  wind-up. Never slow and floaty.
- **Fighter identity.** Each fighter's moves fit the stance and style in `combat-states.md` (KAEL boxer, SIERRA
  kickboxer, GORAN heavy brawler, LUMI acrobat, RHYS traditional karate, NIA fluid open-hand style). The same
  archetype on two fighters should still look like two different people (timing, guard, chamber height, weight).

## 3. Originality (hard rule)

Original moves only. No franchise characters, names, move names, signature or iconic poses (from games or films —
e.g. no one-legged "crane" wings pose, no recognisable signature throws or victory poses), no ripped or
reconstructed game animation. Generic martial-arts techniques (jab, teep, roundhouse, hip toss, suplex…) are fine.
Only CC0 / CC BY / CMU-terms data from the catalog — never Mixamo, never NC/ND/SA, never Bandai Namco or other game
data. Every clip carries `sources = {...}` (catalog ids such as `accad-male2-e1-jableft`, or `"handkey"`) and a
`-- sources:` header line, so the integrator credits only what is used.

## 4. Evidence (required per move) and tests

- An **offline contact sheet** per move (motioncore's review/render tool): ≥ 6 key frames including first frame,
  chamber/wind-up, the exact contact frame (mark it), recovery and last frame; front and side views; a reach line.
  For strings, one sheet per whole string. Look at every sheet yourself and fix what looks wrong.
- A **coverage table** in `OV6\handoff\<agent>.md`: fighter · move key · clip module · source(s) · contact error
  (frames, must be 0) · reach error % · max support-foot slide (cm) · joint-limit violations (must be 0).
- **Studio check** (memory permitting, see §5): burst captures of at least 10 representative moves in a real fight
  (practice pad or `FightingLabDuelDebug.startCpu`), and the full suite green.
- **Test** `ServerStorage.UnitTest.Cases.MotionMoves<Category>Coverage_Test`: every Roster move of your category,
  for every fighter, resolves to a clip from your subfolder; the clip's contact maps to `startup + 1`; `sources`
  is non-empty; channels decode without NaN.

## 5. Working rules

- One Studio at most, launched **only when ≥ 6 GB RAM is free** (`(Get-CimInstance Win32_OperatingSystem)
  .FreePhysicalMemory/1MB`); do the offline pipeline first (conversion + sheets need no Studio); close Studio when
  done. Launch minimized + `Show-StudioBehind.ps1` (never steal focus, never send OS keystrokes). Work folder
  `OV6\work\<agent>\`, Studio file `OV6\work\<agent>\FightingLab-<agent>.rbxlx` copied from `OV6\base`.
- Live sync: contract §3 (your port below). Load motioncore's latest `handoff\motioncore-src` and combat's
  `handoff\combat-src` into your Studio before testing your clips (later exports win; re-sync when they update).
- Exports: `OV6\handoff\<agent>-src\<Full.Roblox.Path>.luau` (UTF-8, LF, no BOM). Only your owned paths.
- Three move agents run in parallel — never write into another's subfolder. Runtime changes (ClipPlayer,
  ClipLibrary, MotionPlayer, CharacterPresenter) belong to motioncore: write `REQUEST: <file>: <change>` in your
  `handoff\<agent>.md` and report.
- SQL todos: only rows you create, prefixed with your agent name.
- **At most one phase-2 Studio at a time.** Right before launching, check memory again and check that no other
  `FightingLab-motionstrikes/-motionkicks/-motionthrows` Studio is open (`Get-Process RobloxStudioBeta` window
  titles); if one is, keep working offline and retry later. If memory never allows a Studio, finish with offline
  evidence and say so — the integrator runs the Studio check during integration.
- Questions about the clip runtime/tools: message motioncore (agent id `cb5c1953-1045-4747-97f1-401780d21d32`);
  about frame data/move keys: combat (`dc3543f3-785c-4fbf-8f38-22aedca04e9a`). Keep messages short and specific;
  never ask them to edit your files.

## 6. Assignments (from `combat-states.md`; a string clip belongs to the category of its own last button)

| agent | port | owns | moves |
|---|---|---|---|
| motionstrikes | 35305 | `CL.Motion.Strikes`, `CL.Motion.MoveAnimOverrides`, `CL.Motion.Clips.Moves.Strikes.*`, tests `MotionStrikes*`, `MotionMovesStrikes*` | 38 |
| motionkicks | 35307 | `CL.Motion.Kicks`, `CL.Motion.Clips.Moves.Kicks.*`, tests `MotionKicks*`, `MotionMovesKicks*` | 49 |
| motionthrows | 35308 | `CL.Motion.Throws`, `CL.Motion.Clips.Moves.Throws.*`, tests `MotionThrows*`, `MotionMovesThrows*` | 13 |

**Strikes (38):** KAEL Jab, OneTwo, LiverHook, Cross, CrossHook, Overhand, BodyBlow, RisingUppercut, WeaveHook,
ChargingCross · SIERRA Jab, Cross, DuckJab, HopCross · GORAN Jab, JabHammer, Hammer, DoubleHammer,
ShoulderTackle, Uppercut, CrouchJab, Haymaker, Bulldozer · LUMI Palm, SpinBackfist · RHYS Jab, ReversePunch,
StraightPunch, Deflect (parry), LowPunch, SpinBackfist, LungePunch · NIA Chop, DoubleChop, PalmThrust, RisingPalm,
Backfist, Elbow.
Mocap: jab/cross/hook/uppercut/body blows good (ACCAD E1–E16, CMU boxing 14_01); backfist `accad-male2-e12`.
Gaps to hand-key: overhand, hammer fists, elbows, palm strikes, chops, shoulder tackles, hopping cross, parry.

**Kicks (49):** KAEL ShinKick, LegKick, FrontKick, Roundhouse · SIERRA JabKick, Teep, TeepKick, HighRoundhouse,
DoubleRoundhouse, SpinningBackKick, KneeStrike, SwitchKick, LegKick, LowSweep, AngleKick · GORAN KneeLift, PushKick,
ClubKick, Stomp, LegHook · LUMI PalmHeel, SnapKick, SnapCrescent, CrescentKick, CartwheelKick, FlipKick, SlideKick,
QuickLow, ScissorKick, VaultKick, TwirlKick, KneeRush · RHYS PunchKick, FrontSnap, AxeKick, RisingKnee, LowSweep,
LowKick, SideKick, CrescentStep · NIA FlurryKick, PalmKick, RisingFrontKick, HighKick,
LowSpin, RisingTornado, ButterflyKick, LowSweep, TornadoKick.
Mocap: front/push, roundhouse high/mid, side kick, spinning back kick, reverse spin crescent good (ACCAD G1–G20,
CMU 135_04). Weak: knees (CMU 86_06). Gaps to hand-key: low kicks, sweeps, slide kick, stomp, cartwheel/flip/
butterfly/tornado/jumping kicks (credible airborne arcs; ask motioncore how clip root height is allowed).

**Throws (13):** KAEL Throw (clinch strike), ThrowB (hip toss) · SIERRA Throw (clinch knees), ThrowB (arm toss) ·
GORAN Throw (bear hug toss), ThrowB (slam), RamSlam (f+1+3, slam) · LUMI Throw (flip toss), ThrowB (arm toss) ·
RHYS Throw (hip toss), ThrowB (arm toss) · NIA Throw (arm toss), ThrowB (hip toss).
No two-person mocap exists under an accepted license: hand-key attacker + defender tracks synchronised to
`throw.frame` / `throw.duration` / `throw.impactFrame`, with a believable grab (hands on the defender's neck/arm/
waist, no gaps or interpenetration), lift/rotation, impact on the floor at `impactFrame`, and a defender end pose
that **matches motioncore's lying (Landing FaceUp/FaceDown) pose** so there is no pop and no floating. Also a short
**throw break** (both push apart back to stance). Single-person reference: ACCAD/CMU falls (`cmu-90_18`,
`quat-ual2-hit-knockback`) for the defender's fall.
