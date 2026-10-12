# FightingLab mocap research — report v1 (final)

Owner: mocap-research. Folder: `OV6\research\motion\` → `catalog.json` (263 segments), `raw\` (117 MB, only
catalogued files), `tools\`, `sheets\` (73 contact sheets), `verify-report.txt`.
Verification: `python tools\verify_catalog.py` → **`[VERIFY] 263 entries, 162 files parsed, 0 errors`**.
Quality scores were set after looking at the stick-figure sheets (5 = drop-in, 4 = clean real mocap of the exact
move, 3 = usable with trimming/retiming, 2 = rough/stylised/untrained, 1 = reference only).

## 1. Accepted sources (license quotes, URLs, credit)

| Source | License (verbatim) + URL | Credit line to ship (Credits screen) |
|---|---|---|
| **ACCAD Open Motion Project** (Ohio State) — martial artist "Male2": stances, footwork, 16 punches, 8 blocks, dodges/ducks, 20 kicks, victory, taunt, bow, crouch | "Open Motion Project by ACCAD/The Ohio State University is licensed under a Creative Commons Attribution 3.0 Unported License." — https://accad.osu.edu/research/motion-lab/mocap-system-and-data (license https://creativecommons.org/licenses/by/3.0/) | "Motion capture data from the Open Motion Project by ACCAD/The Ohio State University, licensed under CC BY 3.0." |
| **CMU Graphics Lab Motion Capture Database** — karate (subject 135), boxing, getups (140), falls (90), footwork, emotes | Home page http://mocap.cs.cmu.edu/: "This dataset of motions is free for all uses." … "This data is free for use in research projects. You may include this data in commercially-sold products, but you may not resell this data directly, even in converted form. If you publish results obtained using this data, we would appreciate it if you would send the citation to your published paper to jkh+mocap@cs.cmu.edu, and also would add this text to your acknowledgments section: The data used in this project was obtained from mocap.cs.cmu.edu. The database was created with funding from NSF EIA-0196217." FAQ http://mocap.cs.cmu.edu/faqs.php: "The motion capture data may be copied, modified, or redistributed without permission." | "The data used in this project was obtained from mocap.cs.cmu.edu. The database was created with funding from NSF EIA-0196217." |
| **Quaternius Universal Animation Library 1 & 2 [Standard]** (hand-keyed, not mocap) — hit reactions, knockback, death/KO, lay-to-idle getup, roll, crouch idle | Pack `License.txt`: "License: CC0 1.0 Universal (CC0 1.0) Public Domain Dedication https://creativecommons.org/publicdomain/zero/1.0/". itch.io page https://quaternius.itch.io/universal-animation-library : "Free to use in personal, educational and commercial projects. (CC0 License)" (UAL2: https://quaternius.itch.io/universal-animation-library-2, same License.txt) | optional: "Animations: Universal Animation Library by Quaternius (CC0)." |
| **100STYLE** (Ian Mason) — accepted license, evaluated, **nothing catalogued** | "For creative or commercial work please credit in an appropriate way. E.g. 'The 100STYLE Dataset - Ian Mason'. This work is licensed under a Creative Commons Attribution 4.0 International License." — https://www.ianxmason.com/100style/ (also Zenodo record 8127870, cc-by-4.0) | (only if used) "The 100STYLE Dataset - Ian Mason (CC BY 4.0)" |

Every catalog entry carries its own `license`, `credit` and `url`. No Bandai Namco / Mixamo / game-ripped / franchise-named
data was downloaded. CMU: 126 targeted trials were fetched (not a crawl — the site asks not to be crawled) and pruned to the 61 catalogued trials + 24 skeletons.
100STYLE verdict after sheets: locomotion styles on curved walking paths with T-pose segments; the "Punch"/"Kick"/
"KarateChop"/"Sweep" styles are walks with occasional arm/leg flourishes and "Sweep" is not a leg sweep → not useful
for a fighter; files deleted, re-enable via `STY_INCLUDE` in `build_catalog.py` if ever wanted.

## 2. Rejected / not accepted

| Source | Reason |
|---|---|
| SFU Motion Capture DB (mocap.cs.sfu.ca; has kendo + wushu kicks) | "This dataset of motions is free for research purposes. The data cannot be used for commercial products or resale, unfortunately." (https://mocap.cs.sfu.ca/) |
| HDM05 (Bonn/MPI; punches, kicks, `hitRHandHead`, `lieDownFloor`, `standUpLieFloor`) | CC BY-SA 3.0 — ShareAlike is more than "attribution only" → fails our rule. Would be the best mocap hit-reaction/lie/getup library **if the user explicitly accepts ShareAlike for derived animation data** (decision for the user, not us). |
| KIT Whole-Body Human Motion DB | registration wall, no license text found, robotics content |
| Rokoko Motion Library | account-gated marketplace ("Download today and get 150 free assets") |
| Truebones | Gumroad-gated, EULA not verifiable |
| Mixamo, Bandai Namco research dataset, Ubisoft LaFAN1 (CC BY-NC-ND), AMASS & derivatives (NC), Human3.6M/TotalCapture (research-only) | excluded by rule |
| OpenGameArt / itch.io (other than Quaternius) | nothing fighting-specific with a clean license found in the sweep |

Details/quotes: `work\secondary-sources.md`.

## 3. Coverage vs Priority A (best clip first; ids are `catalog.json` ids)

| Need | Best clips | Verdict |
|---|---|---|
| Fighting stance / boxing bounce | `accad-male2-e8-bounce` (q4, loopable bounce, guard up), `accad-male2-d1-standtoready` (stand→stance), `accad-male2-d15-switchstance`, `cmu-76_04` guard pose, `cmu-14_01` boxing bounce (whole take) | **good** (one kickboxing/karate-ish stance actor; boxing in CMU; no wrestler crouch) |
| Walk forward / back in stance | single steps `accad-male2-e3-advance-s1..s6` (0.6–0.67 m per step, 0.9–1.0 s), `accad-male2-e5-retreat-s1..s5` (0.5–0.66 m, 0.7–1.1 s) | **good** (speed up ~2× to hit 5/4 studs/s) |
| Forward dash | `accad-male2-e4-quickadvance-s2/s3/s4` (0.86–0.89 m ≈ 3.1 studs in 0.40–0.50 s), `accad-male2-e7-superfastadvance-s2/s3` (0.96–0.99 m in 0.53 s) | **good** (target 3 studs/14 f@60 → play ~1.7–2× faster) |
| Backdash / hop back | `accad-male2-e6-quickretreat-s2/s3/s5` (−0.70…−0.83 m ≈ 2.5–3 studs in 0.33–0.40 s), `cmu-76_11-s2` | **good** (closest to target: 3 studs/18 f) |
| Sidestep | `accad-male2-e9-sidestepleft` (+s2: 0.51 m), `accad-male2-e10-sidestepright` (−0.68 m), `cmu-102_28-s3/s4` (defensive slides) | **ok** — real in-stance sidesteps but slow (0.9–1.3 s); compress to ~16 f |
| Crouch / duck | `accad-male2-e21-duckleft`, `-e22-duckright` (q4 weave-duck), `quat-ual1-crouch-idle-loop` (crouch-guard pose), `accad-male2-d14-readytocrouch` / `-d13-crouchtoready` (very deep, limit depth) | **ok** |
| Guard / blocking | high `accad-male2-e11-blocklefthigh`, `-e13-blockrighthigh`; mid `-e15`, `-e16`; low `-e12`, `-e14`, `-e18` | **good** (karate-style arm blocks; contactFrame = block formed) |
| Jab / cross | `accad-male2-e1-jableft` (c35), `-e2-jabright` (c25), `-e3-crossleft` (c25), `-e4-crossright` (c21) | **good** |
| Hook / uppercut | `accad-male2-e5-hookleft` (c28), `-e6-hookright` (c32), `-e7-uppercutleft` (c25), `-e8-uppercutright` (c17) | **good** |
| Body blow | `accad-male2-e9/e10-bodyhook*`, `-e13/e14-bodycross*`, `-e15/e16-bodyjab*` | **good** |
| Overhand | none labelled (backfist `accad-male2-e12-backfistright` is the closest arc) | **gap** |
| Front / push kick | `accad-male2-g2-frontkick` (c22), `-g17/g18-pushkick*`, `cmu-135_04-e1..e3` (karate mae-geri, q4) | **good** |
| Roundhouse high / mid | high `accad-male2-g10-roundhouseleadingleft` (c24, foot at head height); mid `-g8`, `-g9-…t2`, `-g11`, `-g14/g15-roundhousebody*` | **good** |
| Low kick | none clean (`accad-male2-g17-pushkickleft` lands low, 0.75 m) | **gap** |
| Side kick | `accad-male2-g1-sidekickleadingleft` (c34), `-g3-sidekickleadingright` (c21) | **good** |
| Spinning / back kick | `accad-male2-g4-spinningbackkick` (c38), `-g5-backkick`, `-g19/g20-reversespincrescent*` | **good** |
| Knee | `cmu-86_06-e2/e3` (untrained, q2) | **weak** |
| Sweep | none (100STYLE "Sweep" is not a leg sweep) | **gap** |
| Hit reactions head / body | `quat-ual1-hit-head` (14 f), `quat-ual1-hit-chest` (11 f) — hand-keyed, subtle | **weak** (no mocap hit reactions under an accepted license) |
| Low (leg) hit, stagger | `quat-ual2-idle-shield-break` (guard-break stagger, q2); CMU stumbles are reference-only (q1) | **gap/weak** |
| Knockdown fall backward / forward | `cmu-90_18` rug-pull fall flat on back (c117 = pelvis hits floor), `quat-ual2-hit-knockback` (hit → thrown back → flat, 26 f, root motion), `cmu-90_16` fall on face (c446); `cmu-90_17` is a comedic banana slip (q2) | **ok** |
| Launched / airborne → land | `quat-ual2-hit-knockback` (partial), `quat-ual1-jump-land`, `quat-ual2-ninjajump-land` | **weak** |
| Lying on ground | `accad-male1-a9-liedown` (face up, 8 s still); first frames of `cmu-140_01/02` (face down) and `cmu-140_08/09` (face up) | **ok** |
| Getups face up / face down / side | face up `cmu-140_08` (c448 = pelvis leaves floor), `cmu-140_09`; face down `cmu-140_01`, `cmu-140_02`; side `cmu-140_03/04`; quick `quat-ual2-laytoidle` (47 f) | **good** |
| Quick roll | `quat-ual1-roll` (forward combat roll, hand-keyed) | **weak** |
| KO fall | `quat-ual1-death01` (buckle → fall on back, 73 f), `cmu-90_18` | **ok** |
| Victory / defeat | `accad-male2-d10-victory2`, `-d9-victory1` (q4), `cmu-79_69` very happy, `cmu-79_94` flexing; defeat `cmu-79_71` sad, `cmu-79_74` upset, `quat-ual2-idle-no-loop` | **ok** |

Priority B: blocks with arm motion — good (ACCAD E11–E18, CMU 135_05/135_10, 144_07/26); kata — `cmu-135_01` Bassai,
`cmu-135_06` Heian Shodan, `cmu-135_02` Empi, `accad-male2-form-1`; footwork drills — ACCAD E-series, `cmu-102_27/28`;
strings/combos to mine — `accad-male2-extended-1/2/3`, CMU boxing takes (`cmu-14_01` lists every auto-detected punch
`frame:hand-type` in `notes`); taunts/bow intro — `accad-male2-d11/d12` taunt, `-d8-bowtoready`.
**Missing in all accepted sources: throws/grapples (two-person), elbows, palm strikes, sweeps, low kicks, overhand,
real mocap hit reactions.** These need hand-keying (or the user accepting HDM05's CC BY-SA for `hitRHandHead`).

### Follow-up candidate for the stagger / body-hit gap (license OK, NOT downloaded)
**"Full Body Motion Capture of Single Individuals Following External Perturbations from Different Directions"**
(T. Chatagnon, 2024) ? https://zenodo.org/records/10512652 ? Zenodo license id `cc-by-4.0`. 21 adults pushed with a
pole at shoulder height from 0/45/90/135/180?, low/medium/high force, balance recovery with and without steps;
45-marker Qualisys C3D at 200 Hz. Realistic push-stagger + recovery steps (gentle pushes, not punches). Not fetched:
one 1.18 GB `.7z` (whole-archive download) and marker-only data (needs marker?joint solving, e.g. joint centres from
anatomical marker pairs). Worth it only if hand-keyed staggers look wrong. Credit would be "Chatagnon, T. (2024).
Full Body Motion Capture of Single Individuals Following External Perturbations from Different Directions. Zenodo,
CC BY 4.0."

## 4. Notes for the motion agents (retargeting)

- **Frames**: `start`/`end`/`contactFrame` are 0-based indices into the file's frames (`frameIndexBase: 0`; CMU AMC
  frame label = index + 1). `fps` is per entry: ACCAD 30 (a few general takes 120), CMU 120 except subjects 74–80/87/88
  = 60, Quaternius 30. Resample to your 60 Hz clip format.
- **contactFrame meaning**: strikes = max reach toward the target (impact); blocks = block fully formed; duck = lowest
  head; dodge = max head displacement; getups = frame the pelvis leaves the floor; falls = frame the pelvis reaches the
  floor; Quaternius hits = 0 (reaction starts at impact; `peakFrame` = max displacement). Strike entries also carry
  `contactHeightM`, `contactHeightRatio`, `heightClass` (high/mid/low) and `strikeDirDeg`.
- **lead** = the limb that performs the action (detected from motion, not the file name; ACCAD block names
  "Left/Right" refer to the side, the detected arm is in `lead`). **stance** = which foot is forward at `start`.
- **Target line**: `targetDirXZ` (unit XZ vector in file coordinates) points toward the opponent. For ACCAD Male2 all
  martial-arts takes use **+Z** (verified: jab/cross/hook contact within ±6°, advance −2°, retreat 179°, sidesteps
  ±90°). The ACCAD actor's hips are bladed ~50° off that line in stance — align +Z with the fight line, NOT the hips.
  CMU/Quaternius use the initial hips facing (karate walks: travel direction).
- **Units/axes**: all exports are meters, Y-up. CMU ASF unit = 0.05644 m (1/0.45 in); ACCAD/100STYLE BVH = cm;
  Quaternius BVH (Blender export) = meters, **Z-up in the file** (the loader converts (x,y,z)→(x,z,−y)). Roblox: 1 stud ≈ 0.28 m
  (actor height 1.55–1.75 m ≈ 5.5–6.2 studs; scale to your rig's hip height).
- **Skeletons** (canonical 24-joint names in `tools\mocap.py: CANON`, mapping in `CANON_MAP`):
  ACCAD `Hips, ToSpine, Spine, Spine1, Neck, Head, Left/RightShoulder (clavicle), Left/RightArm, Left/RightForeArm,
  Left/RightHand, Left/RightUpLeg, Left/RightLeg, Left/RightFoot, Left/RightToeBase`, channels Zrot Xrot Yrot, root
  position absolute. CMU ASF bones `root, lhipjoint, lfemur, ltibia, lfoot, ltoes, lowerback, upperback, thorax,
  lowerneck, upperneck, head, lclavicle, lhumerus, lradius, lwrist, lhand, …` (positions = bone END points).
  Quaternius `root, pelvis, spine_01-03, neck_01, Head, clavicle_l, upperarm_l, lowerarm_l, hand_l, thigh_l, calf_l,
  foot_l, ball_l` (+ fingers).
- **Game mapping**: fighter on the LEFT facing right ⇒ "sidestep into the screen (W)" = step to the fighter's LEFT
  (`sidestep-left`), "toward the camera (S)" = fighter's RIGHT (`sidestep-right`). Mirror (negate x) clips whose
  `lead`/stance is opposite to what a move needs.
- **Timing vs contract**: mocap is slower than game targets — dash 0.86–0.99 m in 0.40–0.53 s vs 3 studs/14 f;
  backdash 0.70–0.83 m in 0.33–0.40 s vs 3 studs/18 f; sidestep 0.5–0.7 m in 0.9–1.3 s vs 1.8 studs/16 f. Retime the
  stepping phase, keep the planted-foot frames. Single steps were cut at pelvis-speed minima (both feet planted).
- **Known data issues**: dropped ACCAD floor takes with marker glitches (Male2 A9/A10, Female1 A09/A10: limbs below
  floor, head at 2.6 m). CMU 139_xx duplicates 77_xx (same person, CMU lists 120 vs 60 fps; we use 139 at 120).
  CMU boxing punch types are auto-classified (q2) — verify on sheets before use.

## 5. Tools (`tools\`, Python 3.13 + numpy + matplotlib)

- `mocap.py` — loader: `load_motion(path, fps=None)` parses ASF/AMC and BVH (ACCAD, CMU, Blender/Quaternius Z-up,
  100STYLE) → `Motion.positions` (N,J,3) world meters + `canon()` 24 joints. `python mocap.py <files>` prints a check.
- `build_catalog.py` — curated specs → automatic segments/contact/lead/stance/target/heights/steps → `catalog.json`;
  manual review decisions live in `catalog_overrides.json`.
- `sheets.py` — contact sheets (`--label x`, `--all`, `--ids a,b --out f.png`): side view (opponent to the right) +
  front view, 8 frames, star = contactFrame, blue = left, red = right.
- `verify_catalog.py` — parses every catalogued file, checks ranges → `verify-report.txt` (exit 1 on error).
- `export_clip.py <id…> [--fps 60]` — writes per-frame canonical positions in the **target frame** (x = actor-left,
  y = up, z = toward opponent, pelvis-start origin, floor y=0) + `rootYawDeg`, resampled; contactFrame re-based.
- `blender_glb_to_bvh.py` — Blender 5.0 headless GLB→BVH (`blender -b --factory-startup -P blender_glb_to_bvh.py --
  <glb> <outdir> <Anim1,Anim2>`), used for Quaternius `_RM` (root-motion) GLBs.
- `fetch_cmu.py`, `survey.py`, `events.py` — targeted CMU download, take survey, event detection helpers.

## 6. Evidence looked at (sheets\*.png)

punch-jab/cross/hook/uppercut: ACCAD clean, contact frames on full extension ✔ · kick-roundhouse/side/front/
spinning-back: ACCAD clean chambers + extensions, CMU 135_04 karate front kicks clean ✔, CMU 135_11 side kicks go
sideways (q2) · guard-high/low/mid: ACCAD arm blocks ✔ · getup-face-up/down: CMU 140 natural roll-to-knees getups ✔ ·
fall-backward: 90_18 flat backward fall ✔, 90_17 cartoon slip (q2) · dash-forward/backdash: ACCAD shuffle cycles
with guard held ✔ · sidestep: ACCAD lateral step in stance ✔ (slow) · duck: ACCAD weave-duck ✔ · stagger: CMU
stumbles barely react ✘ (q1) · hit-head/body: Quaternius subtle flinches (q2) · hit-knockback / ko-fall: Quaternius
clean hit→floor ✔ · getup-generic/lie-ground: ACCAD Male2/Female1 floor takes glitched → dropped · 100STYLE styles:
not fighting-relevant → not catalogued.
