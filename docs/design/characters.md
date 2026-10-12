# Characters (OV6) — handoff

## Round 4 (scaling audit): every fighter in real adult proportion

The user asked for a full scaling audit ("each fighter looks right in every scale"): Kael's and Sierra's massive gloves,
Rhys's head reading too big, Goran's box-like lifting belt, and anything else the measurements flag. Every fighter was
measured on the fight templates and the lobby avatars (identical numbers), fixed, and is now bounded by
`CharacterLook_Test`. RootHeight and hip height are unchanged to the millimetre for all six; arm lengths moved -1.3% to
+1.5%.

**Method.** All numbers come from precise-collision copies of the meshes (`AssetService:CreateMeshPartAsync`,
`PreciseConvexDecomposition`) on a Workspace clone of the neutral template, sampled with rays: head width = widest
front-view row of the bare head (ears included), head depth = widest side-view row; hair = head + hair/hat silhouette;
shoulders = deltoid to deltoid on the bare body (upper torso + upper arms, widest front-view row from 0.07 x stature
below the shoulder joints to 0.02 x stature above; the arms hang slightly abducted, so the band's lower edge is the
widest row for everyone); neck = narrowest front-view row between the head box bottom - 0.15 and the jaw; hand length =
wrist joint to the farthest point of the hand mesh (the relaxed curl makes the box length unreliable), hand width =
widest row across the palm incl. the thumb (hand frame). Rigid gear is measured the same way through its weld; layered
items (they wrap the body cage on the client only) were measured as rendered (front and side chroma silhouettes vs the
precise bare body; on the rigid gloves, measured both ways, the renders read 2-4% larger than the precise hulls) and
are bounded by those renders in the test, per fit (body scales and hand scale). The CharacterLook_Test helpers produce every number in the tables
(`OV6\work\r4-characters\data\report-main.txt` / `report-final.txt`).

| Fighter | Heads tall | Head W / D (studs) | Hair / head W | Shoulders / head W | Neck / head W | Hand length, width / stature (visible hands) | Arms L / R (shoulder-elbow-wrist) |
|---|---|---|---|---|---|---|---|
| Kael | 7.03 -> 7.03 | .572 / .639 | 1.00 | **3.38 -> 3.24** | .56 | gloved (bare hand inside .111-.114, .065) | 1.704 / 1.669 -> 1.701 / 1.666 |
| Sierra | 7.01 -> **7.10** | .554 / .555 -> .547 / .547 | 1.00 | **2.19 -> 2.45** | .43 (head-mesh neck) | gloved (.098-.101, .054) | 1.643 / 1.647 -> 1.652 / 1.659 |
| Goran | 7.07 -> 7.07 | .666 / .691 | shaved | **4.31 -> 3.50** | .61 -> .60 | **.093 -> .103, .081 -> .054** | 1.901 / 1.926 -> 1.876 / 1.901 |
| Lumi | 7.25 -> 7.32 | .601 / .634 -> .595 / .626 | **1.64 -> 1.36** | **2.12 -> 2.43** | **.43 -> .48** | .109, .047 | 1.574 / 1.582 -> 1.597 / 1.605 |
| Rhys | **7.07 -> 7.25** | **.516 / .562 -> .502 / .547** | 1.04 | **3.18 -> 3.29** | .54 | .105, **.061 -> .054** | 1.697 / 1.677 -> 1.698 / 1.677 |
| Nia | **6.99 -> 7.07** | .518 / .479 -> .511 / .473 | **1.31 -> 1.23** | **2.24 -> 2.53** | .45 (.448, head-mesh neck) | **.091 -> .102**, .052 | 1.431 / 1.451 -> 1.450 / 1.470 |

Targets: 7.0-7.4 heads; shoulders men 2.8-3.3 head widths (Goran 3.6), women 2.4-2.9; neck >= 0.45 head widths (men
0.5); hands 0.10-0.115 x stature long, <= 0.055 wide; hair <= 1.3 head widths (curly 1.4). Statures: Kael 5.947,
Sierra 5.848 -> 5.837, Goran 6.753, Lumi 5.910 -> 5.901, Rhys 5.915 -> 5.893, Nia 5.503 -> 5.494. RootHeight / hip joint
height: Kael 4.113 / 3.215, Sierra 4.059 / 3.161, Goran 4.095 / 3.245, Lumi 4.111 / 3.292, Rhys 4.100 / 3.155,
Nia 3.933 / 3.073, all unchanged.

Justified outliers: Sierra's and Nia's necks (0.428 and 0.448 head widths) are the slender necks of their head meshes:
the narrowest point lies on the head mesh, which scales uniformly, so no scale changes the ratio (bounded at 0.42 and
0.44). Rhys is held at the top of the men's shoulder band (3.25-3.30) and >= 7.2 heads: the band caps how much broader
his frame may get, so the rest of the fix is a smaller head (0.72 -> 0.70) and slimmer hands; his bun stays (every
slimmer bun or topknot left scalp gaps or a hole at the back).

