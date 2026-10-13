# Ultimates: the cinematic format, runtime, camera and effects (round 6, motion)

The Ultimate is FightingLab's own low-health comeback: a fighter in **Surge** (at or below the Surge threshold, once a
round; Free Training keeps the player in Surge) presses 1+2 for its Ultimate. The move itself is an ordinary armoured
strike; when it connects, the sim locks both fighters into state `"Ultimate"` and a scripted two-person cinematic plays
for the attacker's roster timeline. This document covers everything on the client side: the clip format, how the
runtime plays it, the camera, the effects and sound, and how to author or re-time a cinematic. The sim side
(timelines, damage shares, Surge rules) is in `movesets.md` (section 3) and `CONTRACTS-v6.md` (Contract A).

| Fighter | Ultimate | Frames | Impacts (sim frames) | Ends | endDistance |
|---|---|---|---|---|---|
| Kael | Final Bell | 200 | 30, 62, 94, 128, 176 | FaceDown | 4.4 |
| Sierra | Eight Limbs | 230 | 34, 70, 104, 140, 196 | FaceUp | 4.6 |
| Goran | Landslide | 240 | 40, 92, 150, 214 | FaceUp | 4.6 |
| Lumi | Skyline | 210 | 28, 56, 86, 118, 150, 192 | FaceDown | 4.4 |
| Rhys | Last Kata | 190 | 32, 64, 98, 170 | FaceUp | 4.6 |
| Nia | Monsoon | 260 | 30, 66, 104, 146, 190, 240 | FaceUp | 4.6 |

The roster (`Roster.get(id).moves.Ultimate.cinematic`) is the source of truth; the table is a snapshot.

## 1. What the sim sends (Contract A)

* Events: `Surge` (a fighter entered Surge), `UltStart` (the Ultimate move started: activation), `UltHit`
  (`combo` = impact index 1..n, `knockdown = true` on the last, `damage`), and the round's `KO` when the cinematic ends
  on a defeated defender.
* Views: fighter flags `surge`, `ultUsed`; during the cinematic both views have `state = "Ultimate"` and
  `throw = { archetype = "ultimate", move = "Ultimate", role = "Attacker" | "Defender", frame = 1..duration, duration,
  impactFrame }`. Both roots stay locked, the defender `endDistance` studs in front of the attacker (moved inward
  together when that spot is outside the arena). After the last frame the defender is in `Landing` with
  `knockdown = endKind` (or `KO`) and the attacker is free.
* Hits on an airborne body can carry `tumble = true` (the view flag `tumble` stays on until the body lands).

## 2. Clip format: FLThrow1 with cinematic fields

One module per fighter in `Motion.Clips.Moves.Ultimates`, `<Fighter>_Ultimate`, format `FLThrow1` bound to
`fighter = "<Fighter>"`, `move = "Ultimate"` (`ClipLibrary.forThrow(id, "Ultimate")`; fighter `"*"` = any fighter),
plus the move's own clip `<Fighter>_UltimateStart` (FLClip1 bound to the same move: the activation pose, the armoured
catch strike on `startup + 1`, the whiff/block recovery).

FLThrow1 fields used by the cinematic (all optional except the tracks):

| field | meaning |
|---|---|
| `attacker`, `defender` | FLClip1 tracks (60 fps, authored on the sim frames: clip second = sim frame / 60) |
| `distance` | root spacing the defender track was authored at, in attacker leg lengths |
| `impacts` | normalised clip times of the impacts (one per roster impact) |
| `hits` | per impact `{ limb, height }`: the striking limb (effects spawn on it) |
| `release` | normalised time from which the defender glides onto its sim spot (default: the last impact) |
| `endKind` | `"FaceUp"` / `"FaceDown"` the defender's last frame lies in (must match the roster) |
| `grips` | runtime contact windows (FLThrow1 grips): striking hands/feet land on the partner's real body point |
| `camera` | camera keys `{ t, pos, look, fov, cut, ease, roll }` (see section 4) |

