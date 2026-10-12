# OV6 world handoff

Exports: `OV6\handoff\world-src\` (17 files, UTF-8, LF, no BOM, baseline file names). Unchanged and not exported:
`ServerScriptService.FightingLabWorldBoot`, `CL.LightingProfile`. Built world version attribute: `ov6-world-1`.

## What changed

The world builder (`ServerStorage.FightingLab.World.*`) was rewritten as a compact ring district called "Ember Square":

- Central plaza (radius 30, floor top Y = 0) with the Ember Beacon fountain/tower landmark, 6 spawn medallions
  facing north toward the Midnight Rooftop stair, the Fighter Kiosk (bearing 40, r 26) and the Hall of Champions
  leaderboard (bearing 314, r 26) beside the spawn court, a fingerpost with one arm per arena, and coloured
  wayfinding lines with chevrons from the beacon to each stair foot.
- Five stages in a ring round the plaza (bearing 0 = north/-Z, clockwise):

| Arena | bearing | FightOrigin distance | floor Y | stair width | worst walk spawn -> pad |
|---|---|---|---|---|---|
| Arena_MidnightRooftop | 0 | 70 | 6.0 | 26 | 52 studs |
| Arena_HarborDusk | 72 | 70 | 1.2 | 30 | 67 studs |
| Arena_SnowSummit | 144 | 66 | 4.2 | 34 | 77 studs |
| Arena_JungleRuins | 216 | 66 | 2.4 | 36 | 78 studs |
| Arena_TrainingBay | 288 | 70 | 1.2 | 30 | 71 studs |

  Walks are PathfindingService path lengths (agent radius 1.5, no jumping) from all 6 spawns to both pads. The
  budget is 90 studs (about 5.6 s at WalkSpeed 16), and World_Test enforces it. Before this change the arenas were
  150 to 220 studs out.
- Each stage is a round podium (top radius 31.5) reached by a straight stair from the plaza:
  - **Fight floor:** radius 21, centred on FightOrigin.
  - **Edge line:** glowing neon, 21.0 to 21.4, so it marks the clamp radius.
  - **Edge band:** 21.4 to 22.4.
  - **Barrier:** themed posts at radius 22.75. Rails, ropes and cords run between them, with their lowest edge at
    least 1.6 above the floor so knocked-down bodies slide under.
  - **Apron:** from the barrier out to 31.5. Pads and exits stand on it.
- The themed barriers are: neon rails (rooftop), hemp ropes on pilings (harbor), steel rail with an ice LED strip
  (summit), vine ropes on glyph stone posts (jungle), and red cord with a straw rope on lacquer posts (dojo).
- Each stage has its own backdrop:
  - **Rooftop:** neon city skyline.
  - **Harbor:** port cranes and containers, boats, and a lighthouse.
  - **Summit:** observatory dome, pines and snowfall.
  - **Jungle:** temple pyramid and canopy.
  - **Dojo:** pagoda hall over the bay and cherry trees.
- Grounds (`World.Walkways`): district floor slab (r 100, 6 thick, top 0), stone balustrade on the land sides and a
  quay rail over the water. Five pockets sit between the stages: Night Market (36), Sea Lookout (108),
  "EMBER SQUARE" welcome wall (180, the photo spot down the south walkway), Beach Garden (252) and Lantern
  Garden (324).
- Terrain (`World.TerrainSetup`): the sea, a rock foundation, green hills and snow-capped mountains outside the
  district. It is carved to air under the whole district (no grass or terrain can reach the hardscape).
  `Terrain.Decoration` stays off.
- `Kit.keepOut / Kit.clearSpot`: a keep-out registry. Stages, boards, edges, pockets and landmarks register their
  footprints, and trees, pines and ruins only grow in free spots. This prevents trunks through walls or benches.
- `CL.LobbyAmbience`: the API is unchanged. Only the positional ambience roll-off changed (min 16, max 80, was
  35/170), so the five loops do not pile up in the compact ring.

## Anchors (all names and attributes kept)

`workspace.FightingLabWorld.{Lobby,Arenas}`, `Lobby.LobbySpawn` x6, `Lobby.FighterKiosk.PromptPart.ChooseFighter`,
`Lobby.Leaderboard.LeaderboardGui` (800x600 canvas), per arena: `FightOrigin` (identity rotation; the fight axis is
still world X), `PadP1/PadP2` or `PadTraining/PadCpu`, `ExitP1/ExitP2` or `ExitTraining/ExitCpu`,
`StatusBoard.StatusGui`, model attributes `ArenaId, StageId, DisplayName, Kind, Order`, and
`ReplicatedStorage.FightingLab.WorldReady`.

Positions changed. Code reads them from the parts, so nothing else needs changing:

- **Pads:** 27 studs from FightOrigin at +/-50 degrees from the plaza direction, on the apron in front of the stage.
  Slot 1 is on the left as seen from the plaza. Pad top = floor + 0.2.
- **Exits:** at +/-63 degrees, r 27, on the stage floor, facing FightOrigin.
- **StatusBoard:** 52 studs behind FightOrigin (away from the plaza), facing the plaza.

Additions:

- Arena attribute `FightRadius` (21), plus `AccentColor` and `Tagline`.
- `StatusBoard.BoardIdle`: a SurfaceGui with ZOffset 0 under `StatusGui` (ZOffset 1). It shows the arena name
  while StationBoards hides StatusGui during the local player's fight. In the fight camera, the name sits in the
  board's visible lower half.
- `Gate_<StageId>`: a lettered name mat at each stair foot.
- World attributes: `PartCount, LightCount, EmitterCount, OccluderCount, BuildSeconds, BuildBusySeconds, Version`.
- Each arena model gets `WorstWalk` when World_Test runs.

The camera-occluder rule is kept: everything taller than floor + 1.5 within radius 46 of a FightOrigin is tagged
`FightingLabCameraOccluder`, including the barrier. Lobby and grounds pieces taller than a lamp stay at least 36
studs from every FightOrigin.

## Numbers (Play, server)

- 3,944 parts (budget 9,000; was ~7,100), all anchored.
- 98 lights, 25 particle emitters, 1,145 occluder tags.
- Build time 0.26 s wall, 0.16 s busy (the builder yields in 60 ms slices).

## Tests

`World_Test` was rewritten and now has 23 tests:

- Anchors and attributes.
- Pads and exits.
- Edge ring at 21 +/- 0.5 and the barrier for every arena.
- Flat floor to radius 25.
- Occluder tags.
- Lobby pieces clear of the fight cameras.
- Walking path at most 90 studs from the spawns to each pad (one test per arena).
- No piece clips into another section.
- No tree trunk through a structure.
- No coplanar overlapping surfaces (z-fighting scan, 2-stud grid over r 200).
- Every pocket reachable through a walkway at least 5 studs wide.
- No terrain or grass under the district (voxel read).
- Part budget, anchoring and build time.
- Lighting, signage text size, and pad light columns.

Full suite in Play: `[SUMMARY] 231 run, 231 passed, 0 failed`.

## REQUESTs

- **combat (NetProtocol):** `SpectatorRadius = 150` now covers all five arenas from anywhere in the district. Every
  running match therefore streams 20 Hz spectator snapshots to every lobby player. Consider ~75 to 90 if bandwidth
  matters: the plaza centre is 66 to 70 from each FightOrigin, so plaza watchers still see the fights.
- **ui (StationBoards):** pad tags (BillboardGui, MaxDistance 120) of the *other* arenas float in the fight-camera
  background, because the stages are now 66 to 70 apart. During the local player's own fight, consider hiding every
  arena's pad tags, not only the local arena's, or lowering MaxDistance to about 60.
- **integrator (DevWorld):** the stub world still places pads at +/-27 X. This is harmless (it is only used when the
  world is missing), but it no longer matches the real layout.

## Known issues

- Neighbouring stages are visible in the far background of some fight-camera angles (a compact-ring trade-off). The
  fight floor, edge and barrier still dominate the frame.
- The stair blocks of the rooftop overlap inside the podium/cheeks. They are never visible, and the z-fighting test
  only scans visible floor surfaces.
- Once, one capture frame of the open sea showed a checkerboard water LOD pattern from far above. The next frame was
  clean, so it is an engine render artifact.

## Round 2: fight exposure (fighters blown out in the Training Bay dojo)

**Cause.** Sun brightness 3.4 together with exposure +0.15 and a low bloom threshold (1.35). On top of that, four
stage spots at 1.3 to 1.6 and the fighters' own key/fill/rim lights pushed pale skin and platinum hair over the
bloom threshold. They clipped to white with halos. In shots that look straight into the low sun, sun rays (0.06) and
glare (0.55) also laid a flat orange veil over the frame.

**Changes** (world only, no motioncore files touched):

- `World.LightingSetup`:

| Setting | Before | After |
|---|---|---|
| ExposureCompensation | +0.15 | -0.1 |
| Bloom (Intensity / Threshold) | 0.55 / 1.35 | 0.35 / 2.5 |
| Grade (Brightness / Contrast) | +0.03 / 0.1 | 0 / 0.04 |
| SunRays intensity | 0.06 | 0.02 |
| Atmosphere glare | 0.55 | 0.25 |
| Sun angular size | 15 | 9 |

  Unchanged: sun Brightness 3.4, ClockTime 17.4, haze 1.9, ambient, saturation and tint. The sun stays low and
  warm, so each arena keeps its mood.
- Stage spots:
  - Shared constants `Layout.STAGE_SPOT_BRIGHTNESS = 0.45` and `STAGE_SPOT_RANGE = 46` (was 60).
  - `ArenaKit.stageLight` now takes a per-theme multiplier instead of an absolute brightness.
  - Resulting brightness: rooftop 0.495, harbor 0.56, summit and dojo 0.45. Before, they were 1.4, 1.6, 1.3 and 1.3.
  - Each spot is named `StageSpot`.
- `World_Test` has a new test, "fight exposure stays inside the measured ceilings":
  - exposure <= 0 and sun brightness <= 3.5;
  - bloom threshold >= 2 and intensity <= 0.4;
  - grade brightness <= 0.01 and contrast <= 0.06;
  - sun rays <= 0.03 and glare <= 0.3;
  - stage spots <= 0.6 within range;
  - no other light brighter than 3 reaches a fight floor.

  The floor probes now raycast against the world only. A player returned to an exit or pad by the duel server
  used to fail the exit test.

**Method.**
- The baked fight rigs come from real practice sessions: Sierra (palest skin, platinum hair) vs Goran, and Kael vs
  Nia (darkest outfits and skin).
- They are posed at each FightOrigin with the real `CameraDirector._plan` camera. A `FighterLighting` instance drives
  the key/fill/rim lights and a `StageController` instance fades occluders. The local-fight UI is hidden, as in a
  fight.
- Pose matrix: 5 orientations (0/90/180/270 plus 231 = straight into the sun) × 3 placements (centre, 16 studs
  towards the background, 16 studs towards the camera) × 2 pairs, for 150 poses.
- Each pose is captured three ways: the frame, a magenta Highlight silhouette mask of both fighters, and a head-only
  mask for faces.
- Stats use Rec. 709 luma over the eroded fighter mask.
- Harness and tools stay in `OV6\work\world\`: `harness.luau`, `devserver.py` (capture endpoint), `analyze.py` and
  `exposure.py`.

**Results** (fighter pixels; target p95 <= 235 and near-white <= 0.5 %):

| Arena | poses | fighter p95 max / median | near-white max | face p50 range | face p95 max | before: p95 max / near-white max / failing poses |
|---|---|---|---|---|---|---|
| TrainingBay | 30 | 224.3 / 182.4 | 0.00 % | 81-202 | 231.7 | 253.9 / 7.37 % / 13 of 24 |
| MidnightRooftop | 30 | 220.9 / 189.7 | 0.00 % | 102-173 | 220.8 | 253.5 / 9.30 % / 17 of 24 |
| HarborDusk | 30 | 198.4 / 162.5 | 0.00 % | 82-176 | 205.3 | 247.7 / 1.79 % / 8 of 24 |
| SnowSummit | 30 | 201.6 / 167.7 | 0.00 % | 80-186 | 213.5 | 251.1 / 7.07 % / 11 of 24 |
| JungleRuins | 30 | 202.0 / 161.6 | 0.00 % | 80-167 | 224.6 | 223.9 / 0.43 % / 0 of 24 |

Face p50 per fighter across all arenas: Sierra 105-174, Goran 107-179, Kael 82-139, Nia 105-203. No face pixel
clips.

The real practice fight in the dojo (Kael vs Sierra, after sidesteps and dashes, including straight into the sun)
was measured with the integrator's crop. Fight region p95 is 198-208 with 0 % near-white. Before, `p07-practice`
was 241.2 / 0.27 % and `b-06` was 251.5 / 1.12 %.

**Tests (round 2):** `World_Test` 24/24. Full suite in a fresh Play: `[SUMMARY] 322 run, 321 passed, 1 failed`.
The only failure is motioncore's `MotionGround_Test` (see below).

**Evidence** (`OV6\work\world\shots\r2x\`):
- `verify\sg\sheet-*.jpg` and `verify\kn\sheet-*.jpg`: per arena, every pose labelled with p95 and near-white.
- `base\*\sheet-*.jpg`: the same view before the change.
- `sheet-before-after.jpg`: integrator frames next to the same moments now.
- `real2\sheet-real2.jpg`: the real dojo fight after moving.
- `sheet-sun-compare.jpg`: looking into the sun, before and after the sun-ray and glare change.
- `lobby\sheet-lobby.jpg`: the lobby is still bright.

**Notes and REQUESTs for round 2**
- No change to `CL.FighterLighting` is needed, so there is no REQUEST for it. The fighters pass with margin at the
  profile strengths (key 0.55, fill 0.18, rim 0.3). As a diagnostic, halving those lights lowered the fighters' p95
  by only about 2 to 5 luma. The blow-out came from the global exposure, bloom and the stage spots.
- **motioncore (MotionGround_Test, not world):** in the full suite, "Sierra KO FaceDown sinks -0.049 (LeftLowerArm)"
  fails against its -0.04 threshold. The test poses rigs at its own constant floor (Y=120) and MotionPlayer does no
  world queries, so this is independent of the world and lighting.
