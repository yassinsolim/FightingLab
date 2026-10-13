# movesets.md — round 6: six distinct movesets, signature mechanics, combos, Surge and the Ultimate

Owner: combat (`r6-combat`). Source of truth: `ReplicatedStorage.FightingLab.Roster` (every key, input, frame data,
animation hint, stance, Ultimate timeline and combo route below is generated from it by
`OV6\work\r6-combat\harness\gen_movesets.luau`). Rules: `RF.CombatSim`. Frames are 60 Hz sim frames.

**Stability (Contract B).** From M1 on, move keys, stance keys/tags and the Ultimate impact frames stay stable. Any
later change is listed in a commit-message line `KEYS: ...` and in the change log at the end of this file.
Presentation keys on the move KEY (never on the input or name). Existing keys keep their clips; new keys have none
yet and animate through the procedural fallback (`anim.archetype`, always one of the existing Strikes / Kicks /
Throws archetypes, so nothing errors); the `intent` text is what the clip should show.

## 1. What changed (the user's request: "each character have different movesets and combos, and at low hp an ult")

- 16-17 template moves per fighter → **23-26 moves**: three 3-hit strings with different enders per fighter, two
  launchers each (a standard one plus a unique one: from the stance or on counter hit), a **tumble** juggle extender,
  a signature mechanic on **3+4**, and the **Ultimate** on **1+2**.
- **Template sameness** (for every input two fighters share, the two moves have the same animation archetype, height,
  hit result, counter-hit result and special property; throws, 1+2 and 3+4 are excluded as universal inputs):
  **33 of 113 shared inputs (29.2 %) → 6 of 118 (5.1 %)**; the 6 left are the universal 10-frame jab on 1 (Kael,
  Sierra, Goran, Rhys). Without the property columns (archetype + height + hit result only): 33/113 → 22/118.
  Test: `CombatCombo_Test` "fighters do not share the same kind of move on the same input" (prints `[SAMENESS]`).
- Inputs that used to be the same template move everywhere now differ: df+2 is only Kael's uppercut (Goran's moved to
  d+2, Nia's palm to db+2), db+4 is only Sierra's sweep (Rhys's moved to b+4, Nia's into her Coil), d+1 is a crouch
  jab only for Sierra and Rhys (Goran's poke moved to db+1, Rhys's cancels into Still Water), Sierra's 2 is now a
  Muay Thai elbow (her cross moved to b+2), 3 / 4 / f+3 carry a different property per fighter.

## 2. Systems (sim rules every fighter shares)

### 2.1 Signature on 3+4 (stances and the catch)

3+4 (J+K together, or 3 then 4 within 2 frames; slower 3,4 stays a string) is every fighter's signature button:

| fighter | signature | kind |
|---|---|---|
| Kael | **Pocket** (`PKT`) | stance: low bob-and-roll crouch, crushes highs the whole time, +1 body shovel, uppercut launcher |
| Sierra | **Southpaw** (`SPW`) | stance: switches the lead leg, guards highs and mids while held, long head kick, power body kick, low kick |
| Goran | **Bear Trap** | catch move: a high or mid strike that touches him on frames 4-24 is caught into an unbreakable Belly Suplex |
| Lumi | **Aerial** (`AER`) | committed stance: a forward no-hands cartwheel, airborne over lows, kicks out of it |
| Rhys | **Still Water** (`STW`) | stance: parries every high or mid strike that touches him while held |
| Nia | **Coil** (`COIL`) | stance: a wound-up stance; COIL+4,4,4 is a three-kick whirl with delayable 2nd and 3rd hits |

Stance rules (sim):
- Entering: press 3+4 (the entry key, e.g. `Pocket`, is a move with `toStance` and no hitbox), or press 3+4 during the
  recovery of a move marked `stanceCancel` (e.g. Kael 1,2 / 2 / d+2) to cancel the rest of its recovery into the stance.
- In the stance: state `"Stance"`, snapshot `stance` = the stance KEY (`"Pocket"`, `"Southpaw"`, `"Aerial"`,
  `"StillWater"`, `"Coil"`) and `stanceFrame` = 1, 2, 3, ... (frames since entry). `crush` / `guard` follow the stance's
  windows. A button pressed in the stance does the stance follow-up for that button (input `<TAG>+<button>`, optional
  `d`: `SPW+d+4`); a button without a follow-up does the normal move (leaving the stance). Presses before
  `cancelFrom` are buffered. 3+4 again leaves the stance.
- Leaving: holding back from `backExit` (into standing guard), the `maxFrames` timeout (into Idle), a follow-up, or
  being hit / blocking. There is no exit state: the next frame is Idle (blend with `exitIntent`).
- Hits taken in a stance with `counterHit = true` are counter hits (Southpaw guards instead). Stance follow-ups can
  also be started directly (the CPU and tests do), the stance only selects them.

### 2.2 Tumble (juggle extender)

A move with `tumble = true` that hits an AIRBORNE opponent spins the body over in the air ("tumble"): the body is
lifted again (`TumbleVelocity`, 12 studs/s up), the juggle's air-hit cap grows by one so exactly one more hit
connects, and the juggle ends face down. Once per combo (a second tumble hit in the same juggle is a normal air hit).
On the ground a tumble move is a normal hit. Snapshot: the airborne fighter has `tumble = true` from the tumble hit
until it lands; the `Hit` event carries `tumble = true`. One tumble move per fighter: Kael `RibRoller` (b+1), Sierra
`SouthpawBodyKick` (SPW+3), Goran `KneeLift` (f+3), Lumi `PalmHeel` (1,4), Rhys `SpinBackfist` (b+2), Nia
`RisingFrontKick` (3).

### 2.3 Parries, the catch, counter-hit launchers

- **Parry** (Rhys `Deflect` b+1 high/mid, `LowParry` db+1 lows, the `StillWater` stance high/mid): the attacker
  staggers (`stagger` frames) and the parrying fighter is FREE at once (its parry move or stance ends), so a parry is
  a real punish window (24-26 frames). Event `Parry` as before.
- **Catch** (Goran `BearTrap`): a high or mid strike touching him in the window is absorbed and he immediately starts
  the referenced throw (`ThrowB`, Belly Suplex) on the striker, unbreakable. Events: `Catch` (attacker = Goran,
  target = striker, move = "BearTrap"), then the normal `ThrowStart` / `ThrowHit` of `ThrowB`.
- **Counter-hit launchers** (`onCounter = "LAUNCH"`): Sierra `KneeStrike` (f+3), Goran `Haymaker` (b+2), Lumi
  `CartwheelKick` (b+3).

### 2.4 Damage scaling

- Air hits (unchanged): × 0.7 × 0.82^(air hits before this one).
- Ground combos (new): the 4th and later consecutive hits of a combo on the ground deal × 0.85 / 0.75 / 0.65 (min
  0.6); natural 3-hit strings are unscaled.
- Surge: × 1.1 for everything the Surging fighter deals (not in Free Training, where Surge is only there to try the
  Ultimate, so combo damage reads true).
- The Ultimate: × 0.7 when it lands on an opponent already in a combo or juggle (`UltComboScale`).

### 2.5 Surge and the Ultimate (CONTRACTS-v6.md, Surge and Ultimate)

- **Surge**: the first frame of a round a fighter's health is ≤ 25 % of its maximum (and above 0) it enters Surge
  (event `Surge`, snapshot `surge = true`). Surge lasts until the round ends or the fighter starts its Ultimate.
- **Ultimate** (key `"Ultimate"`, last in `moveOrder`, input 1+2; keyboard `L` or U+I together, gamepad RT): only in
  Surge, once per round (`ultUsed`). About i18-22, armored through its startup (absorbs every strike; throws beat it),
  -15 on block (launch punishable), Mid. Its first frame ends Surge and emits `UltStart`.
- **On hit** both fighters enter state `"Ultimate"` for `cinematic.duration` frames; the defender is placed
  `endDistance` studs in front of the attacker and both are locked (the round timer pauses). Damage lands at each
  impact (`share × damage × scaling`, event `UltHit` with `combo` = impact index and `knockdown = true` on the last).
  A KO is declared at the end of the cinematic. Then the defender lies in Landing with `knockdown = endKind`, the
  attacker is free. **On block or whiff**: the normal `Block` / `Whiff` with `move = "Ultimate"` and the recovery.
- Snapshot during the cinematic: both fighters carry the `throw` table `{ archetype = "ultimate", move = "Ultimate",
  role = "Attacker" | "Defender", frame = cinematic frame 1..duration, duration, impactFrame = first impact }`.
- **Free Training** (practice, dummy Stand or Guard): the player is always in Surge and the Ultimate is available
  again as soon as it ends. Versus CPU practice and real matches use the normal rule.

### 2.6 Juggles

Launch speed 19 studs/s up (was 16), juggle re-lift 9 (was 7.5), the air time limit 110 frames (was 86): a launcher
is followed by 3-4 air hits plus the tumble hit; the air-hit cap (5, +1 after a tumble) and the decaying air damage
keep every juggle at 5-7 hits and inside 45 % of the smallest health bar (`Balance_Test`).

### 2.7 Combos as data

Every `CharacterDef` lists `combos` (`Roster.get(id).combos`): `{ name, kind, notation, damage, difficulty, surge?,
counter?, steps = { { wait, input } } }`. `kind` is `launch` (bread and butter), `stance` (signature route), `counter`
(counter-hit opener), `low`, `max` (best damage) or `ultimate` (ends in the Ultimate, played in Surge). `steps[i].input`
is display notation (`"df+2"`, `"PKT+2"`, `"3+4"`, `"1+2"`); `steps[i].wait` = frames after the previous press,
counting only frames without hitstop (the first is 0). `CombatSim.comboRun / comboTick` play them; `CombatCombo_Test`
drives every combo against all six fighters and checks that every press connects as a true combo and the damage matches
(±1); the CPU uses the same routes. Damage targets: 30-45 % of a 100 HP bar (31-40 listed), Ultimate enders ≤ 55 %
of the smallest bar (35-44 listed).
## 3. Snapshot and event fields (codec v3, additive)

| field | where | meaning |
|---|---|---|
| `surge` | fighter (flag bit 32) | in Surge |
| `ultUsed` | fighter (flag bit 64) | the Ultimate was started this round |
| `tumble` | fighter (flag bit 128) | airborne after a tumble hit (spinning), until it lands |
| `stance`, `stanceFrame` | fighter | the stance key and frames since entry, while state = `"Stance"` |
| state `"Stance"`, `"Ultimate"` | fighter | new states (both locked: never extrapolate) |
| `throw` with `archetype = "ultimate"` | fighter | during the cinematic (see 2.5) |
| `Surge`, `UltStart`, `UltHit`, `Catch` | events | see 2.3 and 2.5; `Hit.tumble = true` (event flag bit 64) |

## 4. Notation