`ClipLibrary.decode` keeps these fields (`decodeImpacts`, `decodeHits`, `decodeCamera`); unknown or malformed values
are dropped, never an error. A track whose root travels further than 2 leg lengths (Goran's suplex lands its defender
behind him) carries `rootRange = R` (FLClip1, optional): its three root channels are quantised over [-R, R] instead of
[-2, 2] (`tools/mocap/clipio.py` picks it; without it the root clipped at 2 leg lengths and the thrown body was shown
in the wrong place).

## 3. Runtime (`Client.Motion.Cinematic`, `MotionPlayer`)

* `Cinematic.timeline(attackerId, throw)`: the roster timeline, else the contract's default template; a sim
  `throw.duration` that differs rescales the impact frames. Cached (`Cinematic.clearCache()`).
* **Time map.** `Cinematic.clipU(tc, tl, f)` is piecewise linear through (0, 0), (impact frame k, clip impact k), …,
  (duration, 1): every impact of the clip is shown exactly on its roster frame whatever the clip's own pacing. With a
  different impact count the first ones pair in order and the last (the finisher) always pairs with the last.
* **Presentation slow motion.** `Cinematic.displayFrame(tl, f)` runs the display slightly ahead before the final impact,
  at `SlowFactor` (0.3) through it (`SlowBefore` 14 / `SlowAfter` 8 sim frames) and catches up after it; every impact
  frame, the first and the last frame map onto themselves, so the UltHit events, damage numbers and sounds stay in
  sync and the sim timing never changes (`Cinematic.slowMotion` tells camera/effects when they are in the window).
* **Both roles, one clip.** The defender plays the ATTACKER's clip (its `defender` track) at the same clip time. The
  defender track was authored `distance` leg lengths in front: the runtime slides it along its facing by
  `actual − distance × attackerLeg` (ramped in over `AlignFrames` = 4 frames, released from `release` to the end), so
  the bodies meet whatever the two fighters' sizes and the defender's last frame lies exactly on its sim spot.
* **Entering.** The sim moves the defender onto its lock spot on the hit frame (a juggled body is pulled to the floor
  spot): `MotionPlayer` absorbs that jump with a short glide (`UltimateEntryGlide` 0.1 s: the catch knocks it back
  onto its spot). The catch strike is authored against that spot; with a normal push glide (up to 0.2 s) the body
  stayed at its point-blank pre-hit spot long enough for the attacker's straight to pass through its chest and its
  folding head to land on his arm (round 6 follow-up, Kael). Catch strikes also hold a grip on the chest for their
  first frames.
* **Strike contact.** Grip windows of the attacker's strikes (`C.Hits().add`) put the bare fist's contact point on the
  partner's real body. A boxing glove or the forearm behind it still inside the partner's head or body
  (`Motion.BodyShape`) then draws the point back toward the striker by that depth and the arm solves again, while that
  helps (`MotionPlayer.applyGrips`, `StrikeGripClearance` 0.02 studs).
* **Lifted bodies.** A defender key based on a lying pose inherits its floor-support weight (`ground` 1.0, e.g.
  `C.fallback_contact()`): a carried or lifted body must say `ground=0.0`, else the ground solver pulls it down onto
  the floor at the attacker's feet (round 6 follow-up: Goran's knee slam and shoulder carry never showed, his legs went
  through the body and once it sank under the floor). `MotionUltimate_Test` checks every Ultimate clip for it.
* **Whole poses on screen.** Roblox draws the joints written the frame before with a root moved this frame, so a big
  root step (a lift, a carry, a drop, the first frame) showed the last pose on the new root for a frame (Nia's body
  under the floor in run 1 of the playtest). In Play `CharacterPresenter` keeps each fighter's root with the joints
  shown and moves it in PreAnimation (`DeferRootToPicture`; motioncore.md section 15.7).
