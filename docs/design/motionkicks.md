# motionkicks handoff — kick-type moves as clips (OV6 phase 2)

**Status: done.** All 49 kick-type moves of the six fighters (kicks, knees, sweeps, acrobatic kicks; a string
follow-up counts when its own last button is 3/4) play a dedicated FLClip1 clip: 21 built on licensed mocap
(ACCAD CC BY 3.0, CMU terms) with hand-keyed edits, 28 hand-keyed. Full suite green in my Studio
(first delivery); the integrator review accepted it (354/354 in the integrated build).

## 0. Integrator follow-up (done, offline-verified)

Five Lumi clips changed; the other 44 modules and the coverage test are byte-identical to the accepted export.
Contact frames stay exact (0 f) and the reach is unchanged within 0.05 studs. Measured on the decoded modules exactly
as the runtime plays them: head = head height / standing head height of the displayed stance; feet = lowest point
(sole, ball, toe, heel) of either foot, in leg lengths (L).

| Item | Before | After |
|---|---|---|
| CartwheelKick striking leg | rear (right) leg, `tags.limb = "RightFoot"` | **lead (left) leg** = Roster `LeadLeg`, no limb override; tip 3.21 → 3.26 studs (surface gap +0.02 → −0.03) |
| CartwheelKick head on f4 (high crush f4–16) | 0.82 | **0.685** (≤ 0.685 for the whole window) |
| SlideKick head on f5 (high crush f5–20) | 0.76 | **0.67** (≤ 0.67 for the whole window) |
| FlipKick push-off foot on f6 (low crush f6–15) | 0.000 L, on the floor (contact 0.05) | **0.111 L**, contact 0 (≥ 0.11 for the whole window) |
| ScissorKick lowest foot on f5 (low crush f5–14) | 0.019 L | **0.164 L** (≥ 0.16 for the whole window) |
| VaultKick lowest foot on f3 (low crush f3–12) | 0.025 L | **0.185 L** (≥ 0.18 for the whole window) |

How: CartwheelKick uses the capoeira capture unmirrored (its left leg kicks), turned −50° onto the fight line; the
rear foot takes a real, lifted step through to its pivot spot (f1–7) while she turns, so the lead leg reaches as far
as before, and the extra turn out of the orthodox stance is spread over the first 13 frames. Its dive is re-timed
(source anchor at f4, constant-rate drop from f0). SlideKick's drop keys moved from f4/f6/f8 to f3.5/f5/f7.5.
FlipKick's dip and push-off come earlier (dip f3.3, push-off f4.3, foot in the air by f6). ScissorKick dips at f2.5,
both feet are unplanted by f3.4 and the take-off key moved from f6 to f5.5; VaultKick's vault foot leaves the floor at
f1.9 (was f2.5) and keeps rising through f3–4.
Re-rendered and viewed: the five own sheets and the five clipsheets; cliplint OK; joint-limit violations 0 on all 49.

## 0b. String rebuild on motionstrikes' final strike export (done, offline-verified)

motionstrikes re-exported its strikes (final export 02:16; Palm moved up to 0.48 studs, DoubleChop 0.35). The five
string follow-ups were rebuilt from it with `python build.py Sierra.JabKick,Lumi.PalmHeel,Rhys.PunchKick,Nia.FlurryKick,Nia.PalmKick`.

