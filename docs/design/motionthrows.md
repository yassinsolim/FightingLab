# motionthrows — two-person throws (OV6 phase 2)

Owner: motionthrows. Status: **ROUND 2 READY (offline-verified)**: 13 hand-keyed two-role throws, 13 grab clips and
1 test case exported to `handoff/motionthrows-src/`. Integrator round-2 gates met offline: joint violations 0;
interpenetration ≤ 4.9 cm (throw) and ≤ 4.6 cm (break); hands on the grip within 2 cm from the first grip frame;
attacker end feet clear of the FallBack feet. This export has not been run in Studio (see "Tests").

## 1. Files (`handoff/motionthrows-src/`, UTF-8, LF, no BOM)

| path | what |
|---|---|
| `ReplicatedStorage.FightingLab.Client.Motion.Clips.Moves.Throws.<Fighter>_<Key>.luau` (13) | FLThrow1: `attacker`, `defender` (60 fps, duration = throw.duration/60), `breakAttacker`, `breakDefender` (16 sim frames), `impact` = impactFrame/duration, `distance` = 1.0714 leg lengths, `sources`, `grips` (2-6 windows per throw, motioncore's runtime grip correction) |
| `ReplicatedStorage.FightingLab.Client.Motion.Clips.Moves.Throws.<Fighter>_<Key>_Grab.luau` (13) | FLClip1 grab attempt bound to the same move key: reach lands on the roster's first active frame (`contact`), whiff, back to stance; `tags.aim = false` |
| `ServerStorage.UnitTest.Cases.MotionMovesThrowsCoverage_Test.luau` | coverage + timing + end-pose + grab + finiteness + MotionPlayer smoke tests |

No runtime code changed. `ClipLibrary` indexes every ModuleScript under `Clips.Moves` (any subfolder), so the
throws bind through `ClipLibrary.forThrow(fighter, key)` and the grabs through `forMove`. My procedural
`Client.Motion.Throws` is unchanged and stays the fallback for unbound keys.

## 2. How the clips are made

Work folder `work/motionthrows/` (offline, no Studio):
- `thlib.py` two-body authoring on motioncore's reference skeleton: FK identical to `review.reconstruct`, analytic
  2-bone IK with poles, **grips** (a hand/foot attached to a point of the other body: collar, nape, belly, thigh,
  wrist …), **knee targets**, **carries** (a lifted body rides rigidly on the carrier's chest/pelvis), body-local
  limbs/poles (flips and lifts), capsule interpenetration / self-intersection / humerus-femur twist / floor checks.
- `spec_<fighter>.py` keys per throw (sim frames, library axes, metres). `build.py` solves both bodies per frame,
  checks, writes the modules with `clipio`, renders dense review sheets and the official `clipsheet.py` sheets.
  `summ.py` lists every problem frame; `probe*.py` print joints.
- Start/end poses: attacker and break tracks start/end on motioncore's **final displayed idle**
  (`keyed.displayed_frame` = `"Displayed:<Fighter>"`, §12 STANCES FINAL, Goran orthodox). Defender tracks end exactly on
  **`FallBack@0.3667`** (floor contact; Landing continues from it). Both end poses are shifted by the baked pushes
  agreed with motioncore: throw −0.155 L (0.45 studs) back for each fighter, break −0.207 L (0.6 studs).
- Channels: `ground` 0 until impact−1, 1 from the impact frame (runtime puts the lowest torso part on the floor);
  foot `contact` is sanitised so a foot is only "planted" (runtime foot lock) while its sole is on the floor and
  still; root motion is in the tracks (authored root distance 1.0 m = 1.0714 L).
- `grips` (motioncore runtime contact correction, validated by `clipio`/`cliplint`): every key segment in which a
  hand/foot fully holds the same partner point (weight 1 at both keys) is exported as a window (role, limb,
  anchor or R15 part + box point, from/to in track seconds, fade 0.05) so the runtime re-solves that limb onto the
  partner's real body for any fighter sizes; sliding grips keep the authored path. Each spec grip helper carries its
  runtime target (`spec_common.py`, e.g. nape -> Head (x, -0.75, 1), feet on the belly -> LowerTorso z -1.65).
  Until motioncore's runtime export lands, the field is ignored and the authored contacts play.
- Grab clips: keyed from the throw's first resolved attacker pose; `startup` = SIM startup (roster data is the
  genre impact frame, sim startup = impact − 1), so the reach shows on frame 12 (RamSlam 15).

## 3. What each throw shows (adaptations)

The sim never swaps sides and always lands the defender FaceUp at its own root, head away from the attacker, so
every "over the hip/shoulder/head" toss is staged as a backward takedown with the same idea and fighter style.

| fighter · key | name (combat) | animated |
|---|---|---|
| Kael · Throw | Clinch Headbutt | collar tie, rear knee to the body, short headbutt, shove; falls on his back |
| Kael · ThrowB | Over-Under Toss | over-under body lock, hip loads and lifts him (carried on the hip), dumps him on his back in front |
| Sierra · Throw | Clinch Knees | double collar tie, two alternating knees, twist and dump |
| Sierra · ThrowB | Clinch Trip | underhook (his elbow lifted), lead foot posts outside, rear leg swings round the outside and sweeps the lead ankle with a shoulder turn, then she steps back out of his falling legs |
| Goran · Throw | Bear Hug Toss | bear hug at the waist (he frames on Goran's left shoulder/arm), hip-thrust lift (legs dangle), wind-up pivot (front foot steps back), tosses him onto his back **in front** (not behind) |
| Goran · ThrowB | Belly Suplex | front body lock, sits under, lifts him belly to belly (arms fly up, legs straddle Goran's hips), **drives forward and slams him onto his back**, releasing just above the floor while the front foot steps back (no backward bridge) |
| Goran · RamSlam | Ram Slam | level change, shoulder in the belly, thighs scooped, carried on the shoulder (legs wide), tipped over and driven flat as Goran lets the thighs go and drops to a knee, then rises back clear |
| Lumi · Throw | Flip Toss | collar and shoulder grip, springs up, both feet on his belly, **backflips off him** (over her own head, not his); the kick-off drives him onto his back |
| Lumi · ThrowB | Vault Takedown | slips to his side (his near arm goes up), hooks the back of the neck, springs up hanging on it, stamps his lead knee, her weight folds him backwards; lands crouched well beside him and springs back |
| Rhys · Throw | Hip Throw | sleeve and collar, steps in, **outer reap** of the lead leg (the reaping foot comes down behind, the support foot steps out of his landing path), keeps the sleeve, zanshin |
| Rhys · ThrowB | Shoulder Throw | traps the lead arm and pulls it across, steps deep behind the lead leg with the forearm across the chest, rises into him and drops to a knee: **leg-block takedown** |
| Nia · Throw | Spinning Arm Toss | catches the lead wrist, draws it down, wheels it up and cuts it back over his shoulder (arm wheel); **no full-body spin** |
| Nia · ThrowB | Twisting Hip Toss | palm on the chest, palm under the hip, sinks and coils, uncoils upward: feet leave the floor, spirals onto his back |

## 4. Coverage (round 2)

Reference body (ACCAD Male2 proportions), attacker frame, every sim frame of the throw and of the 16-frame break.
- impact err = (frame the defender's torso first touches the floor) − throw.impactFrame.
- end gap = defender last frame vs `FallBack@0.3667` + baked push (same pose, cm).
- joint violations = humerus/femur twist beyond 105° (arm) / 65° (leg), throw + break; the solver clamps twist at
  100°/60° by rotating the pole, and the clamped pole is what is exported, so the runtime IK sees the same elbow/knee.
- interpenetration = deepest capsule overlap after intended-contact tolerances. Those are 3–5 cm for a hand on a
  limb, a forearm on the neck/back, or a foot on the thigh/belly, and 9 cm for a hand wrapped round a limb (its
  centre sits on the limb). Throw / break.
- grip gap = IK shortfall of a hand/foot whose grip weight is ≥ 0.5 (hand not on its partner point), worst frame.
- end clear = A's last frame vs D's last frame (raw capsules, no tolerance; negative = clearance).

| fighter | key | clip | sources | impact err | end gap | joint violations | interpenetration throw / break | grip gap | end clear |
|---|---|---|---|---|---|---|---|---|---|
| Kael | Throw | Kael_Throw (+_Grab) | original:motionthrows, quat-ual2-hit-knockback, accad-male2-e8-bounce | 0 | 0.0 cm | none | 2.8 cm (thighs f22) / 2.7 | 2 cm (f3) | −7.4 cm |
| Kael | ThrowB | Kael_ThrowB | same | 0 | 0.0 cm | none | 4.9 cm (thigh/shin f36) / 3.4 | 0 | −7.4 cm |
| Sierra | Throw | Sierra_Throw | same | 0 | 0.0 cm | none | 4.2 cm (forearm/head f22) / 4.6 | 1 cm (f0) | −1.9 cm |
| Sierra | ThrowB | Sierra_ThrowB | same | 0 | 0.0 cm | none | 4.7 cm (forearm/arm f2) / 4.2 | 0 | −1.9 cm |
| Goran | Throw | Goran_Throw | + accad-male2-d1-standtoready | 0 | 0.0 cm | none | 3.1 cm (thigh/shin f20) / 2.0 | 0 | −8.2 cm |
| Goran | ThrowB | Goran_ThrowB | same | 0 | 0.0 cm | none | 4.1 cm (head/chest f6) / 4.6 | 0 | −8.2 cm |
| Goran | RamSlam | Goran_RamSlam | same | 0 | 0.0 cm | none | 3.8 cm (thigh/foot f39) / clear | 2 cm (f18) | −8.2 cm |
| Lumi | Throw | Lumi_Throw | original:motionthrows, quat-ual2-hit-knockback, accad-male2-e8-bounce | 0 | 0.0 cm | none | 3.5 cm (foot/belly f15, the kick-off) / 1.7 | 1 cm (f0) | −3.1 cm |
| Lumi | ThrowB | Lumi_ThrowB | same | 0 | 0.0 cm | none | 4.9 cm (forearm/arm f2) / 4.2 | 2 cm (f0) | −3.1 cm |
| Rhys | Throw | Rhys_Throw | + accad-male2-d1-standtoready | 0 | 0.0 cm | none | 4.3 cm (forearms f19) / 3.3 | 2 cm (f0) | −1.8 cm |
| Rhys | ThrowB | Rhys_ThrowB | same | 0 | 0.0 cm | none | 4.8 cm (shin/foot f43) / 4.6 | 0 | −1.8 cm |
| Nia | Throw | Nia_Throw | same | 0 | 0.0 cm | none | 3.5 cm (thigh/shin f28) / 0.0 | 0 | −3.1 cm |
| Nia | ThrowB | Nia_ThrowB | same | 0 | 0.0 cm | none | 4.7 cm (forearms f15) / 3.3 | 0 | −3.1 cm |

Self-intersection ≤ 4.7 cm (hand/forearm vs own chest in fast releases). Planted-foot slide ≤ 0.2 cm. Lowest
capsule surface −0.7 cm (Rhys ThrowB kneel); feet never below the floor, and no planted foot hovers more than
2 cm (`feetgap.py`). `cliplint.py`: 26 modules, 222.1 KB, OK (grips validated).

What changed for the round-2 gates (all in `work/motionthrows/spec_*.py`, `thlib.py`, `spec_common.py`):
- **Twist**: solver-level clamp (above). Twist violations went from +1…+27° to 0 in every throw and break.
- **Paths, not shrinking**: Goran ThrowB is re-staged as a body-lock slam (legs straddle wide round his hips,
  released just above the floor, Goran steps the front foot back as he drives). RamSlam: legs carried wide, the arms
  let go of the thighs during the drop, Goran kneels further back and rises clear of the landing legs. Goran Throw:
  the defender frames on Goran's left shoulder/arm (no arm across his face), Goran pivots his front foot back during
  the wind-up. Sierra ThrowB: underhook under a raised elbow, lead foot posts outside, the sweep's knee stays outside
  his leg, a faster but legal retract. Lumi Throw: collar + shoulder grip, his hands go low-out then up as she jumps.
  Lumi ThrowB: she works further out at his side, his near arm goes up out of the way. Rhys Throw: the reaping foot
  comes down behind and the support foot steps out of his landing path (no high kick-back). Rhys ThrowB: the
  defender stays upright in the arm trap (shoulders no longer interlock). Kael ThrowB: the rear foot rises onto the
  ball during the lift (it hovered 5 cm before). Breaks: per-throw push directions, or an earlier `breakFrom` pose,
  where the generic shove crossed arms.
- **Hands on the grip from the first grip frame**: attackers lunge closer on the contact frame. Grip paths go
  round the body with intermediate keys (waist side → back, shoulder → armpit → shoulder blade). Releases ramp the
  weight below 0.5 instead of tearing the hand off a moving point. Remaining shortfall ≤ 2 cm, on frames 0–3 only
  (the hand closing on the collar at the contact frame).
- **End-pose feet**: `spec_common.END_CLEAR` steps the attacker's lead foot clear of the lying defender's raised
  FallBack foot: kickboxer (−6, −9) cm, karate (−14, −12) cm (x outward, z back). The other stances were already
  clear. Raw capsule clearance at the last frame is now −1.8 to −8.2 cm for every throw (it was +8.7 cm for Rhys).
  Idle's crossfade takes the foot back to the stance spot. The test allows the attacker's throw-end feet 0.62 studs;
  hands and root stay strict.
- `shifted(..., y)` now lowers the body only, so the old 1–3 cm "feet sunk into the floor" in a few recoveries is gone.
- Lumi Throw: slightly more hang time (apex +6 cm, lands f38 instead of f37, same duration/impact).

## 5. Evidence (`work/motionthrows/sheets/`, re-rendered for round 2)

- `<Name>.sheet.png`: official `clipsheet.py` render of all 13 throws (both bodies at the authored distance,
  `--duration/--impact-frame`, break row), plus `<Name>_Grab.sheet.png` for the 13 grabs.
- Composites I reviewed: `official_pair_0..6.png` (all 13 throws + breaks) and `official_grabs_final.png` (13 grabs);
  `official_overview.png` stacks all 13 throw sheets at 45 %.
- `<Name>.dense.png`: my two-body review sheets (side + three-quarter, every 2 frames). Some were last rendered as
  quick frame ranges; `python build.py --only <Name>` re-renders the full sheet.
- `report.json` holds the per-throw numbers. `summ.py <Names> <pen cm> <gap cm>` lists problem frames.
  `feetgap.py` lists hovering feet.

## 6. Tests

`ServerStorage.UnitTest.Cases.MotionMovesThrowsCoverage_Test` (7 cases):
- each of the 13 roster throws is bound to its FLThrow1 (with break tracks), a grab clip, and credits;
- impact = impactFrame/duration; track lengths, distance and 16-frame breaks match;
- the defender is not down 2 frames before the impact and is down at it; its last frame = FallBack@0.3667 pushed back;
- the attacker's throw and break ends = the grab clip's first frame (displayed stance) pushed back; the throw end
  allows feet up to 0.62 studs (lead foot stepped clear), hands strict;
- the grab contact lands on the first active frame, with `aim = false`;
- all tracks are finite;
- MotionPlayer poses both roles.

Round 2, offline:
- `testmirror.py` mirrors cases 1–6 on the exported modules against the combat Roster and motioncore's FallBack
  clip: **692/692 checks passed** over 13 throws.
- `cliplint` OK (work `src` and `handoff/motionthrows-src`).
- The test parses (StyLua formats it cleanly).

Studio: motioncore ran the full suite (298/298, including these 7 cases) against my **previous** export (round 1 +
grips). **This round-2 export has not been run in Studio** (not opened per the integrator: optional, memory rule).

## 7. Known issues (honest)

- Contacts are authored for the mid-size reference pair at the authored distance; motioncore's runtime `grips`
  correct the windowed holds for other sizes (verified by motioncore in-engine for Goran/Lumi pairs on the previous
  export), but sliding grips (collar → nape, waist side → back) and free limbs are not corrected.
- Several numbers sit just under the 5 cm gate (Kael ThrowB 4.9, Lumi ThrowB 4.9, Rhys ThrowB 4.8, Sierra
  ThrowB 4.7, Nia ThrowB 4.7, Goran ThrowB and Rhys ThrowB breaks 4.6). These are forearm/arm brushes in the clinch
  entries and a shin/foot brush as Rhys steps away.
- In the runtime Idle after a Sierra/Rhys throw, the crossfade brings the lead foot back to the stance spot while the
  lying defender's FallBack foot is still raised (before Landing's settle lowers it). A brief brush is possible
  there; it is outside these clips.
- Fast pieces: Sierra ThrowB's sweeping foot retracts at ~6 m/s; Goran RamSlam's defender passes vertical over
  Goran's shoulder for ~4 frames (f34–38) before the drop. They read as intended on the sheets, but should be
  checked in the integrator's real-fight captures.
- Lumi Throw flight is still quick (backflip f20–f38, ~0.3 s).

## 8. REQUESTs

1. REQUEST: `combat-src/ReplicatedStorage.FightingLab.Roster.luau` (intent strings only): update the animation intent
   of Goran Throw ("tosses them face-up in front of him"), Goran ThrowB ("lifts them belly to belly and slams them
   forward onto their back"), Lumi Throw ("backflips off the opponent's belly, the kick-off drives them onto their back"), Lumi ThrowB
   ("hooks the neck from the side, springs up and stamps the lead knee; her weight folds them backwards"), Rhys Throw
   ("outer reap of the lead leg"), Rhys ThrowB ("arm trap and leg-block takedown, kneeling at the end"), Nia Throw
   ("arm wheel: draws the wrist down, circles it up and cuts it back over the shoulder"), Kael ThrowB ("hip lift and
   dump in front") — the sim never swaps sides, so the literal intents cannot be animated.
2. ~~REQUEST: motioncore runtime grip correction + defender distance ramp~~: implemented and exported by
   motioncore (FLThrow1 `grips`, `MotionPlayer.ThrowAlignFrames` = 4; full suite 298/298 on my previous export).
   Remaining: the integrator's Studio run of this round-2 export plus real-fight throw/break captures.
