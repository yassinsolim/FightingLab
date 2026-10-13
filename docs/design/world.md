# OV6 world handoff

> **Current layout: see "Round 5: compact layout" at the end.** It supersedes the round-1 ring described below
> (positions, radii, pads and walk numbers). The anchors and the round-2 lighting are unchanged.

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

## Round 5: compact layout ("the lobby and arenas are too far away")

**Layout** (`World.Layout`, world version `ov6-world-5`). The five stages now stand in a horseshoe round the spawn
court instead of a ring round a larger plaza:

- **Spacing:**
  - Every FightOrigin is 66 studs from the plaza centre, and neighbouring stages are 56° apart.
  - Neighbouring stages are therefore 62 studs apart, with an 8-stud walkway between their podiums.
- **Plaza head:** the open side of the horseshoe (bearing 38, north-east).
  - Ember Beacon, 44 out.
  - Fighter Kiosk (bearing 17) and Hall of Champions (bearing 59), 36 out.
  - Fingerpost at bearing 38, 15.5 out.
- **Bearings** (clockwise from the plaza head) match the scenery behind each stage:

  | Stage | bearing | scenery behind it |
  |---|---|---|
  | Harbor Dusk | 106 | harbour basin, cranes, lighthouse |
  | Summit | 162 | peaks, observatory |
  | Jungle Ruins | 218 | jungle hills, pyramid |
  | Training Bay | 274 | the bay, pagoda hall |
  | Midnight Rooftop | 330 | city skyline, Orbit Tower |

- **Podium:** top radius 27 (was 31.5).
  - Fight floor 21; edge line 21 to 21.4; band to 22.4; barrier posts at 22.75; then a walkway round the barrier.
  - Floors: rooftop 4.2 (was 6.0), summit 3.0 (was 4.2), jungle 2.4, harbor and dojo 1.2.
  - Stairs are 8 wide (were 26 to 36).
- **Pads** left the podium and stand on the plaza in front of the stair:
  - 41 studs in front of FightOrigin and 7.5 to each side, so 26.1 from the plaza centre; top = plaza + 0.25.
  - Exits stand just behind them (34.5 in front, 7.5 to the side), facing the arena.
  - The name mat lies at the stair foot.
- **Spawn court:** the 6 spawns form a 3 × 2 block (5.2 × 5.2 apart) on the centre, facing the plaza head. Plaza
  radius is 34 (was 36).
- **NEW `Arrival` part** per arena (the lobbyux interface):
  - 4 × 0.2 × 4, Transparency 1, Anchored, CanCollide/CanQuery/CanTouch false.
  - 0.1 above the plaza, between the two pads: 41 in front of FightOrigin and 25 from the plaza centre.
  - Faces FightOrigin.
- **Grounds pockets**, re-centred on the new gaps: Night Market 38 (plaza head), Lantern Garden 134, welcome wall 190,
  Beach Garden 246 (now 2 palms), Sea Lookout 302.
- **Arena dressing**, re-placed for the smaller podiums and closer neighbours:
  - **Rooftop:** smaller HVAC units, skylights and dishes on the apron; the Orbit Tower behind the status board; one
    skyline tower moved from (-46, -128) to (-6, -128).
  - **Harbor:** pilings only round the back; bollards, rope coils, life rings and crates on the apron rim; festoons
    only on the back corners.
  - **Summit:** boulders only round the back, 4 studs out from the podium wall; snow drifts; prayer-flag poles on the
    ground just behind the podium; the observatory 57.7 out and 29.5 to the right.
  - **Jungle:** pyramid 77.5 out and 19.2 to the left; braziers on the apron rim.
  - **Dojo:** dummies side-on at the back; stone lanterns squared to the ring; cherry trees behind the pier's sides;
    lantern strings only on the back corners.
- **Neighbour checks while building.** Scenery placed round a stage checks its neighbours:
  - `ArenaKit.clearOfNeighbours`: nothing rising above a neighbour's floor + 1.5 within 32 studs of that neighbour's
    FightOrigin.
  - `ArenaKit.clearOfFightFloor`: cherry crowns stay outside the flat fight floor.
  - `Kit.woodClashes`: canopy trunks and boughs never interlock.

  A tree that fails a check is moved further out or left out.

**PathfindingService and thin plates.** PathfindingService treats the rim of a thin collidable plate as a wall, even
when the rim is only a few hundredths of a stud high:
- **Affected plates:** spawn plates, pads, name mats, paving rings, the kerb, lawns, sand beds, the summit's snow field
  and the jungle floor.
- **Effect:** paths detoured 5 to 13 studs round them. The snow field's rim alone closed the 8-stud walkway between the
  Harbor and Summit podiums, so an 8-stud hop became a 226-stud path.