**Gloves.** Kael's and Sierra's layered both-gloves item (Deki's UGC) wrapped the large hand cage: Kael's rendered 1.44
head widths wide and 1.29 head depths deep and sat inside his head from the first guard frame on. Both now wear VochtigDoekje's
single gloves as rigid gear (`role = "glove"`, the mesh de-tilted and turned palm-in, uniform scale, tinted; the hand is
hidden inside). The glove is seated like a real one on a closed fist: its fist end lies past the knuckles by the padding
(Kael's heavy gloves 0.82 hand lengths from the wrist joint, Sierra's lighter ones 0.71; seated on the open fingertips,
1.03, the gloves stood 0.2-0.3 studs above the eye line in guard) and the cuff wraps the wrist 0.55-0.62 hand lengths up
the forearm.

| | Length / stature | Width / head W | Depth / head D | Fist end, cuff (hand lengths from the wrist) | Glove inside the head (guard, jab + cross to full extension, 6 hit reactions; 195 frames) | Eyes hidden in guard (fight camera, both sides) |
|---|---|---|---|---|---|---|
| Kael | .165 -> .155 | **1.44 -> .95** | **1.29 -> .84** | 1.14, .36 -> .82, .55 | **209 of 390 glove-frames -> 0** | 0 of 45 eye sightings -> 0 of 45 |
| Sierra | .146 -> .134 | .93 -> .84 | .75 -> .83 | 1.06, .37 -> .71, .60 | **5 (jab/cross extension) -> 0** | **45 of 90 -> 0 of 90** |

**Gear.** Goran's lifting belt was a 0.62-stud box (0.092 x stature tall): refit lower and slimmer on the shorts'
waistband, 0.32 tall (0.047), 0.17 proud (0.026). His tactical knee pads stood 0.355 off the knee (0.053; every catalog
pad measured 0.31-0.37), so they are gone; they had been hiding the body bundle's open knee joint (the upper-leg mesh
ends above the lower-leg mesh at the front of the knee, at any scale), so he now wears plain black compression tights
under the shorts (layered, flush; grappler spats). Nia's rigid pirate sash was a box at the hip (band 0.094 x stature,
0.063 proud) -> GAULTIER's layered purple waist wrap: band 0.085 (a draped sash; real sashes are 10-15 cm, 0.09 bound),
band 0.029 proud, tails hanging 0.29 off the hip. Sweatbands 0.095 -> 0.084 (0.012), Lumi's sleeves 0.094 (0.016),
Rhys's wraps 0.058 (0.010).

**Changes per fighter** (`characters/<Id>.json`; `tools\build-data.ps1` regenerated `CharacterSpecs`, `CREDITS.md`
and the Credits module):