1 / 2 / 3 / 4 = left punch / right punch / left kick / right kick (U I J K). f / b / d / df / db = direction held
(D / A / S / S+D / S+A). `1,2` = press in sequence (a string). `1+2` = together. `f,f+2` = out of a forward dash.
`ss+4` = during a sidestep. `PKT+1` = 1 while in Pocket (stance tags: PKT, SPW, AER, STW, COIL). `CH` = counter hit.
Frame data: `i` = impact frame (first active frame); block / hit = advantage of the attacker after the move.


## 5. Movesets (generated from `RF.Roster`)

Columns: key (stable id clips bind to; **new** = new this round, *input* = its input changed this round) · name · notation · height · i / act / rec · block / hit (CH = counter hit) · damage · reach + root advance · properties · fallback archetype · **animation intent**.

### 5.1 KAEL — Street boxing / pressure (23 moves)

**Identity:** Relentless boxer: fast hands, body hooks and +1 pressure from the Pocket, where high punches sail over him.

**Signature — Pocket (stance):** 3+4: a low bob-and-roll crouch. Highs sail over him the whole time; PKT+1 is a +1 body shovel, PKT+2 an uppercut launcher. Cancel 1,2 / 2 / d+2 into it; hold back to leave.

Stance `Pocket` (tag `PKT`, snapshot `stance = "Pocket"`): entry 6 f, follow-ups from stanceFrame 6, hold back from frame 8 to leave, ends on its own at frame 40, creeps forward 0.025 studs/frame; high crush f1-40, hits in it are counter hits.

- Entry: Knees bend fast and the head drops forward-down under the line of a high punch (6 frames).
- Loop: Pocket loop: a low, coiled boxer's crouch with the head moving in a small side-to-side bob-and-roll (U-shape), chin behind the lead shoulder, gloves at the cheeks, elbows on the ribs; he creeps forward a little (0.025 studs/frame). Crushes highs the whole time; no guard (hits are counter hits).
- Exit: Rises back into the upright boxing guard (back to Idle).

| key | name | notation | height | i / act / rec | block / hit | dmg | reach + adv | properties | archetype | animation intent |
|---|---|---|---|---|---|---|---|---|---|---|
| Jab | Jab | 1 | High | 10 / 2 / 12 | +1 / +8 | 6 | 4.2 |  | straight | Lead-hand jab from a tight high boxing guard: small step of the lead foot, lead shoulder rolls over the chin, fist snaps straight to head height and back to the cheek; rear hand stays glued to the jaw. |
| OneTwo | One-Two | 1,2 | High | 10 / 2 / 14 | -2 / +6 | 8 | 3.95 + 0.65 | string after Jab, cancel into Pocket (3+4) | straight | Rear straight right thrown as the jab returns: rear heel pivots out, hips and shoulders rotate fully, fist extends to head height, weight finishes over the lead knee. |
| LiverHook | Lead Liver Hook | 1,2,1 | Mid | 14 / 3 / 20 | -9 / +3 | 12 | 3.9 + 0.3 | string after OneTwo, tracking | body_hook | Short lead hook to the opponent's right side (liver): level change by bending both knees, lead elbow bent ninety degrees, torso whips from the hips, fist lands at rib height. |
| OneTwoShin **new** | One-Two Shin Kick | 1,2,3 | Low | 15 / 2 / 21 | -13 / +1 | 9 | 3.95 + 0.3 | string after OneTwo | low_kick | Low ender of the one-two: as the right straight returns, the boxer drops his weight a little and snaps a lead-leg toe kick into the shin, foot skimming the floor, both gloves stay high at the chin; the kick returns straight to stance (same base as 1,2,1: mid hook or low kick). |
| Cross | Straight Right | 2 | High | 11 / 2 / 14 | -3 / +5 | 9 | 3.6 + 1.0 | cancel into Pocket (3+4) | straight | Rear straight right from the guard without the jab: rear foot pivots, hip and shoulder drive through, fist extends at chin height, lead hand covers the face. |
| CrossHook | Right Into Body Hook | 2,1 | Mid | 13 / 3 / 18 | -8 / +3 | 11 | 3.9 + 0.2 | string after Cross, tracking | body_hook | After the straight right, the boxer dips slightly and rips a lead hook to the body: weight shifts onto the lead leg, lead hip turns in, forearm horizontal at stomach height. |
| HookOverhand **new** | Body Hook Into Overhand | 2,1,2 | High | 16 / 3 / 22 | -11 / KND | 14 | 3.7 + 0.5 | string after CrossHook | overhand | High ender of 2,1: out of the body hook the boxer rises and loops the right hand over the top onto the temple, rear heel lifts, shoulders roll through and the punch drives down and across; the opponent spins to the floor (knockdown). Body-then-head: the hook lowers the guard, the overhand finishes high. |
| Overhand | Overhand Right | f+2 | High | 16 / 3 / 18 | -5 / +6 (CH KND) | 15 | 3.6 + 1.4 |  | overhand | Looping overhand right: step in with the lead foot, rear arm arcs up and over the shoulder and comes down onto the head, upper body rolls forward and down to the left, rear heel lifts. |
| BodyBlow | Crouching Body Shot | d+2 | Mid | 14 / 3 / 17 | -6 / +4 | 12 | 3.8 + 0.3 | cancel into Pocket (3+4), crouching | body_hook | From a deep crouch, rear shovel punch to the stomach: knees stay bent, rear shoulder dips, fist travels forward and slightly upward into the body, chin tucked behind the lead glove. |
| RisingUppercut | Rising Uppercut | df+2 | Mid | 15 / 3 / 22 | -14 / LAUNCH | 14 | 3.9 + 0.3 | high crush f1-7 | uppercut | Rear uppercut rising from a crouch: legs explode upward, hips drive up and forward, rear fist travels vertically from waist to above the head, body ends fully extended on the toes. |
| WeaveHook | Weaving Hook | b+2 | High | 17 / 3 / 19 | -9 / +4 | 15 | 3.7 + 0.7 | homing, high crush f4-14 | weave_hook | Upper body weaves down and under (U-shaped bob) then comes up with a wide lead hook to the head; the hook sweeps horizontally and turns with the opponent (homing), head stays low until the punch fires. |
| RibRoller **new** | Rib Roller | b+1 | Mid | 13 / 3 / 18 | -6 / +3 | 11 | 3.6 + 0.5 | TUMBLE, tracking | body_hook | Short stepping lead hook to the floating ribs: a half step back-and-in with the lead foot, knees bend, the lead elbow tucks to ninety degrees and the hook rolls UP and through the ribs, torso turning hard from the hips. TUMBLE: on an airborne opponent the upward roll of the hook spins the body over in the air (one more juggle hit connects). |
| ShinKick | Shin Kick | d+3 | Low | 12 / 2 / 20 | -12 / +1 | 7 | 4.0 | crouching | low_kick | Quick lead-leg toe kick to the shin from a half crouch: knee lifts slightly, foot snaps out low along the floor and returns, hands stay in the guard. |
| LegKick | Low Roundhouse | d+4 | Low | 19 / 3 / 24 | -17 / KND | 14 | 3.8 + 0.6 |  | low_kick | Heavy rear-leg roundhouse to the thigh/calf: step out with the lead foot, hips turn over, shin swings down through the opponent's leg at knee height, arms swing for balance. |
| FrontKick | Push Kick | 3 | Mid | 13 / 3 / 17 | -6 / +3 | 10 | 3.9 + 1.1 |  | front_kick | Lead-leg push kick to the stomach: knee chambers to the chest, hips push forward, sole of the foot extends straight out, torso leans back slightly, foot returns to stance. |
| Roundhouse | Street Roundhouse | 4 | High | 15 / 3 / 20 | -8 / +5 | 13 | 4.4 + 0.8 | tracking | roundhouse | Rear-leg roundhouse to the head: lead foot pivots, hips rotate fully, shin whips around horizontally at head height, rear arm swings down for counterbalance. |
| ChargingCross | Charging Straight | f,f+2 | Mid | 16 / 3 / 22 | -10 / KND | 17 | 3.6 + 2.2 |  | straight | Out of a forward dash, a lunging rear straight to the chest: big step forward, whole body travels behind the punch, rear leg drags, the boxer ends stretched forward. |
| Pocket **new** | Pocket | 3+4 | Mid | 6 / 1 / 1 | +0 / +0 | 0 | 2.6 | enters Pocket, no hitbox | parry | SIGNATURE stance entry (no strike): the boxer bends both knees and drops his head below an imaginary high punch, chin tucked behind the lead shoulder, gloves glued to the cheeks, elbows covering the ribs; he settles into the Pocket (see the stance: a low bob-and-roll crouch). |
| PocketShovel **new** | Pocket Shovel | PKT+1 | Mid | 12 / 3 / 15 | +1 / +7 | 11 | 3.5 + 0.6 | from Pocket, tracking | body_hook | From the Pocket crouch, a lead shovel hook (half hook, half uppercut) into the liver: the lead knee drives, the elbow stays tucked under the fist, the fist travels forward and slightly up into the side of the stomach while he stays low; he rises back into his guard. Plus on block: the pressure tool. |
| PocketUppercut **new** | Pocket Uppercut | PKT+2 | Mid | 14 / 3 / 24 | -14 / LAUNCH | 13 | 3.6 + 0.5 | from Pocket | uppercut | Out of the lowest point of the Pocket bob, the rear uppercut springs straight up: both legs extend explosively, the rear fist travels vertically from knee height through the chin to above the head, the body finishes tall on the toes; lifts the opponent into a juggle (launcher, very unsafe on block). |
| Throw | Clinch Headbutt | 1+3 | Throw | 12 / 2 / 34 | break 1 ≤f20, impact f30 of 46 | 18 | 3.2 |  | clinch_strike | Both hands grab the back of the opponent's neck (collar tie), pull the head down, two short knees to the body, then shove them away so they fall on their back. |
| ThrowB | Over-Under Toss | 2+4 | Throw | 12 / 2 / 34 | break 2 ≤f20, impact f32 of 48 | 19 | 3.2 |  | hip_toss | Over-under body lock: rear arm under the opponent's armpit, lead arm over the shoulder, then a hip lift and dump in front onto their back. |
| Ultimate **new** | Final Bell | 1+2 | Mid | 18 / 3 / 30 | -15 / KND | 32 | 3.6 + 1.2 | armor (all hits) f1-17 | straight | ULTIMATE (Surge only, once per round) 'Final Bell': an armored lunging right straight opens it; on hit the cinematic plays the beats listed in movesets.md (shovel, body hook, uppercut, straight, then the overhand that drops the opponent face-down). |

**Ultimate — "Final Bell"** (key `Ultimate`, 1+2): i18, active 3, recovery 30, -15 on block, armor (all strikes) on frames 1-17, damage 32, reach 3.6 + 1.2. Cinematic: 200 frames (3.3 s), 5 impacts, ends FaceDown 4.4 studs in front of KAEL.