- **Fix:** every such plate now carries a `PathfindingModifier` named `WalkOver` with `PassThrough = true`
  (`Kit.passThrough`). `Kit.walkOverThin` marks the lobby's and the grounds' thin layers (at most 1 stud thick, top at
  most 0.3).
- **Result:** players still collide with the plates as before. Computed paths now cross them in straight lines: the
  largest excess of any spawn-to-pad path over the straight line is 2.2 studs.

**Walks** (PathfindingService; agent radius 1.5, height 5, no jumping; all 6 spawns × both pads):

| Arena | before (main): worst / median | after: worst / median |
|---|---|---|
| Midnight Rooftop | 54.5 / 49.5 | 33.4 / 26.2 |
| Harbor Dusk | 67.1 / 59.5 | 33.4 / 26.2 |
| Jungle Ruins | 87.6 / 71.5 | 30.4 / 26.7 |
| Summit Observatory | 80.5 / 69.5 | 32.6 / 26.2 |
| Training Bay | 66.6 / 56.1 | 32.6 / 26.2 |
| all 60 pairs | 87.6 / 60.9 | 33.4 / 26.2 |

For the three worst pairs, a real `Humanoid:MoveTo` walk along the path covered 31.9 to 32.6 studs. At WalkSpeed 16
that is about 2 s of walking.

**Fight-camera background.** Measured with the real `CameraDirector._plan` "Fight" framing at the four fight-line
orientations, in a 16:9 frame:
- No other arena's ring centre is inside the central 60 % of the frame within 60 studs.
- Nearest in the central 60 %: 77.5 studs (Jungle and Summit, each seen from the other). Main: 93.3.
- Nearest anywhere in the frame: 75.8 studs (Rooftop and Dojo, at the frame edge).
- World_Test enforces this and stores the value in `FightingLabWorld.NearestCentralArena`.

**Lighting.** Measured with the round-2 harness: baked Sierra/Goran and Kael/Nia rigs, the real fight camera,
`FighterLighting` and `StageController` instances, and magenta masks.
- Poses: 120 (5 arenas × 4 orientations × centre/far/near × 2 pairs).
- Fighter p95 max per arena: dojo 210.4, rooftop 207.9, jungle 187.5, summit 184.2, harbor 177.4 (target ≤ 235).
- Near-white: 0.00 % everywhere (target ≤ 0.5 %). No pose fails.
- Face p95 max: 229.2.
- The stage spots moved in with the smaller podiums (r 26.2); their strength is unchanged.

**LobbyAmbience.**
- Pad light columns hide while the local player fights, sees results or practises. With the stages this close, other
  arenas' columns would otherwise stand in the fight camera's background.
- The positional ambience roll-off is 14/52 (was 16/80).

**Numbers** (Play; same Studio and same load as the main measurement):

| | main | r5-world |
|---|---|---|
| Parts | 3,944 | 3,860 |
| Lights | 98 | 92 |
| Occluder tags | 1,145 | 1,220 |
| Build time, busy | 0.12 to 0.15 s | 0.16 to 0.17 s |
| Build time, wall | 0.18 to 0.29 s | 0.21 to 0.33 s |

**Tests.** `World_Test` now has 28 runs (was 24).
- New tests:
  - every arena has a valid `Arrival`;
  - no other arena's pieces rise inside a fight camera's orbit (32 studs), and stages stand at least 58 apart;
  - the camera-frame check above;
  - the median walk is at most 30 studs.
- Changed tests:
  - per-arena walks must be at most 40 studs. The bound is hard-coded so that a wider layout fails.
  - pads stand on the plaza, and exits on the plaza floor;
  - spawns face the plaza head;
  - the pad-column rule covers the local fight;
  - the part ceiling is 3,944;
  - flat distances are exact for cylinders.
- Results:
  - On main's world, the final World_Test fails 13 of 28. That includes all five per-arena walk tests (48.9 to 73.0
    studs) and the median test (61.2).
  - On the branch it passes 28 of 28.
  - Full suite on `r5-world`: `[SUMMARY] 403 run, 403 passed, 0 failed`.

