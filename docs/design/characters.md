# Characters (OV6) — handoff

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