* **Leaving.** The defender's last frame is the knockdown clip's floor contact in the endKind pose (`FallBack` at its
  contact for FaceUp; `FallFrontAir` at its contact, head away from the attacker, for FaceDown); `Motion.States`
  continues the knockdown from that contact (`"Ultimate"` counts as an air key), so Landing/KO/getup continue without
  a pop. The attacker's last frame is its displayed stance on its own spot.
* **Fallback.** No clip installed (or no `throw.role`/frame): `Cinematic.fallbackKeyframe` poses the defender with a
  reaction per impact and a fall after the last, the attacker with a guard and a lunge into each impact. Nothing
  errors on missing fields (`MotionUltimate_Test`).
* Faces: attacker Shout, defender Pain; a fighter in Surge idles with Grit (`FaceController`).

## 4. Camera (`Client.CameraDirector`)

* `UltStart`: a short freeze (`UltFreeze` 0.14 s), a white flash and a push-in (`UltPushIn` 0.7 s) on the attacker.
* During the cinematic the camera plays the clip's `camera` keys (else `Cinematic.DEFAULT_CAMERA`): positions and
  look-at points in the attacker's frame in studs (+X its right, +Y up, +Z toward the defender), mirrored when the
  attacker stands on the viewer's right so the screen direction of the fight is kept. `cut = true` starts a new shot;
  keys interpolate with `ease` inside a shot. Every shot is checked against both bodies (`BodyMargin`) and the arena
  walls: a shot that would sit inside a body or a wall is pushed out of it (bodies never count as walls). Every shot
  keeps both fighters whole (head tops, hands and soles) inside the **safe picture area** `CineSafe` (normalised
  viewport: top 0.215 = under the HUD band of health bars, names and chips that covers the top letterbox bar, bottom
  0.87 = above the bottom letterbox bar, sides 0.04): `CameraDirector._fitShot` first turns the shot as little as it can
  (pitch and yaw about its own axes, roll kept), then widens the lens up to `CineFitMaxFov` (50 degrees), then moves
  the camera back, away from the bodies' middle and a little up, to the nearest place where it fits. The final camera
  of every frame (after smoothing, shake and the slow-motion narrowing) is checked once more (`_safeFov`, up to
  `GuardMaxFov`). `M._cinematicShot` is that whole computation, shared by the runtime and `CameraFraming_Test`, which
  projects the real posed heads, hands and feet of all 36 pairings through every Ultimate's camera (both viewing
  slots, 16:9 and 4:3). When authoring a reverse angle
  (the attacker's face past the defender), put the camera well to the side of the defender's shoulder (|x| >= 5 studs
  at z >= 6): a camera close behind the defender's back fills the frame with its body. The Play captures in
  `OV6/handoff/motion-shots/round6/ultimate-<fighter>-play.png` showed this on three first drafts (Sierra, Nia, Rhys).
* Slow motion narrows the lens a little on the final impact; at the end the camera returns to the fight camera over
  `CineReturn` (0.8 s). Attributes `CameraCinematic` / `CameraCinematicShot` expose the state for tests.
* **Fight camera headroom** (round 6 follow-up). The fight camera keeps every fighter's head under the HUD band:
  `FightFocusHeight` 3.75 (was 2.75) with the lens at chest height (`FightCameraRise` 0.72: 4.47 studs, as before) and
  `FightDistanceScale` 1.05, so a 6-stud fighter fills ~57% of the screen height at neutral spacing (55-65%). Each
  frame `_fitShot` fits both posed bodies (heads and feet) into `FightSafe` (top 0.215, bottom 0.93) up to
  `FightFitMaxFov` 44 (a jump, a juggle or a throw's close orbit turns the shot and widens the lens a little);
  `CameraFraming_Test` checks every pairing at five spacings from both player slots.

## 5. Effects and sound (`EffectsController`, `AudioController`)

* **Surge aura**: while a fighter's `surge` flag is on, its whole body glows in its surge colour (its roster accent
  made bright; grey accents use an icy blue): `CharacterPresenter`'s per-rig Highlight draws an outline around the
  body pulsing at `SurgeGlow.hz` (1.3 Hz) between outline transparency 0.08 and 0.42 with a faint fill (0.8-0.9, faces
  stay readable; `DepthMode` Occluded: never through walls or the other fighter); the hit flash and the mirror match's
  P2 outline share the same Highlight. Under it a pulsing floor ring of flames and sparks rising to the waist and a
  warm light (`EffectsController.AuraRates` flames 34 / sparks 14 / rings 1.6 per second, `AuraLight` 1.4, range 8).
  The `Surge` event adds a one-time burst: a glow flare (`SurgeGlow.flareSeconds` 0.7), a floor shockwave, a column of
  flames, sparks and a whoosh, an edge flash and a layered sound. When Surge ends, a fighter is put back on its mark or
  a round resets, every aura particle is cleared at once (`ParticleEmitter:Clear()`): nothing lingers where the fighter
  stood.
* **UltStart**: an inward-gathering burst on the attacker and a rising sound; a short, light screen flash (0.16 s:
  the HUD plays its own title card and letterbox on UltStart, so the effects add no text).
* **UltHit k**: an impact burst at the striking limb of `hits[k]` (else the midpoint), a heavier tier per impact; the
  last impact gets a double burst, a floor shockwave, dust and a whoosh. Landing dust and a thud when the defender's
  track reaches the floor inside the cinematic (`Cinematic.defenderGround`).
* Sounds are pitched layers of the existing impact sounds (`AudioController.Layers`), no new assets.

## 6. Authoring a cinematic (`tools/mocap/cine`)

Specs are Python (`ult_<fighter>.py`), built by `cinebuild.py` with the two-body solver (`twobody.py`) on key poses
sampled from the game's own move, reaction and fall clips (credits follow those clips):

```
python tools\mocap\cine\cinebuild.py --roster <roster.json> [--only Kael] [--no-write] [--sheets <dir>] [--debug]
lune run tools\mocap\cine\roster_dump.luau src <roster.json>      # the roster timelines as JSON
```

* Keys are at sim frames (60 fps): `pk(f, pose, ease, **edits)` with poses from `C.pose_at("Clip@seconds")`,
  `C.at(clip, "contact")`, `C.stance_of(fighter)`, `C.end_pose(endKind)`; relative edits `rot_plus` (heading frame),
  `waist_plus`, `neck_plus`, limb targets (`at`, `pole`, `local` chest/pelvis frame), grips onto the partner
  (`{"grip": C.chin(), "w": 1}`) and contacts. `C.rotated(pose, [x, y, z], about=…)` turns a whole pose (flips,
  spins), `C.flight(...)` builds a defender's fall onto its spot.
* `C.Hits().add(frame, limb, height, target)` records an impact (VFX limb, strike check, a runtime contact grip).
* `C.strike_beat(...)` builds a whole strike from an installed attack clip, `C.reach_dz(...)` solves how far to step so
  the striking limb meets the target without the bodies overlapping.
* The defender must end on `C.end_pose(endKind)` at z = 0 (its spot) and the attacker on its displayed stance at 0.
* The build reports partner penetration, self-intersection, the floor, foot sliding and the strike gaps per impact,
  and draws review sheets (both bodies every 10 frames, impacts in red).
* After writing, `python tools\mocap\cliplint.py src --states <States.luau>` and `MotionUltimate_Test` /
  `MotionGround_Test` check the modules; MotionQA (`ultimateCases`) measures them on the real rigs.

When combat re-times an Ultimate (a `KEYS:` commit), rebuild with a fresh roster dump: the specs place their beats
relative to the roster impact frames, so most re-timings need no spec change.

Checking it in a real Play session: start a Training practice (the player is always in Surge with the Ultimate
ready), walk into range and press the Ultimate (or L); the burst captures in the evidence folder were taken that way
from the fight camera, with the press injected through a LocalScript calling the practice runner's
`command("Attack", "Ultimate")`.
