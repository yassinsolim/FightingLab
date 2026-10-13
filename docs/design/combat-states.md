# combat-states.md — fight states, snapshot fields and movesets (OV6, combat agent)

Owner: combat. Source of truth: `RF.CombatSim` (rules), `RF.Roster` (moves), `RF.CombatAI` (CPU), `RF.Controls` (keys).
Round 6: the per-fighter move tables moved to `docs/design/movesets.md` (generated from the Roster with every key,
frame data, stance, Ultimate timeline and combo route); this file keeps the states, fields and rules. Frames are 60 Hz
sim frames.

## 1. Fighter states (`FighterView.state`)

| state | meaning | timing / fields for animation |
|---|---|---|
| `Idle` | standing still. **Standing guard is active** (`guard = "Stand"`) | `walkPhase` frozen |
| `Walk` | walking forward (D). **Not guarding** (`guard = nil`) | ~4.3–5.7 studs/s (per fighter, `Roster.stats.walkSpeed`); `walkPhase` advances 9 rad/s |
| `Backwalk` | walking back (A). Standing guard active | 3.5–4.6 studs/s (`backSpeed`) |
| `Crouch` | holding down (S). Crouch guard active (`guard = "Crouch"`), **stationary** | `crouchFrames` = frames since the crouch started |
| `Dash` | committed forward dash (double-tap D) | `dashFrame` 1..`dashTotal` (13–15 f), travel `dashDistance` (2.6–3.5 studs) with ease-out `1-(1-t)^2`; can turn into an attack from frame 3 (`f,f+` moves) |
| `Backdash` | committed backdash (double-tap A), chainable | `dashFrame` 1..`dashTotal` (17–19 f); travel happens in frames 1–14 (ease-out), the rest is a settle; a new backdash can chain from frame 15; attack cancel from frame 12 |
| `Sidestep` | ONE discrete sidestep per tap (tap W = in, tap S = out) | `stepDir` (+1 = the fighter's own LEFT = into the screen for the left-side player, -1 = its RIGHT = toward the camera), `stepFrame` 1..22: frames 1–16 travel along an arc around the opponent (ease in-out, arc length `stats.sidestepArc` 1.5–2.1 studs, distance to the opponent constant, the fighter keeps facing the opponent), frames 17–22 recovery (feet settle). Cancels: attack from frame 8 (`ss+` moves), holding back from frame 17 ends it into guard |
| `Startup` / `Active` / `Recovery` | executing `move` | `moveFrame` 1..total; first active frame = runtime `def.startup + 1` = `def.impact` (= the "impact" column below, which is the `startup = N` literal of the Roster source); `stringIndex` = 1 for a starter, 2/3 for string follow-ups. Root motion: the sim moves the root forward by `advance` studs spread evenly over the startup frames — `advance / startup` per frame on `moveFrame` 2..`impact` (runtime `startup` = impact − 1), so the root offset at `moveFrame` k is `advance × min(k − 1, startup) / startup` and the full advance is reached on the first active frame (lunges are REAL movement now — remove cosmetic lunges or match them). The attacker stops early if the bodies meet (separation 2.6); the defender is never shoved by the step. **Step-in moves (REQUEST 7):** 57 moves that visibly connected short now have a smaller `range` and a larger `advance` with the same threat range (`range + advance`); animate them as a real step (support foot travels with the root). Facing: locked at move start, except `track`°/frame during startup (and through the active frames for `homing` moves) |
| `Hitstun` | hit reaction | `stun` frames left; `lastHit` (kind/height/tier/counter/limb/side) |
| `Blockstun` | blocking a hit | `stun` frames left; `guard` = "Stand"/"Crouch" (blocked low = crouch block); `lastHit.kind = "Block"` |
| `Stagger` | parried | `stagger` frames left (24-26). Round 6: the PARRYING fighter is free at once (its parry move or stance ends), so the stagger is its punish window |
| `Stance` | **round 6:** in its 3+4 signature stance | `stance` = the stance key (`"Pocket"`, `"Southpaw"`, `"Aerial"`, `"StillWater"`, `"Coil"`), `stanceFrame` 1, 2, 3... since entry; `crush` / `guard` follow the stance (Pocket high crush, Southpaw standing guard, Aerial low crush + 2.2 studs of forward travel over frames 1-18, Still Water parries highs/mids); ends into a follow-up move, `Idle` (back held from `backExit`, 3+4 again, or `maxFrames`), or a hit/block. Locked (never extrapolate). See movesets.md 2.1 |
| `Ultimate` | **round 6:** inside the Ultimate cinematic (both fighters) | `throw` table with `archetype = "ultimate"`, `move = "Ultimate"`, `role` Attacker/Defender, `frame` 1..`duration` (cinematic frame), `impactFrame` = first impact; positions locked (defender `endDistance` in front); `UltHit` events on the impact frames; then the defender lies in `Landing` (`knockdown` = endKind) or is `KO` (declared at the end), the attacker is `Idle` |
| `Airborne` | launched / juggled | `velocityY`, `airFrames`, `airHits`; root `pos.Y` is the real height (gravity 44 studs/s², launch 19 studs/s since round 6). `tumble = true` from a tumble hit until it lands (spin the body: one extra juggle hit, ends face down). **`knockdown` set while Airborne** = the juggle is over (knockdown hit, 4th air hit or air time cap): the body falls the rest of the way (never snapped down), no more hits connect, and it becomes `Landing` when `pos.Y` reaches 0 |
| `Landing` | **on the floor** after a knockdown or throw (fully invulnerable) | lasts 34 f (`stun` counts down; `Config.LandingFrames`); `knockdown` = "FaceUp"/"FaceDown"; `getupKind` gets set while lying (hold back = "BackRoll", tap W/S = "SideRoll") |
| `Getup` | standing up (fully invulnerable) | `stun` counts down from 26 (+10 for rolls; `Config.GetupFrames`, `RollFrames`) — about 1.0 s from touching the floor to standing (1.2 s with a roll); `getupKind` "Stand" / "BackRoll" (root travels 2.2 studs straight back over the first 10 f) / "SideRoll" (2.2 studs sideways, `rollDir` +1 left / -1 right); the first frame after Getup is a guarding Idle |
| `KO` | knocked out | body lies on the floor. A KO in the air keeps falling: `pos.Y` > 0 and `velocityY` < 0 for a few frames until it reaches 0 (also during RoundOver/MatchOver). Never snap a body to the floor yourself; never leave it floating |
| `Throw` | inside a throw (`throw` table) | `throw.role` Attacker/Defender, `throw.move` (move key), `throw.archetype`, `throw.frame` 1..`throw.duration`, `throw.impactFrame` (damage + knockdown), `throw.breakWindow`. **Break**: event `ThrowBreak`, then `throw.broken = true` and `throw.breakFrame` (the throw frame of the break) for 16 more frames (`Config.ThrowBreakFrames`, both locked: play the break / shove-apart tracks), then both fighters return to `Idle` together, pushed 0.6 studs apart (neutral, nobody is plus) |

Removed since OV5: the free `Block` state (guard is automatic, see `guard`) and the `Step` state (now `Sidestep`, a
discrete step, no continuous orbit). `Dash` with `moveX < 0` is no longer used for backdashes: use `state == "Backdash"`.

## 2. Snapshot fields (additive; path `MatchRunner.serialize` → `NetProtocol` pack/encode → `RenderBuffer.parse`)

Existing fields keep their meaning. New in OV6 (per fighter): `guard` ("Stand" | "Crouch" | "All" | nil),
`stepDir`, `stepFrame`, `dashFrame`, `dashTotal`, `stringIndex`, `getupKind` ("Stand" | "BackRoll" | "SideRoll" | nil),
`rollDir`, `crouchFrames`, `throw.move`, `throw.breakWindow`, `throw.broken`, `throw.breakFrame` (motioncore REQUEST). Per entry: `dummy` ("Stand" | "Guard" | "Fight" | nil,
practice dummy behaviour). Events: `Whiff.evaded = true` when the move missed because the target sidestepped it.

Round 6 (codec v3, `NetProtocol` CODEC_VERSION 3; absent fields read as false / nil / 0): `surge` (fighter flag bit 32),
`ultUsed` (bit 64), `tumble` (bit 128), `stance` + `stanceFrame`; states `"Stance"` and `"Ultimate"`; the cinematic `throw`
table (`archetype = "ultimate"`). Events: `Surge` (attacker = target = the fighter entering Surge), `UltStart` (the
Ultimate's first frame), `UltHit` (`combo` = impact index 1..n, `knockdown = true` on the last), `KO` with `move =
"Ultimate"` at the end of a lethal cinematic, `Catch` (Goran's Bear Trap; attacker = Goran), `Hit.tumble = true`
(event flag bit 64), `Hit.punish = true` (event flag bit 128: a clean ground hit on an opponent recovering from its
own move or staggered after a parry, for a HUD "PUNISH" call-out). Debug attributes: `LearnerSurge`, `LearnerUltUsed`, `LearnerStance` (and `Trainer*`).

Event kinds are unchanged: `Hit` (`counter`, `launch`, `knockdown`, `air` flags), `Block` (`height` Low = crouch
block), `Whiff`, `KO`, `Parry`, `Crush`, `Armor`, `ThrowStart`, `ThrowHit`, `ThrowBreak`.

## 3. Rules that matter for presentation

- Fighters always face each other when free; during a move the facing only changes by the move's tracking.
- No chip damage: `Block` events carry `damage = 0`.
- Guard: standing still or holding back = standing guard (blocks highs and mids), holding down = crouch guard (blocks
  lows, ducks highs, mids hit). Walking forward, attacking, dashing, sidestepping and all reactions do not guard.
  Special mids (`*` below) are blocked by both guards.
- Throws: 1+3 throws are broken with 1, 2+4 throws with 2, within `breakWindow` frames of `ThrowStart` (the first
  punch pressed decides); crouching ducks throws; throws cannot grab someone in hit/blockstun or on the floor.
  Throw reach is 3.2 studs centre-to-centre (bodies touch at 2.6); a whiffed grab recovers in 34 frames (punishable).
- Juggles: max 4 air hits (+1 after the one tumble hit of a juggle; the last forces a knockdown), damage scaling
  0.7 × 0.82^n, air time cap 110 f (round 6: launch 19, re-lift 9, tumble lift 12 studs/s). Ground combos are scaled
  from their 4th consecutive hit (× 0.85 / 0.75 / 0.65, min 0.6).
- Round 6 Surge and the Ultimate (CONTRACTS-v6.md, Surge and Ultimate): Surge on the first frame at or below 25 %
  health (× 1.1 damage), the Ultimate (1+2) once per round only in Surge, armored startup, cinematic on hit, KO declared
  at the end, the round clock waits for the cinematic. Free Training keeps the player in Surge with the Ultimate
  refilled (no damage bonus).
- Knockdown → Landing (34 f) → Getup (26 f, +10 when rolling) → Idle (guarding). Both lying and getting up are
  invulnerable; ground hits do not exist.

## 4. Controls (binding, contract §2; data in `RF.Controls`)

D forward (double-tap: dash) · A back + guard (double-tap: backdash, chainable) · tap W = sidestep in · tap S =
sidestep out · hold S = crouch (crouch guard) · U = 1 · I = 2 · J = 3 · K = 4 · O = throw (1+3) · U+J = 1+3 throw ·
I+K = 2+4 throw · break with U (1) or I (2) · J+K = 3+4 signature (stance or catch) · L (or U+I together) = the
Ultimate (1+2, only in Surge) · G = controls guide · practice: R reset, T Training/Versus CPU (LobbyUI),
1/2/3 difficulty (LobbyUI), Y dummy Stand/Guard/Fight, P pause, Backspace leave (LobbyUI). Gamepad: stick/D-pad move,
X/Y/A/B = 1/2/3/4, RB throw, RT Ultimate, Start pause, Select guide.

## 5. Practice dummy

`MatchRunner:command("Dummy", "Stand" | "Guard" | "Fight" | nil)` (nil cycles). Stand = never guards on its own
(holding back/down still would), Guard = blocks everything (highs, mids and lows), Fight = the CPU fights back
(= old Spar) at the Training difficulty; switching to Fight starts a fresh CPU brain (it did not watch what happened
while it stood or guarded). Visible as `entry.dummy`. Client: `ctx.modules.Input.practice("Dummy", mode)`.

## 6. Movesets

Moved to `docs/design/movesets.md` in round 6 (generated from `RF.Roster`: every key, input, notation, frame
data, properties, animation intent, the stances, the Ultimate timelines with their beats, and the combo routes).
