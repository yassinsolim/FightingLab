# motioncore handoff — CLIP PIPELINE READY · STANCES FINAL

Owner: motioncore. Status: **CLIP PIPELINE READY** (round 1: mocap → clip modules → runtime with contact alignment,
verified in Studio and offline) and **STANCES FINAL** (round 2, §12: every fighter's displayed idle stance is final —
start and end your attack clips on `"from": "Displayed:<Fighter>"`). Code: `OV6\handoff\motioncore-src\` (runtime)
and `OV6\tools\mocap\` (tools).
Phase-2 agents: **motionstrikes** (`Clips.Moves.Strikes`), **motionkicks** (`Clips.Moves.Kicks`),
**motionthrows** (`Clips.Moves.Throws`). Read `OV6\handoff\combat-states.md` (move keys, frame data, intent lines)
together with this file.

Round 3 runtime export (Studio-verified, full suite 298/298 with all current phase-2 exports): throw **grips** and
the 4-frame defender glide (§5), non-fatal decode of malformed shipped clips (§9), relaxed face-down legs and feet,
a reworked side roll, victories/defeat that start from the displayed stance, and round-transition cuts (§11).
Nothing in the clip format changed; existing clips need no edits.

Round 4 runtime export (full suite 309/309 with every merged export): **planted feet rest on the floor** (motionstrikes
REQUEST 1; §11 "Feet") and the **camera cuts on the round reset** on the same frame as the bodies (§11). No clip
or format changes.

Round 5 runtime export (full suite 310/310 with every merged export): the **reach net** — a foot target beyond the
leg's reach (step-ins: the sim carries the root by `advance` while the rear foot stays behind; keyed lunges and
spins that place a foot past the hip's reach) no longer lifts the foot off the floor (§11 "Reach net"). New test:
`MotionGround_Test` "move clips never lift a foot…" plays all 113 installed move clips (both throw roles, break tracks,
grab attempts) at max and close range. No clip or format changes; clips that relied on the lift need no edits.
Round 5b (motionstrikes REQUESTs 3 and 4): a released foot lock **lets go over 4 frames** instead of snapping, and a
step-in **held back at Separation** (keepApart capped the advance) no longer steps in place (§4, §11). Two more
`MotionGround_Test` cases cover them on every move clip. Still no clip or format changes.

Overhaul round 4 (motion QA, branch `r4-motion`): a smoothness / joint-limit / clipping **QA harness on the real rigs**,
runtime fixes for every root cause it found (transitions, hitstop, IK continuity, strike contact, self clearance, feet),
re-timed throw clips, an eased fight camera and the `MotionQA_Test` suite — see §13.

Overhaul round 5 (branch `r5-motion`): knockdowns into getups **without the 180-degree spin** (a turn-over clip and a
rebuilt side roll; whole-body turns ≤ 12.2 deg/frame, limbs ≤ 29.5), **point-blank strikes that land on the surface**
(lunge spacing + contact push-back), **no gloves or forearms in the own body on the floor or when thrown** (also when
breaking a throw), and **Kael's face readable** from the fight camera behind a real guard — tests in
`MotionQARound5_Test`; see §14.

---------------------------------------------------------------------------------------------------------------------

## 0. Quick start (one move, no Studio)

```powershell
cd C:\Users\solim\.copilot\session-state\e3751321-5f48-4183-b62a-9577765df8cf\files\overhaul6
# 1. describe the clip(s) in a spec (see §6 / §7), e.g. tools\mocap\specs\example-moves.json
python tools\mocap\convert.py --spec tools\mocap\specs\example-moves.json --out <your src dir> --review <your review dir>
#    (hand-keyed moves and throws: python tools\mocap\keyed.py --spec <keyed.json> --out <your src dir>)
# 2. look at it the way the game will play it (Kael Jab: impact frame 10 = startup 9, active 2, recovery 12)
python tools\mocap\clipsheet.py <your src dir>\ReplicatedStorage.FightingLab.Client.Motion.Clips.Moves.Strikes.Example_Kael_Jab.luau --startup 9 --active 2 --recovery 12
# 3. lint everything you made (credits header, decode, roster/move keys, duplicates, size budget)
python tools\mocap\cliplint.py <your src dir>
```

The output file name is the Studio path: `ReplicatedStorage.FightingLab.Client.Motion.Clips.Moves.Strikes.<Name>.luau`
→ ModuleScript `Client.Motion.Clips.Moves.Strikes.<Name>`. Drop it into Studio (sync like any other source file);
nothing else has to be registered.

Python 3 with numpy, scipy, Pillow (installed on this machine). Everything runs in seconds.

---------------------------------------------------------------------------------------------------------------------

## 1. Where clips live, how they bind

- `ClipLibrary` discovers **every ModuleScript under `Client.Motion.Clips` recursively** (any sub-folder depth) the first
  time a clip is needed (`MotionPlayer.warmClips()` is called by `CharacterPresenter.prewarm`).
  - `Clips.Core.*` — motioncore (stances, locomotion, guard, reactions, falls, getups, KO, intro/victory/defeat).
  - `Clips.Moves.Strikes.*` — motionstrikes; `Clips.Moves.Kicks.*` — motionkicks; `Clips.Moves.Throws.*` — motionthrows.
    Sub-folders inside your folder are fine (`Moves.Kicks.Sierra.Roundhouse`).
- A module **returns one clip table or an array of clip tables** (e.g. one module per fighter with all of their kicks).
  Module/clip names must be unique across all folders (duplicates are reported by `ClipLibrary.problems()`).
- **Binding**: every attack clip declares `fighter` + `move`:
  - `fighter = "Kael"` (roster id, case-insensitive: Kael, Sierra, Goran, Lumi, Rhys, Nia) or `"*"` = any fighter.
  - `move = "<key>"` — the **key column** of the moveset tables in `combat-states.md` (`Jab`, `OneTwo`, `LiverHook`, …).
  - optional `stringIndex = n` — preferred when the sim says the move is hit `n` of a string (`view.stringIndex`).
- **Precedence** (`ClipLibrary.forMove(fighterId, moveKey, stringIndex)`): this fighter + this stringIndex → this
  fighter → any fighter (`"*"`) + this stringIndex → any fighter → **no clip = the procedural archetype keyframes**
  (`Motion.Strikes/Kicks/Throws` + `MoveAnimOverrides`, unchanged) stay the fallback until coverage is 100 %.
- Throws: FLThrow1 clips bind the same way to the attacker's throw move key (`ClipLibrary.forThrow`). The defender
  plays the defender track of the ATTACKER's clip (the runtime looks up the opponent's character id).

---------------------------------------------------------------------------------------------------------------------

## 2. Clip format FLClip1 (one body track)

A module looks like this (generated — never edit `data` by hand; regenerate):

```lua
-- sources: accad-male2-e1-jableft
-- Example_Kael_Jab: generated by OV6/tools/mocap/convert.py. Do not edit by hand.
-- Source: accad-male2-e1-jableft [23:70]
-- License: CC BY 3.0 (https://creativecommons.org/licenses/by/3.0/)
return {
	format = "FLClip1",
	name = "Example_Kael_Jab",
	fps = 30,                 -- sample rate (30 recommended: plenty after the time warp, half the bytes of 60)
	frames = 48,
	loop = false,
	speed = 0.0000,           -- locomotion only: root speed of the source, leg lengths per second
	travel = { 0, 0, 0 },     -- root travel removed from the clip (leg lengths)
	contact = 0.2553,         -- normalised clip time (0..1) of the impact frame  (or contactFrame = 0-based frame)
	recover = 0.55,           -- optional: normalised time the limb is back in guard (default contact + (1-contact)/3)
	fighter = "Kael",         -- roster id or "*"
	move = "Jab",             -- roster move key
	stringIndex = 2,          -- optional
	mirror = true,            -- optional: play left/right mirrored at runtime (prefer baking the mirror, §6)
	tags = { limb = "LeftHand", aim = true, aimWeight = 1 },   -- optional, see §4
	sources = { "accad-male2-e1-jableft" },                    -- credits (see below)
	source = "accad-male2-e1-jableft [23:70]",
	layout = "vvvvccc...",    -- 58 chars, "v" = per-frame channel, "c" = constant channel
	data = "gbgfgigk...",     -- 12-bit values, 2 base64 chars each, channel-major
}
```

**Credits rule (binding, integrator):** line 1 of every module is `-- sources: <ids>` and the returned table has the
same ids in `sources = { ... }`. Ids are `research\motion\catalog.json` ids (e.g. `accad-male2-e1-jableft`,
`cmu-140_08`). Hand-keyed work uses `"original:<agent>"` (e.g. `"original:motionthrows"`); the integrator builds the
in-game credits (ACCAD CC BY 3.0, CMU acknowledgement, Quaternius) from the ids the shipped clips actually use. Both
tools write this automatically from `catalog` / `sources` in the spec; `cliplint.py` checks it.

**Channels** (per frame; Roblox character space of the clip heading: +X right, +Y up, **-Z toward the opponent**):

| channels | meaning | units / range |
|---|---|---|
| 1-3 | pelvis (root) position; Y relative to the straight-legged standing height | leg lengths (hip→sole), [-2, 2] |
| 4-7 | pelvis rotation quaternion x,y,z,w | [-1, 1] |
| 8-11 | waist = chest relative to the pelvis | quaternion |
| 12-15 | neck = head relative to the chest | quaternion |
| 16-25 / 26-35 | LeftHand / RightHand: pos(3) shoulder→hand, pole(3) elbow direction, rot(4) | arm lengths; unit vector; quaternion |
| 36-45 / 46-55 | LeftFoot / RightFoot: pos(3) hip→sole point, pole(3) knee direction, rot(4) foot rotation | leg lengths; unit vector; quaternion |
| 56, 57 | left / right foot contact (planted) | 0..1 |
| 58 | ground (body supported by the floor, lying/kneeling) | 0..1 |

Positions are proportional (limb-length units), so one clip fits every fighter: `MotionPlayer.apply` re-targets them
to each rig's real limb lengths with two-bone IK (elbow/knee poles from the clip), then the ground solver keeps every
body part out of the floor and rests lying bodies on it. Quantisation error ≤ 0.0005.

Size: a 1 s attack at 30 fps is ~3-6 KB of source. Budget for ALL clips (core + 100 moves): ~2 MB, i.e. stay around
≤ 8 KB per move clip (trim the source range to the move: a few frames of stance before the motion starts, end when the
fighter is back in guard). `cliplint.py` prints the total.

---------------------------------------------------------------------------------------------------------------------

## 3. Timing: contact alignment and per-move speed (exact rule)

The clip's own length does not matter: the runtime **time-warps every attack clip onto the move's frame data**
(`Roster` startup / active / recovery = the `i / act / rec` column of combat-states.md, `i = startup + 1`).
`view.moveFrame` f = 1..total (sim frames, 60 Hz). With D = clip duration (s) (`(frames-1)/fps`; loops `frames/fps`),
c = `contact`·D, r = `recover`·D (default `contact + (1-contact)/3`), F1 = startup + 1 (first active frame),
FA = startup + active, T = FA + recovery:

```
f <= F1           : t = c · f / F1                                   (startup plays clip [0, contact])
F1 < f <= FA + 1  : t = c + (r - c) · (f - F1) / (FA + 1 - F1)       (active window plays [contact, recover])
f > FA + 1        : t = r + (D - r) · (f - FA - 1) / (T - FA - 1)    (recovery plays [recover, end], ends at total)
```

So **the clip's contact frame is shown exactly on the first active frame** (`ClipPlayer.moveTime`; `clipsheet.py`
uses an exact copy and outlines that frame in red). "Per-move speed" therefore comes from the frame data: a 10-frame
jab and a 19-frame low roundhouse can come from captures of any speed. Pick `recover` where the striking limb is back
near the guard (snappy retraction = early recover). Hitstop freezes the pose (no time passes); string follow-ups are
separate moves (their own key) and optionally `stringIndex` variants of a shared key.

Blend: the runtime crossfades INTO a move clip over 0.05 s and back to the stance over 0.12-0.15 s, so clips should
start and end in a plain fighting stance (they do not need to match each fighter's guard style exactly).

---------------------------------------------------------------------------------------------------------------------

## 4. Root motion and contact aim

- **Attack clips are in place horizontally** (convert default `"travel": "remove"`): the sim already moves the attacker
  forward by `advance` studs spread evenly over the startup frames (combat-states `reach + adv`), and the old cosmetic
  lunge is switched off for every move that has `advance`. A step-in in the capture still shows (feet and body move
  relative to the root); only the net root travel is removed. Never add root travel to match `advance` yourself.
- Vertical root motion (crouch, hop, jump kick, dropping into a sweep) and all rotation (spins) stay in the clip.
- Planted feet (contact channels) are **locked in world space** at runtime (no skating while the body moves above them;
  a leash of 0.3 studs·scale lets a sliding foot follow when the sim pushes the body). `convert.py` computes contacts
  from the capture; `keyed.py` from the sole height (or explicit `contact`). Round 5b: when the contact drops, the lock
  lets go over `FootLockRelease` (4 frames, paced by the pose clock) instead of in one frame, so a foot held back on its
  anchor leaves it smoothly; a foot that lands again while still letting go locks where it is shown.
- **Capped step-ins** (round 5b): when keepApart holds the attacker back (opponent at Separation), the sim applies
  less than `advance`. A released foot whose clip sole is near the floor (≤ 0.12 leg lengths, fading out by 0.25)
  then lifts only the applied ÷ designed share of its clip clearance (`pose.stepScale`, counted from the move's first
  frame), so the body does not step in place; at full range nothing changes.
- **Contact aim layer**: around the impact the striking hand/foot is pulled vertically to the move's contact height
  **of the opponent** — `height` High = its head centre, Mid = its chest (UpperTorso centre), Low = its knees, as
  measured on the opponent's actual rig in its displayed stance (`MotionPlayer.standingHeights`, cached per rig by
  `CharacterPresenter`); the IK then puts the fist (hand centre) or foot at that world height through the attacker's
  real, posed shoulder/hip, so leaning body blows, crouching jabs and uppercuts, tall vs short fighters and every rig
  proportion land exactly (tests: within 0.03 studs on all six new rigs; a 40° lean + 25° waist bend lands within
  0.15 of upright). Without rig data (tests, tools) the estimate `MotionLibrary.contactY` of the opponent's
  RootHeight is used. A high still whiffs over a crouching opponent: the aim uses the standing heights, never the
  current pose. Weight ramps in over the 2nd half of startup, holds through the active frames, releases over 40 % of
  recovery. The limb comes from the roster (`limb` LeadArm/RearArm/LeadLeg/RearLeg → LeftHand/RightHand/LeftFoot/
  RightFoot for our orthodox fighters); override with `tags = { limb = "RightFoot" }`, scale with `aimWeight = 0.5`,
  disable with `aim = false` (e.g. elbows/knees/shoulder tackles, where the hand is not the contact point, or sweeps
  that should stay on the floor line). With the measured layer a full `aimWeight` is safe again for leaning strikes;
  if you bake aim into a clip, keep a small weight rather than 0 so size differences between fighters are covered.

---------------------------------------------------------------------------------------------------------------------

## 5. Throws: FLThrow1 (two synchronised roles)

```lua
-- sources: original:motionthrows
return {
	format = "FLThrow1", name = "Goran_Suplex", fighter = "Goran", move = "Throw",
	impact = 0.62,          -- normalised clip time of the impact; lands exactly on throw.impactFrame
	distance = 0.55,        -- authored root-to-root distance in ATTACKER leg lengths
	sources = { "original:motionthrows" },
	attacker = { format = "FLClip1", ... },   -- attacker's own heading space (-Z toward the defender)
	defender = { format = "FLClip1", ... },   -- DEFENDER's own heading space (-Z toward the attacker)
	breakAttacker = { format = "FLClip1", ... },   -- optional: played when the throw is broken (below)
	breakDefender = { format = "FLClip1", ... },
}
```

- Runtime input: `view.throw` = { role "Attacker"/"Defender", move, frame 1..duration, duration, impactFrame,
  breakWindow, broken, breakFrame, archetype }. Both fighters sample the SAME clip time:
  `u = impact · f / impactFrame` for f ≤ impactFrame, else `impact + (1 - impact)(f - impactFrame)/(duration - impactFrame)`;
  clip time = u · D (`MotionPlayer.throwTime`). E.g. Kael `Throw`: impact f30 of 46 (combat-states).
- Placement: both tracks are authored with the roots `distance` attacker-leg-lengths apart, facing each other. At
  runtime the defender's body is slid along its facing by (real distance − authored distance), so the bodies meet
  whatever the sim spacing is; the correction eases in over the first `MotionPlayer.ThrowAlignFrames` (4) throw
  frames (round 3), so the defender glides into the clinch instead of jumping. Each track can move its own root
  (lifts, carries, slams: root Y and Z travel are kept in throw tracks — `"travel": "none"` when converting); the sim
  keeps both roots where it put them.
- **Grips (round 3, optional)**: `grips = { { role, limb, anchor | part + at, from, to, fade, weight }, ... }` holds a
  hand (or foot) on the PARTNER's real body for a time window, whatever the two fighters' sizes. After both bodies are
  posed (`CharacterPresenter` calls `MotionPlayer.applyGrips`, attacker grips first), each active grip re-solves that
  limb through the normal IK (floor rules kept) so the hand centre / ankle reaches the point. Fields: `role`
  "Attacker"|"Defender" (whose limb), `limb` LeftHand|RightHand|LeftFoot|RightFoot, `anchor` = a named point
  (`ClipLibrary.GRIP_ANCHORS`: Collar, Chest, Back, Nape, Belly, LowBack, Left/RightHip, Left/RightShoulder,
  Left/RightElbow, Left/RightWrist, Left/RightThigh, Left/RightKnee, Left/RightAnkle — the partner's own left/right)
  or `part` = a partner R15 part + `at` = {x, y, z} in that part's box (−1..1 of the half size; x right, y up, z back,
  so −z is the front; torso fronts sit at z −1.2, just outside the surface). `from`/`to` = seconds of track time,
  `fade` (default 0.06 s) ramps the weight in/out around the window, `weight` 0..1 (default 1). Feet target the ankle
  joint: put a sole-on-belly point a little outside the surface. Grip only where the hand really holds; broken throws
  never grip. Writing: `clipio.throw_module(..., meta = {..., "grips": [...]})` or a `"grips"` list in a keyed.py
  FLThrow1 spec (sides swap with `"mirror": true`); `cliplint.py` validates them.
- After the throw the defender is in `Landing` (lying; CombatSim makes every throw knockdown `FaceUp`). End the
  defender track on **`FallBack@0.367`** (FallBack's floor contact = `contact` 0.44 × 0.833 s): Landing after a Throw
  continues FallBack from that contact (no second fall, no second floor-impact dust/thud), then Getup takes over.
  `endThrow` pushes the defender +0.45 / the attacker −0.45 studs along the attacker's facing on the frame the throw
  ends. The runtime crossfades (≥ 0.12 s) out of the last throw pose, offset by the **sim position jump only** (not the
  rendered root): with roots at 0 you see a 0.45-stud glide over the fade; bake the push into the last frames of each
  track (root z = −0.45 studs ÷ that fighter's leg length in library axes, i.e. both bodies move toward their own
  back) and the glide is zero.
- The **grab attempt** itself (startup/active/recovery of the throw move, e.g. 12/2/26, and its whiff) is a normal
  move: bind an FLClip1 to the same move key (hands reach out at the contact = first active frame). The FLThrow1 plays
  only while `view.throw` exists.
- **Break**: combat now keeps both fighters in `Throw` for `CombatConfig.ThrowBreakFrames` (16) frames after a break,
  with `throw.broken = true` and `throw.breakFrame` (the throw frame of the break; `throw.frame` keeps counting), then
  both return to Idle pushed 0.6 studs apart. While broken, each fighter plays its role's `breakAttacker` /
  `breakDefender` track (FLClip1, own heading space, standing at the authored distance) at
  `t = clamp((throw.frame - throw.breakFrame) / ThrowBreakFrames, 0, 1) · D`; throws without break tracks play the
  generic `Core.ThrowBreak` shove. The rest of the throw is never shown after a break. Author break tracks that start
  from the clinch pose of the break window (breaks happen before the impact) and end in a fighting stance.
  `keyed.py` takes `"breakAttacker": { "keys": [...] }, "breakDefender": { "keys": [...] }` in an FLThrow1 spec;
  `clipsheet.py` draws them as an extra row (`--break-frames 16`).
- Authoring: no licence-clean two-person mocap exists → hand-key both roles with `keyed.py` (§7). Check them with
  `clipsheet.py <module> --duration 46 --impact-frame 30` (draws attacker left, defender right at the authored distance).

---------------------------------------------------------------------------------------------------------------------

## 6. Converting mocap: `tools\mocap\convert.py`

```
python tools\mocap\convert.py --spec <spec.json> --out <dir> [--review <dir>] [--only Name1,Name2] [--catalog <catalog.json>]
```

Spec (JSON). Example: `tools\mocap\specs\example-moves.json`; motioncore's own: `tools\mocap\specs\core.json`.

```json
{
  "folder": "Moves.Strikes",
  "sources": {
    "accad-male2": { "root": "research/motion/raw/accad/Male2", "calib": ["Male2_D1_StandToReady.bvh", 0],
                      "license": "CC BY 3.0 (https://creativecommons.org/licenses/by/3.0/)",
                      "credit": "Motion capture data from the Open Motion Project by ACCAD/The Ohio State University, licensed under CC BY 3.0." },
    "cmu": { "root": "research/motion/raw/cmu", "license": "CMU Graphics Lab Motion Capture Database terms", "credit": "..." }
  },
  "clips": [
    { "name": "Kael_Jab", "source": "accad-male2", "catalog": "accad-male2-e1-jableft", "fighter": "Kael", "move": "Jab" },
    { "name": "Kael_Cross", "source": "accad-male2", "catalog": "accad-male2-e2-jabright", "mirror": true,
      "fighter": "Kael", "move": "Cross", "range": [10, 60], "contact": 25, "recover": 38, "tags": { "limb": "RightHand" } }
  ]
}
```

Clip fields: `catalog` (fills file, fps, range, target direction and contact from `research\motion\catalog.json`;
0-based source frames), or `source` + `file` + `fps` + `range` [first, last] (inclusive source frames);
`contact` / `recover` (source frames); `target` = source XZ direction toward the opponent ([x, z], `"pelvis"`,
`"chest"`, `"travel"`) — the catalog value aligns the strike line, not the bladed hips; `yawOffset` (deg);
`travel` `"remove"` (default, attacks) | `"none"` (throw tracks, falls) | `"linear"`/`"center"` (locomotion loops);
`mirror` (bake a left/right mirror); `loop`; `smooth` (σ, default 1 source frame at 60 Hz); `outFps` (30);
`ground` (`"auto"` or 0..1); `footLock` (true); `fighter`, `move`, `stringIndex`, `tags`, `sources` (extra credit
ids; default `[catalog]`); `reverse` (play the capture backwards); `overlay` (hand-authored layer on top of the
mocap — library axes, leg lengths / degrees, each curve `[[u 0..1, [x, y, z]], ...]` over the clip: `root` pelvis
offset with the feet planted (weight shift, dip, lean off the fight line), `rootFeet` pelvis and feet together (hop),
`rootRot` / `waist` / `neck` extra rotation; motioncore's dash lean, backdash hop and sidestep head offset are built
this way, see `specs\core.json`); `leadIn` = `{ "from": "Displayed:<Fighter>" | "<Clip>@<s>", "seconds": 0.5,
"stepMin": 0.04 }` prepends a stepped transition from that pose into the clip's first frame (body eases, feet that
must move take lifted steps with their contact released; round 3: motioncore's victories/defeat use it so they start
on the fighter's own stance; `--clips <dir>` selects where the Displayed stance is read from). Throws: `{ "format": "FLThrow1", "name", "fighter", "move", "attacker": {clip fields},
"defender": {clip fields}, "impact": <attacker source frame>, "distance": <leg lengths> }`.

**Lead side.** All six fighters stand **orthodox: left foot and left hand forward** (`LeadArm` = LeftHand, `LeadLeg`
= LeftFoot). The catalog gives `stance` (foot forward at the start of the segment) and `lead` (the limb that does the
technique). If the capture's `stance` is `right-forward`, set `"mirror": true` (most ACCAD Male2 clips are
right-forward; e.g. `e1-jableft` is already left-forward/left lead = an orthodox jab, `e2-jabright` mirrored = a rear
straight). Use runtime `mirror = true` only to reuse one clip for both sides.

**Facing**: ACCAD strikes point along the file's +Z while the actor stands ~50° bladed: keep the catalog `targetDirXZ`
(fight line), do not align to the hips. **Speed**: no need to time-compress attacks (the warp does it); keep a few
frames of anticipation before the motion — the startup frames show them.

Outputs: the module, `--review` sheet `<Name>.png` (source skeleton vs. the clip reconstructed on a reference
skeleton — side and front rows; they must read as the same motion), and `manifest-<folder>.json`.

---------------------------------------------------------------------------------------------------------------------

## 7. Hand-keyed clips: `tools\mocap\keyed.py`

For everything without licence-clean mocap — **all throws**, overhands, low kicks, sweeps, elbows, palm strikes,
shoulder tackles — key poses in JSON; `keyed.py` interpolates them into a normal FLClip1 / FLThrow1 module (same
runtime path: warp, aim, foot lock, mirroring). Full field list in the file header; example (fake move keys, so it
never binds in-game): `tools\mocap\specs\example-keyed.json`.

```
python tools\mocap\keyed.py --spec <keyed.json> --out <dir> [--only Name] [--clips <dir with Core clip modules>]
```

- Axes are LIBRARY axes for authoring: +X = fighter's right, +Y = up, **+Z = toward the opponent**.
- `"from": "Stance"` (or any installed clip: `"FallBack@1.2"` = that clip at 1.2 s) starts a key from a real mocap
  frame; later fields in the key override channels. Missing fields carry over from the previous key.
- **`"from": "Displayed:<Fighter>"`** (optionally `@<seconds>`) = that fighter's idle stance **exactly as the game
  shows it** (style stance clip + per-style yaw, guard arms, width/length/drop from the installed `Motion.States`; §12).
  Use it for the first and last key of every attack clip so the blend from/to the idle does not twist the body.
  Mocap attacks (`convert.py`) are not re-posed: pick a range that starts/ends in a similar bladed orthodox stance,
  or finish them with a keyed tail.
- `root` [x,y,z] leg lengths (y = 0 straight-legged standing; fighting stance ≈ -0.08; lying ≈ -0.95),
  `rootRot` / `waist` / `neck` [x,y,z] degrees, Roblox Euler XYZ (x+ leans back, y+ turns left, z+ leans left),
  `LeftHand`/`RightHand` { pos = shoulder→hand in arm lengths (|pos| 1 = straight), pole = elbow direction },
  `LeftFoot`/`RightFoot` { pos = hip→sole in leg lengths (y -1 under a straight leg), pole = knee direction, rot },
  `contact` { LeftFoot, RightFoot } (default from sole height), `ground` (default from pelvis height),
  `ease` of the segment ending at the key: smooth | linear | in | out | snap (fast in, use it on the impact key) | hold.
  Moving `root` keeps planted feet where they stand; `"feetFollowRoot": true` on a key carries them along (hops,
  rolls). Clip-level `"loop": true` makes a looping clip (last key = first key).
- `contact` / `recover` / throw `impact` are given in SECONDS of clip time.
- Relative fields (added on top of the carried value — handy for reactions and small variations of a mocap frame):
  `root+` [x,y,z], `rootRot+` / `waist+` / `neck+` [x,y,z] degrees (turn applied in the parent frame),
  `LeftHand+` / … `{ pos = [dx,dy,dz], pole = [..], rot = [deg] }`. motioncore's own reactions are built this way:
  `tools\mocap\specs\core-keyed.json` (hit reactions, blockstun, stagger: they START on the impact pose so the
  defender shows the impact during hitstop).
- Tips: 4-7 keys per attack (stance → anticipation → impact (snap) → follow-through → back to `"from": "Stance"`);
  poles decide how elbows/knees bend — always set them on strikes with bent limbs; real humans rotate hips before the
  shoulders and the head stays level; keep the non-striking hand at the chin.

---------------------------------------------------------------------------------------------------------------------

## 8. Verifying offline (no Studio) — and in Studio

Memory is tight: do not open extra Studios. Everything can be checked offline:

1. `convert.py --review <dir>`: source vs. reconstruction sheet (catches wrong facing, wrong mirror, bad range).
2. `clipsheet.py <module> --startup S --active A --recovery R`: the frames the GAME will show at sim frames 1..total
   after the warp (side + 3/4 rows; first active frame outlined red), reconstructed by IK on a reference
   martial-artist skeleton like `MotionPlayer.apply` does. Throws: `--duration D --impact-frame I` (both bodies).
   Without timing: evenly spaced clip frames. Look at it: contact pose at the red frame, guard hand at the chin,
   knees/elbows bending the right way, no limb through the floor, the move matches the animation-intent line.
3. `cliplint.py <dir>`: header/sources, decode, unit quaternions, roster id + move key exist in combat-states.md,
   attack clips have `contact`, duplicate bindings, total size vs. budget.

In Studio (when the integrator gives you a slot): sync your modules, then
`require(ServerStorage.UnitTest.RunUnitTest)("MotionClip", 10)` must stay green (it decodes every installed clip,
checks credits and the budget). Write your own `MotionMoves<Category>_Test`: for each clip,
`ClipLibrary.forMove(id, key)` is your clip, and `MotionPlayer.sample` at `moveFrame = startup + 1` puts the aimed limb
at its contact height (see `MotionClip_Test` "contact warp lands the clip contact exactly on the first active frame"
for a template, and `ClipLibrary.register/unregister` to install test clips). Visual check in a fight:
`FightingLabDuelDebug:Invoke("startCpu", "Arena_MidnightRooftop", 2, "Normal")` on the Server DM.
Test hygiene (all clip agents share one library): `register` shadows a shipped clip with the same binding and
`unregister` gives the binding back; for precedence/fallback checks bind your test clips to a made-up move key
(e.g. `"UT_<yourAgent>Probe"`) so other agents' installed clips never change the result.

---------------------------------------------------------------------------------------------------------------------

## 9. Runtime API (Client.Motion.*, for tests and tools)

- `ClipLibrary.index()`, `get(name)`, `find(base, styleName?)`, `forMove(fighterId, moveKey, stringIndex?)`,
  `forThrow(fighterId, moveKey)`, `register(name, raw)` / `unregister(name)` (tests), `problems()` (decode/duplicate
  errors), `sourceIds()` (all credit ids in use), `decode(raw)`; constants `CHANNELS`, `LIMB_BASE`, `CONTACT_LEFT`…
  A shipped clip that fails to decode (e.g. an unknown grip anchor) never breaks the game: it is listed in
  `problems()` (MotionClip_Test fails on it) and its move/state falls back to the keyframes. `register` (tests)
  decodes at once and raises, leaving nothing registered.
- `ClipPlayer.sample(clip, t, { mirror, legLength, scale })` → heading-space pose (round 5: each foot effector also
  carries `sole` = the clip's own sole height in leg lengths, `1 + pelvis y + hip→sole y`; crossfades blend it);
  `ClipPlayer.moveTime(clip, { startup, active, recovery }, frame)`; `ClipPlayer.progressTime(clip, elapsedFrames,
  frames)`.
- State requests (`Motion.States`): `timeMode = "progress"` plays 0..1 of a clip, optionally from
  `clip.tags[req.startTag]` seconds (round 3: the prone side roll starts at `SideRoll.tags.proneStart`).
- `MotionPlayer.sample(config, view, frame, slot)`, `apply(rig, pose, floorY)`, `collectRig(model)`,
  `resolveMove(id, key, rootHeight)`, `throwTime(impact, f, impactFrame, duration)`, `namedPose(id, name, t,
  rootHeight, legLength?)`, `standingHeights(rig, id)` (High/Mid/Low world heights of a rig in its displayed stance;
  views carry them as `aimHeights`), `applyGrips(rig, pose, view, frame, slot, partnerRig, floorY)` (throw grips,
  after both fighters were applied), `partWorld(rig, partName)` (posed part frame through the joint chain),
  `warmClips()`, `reset(slot)`, `solveTwoBone`, `extentY`; constants `ThrowAlignFrames` (4), `TeleportDistance` (3).
  Round 5: `FootReachNet` (true; false = the round-4 behaviour, for A/B checks), rig fields `footClear[foot]` (the
  height above the floor the runtime intends for each foot's lowest point in the latest apply: 0 for a planted foot,
  the clip's own clearance for a released one — compare the shown foot `tips[foot]` with it) and `footHang[foot]`.
  The contact aim layer now always marks the striking effector with `aimWeight` (also without measured heights).
  Round 5b: `FootLockRelease` (4/60 s); `sample` stamps poses with `clock` (the slot clock; `apply` paces the lock
  release with it) and, for step-ins whose advance keepApart capped, `stepScale` (applied ÷ designed advance).

---------------------------------------------------------------------------------------------------------------------

## 10. Combat facts the move agents need (from combat-states.md, forwarded)

- States: Idle (standing guard) / Walk / Backwalk (guard) / Crouch (crouch guard, `crouchFrames`) / Dash / Backdash
  (`dashFrame`/`dashTotal`) / Sidestep (`stepDir` +1 = own LEFT, `stepFrame` 1-16 travel, 17-22 recovery) /
  Startup / Active / Recovery (`move`, `moveFrame`, `stringIndex`) / Hitstun / Blockstun / Stagger / Airborne /
  Landing (on the floor, **34 f**) / Getup (**26 f**, +10 for rolls = 36 f, `getupKind` Stand/BackRoll/SideRoll,
  `rollDir`; rolls travel 2.2 studs over their first 10 frames) / KO / Throw (`throw` table).
  `Block` and `Step` no longer exist. Floor-to-standing is 60 f (70 f with a roll); motioncore starts the standing
  getup 10 frames before Landing ends (the fighter cannot act then) so the rise plays over 36 frames.
- Attacks have REAL root motion (`advance`, spread over startup) — clips stay in place (§4).
- A juggle that ends in the air keeps the fighter `Airborne` with `knockdown` already set until it lands (then
  `Landing`); motioncore plays the fall into the knockdown (face-down: the FallFrontAir clip reaches its floor contact
  exactly at touchdown). Throw breaks: `throw.broken` / `throw.breakFrame` for `ThrowBreakFrames` (§5). Throw end:
  `endThrow` push ±0.45 studs, defender lands FaceUp in Landing (§5).
- Move keys, heights, impact frames, `advance`, flags and the **animation intent** line per move: combat-states §6.
  Moves with `crouching` start from a crouch; `homing`/`tracking` turn during startup (the sim turns the root).
- Throws: impact frame and duration per throw in the `block / hit` column (e.g. "impact f30 of 46").

---------------------------------------------------------------------------------------------------------------------

## 11. What motioncore guarantees / known limits

- Core clips shipped (`Clips.Core`, 80 modules, ~293 KB): Stance (+ _Kickboxer/_Karate/_KungFu/_Grappler),
  WalkFwd, WalkBack, Dash, Backdash, SidestepLeft/Right, Crouch (+ per-style), Blockstun / CrouchBlockstun /
  HitHigh·Mid·Low × Light·Heavy / Stagger (each + _Kickboxer/_Grappler/_Karate/_KungFu variants), ThrowBreak, Juggle,
  FallBack, FallFront, FallFrontAir, GetupBack, GetupFront, BackRoll, SideRoll, KOBack, KOFront, Intro, Victory
  (Kael: celebration; _Kickboxer Sierra: arm raise, roar, back to guard; _Grappler Goran: flexing; _Flow Lumi: jubilant;
  _Karate Rhys: attention, bow, kamae; _KungFu Nia: hand-keyed fist-and-palm salute and bow), Defeat. Sources: ACCAD
  Male2 (CC BY 3.0), CMU (getups/falls/defeat/victories), Quaternius (CC0: knockback/juggle) and hand-keyed clips on
  mocap frames (`original:motioncore`: crouches, reactions, rolls, face-down crumple, kung-fu salute).
- Loader formats: ACCAD/MotionBuilder BVH, CMU ASF/AMC, Quaternius/Blender BVH (Z-up, metres, per-joint
  translation channels) — any catalog id works in a spec.
- Ground: lying/KO bodies rest on the floor (worst gap 0.03 studs, all six fighters with the characters agent's final
  rigs, face up/down) along their whole length — after the floor impact the spine settles (pelvis turns about the
  waist, head about the neck, feet come down), so a deep chest no longer props the hips, head and legs up; a lying
  body whose limb would dip under it rests on that limb; no body part below the floor in any state; planted feet lock
  in world space (≤ 0.04 studs per contact and ≤ 0.14 studs/s while planted for idle, walk and backwalk on all six).
  Throw defender tracks that end lying get the same settle once Landing takes over. Lying legs (round 3): no sole-down
  foot flattening, shins rest on the floor, and after a knockdown/KO toes that a capture tucked under the body relax
  along the floor (instep down, soles up) and drape over the ankle until the toes touch the floor (thick boots/shins
  drop further, at most 60°); a pelvis settling face down stops when the thighs reach the floor (nothing ever ends
  below it) — so authored lying feet need no special care.
- Side roll (round 3): a log roll that turns the chest toward its travel first, timed on the sim's ease-out travel
  (one full turn face up by getup frame ~14, the second half turn when starting face down), then a quick sit-up and
  the face-up mocap rise; mirrored for `rollDir` -1. Back roll unchanged.
- Round transitions (round 3): when the sim puts the fighters back on their marks (a position jump > 3 studs, or a
  KO/Victory/Defeat pose followed by the next round's Intro) the pose cuts instead of crossfading. Round 4: the camera
  (`CameraDirector`) cuts on the same frame by the same rule (`CameraDirector.TeleportDistance` =
  `MotionPlayer.TeleportDistance`, or RoundOver/MatchOver -> Ready): it starts the new round on its intro shot, with
  shake, impact push/tilt and the KO slow-mo framing cleared. Victories and the
  defeat start on the fighter's displayed stance (baked lead-in) and hold their last frame. Between rounds only ~0.9 s
  of a victory shows (RoundOver is 120 f, after motioncore's 1.1 s final-hit hold); MatchOver shows it in full.
- Feet (round 4): the foot effector is the sole point (ankle minus ankle height). Near the floor a foot is shown
  flattened sole-down and its ankle height is derived from the SHOWN orientation, so the foot's lowest point keeps the
  clip foot's clearance and a planted foot (clip contact >= 0.8, or a settling body) rests ON the floor. Before, the
  ankle height came from the clip's tilted foot and the flattened foot hovered 0.1-0.37 studs in stances, crouches,
  crouching moves and getup ends. A leg too straight to reach a flat foot keeps the heel up just enough (on the ball);
  if even the clip foot is out of reach (a straight pivot leg on a rig whose pelvis rides high), the foot rises further
  onto its ball, at most 60°. Measured on all six final rigs: every sustained planted foot within 0.004 studs in the
  stances, walks, crouch guard, every crouching/low move and every getup end. The rest of the 100 moves are within
  0.03 except 12 foot-frames in 4 Sierra kicks (≤ 0.15, straight pivot legs). Clip authors: plant a foot by its
  contact channel; there is no need to bake floor offsets into foot positions. (Round 5: those 12 are now 0.)
- Reach net (round 5): when a foot target is beyond the leg's reach from the POSED hip — the sim carries the root
  forward by `advance` while the rear foot stays behind or is locked, a keyed lunge/spin places a foot past the hip's
  reach, a lock leash drags a planted foot back — the IK clamp used to pull the foot toward the hip and UP (Kael
  ChargingCross rear foot +1.36 studs, Lumi PalmHeel +1.73). Now a foot the clip holds on or near the floor (its own
  sole ≤ 0.12 leg lengths, fading out by 0.25: steps in the air, chambers and kicks keep the old straight-leg clamp
  toward their target) keeps its height: it rises onto its ball (at most 40°), then slides along the floor toward the
  hip until the straight leg reaches it, and a world-space planted lock is re-anchored where it now stands. A pelvis
  riding higher than even a straight leg hanging under it reaches (Lumi KneeRush's support leg at the top of the
  rise) is lowered onto that foot (never below the core's floor clearance). Never on a lying body, never on a striking
  foot the contact aim pulls to the opponent (`aimWeight`). Reachable targets are untouched: every round-4 number is
  identical except one unreachable Sierra LegKick frame (0.002 → 0.003). Clip authors: a rear foot that trails a
  step-in may stay where it is in the clip — the runtime drags it on its ball as far as the leg needs; to SHOW a drag
  step on the floor, keep its sole on the floor (≤ 0.05 L) instead of lifting it a few centimetres.
- What the runtime shows above the floor on purpose (information line of the reach test, all reachable): a released
  foot (contact < 0.8) whose clip sole hovers 0.02-0.05 leg lengths up is shown at that height (0.06-0.16 studs), and
  foot targets are hip-relative, so wherever the posed pelvis sits differently from the clip's (a strongly pitched or
  rolled pelvis, a lying body that the ground solver rests on its torso) its feet move with it — e.g. Lumi SlideKick's
  sliding foot shows 0.4-0.48 studs above the floor on the lying slide although its clip sole is on it. Plant feet that
  stand (contact ≥ 0.8); lower sliding/released ones in the clip — a sole authored a little below the floor is shown ON
  it (the runtime never sinks a foot). Check with the test's information line or `rig.footClear`.
- Hitstop: attack clips freeze on the hit frame; the defender snaps to the first frame of its reaction clip during
  hitstop (so a reaction's first frame must be the impact pose). Reactions are per style and scale with height
  (high: head snap + half step back; mid: fold at the waist; low: the struck leg buckles) and strength (heavy and
  counter hits stagger further) — all inside combat's stun frames.
- Rig scale: clips are proportional; the IK fits them to every fighter (RootHeight 3.5-4.2).
- Stance style layer: idle/guard/walk/crouch poses get the per-style yaw, guard arms and stance width (§12); in
  travelling states (walks, dashes, sidesteps) the yaw turns the feet's placement but never their stride, so planted
  feet keep pace with the sim. Attack clips are played as authored (0.05 s fade in, 0.12-0.15 s fade back to the idle)
  — start and end them on `"from": "Displayed:<Fighter>"`.
- Throw breaks play the clip's break tracks or the generic `Core.ThrowBreak` (§5). Runtime `mirror` swaps limbs and negates X, nothing else.
- If something in the format blocks you, write to motioncore (via the integrator) instead of working around it.

---------------------------------------------------------------------------------------------------------------------

## 12. STANCES FINAL (round 2) — what your clips start and end on

The displayed idle of each fighter = its style's stance clip, sampled at `time × rate`, then `Motion.States.styleAdjust`:
rotate the whole pose by `yaw` about the vertical axis, blend the guard arms (weight `w`) to the style's lead/rear hand
positions in the chest frame, and scale the foot placement by `width` / `length` (+ `WIDTH_SPREAD` 0.25 leg lengths
per unit of width above 1), lowering the pelvis by `drop` leg lengths (feet stay planted). All six are **orthodox**
(left foot and left hand forward). These numbers are final; motioncore will not change them without telling you.

| Fighter | style | stance clip (source) | yaw | width | length | drop | rate | guard |
|---|---|---|---|---|---|---|---|---|
| Kael | boxer | `Stance` (accad-male2-e8-bounce [40:100], bounce) | 30° | 0.85 | 0.9 | 0 | 1.15 | high tight, chin tucked |
| Sierra | kickboxer | `Stance_Kickboxer` (accad-male2-e8-bounce [110:179]) | 20° | 1.05 | 1.1 | 0 | 0.8 | tall, long lead hand |
| Goran | grappler | `Stance_Grappler` (accad-male2-d1-standtoready [48:86], mirrored) | 25° | 1.5 | 1.0 | 0.06 | 0.6 | open hands forward at chest height |
| Lumi | flow | `Stance` (shared) | 30° | 1.2 | 0.9 | 0.04 | 1.05 | loose, relaxed arms, side sway |
| Rhys | karate | `Stance_Karate` (accad-male2-d1-standtoready [44:86]) | 15° | 0.95 | 1.25 | 0.03 | 0.45 | lead hand extended, rear fist at the chin |
| Nia | kungfu | `Stance_KungFu` (accad-male2-d1-standtoready [44:86]) | 25° | 1.3 | 1.05 | 0.07 | 0.55 | lead open palm forward, slow circling |

- **Goran changed in round 2** (he read as squatting): the old square CMU clip (cmu-77_03, yaw 35 → displayed
  southpaw) is gone. Now: ACCAD stand-to-ready mirrored to orthodox, wide base, torso up, knees moderately flexed.
  Use the exported `Stance_Grappler` with yaw 25 — or simply `"from": "Displayed:Goran"`.
- **How to match it**: `keyed.py` `"from": "Displayed:<Fighter>"` (first and last key). For an offline picture of all
  six (side + three-quarter rows): `python tools\mocap\lineup.py --out <dir>` (stance, walk, backwalk, crouch;
  reads the numbers from the installed `Motion.States.luau`). `clipsheet.py` of your clip shows its first/last frame
  for comparison.
- Walks keep part of the style (drop × 0.4, width halfway to 1); crouches keep only the width. Reactions, falls,
  getups and attack clips are not style-adjusted.

---------------------------------------------------------------------------------------------------------------------

## 13. Round 4 (overhaul): motion QA on the real rigs, smooth transitions

The user asked for fights that look smooth and physically believable. Round 4 measured every state, move, throw and
transition on the real fighter rigs, fixed the root causes in the runtime first, then the clips that still jumped.

### 13.1 QA harness and report

- `ServerStorage.UnitTest.MotionQA` plays views through the same path as `CharacterPresenter`
  (`MotionPlayer.presentFrame`: sample -> root placement -> apply -> throw grips -> contact pass) at 60 fps on clones of
  `ReplicatedStorage.FightingLab.Characters` and measures per frame: rotation/limb-tip pops (over an absolute limit AND
  4x the local median), transition jumps (> 15 deg per joint at a key change, and > 1.5x the joint's own motion),
  elbow/knee bend-plane flips (> 45 deg/frame), joint limits (elbow/knee hyperextension, shoulder/hip twist, wrist,
  ankle, neck yaw > 80, waist twist > 70), self-intersection (glove/hand in the own head or torso, arm centreline in the
  torso, legs through each other), opponent interpenetration (striking hand/foot depth at contact, bodies overlapping
  outside throws) and jitter (a part reversing 3 times within 6 frames at >= 0.02 studs / 2 deg per frame) in loops.
  Rig geometry comes from the rig (part sizes, profiled hulls in `Motion.BodyShape`, rigid glove parts, layered
  gloves, fists), so it works on any rig — re-run it after any proportion change.
- Cases (~600 per run, ~65k frames): every state (idle, walk, backwalk, crouch, dash, backdash, both sidesteps,
  standing/crouching block and blockstun, hit reactions high/mid/low/counter/heavy, stagger, launch/juggle/landing,
  knockdowns face up/down with every getup and roll, KO, victory, defeat), all 100 moves at max and close range
  (Separation), hit and block outcomes of every move on the partner, string chains, move -> counter hit,
  blockstun -> attack, dash -> attack, sidestep -> attack, and both roles of every throw (normal and broken).
- Full ranked report: in Studio Play (server), load the harness and run `tools/mocap/motionqa_report.luau`
  (`_G.MotionQATag`, `_G.MotionQAFighters`, `_G.MotionQAParts = {"states","moves","transitions","throws","hits"}`;
  it POSTs one JSON per fighter to a local sink), then
  `python tools/mocap/motionqa_report.py --reports <dir> --tag <tag> --baseline <tag> --out <md> --json <json>`
  (ranked defects: fighter · case · frame · metric · value, counts per category and fighter, glove-vs-head table).
- `ServerStorage.UnitTest.Cases.MotionQA_Test` (7 tests, ~16 s) asserts the targets on a sample: loops of all six
  (no pop, flip, limit or jitter; glove/hand vs head <= 0.03, other self-intersection <= 0.05), standing transitions
  of all six (no joint > 15 deg in a frame at a switch, no pop or flip outside an attack's own clip), strikes resting
  on the opponent (<= 0.15 deep at contact), face-down knockdowns/getups/KO without a 90-degree whip, and throw
  tracks without teleports. Tolerated defects are listed in its `EXCEPTIONS` table with the reason; a new defect or a
  known one getting worse fails.

### 13.2 Runtime changes (MotionPlayer, ClipPlayer, BodyShape, CameraDirector)

| area | change | knobs |
|---|---|---|
| hitstop | the animation clock stops on the rendered hit window (server duels render a buffer behind the newest snapshot); the attacker shows its contact frame | `hitstopActive(frame)` |
| impact entries | a reaction / knockdown / launch / KO / throw starting on a hit crossfades on real time (plays during the freeze), linear, sized by how far the pose travels | `ImpactFadeMin` 4/60, `ImpactFadeMax` 12/60, `ImpactDegPerFrame` 8 |
| crossfades | other fades stretch with pose travel (never shorter than the state asks); getups capped (sim roll timing); attack fade-ins end before the first active frame, linear when capped, at most 8 frames | `CrossfadeDegPerFrame` 9, `CrossfadeMax` 0.3, `GetupCrossfadeMax` 0.1, `MoveFadeMax` 8/60 |
| blend paths | arm targets blend around the shoulder (direction slerp + reach lerp), rotations slerp, step-in caps hold through fade-ins | — |
| hit push | the sim's hit push glides instead of a one-frame shove; displacement the renderer delivers over the next frames (practice interpolates between sim frames, duels between snapshots) is absorbed into the same glide for a short window after a hit or a throw exit | `PushAbsorbWindow` 2.5/60 |
| round reset | the cut is also detected from the newest entry's position jump (> `TeleportDistance` and faster than 1.5 studs/frame; the renderers interpolate across the reset), and the new round's intro pose is shown at the new mark until the interpolation arrives there (no in-between frame) | `ResetSnapWindow` 0.5 |
| blockstun | ducking or standing up during a blockstun crossfades between the standing and crouching clip (own key, same stun clock) instead of swapping in one frame | `MotionRequest.timeKey` |
| IK poles | the bend plane keeps the previous frame's direction as the clip's pole hint weakens, and turns at most 30 deg/frame (no elbow/knee flips) | `PoleContinuity`, `PoleMaxStep` |
| feet | heel drop rate-limited, soft floor and soft reach limits (C1), rise-on-ball eased in with the contact and never more than the rise that lifts the ankle, median-filtered clip contacts, lying-leg ramps; a lying body's relaxed feet (toes laid out, sole up) come and go over a real-time ramp (a roll getup snapped the ankle 66 deg tucking the toes again) | `FlattenRate` 0.15, `SoftFloor` / `SoftReach` 0.06, `LyingLegsRamp` 0.1, `RelaxFeetRamp` 0.25 |
| strike contact | a hand/foot (and its forearm/shin) sinking into the opponent's head/chest/pelvis is drawn back along its reach to the surface (elbow/knee bends, flex-limited), released gradually; throws and grab moves exempt | `StrikeContact`, `ContactAllowance` 0.05, `ContactMaxRetract` 0.85, `ContactMaxFlex` 135, `ContactRelease` 0.1 |
| self clearance | in guard, movement, block and hit reactions a glove/hand inside the own head or torso, or an arm through the torso, is pushed out along the surface normal (rate-limited, in heading space); also after a contact retraction, on its own channel for only the arms the contact drew back (rate-limited from zero); the push is measured from a base that eases between the IK goal and the solved tip, so a pass switching on or off does not re-land the arm elsewhere | `SelfClearance`, `SelfHeadAllowance` 0.015, `SelfBodyAllowance` 0.03, `SelfPushRate` 0.05, `SelfBaseFrames` 6 |
| IK pole clock | the pole-continuity reference advances with the shown frames (real time), not the animation clock: through a hitstop freeze the impact fade keeps moving the pose (Kael's KO arm spun 153 deg in one frame when the freeze ended) | `ContinuityRealTime` |
| grips | throw grips fade in/out over a minimum time | `GripFadeInMin` 0.05, `GripReleaseMin` 0.15 |
| guard trims | per-fighter hand offsets in the guard states: Kael's rear (camera-side) glove sits 0.1 lower so his profile eye reads from the player's own camera | `GuardTrim` |
| body shapes | `Motion.BodyShape`: profiled hulls of the real parts, rigid glove capsules (round-4 gloves), `handCapsule`, `coreDistance` — shared by the runtime and the harness | — |
| camera | eased hitstop lean, impact push and tilt; 5-7 Hz eased shake; acceleration-limited follow (no jerk when a shot jumps); zeroed on cuts | `CameraDirector.MaxCameraAccel` 600 |

### 13.3 Clips

- `tools/mocap/retime.py` re-times fast segments of built clips in place (anchors at start, contact/impact, recover and
  end stay exact; slow holds play a little faster, snaps a little slower; poses unchanged). All 13 FLThrow1 throws were
  re-timed: fastest body point 0.87-2.06 -> 0.46-0.54 studs/frame; grips remapped; break tracks untouched.
- `FallFront` and `KOFront` (hand-keyed, `specs/core-keyed.json`) pitched forward with the head toward the opponent and
  then, in their last 0.1-0.15 s, landed in `FallFrontAir`'s prone pose — head AWAY from the opponent: a 180-degree turn
  between two keys (feet flipping 150-163 deg in a frame at the floor contact, Kael's KO foot 177 deg), and the face-down
  getup (`GetupFront`, which starts head toward) turned the body back with a 178-degree leg whip. Both now land in
  `GetupFront`'s first frame (the pelvis no longer drifts forward and slides back), and `Motion.States` starts every
  getup from a grounded face-down knockdown with `GetupFront` (rolls push up while the sim slides the body). Prone
  orientation per clip: face up = head away everywhere; face down = head toward after a grounded fall or KO, head away
  after a juggle (`FallFrontAir`; its getups are unchanged, see 13.4). The `:Air` suffix on getup keys keeps the choice.

### 13.4 Results (all six fighters, merged round-4 rigs; distinct defects main -> branch, report r27 vs base7)

598 cases, 65,237 frames per run. A defect is a distinct (fighter, case, metric, part), counted at its worst frame.

| category | main -> branch | of which >= 2x the limit | worst main -> branch |
|---|---|---|---|
| rotation pops | 5226 -> 1842 | 3723 -> 1247 | 179.3 -> 179.6 deg |
| limb-tip speed pops | 1988 -> 720 | 1665 -> 445 | 3.49 -> 2.68 studs/frame |
| transition jumps (> 15 deg/frame at a switch) | 777 -> 254 | 560 -> 127 | 179.1 -> 91.5 deg |
| elbow/knee bend-plane flips | 471 -> 162 | 173 -> 3 | 178.6 -> 154.4 deg |
| joint limits | 1576 -> 1366 | 391 -> 265 | |
| glove/hand in own head | 27 -> 26 | 21 -> 14 | 0.36 -> 0.29 studs |
| glove/hand in own torso | 194 -> 93 | 155 -> 70 | |
| arm through own torso | 1360 -> 902 | 1057 -> 379 | 0.79 -> 0.46 studs |
| legs through each other | 266 -> 158 | 241 -> 136 | |
| strike depth at contact | 76 -> 36 | 56 -> 17 | 0.71 -> 0.57 studs |
| strike through the opponent | 83 -> 32 | 52 -> 19 | |
| bodies overlapping | 4 -> 6 | 2 -> 2 | |
| jitter (loops) | 3 -> 2 | 0 -> 0 | |

Knockdowns (distinct defects of all six, worst rotation pop): face-down KO 183 (162 deg) -> 41 (46), face-down stand-up
204 (167) -> 105 (66), face-down rolls ~228 (166-179) -> ~121 (66), face-up cases 120-210 -> 60-143 (worst 87). Guard,
movement and hit reactions: every glove clears the own head for all six. Glove/hand in the head now comes from strikes
and round-end poses only (Kael BodyBlow 0.155, Sierra DuckJab 0.135, Lumi defeat 0.14); the face-down getups' 0.18-0.42
is gone. Real-play emulation (measured on bd10d27; four CPU fights, 2000 frames each, rendered between sim frames
like practice): isolated root jumps 88 -> 13 (3 are the intended round-reset cuts, the other 10 are <= 0.15 studs;
main's worst non-reset jump was 0.57), isolated limb/head jumps 566 -> 199.

Not fixed:
- A juggle ending face down (FallFrontAir, head away) still turns the body 180 degrees in the stand-up getup's
  crossfade (launch>fallFaceDown>getup, worst 180 deg): no getup clip starts head away. A side roll from its prone
  half turn was measured and rejected (arms swing through the shoulder, 116-131 deg; more defects). Needs a new clip.
- Prone legs twist 30-65 deg/frame for a few frames after landing (the knee floor lift turns the bend plane).
- Clip content: fast strike/spin arcs, getups and rolls (gloves through the torso while rolling, up to 0.7), ankle/knee
  direction mismatches in a few clips, point-blank strikes limited by the flex cap, and the counter-hit entries listed
  OPEN in MotionQA_Test.
### 13.5 For clip authors

- Run `MotionQA_Test` and the report after changing a clip; fix pops by re-keying or `retime.py`, keep contact
  frames exact, start and end on the displayed stance.
- A wind-up that tucks the hand next to the ear passes the arm close to the shoulder: keep the elbow's pole hint
  consistent through the chamber (a pole pointing along the forearm flips the elbow).
- Gloves: the runtime keeps them out of the head/torso only in guard, movement and reactions; in attacks, getups and
  throws the clip must route the hands around the body.

## 14. Round 5 (overhaul): getups without a spin, strikes on the surface, no self-clipping on the floor, Kael's face

The user asked for four fixes after round 4:
- a face-down knockdown must get up without turning 180 degrees;
- point-blank strikes must not sink into the opponent;
- gloves and forearms must stay out of the own body in getups, rolls, KO and thrown-defender tracks;
- Kael's face must read from the fight camera.

Everything below is measured on the real rigs of all six fighters (round-4 proportions, rigid gloves for Kael and
Sierra).

### 14.1 Harness and tests

`ServerStorage.UnitTest.MotionQA` additions:
- `QA.knockdownCases(id)`: knockdowns from a grounded hit, a launcher fall and a juggle, face up and face down, into
  Stand, BackRoll, SideRoll left/right and late rolls (chosen at Landing 31, after the stand-up lead started), plus the
  KO (grounded face up/down, launch face up, juggle face down). Each frame from the one before the body reaches the
  floor to the end of the case (the stance after it) is checked for:
  - `getup.spin`: pelvis yaw/roll per frame, limit 15 deg;
  - `getup.whip`: every part's turn relative to the pelvis per frame, limit 30 deg.
- `QA.moveCase(id, key, "mid")`: halfway between Separation and the move's range.
- `QA.slotTwo(case)`: the subject in player slot 2.
- An `onFrame` hook in `QA.play`.
- Face metrics:
  - `QA.fightCamera`: CameraDirector's shot for a pair;
  - `QA.faceVisibility`: the share of the camera-side eye, nose and mouth landmarks (`Motion.BodyShape.faceLandmarks`,
    13 points snapped onto the head) whose sight line to the camera no glove or hand capsule crosses;
  - `QA.guardShape`: glove top vs chin, glove centre under the eyes, elbow outside the shoulder line.

`ServerStorage.UnitTest.Cases.MotionQARound5_Test` has 84 tests, each well under the runner's 5 s:
- 1: knockdown continuity per fighter, source and face.
- 3: gloves/hands vs own head (≤ 0.03) and torso (≤ 0.05), and forearm centrelines (≤ 0.05), in two settings:
  - Landing, Getup, KO and Knockdown, per fighter;
  - every throw's defender track per defender, thrown (per defender and attacker half) and breaking the throw. Three
    cases are capped in `DEFENDER_EXCEPTIONS` (14.6).
- 2: every strike and kick at point-blank (Separation 2.6), mid and max range: `opp.strike` and `opp.through`
  ≤ 0.15 after the startup (active and recovery).
- 4: face visibility ≥ 70% from the fight camera at spacings 3.5 and 7, both player slots, in idle, walk, backwalk and
  blockstun; and Kael's idle guard: glove tops at most 0.1 under the chin, centres under the eyes, elbows ≤ 0.3
  outside the shoulders.

On main's runtime 70 of the 78 failed, measured before the six thrown-defender tests were split into attacker halves
(all six failed on main; the halves were not re-run on main). The 8 that pass on main are guards against regressions:
- max-range strikes for Kael, Sierra, Goran, Lumi and Rhys (Nia's Elbow sinks 0.24 at max range on main);
- faces for Goran, Lumi and Nia.

Test time:
- The round-4 `MotionQA_Test` group tests and the two `MotionGround_Test` sweeps over every move clip now run per
  fighter or per case group (the throw tracks in two halves: the throws of three fighters, or the rigs of three
  fighters), with the same cases and checks.
- So each test stays well inside the runner's limit with the extra floor and thrown-defender clearance: in a timed
  copy of the runner the slowest motion test takes 2.6 s (4.15 s before the throw halves).
- Official runner on the branch: 501/501 in one Play session, 230 s, no timeouts.

`tools/mocap/motionqa_report.py` reports `getup.spin` / `getup.whip` and a worst-value-per-category table.

### 14.2 Runtime changes (MotionPlayer, States, BodyShape)

| area | change | knobs |
|---|---|---|
| knockdown smoother | in Landing, Getup, KO and Knockdown (and 0.6 s of stance after) each frame's pose is limited against the shown one in body frames: pelvis yaw/roll and pitch, spine and neck, each limb's direction and reach in its chest/pelvis frame, poles, and the feet relative to their own leg | `LyingSmooth`, `LyingYawRoll` 12, `LyingPitch` 28, `LyingSpine` 14, `LyingLimb` 18, `LyingReach` 0.08, `LyingPole` 22, `LyingFoot` 22, `LyingTail` 0.6 |
| knockdown whip limit | the last step of `apply` on those poses: every part's rotation relative to the pelvis turns at most 26 deg per frame from the shown frame (pelvis outward), so neither fast clip content nor the floor rules whip a limb. A clamped leg that would end up lower than the solve rested it (or below the floor) is lifted rigidly about the hip by the least angle that clears it, at most 3.5 deg (a foot held at last frame's turn while the solver laid it down sank shoes 0.03-0.08 into the floor) | `LyingJointDeg` 26, `LyingLiftMaxDeg` 3.5 |
| getup ankle range | on getup clips' poses (`Pose.ankleRange`) a foot that is not planted keeps inside the ankle's range against its own shin (dorsiflexion 40, roll 35, yaw 40; pointed toes left alone), never taking the foot or its shoe lower than the solve had it; fades out as the foot plants. The new side roll's kneeling foot read 100-146 deg of dorsiflexion and 60-95 deg of roll against its shin | `GetupAnkleRange`, `AnkleRange` |
| floor / thrown self clearance | the self clearance also runs on the floor and for a thrown defender or one breaking the throw. The push rate ramps in over 6 lying frames; a defender's push starts at full rate. A thrown defender's gripping hands get their own clearance pass after the grips | `LyingSelfClear`, `LyingPushRate` 0.3, `LyingPushRamp` 6, `DefenderClearBreak` |
| elbow swivel | on the floor and for a thrown defender, an elbow or upper arm inside (or within 0.25 of) the body turns the pole out along the body's normal (the hand stays put). It is warm-started from the last frame, rate-limited and faster while deep; a defender's swivel eases in over the throw's first 3 frames. It never twists the upper arm past 112 deg about its own axis when the clip's pole stays within that and the guarded swivel leaves the arm no deeper (turning the elbow out around an arm reaching overhead twisted shoulders 140-170 deg) | `ElbowSwivel`, `ElbowSwivelPasses` 4, `ElbowSwivelGain` 0.6, `ElbowSwivelMargin` 0.25, `ElbowSwivelRate` 10, `ElbowSwivelDeep` 0.08, `DefenderSwivelRamp` 3, `SwivelTwistMax` 112 |
| crossfade hands | hands blend in each pose's chest frame (reach, pole, rotation) and are carried by the blended chest | `ChestBlend` |
| lunge spacing | an attack whose clip lunges toward a target at its designed range scales the forward pelvis travel down to what the real distance leaves (rate-limited, carried through a string) | `LungeSpacing`, `LungeRate` 0.15 |
| contact push-back | what still sinks after the contact pass bent the limb (an elbow or knee strike, a folded hammer arm) holds the attacker's body back by the residual (re-applied pose, planted feet stay), released slowly. It grows at most 0.15/frame in the startup, freely from the first active frame | `ContactPushBack`, `ContactPushMax` 0.8, `ContactPushRelease` 0.04, `ContactPushRate` 0.15 |
| profile clearance | in guard, movement and reactions the right glove moves off the sight lines from the camera to the eye, nose and mouth: down along the jaw and a little forward, by the least distance (refined), smoothed over frames. That is the camera side, because the local fighter stands on the left. Out of the guard the shift lets go at 0.04/frame (dropped at the self push's rate, it turned Kael's shoulder 16 deg on a hook's first frame) | `ProfileClearance`, `ProfileHand`, `ProfileMargin` 0.03, `ProfileSmooth` 0.5, `ProfileRelease` 0.04, `ProfileViews`, `ProfileDir` |
| knockdown states | `Motion.States` knows how the shown body lies (`RequestContext.shownLie`). A juggle that ends face down (prone, head away) is rolled onto its back with `ProneTurnOver` during Landing (keys `Down:FaceDown:Turn:Air`, `Down:FaceUp:Turned:Air`), and every getup after it starts face up (`Getup:FaceUp:<kind>:Air`) | `States.TURN_START` 6, `States.TURN_FRAMES` 18 |
| face landmarks | `BodyShape.FACE` and `BodyShape.faceLandmarks(head, side)` (eye, nose, mouth points on the real head) for the harness and the profile clearance | — |
| shoes | rig chains carry the worn shoe's box (`shoeBox`, `shoeSize`), so the whip limit and the ankle range keep the shoe, not just the foot box, out of the floor | — |

### 14.3 Clips (`tools/mocap/lying.py`, body-frame keys)

`lying.py` builds lying clips from keys in body frames (pelvis rotation path, hands in the chest frame, feet in the
pelvis frame), so limbs follow the body through a roll instead of counter-rotating against it.
- `ProneTurnOver` (new, 18 frames): FallFrontAir's prone pose (head away) rolled onto the back over the right side at
  ≤ 12 deg/frame.
  - The lower arm reaches overhead along the floor and comes down beside the body.
  - The upper arm guards the face; the legs stay together.
  - It ends in FallBack's lying pose.
- `SideRoll` (rebuilt, 36 frames): from FallBack's pose a quarter turn onto the travel-side hip (the old clip spun a
  full turn in 14 frames, 27 deg/frame).
  - The lower hand braces in front of the chest and the upper hand plants.
  - A push up into a crouch turning toward the opponent, then the stance.
  - The feet keep their lying set on the leg until they plant.
  - The clip rolls left; the runtime mirrors it.

### 14.4 Results (all six, real rigs; main -> branch)

| issue | main | branch |
|---|---|---|
| 1. knockdown -> getup -> stance, worst whole-body turn per frame | 53.2 deg (all six) | 12.0-12.2 deg |
| 1. worst limb turn relative to the pelvis per frame | 173-179.5 deg | 28.0-29.5 deg |
| 1. QA report: `getup.spin` / `getup.whip` defects | 42 / 839 | 0 / 0 |
| 2. strike depth after startup, point-blank | 0.38-0.77 (Goran CrouchJab 0.77, Rhys LowPunch 0.61) | 0.05-0.14 |
| 2. mid range | 0.31-0.71 (Goran JabHammer 0.71) | 0.05-0.14 |
| 2. max range | Nia Elbow 0.24, others ≤ 0.15 | 0.04-0.07 |
| 3. glove/hand/forearm in own body, Landing/Getup/rolls/KO | 0.37-0.77 | clean (≤ the limits) for all six |
| 3. thrown defender (every throw) | 0.07-0.35 (Goran's RamSlam 0.35) | clean except Rhys 0.20 (RamSlam slam frame), Nia 0.033 (Rhys Throw) |
| 3. defender breaking a throw | up to 0.29 (Kael breaking RamSlam) | clean except Nia 0.030 (Rhys Throw) |
| 4. Kael face visible (worst / average) | 0.00 / 0.38 | 0.85 / 1.00 |
| 4. Sierra / Rhys / others (worst) | 0.38 / 0.54 / 1.00 | 1.00 / 1.00 / 1.00 |
| 4. Kael idle guard: lowest glove top vs chin, widest elbow outside the shoulders | +0.18, -0.01 | -0.02 (at the chin), -0.09 |

Round-4 QA report re-run (598 cases, 65,237 frames; `OV6\handoff\motion-shots\round5\report\`). Distinct defects
main -> branch per category:

| category | main -> branch |
|---|---|
| rotation pops | 1842 -> 1617 |
| tip-speed pops | 720 -> 658 |
| transition jumps | 254 -> 228 |
| flips | 162 -> 68 |
| joint limits | 1366 -> 1327 |
| glove in head | 26 -> 18 |
| glove in torso | 93 -> 54 |
| arm in torso | 902 -> 612 |
| legs | 158 -> 107 |
| strike depth | 36 -> 1 |
| strike through | 32 -> 2 |
| bodies overlapping | 6 -> 0 |
| jitter | 2 -> 2 |
| getup spin | 42 -> 0 |
| getup whip | 839 -> 0 |

No category gets worse for any fighter (Kael's transition jumps 28 -> 28, the closest). Within joint limits the lying
cases do get worse (14.6).

### 14.5 For clip authors

- Lying clips:
  - key them in body frames (`lying.py`);
  - never let a lying turn exceed ~12 deg/frame;
  - keep the arm under the body out of the way (reach overhead or brace in front of the chest);
  - start a getup from the lying pose its landing shows (`Motion.States` picks the face-up getups after the
    turn-over).
- Strikes: the runtime now scales a clip's forward lunge to the real distance and holds the body back for what still
  sinks. A strike that should travel forward at point-blank must still not rely on reaching through the target.
- Getup feet: the runtime keeps unplanted feet inside the ankle's range against the shin. A clip that wants a
  kneeling toe-tuck should key it on the shin (`lying.py` `leg_frame`), not in the pelvis frame.

### 14.6 Known issues (round 5)

Defender cases over the limit, capped in `MotionQARound5_Test` `DEFENDER_EXCEPTIONS`:
- Rhys's left forearm on Goran's RamSlam slam frame (0.20, 1 frame).
- Nia's right fingertips grazing her cheek on Rhys's Throw entry, thrown (0.033) and breaking it (0.030).

Other known issues:
- Point-blank startup frames are outside the strike target. Goran's Hammer at Separation sinks 0.36 on a startup frame
  (JabHammer 0.24), and Goran's Uppercut on hit 0.23 at its launch (the defender's launch pose rises into the fist
  during hitstop); these are the QA report's remaining `opp.*` defects.
- Joint limits: 1327 remain (main 1366), counted by case family main -> branch:
  - lying cases 233 -> 272;
  - hit cases 509 -> 456;
  - states 491 -> 488;
  - throws 133 -> 111.

  The lying increase is the rebuilt SideRoll: 9-16 distinct limit defects per fighter over both roll directions
  (main's old roll 2-4). They are:
  - ankle dorsiflexion and roll where the runtime flattens a planted foot under the kneeling shin;
  - hip twist at the kneel;
  - shoulder twist at the hand plant.

  The getup ankle range only acts on unplanted feet. A kneel keyed on the toes, with the contact released until the
  shin is upright, would remove the rest (a clip change; a first attempt moved the defects into ankle yaw and was
  reverted).
- Cost: the floor and thrown-defender clearance makes a lying or thrown frame dearer (the move-clip ground sweeps run
  ~1.5x longer); standing frames are unchanged.

## 15. Round 6: Ultimates, signature stances, tumble, the new movesets

The user asked for different movesets and combos per fighter and a low-health Ultimate. Combat (r6-combat) redesigned
the movesets (`movesets.md`) and added Surge and the Ultimates to the sim (Contract A); motion makes them look right.

### 15.1 Ultimates

Six two-person cinematics, one per fighter, on the roster timelines (impacts exactly on the roster frames), plus the
move's own start clip. Format, runtime (`Client.Motion.Cinematic`), camera, effects and authoring:
**`ultimates.md`**. Clips: `Motion.Clips.Moves.Ultimates.<Fighter>_Ultimate` (FLThrow1) and `<Fighter>_UltimateStart`
(FLClip1); source specs `tools/mocap/cine/ult_<fighter>.py`, builder `cinebuild.py`.

### 15.2 Signature stances (state `"Stance"`)

The sim enters a stance directly on 3+4 (`view.state = "Stance"`, `view.stance` = the key, `view.stanceFrame` from 1;
no Startup state). `Motion.States.stanceRequest`:

| phase | clip | time |
|---|---|---|
| entry, stanceFrame ≤ `entryFrames` | `Kick_<Fighter>_<Stance>` (the clip bound to the 3+4 entry move, Moves.Kicks) | progress over entryFrames |
| held | `<Fighter>_<Stance>` (Core, loop) | elapsed since the entry |
| a travelling stance (Lumi's Aerial) | `<Fighter>_<Stance>` (Core, one-shot) whole | stanceFrame / maxFrames |
| leaving into the guard | `<Fighter>_<Stance>Exit` (Core) when installed, else the idle crossfade | 10 frames |

Keys `SigEnter:<key>`, `Sig:<key>`, `SigExit:<key>`. The stance's own clips show its crush (Kael's Pocket ducks, the
Aerial is in the air), so `view.crush` does not swap them for the crouch. Stance follow-ups (PocketShovel,
SouthpawHeadKick, AerialSplit, StillStrike, CoilWhirl, …) are ordinary move clips whose first frame is the stance pose.
Southpaw follow-ups are the orthodox kicks mirrored (the roster `limb` names the physical leg: RearLeg = right) and end
on the orthodox stance with a hop-switch (the sim leaves the stance with the move).

| Fighter | stance | entry | loop | exit |
|---|---|---|---|---|
| Kael | Pocket (PKT) | knees bend, head drops under the line (6 f) | low bob-and-roll, U shape, 40 f | rises to the guard |
| Sierra | Southpaw (SPW) | hop-switch (5 f) | the mirrored bouncing stance | hop-switch back |
| Lumi | Aerial (AER) | one 26-frame clip: dip, no-hands cartwheel (airborne 3-18), landing | | |
| Rhys | StillWater (STW) | lead foot back, open hand forward (8 f) | still, a slow breath, 60 f | foot back to the front stance |
| Nia | Coil (COIL) | shoulders turn away, palms to the hip (6 f) | palms circling, 48 f | unwinds |

Goran's 3+4 is the Bear Trap (a catch move, `Kick_Goran_BearTrap`: hips down, arms wide 4-24); a catch plays his
ThrowB.

### 15.3 Tumble

A tumble hit (`Hit.tumble`, view flag `tumble` while the body is still in the air) plays `Core.AirTumble`: the juggled
body rolls once about its long axis and holds the falling juggle pose until it lands; a new air hit rolls it again.

### 15.4 New and changed move clips (`tools/mocap/cine/movebuild.py`, specs `movespecs.py`)

39 new move clips (23 kick-type in Moves.Kicks, 11 punch-type in Moves.Strikes, the 5 stance entries) plus 8 stance
loop/exit/whole clips and AirTumble in Core, hand-keyed on poses sampled from the game's own clips (credits follow
them; kicks credit `original:motionkicks`, strikes `original:motionstrikes`):
- `standard(ctx, src, start, lead, a, ...)` retimes a source clip onto the move: start pose on frame 0, the source's
  [a .. contact] onto [lead .. startup + 1] (contact snap), [contact .. recover] onto the active frames, the rest onto
  the recovery, ending on the displayed stance on the move's last frame (60 fps, `contact = (startup + 1) / total`,
  `recover = (startup + active + 1) / total`: the warp is the identity).
- String enders start on the previous hit's pose: punch-type on its recover mark (where the sim starts the follow-up),
  kick-type on its last active frame (`kick_chain`); a follow-up of a NEW move starts on that clip's solved pose
  (`built_pose`).
- Spins and flips keep the source's own path (dense keys every 2 frames); `C.rotated`/`C.rotated_axis` turn whole
  poses (limbs follow).
- Build: `python tools\mocap\cine\movebuild.py --roster <roster.json> [--only Kael] [--no-write] [--sheets <dir>]`;
  the sheets show every clip at start, wind-up, contact (red), recover and end.

- Dense samples interpolate linearly (`seg`): a smoothstep per 2-3 frame segment stopped the motion at every key, a
  stop-and-go MotionQA read as speed pops. The source recovery plays at its own speed (compressing it sped the
  retraction up into pops).
- A move combat re-times keeps its round-5 clip as a reference copy (`tools/mocap/cine/refclips`, never installed):
  SnapKick is that clip with a small hop; RisingTornado (impact 22 -> 20) plays its busy frames (the hand swing, the
  arm swing, the jump and the kick) at the round-5 speed while the calm frames absorb the two frames (weights from a
  rig probe of the round-5 move, `R5_RISING_BUSY`). A uniform retime sped the whole startup up 10 % into speed pops.
- SlashElbow keeps the glove a glove's depth in front of the face all the way (it used to pass over the head: the
  CharacterLook glove check). RibRoller's follow-through is hand-keyed: the hook source squeezed contact-to-recover
  into the three active frames and flipped the lead elbow in one frame; now the fist rolls up through the target, the
  arm folds back in front of the chest with the elbow turning down into the guard and the body rises out of the dip.

Coverage after round 6: 77 kick-type moves (24 kick string follow-ups) and 49 punch-type moves, one clip each
(`MotionMovesKicksCoverage_Test`, `MotionMovesStrikesCoverage_Test`; the Ultimate is covered by
`MotionUltimate_Test`, the 3+4 signatures by the Body-limb branch: the body stays with the sim root).

### 15.5 Tests and QA

- `MotionUltimate_Test`: every fighter's Ultimate clip and start clip on the roster timeline (impacts exactly on their
  frames, contact on startup + 1), the presentation time map, both roles finite on every frame, the defender lying on
  its spot at the end and the knockdown continuing without a jump, missing fields never erroring, stance entry/loop/
  exit requests, the tumble request.
- `MotionGround_Test` sweeps the Ultimates on their real timelines (attacker; Goran and Nia as defenders) instead of
  as 46-frame throws.
- MotionQA: `QA.ultimateCases(id)` (move, cinematic, Landing and getup) and `QA.stanceCases(id)` (each stance held to
  its end and into each follow-up); `tools/mocap/motionqa_report.luau` runs them as parts `ultimates` and `stances`.
- MotionQA r6 vs main (all six fighters, real rigs, the cases both runs share): no category worse for any fighter
  against main's runtime run with r6's `CombatConfig`. Against main as it is, three categories are +1 (Lumi pop.rot,
  Rhys and Nia pop.speed), all on the launch frame of the state case `launch>juggle>landing>getup>idle`, which takes
  its launch from `CombatConfig.LaunchVelocity` (combat raised it 16 -> 19); main's runtime shows the same defects
  with the new constant. Report: `OV6/handoff/motion-shots/round6/motionqa-r6-vs-main.md`.

### 15.6 Presentation fixes asked by the other agents

- Hit flash (`CharacterPresenter`): a white fill of at most 30 % for 4 frames (was 55 % for 6), so still frames do
  not look washed out; Surge and UltStart flash the body for 5 frames, the UltStart screen flash lasts 0.16 s.
- Boxing gloves (`Motion.BodyShape.isGlove`): the boolean attribute `FightingLabGlove`, else a `FightingLabRole` of
  `Glove`/`BoxingGlove`, decides; the old "*glove*" name rule only applies without either.
- The Ultimate camera frames both fighters whole (`CameraDirector._fitShot`, see `ultimates.md` section 4).

### 15.7 Integration playtest follow-up (main @ a8cd197 merged into r6-motion)

- Goran's Landslide: lifted defender keys said `ground = 0` (they inherited the lying source pose's floor support, so
  the ground solver pulled the carried body down: no knee slam or carry, his legs through it, once under the floor).
  Choreography as designed: he hauls it up from behind by the armpits (standing past its head), cradles it onto his
  raised knee, swings it lengthwise onto his right shoulder (its body beside his head, its near arm raised clear of his
  face, quarter-turn keys so it follows the arc round his head), turns, steps and drops forward onto his knee at its
  hip. FLClip1 `rootRange` (ultimates.md section 2) keeps the suplexed body's root from clipping at 2 leg lengths.
  `MotionUltimate_Test` checks every defender track for floor support on a lifted body.
- Whole poses in Play (the body under the floor in run 1): Roblox draws a frame with the Motor6D transforms written
  the frame before (it moves the parts to them after the picture) but with a root part moved this frame at once. Any
  frame whose root offset jumps (a lifted, carried or dropped body, a cinematic's first frame) therefore showed the
  last pose on the new root; a Play probe measured up to 4.7 studs between the drawn parts and the posed ones, and
  Nia's head 1.2 studs under the floor while no posed frame went below it. A Play experiment (a clone whose root goes
  up 3 studs on odd frames while its Root joint goes down 3) jumped every frame with the root set in RenderStepped and
  stood still with the root set in PreAnimation or Stepped. `CharacterPresenter.DeferRootToPicture`: in Play each
  fighter is posed on this frame's root as before (grips, contact and the ground solver read it), then the root goes
  back where the shown joints belong and moves on in PreAnimation. Studio sometimes draws twice without an animation
  step (about one frame in seven in the probe); such a frame keeps the last whole pose (the root moves only with the
  step, or after `RootFlushFrames` frames as a fallback). Probe after the fix, 8 pairings: lowest drawn point -0.02
  studs in every cinematic. `MotionUltimate_Test` checks the presenter keeps each root with its joints, also across a
  frame without an animation step. Every body shows one frame later than it is posed, as its joints always did.
- Kael's Final Bell: the defender glides onto its cinematic spot in `MotionPlayer.UltimateEntryGlide` (0.1 s) and the
  catch straight holds a chest grip (the straight no longer passes through it, its head no longer folds onto his arm);
  he steps in on his right of its folded head with his rear glove at his cheek, then rolls under to his left into the
  liver hook. Strike grips clear gloves and forearms out of the partner (`StrikeGripClearance`, ultimates.md
  section 3). The opening shots frame the catch and the clinch in profile from his right (from behind his right
  shoulder his guard glove hid its folded face and read as pushed into its head even with the bodies clear).
- Nia's Monsoon: the final two-palm push lands beside the falling body (turned 42 degrees, 0.85 m to the side), so its
  legs come down past her shins.
- Camera: whole bodies inside the safe picture area under the HUD band, in the Ultimate (`CineSafe`) and in the fight
  (`FightSafe`, a higher aim from the same lens height); `CameraFraming_Test` projects the real posed bodies of every
  pairing. `VfxUltimate_Test` runs one camera test per fighter, `MotionGround_Test` splits its throw sweeps in thirds
  (each test well under the runner's 5 s).
- Surge: a pulsing body glow (Highlight outline in the surge colour) over the floor aura, a stronger Surge burst, and
  every aura particle cleared at once when Surge ends, a fighter is put back on its mark or a round resets.