**Evidence:** `OV6\handoff\world-shots\round5\`.

**Notes**
- `NetProtocol.SpectatorRadius` (85) needs no change. Every FightOrigin is 66 studs from the plaza centre (main: 66 to
  70). The whole spawn court therefore still streams all five stages, which are at most 72 studs away. As before, the
  far rim of the plaza is at most 100 studs from the opposite stage.
- The Fighter Kiosk and the Hall of Champions are not walk-tested. I measured paths from the six spawns to a spot in
  front of each:
  - Kiosk: 28 to 48 studs.
  - Hall: 29 to 35 studs, except from the two west spawns (63 and 68). There PathfindingService detours round the
    fingerpost, while a player walks straight past it (37 studs).
- On the Summit and Jungle, the default north/south fight views look across the plaza. The kiosk, the hall and the
  Rooftop's status board stand in the background beyond the barrier. They are lobby props, not fighters.
- Any new thin plate on a walkway needs `Kit.passThrough`, or computed paths will route round it. The walk and pocket
  tests catch this.

## Round 6 (look): an art pass per arena ("more refinements on the whole look of the game")

Every duel arena now has its own world in a fight: a mood, a light rig, fight-only scenery with a crowd, and its
own floor dressing. The lobby keeps the shared golden hour, so lobby players and spectators see the world as before.
World version `ov6-world-6`. Anchors, attributes and the compact layout are unchanged: World_Test passes 28 of 28.

### Arena moods (`Client.LightingProfile`, client only)

When the local fight starts, `StageController` calls `LightingProfile.applyArena(stageId)`. When it ends, it calls
`restore()`. The mood sets the time of day, ambient, atmosphere, sky, clouds, bloom, the colour grade, sun rays, a
subtle depth of field and the light rig. Every changed value is recorded first and put back exactly. Effects the
mood creates carry the `FightingLabArenaLook` attribute and are removed on restore. On the server it does nothing.

| arena | mood | clock | bloom (intensity / threshold) | grade (contrast / saturation) | sun rays | DOF far | rig: key / rim |
|---|---|---|---|---|---|---|---|
| Midnight Rooftop | Neon Midnight | 0.6, moonlit night | 0.55 / 1.9 | 0.14 / 0.16 | 0 | 0.22 | cool white 0.95 / magenta 2.2 |
| Harbor Dusk | Last Light | 18.05, sun on the water | 0.45 / 2.0 | 0.10 / 0.20 | 0.03 | 0.18 | amber 0.9 / violet 2.4 |
| Jungle Ruins | Canopy Haze | 15.6, humid afternoon | 0.34 / 2.3 | 0.12 / 0.12 | 0.04 | 0.20 | warm 0.8 / leaf green 1.8 |
| Summit Observatory | Blue Hour | 5.85, before sunrise | 0.50 / 1.8 | 0.12 / -0.04 | 0 | 0.20 | warm 1.05 / ice blue 1.5 |
| Training Bay | Morning Calm | 8.6, low sun | 0.35 / 2.2 | 0.07 / 0.06 | 0.03 | 0.16 | warm 0.7 / amber 1.8 |

- **Ceilings** (`LightingProfile.CEILINGS`, pinned by ArenaLook_Test):
  - exposure ? 0.3;
  - bloom ? 0.9, with a threshold of at least 1.35;
  - grade brightness ? 0.04 and contrast ? 0.16;
  - sun rays ? 0.06, glare ? 0.4, DOF far ? 0.3;
  - rig key ? 2.4, rim ? 4.5.
- **Depth of field:** `setFocus` keeps it on the fighters every frame.
- **Fight light rig:** two spot lights (no shadows) that follow the fight camera (`StageController.rigFrames`). The key
  comes from the camera side. The rim is coloured and comes from behind the fighters. Both are aimed at the fighters.

### Fight sets (`World.FightSets` ? `ReplicatedStorage.FightingLab.FightSets.<StageId>`)

The sets are built with the world but never placed in the Workspace. `StageController` clones the local player's
arena set for that player's fight only. The fight camera then sees the arena's own world instead of the plaza, the
other arenas and the city.

**Placement rules**
- A piece only stands on a covered bearing:
  - `ARC` = 105? either side of the plaza side;
  - plus `NORTH_ARC` = 50? round north, which is the default fight camera's view (unless the arena's own backdrop is
    there).
- Every piece stands at least `MIN_RADIUS` = 38 studs from FightOrigin. The fight camera orbits inside 36, so no set
  piece can come between the camera and the fighters.
- Every part is anchored and quiet: no collide, no query, no touch.

**Sets per arena**
- **Rooftop:** neighbouring rooftops with water tanks and antennas, a big neon billboard, a crowd on a terrace, far
  towers, drizzle.
- **Harbor:** stacked freight, a lit warehouse with loading bays and its sign, a dock crane, dock workers watching,
  warm dust in the low sun.
- **Jungle:** understory, giant trees, a closed canopy, vines, a ruined gate with glowing glyphs, ground mist, fireflies.
- **Summit:** a snowy ridge with pines, far peaks, an aurora (beams, no textures), snowfall.
- **Dojo:** a garden wall with lanterns, blossoming trees, a five-roof pagoda, misty mountains across the bay, students
  watching, drifting petals.

**Shared pieces**
- **Far hills** close every horizon, so the city towers behind the plaza disappear in the haze.
- **Crowd:** spectator silhouettes drawn on transparent SurfaceGui panels (no part per person) and shaded by the
  scene's light. StageController makes each figure sway (attributes `Phase` and `Rate`).

**District hide**
- While the local player fights, the Lobby and the other arenas are hidden on that client:
  - `LocalTransparencyModifier = 1`;
  - their guis, emitters, beams and lights are switched off.
- `clearArena` puts everything back.
- `LobbyAmbience` never writes 1 (it uses 0 and 0.85), so the two never fight over a part.

### In-world dressing (the server's world, seen by everyone)

- **Floor decals:** `ArenaKit.paintBar`, `paintTicks` and `paintCrest` lay flat decals made of thin, non-colliding
  parts:
  - a crest in the ring centre: hex (Rooftop), compass (Harbor), flake (Summit), enso (dojo);
  - minute ticks round every ring edge.
- **Banners:** named banners on poles behind the rails: MIDNIGHT / ROOFTOP, PIER 9 / DUSK, SUN / GATE, SUMMIT / PEAK.
- **Reflectance:** the Rooftop deck 0.06, the Summit floor 0.04.
- **Stair name mats:** they used TextScaled, which splits a word ("HARBO / R DUSK", "TRAININ G BAY"). They now put one
  word per line (`ArenaKit.nameLines`) at the largest fixed size that fits (`ArenaKit.nameTextSize`, 32 px per stud,
  at least 18 px).

### Fix: the Rooftop and Summit fight floors turned magenta / cyan

The global `FightingLabCameraOccluder` tag is meant for lower neighbours. `StageController` also applied it to the
fighting arena's own floor stack, faded it, and the neon EdgeLine disc beneath showed through. Occluders now count
per arena: a tagged part only fades when its top is above the fight floor + 1.5 (`occluderRelevant`). The
ArenaLook_Test regression fails without the fix: "Arena_MidnightRooftop: FightFloor must never fade in its own
fight".

### Numbers (Play, server and client)

| | before (main) | round 6 |
|---|---|---|
| world parts (`PartCount`) | 3,860 | 3,892 (+0.8 %; the World_Test ceiling 3,944 is unchanged) |
| world lights / casting shadows | 92 / 0 | 92 / 0 |
| world build (`BuildSeconds`) | not measured | 0.24 s, plus 0.02 s for the sets (0.24-0.27 s across runs) |
| fight-only parts (one set, one client) | none | Rooftop 86, Harbor 202 (1 light), Jungle 191, Summit 188, Dojo 273 |
| fight rig | none | 2 spot lights, no shadows |

### Readability: fighter luma in real fights

The tool is `cap_luma.py`. It runs CPU Easy fights (practice in the dojo) at 1920 x 1080. Each fighter is masked with
a green Highlight and the mask is eroded by 3 px. About 135,000 fighter pixels are measured per arena.

| arena | fighter luma p50 | p95 | near-white (? 245) |
|---|---|---|---|
| Midnight Rooftop | 62.5 | 188.1 | 0 % |
| Harbor Dusk | 65.5 | 188.0 | 0 % |
| Jungle Ruins | 70.0 | 220.5 | 0 % |
| Summit Observatory | 90.1 | 212.5 | 0.32 % |
| Training Bay | 120.2 | 210.3 | 0.46 % |

### Assets

No external assets were added. Everything uses built-in materials (Slate, Limestone, Wood, LeafyGrass, Rock, Snow,
Plaster, Metal, CorrodedMetal and others), procedural parts and SurfaceGui silhouettes, so there is nothing new to
credit.

### Tests

- **ArenaLook_Test** (new, 6 tests):
  - every mood stays inside the ceilings;
  - `applyArena` / `restore` put back every value exactly;
  - a fight never fades its own floor stack;
  - the light rig is aimed at the fighters;
  - the sets: one per arena, quiet, inside the part budget, and outside the camera orbit in the fighters' height band;
  - the stair name mats.
- World_Test passes 28 of 28.

**Evidence:** `OV6\handoff\look-shots\round6\`.

### Known issues

- The biggest change is in the fight view. From the lobby, the new dressing (crests, ticks, banners) is subtle.
- The crowd is made of 2D silhouettes.
- No MaterialVariants or SurfaceAppearance: no new textures were uploaded.
- In a still frame, the hit flash (CharacterPresenter's white Highlight, owned by motion) can make a fighter look
  washed out for a few frames.
