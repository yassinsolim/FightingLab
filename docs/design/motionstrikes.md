# motionstrikes handoff — 38 punch-type move clips (OV6 phase 2)

Owner: motionstrikes. Exports: `OV6\handoff\motionstrikes-src\` (UTF-8, LF, no BOM):
- 38 × `ReplicatedStorage.FightingLab.Client.Motion.Clips.Moves.Strikes.Strike_<Fighter>_<Key>.luau` (FLClip1, one per
  roster move; `fighter` + `move` (+ `stringIndex` for string hits) bind them through `ClipLibrary`).
- `ServerStorage.UnitTest.Cases.MotionMovesStrikesCoverage_Test.luau` (5 tests).
- `Client.Motion.Strikes` and `Client.Motion.MoveAnimOverrides` are **unchanged**. The procedural strikes stay the
  fallback for any move that has no clip; every punch-type move now has one, so the clips are what plays.

cliplint: `38 modules, 153.5 KB (budget 2048 KB) OK`. Studio suite (all merged exports in `OV6\handoff\*-src`
incl. motioncore's round-5 runtime of 01:11, run on exactly this export): `[SUMMARY] 357 run, 356 passed, 1 failed`.
The failure is motionkicks' `MotionMovesKicksCoverage_Test` ("Lumi.PalmHeel starts at Palm's chain pose (gap 0.689
studs)"): the feet passes had to move the Lumi Palm and Nia DoubleChop cancel poses (approved by the integrator;
deltas in "Feet pass round 2"). It clears once motionkicks rebuilds PalmHeel and FlurryKick from this export.

Feet pass round 2 (final export 02:16): 34 of the 38 clips re-exported (unchanged: Goran CrouchJab, Hammer, JabHammer,
Sierra HopCross). Round 1 (01:08) is kept below as history.

## How the clips are made

Offline pipeline in `OV6\work\motionstrikes\` (no Studio needed). `python run.py [Fighter_Key ...]` rebuilds everything:
`src\`, `metrics\<F>_<K>.json`, `sheets\<F>_<K>.png`. `python string_sheet.py` makes the string sheets, and
`python coverage_table.py --stats` prints the table below.

1. **Source motion.** ACCAD Male2 mocap from the catalog (CC BY 3.0) is retargeted to the clip format: jab, cross,
   hooks, uppercuts, body jab, block. Moves no catalog clip fits (hammer fists, the shoulder tackle, spins) are
   hand-keyed (`original:motionstrikes`) on top of mocap frames or keyed from scratch. Every clip starts and ends on
   motioncore's exact displayed stance (`Displayed:<Fighter>`, §12, yaw/guard/width included). String hits start on
   the previous hit's cancel pose (startup+active+1).
2. **Real-rig calibration.** `rig.py` is a line-by-line replica of `ClipPlayer.sample` + `MotionPlayer.apply`: torso
   FK, the posed shoulder pivot, arm/leg IK, the measured contact aim, sole/ankle placement. It runs on the six
   **real** fighter rigs dumped from Studio (`studio\rigdump.json`, `studio\stance.json`). Studio agrees with the
   replica to about 0.1 stud (`studio\probe_new_runtime.json`). For every move, at the move's **max range**
   (`range`, after the sim root's full `advance`) against the mean defender:
   - the striking fist/palm/elbow lands on its spot on the body surface (head front, chest, collarbone, liver side,
     temple...);
   - the contact pose is exactly on the first active frame;
   - the guard hand stays at the chin, and no joint bends backwards or hyper-extends;
   - no limb passes through the torso, and planted feet stay put in the world while the sim root advances.
3. **No fake reach.** Only natural reach layers are used (pelvis shift ≤ 0.10–0.15 leg lengths, lean ≤ 5°, turn ≤ 14°).
   Arm extension is capped at 0.985 of the arm, so elbows are never straightened past natural. Moves that could not
   connect at their old range got a **real step-in** from combat instead (REQUEST 7 table, 22 strikes; applied in
   combat's Roster 21:20/21:44 and verified identical to what the clips were built against). The lead foot steps
   during startup, un-planted while it travels, then the rear foot follows. The clip stays in place horizontally, and
   the sim moves the root by `advance` (motioncore §4).
4. **Keep-out pass (new in the final build).** Before and after the hit, the fist must not pass through the defender:
   - on the approach (root still short by the rest of `advance`), it keeps the contact's own standoff from the
     defender's head/chest/pelvis;
   - hooks, hammers and backfists stop at the impact point instead of driving on through the body;
   - the contact pose and the string cancel poses are unchanged (bit-identical contact target).
   This changed 7 clips: Goran Hammer/JabHammer/Uppercut, Kael LiverHook/CrossHook, Nia Backfist/Elbow.
5. **Contact aim.** Aimed clips carry `tags.aimWeight = 0.25`, baked so the hit lands on the spot with motioncore's
   measured aim at that weight. Deflect (parry) is `aim = false`, and the body charges don't aim.

6. **Feet pass** (`feetfix.py`, run inside every rebuild, after the foot re-anchoring). It works on the real-rig leg
   geometry of the round-4 runtime (lockFoot, flat/heel-up/tiptoe floor solve, two-bone reach clamp), replicated in
   `feet_rt2.py` and checked against Studio:
   - touch-down/lift-off frames (0.5 ≤ contact < 0.8) rest the clip foot on the floor;
   - rear-foot lifts are follow-steps of at most 5 sim frames above 0.02 stud and at most 0.22 stud high; longer
     lifts lose their low tails, and a lift that cannot be shortened that way becomes a slide on the floor. Lead-foot
     step arcs are only scaled down to 0.22 stud;
   - a trailing foot the leg cannot reach is dragged forward (world space, never backwards) just enough. On the floor
     it slides on its ball with contact 0, and the runtime raises the heel as far as the straight leg needs. In a
     move whose root travels (`advance` ≥ 0.2), the planted rear foot may start this drag during startup/active;
   - any planted foot that still cannot reach lowers the pelvis (more knee bend), eased over ±4 frames;
   - start/end poses and the three locked cancel poses never change.
7. **Steps and end swings (feet pass round 2).**
   - `finish.reanchor`: the step into an implicit end plant (and out of an implicit start plant) gets at least
     max(4, distance / 0.15 stud) clip frames; the neighbouring plant is cut short and released (contact 0). Before,
     a foot still planted on the second-to-last frame jumped to the stance on the last one (Kael CrossHook: lead
     foot 0.86 stud in one sim frame, pelvis 0.5 stud).
   - `feetfix.shape_steps`: a released foot (contact < 0.5) is off the floor only while it travels in the world
     (sim advance included). Its lift follows the progress along the step, h = H·sin(π·u) with u = distance
     covered / step length and H ≤ 0.25 × step length (≤ 0.22 stud, ≤ the authored peak), so it comes down as it
     slows and never hangs. A released foot at rest sits on the floor, and plants (contact 1) if it used to hang
     there. A slide on the floor faster than 0.25 stud/frame becomes a low step; a short slow step (< 0.4 stud,
     < 0.06 stud/frame) shuffles on the floor. Rear-foot steps stay ≤ 5 lifted sim frames (lead steps ≤ 14),
     except the spinning foot of the two spin backfists (≤ 12: the turn is the step). Then the drag/sink run
     again, so every foot the step lowered is still reachable.

## Coverage table

Columns:
- *contact err*: frames between the first active frame and the real-rig contact pose (closest approach of the striking
  point to its spot), as the game plays the warped clip.
- *reach err %*: how far the striking point stops from the defender's body surface at the move's max range, as % of
  that distance (0 = touching; + = past the surface).
- *literal reach %*: fist centre vs `range` from the root, the brief's literal metric. It is −15…−27% by construction:
  `range` is root-to-root, so a fist that touches the face sits about head depth + half a fist (≈0.6–0.9 studs)
  short of the opponent's root.
- *gap*: studs short of the surface (0.00 = touching).
- *dy / lat*: vertical and lateral miss vs the spot.
- *slide*: largest planted-foot drift in the world in the clip on the real-rig replica, before the runtime foot lock.
- *violations*: elbow/knee direction, hyper-extension, limb-through-torso, foot under floor.

| fighter | key | clip module (`Clips.Moves.Strikes.`) | source(s) | contact err (frames) | reach err % (real rig, to body surface) | literal reach % (fist centre vs range) | gap at range (studs) | dy / lat (studs) | max foot slide (cm) | joint violations | range + adv |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Kael | Jab | Strike_Kael_Jab | accad-male2-e1-jableft | 0 | -0.1 | -20.6 | +0.01 | -0.01 / +0.00 | 0.2 | 0 | 4.20 + 0.00 |
| Kael | OneTwo | Strike_Kael_OneTwo | accad-male2-e4-crossright | 0 | +0.8 | -21.1 | -0.03 | -0.01 / +0.01 | 1.9 | 0 | 3.95 + 0.65 (step-in) |
| Kael | LiverHook | Strike_Kael_LiverHook | accad-male2-e10-bodyhookright | 0 | -0.1 | -14.7 | +0.00 | -0.00 / +0.00 | 0.4 | 0 | 3.90 + 0.30 |
| Kael | Cross | Strike_Kael_Cross | accad-male2-e4-crossright | 0 | +0.1 | -23.8 | -0.00 | -0.01 / +0.02 | 1.1 | 0 | 3.60 + 1.00 (step-in) |
| Kael | CrossHook | Strike_Kael_CrossHook | accad-male2-e6-hookright | 0 | -0.1 | -14.8 | +0.00 | +0.00 / +0.00 | 0.5 | 0 | 3.90 + 0.20 |
| Kael | Overhand | Strike_Kael_Overhand | accad-male2-e4-crossright, hand-key | 0 | +0.2 | -23.7 | -0.00 | -0.01 / +0.00 | 1.3 | 0 | 3.60 + 1.40 (step-in) |
| Kael | BodyBlow | Strike_Kael_BodyBlow | accad-male2-e7-uppercutleft | 0 | +0.2 | -18.8 | -0.01 | +0.00 / +0.00 | 1.4 | 0 | 3.80 + 0.30 |
| Kael | RisingUppercut | Strike_Kael_RisingUppercut | accad-male2-e7-uppercutleft | 0 | -0.2 | -18.7 | +0.01 | -0.00 / +0.01 | 0.4 | 0 | 3.90 + 0.30 |
| Kael | WeaveHook | Strike_Kael_WeaveHook | accad-male2-e6-hookright | 0 | -1.1 | -20.1 | +0.03 | +0.00 / +0.00 | 0.8 | 0 | 3.70 + 0.70 (step-in) |
| Kael | ChargingCross | Strike_Kael_ChargingCross | accad-male2-e4-crossright | 0 | -0.2 | -20.2 | +0.01 | -0.00 / +0.01 | 2.8 | 0 | 3.60 + 2.20 (step-in) |
| Sierra | Jab | Strike_Sierra_Jab | accad-male2-e2-jabright | 0 | -0.1 | -21.8 | +0.00 | -0.00 / +0.00 | 0.6 | 0 | 3.95 + 0.25 (step-in) |
| Sierra | Cross | Strike_Sierra_Cross | accad-male2-e3-crossleft | 0 | -0.2 | -22.7 | +0.00 | -0.01 / +0.01 | 1.5 | 0 | 3.80 + 0.80 (step-in) |
| Sierra | DuckJab | Strike_Sierra_DuckJab | accad-male2-e16-bodyjableft | 0 | +0.2 | -18.9 | -0.01 | +0.00 / +0.00 | 0.3 | 0 | 3.80 + 0.00 |
| Sierra | HopCross | Strike_Sierra_HopCross | accad-male2-e3-crossleft, hand-key | 0 | +0.0 | -23.2 | -0.00 | -0.00 / -0.00 | 5.3 | 0 | 3.70 + 2.10 (step-in) |
| Goran | Jab | Strike_Goran_Jab | accad-male2-e1-jableft | 0 | -0.1 | -19.6 | +0.00 | +0.00 / -0.00 | 0.2 | 0 | 4.40 + 0.00 |
| Goran | JabHammer | Strike_Goran_JabHammer | accad-male2-e3-crossleft, hand-key | 0 | -0.3 | -15.8 | +0.01 | -0.01 / +0.00 | 0.9 | 0 | 4.00 + 0.20 |
| Goran | Hammer | Strike_Goran_Hammer | accad-male2-e3-crossleft, hand-key | 0 | +0.0 | -15.5 | -0.00 | -0.01 / +0.00 | 0.9 | 0 | 4.00 + 0.20 |
| Goran | DoubleHammer | Strike_Goran_DoubleHammer | hand-key | 0 | -0.0 | -15.6 | +0.00 | -0.00 / -0.00 | 0.5 | 0 | 4.00 + 0.30 |
| Goran | ShoulderTackle | Strike_Goran_ShoulderTackle | hand-key | 0 | +0.4 | -16.5 | -0.01 | +0.00 / +0.96 | 1.3 | 0 | 2.80 + 2.20 (step-in) |
| Goran | Uppercut | Strike_Goran_Uppercut | accad-male2-e7-uppercutleft | 0 | +0.3 | -18.3 | -0.01 | +0.02 / +0.00 | 2.1 | 0 | 3.90 + 0.20 |
| Goran | CrouchJab | Strike_Goran_CrouchJab | accad-male2-e16-bodyjableft | 0 | +0.3 | -19.8 | -0.01 | +0.00 / -0.00 | 2.1 | 0 | 3.60 + 0.00 |
| Goran | Haymaker | Strike_Goran_Haymaker | accad-male2-e5-hookleft | 0 | +0.0 | -17.9 | -0.00 | +0.00 / -0.00 | 1.1 | 0 | 3.95 + 0.55 (step-in) |
| Goran | Bulldozer | Strike_Goran_Bulldozer | hand-key | 0 | -0.2 | -17.0 | +0.00 | +0.00 / -0.19 | 1.4 | 0 | 2.80 + 3.00 (step-in) |
| Lumi | Palm | Strike_Lumi_Palm | accad-male2-e1-jableft | 0 | -1.0 | -20.1 | +0.04 | -0.02 / +0.01 | 0.3 | 0 | 3.95 + 0.25 (step-in) |
| Lumi | SpinBackfist | Strike_Lumi_SpinBackfist | hand-key | 0 | -0.0 | -18.9 | +0.00 | -0.01 / -0.01 | 1.6 | 0 | 3.75 + 0.85 (step-in) |
| Rhys | Jab | Strike_Rhys_Jab | accad-male2-e2-jabright | 0 | +0.1 | -20.4 | -0.00 | -0.00 / +0.00 | 0.4 | 0 | 4.20 + 0.00 |
| Rhys | ReversePunch | Strike_Rhys_ReversePunch | accad-male2-e3-crossleft | 0 | +0.1 | -16.3 | -0.00 | -0.00 / -0.00 | 0.3 | 0 | 4.40 + 0.20 |
| Rhys | StraightPunch | Strike_Rhys_StraightPunch | accad-male2-e3-crossleft | 0 | +0.1 | -19.0 | -0.00 | +0.00 / +0.00 | 0.7 | 0 | 3.80 + 0.80 (step-in) |
| Rhys | Deflect | Strike_Rhys_Deflect | accad-male2-e16-blockrightmiddle | 0 | n/a | -24.3 | n/a | n/a / n/a | 0.3 | 0 | 2.60 + 0.00 |
| Rhys | LowPunch | Strike_Rhys_LowPunch | accad-male2-e16-bodyjableft | 0 | +0.0 | -19.0 | -0.00 | +0.00 / +0.00 | 0.3 | 0 | 3.80 + 0.00 |
| Rhys | SpinBackfist | Strike_Rhys_SpinBackfist | hand-key | 0 | -0.2 | -17.3 | +0.01 | -0.00 / +0.00 | 1.7 | 0 | 4.15 + 0.45 (step-in) |
| Rhys | LungePunch | Strike_Rhys_LungePunch | accad-male2-e3-crossleft | 0 | +0.1 | -19.7 | -0.00 | +0.00 / -0.00 | 1.4 | 0 | 3.65 + 1.95 (step-in) |
| Nia | Chop | Strike_Nia_Chop | accad-male2-e1-jableft, hand-key | 0 | +0.2 | -22.7 | -0.00 | -0.01 / +0.00 | 0.9 | 0 | 3.55 + 0.65 (step-in) |
| Nia | DoubleChop | Strike_Nia_DoubleChop | accad-male2-e3-crossleft, hand-key | 0 | -0.3 | -21.8 | +0.01 | +0.00 / +0.00 | 0.9 | 0 | 3.75 + 0.55 (step-in) |
| Nia | PalmThrust | Strike_Nia_PalmThrust | accad-male2-e3-crossleft | 0 | -0.1 | -18.4 | +0.00 | +0.00 / +0.00 | 0.9 | 0 | 3.40 + 1.00 (step-in) |
| Nia | RisingPalm | Strike_Nia_RisingPalm | accad-male2-e7-uppercutleft | 0 | -0.1 | -19.5 | +0.00 | -0.00 / +0.00 | 1.2 | 0 | 3.20 + 0.90 (step-in) |
| Nia | Backfist | Strike_Nia_Backfist | accad-male2-e3-crossleft, hand-key | 0 | -0.4 | -27.3 | +0.01 | -0.00 / -0.00 | 2.6 | 0 | 3.00 + 1.60 (step-in) |
| Nia | Elbow | Strike_Nia_Elbow | accad-male2-e1-jableft, hand-key | 0 | -0.4 | -20.8 | +0.01 | -0.01 / -0.01 | 4.2 | 0 | 2.80 + 1.20 (step-in) |

Summary (final export, 02:16):
- contact error 0 on all 38;
- joint violations 0;
- |gap| ≤ 0.04 stud (reach err within ±1.1%). Lumi Palm is the +0.04 (0.035): it uses its full 1.5× reach-layer
  cap; the deeper round-2 knee bend took 0.035 of its reach. Everything else is within ±0.03;
- |dy| ≤ 0.02 stud;
- max slide 5.3 cm (clip, before the runtime foot lock);
- stance/string start and end gaps 0 cm;
- worst hand speed 0.54 L/frame (Lumi SpinBackfist whip); Kael CrossHook 0.42, LiverHook 0.39 L/frame.

ShoulderTackle's lat +0.96 is intended: the lead shoulder, not the body centre, meets the chest.

## Strings, step-ins, shared poses

- String sheets (whole string as one game timeline): `sheets\STRING_Kael_Jab_OneTwo_LiverHook.png`,
  `STRING_Kael_Cross_CrossHook`, `STRING_Goran_Jab_JabHammer`, `STRING_Goran_Hammer_DoubleHammer`,
  `STRING_Rhys_Jab_ReversePunch`, `STRING_Nia_Chop_DoubleChop`. Each follow-up starts exactly (0 cm) on the previous
  hit's cancel pose.
- motionkicks strings start from five of my clips: Sierra Jab→JabKick, Lumi Palm→PalmHeel, Rhys
  StraightPunch→PunchKick, Nia DoubleChop→FlurryKick, Nia PalmThrust→PalmKick. After the feet pass, the Sierra Jab,
  Rhys StraightPunch and Nia PalmThrust cancel poses are bit-identical (pose diff 0.000000). The Lumi Palm and Nia
  DoubleChop cancel poses moved (their rear foot hovered inside the old cancel pose). **motionkicks must rebuild
  PalmHeel and FlurryKick** from the 02:16 export; exact deltas are in "Feet pass round 2" (round 2 moved them again:
  Lumi Palm by ≤ 0.06 stud vs 01:08, Nia DoubleChop by up to 0.35 stud because its contact settled 2 clip frames
  later).

## Evidence (all looked at)

- `work\motionstrikes\sheets\<F>_<K>.png` (38): clipsheet-style contact sheet on the real rig.
  - Contents: side and front rows; start, wind-up, drive, pre, CONTACT (red), active end, recovery, settle and end
    frames; the defender ghost at max range; reach and design-distance lines; every-frame strip.
  - Verdict: contacts sit on the red frame. The guard hand is at the chin. No broken elbows or knees. Weight shifts
    into each strike.
- `work\motionstrikes\sheets\STRING_*.png` (6). Verdict: strings flow hit-to-hit without pops; each step-in reads as
  the lead foot stepping in.
- `work\motionstrikes\metrics\<F>_<K>.json`: the numbers in the table above.
- `work\motionstrikes\studio\probe_new_runtime.json`: real-rig contact probe in Studio. Verdict: Studio and the
  replica agree to ≈0.1 stud; the worst case, 0.26, comes from idle bounce.
- `work\motionstrikes\studio\suite_final.txt`: `324 run, 324 passed, 0 failed`, with the final exports.
- Studio burst captures in a real practice fight (`work\motionstrikes\captures\`; `SHEET_*`, `ZOOM_*`, `REVIEW_*`
  are crops). In each one the striking limb visibly reaches the target and the hit registers (hit flash / LAUNCH):
  - Kael Jab — fist reaches the face;
  - Kael OneTwo — rear hand reaches the head;
  - Kael Cross — re-shot in range; hit flash on the face;
  - Kael BodyBlow — the low rear fist digs into the body;
  - Kael RisingUppercut — LAUNCH, the opponent flies;
  - Sierra Cross — long rear hand on the face, rear heel up;
  - Sierra HopCross — hop-in cross lands;
  - Goran Hammer — on the shoulder/collarbone (also re-shot with the final export: `Final2_Goran_Hammer-14.png`);
  - Goran Haymaker — wide arc lands with a hit flash;
  - Lumi Palm — palm on the face;
  - Lumi SpinBackfist — backfist lands at head height after the turn;
  - Nia PalmThrust — palm to the chest;
  - Nia Backfist — hit at the temple;
  - Rhys Jab→ReversePunch — both land.
  Two captures did **not** connect, so they are not counted as evidence: an early Kael Cross/Haymaker take (shot out
  of range, re-shot) and Rhys SpinBackfist (spun from beyond range; whiff, not re-shot).
  Timing of the captures: all but the final Goran Hammer were shot with the 20:56 export. That export is
  byte-identical to the final one for 31 of the 38 clips. For the other 7 (keep-out pass), only frames away from the
  contact pose changed.

- Feet pass evidence (`work\motionstrikes\`):
  - `feetsheets\<F>_<K>.png` (38): what the runtime renders for the legs, every sim frame, side view in world
    space, before (shipped export) above after (feet pass). Blue = rear foot; red = hanging; yellow = deliberate
    lift; magenta = planted hover. Looked at: Kael ChargingCross, LiverHook, OneTwo, Cross, WeaveHook; Lumi Palm,
    SpinBackfist; Sierra HopCross; Nia RisingPalm. Verdict: every red/magenta foot of the old export is gone; rear
    feet slide on the floor and finish with a short low follow-step.
  - `sheets\<F>_<K>.png` vs `sheets_before\` (body posture with the pelvis sink): looked at Kael LiverHook,
    CrossHook, Sierra Cross, Lumi Palm. Verdict: knees bend more, rear legs are no longer stretched straight; Lumi
    Palm loses most of its spring-up (it was the cause of her hanging rear foot).
  - `studio\foot_probe_v2_r1.json`, `_r2.json` (+ `_report.txt`): Studio probe on the real MotionPlayer (23:19),
    real rigs, sim advance, at max/mid/close range (root advance capped at keepApart's 2.6 body contact), all 38.
    Replica agreement p95 ≤ 0.005 stud.
  - `studio\suite_feet.txt`: `356 run, 355 passed, 1 failed` (motionkicks' string-start test, see top).
  - Bursts in a real practice fight, Kael vs Sierra (`captures\SHEET_Feet2_*`, `ZOOM_Feet2_*_01-12.png`):
    - Kael ChargingCross: started at the practice reset distance, which is ≥ its max range, so the sim root makes its
      full 2.2 advance; the cross lands with a KND. Verdict: both feet stay on the floor through the step-in, the
      contact and the follow-through; the rear foot slides behind with the leg extended.
    - Kael LiverHook: the 1,2,1 string at roughly max range. Verdict: jab, one-two (lands) and the low liver hook
      all keep both shoes on the floor; the deep level change shows as a lunge, not a hanging leg.

- Feet pass round 2 evidence (`work\motionstrikes\`):
  - `studio\foot_probe_final2_net_on.json`, `_net_on_r2.json`, `_net_off.json` (+ `_report2.json`, made by
    `probe_report2.py`; final 02:16 clips; the 02:00 build gave the same worst values in `foot_probe_r5net_*`):
    Studio probe on motioncore's round-5 runtime (MotionPlayer 01:11, real rigs, sim advance),
    all 38 strikes at max/mid/close, reach net on (2 runs, identical) and off (A/B). The probe now also records the
    feet's world position and `rig.footClear`. Verdict: planted ≤ 0.005 stud; nothing shown above the runtime's
    intended height by more than 0.005. Net on vs off: identical except Sierra Jab's locked cancel frames (0.081 →
    0.005). Replica (`feet_rt2.py`) vs Studio ≤ 0.004 stud apart from that frame.
  - `studio\suite_final_console.txt` (02:16 clips; `suite_r5_console.txt` = 02:00 build, same result):
    `357 run, 356 passed, 1 failed` (motionkicks' string-start test, see top).
  - `feetsheets\<F>_<K>.png`, regenerated with before = 01:08 export, after = round 2. Looked at: Kael CrossHook,
    OneTwo, LiverHook, WeaveHook, RisingUppercut, ChargingCross; Lumi SpinBackfist, Palm; Rhys SpinBackfist,
    LowPunch; Goran DoubleHammer; Nia DoubleChop. Verdict: CrossHook's lead foot now steps back over f29–f33
    (lifted ≤ 0.19 while it travels) instead of jumping 0.86 stud on the last frame. LowPunch's 1.2-stud return
    is a 4-frame step instead of a 3-frame skate. The spin feet step round lifted instead of skating at
    0.4–0.7 stud/frame. Lead feet that hovered without travelling (OneTwo, DoubleHammer, DoubleChop) stand.
  - `sheets\` (body): looked at Kael CrossHook, Lumi Palm, Nia DoubleChop (vs `sheets_before\`), RisingPalm.
    Verdict: same strikes. Lumi Palm and RisingPalm bend the knees a little more; DoubleChop's contact pose is
    unchanged although its clip contact moved 2 frames.
  - Bursts in a real practice fight, Kael vs Sierra (`captures\SHEET_Feet3_*`, `ZOOM_Feet3_*_01-12.png`; shot on
    the 02:00 build; ChargingCross and LiverHook are byte-identical in the final export, CrossHook differs by
    ≤ 0.005 leg length):
    - Kael ChargingCross (dash from the reset distance, 6.25): lands, KND. Both shoes on the floor through the
      dash, the lunge, the contact and the follow-through.
    - Kael LiverHook (1,2,1 from 5.0, about 0.15 beyond max range: the string whiffs). Jab, one-two and the
      level-changing hook keep both shoes on the floor; the rear leg stretches back on the ball.
    - Kael CrossHook (2,1 from 3.2, i.e. close range): both land. The hook's recovery steps back into guard with
      no visible jump.

## Known issues (honest)

1. **Literal reach %** (fist centre vs `range`) is −15…−27%, outside the brief's ±10% on paper. The brief's intent
   ("hits visibly connect at the fighter's range") is met instead: on the real rigs, at max range, every striking
   point touches the defender's surface (|gap| ≤ 0.03 stud). The literal metric can't be met without hyper-extended
   arms or fists sunk 0.6–0.9 studs into the opponent's head, which is the "broken limbs" look the user rejected.
2. **Defender variety.** Calibration is against the mean defender. Per defender, the surface at max range sits
   −0.27…+0.19 stud from the fist (`gapMaxByDefender` in the metrics), so a hit can read slightly deep on a wide
   chest or a bit short on a slim one.
3. **Feet**: fixed at max and mid range. See "Feet pass round 2" for the exceptions: Sierra HopCross is airborne
   by design, and the two spin feet step round lifted for 9–11 frames.
4. **Floor values below 0** in the metrics (Goran −3.6…−7.1 cm, Sierra HopCross −3.1 cm) are the clip's toe before
   MotionPlayer's floor clamp; the runtime lifts them.
5. **Spin backfists** (Lumi, Rhys) have the fastest hand speed (≈0.5 leg lengths/frame on the whip frame). It reads as
   a whip, not a pop, on the sheets and in the Lumi burst; the Rhys burst only shows the turn (whiff).
6. **Planted-foot slide** of up to 5.3 cm (Sierra HopCross; others ≤ 4.7) is measured on the clip before the runtime
   foot lock; the lock absorbs it (the rendered planted-foot drift at max range is ≤ 0.09 stud).
7. **Pelvis sinks** (round 2, upper bound = sum of the passes): where a planted foot could not reach, the pelvis
   comes down: Kael LiverHook 0.56 stud, Lumi Palm 0.51, Nia RisingPalm 0.42, Sierra Cross 0.25, Kael
   RisingUppercut 0.24, OneTwo 0.18, CrossHook 0.13, Goran Uppercut 0.12, Sierra HopCross 0.12, Lumi SpinBackfist
   0.10, Kael WeaveHook 0.08, others < 0.05.
   LiverHook and Lumi Palm read as deep knee bends (a level-changing body hook; a low palm).
8. **Close-range foot drag (runtime, pre-existing).** When keepApart stops the root early, the clip's planted
   feet move back relative to the root and lockFoot holds them within its 0.3 × scale leash, then drags them
   (up to 0.84 stud for Kael ChargingCross, 0.93 Goran Bulldozer, rendered). Vertical is fine at every range;
   this horizontal drag is the same as before the feet pass.
9. **Reduced range: lock-release snap (runtime, pre-existing).** When keepApart caps the root, the planted rear
   foot (authored world-fixed against the full advance) is held back by lockFoot. When its contact drops it jumps
   to the clip spot in one frame. Studio: Goran ShoulderTackle 0.39 (mid) / 0.46 (close), Bulldozer 0.39 / 0.49,
   Rhys LungePunch 0.53, Nia Elbow 0.46, Nia Backfist 0.45 (close; was 0.22 + 0.16 over two frames before round
   2, the release is sharper since its contact moved 0.6 clip frame), all stud per frame. Max range: none.
   REQUEST 3.
10. **Close range: a step-in's lead foot steps in place.** The lead foot's lift is timed with the sim advance. When
   keepApart stops the root (cap 0.1), the foot rises and lands without travelling: Studio worst Nia PalmThrust 0.22,
   Rhys StraightPunch 0.18, Sierra Cross 0.17, Goran ShoulderTackle 0.14, Nia Chop 0.14, Rhys LungePunch 0.12,
   Kael Cross 0.12 stud for 2–7 frames. Most of it was there before round 2 (replica, 01:08: PalmThrust 0.21,
   Sierra Cross 0.19, StraightPunch 0.18, ShoulderTackle 0.16, Kael Cross 0.11, Nia Chop 0.08). Round 2 adds Rhys
   LungePunch (0.12) and raises Nia Chop to 0.14, because their lead steps now lift from the first moving frame.
   A clip can't know the range; optional REQUEST 4.
11. **Contact times moved** in round 2 for 6 clips. The impact still lands exactly on the first active frame
   (contact err 0); the clip time it maps to settled elsewhere: Nia DoubleChop 7.00 → 9.00, Kael RisingUppercut
   10.05 → 10.75, Nia Backfist 5.45 → 4.85, Kael LiverHook 7.95 → 7.80, CrossHook 8.15 → 8.05, Goran Uppercut
   12.80 → 12.75.

## REQUESTs

- REQUEST 1 (feet hovering in crouches) — **done by motioncore** (round-4 runtime, 23:19).
- REQUEST 2: `MotionPlayer` (lockFoot at a move start): when a move clip starts, the foot lock still holds the idle's
  foot spot (up to the 0.3 × scale leash) while the 0.05 s crossfade blends into the clip. A clip whose rear leg is
  near full reach in its first frames then hovers for a frame or two: seen once in Studio on Sierra Jab, +0.08 at f3
  in one probe run, depending on the bouncy idle's phase. The clips now keep extra margin there (the rear foot
  starts its slide earlier), and the probe shows ≤ 0.005. A runtime fix would cover every clip: re-anchor the locks
  to the new pose's goals when the move key changes, or blend them over the fade.
- motioncore's reach net (round 5, 01:11): **verified** with these clips (probe above). With the net off, the
  strikes render identically except Sierra Jab's two locked cancel frames, +0.08 inside its follow-step; the net
  brings them to 0.005. The clips do not need it anywhere else.
- REQUEST 3: `MotionPlayer.lockFoot`: when a locked foot is released (contact falls below 0.5), fade its lock offset
  out over ~4 frames instead of dropping it, at least when the sim root's advance was capped (keepApart). This
  removes the reduced-range rear-foot snaps (known issue 9, up to 0.53 stud/frame) for every step-in strike and
  kick at once; at max range the offset is ~0, so nothing changes there.
- REQUEST 4 (optional, low priority): when keepApart caps a move's root advance, scale a released foot's clip
  clearance (`footClear`, feet with clip sole ≤ 0.12 L only) by applied ÷ designed advance, so a step-in's lead foot
  doesn't lift in place at point-blank range (known issue 10).

## Feet pass (integrator follow-up, round 1 — 01:08 export, superseded)

Goal: no foot hangs in the air at runtime. Planted feet ≤ 0.03 stud. An un-planted rear foot ≤ 0.25 stud, lifted
only inside a deliberate follow-step of ≤ 6 frames. Where a planted foot can't reach, the pelvis sinks. Contact frames
and reach stay as they are, with 0 joint violations. Clips start and end on the displayed stance, and the cancel poses
motionkicks builds from are kept unless approved.

How: see pipeline step 6 (`feetfix.py`). Verified with the Studio probe on the real runtime (MotionPlayer 23:19,
real rigs, sim advance) at max, mid and close range for all 38 strikes, 2 runs each:
- planted feet (contact ≥ 0.8): worst **0.005 stud** (was up to 0.21);
- un-planted rear foot: worst **0.22 stud**, longest lifted run **5 sim frames** (was 1.36 stud / 22 frames), except
  Sierra HopCross (below);
- no frame where a foot is above its own authored clearance by more than 0.03 stud, except the Sierra Jab cancel frame
  (below).

Before = the shipped export: replica on 3 ranges, which matches the 23:19 Studio probe. After = Studio probe, worst
of max/mid/close × 2 runs. Reach error = studs short of the body surface at max range on the real rigs
(+ = short).

| fighter · key | worst planted gap (studs) before → after | worst rear-foot lift (studs) / longest lifted run (sim frames) before → after | reach error at range (studs) before → after | pelvis sink (studs) | end pose |
|---|---|---|---|---|---|
| Kael · Jab | 0.000 → 0.000 | 0.00 / 0 → 0.00 / 0 | +0.00 → +0.01 | 0.02 | stance; cancel pose rebuilt with its follow-up (string gap 0) |
| Kael · OneTwo | 0.000 → 0.000 | 0.58 / 14 → 0.10 / 3 | -0.02 → -0.02 | 0.18 | stance; cancel pose rebuilt with its follow-up (string gap 0) |
| Kael · LiverHook | 0.072 → 0.000 | 1.00 / 8 → 0.08 / 1 | +0.01 → -0.00 | 0.50 | stance (unchanged) |
| Kael · Cross | 0.000 → 0.000 | 0.49 / 9 → 0.13 / 5 | -0.00 → -0.00 | 0.00 | stance; cancel pose rebuilt with its follow-up (string gap 0) |
| Kael · CrossHook | 0.000 → 0.000 | 0.67 / 13 → 0.09 / 2 | +0.08 → -0.01 | 0.16 | stance (unchanged) |
| Kael · Overhand | 0.000 → 0.000 | 0.20 / 12 → 0.17 / 5 | -0.00 → -0.00 | 0.00 | stance (unchanged) |
| Kael · BodyBlow | 0.000 → 0.000 | 0.07 / 7 → 0.07 / 5 | -0.01 → -0.01 | 0.00 | stance (unchanged) |
| Kael · RisingUppercut | 0.000 → 0.000 | 0.44 / 8 → 0.07 / 5 | +0.01 → +0.01 | 0.19 | stance (unchanged) |
| Kael · WeaveHook | 0.000 → 0.000 | 0.32 / 8 → 0.13 / 5 | +0.03 → +0.03 | 0.03 | stance (unchanged) |
| Kael · ChargingCross | 0.000 → 0.000 | 1.36 / 11 → 0.20 / 5 | +0.01 → +0.01 | 0.00 | stance (unchanged) |
| Sierra · Jab | 0.000 → 0.005 | 0.19 / 7 → 0.20 / 5 | +0.00 → +0.00 | 0.00 | cancel pose identical (JabKick) |
| Sierra · Cross | 0.208 → 0.003 | 0.54 / 11 → 0.16 / 3 | +0.00 → +0.00 | 0.25 | stance (unchanged) |
| Sierra · DuckJab | 0.000 → 0.000 | 0.07 / 3 → 0.09 / 3 | -0.00 → -0.00 | 0.00 | stance (unchanged) |
| Sierra · HopCross | 0.142 → 0.004 | 1.34 / 22 → 0.79 / 18 | +0.00 → -0.00 | 0.12 | stance (unchanged) |
| Goran · Jab | 0.000 → 0.000 | 0.00 / 0 → 0.00 / 0 | +0.00 → +0.00 | 0.00 | stance; cancel pose rebuilt with its follow-up (string gap 0) |
| Goran · JabHammer | 0.000 → 0.001 | 0.00 / 0 → 0.00 / 0 | +0.01 → +0.01 | 0.00 | stance (unchanged) |
| Goran · Hammer | 0.000 → 0.000 | 0.00 / 0 → 0.00 / 0 | -0.00 → -0.00 | 0.00 | stance; cancel pose rebuilt with its follow-up (string gap 0) |
| Goran · DoubleHammer | 0.000 → 0.000 | 0.13 / 5 → 0.13 / 4 | +0.00 → +0.00 | 0.00 | stance (unchanged) |
| Goran · ShoulderTackle | 0.000 → 0.000 | 0.23 / 6 → 0.22 / 4 | -0.01 → -0.01 | 0.00 | stance (unchanged) |
| Goran · Uppercut | 0.000 → 0.002 | 0.27 / 5 → 0.00 / 0 | -0.01 → -0.00 | 0.12 | stance (unchanged) |
| Goran · CrouchJab | 0.000 → 0.000 | 0.00 / 0 → 0.00 / 0 | -0.01 → -0.01 | 0.00 | stance (unchanged) |
| Goran · Haymaker | 0.000 → 0.000 | 0.08 / 4 → 0.08 / 4 | -0.00 → -0.00 | 0.00 | stance (unchanged) |
| Goran · Bulldozer | 0.000 → 0.000 | 0.27 / 7 → 0.22 / 5 | +0.00 → +0.00 | 0.00 | stance (unchanged) |
| Lumi · Palm | 0.029 → 0.001 | 0.47 / 8 → 0.15 / 3 | +0.01 → -0.00 | 0.41 | cancel pose MOVED (PalmHeel): body 0.43 lower, rear ankle 0.31 |
| Lumi · SpinBackfist | 0.059 → 0.000 | 0.29 / 16 → 0.22 / 2 | +0.04 → +0.00 | 0.14 | stance (unchanged) |
| Rhys · Jab | 0.000 → 0.000 | 0.06 / 4 → 0.06 / 4 | -0.00 → -0.00 | 0.00 | stance; cancel pose rebuilt with its follow-up (string gap 0) |
| Rhys · ReversePunch | 0.000 → 0.000 | 0.10 / 4 → 0.04 / 2 | -0.00 → -0.00 | 0.04 | stance (unchanged) |
| Rhys · StraightPunch | 0.000 → 0.000 | 0.16 / 7 → 0.16 / 3 | -0.00 → -0.00 | 0.00 | cancel pose identical (PunchKick) |
| Rhys · Deflect | 0.000 → 0.000 | 0.02 / 0 → 0.02 / 0 | n/a (parry) → n/a (parry) | 0.00 | stance (unchanged) |
| Rhys · LowPunch | 0.000 → 0.000 | 0.00 / 0 → 0.00 / 0 | -0.00 → -0.00 | 0.00 | stance (unchanged) |
| Rhys · SpinBackfist | 0.000 → 0.000 | 0.13 / 13 → 0.01 / 0 | +0.01 → +0.01 | 0.00 | stance (unchanged) |
| Rhys · LungePunch | 0.000 → 0.000 | 0.37 / 10 → 0.03 / 1 | -0.00 → -0.00 | 0.01 | stance (unchanged) |
| Nia · Chop | 0.000 → 0.001 | 0.17 / 5 → 0.13 / 4 | -0.01 → -0.01 | 0.00 | stance; cancel pose rebuilt with its follow-up (string gap 0) |
| Nia · DoubleChop | 0.113 → 0.001 | 0.57 / 9 → 0.19 / 4 | -0.01 → -0.00 | 0.10 | cancel pose MOVED (FlurryKick): body 0.09 fwd/down, rear ankle 0.21 |
| Nia · PalmThrust | 0.000 → 0.001 | 0.23 / 8 → 0.15 / 3 | +0.00 → +0.00 | 0.00 | cancel pose identical (PalmKick) |
| Nia · RisingPalm | 0.123 → 0.001 | 0.96 / 13 → 0.22 / 4 | +0.00 → +0.00 | 0.27 | stance (unchanged) |
| Nia · Backfist | 0.000 → 0.001 | 0.66 / 11 → 0.21 / 4 | -0.01 → -0.01 | 0.00 | stance (unchanged) |
| Nia · Elbow | 0.000 → 0.001 | 0.63 / 7 → 0.17 / 5 | +0.01 → +0.01 | 0.00 | stance (unchanged) |

Exceptions (honest):
- **Sierra HopCross** is airborne by frame data (low crush f6–15: both feet off the floor), and its rear leg
  kicking back for balance is the move. The IK over-reach (+0.31) and the landing hover (planted +0.14) are
  gone. The kick-back is lower (0.79 stud, was 1.34 incl. over-reach), kept within leg reach, and comes down
  2 frames after the punch lands instead of 6. The rear foot is still up for 18 frames: knee fake + hop + kick-back.
- **Sierra Jab** cancel frame (sim f12, locked: motionkicks' JabKick starts there) has the rear foot mid-step at
  0.10 stud, 0.06 of it from leg reach. It is inside a 5-frame follow-step, ≤ 0.25.

Cancel poses motionkicks starts from (real-rig joints at the cancel time):
- Sierra Jab, Rhys StraightPunch, Nia PalmThrust: **bit-identical** (pose diff 0.000000).
- **Lumi Palm (→ PalmHeel) moved.** Cancel time is clip frame 11.000, was 9.999; the contact refined one clip frame
  later, and the cancel is still sim frame 12. Measured on the real rig:
  - pelvis 0.439 stud (fwd +0.08, up −0.43, side −0.01); head 0.440 (fwd +0.07, up −0.43);
  - lead hand 0.302 (fwd −0.14, up −0.26, side −0.04); rear hand 0.447 (up −0.44);
  - lead ankle 0.038; rear ankle 0.313 (up −0.28, side +0.14);
  - rotations pelvis 2.8°, waist 1.9°, neck 2.1°, feet 2.0° / 3.5°;
  - contact flags L 1.00, R 0.00 → 0.45.
  The old cancel pose had the rear foot 0.40 stud in the air.
- **Nia DoubleChop (→ FlurryKick) moved.** Cancel time unchanged (clip 9.999). Measured on the real rig:
  - pelvis, head and hands shifted 0.083–0.086 stud (fwd +0.075, up −0.02/−0.03, side −0.03);
  - rear ankle 0.213 (fwd +0.17, up −0.13); lead ankle 0;
  - rotations 0.0°; contact flags R 0.72 → 1.00.
  The old cancel pose had the rear foot 0.08–0.11 stud up.

Re-exported (32): every clip except Goran Jab, JabHammer, Hammer, CrouchJab, Rhys Jab and LowPunch, plus the
coverage test, all unchanged. Changes are feet/contacts only, except where the pelvis sank (root, plus the
hands re-baked onto the same contact spot): Kael Jab/OneTwo/LiverHook/CrossHook/RisingUppercut/WeaveHook, Sierra
Cross/HopCross, Goran Uppercut, Lumi Palm/SpinBackfist, Rhys ReversePunch, Nia DoubleChop/RisingPalm.
HopCross also has re-keyed rear-leg keys (lower knee fake and kick-back, earlier landing).

## Feet pass round 2 (reach net verified, lead-foot steps, end swings) — current export 02:16

Why: motioncore's reach-net probe flagged released lead feet shown 0.15–0.19 stud up (Kael WeaveHook, CrossHook,
LiverHook, RisingUppercut). My own scan of foot speed found the lifts that hang (the foot up while not
travelling) and one-frame foot jumps. The worst was Kael CrossHook's lead foot and pelvis snapping back to the
stance on the last frame (0.86 / 0.5 stud).

What: pipeline step 7 (end/start swings in `finish.reanchor`; `feetfix.shape_steps`).

Verified (Studio, round-5 runtime 01:11, real rigs, sim advance, all 38 strikes at max/mid/close, 2 runs; net on,
and net off as the round-4 A/B):
- planted feet (contact ≥ 0.8): worst **0.005 stud**;
- shown above the runtime's intended height (`rig.footClear`): worst **0.005 stud** (net on). Net off: identical
  except Sierra Jab f11–12 +0.08 (locked cancel frames, inside a 5-frame follow-step, ≤ 0.21 stud);
- un-planted rear foot: worst **0.22 stud**, longest lifted run **5 sim frames**. Exceptions: the spin steps of Lumi
  SpinBackfist (9) and Rhys SpinBackfist (11), and Sierra HopCross (airborne, unchanged);
- hang (a foot lifted > 0.03 while it moves < 0.03 stud/frame; Studio, frames 4..N−3): max range **35 of 38
  clips have none**; Goran Uppercut, Kael BodyBlow and Sierra DuckJab have 1–2 frames ≤ 0.06 at the end of a
  step. Mid range adds Rhys LungePunch (1 frame, 0.10). Close range: see known issue 10;
- contact frame exact (err 0), reach gap within ±0.04, joint violations 0, stance/string gaps 0;
- cliplint OK; suite 357/356/1 (motionkicks' string start, see top).

Table: before = 01:08 export, after = 02:16 export.
- planted gap, rear lift/run: Studio worst of max/mid/close (before: v2 probe on the round-4 runtime; after:
  round-5 runtime, net on);
- hang and fastest foot frame (stud per sim frame, any foot): feet_rt2 replica at max range;
- reach gap: studs short of the body surface at max range (+ = short).

| clip | planted gap (Studio) | rear lift / run (Studio) | hang, max range (lifted, not moving) | fastest foot frame | reach gap | end pose |
|---|---|---|---|---|---|---|
| Kael Jab | 0.000 → 0.000 | 0.00/0 → 0.00/0 | 0.00×0 → 0.00×0 | 0.30 → 0.25 | +0.01 → +0.01 | stance, unchanged |
| Kael OneTwo | 0.000 → 0.000 | 0.10/3 → 0.12/3 | 0.19×5 → 0.00×0 | 0.28 → 0.28 | -0.02 → -0.03 | stance, unchanged |
| Kael LiverHook | 0.000 → 0.000 | 0.08/1 → 0.08/1 | 0.12×2 → 0.00×0 | 0.25 → 0.25 | -0.00 → +0.00 | stance, unchanged |
| Kael Cross | 0.000 → 0.000 | 0.13/5 → 0.12/5 | 0.00×0 → 0.06×1 | 0.21 → 0.28 | -0.00 → -0.00 | stance, unchanged |
| Kael CrossHook | 0.000 → 0.000 | 0.09/2 → 0.09/1 | 0.14×5 → 0.00×0 | 0.86 → 0.26 | -0.01 → +0.00 | stance, unchanged |
| Kael Overhand | 0.000 → 0.000 | 0.17/5 → 0.21/5 | 0.07×1 → 0.00×0 | 0.24 → 0.24 | -0.00 → -0.00 | stance, unchanged |
| Kael BodyBlow | 0.000 → 0.000 | 0.07/5 → 0.20/4 | 0.14×3 → 0.04×1 | 0.25 → 0.25 | -0.01 → -0.01 | stance, unchanged |
| Kael RisingUppercut | 0.000 → 0.000 | 0.07/5 → 0.12/4 | 0.11×1 → 0.00×0 | 0.39 → 0.37 | +0.01 → +0.01 | stance, unchanged |
| Kael WeaveHook | 0.000 → 0.000 | 0.13/5 → 0.20/4 | 0.09×1 → 0.00×0 | 0.32 → 0.32 | +0.03 → +0.03 | stance, unchanged |
| Kael ChargingCross | 0.000 → 0.000 | 0.20/5 → 0.22/5 | 0.00×0 → 0.00×0 | 0.30 → 0.29 | +0.01 → +0.01 | stance, unchanged |
| Sierra Jab | 0.005 → 0.005 | 0.20/5 → 0.21/4 | 0.00×0 → 0.00×0 | 0.30 → 0.37 | +0.00 → +0.00 | cancel pose identical |
| Sierra Cross | 0.003 → 0.003 | 0.16/3 → 0.16/2 | 0.00×0 → 0.00×0 | 0.18 → 0.18 | +0.00 → +0.00 | stance, unchanged |
| Sierra DuckJab | 0.000 → 0.000 | 0.09/3 → 0.10/5 | 0.07×3 → 0.03×1 | 0.34 → 0.30 | -0.00 → -0.01 | stance, unchanged |
| Sierra HopCross | 0.004 → 0.004 | 0.79/18 → 0.79/18 | 0.00×0 → 0.00×0 | 0.40 → 0.40 | -0.00 → -0.00 | stance, unchanged |
| Goran Jab | 0.000 → 0.000 | 0.00/0 → 0.00/0 | 0.00×0 → 0.00×0 | 0.11 → 0.11 | +0.00 → +0.00 | stance, unchanged |
| Goran JabHammer | 0.001 → 0.001 | 0.00/0 → 0.00/0 | 0.00×0 → 0.00×0 | 0.14 → 0.14 | +0.01 → +0.01 | stance, unchanged |
| Goran Hammer | 0.000 → 0.000 | 0.00/0 → 0.00/0 | 0.00×0 → 0.00×0 | 0.12 → 0.12 | -0.00 → -0.00 | stance, unchanged |
| Goran DoubleHammer | 0.000 → 0.000 | 0.13/4 → 0.10/4 | 0.22×7 → 0.00×0 | 0.08 → 0.08 | +0.00 → +0.00 | stance, unchanged |
| Goran ShoulderTackle | 0.000 → 0.000 | 0.22/4 → 0.20/4 | 0.00×0 → 0.00×0 | 0.27 → 0.27 | -0.01 → -0.01 | stance, unchanged |
| Goran Uppercut | 0.002 → 0.002 | 0.00/0 → 0.13/3 | 0.08×1 → 0.06×1 | 0.39 → 0.40 | -0.00 → -0.01 | stance, unchanged |
| Goran CrouchJab | 0.000 → 0.000 | 0.00/0 → 0.00/0 | 0.00×0 → 0.00×0 | 0.26 → 0.26 | -0.01 → -0.01 | stance, unchanged |
| Goran Haymaker | 0.000 → 0.000 | 0.08/4 → 0.08/5 | 0.04×1 → 0.00×0 | 0.17 → 0.17 | -0.00 → -0.00 | stance, unchanged |
| Goran Bulldozer | 0.000 → 0.000 | 0.22/5 → 0.22/5 | 0.00×0 → 0.00×0 | 0.32 → 0.32 | +0.00 → +0.00 | stance, unchanged |
| Lumi Palm | 0.001 → 0.000 | 0.15/3 → 0.15/1 | 0.08×2 → 0.00×0 | 0.31 → 0.31 | -0.00 → +0.04 | cancel pose moved (see below) |
| Lumi SpinBackfist | 0.000 → 0.000 | 0.22/2 → 0.22/9 | 0.00×0 → 0.00×0 | 0.72 → 0.72 | +0.00 → +0.00 | stance, unchanged |
| Rhys Jab | 0.000 → 0.000 | 0.06/4 → 0.07/4 | 0.00×0 → 0.00×0 | 0.20 → 0.20 | -0.00 → -0.00 | stance, unchanged |
| Rhys ReversePunch | 0.000 → 0.000 | 0.04/2 → 0.19/3 | 0.00×0 → 0.00×0 | 0.34 → 0.34 | -0.00 → -0.00 | stance, unchanged |
| Rhys StraightPunch | 0.000 → 0.000 | 0.16/3 → 0.11/3 | 0.00×0 → 0.00×0 | 0.18 → 0.16 | -0.00 → -0.00 | cancel pose identical |
| Rhys Deflect | 0.000 → 0.000 | 0.00/0 → 0.00/0 | 0.00×0 → 0.00×0 | 0.04 → 0.05 | parry | stance, unchanged |
| Rhys LowPunch | 0.000 → 0.000 | 0.00/0 → 0.13/2 | 0.04×1 → 0.00×0 | 0.60 → 0.40 | -0.00 → -0.00 | stance, unchanged |
| Rhys SpinBackfist | 0.000 → 0.000 | 0.00/0 → 0.22/11 | 0.00×0 → 0.00×0 | 0.41 → 0.41 | +0.01 → +0.01 | stance, unchanged |
| Rhys LungePunch | 0.000 → 0.000 | 0.03/1 → 0.20/5 | 0.00×0 → 0.00×0 | 0.29 → 0.29 | -0.00 → -0.00 | stance, unchanged |
| Nia Chop | 0.001 → 0.001 | 0.13/4 → 0.12/4 | 0.00×0 → 0.00×0 | 0.22 → 0.22 | -0.01 → -0.00 | stance, unchanged |
| Nia DoubleChop | 0.001 → 0.002 | 0.19/4 → 0.06/4 | 0.04×1 → 0.00×0 | 0.15 → 0.21 | -0.00 → +0.01 | cancel pose moved (see below) |
| Nia PalmThrust | 0.001 → 0.001 | 0.15/3 → 0.15/5 | 0.00×0 → 0.00×0 | 0.20 → 0.20 | +0.00 → +0.00 | cancel pose identical |
| Nia RisingPalm | 0.001 → 0.002 | 0.22/4 → 0.22/5 | 0.16×5 → 0.00×0 | 0.39 → 0.39 | +0.00 → +0.00 | stance, unchanged |
| Nia Backfist | 0.001 → 0.001 | 0.21/4 → 0.06/3 | 0.00×0 → 0.00×0 | 0.22 → 0.26 | -0.01 → +0.01 | stance, unchanged |
| Nia Elbow | 0.001 → 0.001 | 0.17/5 → 0.15/4 | 0.00×0 → 0.00×0 | 0.26 → 0.26 | +0.01 → +0.01 | stance, unchanged |

Cancel poses motionkicks starts from (real-rig joints at the cancel time, `cancel_cmp.py`):
- Sierra Jab, Rhys StraightPunch, Nia PalmThrust: **bit-identical** to the 23:22 build (pose diff 0).
- **Lumi Palm (→ PalmHeel)**: cancel at clip frame 11.0, was 10.0 at 23:22.
  - vs 23:22 (what PalmHeel was built from): pelvis 0.48 stud (up −0.47), head 0.48, lead hand 0.26, rear hand
    0.48, rear ankle 0.31 (fwd −0.14, up −0.28), lead knee 0.68, rear knee 0.44; rotations pelvis 2.8°,
    waist 1.8°, neck 2.1°.
  - vs 01:08: every joint ≤ 0.06 stud, rotations ≤ 0.2°.
- **Nia DoubleChop (→ FlurryKick)**: cancel at clip frame 12.0, was 10.0 (contact 7 → 9).
  - vs 23:22: pelvis 0.12 stud, head 0.12, lead hand 0.29 (fwd +0.27), rear hand 0.28 (up +0.16), rear ankle 0.33
    (up −0.13), rear knee 0.24; rotations pelvis 1.1°, waist 0.9°, neck 3.9°.
  - vs 01:08: lead hand 0.24, rear hand 0.35, rear ankle 0.14, pelvis 0.07.
motionkicks: rebuild PalmHeel and FlurryKick from this export (the suite names PalmHeel; FlurryKick follows it in
the same test). JabKick, PunchKick and PalmKick are unaffected.