| impact | cinematic frame | share | damage (base) |
|---|---|---|---|
| 1 | 30 | 0.10 | 3.2 |
| 2 | 62 | 0.14 | 4.5 |
| 3 | 94 | 0.16 | 5.1 |
| 4 | 128 | 0.20 | 6.4 |
| 5 | 176 | 0.40 | 12.8 |

Beats (what attacker and defender do; impact poses land on the impact frames):

- f0 (the hit): an armored, lunging right straight to the sternum; the opponent folds forward and Kael steps in chest to chest, dipping into the Pocket.
- f30 impact 1: lead shovel hook to the liver; the defender doubles over to its right side, elbows drop.
- f62 impact 2: rear hook to the other side of the body; the defender's knees buckle and its hands fall from its face.
- f94 impact 3: lead uppercut through the guard; the defender's chin snaps up, torso straightens and it staggers half a step back.
- f128 impact 4: right straight to the jaw; the defender's head turns and it spins a quarter turn away, arms limp.
- f150-175: Kael plants, loads the overhand right high behind his ear (the camera holds on him).
- f176 impact 5 (the final bell): the overhand right comes over the top onto the temple and drives the defender face-first into the floor (FaceDown, 4.4 studs in front); Kael ends standing over it, gloves up, breathing.

Combos (`Roster.get("Kael").combos`, verified against all six opponents by `CombatCombo_Test`):

| combo | kind | notation | presses (frames after the previous press, hitstop not counted) | damage | difficulty |
|---|---|---|---|---|---|
| Uppercut Bread | launch | `df+2, 1, b+1, 2,1` | df+2 · +32 1 · +23 b+1 · +33 2 · +8 1 | 32 | 2/5 |
| Pocket Launch | stance | `3+4, PKT+2, 1, b+1, 2,1` | 3+4 · +1 PKT+2 · +38 1 · +23 b+1 · +33 2 · +8 1 | 31 | 3/5 |
| Counter Uppercut | max (CH opener) | `CH df+2, 1, b+1, 2,1` | df+2 · +32 1 · +23 b+1 · +33 2 · +8 1 | 36 | 3/5 |
| Final Bell Finish | ultimate | `df+2, 1+2` | df+2 · +32 1+2 | 37 (in Surge) | 2/5 |

New keys (7): OneTwoShin, HookOverhand, RibRoller, Pocket, PocketShovel, PocketUppercut, Ultimate.

### 5.2 SIERRA — Kickboxing / range control (26 moves)

**Identity:** Range kickboxer: teeps and long kicks keep you out, elbows punish you inside, and Southpaw switches every angle.

**Signature — Southpaw (stance):** 3+4: switch the lead leg. Southpaw guards highs and mids while held; SPW+4 fast long head kick, SPW+3 power body kick (tumbles in juggles), SPW+d+4 low kick. Cancel 3 / 1,3 into it; 3+4 again or back to switch back.

Stance `Southpaw` (tag `SPW`, snapshot `stance = "Southpaw"`): entry 5 f, follow-ups from stanceFrame 5, hold back from frame 8 to leave, ends on its own at frame 90; guards Stand, no counter hits.

- Entry: Quick hop-switch of the feet (5 frames): right leg forward, guard mirrored.
- Loop: Southpaw loop: the mirrored kickboxing stance, right foot and right glove forward, light rhythmic bounce, standing guard up (blocks highs and mids). Stationary (no walking in it).
- Exit: Hop-switch back to the orthodox stance (left leg forward).

| key | name | notation | height | i / act / rec | block / hit | dmg | reach + adv | properties | archetype | animation intent |
|---|---|---|---|---|---|---|---|---|---|---|
| Jab | Range Jab | 1 | High | 10 / 2 / 12 | +1 / +8 | 5 | 3.95 + 0.25 |  | straight | Long lead jab from a bladed kickboxing stance: lead foot slides forward, arm fully extends at head height, rear glove at the cheek, quick return. |
| JabKick | Jab Into Teep | 1,3 | Mid | 14 / 3 / 18 | -7 / +3 | 11 | 3.75 + 1.35 | string after Jab, cancel into Southpaw (3+4) | teep | As the jab retracts, the lead knee lifts and the ball of the foot pushes straight into the stomach (teep); hips thrust forward, upper body leans back, arms stay high. |
| JabTeepHigh **new** | Jab Teep Head Kick | 1,3,4 | High | 16 / 3 / 21 | -9 / +5 | 13 | 4.6 + 0.4 | string after JabKick, tracking | roundhouse | High ender of 1,3: the teep foot lands forward and the rear leg whips a full roundhouse to the side of the head, hips turning over, rear arm swinging down for balance; she lands back in the bladed stance. |
| JabTeepLow **new** | Jab Teep Calf Kick | 1,3,3 | Low | 15 / 2 / 20 | -12 / +2 | 9 | 4.0 | string after JabKick | low_kick | Low ender of 1,3: the teep leg never touches down; it re-chambers and chops an inside low kick into the opponent's lead calf, shin turned over, hands high (same base as the head kick: high or low). |
| SlashElbow **new** | Slashing Elbow | 2 | High | 12 / 2 / 15 | -3 / +5 | 11 | 3.2 + 0.6 |  | elbow | Muay Thai slashing elbow: a short step in, the rear elbow lifts to shoulder height and slices diagonally down and across the opponent's brow, forearm horizontal, lead glove covering the chin; the body turns behind it and she resets the guard. |
| Cross *input* | Counter Cross | b+2 | High | 11 / 2 / 14 | -3 / +5 | 9 | 3.8 + 0.8 |  | straight | Counter cross (the weight rocks back first, then the punch): rear heel turns out, hips rotate, arm extends straight to the head, lead hand drops to cover the chin, snaps back to the bladed guard. |
| Teep | Long Teep | 3 | Mid | 13 / 3 / 17 | -5 / +3 | 11 | 3.8 + 1.4 | cancel into Southpaw (3+4) | teep | Lead-leg push kick at full length: knee chambers high, hips drive the sole of the foot into the belly, supporting foot rises onto the ball, arms hold a high guard. |
| TeepKick | Teep Into High Kick | 3,4 | High | 16 / 3 / 20 | -9 / +4 | 12 | 5.2 + 0.3 | string after Teep, tracking | roundhouse | The teep foot lands forward and the rear leg immediately whips a roundhouse to the head; full hip rotation, rear arm swings down, kick turns over at head height. |
| TeepSpinKick **new** | Teep Kick Spin | 3,4,4 | Mid | 18 / 3 / 24 | -13 / KND | 15 | 4.2 + 0.8 | string after TeepKick | spinning_back_kick | Mid ender of 3,4: the head kick's momentum carries her around; she lets the rear leg land, keeps turning her back to the opponent (head looking over the shoulder) and drives a spinning back kick heel-first into the stomach (knockdown). |
| HighRoundhouse | Head Roundhouse | 4 | High | 14 / 3 / 20 | -8 / +5 (CH KND) | 13 | 4.5 + 0.9 | tracking | roundhouse | Rear-leg roundhouse to the head (Muay Thai style): lead foot pivots on the ball, hips turn over completely, shin swings in a flat arc at head height, rear arm swings back. |
| DoubleRoundhouse | Double Roundhouse | 4,4 | Mid | 16 / 3 / 24 | -12 / KND | 12 | 4.35 + 0.85 | string after HighRoundhouse, tracking | roundhouse | Without planting, the same rear leg chambers again and fires a second roundhouse to the ribs; supporting leg hops slightly to re-balance, arms counter-swing. |
| SpinningBackKick | Spinning Back Kick | b+4 | Mid | 17 / 3 / 22 | -8 / KND | 17 | 4.25 + 1.15 |  | spinning_back_kick | Turn the back to the opponent (head looks over the shoulder), rear leg chambers and thrusts straight back heel-first into the stomach, then the body completes the turn back to stance. |
| KneeStrike | Driving Knee | f+3 | Mid | 14 / 3 / 17 | -5 / +5 (CH LAUNCH) | 13 | 2.8 + 1.6 |  | knee | Step in and drive the lead knee up into the body: hands reach forward as if pulling the opponent in, hips push forward, supporting heel lifts. |
| SwitchKick | Switch Lift Kick | df+3 | Mid | 15 / 3 / 22 | -13 / LAUNCH | 13 | 2.8 + 1.4 |  | rising_kick | Quick stance switch (feet swap with a small hop), then the lead leg kicks straight up under the chin like a vertical front kick, toes pointing up, body leans back. |
| LegKick | Calf Kick | d+4 | Low | 13 / 2 / 21 | -13 / +1 | 8 | 4.0 |  | low_kick | Fast rear-leg calf kick: small hip turn, shin chops down onto the opponent's lead calf just below the knee, foot returns quickly, guard stays high. |
| LowSweep | Ground Sweep | db+4 | Low | 20 / 4 / 26 | -18 / KND | 15 | 4.0 + 0.6 | crouching | sweep | Drop low onto the lead knee and hands, rear leg sweeps in a wide arc along the floor at ankle height, body spins with it and rises back to stance. |
| DuckJab | Crouch Jab | d+1 | Mid* | 11 / 2 / 14 | -4 / +4 | 5 | 3.8 | special mid, crouching | straight | Short lead jab from a crouch, aimed at the stomach: knees stay bent, lead arm extends level, rear glove covers the face, stays crouched after. |
| HopCross | Hop Cross | f+2 | High | 17 / 3 / 18 | -6 / +6 | 15 | 3.7 + 2.1 | low crush f6-15 | superman_punch | Fake a rear knee, push off it and hop forward, throwing the rear cross in mid-air while the leg kicks back for balance; lands on the lead foot (feet leave the floor = low crush). |
| AngleKick | Angle Kick | ss+3 | Mid | 15 / 3 / 18 | -8 / +4 | 12 | 3.25 + 1.75 | homing | roundhouse | From a sidestep, a lead-leg roundhouse to the ribs that turns with the opponent; pivot on the rear foot, kick arcs horizontally at waist height. |
| Southpaw **new** | Southpaw | 3+4 | Mid | 5 / 1 / 1 | +0 / +0 | 0 | 2.6 | enters Southpaw, no hitbox | parry | SIGNATURE stance entry (no strike): a small hop-switch of the feet (the right leg becomes the lead leg, the left the rear), the guard mirrors (right glove forward), she lands light on the balls of the feet in a mirrored, bladed kickboxing stance (see the stance). |
| SouthpawHeadKick **new** | Southpaw Head Kick | SPW+4 | High | 13 / 3 / 19 | -7 / +6 | 13 | 4.6 + 0.5 | from Southpaw, tracking | roundhouse | From Southpaw the RIGHT leg is the lead: a fast lead-leg round kick to the head with almost no chamber, the hip flicks over, the foot snaps to the temple and back; long reach, quick return to the southpaw guard. |
| SouthpawBodyKick **new** | Southpaw Body Kick | SPW+3 | Mid | 13 / 3 / 20 | -8 / +4 | 13 | 4.0 + 0.6 | from Southpaw, TUMBLE, tracking | roundhouse | From Southpaw the LEFT leg is the rear (power) leg: a full rear roundhouse into the liver, the right foot pivots, hips turn over completely and the shin lands flat on the ribs, left arm swings down. TUMBLE: on an airborne opponent the shin rolls the body over in the air. |
| SouthpawLowKick **new** | Southpaw Low Kick | SPW+d+4 | Low | 14 / 2 / 20 | -12 / +2 | 9 | 4.0 | from Southpaw | low_kick | From Southpaw (holding down), the right (now lead) leg chops a short low kick into the inside of the opponent's lead knee; hands stay high, she stays upright and bladed. |
| Throw | Clinch Knees | 1+3 | Throw | 12 / 2 / 34 | break 1 ≤f20, impact f34 of 48 | 17 | 3.2 |  | clinch_knees | Double collar tie (both hands behind the head), pull down, two alternating knees to the chest, then twist and dump the opponent to the floor. |
| ThrowB | Clinch Trip | 2+4 | Throw | 12 / 2 / 34 | break 2 ≤f20, impact f30 of 46 | 18 | 3.2 |  | arm_toss | Underhook the arm, step across and sweep the opponent's lead leg with the rear leg while turning the shoulders; the opponent spins and lands on their back. |
| Ultimate **new** | Eight Limbs | 1+2 | Mid | 20 / 3 / 28 | -15 / KND | 33 | 4.0 + 1.0 | armor (all hits) f1-19 | teep | ULTIMATE (Surge only, once per round) 'Eight Limbs': an armored long teep opens it; on hit the cinematic plays the beats in movesets.md (body kick, clinch knees, elbow, switch head kick). |

