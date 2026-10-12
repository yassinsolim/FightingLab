# combat-states.md — fight states, snapshot fields and movesets (OV6, combat agent)

Owner: combat. Source of truth: `RF.CombatSim` (rules), `RF.Roster` (moves), `RF.CombatAI` (CPU), `RF.Controls` (keys).
This file is regenerated from the Roster (`work/combat/harness/gen_states_doc.luau`); the moves section is always
current. Frames are 60 Hz sim frames. Code exports: `OV6\handoff\combat-src\`.

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
| `Stagger` | parried | `stagger` frames left |
| `Airborne` | launched / juggled | `velocityY`, `airFrames`, `airHits`; root `pos.Y` is the real height (gravity 44 studs/s², launch 16 studs/s). **`knockdown` set while Airborne** = the juggle is over (knockdown hit, 4th air hit or air time cap): the body falls the rest of the way (never snapped down), no more hits connect, and it becomes `Landing` when `pos.Y` reaches 0 |
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
- Juggles: max 4 air hits (the 4th forces a knockdown), damage scaling 0.7 × 0.82^n, air time cap 86 f.
- Knockdown → Landing (34 f) → Getup (26 f, +10 when rolling) → Idle (guarding). Both lying and getting up are
  invulnerable; ground hits do not exist.

## 4. Controls (binding, contract §2; data in `RF.Controls`)

D forward (double-tap: dash) · A back + guard (double-tap: backdash, chainable) · tap W = sidestep in · tap S =
sidestep out · hold S = crouch (crouch guard) · U = 1 · I = 2 · J = 3 · K = 4 · O = throw (1+3) · U+J = 1+3 throw ·
I+K = 2+4 throw · break with U (1) or I (2) · G = controls guide · practice: R reset, T Training/Versus CPU (LobbyUI),
1/2/3 difficulty (LobbyUI), Y dummy Stand/Guard/Fight, P pause, Backspace leave (LobbyUI). Gamepad: stick/D-pad move,
X/Y/A/B = 1/2/3/4, RB throw, Start pause, Select guide.

## 5. Practice dummy

`MatchRunner:command("Dummy", "Stand" | "Guard" | "Fight" | nil)` (nil cycles). Stand = never guards on its own
(holding back/down still would), Guard = blocks everything (highs, mids and lows), Fight = the CPU fights back
(= old Spar) at the Training difficulty; switching to Fight starts a fresh CPU brain (it did not watch what happened
while it stood or guarded). Visible as `entry.dummy`. Client: `ctx.modules.Input.practice("Dummy", mode)`.

## 6. Movesets (generated from `RF.Roster`)

Columns: key (stable id the clip binds to) · name · notation (buttons 1-4 = U/I/J/K, f/b/d = D/A/S held, ss = during a sidestep, f,f = out of a forward dash) · height · impact frame (first active frame) / active / recovery · on block / on hit · damage · reach + root advance (studs the sim moves the attacker forward during startup) · flags · archetype (current placeholder generator) · **animation intent**.

Frame numbers: the impact frame `i` is the `startup = N` literal written in the Roster source. The Roster constructor stores it as `def.impact = N` and `def.startup = N - 1` (frames before the first active frame), so at runtime the move is in `Startup` for `moveFrame` 1..N-1 and its first active frame is `moveFrame` N. Example: Jab `i = 10` means Startup on moveFrames 1-9 and the hit lands on moveFrame 10.

### KAEL — Street boxing / pressure (boxer stance)

Stance: upright, high tight guard, light bounce on the balls of the feet, narrow stance, chin tucked. Stats: health 100 · walk 5.0 / back 4.0 studs/s · dash 3.0 studs in 14 f · backdash 3.0 studs in 18 f · sidestep arc 1.8 studs · preferred range 3.6.

| key | name | input | height | i / act / rec | block / hit | dmg | reach + adv | flags | archetype | animation intent |
|---|---|---|---|---|---|---|---|---|---|---|
| Jab | Jab | 1 | High | 10 / 2 / 12 | +1 / +8 | 6 | 4.2 |  | straight | Lead-hand jab from a tight high boxing guard: small step of the lead foot, lead shoulder rolls over the chin, fist snaps straight to head height and back to the cheek; rear hand stays glued to the jaw. |
| OneTwo | One-Two | 1,2 | High | 10 / 2 / 14 | -2 / +6 | 8 | 3.95 + 0.65 | string after Jab | straight | Rear straight right thrown as the jab returns: rear heel pivots out, hips and shoulders rotate fully, fist extends to head height, weight finishes over the lead knee. |
| LiverHook | Lead Liver Hook | 1,2,1 | Mid | 14 / 3 / 20 | -9 / +3 | 12 | 3.9 + 0.3 | string after OneTwo, tracking | body_hook | Short lead hook to the opponent's right side (liver): level change by bending both knees, lead elbow bent ninety degrees, torso whips from the hips, fist lands at rib height. |
| Cross | Straight Right | 2 | High | 11 / 2 / 14 | -3 / +5 | 9 | 3.6 + 1.0 |  | straight | Rear straight right from the guard without the jab: rear foot pivots, hip and shoulder drive through, fist extends at chin height, lead hand covers the face. |
| CrossHook | Right Into Body Hook | 2,1 | Mid | 13 / 3 / 18 | -8 / +3 | 11 | 3.9 + 0.2 | string after Cross, tracking | body_hook | After the straight right, the boxer dips slightly and rips a lead hook to the body: weight shifts onto the lead leg, lead hip turns in, forearm horizontal at stomach height. |
| Overhand | Overhand Right | f+2 | High | 16 / 3 / 18 | -5 / +6 | 15 | 3.6 + 1.4 | counter: KND | overhand | Looping overhand right: step in with the lead foot, rear arm arcs up and over the shoulder and comes down onto the head, upper body rolls forward and down to the left, rear heel lifts. |
| BodyBlow | Crouching Body Shot | d+2 | Mid | 14 / 3 / 17 | -6 / +4 | 12 | 3.8 + 0.3 | crouching | body_hook | From a deep crouch, rear shovel punch to the stomach: knees stay bent, rear shoulder dips, fist travels forward and slightly upward into the body, chin tucked behind the lead glove. |
| RisingUppercut | Rising Uppercut | df+2 | Mid | 15 / 3 / 22 | -14 / LAUNCH | 14 | 3.9 + 0.3 | high crush f1-7 | uppercut | Rear uppercut rising from a crouch: legs explode upward, hips drive up and forward, rear fist travels vertically from waist to above the head, body ends fully extended on the toes. |
| WeaveHook | Weaving Hook | b+2 | High | 17 / 3 / 19 | -9 / +4 | 15 | 3.7 + 0.7 | homing, high crush f4-14 | weave_hook | Upper body weaves down and under (U-shaped bob) then comes up with a wide lead hook to the head; the hook sweeps horizontally and turns with the opponent (homing), head stays low until the punch fires. |
| ShinKick | Shin Kick | d+3 | Low | 12 / 2 / 20 | -12 / +1 | 7 | 4.0 | crouching | low_kick | Quick lead-leg toe kick to the shin from a half crouch: knee lifts slightly, foot snaps out low along the floor and returns, hands stay in the guard. |
| LegKick | Low Roundhouse | d+4 | Low | 19 / 3 / 24 | -17 / KND | 14 | 3.8 + 0.6 |  | low_kick | Heavy rear-leg roundhouse to the thigh/calf: step out with the lead foot, hips turn over, shin swings down through the opponent's leg at knee height, arms swing for balance. |
| FrontKick | Push Kick | 3 | Mid | 13 / 3 / 17 | -6 / +3 | 10 | 3.9 + 1.1 |  | front_kick | Lead-leg push kick to the stomach: knee chambers to the chest, hips push forward, sole of the foot extends straight out, torso leans back slightly, foot returns to stance. |
| Roundhouse | Street Roundhouse | 4 | High | 15 / 3 / 20 | -8 / +5 | 13 | 4.4 + 0.8 | tracking | roundhouse | Rear-leg roundhouse to the head: lead foot pivots, hips rotate fully, shin whips around horizontally at head height, rear arm swings down for counterbalance. |
| ChargingCross | Charging Straight | f,f+2 | Mid | 16 / 3 / 22 | -10 / KND | 17 | 3.6 + 2.2 |  | straight | Out of a forward dash, a lunging rear straight to the chest: big step forward, whole body travels behind the punch, rear leg drags, the boxer ends stretched forward. |
| Throw | Clinch Headbutt | 1+3 | Throw | 12 / 2 / 34 | break 1 ≤f20, impact f30 of 46 | 18 | 3.2 |  | clinch_strike | Both hands grab the back of the opponent's neck (collar tie), pull the head down, two short knees to the body, then shove them away so they fall on their back. |
| ThrowB | Over-Under Toss | 2+4 | Throw | 12 / 2 / 34 | break 2 ≤f20, impact f32 of 48 | 19 | 3.2 |  | hip_toss | Over-under body lock: rear arm under the opponent's armpit, lead arm over the shoulder, then a hip lift and dump in front onto their back. |

### SIERRA — Kickboxing / range control (kickboxer stance)

Stance: bladed, mid-high guard, rhythmic weight shift front-back, lead foot light. Stats: health 95 · walk 5.4 / back 4.4 studs/s · dash 3.3 studs in 14 f · backdash 3.2 studs in 18 f · sidestep arc 1.9 studs · preferred range 4.4.

| key | name | input | height | i / act / rec | block / hit | dmg | reach + adv | flags | archetype | animation intent |
|---|---|---|---|---|---|---|---|---|---|---|
| Jab | Range Jab | 1 | High | 10 / 2 / 12 | +1 / +8 | 5 | 3.95 + 0.25 |  | straight | Long lead jab from a bladed kickboxing stance: lead foot slides forward, arm fully extends at head height, rear glove at the cheek, quick return. |
| JabKick | Jab Into Teep | 1,3 | Mid | 14 / 3 / 18 | -7 / +3 | 11 | 3.75 + 1.35 | string after Jab | teep | As the jab retracts, the lead knee lifts and the ball of the foot pushes straight into the stomach (teep); hips thrust forward, upper body leans back, arms stay high. |
| Cross | Snapping Cross | 2 | High | 11 / 2 / 14 | -3 / +5 | 9 | 3.8 + 0.8 |  | straight | Rear cross to the head: rear heel turns out, hips rotate, arm extends straight, lead hand drops to cover the chin, snaps back to the bladed guard. |
| Teep | Long Teep | 3 | Mid | 13 / 3 / 17 | -5 / +3 | 11 | 3.8 + 1.4 |  | teep | Lead-leg push kick at full length: knee chambers high, hips drive the sole of the foot into the belly, supporting foot rises onto the ball, arms hold a high guard. |
| TeepKick | Teep Into High Kick | 3,4 | High | 16 / 3 / 20 | -9 / +4 | 12 | 5.2 + 0.3 | string after Teep, tracking | roundhouse | The teep foot lands forward and the rear leg immediately whips a roundhouse to the head; full hip rotation, rear arm swings down, kick turns over at head height. |
| HighRoundhouse | Head Roundhouse | 4 | High | 14 / 3 / 20 | -8 / +5 | 13 | 4.5 + 0.9 | tracking | roundhouse | Rear-leg roundhouse to the head (Muay Thai style): lead foot pivots on the ball, hips turn over completely, shin swings in a flat arc at head height, rear arm swings back. |
| DoubleRoundhouse | Double Roundhouse | 4,4 | Mid | 16 / 3 / 24 | -12 / KND | 12 | 4.35 + 0.85 | string after HighRoundhouse, tracking | roundhouse | Without planting, the same rear leg chambers again and fires a second roundhouse to the ribs; supporting leg hops slightly to re-balance, arms counter-swing. |
| SpinningBackKick | Spinning Back Kick | b+4 | Mid | 17 / 3 / 22 | -8 / KND | 17 | 4.25 + 1.15 |  | spinning_back_kick | Turn the back to the opponent (head looks over the shoulder), rear leg chambers and thrusts straight back heel-first into the stomach, then the body completes the turn back to stance. |
| KneeStrike | Driving Knee | f+3 | Mid | 14 / 3 / 17 | -5 / +5 | 13 | 2.8 + 1.6 |  | knee | Step in and drive the lead knee up into the body: hands reach forward as if pulling the opponent in, hips push forward, supporting heel lifts. |
| SwitchKick | Switch Lift Kick | df+3 | Mid | 15 / 3 / 22 | -13 / LAUNCH | 13 | 2.8 + 1.4 |  | rising_kick | Quick stance switch (feet swap with a small hop), then the lead leg kicks straight up under the chin like a vertical front kick, toes pointing up, body leans back. |
| LegKick | Calf Kick | d+4 | Low | 13 / 2 / 21 | -13 / +1 | 8 | 4.0 |  | low_kick | Fast rear-leg calf kick: small hip turn, shin chops down onto the opponent's lead calf just below the knee, foot returns quickly, guard stays high. |
| LowSweep | Ground Sweep | db+4 | Low | 20 / 4 / 26 | -18 / KND | 15 | 4.0 + 0.6 | crouching | sweep | Drop low onto the lead knee and hands, rear leg sweeps in a wide arc along the floor at ankle height, body spins with it and rises back to stance. |
| DuckJab | Crouch Jab | d+1 | Mid* | 11 / 2 / 14 | -4 / +4 | 5 | 3.8 | special mid, crouching | straight | Short lead jab from a crouch, aimed at the stomach: knees stay bent, lead arm extends level, rear glove covers the face, stays crouched after. |
| HopCross | Hop Cross | f+2 | High | 17 / 3 / 18 | -6 / +6 | 15 | 3.7 + 2.1 | low crush f6-15 | superman_punch | Fake a rear knee, push off it and hop forward, throwing the rear cross in mid-air while the leg kicks back for balance; lands on the lead foot (feet leave the floor = low crush). |
| AngleKick | Angle Kick | ss+3 | Mid | 15 / 3 / 18 | -8 / +4 | 12 | 3.25 + 1.75 | homing | roundhouse | From a sidestep, a lead-leg roundhouse to the ribs that turns with the opponent; pivot on the rear foot, kick arcs horizontally at waist height. |
| Throw | Clinch Knees | 1+3 | Throw | 12 / 2 / 34 | break 1 ≤f20, impact f34 of 48 | 17 | 3.2 |  | clinch_knees | Double collar tie (both hands behind the head), pull down, two alternating knees to the chest, then twist and dump the opponent to the floor. |
| ThrowB | Clinch Trip | 2+4 | Throw | 12 / 2 / 34 | break 2 ≤f20, impact f30 of 46 | 18 | 3.2 |  | arm_toss | Underhook the arm, step across and sweep the opponent's lead leg with the rear leg while turning the shoulders; the opponent spins and lands on their back. |

### GORAN — Heavyweight grappling / armored pressure (grappler stance)

Stance: wide low base, knees deep, hands open and forward at chest height, heavy slow sway. Stats: health 120 · walk 4.3 / back 3.5 studs/s · dash 2.6 studs in 15 f · backdash 2.6 studs in 19 f · sidestep arc 1.5 studs · preferred range 3.2.

| key | name | input | height | i / act / rec | block / hit | dmg | reach + adv | flags | archetype | animation intent |
|---|---|---|---|---|---|---|---|---|---|---|
| Jab | Heavy Jab | 1 | High | 10 / 2 / 13 | +1 / +7 | 7 | 4.4 |  | straight | Heavy, short lead jab from a wide grappling stance with open-ish fist: shoulder pushes the punch, little footwork, the big torso leans in. |
| JabHammer | Jab Into Hammer | 1,2 | Mid | 15 / 3 / 19 | -9 / +3 | 12 | 4.0 + 0.2 | string after Jab | hammer_fist | After the jab, the rear fist rises above the head and clubs straight down onto the collarbone (hammer fist); knees bend as the blow lands. |
| Hammer | Hammer Fist | 2 | Mid | 14 / 3 / 18 | -5 / +4 | 13 | 4.0 + 0.2 |  | hammer_fist | Rear arm swings up and over like an axe and the bottom of the fist smashes down onto the shoulder/chest; whole body drops with the strike. |
| DoubleHammer | Double Hammer | 2,2 | Mid | 17 / 3 / 24 | -13 / KND | 14 | 4.0 + 0.3 | string after Hammer | hammer_fist | The lead arm follows with a second overhead hammer fist, both shoulders driving down, a step forward into it that flattens the opponent. |
| ShoulderTackle | Shoulder Charge | f+2 | Mid | 18 / 4 / 20 | -10 / KND | 18 | 2.8 + 2.2 | armor f6-17 | shoulder_tackle | Lowers the lead shoulder, tucks the chin and charges two steps forward, ramming the shoulder into the chest; absorbs one hit while charging (armor). |
| Uppercut | Lifting Uppercut | df+2 | Mid | 16 / 3 / 24 | -15 / LAUNCH | 15 | 3.9 + 0.2 | high crush f1-8 | uppercut | Squat down, then a huge rear uppercut lifts from the floor to above the head, legs and hips extending, lifting the opponent off their feet. |
| KneeLift | Knee Lift | f+3 | Mid | 14 / 3 / 18 | -5 / +5 | 13 | 2.8 + 1.2 |  | knee | Both hands reach out to grab, then the lead knee drives up into the stomach as the hands pull down; heavy forward step. |
| PushKick | Boot Push | 3 | Mid | 14 / 3 / 18 | -4 / +3 | 12 | 3.8 + 1.2 |  | teep | Big flat-footed lead push kick with the boot sole into the belly, upper body leaning back, arms out wide for balance. |
| ClubKick | Club Kick | 4 | Mid | 16 / 3 / 20 | -8 / +3 | 14 | 4.8 + 0.2 | tracking | roundhouse | Heavy rear-leg body kick thrown like a club: less snap, more weight, hips turn over slowly and the shin lands on the ribs. |
| Stomp | Knee Stomp | d+3 | Low | 14 / 3 / 20 | -12 / +1 | 9 | 3.8 + 0.3 |  | stomp | Lifts the lead knee and stamps the boot down and forward onto the opponent's lead knee/shin; arms stay forward. |
| CrouchJab | Low Poke | d+1 | Mid* | 12 / 2 / 15 | -5 / +3 | 6 | 3.6 | special mid, crouching | straight | From a squat, a short stiff lead punch to the stomach; stays crouched, other hand forward. |
| LegHook | Leg Hook Sweep | d+4 | Low | 21 / 4 / 24 | -17 / KND | 16 | 3.8 + 0.5 | crouching | sweep | Drops onto the lead knee and hooks the rear leg around the opponent's ankles, reaping them off their feet; heavy body rotation. |
| Haymaker | Wide Haymaker | b+2 | High | 18 / 3 / 19 | -9 / +5 | 17 | 3.95 + 0.55 | homing | hook | Huge looping rear hook to the head, wound up from behind the hip; the arc sweeps wide and follows a sidestepping opponent (homing). |
| Bulldozer | Bulldozer | f,f+2 | Mid | 20 / 4 / 22 | -12 / KND | 22 | 2.8 + 3.0 | armor f4-19 | shoulder_tackle | Out of a dash, a running double-handed shove/shoulder ram: three heavy running steps, arms forward, absorbs a hit (armor), and bowls the opponent over. |
| Throw | Bear Hug Toss | 1+3 | Throw | 12 / 2 / 34 | break 1 ≤f20, impact f36 of 50 | 18 | 3.2 |  | bear_hug_toss | Wraps both arms around the opponent's waist, lifts them off the floor with a hip thrust, turns and tosses them face-up in front of him. |
| ThrowB | Belly Suplex | 2+4 | Throw | 12 / 2 / 34 | break 2 ≤f20, impact f38 of 52 | 20 | 3.2 |  | slam | Front body lock, steps in deep, lifts belly to belly, slams forward onto the back. |
| RamSlam | Ram Slam | f+1+3 | Throw | 15 / 2 / 36 | break 1 ≤f14, impact f42 of 58 | 26 | 3.2 |  | slam | Command grab: lunges forward, scoops the opponent onto his shoulder and drops forward, slamming them flat into the floor (shorter break window). |

### LUMI — Acrobatic freerunning (flow stance)

Stance: loose low stance, constant side-to-side sway with relaxed arms, springy knees. Stats: health 90 · walk 5.7 / back 4.6 studs/s · dash 3.5 studs in 13 f · backdash 3.4 studs in 17 f · sidestep arc 2.1 studs · preferred range 4.2.

| key | name | input | height | i / act / rec | block / hit | dmg | reach + adv | flags | archetype | animation intent |
|---|---|---|---|---|---|---|---|---|---|---|
| Palm | Quick Palm | 1 | High | 10 / 2 / 12 | +1 / +8 | 5 | 3.95 + 0.25 |  | palm | Loose lead palm strike to the face from a bouncy low stance: wrist bent back, heel of the palm snaps forward and back, knees springy. |
| PalmHeel | Palm To Spin Heel | 1,4 | Mid | 15 / 3 / 22 | -10 / +3 | 12 | 3.5 + 1.4 | string after Palm, tracking | spin_kick | After the palm, she spins a full turn on the lead foot and the rear heel swings around into the ribs (spinning heel kick), arms flung out for momentum. |
| SpinBackfist | Spin Backfist | 2 | High | 12 / 3 / 16 | -5 / +5 | 10 | 3.75 + 0.85 | tracking | spinning_backfist | Quick spin on the lead foot, back turned for a moment, rear arm whips around and the back of the fist hits the side of the head at the end of the turn. |
| SnapKick | Snap Kick | 3 | Mid | 12 / 3 / 15 | -4 / +4 | 9 | 3.8 + 1.0 |  | front_kick | Fast lead front snap kick to the stomach: knee up, shin snaps out and back like a whip, she bounces on the supporting foot. |
| SnapCrescent | Snap Into Crescent | 3,4 | High | 15 / 3 / 20 | -9 / +4 | 11 | 3.75 + 1.45 | string after SnapKick, tracking | crescent_kick | The snap kick lands and the rear leg swings a straight-legged outside-to-inside crescent across the head, sweeping arc, arms counter-balance. |
| CrescentKick | Crescent Kick | 4 | High | 14 / 3 / 19 | -7 / +4 | 12 | 3.6 + 1.6 | tracking | crescent_kick | Rear-leg crescent kick: straight leg lifts and swings across the face in a wide arc, hips open then close, foot lands back in stance. |
| CartwheelKick | Cartwheel Kick | b+3 | Mid | 18 / 4 / 20 | -9 / KND | 15 | 3.7 + 1.5 | high crush f4-16 | cartwheel_kick | Hands go to the floor in a sideways cartwheel (head drops low = high crush) and the lead leg comes over the top into the chest; lands back on her feet. |
| FlipKick | Backflip Kick | df+4 | Mid | 16 / 3 / 26 | -15 / LAUNCH | 13 | 3.1 + 0.9 | low crush f6-15 | flip_kick | Standing backflip: the rear foot kicks up under the chin as she flips backwards, feet leave the floor (low crush), lands crouched slightly behind her start. |
| SlideKick | Slide Kick | d+4 | Low | 18 / 4 / 24 | -16 / KND | 13 | 3.4 + 1.8 | crouching, high crush f5-20 | slide_kick | Baseball slide: drops onto the hip and slides feet-first along the floor into the opponent's ankles, rear leg extended, then pops back up. |
| QuickLow | Flick Low | d+3 | Low | 12 / 2 / 18 | -11 / +2 | 7 | 4.0 | crouching | low_kick | From a squat, the lead foot flicks out along the floor into the shin and snaps back; hands near the floor for balance. |
| ScissorKick | Scissor Hop Kick | f+4 | High | 16 / 3 / 20 | -9 / KND | 14 | 3.5 + 1.7 | low crush f5-14 | jumping_kick | Jumps off both feet, legs scissor in the air and the rear foot kicks forward at head height; lands on the kicking foot. |
| VaultKick | Vault Kick | f,f+3 | Mid | 14 / 3 / 18 | -6 / +4 | 14 | 4.1 + 1.5 | low crush f3-12 | jumping_kick | Out of a run, she vaults off the rear foot into a flying lead front kick to the chest, body almost horizontal, lands in stance. |
| TwirlKick | Twirl Kick | ss+4 | High | 15 / 3 / 20 | -9 / +4 | 13 | 3.35 + 1.65 | homing | tornado_kick | From a sidestep, a 360-degree turning kick: she spins on the lead foot and the rear leg sweeps a flat circle at head height that tracks the opponent. |
| KneeRush | Running Knee | f+3 | Mid | 13 / 3 / 17 | -4 / +6 | 12 | 2.8 + 1.6 |  | knee | Two quick running steps and a jumping lead knee to the body, arms pumping back, lands on the knee leg. |
| Throw | Flip Toss | 1+3 | Throw | 12 / 2 / 34 | break 1 ≤f20, impact f32 of 46 | 16 | 3.2 |  | flip_toss | Grabs the opponent's shoulders, springs up and backflips off the opponent's belly, the kick-off drives them onto their back. |
| ThrowB | Vault Takedown | 2+4 | Throw | 12 / 2 / 34 | break 2 ≤f20, impact f30 of 46 | 17 | 3.2 |  | arm_toss | Hooks the neck from the side, springs up and stamps the lead knee; her weight folds them backwards. |

### RHYS — Karate-based counter striking (karate stance)

Stance: long front stance, lead hand extended forward at chest height, rear fist chambered near the ribs, very still. Stats: health 100 · walk 4.8 / back 4.2 studs/s · dash 3.0 studs in 14 f · backdash 3.1 studs in 18 f · sidestep arc 1.9 studs · preferred range 4.0.

| key | name | input | height | i / act / rec | block / hit | dmg | reach + adv | flags | archetype | animation intent |
|---|---|---|---|---|---|---|---|---|---|---|
| Jab | Lead Strike | 1 | High | 10 / 2 / 12 | +1 / +8 | 6 | 4.2 |  | straight | Karate lead punch (kizami-style) from a long front stance: the lead foot slides in, the fist twists palm-down at impact, the rear fist stays chambered at the ribs. |
| ReversePunch | Lead Into Reverse | 1,2 | Mid | 12 / 3 / 17 | -6 / +4 | 11 | 4.4 + 0.2 | string after Jab | straight | The lead hand pulls back to the hip while the rear reverse punch drives to the solar plexus: hips snap square, rear heel planted, fist twists at full extension. |
| StraightPunch | Center Punch | 2 | Mid | 12 / 3 / 16 | -4 / +5 | 11 | 3.8 + 0.8 |  | straight | Rear reverse punch to the chest from stance (gyaku-zuki): hip rotation first, lead hand chambers back, very straight line, short sharp exhale posture. |
| PunchKick | Punch Into High Kick | 2,4 | High | 16 / 3 / 21 | -9 / +5 | 13 | 4.65 + 0.55 | string after StraightPunch, tracking | roundhouse | After the center punch, the rear leg fires a snapping roundhouse to the head (mawashi-geri): knee chambers sideways, the instep snaps to the temple, snaps back. |
| FrontSnap | Front Snap Kick | 3 | Mid | 12 / 3 / 16 | -3 / +4 | 10 | 3.8 + 1.0 |  | front_kick | Lead front snap kick (mae-geri) with the ball of the foot to the stomach: knee lifts high first, shin snaps out, recoils before landing. |
| AxeKick | Falling Axe Kick | 4 | Mid | 19 / 3 / 18 | -2 / KND | 16 | 3.25 + 1.65 |  | axe_kick | Rear leg swings straight up above head height and the heel chops down onto the collarbone; body stays upright, arms open for balance. |
| Deflect | Deflect | b+1 | Mid | 3 / 10 / 22 | +0 / +0 | 0 | 2.6 | parry f4-13 | parry | Inside-to-outside sweeping block (uke) with the lead forearm while stepping slightly back; on contact the attacker's arm/leg is knocked aside and they stagger. |
| RisingKnee | Rising Knee | df+3 | Mid | 15 / 3 / 22 | -13 / LAUNCH | 13 | 2.8 + 1.1 |  | knee | From a slight crouch the lead knee drives straight up under the chin with a small jump, both hands pulling down, lifting the opponent. |
| LowSweep | Low Reaping Sweep | db+4 | Low | 19 / 4 / 24 | -16 / KND | 14 | 3.9 + 0.5 | crouching | sweep | Drops low on the lead leg, rear leg reaps along the floor in a wide arc at the ankles (ashi-barai style), comes back up in stance. |
| LowKick | Low Kick | d+4 | Low | 13 / 2 / 20 | -13 / +1 | 8 | 4.0 |  | low_kick | Short rear-leg low kick to the inside of the knee: quick hip turn, shin chops down, returns to stance immediately. |
| LowPunch | Kneeling Punch | d+1 | Mid* | 11 / 2 / 14 | -4 / +4 | 5 | 3.8 | special mid, crouching | straight | Drops into a low stance and throws a short straight lead punch to the stomach; stays low afterward. |
| SpinBackfist | Turning Backfist | b+2 | High | 15 / 3 / 18 | -8 / +4 | 13 | 4.15 + 0.45 | homing | spinning_backfist | Steps across and turns his back, the rear backfist whips around in a flat circle to the side of the head, turning with a sidestepping opponent (homing). |
| LungePunch | Lunging Punch | f+2 | Mid | 16 / 3 / 20 | -8 / +5 | 16 | 3.65 + 1.95 |  | straight | Long gliding step forward (oi-zuki) covering distance, rear-hand punch to the chest at the end of the slide, body low and straight. |
| SideKick | Side Thrust Kick | f+3 | Mid | 14 / 3 / 18 | -6 / +3 | 14 | 3.85 + 1.45 |  | side_kick | Turns sideways, lead knee chambers across the body and the heel thrusts out sideways into the ribs (yoko-geri), body leaning away. |
| CrescentStep | Stepping Crescent | ss+4 | Mid | 15 / 3 / 19 | -7 / +4 | 13 | 4.25 + 0.55 | tracking | crescent_kick | From a sidestep, a stepping crescent kick to the ribs: rear leg swings in a wide inward arc at waist height, catching an opponent moving to the side. |
| Throw | Hip Throw | 1+3 | Throw | 12 / 2 / 34 | break 1 ≤f20, impact f32 of 46 | 18 | 3.2 |  | hip_toss | Grips the sleeve and collar, steps in and takes them down with an outer reap of the lead leg. |
| ThrowB | Shoulder Throw | 2+4 | Throw | 12 / 2 / 34 | break 2 ≤f20, impact f32 of 48 | 19 | 3.2 |  | arm_toss | Arm trap and leg-block takedown, kneeling at the end. |

### NIA — Kung-fu-inspired whirlwind (kungfu stance)

Stance: low wide stance, lead open palm forward, rear palm guarding the chest, slow circular hand flow. Stats: health 95 · walk 5.2 / back 4.3 studs/s · dash 3.2 studs in 14 f · backdash 3.2 studs in 18 f · sidestep arc 2.0 studs · preferred range 3.8.

| key | name | input | height | i / act / rec | block / hit | dmg | reach + adv | flags | archetype | animation intent |
|---|---|---|---|---|---|---|---|---|---|---|
| Chop | Knife Hand | 1 | High | 10 / 2 / 12 | +1 / +8 | 5 | 3.55 + 0.65 |  | chop | Lead knife-hand strike to the neck: open hand, fingers together, wrist turns as the hand cuts forward and slightly down, rear palm guards the chest. |
| DoubleChop | Twin Knife Hand | 1,1 | High | 10 / 2 / 13 | +0 / +7 | 6 | 3.75 + 0.55 | string after Chop | chop | The rear hand follows with a second knife-hand from the other side as the lead hand circles back, flowing figure-eight arm motion. |
| FlurryKick | Flurry Finisher | 1,1,4 | Mid | 15 / 3 / 22 | -12 / KND | 12 | 4.2 + 0.9 | string after DoubleChop, tracking | roundhouse | The hand flurry flows into a turning rear roundhouse to the body; she pivots on the lead foot, arms circle outward as the kick lands. |
| PalmThrust | Palm Thrust | 2 | Mid | 12 / 3 / 16 | -4 / +5 | 11 | 3.4 + 1.0 |  | palm | Rear palm thrust to the chest from a low horse-like stance: the hips sink and turn, the heel of the palm pushes forward, the lead hand withdraws to the waist. |
| PalmKick | Palm Into Rising Snap Kick | 2,3 | Mid | 14 / 3 / 19 | -8 / +3 | 11 | 3.8 + 1.0 | string after PalmThrust | front_kick | The palm withdraws, weight shifts onto the rear leg and the lead foot snaps a front kick into the stomach, then the hands return to a guard as the foot lands back in the low stance. |
| RisingFrontKick | Rising Front Kick | 3 | Mid | 12 / 3 / 15 | -3 / +4 | 9 | 3.6 + 1.2 |  | front_kick | Lead front kick rising from the low stance: knee up, toes pointed, snaps to the stomach and back, rear palm forward. |
| HighKick | Whip Kick | 4 | High | 13 / 3 / 18 | -7 / +5 | 12 | 4.55 + 0.65 | tracking | roundhouse | Whipping rear roundhouse to the head, light and fast: the knee leads, the lower leg whips at the end, arms circle for balance. |
| LowSpin | Low Spin Kick | d+3 | Low | 13 / 2 / 18 | -11 / +2 | 8 | 4.0 | crouching | low_kick | Sinks into a low crouch and the lead leg sweeps a short quick arc into the shin, hands near the floor, stays crouched. |
| RisingTornado | Rising Whirlwind | d+3,4 | Mid | 22 / 3 / 24 | -15 / LAUNCH | 12 | 3.1 + 1.5 | string after LowSpin | rising_kick | From the low spin she rises while turning, the rear leg kicks upward in a spiral under the chin, body corkscrews up onto the toes (the gap before it can be blocked). |
| RisingPalm | Rising Palm Uppercut | df+2 | Mid | 15 / 3 / 22 | -14 / LAUNCH | 13 | 3.2 + 0.9 | high crush f1-7 | uppercut | From a crouch, the rear palm drives straight up under the chin while the legs extend, lead hand pulls down, she rises onto the toes. |
| ButterflyKick | Butterfly Kick | f+4 | Mid | 18 / 4 / 22 | -10 / KND | 16 | 3.85 + 1.15 | low crush f6-16 | butterfly_kick | Torso drops horizontal and she spins in the air with both legs scissoring outward (butterfly kick), the rear leg striking the chest; feet leave the floor (low crush). |
| Backfist | Snapping Backfist | b+2 | High | 12 / 3 / 15 | -3 / +6 | 9 | 3.0 + 1.6 | tracking | backfist | Short snapping backfist with the rear hand across the body to the temple, elbow leads, wrist flicks, quick recoil. |
| LowSweep | Floor Sweep | db+4 | Low | 19 / 4 / 24 | -16 / KND | 14 | 3.9 + 0.5 | crouching | sweep | Drops into a full crouch on one leg and spins a full circle with the other leg sweeping flat along the floor (front sweep), hands on the floor. |
| Elbow | Stepping Elbow | f+1 | Mid | 13 / 3 / 15 | -3 / +6 | 12 | 2.8 + 1.2 |  | elbow | Stomping step forward with a lead elbow driven horizontally into the chest, rear palm pushing the elbow (supported elbow), low stance. |
| TornadoKick | Cyclone Kick | ss+4 | High | 16 / 3 / 22 | -9 / KND | 15 | 3.75 + 1.35 | homing | tornado_kick | From a sidestep, a jumping 360-degree spinning kick: she turns her back, jumps, and the rear leg whips a flat circle at head height that follows the opponent. |
| Throw | Spinning Arm Toss | 1+3 | Throw | 12 / 2 / 34 | break 1 ≤f20, impact f32 of 46 | 17 | 3.2 |  | arm_toss | Catches the opponent's wrist for an arm wheel: draws the wrist down, circles it up and cuts it back over the shoulder, and they fall onto their back. |
| ThrowB | Twisting Hip Toss | 2+4 | Throw | 12 / 2 / 34 | break 2 ≤f20, impact f32 of 46 | 18 | 3.2 |  | hip_toss | Palms on the opponent's chest and hip, she sinks, twists her whole body and uproots them, tossing them in a spiral onto the floor. |

Removed keys since OV5: Kael `FlickerJab`, Kael `StepHook`. Renamed: Nia `DragonUppercut` → `RisingPalm`, Nia `CraneKick` → `RisingFrontKick`, Sierra `SupermanPunch` → `HopCross` (`Roster.renamedKeys`). New keys: Kael `CrossHook`, `LegKick`, `ThrowB`; Sierra `TeepKick`, `ThrowB`; Goran `JabHammer`, `DoubleHammer`, `ThrowB`; Lumi `SnapCrescent`, `ThrowB`; Rhys `PunchKick`, `LowKick`, `ThrowB`; Nia `PalmKick`, `RisingPalm`, `RisingFrontKick`, `ThrowB`. Inputs changed for several surviving keys (see table); presentation should key on the move key, never on the input.