- **Changed modules (4):** `Kick_Lumi_PalmHeel`, `Kick_Nia_FlurryKick` (new start poses), `Kick_Sierra_JabKick` (the
  Jab clip I had baked from was an older export; its old start had the rear ankle 0.16 studs off today's Jab), `Kick_Rhys_PunchKick`
  (start unchanged; only the feet fix below, frames 13–34). `Kick_Nia_PalmKick` and the other 44 modules and the
  coverage test are byte-identical to the accepted export.
- **String start gaps** (previous clip on its last displayed frame vs this clip's frame 0; hands, ankles, pelvis /
  every joint, studs): JabKick 0.0022 / 0.0022, PalmHeel 0.0022 / 0.0026, PunchKick 0.0002 / 0.0002, FlurryKick
  0.0020 / 0.0020, PalmKick 0.0003 / 0.0004. The chain pose is usually between two stored frames (off the 12-bit
  grid); frame 0 now takes the grid values that pose it closest (plain rounding gave up to 0.0037 / 0.0060).
- **Feet without the runtime reach net:** a new pass in the pipeline (`author.reach_feet`) re-authors any foot on or
  near the floor that the leg cannot reach: it rises onto its ball (heel ≤ 40°, toes on the floor), then slides toward
  the hip with contact 0 (a drag step); the striking foot's return after the hit reaches back toward its landing spot
  as far as the leg allows and sets down when the spot is in reach (`reach_return`, contact 0), instead of dragging.
  Checked with `hang.py` (the plain two-bone IK, no net): no hanging foot in the five (before: PalmHeel 0.57,
  PunchKick 0.59, FlurryKick 0.15 studs). PalmHeel's and FlurryKick's rear foot now starts planted (Palm/DoubleChop no
  longer float it) and slides up on its ball while the lead foot steps in (PalmHeel ≈ 1.4 studs with the root's 1.40
  step-in, FlurryKick ≈ 0.6).
- **Kept:** contact exact (0 f) on all five; joint-limit violations 0; tip at F1 unchanged (PalmHeel 3.04, FlurryKick
  3.70 studs: the new starts plant the support foot further forward, so the kicking foot is pulled back 0.14 / 0.12
  studs at contact; JabKick 3.17, PunchKick 3.96, PalmKick 3.26); crush-window numbers of §0 unchanged (those clips
  were not rebuilt). PalmHeel's speed flags 6 → 8 (elbows f7–11 of the spin).
- Viewed: own sheets and clipsheets of PalmHeel, FlurryKick, JabKick and PunchKick (plus close-ups of the starts and
  landings). cliplint `49 modules, 223.9 KB (budget 2048 KB) OK`.

## 1. Files (`OV6\handoff\motionkicks-src\`, UTF-8, LF, no BOM)

- 49 × `ReplicatedStorage.FightingLab.Client.Motion.Clips.Moves.Kicks.Kick_<Fighter>_<Key>.luau` (one clip table per
  module, `fighter`/`move` binding, no `stringIndex` = any; 60 fps; 223.9 KB total of the 2048 KB budget).
- `ServerStorage.UnitTest.Cases.MotionMovesKicksCoverage_Test.luau` (new, 5 tests, see §3).
- Unchanged and still owned: `Client.Motion.Kicks` (procedural fallback; every kick now resolves to a clip, so it is
  no longer used for kicks) and the baseline `MotionKicks_Test`.
- Authoring kit (not shipped): `OV6\work\motionkicks\tools\` — `build.py all` rebuilds every clip, metric and sheet
  in ~5 min; `tips.py` (reach report), `viol.py Fighter.Key` (violations), `zoom.py Fighter_Key f1,f2` (close-ups),
  `hang.py` (hanging-foot check with the plain IK, no reach net), `strgap.py` (string start gaps),
  `burstsheet.py` (Studio burst sheets), `write_handoff.py` (this file).

## 2. How it works

- **Timing is baked to the sim.** Each clip has frames = startup + active + recovery + 1 at 60 fps and `contact` =
  first active frame / total, so `ClipPlayer.moveTime` is the identity: moveFrame k shows clip frame k, contact
  exactly on `startup + 1` (Roster literal `startup = N` = impact frame N). The clips match the 9:44 PM Roster
  (frames, range, advance) for all 49.
- **Sources.** Mocap segments are cut (wind-up → contact → recover → end), retimed piecewise so the capture's contact
  lands on the first active frame, mirrored/yawed into the fighter's displayed stance and blended in/out; spin
  captures get tucked arms (the compressed spins otherwise flail). Keyed clips are PCHIP keys on world-space
  feet/pelvis/hands with knee/elbow poles, per fighter style (KAEL plain boxer kicks, SIERRA shin kicks and teeps,
  GORAN short and heavy, LUMI acrobatic, RHYS chambered karate kicks, NIA fluid open-hand).
- **Pipeline per clip** (`build.py build_one`): builder → contact retime → arm smoothing (mocap) → **step-in layer**
  (REQUEST 7: the support foot steps with the sim root during startup, contact 0 while it travels; the clip stays in
  place horizontally, the sim supplies `advance × min(k − 1, startup) / startup`) → body settle into the end pose
  (pelvis, waist, neck, hands, elbow and knee poles, hand rotations) → feet settle onto the stance spots (pivot on the
  ball) → hand speed limit (≤ 0.19 leg/frame) → limb limits → **reach pass** (no foot the leg cannot reach hangs in the
  air: near-floor feet rise onto the ball, then drag; the striking foot's return reaches toward its landing spot; see
  §0b) → knee/elbow pole continuity (≤ 30°/frame) → contact sanitising → string start on the grid → export → the
  module is decoded exactly as the runtime does and feet the two-bone IK cannot reach are un-planted → metrics + sheet.
- **Start/end poses.** Every clip starts on `Displayed:<Fighter>` (crouching moves on the displayed crouch) and ends on
  the displayed stance (≤ 0.09 studs on every joint; QuickLow and LowSpin end on the displayed crouch). String
  follow-ups (JabKick, TeepKick, DoubleRoundhouse, PalmHeel, SnapCrescent, PunchKick, FlurryKick, PalmKick,
  RisingTornado) start on the previous clip's last displayed frame (`startup + active`; CombatSim starts the
  follow-up on the next tick): measured gap ≤ 0.003 studs.
- **Aim tags** (motioncore §4 layer): knees, sweeps and the slide `aim = false`; axe kick / stomp `aimWeight 0.4`;
  rising and flip kicks `0.3`; low kicks `0.5`. No limb overrides: every clip strikes with the Roster's `limb`.
- **Reach.** Tips were measured per kick and fed combat's step-in table (REQUEST 7, applied in the Roster). Rule agreed
  with combat and motionstrikes: at max range the striking point meets the defender's surface — High 0.61 (head
  front), Mid 0.47 (UpperTorso front), Low 1.20 (lead-knee front; knees +0.10). "Surface gap" below =
  range − (tip + offset): ≈ 0 means the kick lands at max range, negative = it reaches past the surface (low kicks and
  sweeps hit the shin/ankle line), positive = short at max range.

## 3. Tests

- **Studio** (my place = base + motioncore-src + combat-src incl. the 9:44 PM Roster + motionstrikes-src +
  characters-src + this export; Play/Server `require(game.ServerStorage.UnitTest.RunUnitTest)(nil,5)`):
  `[SUMMARY] 293 run, 293 passed, 0 failed` (`MotionMovesKicksCoverage_Test` 5/5). Without characters-src it was
  289 run / 288 passed / 1 failed: motioncore's `MotionGround_Test` (Goran KO lying 0.042 below the floor on the base
  place's old rig) — not kick-related, green with the characters rigs.
- **MotionMovesKicksCoverage_Test:** (1) all 49 kick-type moves resolve via `ClipLibrary.forMove` to
  `Kick_<Fighter>_<Key>` in `Moves.Kicks`, `resolveMove` source "Clip", no library problems; (2) contact maps to
  `startup + 1`, the clip ends with the move, accepted credits, finite channels, unit quaternions, contacts in [0, 1],
  no root travel; (3) contact pose: striking foot in front of the hip (> 0.4 studs; knees > 0); (4) the 9 string
  follow-ups start within 0.35 studs of the previous clip's last displayed frame; (5) every clip in the folder binds a
  Roster kick-type move (49).
- The follow-up (§0) and the string rebuild (§0b) changed clips after that Studio run; they are verified offline only
  (the integrator runs the suite at integration).
- **Offline:** cliplint `49 modules, 223.9 KB (budget 2048 KB) OK`; contact error 0 f on 49/49; joint-limit
  violations (knee/elbow direction, hyper-flexion, twisted planted knee, limb through torso, below the floor,
  floating plant) 0 on 49/49.

## 4. Coverage

Columns: tip = striking foot (knee for knees) ahead of the sim root along the facing on the first active frame,
after the root advance; range+adv = Roster `range` + `advance`; reach err % = tip vs `range` (root to root, so
−8…−18 % is the defender's surface offset, see §2); slide = max planted-foot drift; speed flags = frames where a limb
moves > 0.22 leg/frame (> 0.5 for the striking leg) or changes speed by > 0.16 leg/frame² — fast but continuous motion
in spins and flips, listed for honesty (none is a joint-limit problem).

| Fighter | Key (input, height) | Clip module | Sources | Contact err (f) | Tip at F1 / range+adv (studs) | Reach err % vs range | Surface gap (studs) | Max support slide (cm) | Joint-limit viol. | Speed flags |
|---|---|---|---|---|---|---|---|---|---|---|
| Kael | ShinKick (d+3, Low) | Kick_Kael_ShinKick | keyed (original:motionkicks) | 0 | 3.29 / 4.00+0.00 | -17.8 | -0.49 | 0.1 | 0 | 0 |
| Kael | LegKick (d+4, Low) | Kick_Kael_LegKick | accad-male2-g8-roundhouseleft + keyed edits | 0 | 4.11 / 3.80+0.60 | +8.1 | -1.51 | 0.2 | 0 | 0 |
| Kael | FrontKick (3, Mid) | Kick_Kael_FrontKick | keyed (original:motionkicks) | 0 | 3.41 / 3.90+1.10 | -12.5 | +0.02 | 0.1 | 0 | 0 |
| Kael | Roundhouse (4, High) | Kick_Kael_Roundhouse | accad-male2-g8-roundhouseleft + keyed edits | 0 | 3.80 / 4.40+0.80 | -13.6 | -0.01 | 0.1 | 0 | 0 |
| Sierra | JabKick (1,3, Mid) | Kick_Sierra_JabKick | keyed (original:motionkicks) | 0 | 3.17 / 3.75+1.35 | -15.5 | +0.11 | 0.1 | 0 | 0 |
| Sierra | Teep (3, Mid) | Kick_Sierra_Teep | keyed (original:motionkicks) | 0 | 3.34 / 3.80+1.40 | -12.2 | -0.01 | 0.1 | 0 | 0 |
| Sierra | TeepKick (3,4, High) | Kick_Sierra_TeepKick | accad-male2-g8-roundhouseleft + keyed edits | 0 | 4.47 / 5.20+0.30 | -14.0 | +0.12 | 0.1 | 0 | 0 |
| Sierra | HighRoundhouse (4, High) | Kick_Sierra_HighRoundhouse | accad-male2-g9-roundhouserightt2 + keyed edits | 0 | 3.92 / 4.50+0.90 | -13.0 | -0.03 | 0.9 | 0 | 0 |
| Sierra | DoubleRoundhouse (4,4, Mid) | Kick_Sierra_DoubleRoundhouse | accad-male2-g15-roundhousebodyright + keyed edits | 0 | 3.86 / 4.35+0.85 | -11.3 | +0.02 | 0.1 | 0 | 0 |
| Sierra | SpinningBackKick (b+4, Mid) | Kick_Sierra_SpinningBackKick | accad-male2-g4-spinningbackkick + keyed edits | 0 | 3.79 / 4.25+1.15 | -10.8 | -0.01 | 1.1 | 0 | 1 |
| Sierra | KneeStrike (f+3, Mid) | Kick_Sierra_KneeStrike | keyed (original:motionkicks) | 0 | 1.98 / 2.80+1.60 | -29.1 | +0.25 (knee, 2.80 floor) | 0.1 | 0 | 0 |
| Sierra | SwitchKick (df+3, Mid) | Kick_Sierra_SwitchKick | keyed (original:motionkicks) | 0 | 2.30 / 2.80+1.40 | -18.0 | +0.03 | 0.1 | 0 | 0 |
| Sierra | LegKick (d+4, Low) | Kick_Sierra_LegKick | accad-male2-g15-roundhousebodyright + keyed edits | 0 | 2.95 / 4.00+0.00 | -26.4 | -0.15 | 1.3 | 0 | 0 |
| Sierra | LowSweep (db+4, Low) | Kick_Sierra_LowSweep | keyed (original:motionkicks) | 0 | 3.24 / 4.00+0.60 | -19.0 | -0.44 | 0.1 | 0 | 0 |
| Sierra | AngleKick (ss+3, Mid) | Kick_Sierra_AngleKick | accad-male2-g10-roundhouseleadingleft + keyed edits | 0 | 2.79 / 3.25+1.75 | -14.1 | -0.01 | 0.9 | 0 | 1 |
| Goran | KneeLift (f+3, Mid) | Kick_Goran_KneeLift | keyed (original:motionkicks) | 0 | 2.08 / 2.80+1.20 | -25.6 | +0.15 (knee, 2.80 floor) | 0.1 | 0 | 0 |
| Goran | PushKick (3, Mid) | Kick_Goran_PushKick | keyed (original:motionkicks) | 0 | 3.35 / 3.80+1.20 | -11.7 | -0.02 | 0.1 | 0 | 0 |
| Goran | ClubKick (4, Mid) | Kick_Goran_ClubKick | accad-male2-g14-roundhousebodyleft + keyed edits | 0 | 4.53 / 4.80+0.20 | -5.6 | -0.20 | 1.3 | 0 | 0 |
| Goran | Stomp (d+3, Low) | Kick_Goran_Stomp | keyed (original:motionkicks) | 0 | 2.77 / 3.80+0.30 | -27.0 | -0.17 | 0.1 | 0 | 0 |
| Goran | LegHook (d+4, Low) | Kick_Goran_LegHook | keyed (original:motionkicks) | 0 | 2.44 / 3.80+0.50 | -35.8 | +0.16 | 0.1 | 0 | 0 |
| Lumi | PalmHeel (1,4, Mid) | Kick_Lumi_PalmHeel | accad-male2-g20-reversespincrescentright + keyed edits | 0 | 3.04 / 3.50+1.40 | -13.1 | -0.01 | 0.1 | 0 | 8 |
| Lumi | SnapKick (3, Mid) | Kick_Lumi_SnapKick | keyed (original:motionkicks) | 0 | 3.32 / 3.80+1.00 | -12.6 | +0.01 | 0.1 | 0 | 0 |
| Lumi | SnapCrescent (3,4, High) | Kick_Lumi_SnapCrescent | accad-male2-g13-crescentright + keyed edits | 0 | 3.17 / 3.75+1.45 | -15.4 | -0.03 | 0.1 | 0 | 1 |
| Lumi | CrescentKick (4, High) | Kick_Lumi_CrescentKick | accad-male2-g13-crescentright + keyed edits | 0 | 2.99 / 3.60+1.60 | -16.9 | +0.00 | 0.1 | 0 | 1 |
| Lumi | CartwheelKick (b+3, Mid) | Kick_Lumi_CartwheelKick | accad-male2-g7-capoeira + keyed edits | 0 | 3.26 / 3.70+1.50 | -11.9 | -0.03 | 0.1 | 0 | 6 |
| Lumi | FlipKick (df+4, Mid) | Kick_Lumi_FlipKick | keyed (original:motionkicks) | 0 | 2.59 / 3.10+0.90 | -16.6 | +0.04 | 0.1 | 0 | 13 |
| Lumi | SlideKick (d+4, Low) | Kick_Lumi_SlideKick | keyed (original:motionkicks) | 0 | 3.37 / 3.40+1.80 | -0.8 | -1.17 | 0.1 | 0 | 0 |
| Lumi | QuickLow (d+3, Low) | Kick_Lumi_QuickLow | keyed (original:motionkicks) | 0 | 3.32 / 4.00+0.00 | -16.9 | -0.52 | 0.1 | 0 | 0 |
| Lumi | ScissorKick (f+4, High) | Kick_Lumi_ScissorKick | keyed (original:motionkicks) | 0 | 2.92 / 3.50+1.70 | -16.6 | -0.03 | 0.1 | 0 | 2 |
| Lumi | VaultKick (f,f+3, Mid) | Kick_Lumi_VaultKick | keyed (original:motionkicks) | 0 | 3.64 / 4.10+1.50 | -11.2 | -0.01 | 0.1 | 0 | 3 |
| Lumi | TwirlKick (ss+4, High) | Kick_Lumi_TwirlKick | accad-male2-g19-reversespincrescentleft + keyed edits | 0 | 2.84 / 3.35+1.65 | -15.2 | -0.10 | 0.3 | 0 | 6 |
| Lumi | KneeRush (f+3, Mid) | Kick_Lumi_KneeRush | keyed (original:motionkicks) | 0 | 2.06 / 2.80+1.60 | -26.4 | +0.17 (knee, 2.80 floor) | 0.0 | 0 | 2 |
| Rhys | PunchKick (2,4, High) | Kick_Rhys_PunchKick | cmu-135_07-e3 + keyed edits | 0 | 3.96 / 4.65+0.55 | -14.9 | +0.08 | 0.1 | 0 | 0 |
| Rhys | FrontSnap (3, Mid) | Kick_Rhys_FrontSnap | keyed (original:motionkicks) | 0 | 3.34 / 3.80+1.00 | -12.1 | -0.01 | 0.1 | 0 | 0 |
| Rhys | AxeKick (4, Mid) | Kick_Rhys_AxeKick | keyed (original:motionkicks) | 0 | 2.78 / 3.25+1.65 | -14.5 | +0.00 | 1.9 | 0 | 0 |
| Rhys | RisingKnee (df+3, Mid) | Kick_Rhys_RisingKnee | keyed (original:motionkicks) | 0 | 1.66 / 2.80+1.10 | -40.7 | +0.57 (knee, 2.80 floor) | 0.2 | 0 | 0 |
| Rhys | LowSweep (db+4, Low) | Kick_Rhys_LowSweep | keyed (original:motionkicks) | 0 | 3.40 / 3.90+0.50 | -12.8 | -0.70 | 0.1 | 0 | 0 |
| Rhys | LowKick (d+4, Low) | Kick_Rhys_LowKick | accad-male2-g14-roundhousebodyleft + keyed edits | 0 | 4.19 / 4.00+0.00 | +4.6 | -1.39 | 0.1 | 0 | 0 |
| Rhys | SideKick (f+3, Mid) | Kick_Rhys_SideKick | keyed (original:motionkicks) | 0 | 3.40 / 3.85+1.45 | -11.8 | -0.02 | 0.1 | 0 | 0 |
| Rhys | CrescentStep (ss+4, Mid) | Kick_Rhys_CrescentStep | accad-male2-g12-crescentleft + keyed edits | 0 | 3.76 / 4.25+0.55 | -11.5 | +0.02 | 0.1 | 0 | 0 |
| Nia | FlurryKick (1,1,4, Mid) | Kick_Nia_FlurryKick | accad-male2-g15-roundhousebodyright + keyed edits | 0 | 3.70 / 4.20+0.90 | -12.0 | +0.03 | 0.1 | 0 | 0 |
| Nia | PalmKick (2,3, Mid) | Kick_Nia_PalmKick | keyed (original:motionkicks) | 0 | 3.26 / 3.80+1.00 | -14.3 | +0.07 | 0.1 | 0 | 0 |
| Nia | RisingFrontKick (3, Mid) | Kick_Nia_RisingFrontKick | keyed (original:motionkicks) | 0 | 3.11 / 3.60+1.20 | -13.6 | +0.02 | 0.1 | 0 | 0 |
| Nia | HighKick (4, High) | Kick_Nia_HighKick | accad-male2-g9-roundhouserightt2 + keyed edits | 0 | 3.94 / 4.55+0.65 | -13.5 | +0.00 | 0.1 | 0 | 0 |
| Nia | LowSpin (d+3, Low) | Kick_Nia_LowSpin | keyed (original:motionkicks) | 0 | 3.10 / 4.00+0.00 | -22.5 | -0.30 | 0.1 | 0 | 0 |
| Nia | RisingTornado (d+3,4, Mid) | Kick_Nia_RisingTornado | keyed (original:motionkicks) | 0 | 2.79 / 3.10+1.50 | -10.0 | -0.16 | 0.1 | 0 | 0 |
| Nia | ButterflyKick (f+4, Mid) | Kick_Nia_ButterflyKick | cmu-88_06-e1 + keyed edits | 0 | 3.37 / 3.85+1.15 | -12.5 | +0.01 | 0.1 | 0 | 21 |
| Nia | LowSweep (db+4, Low) | Kick_Nia_LowSweep | keyed (original:motionkicks) | 0 | 3.15 / 3.90+0.50 | -19.3 | -0.45 | 0.0 | 0 | 0 |
| Nia | TornadoKick (ss+4, High) | Kick_Nia_TornadoKick | accad-male2-g20-reversespincrescentright + keyed edits | 0 | 3.09 / 3.75+1.35 | -17.7 | +0.05 | 1.4 | 0 | 9 |

## 5. Evidence (all looked at)

- `OV6\work\motionkicks\sheets\Kick_<Fighter>_<Key>.png` (49) — own renderer from the decoded module: side, front
  and top rows, sim-root triangle, reach line, target height, contact frame outlined red, planted feet circled;
  strings show the previous move's first / hit / last-displayed frames first. Verdict: chambers, pivots, snaps and
  clean returns read correctly; contact on the red frame for all 49.
- `OV6\work\motionkicks\clipsheets\<Fighter>_<Key>.png` (49) — motioncore's `clipsheet.py` with the real
  startup/active/recovery. Verdict: the same poses on the reference skeleton; no broken knees/elbows, nothing below
  the floor.
- `OV6\work\motionkicks\studio\burst\*_sheet.png` (12) — Studio Play bursts: real sim (Training match on
  Arena_MidnightRooftop, `startMoveNow` loop from a temporary harness, removed) + MotionPlayer on the final rigs:
  Sierra Teep / HighRoundhouse / LegKick, Kael Roundhouse (vs Goran), Goran ClubKick / KneeLift, Lumi FlipKick /
  CartwheelKick, Nia ButterflyKick / TornadoKick, Rhys SideKick / LowSweep. Verdict: kicks connect at range (block
  sparks, knockdown on the sweep), support feet stay planted, acrobatics read as intended; TornadoKick's jump is
  small. The CartwheelKick and FlipKick bursts show the versions before the follow-up (rear-leg cartwheel, later
  push-off).
- `OV6\work\motionkicks\metrics.json`, `coverage_rows.json`, `tips.txt` (tip at F1 / max per kick), `cliplint.txt`,
  `stepin_table.json` (combat's final REQUEST 7 table), `adv_base.json`.

## 6. Known issues

- Speed flags remain in the fastest moves (Nia ButterflyKick 21, Lumi FlipKick 13, Nia TornadoKick 9, Lumi PalmHeel 8, Lumi TwirlKick 6; 1–3 in 8
  others): legs/elbows move 0.22–0.38 leg lengths per frame because 360° spins and flips must fit 13–18 startup
  frames (≈ 24–30°/frame body rotation). The motion is continuous (no pose jumps), but these moves are faster than a
  real athlete.
- Knees stop short at max range (surface gap +0.15…+0.57: KneeLift, KneeStrike, KneeRush, RisingKnee) because combat
  floored their range at 2.80; combat accepted this ("knees under the floor need nothing"). Nia RisingTornado
  overreaches by 0.16 (combat accepted). Low kicks and sweeps pass the knee line by design.
- Crush windows now match the body from their first frame (§0). To get there, CartwheelKick's dive is fast: the head
  drops about 0.25 leg lengths per frame on f3–5 (5 of its 6 speed flags). Nia ButterflyKick (not in the follow-up
  list, unchanged) is 0.08 L off the floor on its first low-crush frame (f6).
- Sierra AngleKick: after the kick the body steps 0.37 leg forward in the last 6 frames to catch up with the sim root
  (the root advanced 1.75 studs while the body leaned away from the kick).
- String starts are baked from motionstrikes' final export (02:16; Strike_Sierra_Jab, Strike_Lumi_Palm,
  Strike_Rhys_StraightPunch, Strike_Nia_DoubleChop, Strike_Nia_PalmThrust). If those clips change, run
  `python build.py Sierra.JabKick,Lumi.PalmHeel,Rhys.PunchKick,Nia.FlurryKick,Nia.PalmKick` and re-export; the
  coverage test's string check flags gaps > 0.35 studs. My test samples the previous clip on `startup + active` (the
  last displayed frame), motionstrikes' on `startup + active + 1`; both are within the runtime's 0.05 s crossfade.
- The reach pass (§0b) was applied only to the five rebuilt string clips. Eleven other accepted clips still have a
  near-floor foot the plain IK cannot reach on a few frames and rely on motioncore's runtime reach net (no-net lift:
  TwirlKick 0.46, KneeRush 0.37, AngleKick 0.30, SpinningBackKick 0.25, RisingKnee 0.24, TornadoKick 0.21, AxeKick
  0.20, KneeStrike 0.17, ClubKick 0.10, Nia LowSweep 0.10, Sierra LegKick 0.08 studs). `python build.py <those keys>`
  applies the same pass; not done before release to keep them byte-identical.
- The aim layer is runtime-only: my sheets and clipsheets show the authored heights; the Studio bursts include it.

## 7. REQUESTs

- None for the runtime. Integrator: install `handoff\motionkicks-src` as is (the module names create the
  `Clips.Moves.Kicks` path); any further re-export of motionstrikes' Jab / Palm / StraightPunch / DoubleChop /
  PalmThrust needs the 5-clip rebuild above.