**Ultimate — "Eight Limbs"** (key `Ultimate`, 1+2): i20, active 3, recovery 28, -15 on block, armor (all strikes) on frames 1-19, damage 33, reach 4.0 + 1.0. Cinematic: 230 frames (3.8 s), 5 impacts, ends FaceUp 4.6 studs in front of SIERRA.

| impact | cinematic frame | share | damage (base) |
|---|---|---|---|
| 1 | 34 | 0.10 | 3.3 |
| 2 | 70 | 0.12 | 4.0 |
| 3 | 104 | 0.14 | 4.6 |
| 4 | 140 | 0.16 | 5.3 |
| 5 | 196 | 0.48 | 15.8 |

Beats (what attacker and defender do; impact poses land on the impact frames):

- f0 (the hit): an armored long teep into the stomach folds the opponent; Sierra steps in behind it.
- f34 impact 1: lead (left) body kick into the liver; the defender bends sideways toward the kick.
- f70 impact 2: she clinches (both hands behind the defender's head) and drives a rising knee into its chest; the defender's head is pulled down onto the knee.
- f104 impact 3: the second knee, to the chin; the defender's head snaps back up.
- f140 impact 4: she releases the clinch with a slashing horizontal elbow across the brow; the defender staggers back, turning away.
- f150-195: two quick steps back to kicking range, a hop-switch of the feet (Southpaw) and a breath.
- f196 impact 5: a full-power switch head kick; the defender is spun off its feet and lands on its back (FaceUp, 4.6 studs away). Sierra finishes in her bladed guard.

Combos (`Roster.get("Sierra").combos`, verified against all six opponents by `CombatCombo_Test`):

| combo | kind | notation | presses (frames after the previous press, hitstop not counted) | damage | difficulty |
|---|---|---|---|---|---|
| Switch Teep | launch | `df+3, 3, 3+4, SPW+3, 1,3` | df+3 · +32 3 · +15 3+4 · +8 SPW+3 · +32 1 · +8 3 | 34 | 4/5 |
| Counter Knee | counter (CH opener) | `CH f+3, 1,3,4` | f+3 · +26 1 · +8 3 · +11 4 | 32 | 2/5 |
| Knee To Southpaw | max (CH opener) | `CH f+3, 1,3, 3+4, SPW+3, 2` | f+3 · +26 1 · +8 3 · +19 3+4 · +8 SPW+3 · +32 2 | 36 | 4/5 |
| Eight Limbs Finish | ultimate | `df+3, 1+2` | df+3 · +32 1+2 | 37 (in Surge) | 2/5 |

New keys (9): JabTeepHigh, JabTeepLow, SlashElbow, TeepSpinKick, Southpaw, SouthpawHeadKick, SouthpawBodyKick, SouthpawLowKick, Ultimate.

### 5.3 GORAN — Heavyweight grappling / armored pressure (23 moves)

**Identity:** Armored heavyweight: walks through punches, catches strikes in the Bear Trap and turns every touch into a slam.

**Signature — Bear Trap (catch):** 3+4: open arms for frames 4-24. A high or mid strike that touches him is caught into an unbreakable Belly Suplex. Lows and throws beat it; very punishable on whiff. Plus armored power moves (3, f+2, f,f+2, 3,2,2) and the f+1+3 command grab.

| key | name | notation | height | i / act / rec | block / hit | dmg | reach + adv | properties | archetype | animation intent |
|---|---|---|---|---|---|---|---|---|---|---|
| Jab | Heavy Jab | 1 | High | 10 / 2 / 13 | +1 / +7 | 7 | 4.4 |  | straight | Heavy, short lead jab from a wide grappling stance with open-ish fist: shoulder pushes the punch, little footwork, the big torso leans in. |
| JabHammer | Jab Into Hammer | 1,2 | Mid | 15 / 3 / 19 | -9 / +3 | 12 | 4.0 + 0.2 | string after Jab | hammer_fist | After the jab, the rear fist rises above the head and clubs straight down onto the collarbone (hammer fist); knees bend as the blow lands. |
| JabHammerForearm **new** | Jab Hammer Forearm | 1,2,1 | High | 16 / 3 / 22 | -10 / KND | 13 | 3.6 + 0.5 | string after JabHammer, tracking | elbow | High ender of 1,2: from the hammer fist he steps through with the lead foot and swings the lead forearm horizontally into the side of the head (clubbing forearm smash, elbow bent ninety degrees, the whole torso turning behind it); the opponent is knocked down. |
| JabHammerStomp **new** | Jab Hammer Stomp | 1,2,3 | Low | 16 / 3 / 22 | -13 / +1 | 11 | 3.8 + 0.4 | string after JabHammer | stomp | Low ender of 1,2: after the hammer fist he lifts the lead knee high and stamps the boot heel down onto the opponent's lead foot and shin, arms still forward, whole body weight dropping onto it (same base as the forearm: high or low). |
| Hammer | Hammer Fist | 2 | Mid | 14 / 3 / 18 | -5 / +4 | 13 | 4.0 + 0.2 |  | hammer_fist | Rear arm swings up and over like an axe and the bottom of the fist smashes down onto the shoulder/chest; whole body drops with the strike. |
| DoubleHammer | Double Hammer | 2,2 | Mid | 17 / 3 / 24 | -13 / KND | 14 | 4.0 + 0.3 | string after Hammer | hammer_fist | The lead arm follows with a second overhead hammer fist, both shoulders driving down, a step forward into it that flattens the opponent. |
| ShoulderTackle | Shoulder Charge | f+2 | Mid | 18 / 4 / 20 | -10 / KND | 18 | 2.8 + 2.2 | armor f6-17 | shoulder_tackle | Lowers the lead shoulder, tucks the chin and charges two steps forward, ramming the shoulder into the chest; absorbs one hit while charging (armor). |
| Uppercut *input* | Lifting Uppercut | d+2 | Mid | 16 / 3 / 24 | -15 / LAUNCH | 15 | 3.9 + 0.2 | high crush f1-8 | uppercut | Squat down, then a huge rear uppercut lifts from the floor to above the head, legs and hips extending, lifting the opponent off their feet. |
| KneeLift | Knee Lift | f+3 | Mid | 14 / 3 / 18 | -5 / +5 | 13 | 2.8 + 1.2 | TUMBLE | knee | Both hands reach out to grab, then the lead knee drives up into the stomach as the hands pull down; heavy forward step. TUMBLE: on an airborne opponent the knee drives up under the body and flips it over in the air. |
| PushKick | Boot Push | 3 | Mid | 14 / 3 / 18 | -6 / +3 | 12 | 3.8 + 1.2 | armor f4-13 | teep | Big flat-footed lead push kick with the boot sole into the belly, upper body leaning back, arms out wide for balance. Armored chamber: the raised knee absorbs one strike. |
| BootForearm **new** | Boot Push Forearm | 3,2 | High | 15 / 3 / 18 | -7 / +4 | 12 | 3.6 + 0.6 | string after PushKick | elbow | The push-kick foot lands forward and he swings the rear forearm across into the side of the head (forearm smash, elbow high and bent), shoulders turning heavily behind it. |
| BootForearmHammer **new** | Boot Forearm Hammer | 3,2,2 | Mid | 20 / 3 / 24 | -14 / KND | 17 | 3.8 + 0.4 | string after BootForearm, armor f4-19 | hammer_fist | Mid ender of 3,2: both fists lock together and rise high above his head (armored windup, he absorbs a hit while raising them), then the double-fisted club crashes down onto the collarbone and drives the opponent to the floor (knockdown). |
| ClubKick | Club Kick | 4 | Mid | 16 / 3 / 20 | -8 / +3 | 14 | 4.8 + 0.2 | tracking | roundhouse | Heavy rear-leg body kick thrown like a club: less snap, more weight, hips turn over slowly and the shin lands on the ribs. |
| Stomp | Knee Stomp | d+3 | Low | 14 / 3 / 20 | -12 / +1 | 9 | 3.8 + 0.3 |  | stomp | Lifts the lead knee and stamps the boot down and forward onto the opponent's lead knee/shin; arms stay forward. |
| CrouchJab *input* | Low Poke | db+1 | Mid* | 12 / 2 / 15 | -5 / +3 | 6 | 3.6 | special mid, crouching | straight | From a squat, a short stiff lead punch to the stomach; stays crouched, other hand forward. |
| LegHook | Leg Hook Sweep | d+4 | Low | 21 / 4 / 24 | -17 / KND | 16 | 3.8 + 0.5 | crouching | sweep | Drops onto the lead knee and hooks the rear leg around the opponent's ankles, reaping them off their feet; heavy body rotation. |
| Haymaker | Wide Haymaker | b+2 | High | 18 / 3 / 19 | -9 / +5 (CH LAUNCH) | 17 | 3.95 + 0.55 | homing | hook | Huge looping rear hook to the head, wound up from behind the hip; the arc sweeps wide and follows a sidestepping opponent (homing). On a counter hit it lifts the opponent off its feet (counter-hit launcher). |
| Bulldozer | Bulldozer | f,f+2 | Mid | 20 / 4 / 22 | -12 / KND | 22 | 2.8 + 3.0 | armor f4-19 | shoulder_tackle | Out of a dash, a running double-handed shove/shoulder ram: three heavy running steps, arms forward, absorbs a hit (armor), and bowls the opponent over. |
| BearTrap **new** | Bear Trap | 3+4 | Mid | 4 / 21 / 26 | +0 / +0 | 0 | 2.6 | catch f4-24 High/Mid into ThrowB, no hitbox | parry | SIGNATURE catch (no strike): he sinks his hips and opens both arms wide at chest height, palms forward, chin down, inviting the hit (frames 4-24). A high or mid strike that touches him is caught: his arms clamp around the striking arm or leg and the body, and he goes straight into the Belly Suplex (ThrowB, unbreakable). Lows and throws beat it; a whiffed trap leaves him open for a long time. |
| Throw | Bear Hug Toss | 1+3 | Throw | 12 / 2 / 34 | break 1 ≤f20, impact f36 of 50 | 18 | 3.2 |  | bear_hug_toss | Wraps both arms around the opponent's waist, lifts them off the floor with a hip thrust, turns and tosses them face-up in front of him. |
| ThrowB | Belly Suplex | 2+4 | Throw | 12 / 2 / 34 | break 2 ≤f20, impact f38 of 52 | 20 | 3.2 |  | slam | Front body lock, steps in deep, lifts belly to belly, slams forward onto the back. |
| RamSlam | Ram Slam | f+1+3 | Throw | 15 / 2 / 36 | break 1 ≤f14, impact f42 of 58 | 26 | 3.2 |  | slam | Command grab: lunges forward, scoops the opponent onto his shoulder and drops forward, slamming them flat into the floor (shorter break window). |
| Ultimate **new** | Landslide | 1+2 | Mid | 22 / 4 / 28 | -15 / KND | 36 | 3.0 + 1.4 | armor (all hits) f1-21 | shoulder_tackle | ULTIMATE (Surge only, once per round) 'Landslide': an armored charging shoulder opens it; on hit the cinematic plays the beats in movesets.md (body-lock crush, suplex, knee slam, carry and forward drop). |

**Ultimate — "Landslide"** (key `Ultimate`, 1+2): i22, active 4, recovery 28, -15 on block, armor (all strikes) on frames 1-21, damage 36, reach 3.0 + 1.4. Cinematic: 240 frames (4.0 s), 4 impacts, ends FaceUp 4.6 studs in front of GORAN.

| impact | cinematic frame | share | damage (base) |
|---|---|---|---|
| 1 | 40 | 0.12 | 4.3 |
| 2 | 92 | 0.18 | 6.5 |
| 3 | 150 | 0.25 | 9.0 |
| 4 | 214 | 0.45 | 16.2 |

Beats (what attacker and defender do; impact poses land on the impact frames):

- f0 (the hit): an armored charging shoulder pins the opponent; Goran wraps both arms around its waist (body lock).
- f40 impact 1: he crushes the body lock and shakes the defender; its back arches, arms flail over his shoulders, feet leave the floor.
- f92 impact 2: belly-to-belly suplex: he arches back and throws the defender over his head; it lands on its upper back behind him while he rolls through and stands.
- f120-149: he drags the dazed defender up by the waist, its legs buckling.
- f150 impact 3: he lifts it across his chest and drops it onto his raised knee (body slam onto the thigh); the defender folds over the knee.
- f170-213: he heaves it onto his shoulder (carry), walks one heavy step forward.
- f214 impact 4: he falls forward with his whole weight and drives the defender flat onto its back (FaceUp, 4.6 studs in front); Goran rises slowly over it.

Combos (`Roster.get("Goran").combos`, verified against all six opponents by `CombatCombo_Test`):

| combo | kind | notation | presses (frames after the previous press, hitstop not counted) | damage | difficulty |
|---|---|---|---|---|---|
| Lift And Hammer | launch | `d+2, f+3, 1,2` | d+2 · +35 f+3 · +34 1 · +8 2 | 34 | 2/5 |
| Counter Haymaker | counter (CH opener) | `CH b+2, f+3, 1,2` | b+2 · +32 f+3 · +34 1 · +8 2 | 40 | 3/5 |
| Forearm Finish | max | `d+2, f+3, 1,2,1` | d+2 · +35 f+3 · +34 1 · +8 2 · +11 1 | 39 | 3/5 |
| Landslide Finish | ultimate | `d+2, 1+2` | d+2 · +35 1+2 | 42 (in Surge) | 2/5 |

New keys (6): JabHammerForearm, JabHammerStomp, BootForearm, BootForearmHammer, BearTrap, Ultimate.

### 5.4 LUMI — Acrobatic freerunning (24 moves)

**Identity:** Rooftop acrobat: hops over lows, flips through the air with the Aerial and comes down kicking from angles nobody guards.

**Signature — Aerial (stance):** 3+4: a forward no-hands cartwheel, airborne over lows from frame 3 to 18, traveling 2.2 studs. AER+3 split kick (tumbles in juggles), AER+4 rising heel launcher, AER+d+3 drop sweep; lands on its own at frame 26. Cancel d+3 into it.

Stance `Aerial` (tag `AER`, snapshot `stance = "Aerial"`): entry 4 f, follow-ups from stanceFrame 10, cannot be left by holding back, ends on its own at frame 26, travels 2.2 studs over frames 1-18; low crush f3-18, hits in it are counter hits.

- Entry: Step and dip into the cartwheel: arms swing down, the rear leg kicks up (frames 1-4).
- Loop: Aerial: a no-hands cartwheel, the body sideways and horizontal at the top of a wide arc, legs split in a V, arms out; the root travels 2.2 studs forward over frames 1-18 (ease-out) and she is airborne (low crush) on frames 3-18. Follow-ups come out of the second half (from frame 10).
- Exit: Lands on the lead foot, then the rear, and settles into her bouncy stance (frames 19-26).

| key | name | notation | height | i / act / rec | block / hit | dmg | reach + adv | properties | archetype | animation intent |
|---|---|---|---|---|---|---|---|---|---|---|
| Palm | Quick Palm | 1 | High | 10 / 2 / 12 | +1 / +8 | 5 | 3.95 + 0.25 |  | palm | Loose lead palm strike to the face from a bouncy low stance: wrist bent back, heel of the palm snaps forward and back, knees springy. |
| PalmHeel | Palm To Spin Heel | 1,4 | Mid | 15 / 3 / 22 | -10 / +3 | 12 | 3.5 + 1.4 | string after Palm, TUMBLE, tracking | spin_kick | After the palm, she spins a full turn on the lead foot and the rear heel swings around into the ribs (spinning heel kick), arms flung out for momentum. TUMBLE: on an airborne opponent the spinning heel flips the body over in the air (one more juggle hit connects). |
| PalmHeelHook **new** | Palm Heel Hook Kick | 1,4,4 | High | 16 / 3 / 22 | -12 / KND | 13 | 3.8 + 0.6 | string after PalmHeel, tracking | spin_kick | High ender of 1,4: the spinning heel lands and she keeps the spin going, hopping on the lead foot into a second full turn; the rear heel hooks around at head height (spinning hook kick) and knocks the opponent down. |
| PalmHeelSweep **new** | Palm Heel Sweep | 1,4,3 | Low | 16 / 3 / 22 | -13 / +1 | 10 | 3.9 + 0.4 | string after PalmHeel, crouching | sweep | Low ender of 1,4: out of the spinning heel she drops onto one hand and the lead leg sweeps a fast half circle along the floor at ankle height, then she springs back up (same base as the hook kick: high or low). |
| SpinBackfist | Spin Backfist | 2 | High | 12 / 3 / 16 | -5 / +5 | 10 | 3.75 + 0.85 | tracking | spinning_backfist | Quick spin on the lead foot, back turned for a moment, rear arm whips around and the back of the fist hits the side of the head at the end of the turn. |
| SnapKick | Snap Kick | 3 | Mid | 12 / 3 / 15 | -4 / +4 | 9 | 3.8 + 1.0 | low crush f3-9 | front_kick | Fast lead front snap kick to the stomach thrown off a small hop: both feet leave the floor for a moment (hops over lows), the knee comes up, the shin snaps out and back like a whip, she lands bouncing on the supporting foot. |
| SnapCrescent | Snap Into Crescent | 3,4 | High | 15 / 3 / 20 | -9 / +4 | 11 | 3.75 + 1.45 | string after SnapKick, tracking | crescent_kick | The snap kick lands and the rear leg swings a straight-legged outside-to-inside crescent across the head, sweeping arc, arms counter-balance. |
| CrescentFlyingKick **new** | Crescent Flying Kick | 3,4,4 | Mid | 18 / 3 / 24 | -13 / KND | 14 | 3.9 + 0.8 | string after SnapCrescent, low crush f6-17 | jumping_kick | Mid ender of 3,4: the crescent leg lands and she jumps off it straight away, tucking the lead knee and shooting the rear leg out flat into the chest in mid-air (flying side kick, low crush while airborne), landing in a crouch; knockdown. |
| CrescentKick | Crescent Kick | 4 | High | 14 / 3 / 19 | -7 / +4 | 12 | 3.6 + 1.6 | tracking | crescent_kick | Rear-leg crescent kick: straight leg lifts and swings across the face in a wide arc, hips open then close, foot lands back in stance. |
| CartwheelKick | Cartwheel Kick | b+3 | Mid | 18 / 4 / 20 | -9 / KND (CH LAUNCH) | 15 | 3.7 + 1.5 | high crush f4-16 | cartwheel_kick | Hands go to the floor in a sideways cartwheel (head drops low = high crush) and the lead leg comes over the top into the chest; lands back on her feet. On a counter hit the heel scoops up under the chin and pops the opponent into the air (launch). |
| FlipKick | Backflip Kick | df+4 | Mid | 16 / 3 / 26 | -15 / LAUNCH | 13 | 3.1 + 0.9 | low crush f6-15 | flip_kick | Standing backflip: the rear foot kicks up under the chin as she flips backwards, feet leave the floor (low crush), lands crouched slightly behind her start. |
| SlideKick | Slide Kick | d+4 | Low | 18 / 4 / 24 | -16 / KND | 13 | 3.4 + 1.8 | crouching, high crush f5-20 | slide_kick | Baseball slide: drops onto the hip and slides feet-first along the floor into the opponent's ankles, rear leg extended, then pops back up. |
| QuickLow | Flick Low | d+3 | Low | 12 / 2 / 18 | -11 / +2 | 7 | 4.0 | cancel into Aerial (3+4), crouching | low_kick | From a squat, the lead foot flicks out along the floor into the shin and snaps back; hands near the floor for balance. |
| ScissorKick | Scissor Hop Kick | f+4 | High | 16 / 3 / 20 | -9 / KND | 14 | 3.5 + 1.7 | low crush f5-14 | jumping_kick | Jumps off both feet, legs scissor in the air and the rear foot kicks forward at head height; lands on the kicking foot. |
| VaultKick | Vault Kick | f,f+3 | Mid | 14 / 3 / 18 | -6 / +4 | 14 | 4.1 + 1.5 | low crush f3-12 | jumping_kick | Out of a run, she vaults off the rear foot into a flying lead front kick to the chest, body almost horizontal, lands in stance. |
| TwirlKick | Twirl Kick | ss+4 | High | 15 / 3 / 20 | -9 / +4 | 13 | 3.35 + 1.65 | homing | tornado_kick | From a sidestep, a 360-degree turning kick: she spins on the lead foot and the rear leg sweeps a flat circle at head height that tracks the opponent. |
| KneeRush | Running Knee | f+3 | Mid | 13 / 3 / 17 | -4 / +6 | 12 | 2.8 + 1.6 | low crush f5-13 | knee | Two quick running steps and a jumping lead knee to the body (both feet off the floor: hops over lows), arms pumping back, lands on the knee leg. |
| Aerial **new** | Aerial | 3+4 | Mid | 10 / 1 / 1 | +0 / +0 | 0 | 2.6 | enters Aerial, no hitbox | parry | SIGNATURE (no strike): a forward no-hands cartwheel (gymnastics aerial). She steps in, throws both arms down and swings the legs over in a wide arc, body sideways and horizontal at the top, traveling about 2.2 studs toward the opponent and landing on the lead foot (see the stance: she is airborne, over lows, from frame 3 to 18). |
| AerialSplit **new** | Aerial Split Kick | AER+3 | Mid | 12 / 3 / 18 | -8 / +4 | 12 | 3.6 + 0.4 | from Aerial, low crush f1-10 | jumping_kick | Out of the cartwheel, still in the air, she opens the legs into a split and snaps the lead foot into the chest (low crush while airborne), landing on the rear foot. |
| AerialHeel **new** | Aerial Rising Heel | AER+4 | Mid | 13 / 3 / 24 | -14 / LAUNCH | 12 | 3.4 + 0.4 | from Aerial, low crush f1-8 | rising_kick | She lands out of the cartwheel on the lead foot and the rear heel keeps the wheel's momentum, swinging straight up under the opponent's chin (rising heel kick) and lifting it into a juggle (launcher, very unsafe on block). |
| AerialSweep **new** | Aerial Drop Sweep | AER+d+3 | Low | 12 / 3 / 26 | -16 / KND | 13 | 3.9 | from Aerial, crouching | sweep | Holding down out of the cartwheel, she lands low on both hands and one knee and the lead leg sweeps a fast arc along the floor at ankle height (knockdown), then she springs back up. |
| Throw | Flip Toss | 1+3 | Throw | 12 / 2 / 34 | break 1 ≤f20, impact f32 of 46 | 16 | 3.2 |  | flip_toss | Grabs the opponent's shoulders, springs up and backflips off the opponent's belly, the kick-off drives them onto their back. |
| ThrowB | Vault Takedown | 2+4 | Throw | 12 / 2 / 34 | break 2 ≤f20, impact f30 of 46 | 17 | 3.2 |  | arm_toss | Hooks the neck from the side, springs up and stamps the lead knee; her weight folds them backwards. |
| Ultimate **new** | Skyline | 1+2 | Mid | 18 / 3 / 30 | -15 / KND | 30 | 3.9 + 1.2 | armor (all hits) f1-17 | jumping_kick | ULTIMATE (Surge only, once per round) 'Skyline': an armored running jump kick opens it; on hit the cinematic plays the beats in movesets.md (heel kick, cartwheel kick, wall-run flip off the chest, scissor kick, drop sweep, falling heel). |

**Ultimate — "Skyline"** (key `Ultimate`, 1+2): i18, active 3, recovery 30, -15 on block, armor (all strikes) on frames 1-17, damage 30, reach 3.9 + 1.2. Cinematic: 210 frames (3.5 s), 6 impacts, ends FaceDown 4.4 studs in front of LUMI.

| impact | cinematic frame | share | damage (base) |
|---|---|---|---|
| 1 | 28 | 0.10 | 3.0 |
| 2 | 56 | 0.10 | 3.0 |
| 3 | 86 | 0.12 | 3.6 |
| 4 | 118 | 0.14 | 4.2 |
| 5 | 150 | 0.18 | 5.4 |
| 6 | 192 | 0.36 | 10.8 |

Beats (what attacker and defender do; impact poses land on the impact frames):

- f0 (the hit): an armored running jump kick into the chest; the opponent rocks back and Lumi lands light in front of it.
- f28 impact 1: a spinning heel kick to the ribs; the defender bends sideways.
- f56 impact 2: a cartwheel kick over the top onto the defender's shoulder; it sinks to one knee.
- f86 impact 3: she runs up the defender's thigh and chest like a rooftop wall and kicks off its chest (back-flip off the body); the defender is knocked upright, arms wide.
- f118 impact 4: at the top of the flip, a scissor kick to the head; the defender's head whips sideways.
- f150 impact 5: she lands low and a fast drop sweep takes its legs; the defender floats up horizontally.
- f192 impact 6: she springs into a front flip and drives a falling heel down onto the floating defender, spiking it face-first into the floor (FaceDown, 4.4 studs in front); she lands crouched on one hand.

Combos (`Roster.get("Lumi").combos`, verified against all six opponents by `CombatCombo_Test`):

| combo | kind | notation | presses (frames after the previous press, hitstop not counted) | damage | difficulty |
|---|---|---|---|---|---|
| Flip And Spin | launch | `df+4, 2, 1,4, 4` | df+4 · +37 2 · +30 1 · +8 4 · +11 4 | 34 | 3/5 |
| Aerial Launch | stance | `3+4, AER+4, 2, 1,4, 4` | 3+4 · +1 AER+4 · +41 2 · +30 1 · +8 4 · +11 4 | 33 | 4/5 |
| Cartwheel Counter | counter (CH opener) | `CH b+3, 2, 1,4, 4` | b+3 · +34 2 · +30 1 · +8 4 · +11 4 | 40 | 3/5 |
| Crescent Flight | max | `df+4, 2, 3,4,4` | df+4 · +37 2 · +30 3 · +8 4 · +14 4 | 35 | 3/5 |
| Skyline Finish | ultimate | `df+4, 1+2` | df+4 · +37 1+2 | 35 (in Surge) | 2/5 |

New keys (8): PalmHeelHook, PalmHeelSweep, CrescentFlyingKick, Aerial, AerialSplit, AerialHeel, AerialSweep, Ultimate.

### 5.5 RHYS — Karate-based counter striking (25 moves)

**Identity:** Patient karateka: parries high, mid and low, waits in Still Water and answers every mistake with a straight line.

**Signature — Still Water (stance):** 3+4: a still counter stance. From frame 8 every high or mid strike that touches him is parried (26-frame stagger, he is free at once). Lows and throws beat it. STW+1 fast mid punch, STW+2 rising reverse punch launcher. Cancel d+1 / d+4 into it; hold back to leave. Plus parries on b+1 (high/mid) and db+1 (low).

Stance `StillWater` (tag `STW`, snapshot `stance = "StillWater"`): entry 8 f, follow-ups from stanceFrame 8, hold back from frame 10 to leave, ends on its own at frame 60; parry f8-60 (High/Mid, stagger 26), hits in it are counter hits.

- Entry: Lead foot slides back into a short back-weighted stance, lead open hand extends (8 frames).
- Loop: Still Water loop: a low, back-weighted karate stance (most weight on the rear leg, front foot light), lead open hand forward at chest height, rear fist at the hip, perfectly still except slow breathing. Any high or mid strike that touches him is parried (play the Deflect contact on the parry event). Lows hit him (counter hits).
- Exit: Brings the lead foot back under him and returns to the long front stance.

| key | name | notation | height | i / act / rec | block / hit | dmg | reach + adv | properties | archetype | animation intent |
|---|---|---|---|---|---|---|---|---|---|---|
| Jab | Lead Strike | 1 | High | 10 / 2 / 12 | +1 / +8 | 6 | 4.2 |  | straight | Karate lead punch (kizami-style) from a long front stance: the lead foot slides in, the fist twists palm-down at impact, the rear fist stays chambered at the ribs. |
| ReversePunch | Lead Into Reverse | 1,2 | Mid | 12 / 3 / 17 | -6 / +4 | 11 | 4.4 + 0.2 | string after Jab | straight | The lead hand pulls back to the hip while the rear reverse punch drives to the solar plexus: hips snap square, rear heel planted, fist twists at full extension. |
| ReverseHighKick **new** | Reverse Punch Head Kick | 1,2,4 | High | 16 / 3 / 21 | -9 / +5 | 13 | 4.6 + 0.5 | string after ReversePunch, tracking | roundhouse | High ender of 1,2: as the reverse punch retracts to the hip, the rear knee chambers sideways and the instep snaps to the temple (head roundhouse, mawashi-geri style), then snaps back into the front stance. |
| ReverseLowKick **new** | Reverse Punch Low Kick | 1,2,3 | Low | 15 / 2 / 20 | -12 / +2 | 9 | 3.9 + 0.3 | string after ReversePunch | front_kick | Low ender of 1,2: the lead knee lifts low and the sole of the foot thrusts down into the opponent's lead knee/shin (a low stopping kick), body upright, fists chambered; the foot returns to the front stance (same base as the head kick: high or low). |
| StraightPunch | Center Punch | 2 | Mid | 12 / 3 / 16 | -4 / +5 | 11 | 3.8 + 0.8 |  | straight | Rear reverse punch to the chest from stance (gyaku-zuki): hip rotation first, lead hand chambers back, very straight line, short sharp exhale posture. |
| PunchKick | Punch Into High Kick | 2,4 | High | 16 / 3 / 21 | -9 / +5 | 13 | 4.65 + 0.55 | string after StraightPunch, tracking | roundhouse | After the center punch, the rear leg fires a snapping roundhouse to the head (mawashi-geri): knee chambers sideways, the instep snaps to the temple, snaps back. |
| PunchKickAxe **new** | Punch Kick Axe | 2,4,4 | Mid | 19 / 3 / 22 | -12 / KND | 15 | 3.6 + 0.6 | string after PunchKick | axe_kick | Mid ender of 2,4: the head-kick leg does not land; it rises straight up above head height and the heel chops down onto the collarbone (falling axe kick), body upright, arms open; knockdown. |
| FrontSnap | Front Snap Kick | 3 | Mid | 12 / 3 / 16 | -3 / +4 (CH KND) | 10 | 3.8 + 1.0 |  | front_kick | Lead front snap kick (mae-geri) with the ball of the foot to the stomach: knee lifts high first, shin snaps out, recoils before landing. |
| AxeKick | Falling Axe Kick | 4 | Mid | 19 / 3 / 18 | -2 / KND | 16 | 3.25 + 1.65 |  | axe_kick | Rear leg swings straight up above head height and the heel chops down onto the collarbone; body stays upright, arms open for balance. |
| Deflect | Deflect | b+1 | Mid | 3 / 10 / 22 | +0 / +0 | 0 | 2.6 | parry f4-13 High/Mid, no hitbox | parry | Inside-to-outside sweeping block (uke) with the lead forearm while stepping slightly back; on contact the attacker's arm/leg is knocked aside and they stagger. |
| LowParry **new** | Low Deflect | db+1 | Mid | 3 / 10 / 20 | +0 / +0 | 0 | 2.6 | crouching, parry f3-12 Low, no hitbox | parry | Downward sweeping block: he sinks into a low front stance and the lead forearm sweeps down and out across the shin line (palm down), knocking the low kick aside; the attacker staggers. Parries lows only. |
| RisingKnee | Rising Knee | df+3 | Mid | 15 / 3 / 22 | -13 / LAUNCH | 13 | 2.8 + 1.1 |  | knee | From a slight crouch the lead knee drives straight up under the chin with a small jump, both hands pulling down, lifting the opponent. |
| LowSweep *input* | Low Reaping Sweep | b+4 | Low | 19 / 4 / 24 | -16 / KND | 14 | 3.9 + 0.5 | crouching | sweep | Drops low on the lead leg, rear leg reaps along the floor in a wide arc at the ankles (ashi-barai style), comes back up in stance. |
| LowKick | Low Kick | d+4 | Low | 13 / 2 / 20 | -13 / +1 | 8 | 4.0 | cancel into StillWater (3+4) | low_kick | Short rear-leg low kick to the inside of the knee: quick hip turn, shin chops down, returns to stance immediately. |
| LowPunch | Kneeling Punch | d+1 | Mid* | 11 / 2 / 14 | -4 / +4 | 5 | 3.8 | cancel into StillWater (3+4), special mid, crouching | straight | Drops into a low stance and throws a short straight lead punch to the stomach; stays low afterward. |
| SpinBackfist | Turning Backfist | b+2 | High | 15 / 3 / 18 | -8 / +4 | 13 | 4.15 + 0.45 | TUMBLE, homing | spinning_backfist | Steps across and turns his back, the rear backfist whips around in a flat circle to the side of the head, turning with a sidestepping opponent (homing). TUMBLE: on an airborne opponent the turning backfist spins the body over in the air. |
| LungePunch | Lunging Punch | f+2 | Mid | 16 / 3 / 20 | -8 / +5 | 16 | 3.65 + 1.95 |  | straight | Long gliding step forward (oi-zuki) covering distance, rear-hand punch to the chest at the end of the slide, body low and straight. |
| SideKick | Side Thrust Kick | f+3 | Mid | 14 / 3 / 18 | -6 / +3 | 14 | 3.85 + 1.45 |  | side_kick | Turns sideways, lead knee chambers across the body and the heel thrusts out sideways into the ribs (yoko-geri), body leaning away. |
| CrescentStep | Stepping Crescent | ss+4 | Mid | 15 / 3 / 19 | -7 / +4 | 13 | 4.25 + 0.55 | tracking | crescent_kick | From a sidestep, a stepping crescent kick to the ribs: rear leg swings in a wide inward arc at waist height, catching an opponent moving to the side. |
| StillWater **new** | Still Water | 3+4 | Mid | 8 / 1 / 1 | +0 / +0 | 0 | 2.6 | enters StillWater, no hitbox | parry | SIGNATURE stance entry (no strike): he slides the lead foot back half a step into a short, low back-weighted stance, the lead open hand extends forward at chest height, the rear fist settles at the hip, eyes on the opponent; a long exhale (see the stance). |
| StillStrike **new** | Sudden Strike | STW+1 | Mid | 10 / 2 / 15 | -3 / +5 | 8 | 3.9 + 0.4 | from StillWater | straight | From Still Water, the extended lead hand closes into a fist and shoots straight to the solar plexus with a small forward slide of the front foot, no wind-up; the fist twists palm-down at impact and returns. |
| StillReverse **new** | Rising Reverse Punch | STW+2 | Mid | 14 / 3 / 24 | -14 / LAUNCH | 14 | 3.7 + 0.6 | from StillWater | uppercut | From Still Water, the hips snap square and the rear fist drives from the hip up under the chin on a rising line (a reverse punch angled upward), the legs extending; the opponent is lifted into a juggle (launcher, very unsafe on block). |
| Throw | Hip Throw | 1+3 | Throw | 12 / 2 / 34 | break 1 ≤f20, impact f32 of 46 | 18 | 3.2 |  | hip_toss | Grips the sleeve and collar, steps in and takes them down with an outer reap of the lead leg. |
| ThrowB | Shoulder Throw | 2+4 | Throw | 12 / 2 / 34 | break 2 ≤f20, impact f32 of 48 | 19 | 3.2 |  | arm_toss | Arm trap and leg-block takedown, kneeling at the end. |
| Ultimate **new** | Last Kata | 1+2 | Mid | 20 / 3 / 28 | -15 / KND | 34 | 3.9 + 1.0 | armor (all hits) f1-19 | straight | ULTIMATE (Surge only, once per round) 'Last Kata': an armored gliding reverse punch opens it; on hit the cinematic plays the beats in movesets.md (knife-hand, front kick, rising elbow, a long still breath, one decisive reverse punch). |

**Ultimate — "Last Kata"** (key `Ultimate`, 1+2): i20, active 3, recovery 28, -15 on block, armor (all strikes) on frames 1-19, damage 34, reach 3.9 + 1.0. Cinematic: 190 frames (3.2 s), 4 impacts, ends FaceUp 4.6 studs in front of RHYS.

| impact | cinematic frame | share | damage (base) |
|---|---|---|---|
| 1 | 32 | 0.12 | 4.1 |
| 2 | 64 | 0.14 | 4.8 |
| 3 | 98 | 0.16 | 5.4 |
| 4 | 170 | 0.58 | 19.7 |

Beats (what attacker and defender do; impact poses land on the impact frames):

- f0 (the hit): an armored gliding reverse punch to the sternum; the opponent stops dead.
- f32 impact 1: a lead knife-hand chop down onto the collarbone; the defender's shoulder drops.
- f64 impact 2: a front snap kick into the stomach; the defender doubles over.
- f98 impact 3: a rising elbow under the chin; the defender's head snaps up and it sways, dazed.
- f110-169: Rhys steps back into a deep, still stance and exhales; nothing moves but the defender swaying (the camera holds on him).
- f170 impact 4 (the last kata): one perfect stepping reverse punch to the sternum; the defender is blown off its feet and lands on its back (FaceUp, 4.6 studs away). Rhys holds the finished punch, then returns the fist to his hip.

Combos (`Roster.get("Rhys").combos`, verified against all six opponents by `CombatCombo_Test`):

| combo | kind | notation | presses (frames after the previous press, hitstop not counted) | damage | difficulty |
|---|---|---|---|---|---|
| Knee And Backfist | launch | `df+3, 2, b+2, 1` | df+3 · +32 2 · +30 b+2 · +35 1 | 31 | 2/5 |
| Still Water Answer | stance | `3+4, STW+2, 2, b+2, 1` | 3+4 · +1 STW+2 · +40 2 · +30 b+2 · +35 1 | 32 | 3/5 |
| Counter Knee | max (CH opener) | `CH df+3, 2, b+2, 1` | df+3 · +32 2 · +30 b+2 · +35 1 | 34 | 3/5 |
| Last Kata Finish | ultimate | `df+3, 1+2` | df+3 · +32 1+2 | 38 (in Surge) | 2/5 |

New keys (8): ReverseHighKick, ReverseLowKick, PunchKickAxe, LowParry, StillWater, StillStrike, StillReverse, Ultimate.

### 5.6 NIA — Kung-fu-inspired whirlwind (24 moves)

**Identity:** Flowing whirlwind: never-ending hand strings, spins out of the Coil and delayable kicks that keep you guessing when the next one lands.

**Signature — Coil (stance):** 3+4: wind the body like a spring. COIL+4 starts the whirl: three spinning kicks (COIL+4,4,4: mid, high, mid knockdown) whose 2nd and 3rd hits can be delayed; COIL+d+4 floor sweep. Cancel 4 / 2,3 / b+2 into it; hold back to leave.

Stance `Coil` (tag `COIL`, snapshot `stance = "Coil"`): entry 6 f, follow-ups from stanceFrame 6, hold back from frame 8 to leave, ends on its own at frame 50; hits in it are counter hits.

- Entry: Shoulders turn away, the rear foot pivots, the palms circle and draw back (6 frames).
- Loop: Coil loop: a low, wound-up stance with the shoulders turned away from the opponent (back half turned), weight on the lead foot, both palms drawn back at the hip and slowly circling, the head looking over the lead shoulder. No guard (hits are counter hits).
- Exit: Unwinds back to the open kung fu stance, palms forward.

| key | name | notation | height | i / act / rec | block / hit | dmg | reach + adv | properties | archetype | animation intent |
|---|---|---|---|---|---|---|---|---|---|---|
| Chop | Knife Hand | 1 | High | 10 / 2 / 12 | +1 / +8 | 5 | 3.55 + 0.65 |  | chop | Lead knife-hand strike to the neck: open hand, fingers together, wrist turns as the hand cuts forward and slightly down, rear palm guards the chest. |
| DoubleChop | Twin Knife Hand | 1,1 | High | 10 / 2 / 13 | +0 / +7 | 6 | 3.75 + 0.55 | string after Chop | chop | The rear hand follows with a second knife-hand from the other side as the lead hand circles back, flowing figure-eight arm motion. |
| FlurryKick | Flurry Finisher | 1,1,4 | Mid | 15 / 3 / 22 | -12 / KND | 12 | 4.2 + 0.9 | string after DoubleChop, tracking | roundhouse | The hand flurry flows into a turning rear roundhouse to the body; she pivots on the lead foot, arms circle outward as the kick lands. |
| DoubleChopLow **new** | Flurry Low Kick | 1,1,3 | Low | 15 / 2 / 20 | -12 / +2 | 9 | 4.0 + 0.3 | string after DoubleChop | low_kick | Low ender of 1,1: after the two chops she sinks into a low stance and the lead foot snaps a short kick into the shin along the floor, both palms circling in front of her (same base as the flurry finisher: mid or low). |
| PalmThrust | Palm Thrust | 2 | Mid | 12 / 3 / 16 | -4 / +5 | 11 | 3.4 + 1.0 |  | palm | Rear palm thrust to the chest from a low horse-like stance: the hips sink and turn, the heel of the palm pushes forward, the lead hand withdraws to the waist. |
| PalmKick | Palm Into Rising Snap Kick | 2,3 | Mid | 14 / 3 / 19 | -8 / +3 | 11 | 3.8 + 1.0 | string after PalmThrust, cancel into Coil (3+4) | front_kick | The palm withdraws, weight shifts onto the rear leg and the lead foot snaps a front kick into the stomach, then the hands return to a guard as the foot lands back in the low stance. |
| PalmKickHigh **new** | Palm Kick Crescent | 2,3,4 | High | 16 / 3 / 22 | -9 / +5 | 13 | 4.4 + 0.6 | string after PalmKick, delayable +20 f, tracking | crescent_kick | High ender of 2,3 (delayable: she can hold it for a beat): the snap-kick foot lands and the rear leg swings a straight-legged outside crescent across the face in a wide arc, arms circling the other way. |
| RisingFrontKick | Rising Front Kick | 3 | Mid | 12 / 3 / 15 | -3 / +4 | 9 | 3.6 + 1.2 | TUMBLE | front_kick | Lead front kick rising from the low stance: knee up, toes pointed, snaps to the stomach and back, rear palm forward. TUMBLE: on an airborne opponent the rising kick flips the body over in the air. |
| HighKick | Whip Kick | 4 | High | 13 / 3 / 18 | -7 / +5 | 12 | 4.55 + 0.65 | cancel into Coil (3+4), tracking | roundhouse | Whipping rear roundhouse to the head, light and fast: the knee leads, the lower leg whips at the end, arms circle for balance. |
| LowSpin | Low Spin Kick | d+3 | Low | 13 / 2 / 18 | -11 / +4 | 8 | 4.0 | crouching | sweep | Sinks into a low crouch and the lead leg sweeps a short quick arc into the shin, hands near the floor, stays crouched. |
| RisingTornado | Rising Whirlwind | d+3,4 | Mid | 20 / 3 / 24 | -15 / LAUNCH | 12 | 3.1 + 1.5 | string after LowSpin | rising_kick | From the low spin she rises while turning, the rear leg kicks upward in a spiral under the chin, body corkscrews up onto the toes. Combos from the low spin on hit (a low-starter launcher); on block there is a gap to interrupt it. |
| RisingPalm *input* | Rising Palm Uppercut | db+2 | Mid | 15 / 3 / 22 | -14 / LAUNCH | 13 | 3.2 + 0.9 | high crush f1-7 | uppercut | From a crouch, the rear palm drives straight up under the chin while the legs extend, lead hand pulls down, she rises onto the toes. |
| ButterflyKick | Butterfly Kick | f+4 | Mid | 18 / 4 / 22 | -10 / KND | 16 | 3.85 + 1.15 | low crush f6-16 | butterfly_kick | Torso drops horizontal and she spins in the air with both legs scissoring outward (butterfly kick), the rear leg striking the chest; feet leave the floor (low crush). |
| Backfist | Snapping Backfist | b+2 | High | 12 / 3 / 15 | -3 / +6 | 9 | 3.0 + 1.6 | cancel into Coil (3+4), tracking | backfist | Short snapping backfist with the rear hand across the body to the temple, elbow leads, wrist flicks, quick recoil. |
| LowSweep *input* | Floor Sweep | COIL+d+4 | Low | 19 / 4 / 24 | -16 / KND | 14 | 3.9 + 0.5 | from Coil, crouching | sweep | From the Coil (holding down): she drops into a full crouch on one leg and the wound-up body releases into a full circle, the other leg sweeping flat along the floor (front sweep), hands on the floor; knockdown. |
| Elbow | Stepping Elbow | f+1 | Mid | 13 / 3 / 15 | -3 / +6 | 12 | 2.8 + 1.2 |  | elbow | Stomping step forward with a lead elbow driven horizontally into the chest, rear palm pushing the elbow (supported elbow), low stance. |
| TornadoKick | Cyclone Kick | ss+4 | High | 16 / 3 / 22 | -9 / KND | 15 | 3.75 + 1.35 | homing | tornado_kick | From a sidestep, a jumping 360-degree spinning kick: she turns her back, jumps, and the rear leg whips a flat circle at head height that follows the opponent. |
| Coil **new** | Coil | 3+4 | Mid | 6 / 1 / 1 | +0 / +0 | 0 | 2.6 | enters Coil, no hitbox | parry | SIGNATURE stance entry (no strike): she winds her whole body like a spring: the shoulders turn away from the opponent, the rear foot pivots, both palms circle in front of her and draw back to the hip, knees bent low (see the stance). |
| CoilWhirl **new** | Whirl Kick | COIL+4 | Mid | 12 / 3 / 18 | -6 / +3 | 10 | 3.9 + 0.5 | from Coil, tracking | spin_kick | The coil releases: she unwinds a full turn on the lead foot and the rear heel whips around into the ribs (spinning heel kick at waist height), arms flung wide. First hit of the whirl (4,4,4). |
| CoilWhirl2 **new** | Whirl Kick Second | COIL+4,4 | High | 14 / 3 / 18 | -7 / +4 | 10 | 4.0 + 0.4 | string after CoilWhirl, delayable +20 f, tracking | tornado_kick | Second hit of the whirl (delayable): the spin keeps going, she hops off the lead foot and the same leg whips a flat circle at head height in the air, landing facing the opponent. |
| CoilWhirl3 **new** | Whirl Kick Finish | COIL+4,4,4 | Mid | 17 / 3 / 24 | -13 / KND | 13 | 4.0 + 0.6 | string after CoilWhirl2, delayable +20 f | spin_kick | Third hit of the whirl (delayable): a last, lower, heavier spinning heel kick into the stomach that knocks the opponent down; she finishes the turn crouched with one palm forward. |
| Throw | Spinning Arm Toss | 1+3 | Throw | 12 / 2 / 34 | break 1 ≤f20, impact f32 of 46 | 17 | 3.2 |  | arm_toss | Catches the opponent's wrist for an arm wheel: draws the wrist down, circles it up and cuts it back over the shoulder, and they fall onto their back. |
| ThrowB | Twisting Hip Toss | 2+4 | Throw | 12 / 2 / 34 | break 2 ≤f20, impact f32 of 46 | 18 | 3.2 |  | hip_toss | Palms on the opponent's chest and hip, she sinks, twists her whole body and uproots them, tossing them in a spiral onto the floor. |
| Ultimate **new** | Monsoon | 1+2 | Mid | 19 / 3 / 29 | -15 / KND | 32 | 3.8 + 1.0 | armor (all hits) f1-18 | palm | ULTIMATE (Surge only, once per round) 'Monsoon': an armored spinning palm strike opens it; on hit the cinematic plays the beats in movesets.md (double palm, spinning chop, sweep, spiral kick, mid-air whirl, two-palm push). |

**Ultimate — "Monsoon"** (key `Ultimate`, 1+2): i19, active 3, recovery 29, -15 on block, armor (all strikes) on frames 1-18, damage 32, reach 3.8 + 1.0. Cinematic: 260 frames (4.3 s), 6 impacts, ends FaceUp 4.6 studs in front of NIA.

| impact | cinematic frame | share | damage (base) |
|---|---|---|---|
| 1 | 30 | 0.08 | 2.6 |
| 2 | 66 | 0.12 | 3.8 |
| 3 | 104 | 0.14 | 4.5 |
| 4 | 146 | 0.16 | 5.1 |
| 5 | 190 | 0.18 | 5.8 |
| 6 | 240 | 0.32 | 10.2 |

Beats (what attacker and defender do; impact poses land on the impact frames):

- f0 (the hit): an armored spinning palm strike to the chest; the opponent is rocked back and Nia flows in close.
- f30 impact 1: a double palm strike to the chest (both palms together); the defender's torso is pushed back.
- f66 impact 2: she turns and a spinning back-hand chop lands on the side of the neck; the defender's head jerks sideways.
- f104 impact 3: she drops into a low spinning sweep; the defender's legs are taken and it floats up, horizontal.
- f146 impact 4: she corkscrews up with a rising spiral kick under the floating body, lifting it higher.
- f190 impact 5: in the air at the top, a whirlwind kick (two legs whipping in one turn) across the floating body.
- f240 impact 6: she lands, sinks low and blasts a focused two-palm push into the falling defender; it slides across the floor onto its back (FaceUp, 4.6 studs away). Nia finishes in a low stance, palms forward, breathing out.

Combos (`Roster.get("Nia").combos`, verified against all six opponents by `CombatCombo_Test`):

| combo | kind | notation | presses (frames after the previous press, hitstop not counted) | damage | difficulty |
|---|---|---|---|---|---|
| Palm Lift Flurry | launch | `db+2, 1, 3, 2,3` | db+2 · +32 1 · +23 3 · +29 2 · +8 3 | 31 | 3/5 |
| Coil Whirl | stance | `db+2, 4, 3+4, COIL+4,4` | db+2 · +32 4 · +15 3+4 · +8 COIL+4 · +6 4 | 32 | 4/5 |
| Whirlwind Rise | low | `d+3,4, 4, 3+4, COIL+4,4` | d+3 · +3 4 · +50 4 · +15 3+4 · +8 COIL+4 · +6 4 | 39 | 4/5 |
| Monsoon Finish | ultimate | `d+3,4, 1+2` | d+3 · +3 4 · +50 1+2 | 44 (in Surge) | 3/5 |

New keys (7): DoubleChopLow, PalmKickHigh, Coil, CoilWhirl, CoilWhirl2, CoilWhirl3, Ultimate.

## 6. Change log after M1 (Contract B)

| commit | change |
|---|---|
| M1 (712426d) | keys, stances, Ultimates and timelines published |
| after M1 | `Ultimate.cinematic.endDistance` raised to 4.4-4.6 studs (motion request: the lying defender's feet reach about 3.1-3.3 studs in front of its root; at 2.8-3.8 they landed under the attacker's legs): Kael 4.4, Sierra 4.6, Goran 4.6, Lumi 4.4, Rhys 4.6, Nia 4.6. Keys, impact frames and durations unchanged. |
| phase 2 (sim, combos) | Frame data tuned so the listed combos are true combos (keys, stance keys/tags, Ultimate impact frames and durations unchanged): Sierra `Southpaw` entry 8 → 5 frames (`cancelFrom` 5, back exit from frame 8 instead of 10); `SouthpawBodyKick` (SPW+3) i15 → i13. Nia `LowSpin` (d+3) +2 → +4 on hit and `RisingTornado` (d+3,4) i22 → i20, so d+3,4 is a natural low-to-launch combo on hit. Lumi's tumble extender moved from `AerialSplit` (AER+3) to `PalmHeel` (1,4) (the committed Aerial travel cannot reach a juggled body). Lumi `CartwheelKick` (b+3) launches on counter hit (her counter route). Juggle physics: launch 16 → 19 studs/s, re-lift 7.5 → 9, tumble lift 9 → 12, air time 86 → 110 frames. `combos` lists added to every fighter (section 2.7). |