- Kael: Width .96 -> .92; layered Boxing Gloves (Deki's UGC, 101503419947939) -> rigid Boxing Glove Left/Right White
  (VochtigDoekje, 14775131832 / 14775127400), scale .845, tinted burnt orange.
- Sierra: Width .76 -> .84, Head .72 -> .71; layered Boxing Gloves (Deki's UGC, 81319860328594) -> the same rigid
  VochtigDoekje gloves, scale .72, tinted brown. (Width .85 put her teep kick's released planted foot on a 0.22-stud
  one-frame snap at max range in MotionGround_Test, limit 0.2; at .76-.84 the worst released-foot jump over all kicks
  is .10-.17.)
- Goran: Width 1.12 -> .91, Depth 1.12 -> .98; knee pads ((3.0) Black Tactical Knee Pads, SonokoToume) removed; black
  leggings (WhoseTouz, 15824475572) as compression tights; belt fit [1.15, .297, 1.25] offset [0, .04, .01]; boot fit
  Z 1.06 (keeps the boots 0.16 x stature long); handScale [.88, 1.18, .76] (his January Model Man hands were short mitts).
- Lumi: Width .74 -> .84, Head .88 -> .87; curly hair Scale [.75, .78, .78] Position y +.015 (still 100% scalp).
- Rhys: Head .72 -> .70, Width .86 -> .865; handScale [1, 1, .88].
- Nia: Width .80 -> .89, Head .75 -> .74; bob Scale [.87, .90, .88]; Purple Pirate's Waist Sash (Рort Royal,
  15502016508) -> Elegant Waist Wrap Drape (Purple) (GAULTIER, 93954966441244); handScale [1, 1.13, 1].

**Factory.** NEW `Spec.handScale = {x, y, z}`: scales both hand parts and their attachments about the hand centre after
the avatar is built, re-sets the wrist Motor6D from the scaled wrist attachment (the wrist joint stays put; arm length
unchanged) and scales the Humanoid's OriginalSize / OriginalPosition values so Humanoid rescaling keeps it. Idempotent
(`FightingLabHandScale` attribute): re-applying is a no-op, re-dressing a live character as another fighter undoes the
previous factor; part of the dress signature.

**Tests** (`CharacterLook_Test`, 21 -> 38; all fail on `main` where it had the defect: 14 failures, listed with
numbers in `OV6\work\r4-characters\data\test-r4-main.txt`):

- heads tall bound tightened 6.8-7.6 -> 7.0-7.4 (Nia 6.99 failed on main).
- per fighter "is in real adult proportion": heads (Rhys >= 7.2), shoulder band, neck, hair silhouette, visible hands.
- "motion-relevant lengths hold": RootHeight and hip height within 1%, arm length within 3% of round 3.
- per gloved fighter "boxing gloves are sized like real gloves and cover the hands": rigid gloves exact (precise mesh
  through the weld), layered gloves only through a measured render; length <= .18 x stature, width <= 1.1 head widths,
  depth <= .9 head depths, fist end .65-.9 hand lengths from the wrist, cuff >= .4, closed glove hides the open hand.
- per gloved fighter "gloves never clip into the head and leave the eyes visible in guard": the template posed with the
  real MotionPlayer (guard cycle, jab and cross to their first active frame, High/Mid/Low x Light/Heavy hit reactions);
  glove copies shrunk 8% about their centre (a glove resting on a cheek is contact, not clipping) must not overlap the
  head; in guard, from CameraDirector's fight plan on either side of the fight line, no glove may hide an eye that the
  camera sees in front of the profile line (<= 90 degrees off the face) past the head and hair.
- per fighter "gear sits close to the body": protrusion <= .04 x stature, belts <= .06 x stature tall, sash bands
  <= .09 (rigid gear measured, layered gear through renders per fit).
- `dressCharacter` idempotency now covers the hand scale (applied once, kept, undone on re-dress, restored).

Full suite on the branch (my Studio, Play, server): `[SUMMARY] 387 run, 387 passed, 0 failed` (main: 370).

**Evidence** (`OV6\handoff\characters-shots\round4\`): `lineup-front-before-vs-after.jpg` (head-width and
shoulder-width bars, per-fighter labels), `lineup-side-before-vs-after.jpg`, `fightcam-actions-before.jpg` /
`fightcam-actions-after.jpg` (close-up fight camera: guard, jab at full extension, kick at contact, hit reaction, all
six), `fightcam-actions-after-wide.jpg` (FOV 36 as played), `fightcam-gloves-opponent-side-after.jpg`,
`fighter-select-before-vs-after.jpg`, `lobby-front34-before-vs-after.jpg`, `lobby-back34-before-vs-after.jpg`.

**Known issues (round 4).**

- Guard glove tops sit 0.10-0.18 studs above the eye centre for Kael (brow level) and -0.06..+0.08 for Sierra. From
  the player's own fight camera Kael's face is turned just behind the profile line (92-95 degrees off the face) and his
  rear glove covers the cheek and the profile there (0.02-0.08 studs lower would clear it); the eyes read from the
  opponent's side (74-79 degrees, never covered). Sierra's eyes stay clear from both sides.
- The VochtigDoekje glove mesh is stubbier than a real glove (length 1.7 x its width; real 2.3): a real-length glove
  would be wider than the head, so the gloves are a little short (.134-.155 x stature, real about .17).
- Goran's tights change his round-3 look (bare legs + knee pads); no thin catalog knee sleeve exists (the only one is a
  left-knee item modelled bent, which does not fit as rigid gear).
- Rhys's gi is bulky by design (one layered item): his bare-body shoulder ratio is 3.29, the gi reads wider.

**REQUESTs (round 4).**

- motion (`MotionGround_Test` / Sierra's teep kick): at Sierra Width .85 the released planted foot snaps 0.223 studs in
  one frame at max range (limit 0.2); round 4 ships Width .84 (0.10). The release is on a knife edge for small changes
  in hip width.
- motion (guard pose, `Motion.States` / style arms): optionally lower Kael's rear guard glove ~0.1 studs (glove tops
  at the cheekbone instead of the brow) so his profile eye also reads from the player's own camera.
- motion QA: re-check clipping with the new rigs — rigid gloves (Kael scale .845, Sierra .72, seated toward the wrist:
  the glove's fist end is 0.21 studs closer to the wrist than the round-3 layered gloves' end), hand scales
  (Goran [.88, 1.18, .76], Nia [1, 1.13, 1], Rhys [1, 1, .88]) and the new widths (Kael .92, Sierra .84, Goran .91 /
  depth .98, Lumi .84, Rhys .865, Nia .89). CharacterLook_Test poses the gloved fighters with MotionPlayer and
  CameraDirector, so guard or camera changes on r4-motion should be re-run against it.
- combat (`Roster` look strings), optional: Kael "burnt-orange leather boxing gloves", Sierra "brown leather boxing
  gloves", Goran "grey camo fight shorts over black compression tights" (no knee pads), Nia "deep-purple draped waist
  wrap" (the specs' `look` strings carry the new text).
- Nia's visible-foot ground REQUEST from round 3 is still open.

## Round 3 (user feedback): slimmer shoes, no more bald backs of heads

The user played Overhaul 6 and reported (1) "a lot of the characters' shoes are too big" (Kael's high-tops read as clown
shoes, Lumi's sneakers as moon boots, Goran's boots heavy) and (2) "this guy is bald" (Kael from behind at the lobby
camera: the cornrows stopped at the crown). Both are fixed; Rhys had the same bald-from-behind problem (undercut) and is
fixed too. Bodies, scales, heads, RootHeights and leg lengths are unchanged (statures 5.50-6.75, heads tall 6.99-7.24
exactly as shipped).

**Why rigid shoes.** The OV6 shoes were layered (WrapLayer) accessories. On these realistic bodies a layered shoe wraps
the body's foot cage and renders 1.5-3x the bare foot width; its handle Size/Puffiness does not change the render and
the server cannot measure it. Measured as rendered (chroma silhouettes), they also sank 0.04-0.26 studs below the soles.
Round 3 wears the catalog shoe mesh as a rigid part welded to the foot (`gear` with `role = "shoe"`, `seat = "sole"`),
sized exactly and seated on the foot's sole, so the server measures it and the tests bound it.

**Sole proxy (ground box).** MotionPlayer's ground solver plants, tips onto the ball and lays down the foot part's box.
A real-size shoe is longer than these bodies' small bare feet, so its toe or heel sank whenever the foot pitched
(knockdowns, getups, rolls: Lumi 0.13, Kael 0.06 studs; Lumi's rear foot on its ball 0.28 in a live fight). Where the
bare foot is hidden under its shoe (Kael, Goran, Lumi) `CharacterFactory.build` now makes the hidden foot part the
shoe's ground box: it takes the shoe's length and width and moves under it, keeping its height, bottom face and ankle
joint (RootHeight and leg length identical), with joints, welds, attachments and the Humanoid's OriginalSize /
OriginalPosition values re-expressed so nothing visible moves and Humanoid rescaling cannot undo it (attributes
`FightingLabSoleProxy`, `FightingLabBareFootSize`). Fight templates only; lobby avatars are unchanged.

| Fighter | Shoe before -> after | Length / stature | Width / bare foot | Height / stature | Hair | RootHeight |
|---|---|---|---|---|---|---|
| Kael | layered Dresscraft "Black Street Fit Sneakers" (rendered as huge black/white high-tops) -> rigid **High Cut Sneakers Black** (The 67 UGC), bare foot hidden | 0.272 -> **0.155** | 2.34-2.64 -> **1.14-1.15** | 0.21 -> **0.101** | Cornrows 17750359523 refit (Scale 1.02/1.15/1.10, Position y -0.04): braids reach the nape. Scalp coverage 61% -> **100%** | 4.113 -> 4.113 |
| Sierra | barefoot (unchanged) | - | - | - | Doll High Ponytail (unchanged), 100% | 4.059 -> 4.059 |
| Goran | layered Light Brown Combat Boots -> same boots **rigid**, foot hidden | 0.24 -> **0.169** | 1.56 -> **1.18** | 0.15 -> **0.092** | shaved by design: no hair item at all (reads as a clean shave) | 4.095 -> 4.095 |
| Lumi | layered Dresscraft "Obsidian Prism Tech Sneakers" (moon boots) -> rigid **Tabi Suede Boots in Black** (creepertDev, split-toe martial-arts boots), foot hidden, cuffs tucked | 0.22-0.23 -> **0.152** | 2.64-3.05 -> **1.19** | 0.22 -> **0.115** | curly taper (unchanged), 100% | 4.111 -> 4.111 |
| Rhys | barefoot (unchanged) | - | - | - | Brown Hair Undercut Ponytail (bare back/sides) -> **Brown Man Bun - Millennial** 103417751582989 (Looe UGC, Scale 1.0/1.25/1.04, Position y +0.02). 26% -> **100%** | 4.100 -> 4.100 |
| Nia | layered Casual Slip On Dude Shoes -> same slip-ons **rigid**, foot visible (ankle shows) | 0.133-0.136 -> **0.155** | 1.60-1.64 -> **1.22** | top 0.46-0.47 studs above the sole (ankle bone 0.38-0.40) -> **0.385** (at the ankle bone) | black bob (unchanged), 100% | 3.933 -> 3.933 |

Before = OV6 shipped layered shoes as rendered (chroma silhouettes on the fighter); after = exact rigid boxes. Every shoe
is at most as wide as the lower leg it sits on, and its sole is on the foot's sole (0.00). Scalp coverage = share of 69
rays from behind, three-quarter behind, the sides, the top and the front hairline that hit hair before head skin.

Ground contact, mesh-accurate (precise-collision hull of each shoe), studs below the floor or below the foot box the
solver rests on it; negative = sinks:

- Motion sweep (stance, close stance, walk, back walk, crouch, dash, backdash, both sidesteps, hits, stagger, falls into
  stand/back-roll/side-roll getups, KO face up/down), without -> with the sole proxy: Kael -0.060 -> **-0.012**,
  Goran -0.022 -> **-0.005**, Lumi -0.125 -> **-0.020**; Nia (visible foot, no proxy) **-0.118** in knockdowns and rolls,
  +0.001 standing/walking.
- Live practice fights (Hard CPU, about 45 s each, every frame): Kael worst -0.040 (crouch, 4 frames, the solver's own
  foot box was at -0.040), Goran -0.038 (2 frames), Lumi -0.036 (2 frames); knockdown/getup frames >= -0.024; planted
  soles median -0.002..+0.001. Nia -0.148 (3 frames in a walk), -0.099 (4 frames), -0.086 (1 frame) (visible foot, see below).
- MotionGround_Test (motioncore) passes unchanged with the proxies (worst lying gap 0.030).

Owner files (exported to `OV6\handoff\characters-src\`, UTF-8/LF/no BOM):

| File | Change |
|---|---|
| `ServerStorage.FightingLab.CharacterFactory.luau` | Rigid gear shoes: `GearSpec.seat` (`"sole"`: bottom on the target's bottom face) and `role` (attribute `FightingLabRole`); `Spec.shoeStyle` (`high`/`low`/`barefoot`). Gear handles drop Attachments/Constraints/WrapLayer/WrapTarget; skinned catalog meshes are wrapped in a holder Model (`<name>Rigid`) so they render as welded instead of skinning onto the rig. Gear that fails to load is skipped and listed in `MissingAccessories`. NEW `fitSoleProxies` (fight templates): hidden shod feet become the shoe's ground box (see above); visible shod feet publish `FightingLabShoeGroundSize` / `FightingLabShoeGroundCenter` (foot space). |
| `ServerStorage.FightingLab.CharacterSpecs.luau` | Regenerated from `OV6\handoff\characters\*.json` (`json_to_luau.py`; verified byte-identical to a fresh regeneration). |
| `ServerStorage.UnitTest.Cases.CharacterLook_Test.luau` | NEW per fighter "hair covers the whole scalp" (69 precise-collision rays; >= 95%; Goran: no hair item at all); NEW "shoes are sized like real shoes as worn" (length 0.15-0.17 x stature, width <= 1.25 x bare foot and <= lower leg, low shoes <= ankle bone + 0.02, high-tops <= 0.125 x stature, sole within 0.03 of the foot sole; layered shoes only via measured renders); NEW per shod fighter "shoes rest on the floor through knockdowns, falls, getups and rolls" (real MotionPlayer, shoe hull vs floor/foot box: proxied feet >= -0.03, visible foot >= -0.13). Blocklist adds the film-character costume boots and the brand-look skate high-tops met in the shoe search. |
| `ServerScriptService.FightingLabCharacterBoot.luau` | Unchanged (byte-identical to the shipped build). |

Specs: Kael (cornrows refit, rigid high-tops, `look`), Goran (rigid boots), Lumi (rigid tabi boots, `look`), Rhys (man
bun, `look`), Nia (rigid slip-ons), all six `shoeStyle`. Credits: still 81 unique items; added High Cut Sneakers Black
(bundle 203322574255359 + L 70716256524989 / R 129737407945021, The 67 UGC), Tabi Suede Boots in Black (bundle
199239061768347 + L 109971937853096 / R 111746619334138, creepertDev), Brown Man Bun - Millennial (103417751582989,
Looe UGC); removed Black Street Fit Sneakers [PBR] (141883318340139, 128212268343103, 110054253690142, Dresscraft),
Obsidian Prism Tech Sneakers [PBR] (230848115295914, 106421807303280, 77675773538059, Dresscraft), Brown Hair Undercut
Ponytail (14063983879, LimaMosca); Goran's and Nia's shoe credits change kind to "Rigid shoe".

Tests (my Studio, Play, Server): `[SUMMARY] 370 run, 370 passed, 0 failed` (shipped 359 + 11 new; MotionGround_Test
green). The final CharacterLook_Test on the OV6 shipped specs: `17 run, 14 passed, 3 failed` — Kael scalp 61%, Rhys
26%, 38 shoe problems (e.g. "Kael Left layered 128212268343103 is 0.272 x stature long", "2.34 x the bare foot wide",
"wider than the lower leg (0.77 vs 0.43)", "high-top is 0.209 x stature tall", "sole is -0.130 off the foot's sole").
The ground tests fail on templates without the sole proxy ("hidden foot is its shoe's ground box"). Templates rebuild
with `MissingAccessories` = "" for all six.

Evidence (`OV6\handoff\characters-shots\round3\`):

- `lobby-back-before-vs-after.jpg`: the user's lobby camera (behind, and three-quarter behind) on the Training Bay CPU
  pad, all six, real SelectFighter -> AvatarService path. Backs of heads covered (Kael braids to the nape, Rhys bun),
  Goran clean-shaven, shoes in proportion.
- `heads-from-behind-before-vs-after.jpg`: same cameras, studio light, straight and three-quarter behind.
- `feet-side-front-before-vs-after.jpg`: side + front close-ups, all six.
- `fightcam-before-vs-after.jpg`: real practice fights (Kael vs Goran, Lumi vs Nia) on the fight camera.
- `fighter-select-before-vs-after.jpg`: the Fighter Kiosk select close-up, all six.
- `getup-knockdown-feet-after.jpg` and `getup-feet-groundbox-vs-barefootbox.jpg`: floor-level close-ups of KO, getup
  and roll poses with the sole proxy, and the same poses with the bare-foot box.

Known issues (round 3):

- Nia's foot stays visible above her low slip-ons (hiding it leaves a floating ankle stump), so her foot keeps the bare
  box: in knockdowns, rolls and a few walk frames the slip-on's heel or toe dips up to 0.12-0.15 studs into the floor
  (standing and walking planted: +0.001). Fix needs the ground solver to read the published shoe box (REQUEST below).
- Rigid shoes do not flex at the ankle (high-top shafts rotate with the foot). Goran's thick shins show inside the open
  V of the boot lacing (a skin wedge in front close-ups and rolls; not visible at the fight or lobby camera).
- A pitched foot can show its shoe up to about 0.07 studs above the floor (the solver rests the box corner, the real
  sole is rounded).
- Kael's cornrows are the same item stretched 15% (Y) to reach the nape; the braids are a little longer, not denser.
- Sierra's barefoot doll feet stand on their toes (pre-existing body mesh, unchanged).

REQUESTs (round 3):

- integrator: apply `CharacterFactory`, `CharacterSpecs` and `CharacterLook_Test` from `characters-src` (Boot unchanged).
- integrator (`RF.Credits`, `tools\gen_credits.py`): regenerate from `OV6\handoff\characters` (81 items; adds/removals
  listed above; Dresscraft's Japanese item names leave the credits).
- combat (`RF.Roster`), `look` strings (the JSON `look` fields carry the same text):
  - Kael: "... medium-olive realistic face and tight cornrows down to the nape; ... sleek black leather high-top boxing boots."
  - Lumi: "... mint slim-fit track pants tucked into black suede split-toe tabi boots, open hands."
  - Rhys: "... light realistic face and dark-brown hair tied back in a bun; deep-indigo karate gi ..."
- motioncore (`ReplicatedStorage.FightingLab.Client.MotionPlayer`), optional, fixes Nia's knockdown dips: in
  `restChain`, when the foot part has `FightingLabShoeGroundSize` / `FightingLabShoeGroundCenter` (Vector3, foot space;
  same height and bottom as the foot box), use them as `tipSize` and `tipOffset = C1.Position - center`, and evaluate
  the foot box from `tipWorld * CFrame.new(center)` (lowest point, `soleGap`). `ankleHeight` and RootHeight do not
  change. Hidden-foot fighters already carry the box in the foot part itself.

## Round 2 (head size): every fighter is now 7.0-7.2 heads tall

Head scale only (Kael .83 -> .70, Goran .92 -> .81, Rhys .85 -> .72, Nia .84 -> .75; Sierra and Lumi unchanged). Height,
width, depth, body type and proportion are unchanged, so RootHeights are identical to round 1 (motion clips keep their
leg-length fit). Statures drop by the head difference only (0.09-0.15 studs).

| Fighter | Head scale r1 -> r2 | Heads tall r1 -> r2 | Stature r1 -> r2 | RootHeight |
|---|---|---|---|---|
| Kael | .83 -> .70 | 6.07 -> **7.03** | 6.09 -> 5.95 | 4.113 |
| Sierra | .72 (kept) | 7.01 | 5.85 | 4.059 |
| Goran | .92 -> .81 | 6.32 -> **7.07** | 6.86 -> 6.75 | 4.095 |
| Lumi | .88 (kept) | 7.24 | 5.91 | 4.111 |
| Rhys | .85 -> .72 | 6.14 -> **7.07** | 6.06 -> 5.91 | 4.100 |
| Nia | .84 -> .75 | 6.34 -> **6.99** | 5.59 -> 5.50 | 3.933 |

Checks after the change: hair and Goran's beard stay seated (centres 0.15-0.35 head heights from the head centre, boxes
overlap the head; also at look-up/look-down/turned neck with a shout, `head-angles-r2.jpg`); FaceControls expressions
(neutral/determined/shout/pain) still work (`faces-after.jpg`); faces still read on the game's fight camera
(`fightcam-r1-vs-r2.jpg`); the six silhouettes stay distinct (`lineups.jpg`, `lineup-heads-r1-vs-r2.jpg`). Round-1
sheets (and the lobby plaza shots, which still show round-1 heads) moved to `characters-shots\round1\`; the outfit
standoff metrics are unchanged by head scale and stay at the top level.

Owner files (exported to `OV6\handoff\characters-src\`, UTF-8/LF/no BOM, baseline names):

| File | Change |
|---|---|
| `ServerStorage.FightingLab.CharacterSpecs.luau` | Regenerated from `OV6\handoff\characters\*.json` (`json_to_luau.py`, order Kael, Sierra, Goran, Lumi, Rhys, Nia). Hashes changed for all six, so `FightingLabCharacterBoot` rebuilds every template on first boot. |
| `ServerStorage.FightingLab.CharacterFactory.luau` | NEW `Factory.missingAccessories(model, spec) -> { assetId }` (authored accessories that are not on the rig: unavailable asset or an AccessoryType the catalog item does not match, which HumanoidDescription drops silently). `build()` warns and sets the `MissingAccessories` attribute (`""` when complete). Procedural bands kept for compatibility but no shipped spec uses them. |
| `ServerScriptService.FightingLabCharacterBoot.luau` | NEW `Characters` attribute `IncompleteTemplates` (`"Id:assetIds;..."`, empty when every authored item landed). |
| `ServerStorage.UnitTest.Cases.CharacterLook_Test.luau` | Rewritten, 10 tests: R15/RootHeight [2, 4.2]/FaceControls/MissingAccessories; proportions (round 2: 6.8-7.6 heads tall, leg/stature 0.45-0.62, Goran tallest and >= 1.2x broader, Nia shortest, Lumi longest legs (hip height) and narrowest shoulders); head accessories seated on the scaled heads (hair/beard box overlaps the head, centre <= 0.75 head heights away; self-checked on a synthetic floating item); every item textured (>= 2 PBR, no bands, gear = catalog meshes, tints landed); fitted leg garments (mesh <= 1.9 x 0.95 studs, tall shoes layered above long pants); welded/massless/non-colliding extras; blocklist (ids + words) and exact credits; `dressCharacter` idempotency; `missingAccessories`; build budget. |

Specs JSON (`OV6\handoff\characters\<Id>.json`) remain the source of truth, including exact `sourceAssets` credits (81 unique items).

## Fighters

Scales are Height/Width/Depth/Head/BodyType/Proportion. Stature, heads and leg ratio are measured on the neutral template (crown to sole, hip joint height / stature).

| Fighter | Outfit (final) | Scales (was) | RootHeight | Stature, heads, leg, shoulders | What changed |
|---|---|---|---|---|---|
| Kael | angelshefford Model Man; Cornrows; slate sleeveless boxing hoodie; red satin boxing trunks; orange gloves; black/white high-tops | .93/.96/.92/**.70**/1/.40 (OV5 .90/.90/.90/.86/.62/.84) | 3.728 -> **4.113** | 5.95, **7.03 heads**, .541, 1.23 | Proportions only (smaller head, longer legs, broader boxer frame). Outfit already fitted. |
| Sierra | iAngel Realistic Model Woman Doll; **Doll High Ponytail (Platinum)**; teal striped tank; teal trunks; brown gloves; barefoot | .90/.76/.78/.72/1/.80 (OV5 .82/.74/.78/.70/.45/.92) | 3.543 -> **4.059** | 5.85, **7.01 heads**, .541, .80 | New hair (no shoulder clipping, cleaner silhouette); lean, long-legged kickboxer build. |
| Goran | iAngel January Model Man; **Light Brown Full Trimmed Beard** (fitted pos/scale); **Tight Muscle Tank Top (Dark Red)**; grey camo shorts; **(3.0) Black Tactical Knee Pads**; red sweatbands; lifting belt; light-brown combat boots | .85/1.12/1.12/**.81**/1/0 (OV5 .82/1.08/1.10/.96/.86/.66) | 3.688 -> **4.095** | 6.75, **7.07 heads**, .481, 2.03 | Beard no longer floats (smaller, seated on the jaw); ribbed tank hides a body-texture mark on the deltoid; slim knee pads replace chunky strap pads; tallest/heaviest silhouette (1.65x Kael's shoulders). |
| Lumi | **iAngel January Model Doll** body/head; curly taper + sports band; olive crop tank; techwear sleeves; **White Slim fit tracksuit pants tinted mint**; tech sneakers layered over the pants | .82/.74/.76/.88/1/1 (OV5 .84/.72/.76/.86/.45/.92) | 4.159 -> **4.111** | 5.91, **7.24 heads**, .557, .75 | Wide cargo pants (ballooned) -> slim track pants with cuffs tucked into the sneakers; light, long-limbed build (longest legs, narrowest shoulders). |
| Rhys | angelshefford Fashion Model Man; undercut ponytail (re-seated, no collar clipping); deep-indigo gi; grey tee; black belt; **Hand Wraps** (textured, under the sleeves); barefoot | .95/.86/.86/**.72**/1/.60 (OV5 .92/.84/.86/.88/.55/.88) | 3.756 -> **4.100** | 5.91, **7.07 heads**, .533, 1.06 | Untextured SmoothPlastic tape bands -> textured layered hand wraps; hair fit; taller, cleaner karateka. |
| Nia | **angelshefford Woman Fashion Model Doll** body/head; black bob; black/gold martial top; **slim pants tinted deep purple**; **Purple Pirate's Waist Sash**; dark slip-ons | .86/.80/.80/**.75**/1/.50 (OV5 .84/.72/.76/.86/.45/.92) | 4.159 -> **3.933** | 5.50, **6.99 heads**, .558, .74 | Glossy wide silk pants (ballooned) -> matte tapered pants; procedural gold band -> textured wrapped sash; compact (shortest) build; refined fair-skinned face. |

## Numbers

- Tests (my Studio, Play, Server, round 2): `[SUMMARY] 225 run, 225 passed, 0 failed` (CharacterLook_Test 10/10), on two consecutive Play sessions.
- Boot: all six templates rebuilt in `TemplateBuildSeconds` = 1.91 s warm (2.18 s on the first Play with another agent's Studio running); `IncompleteTemplates` = `""`; `MissingAccessories` = `""` for all six.
- Leg-garment standoff at runtime (chroma silhouettes, leg garments only on a labelled body, p95 distance outside the body, studs, high kick / splits / deep crouch / lunge / front kick):

| | Kael | Sierra | Goran | Lumi | Rhys | Nia |
|---|---|---|---|---|---|---|
| OV5 | 0.11-0.12 | 0.09-0.11 | 0.23-0.48 | **0.29-0.68** | 0.14-0.20 | **0.32-0.60** |
| OV6 | 0.12-0.13 | 0.10-0.12 | 0.14-0.27 | **0.08-0.09** | 0.14-0.21 | **0.08-0.09** |

## Evidence (`OV6\handoff\characters-shots\`)

- `before-vs-after-<Id>.jpg` (6): OV5 vs OV6 round 2, same runtime camera and in-game light, front/3-4/back/face/shout/guard/high kick/crouch.
- `lookbook-<Id>.jpg` (6), `faces-after.jpg` (neutral/determined/shout/pain), `wide-poses-before.jpg` / `wide-poses-after.jpg` (A, guard, high kick, front kick, deep crouch, lunge, splits, lying), `lineups.jpg` (OV5, round 1, round 2) — all round 2.
- Round 2 head checks: `heads-r1-vs-r2.jpg` (front/face/guard, same cameras), `lineup-heads-r1-vs-r2.jpg` (lineup upper bodies at full resolution), `fightcam-r1-vs-r2.jpg` (CameraDirector framing at separation 7 and 3.2, FOV 36), `head-angles-r2.jpg` (look up/down/turn with a shout).
- `legwear-before-overlay.jpg` / `legwear-final-overlay.jpg` (+ `.json`, `.txt`): standoff maps for leg garments only; `outfit-standoff-*`: same for the complete outfit (includes shoes, belts, sash). Unaffected by head scale.
- `round1\`: the round-1 versions of the sheets above plus the lobby plaza shots (`lobby-*.jpg`, describe + dressCharacter avatars and the real SelectFighter -> AvatarService path; round-1 heads, same code path).

## Known issues

- Goran's beard is a rigid accessory: it does not follow the jaw on wide-open expressions (light colour keeps it subtle). His tank texture has two small distressed holes on the back.
- Lumi's January Model Doll head has painted pink blush.
- Kael's satin trunks are glossy by design (satin boxing trunks); everything else is matte/PBR.
- Rhys's gi is one layered item (jacket + trousers); it is exempt from the static fit envelope and checked dynamically (0.14-0.21 studs).
- The sash texture cannot be tinted (rigid TextureID accessory); it reads deep purple, gold stays on the top and bracers.

## REQUESTs

- integrator: apply the four files in `characters-src` (round 2 changed `CharacterSpecs` and `CharacterLook_Test`; Factory and Boot are as in round 1).
- integrator (`RF.Credits`, `tools\gen_credits.py`) — integrator is handling it: regenerate credits from `OV6\handoff\characters` (81 unique items, unchanged in round 2). `ascii_clean` drops look-alike glyphs: creator "Рort Royal" (Cyrillic Р) renders as "ort Royal" and "Deki’s UGC" as "Deki s UGC"; please transliterate (Р->P, ’->') before stripping.
- combat (`RF.Roster`), optional: `look` strings to match the new outfits:
  - Kael: unchanged.
  - Sierra: "Adult woman, lean kickboxer build, fair skin, platinum high ponytail with swept fringe; teal striped training tank over a black sports bra, deep-teal satin kickboxing trunks with black waistband, brown vintage leather boxing gloves, barefoot."
  - Goran: "Adult man, very broad heavyweight build, tan skin, shaved head, trimmed light-brown full beard; deep-red ribbed muscle tank, grey camo fight shorts, black leather lifting belt, black tactical knee pads, red wrist sweatbands, light-brown suede combat boots, open grappler hands."
  - Lumi: "Adult woman, light long-limbed build, deep brown skin, brown eyes, black curly taper with a sports band; olive crop tank, black ribbed techwear arm sleeves, mint slim-fit track pants tucked into black/grey camo tech sneakers, open hands."
  - Rhys: "Adult man, lean athletic build, light skin, dark brown undercut ponytail, clean-shaven; deep-indigo karate gi over a grey training tee, black belt, white cloth hand wraps, barefoot. Do NOT use a white gi, a torn sleeveless gi or any headband."
  - Nia: "Adult woman, compact athletic build, fair skin, black chin-length bob; black cropped mandarin-collar top with gold embroidery and laced gold bracers, deep-purple wrapped waist sash, purple tapered training pants, soft dark slip-on shoes, open hands. Do NOT use a qipao/cheongsam, buns with ribbons, or pigtails."
  - `stats.height` (MotionPlayer fallback only) could follow the round-2 statures: Kael 5.95, Sierra 5.85, Goran 6.75, Lumi 5.9, Rhys 5.9, Nia 5.5.
