# mocap-research — handoff (Overhaul 6)

MOTION DATA READY: `OV6\research\motion\` — read `report.md` first, then `catalog.json`.

- 263 catalogued segments (ACCAD CC BY 3.0 = 116, CMU mocap terms = 131, Quaternius CC0 = 16), every entry has
  `license`, `credit`, `url`, `localFile`, `fps`, `start`/`end`/`contactFrame` (0-based file frames), `lead`, `stance`,
  `targetDirXZ` (toward opponent), `quality` 1–5 (set after looking at `sheets\<label>.png`).
- Best material: ACCAD Male2 martial artist (stances, step-in/out, dash/backdash cycles, sidesteps, ducks/dodges,
  blocks, jab/cross/hook/uppercut/body shots L+R, front/push/roundhouse/side/spinning/back/axe/crescent kicks,
  victory/taunt/bow); CMU 140 getups (face up/down/side), CMU 90_18/90_16 falls, CMU 135 karate kicks;
  Quaternius hit-head/hit-chest/hit-knockback/death/lay-to-idle (hand-keyed gap fillers).
- Gaps (hand-key these): mocap hit reactions (only subtle Quaternius flinches), low/leg hit, stagger, launch→land,
  throws/grapples, elbows, palm strikes, sweeps, low kicks, overhand.
- Loader + exporter: `tools\mocap.py` (ASF/AMC + BVH → world joint positions, meters, Y-up),
  `tools\export_clip.py <id…> --fps 60` (canonical 24 joints in opponent-aligned frame, contactFrame re-based).
  Check: `python tools\verify_catalog.py` → `[VERIFY] 263 entries, 162 files parsed, 0 errors`.
- Credits (REQUEST to integrator, `RF.Credits`): ACCAD line, CMU acknowledgement line, optional Quaternius line —
  exact text in `report.md` §1. Only add the lines for sources actually shipped.
