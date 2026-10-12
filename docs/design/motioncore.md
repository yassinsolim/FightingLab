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
