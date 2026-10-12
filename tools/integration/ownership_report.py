"""Report what each agent changed versus the pristine baseline and flag edits outside the contract ownership.

  python ownership_report.py
"""
import difflib
import os

FILES = r"C:\Users\solim\.copilot\session-state\e3751321-5f48-4183-b62a-9577765df8cf\files"
OV3 = os.path.join(FILES, "overhaul6")
BASE = os.path.join(OV3, "baseline-src")
HANDOFF = os.path.join(OV3, "handoff")
SHARED = os.path.join(FILES, "FightingLab-source")

RF = "ReplicatedStorage.FightingLab."
CL = RF + "Client."
UT = "ServerStorage.UnitTest.Cases."
# Overhaul 6 ownership (CONTRACTS-v6.md section 5). Everything not listed belongs to the integrator (--extra overlays).
# Entries ending in "." are prefixes; entries ending in "*" match any path starting with the text before the "*".
OWNERS = {
    "combat": [RF + "CombatSim", RF + "CombatConfig", RF + "CombatAI", RF + "Roster", RF + "MatchRunner", RF + "RenderBuffer",
               RF + "SnapshotTiming", RF + "NetProtocol", RF + "Controls", CL + "InputController",
               UT + "CombatSim_Test", UT + "CombatRoster_Test", UT + "Difficulty_Test", UT + "MatchRunner_Test",
               UT + "RenderBuffer_Test", UT + "SnapshotTiming_Test", UT + "DuelProtocol_Test", UT + "Combat*",
               UT + "AI*", UT + "Balance*", UT + "Controls_Test"],
    "motioncore": [CL + "MotionPlayer", CL + "MotionLibrary", CL + "Motion.States", CL + "Motion.Clips.Core.",
                   CL + "Motion.ClipPlayer", CL + "Motion.ClipLibrary", CL + "CharacterPresenter", CL + "CameraDirector",
                   CL + "EffectsController", CL + "AudioController", CL + "FighterLighting", CL + "FaceController",
                   UT + "MotionPlayer_Test", UT + "VfxFeel_Test", UT + "VfxV2_Test", UT + "FaceController_Test",
                   UT + "MotionCore*", UT + "MotionClip*", UT + "MotionGround*", UT + "Camera*"],
    # Phase 2 move animation is split by category across all fighters (strikes / kicks / throws).
    "motionstrikes": [CL + "Motion.Strikes", CL + "Motion.MoveAnimOverrides", CL + "Motion.Clips.Moves.Strikes.",
                      UT + "MotionStrikes*", UT + "MotionMovesStrikes*"],
    "motionkicks": [CL + "Motion.Kicks", CL + "Motion.Clips.Moves.Kicks.", UT + "MotionKicks*", UT + "MotionMovesKicks*"],
    "motionthrows": [CL + "Motion.Throws", CL + "Motion.Clips.Moves.Throws.", UT + "MotionThrows*",
                     UT + "MotionMovesThrows*"],
    "ui": [CL + "FrontEnd", CL + "LobbyUI", CL + "FighterSelect", CL + "StationBoards", CL + "Leaderboard",
           CL + "CreditsScreen", CL + "MoveList", CL + "UIHelpers", CL + "UIState", CL + "SelectScene", CL + "ArcadeMode",
           CL + "HudController", UT + "UIFrontend_Test", UT + "SelectScene_Test", UT + "CreditsScreen_Test",
           UT + "LobbyUI_Test", UT + "UI*", UT + "Hud*"],
    "world": ["ServerScriptService.FightingLabWorldBoot", "ServerStorage.FightingLab.World.", CL + "LightingProfile",
              CL + "LobbyAmbience", UT + "World_Test"],
    "characters": ["ServerStorage.FightingLab.CharacterFactory", "ServerStorage.FightingLab.CharacterSpecs",
                   "ServerScriptService.FightingLabCharacterBoot", UT + "CharacterLook_Test"],
}


def owner_of(path):
    # Script files carry a class suffix (.server / .client) that is not part of the Roblox path.
    for suffix in (".server", ".client"):
        if path.endswith(suffix):
            path = path[: -len(suffix)]
    hits = [a for a, pats in OWNERS.items() for p in pats
            if path == p or (p.endswith(".") and path.startswith(p)) or (p.endswith("*") and path.startswith(p[:-1]))]
    return hits[0] if hits else None


def read(p):
    with open(p, encoding="utf-8") as fh:
        return fh.read()


def changed_lines(old, new):
    sm = difflib.SequenceMatcher(None, old.splitlines(), new.splitlines(), autojunk=False)
    return sum(max(i2 - i1, j2 - j1) for tag, i1, i2, j1, j2 in sm.get_opcodes() if tag != "equal")


def scan_dir(label, d):
    print(f"===== {label}")
    if not os.path.isdir(d):
        print("  (missing)")
        return {}
    out = {}
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".luau"):
            continue
        path = fn[:-5]
        new = read(os.path.join(d, fn))
        bp = os.path.join(BASE, fn)
        status = f"~{changed_lines(read(bp), new)} lines changed" if os.path.exists(bp) else f"NEW ({len(new.splitlines())} lines)"
        if os.path.exists(bp) and read(bp) == new:
            status = "identical to baseline"
        own = owner_of(path)
        flag = "" if (label.startswith("shared") or own == label.split("-")[0]) else f"   <-- owner is {own}"
        print(f"  {path}: {status}{flag}")
        out[path] = new
    return out


def main():
    exports = {}
    for agent in OWNERS:
        exports[agent] = scan_dir(agent, os.path.join(HANDOFF, agent + "-src"))
    shared = scan_dir("shared FightingLab-source", SHARED)
    print("===== shared folder changes not present in the owner's export")
    for path, src in sorted(shared.items()):
        bp = os.path.join(BASE, path + ".luau")
        if os.path.exists(bp) and read(bp) == src:
            continue
        own = owner_of(path)
        exported = exports.get(own, {}).get(path) if own else None
        if exported is None:
            print(f"  {path}: changed in shared folder, NOT in {own}-src")
        elif exported != src:
            print(f"  {path}: shared folder differs from {own}-src")


if __name__ == "__main__":
    main()
