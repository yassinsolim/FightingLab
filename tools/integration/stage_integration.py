"""Stage agent exports for integration: copy each agent's OWNED files into one folder, refuse silent conflicts.

  python stage_integration.py --out DIR --agent runtime --agent combat ... [--extra DIR]

Files an agent exports outside its ownership are reported and skipped. If two agents export the same owned path
(should only happen for files with a declared shared line, e.g. CombatConfig.LocalAuthority), the script stops so
the file can be merged by hand into an --extra directory (extra directories are applied last and win).
"""
import argparse
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ownership_report import BASE, HANDOFF, owner_of, read  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--agent", action="append", required=True)
    ap.add_argument("--extra", action="append", default=[])
    a = ap.parse_args()

    if os.path.isdir(a.out):
        shutil.rmtree(a.out)
    os.makedirs(a.out)
    chosen, skipped, conflicts = {}, [], []
    for agent in a.agent:
        d = os.path.join(HANDOFF, agent + "-src")
        if not os.path.isdir(d):
            raise SystemExit(f"missing export folder {d}")
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".luau"):
                continue
            path = fn[:-5]
            own = owner_of(path)
            if own != agent:
                skipped.append(f"{agent}: {path} (owner {own})")
                continue
            src = read(os.path.join(d, fn))
            base_file = os.path.join(BASE, fn)
            if os.path.exists(base_file) and read(base_file) == src:
                continue
            if path in chosen:
                conflicts.append(f"{path}: {chosen[path][0]} vs {agent}")
                continue
            chosen[path] = (agent, os.path.join(d, fn))
    for extra in a.extra:
        for fn in sorted(os.listdir(extra)):
            if fn.endswith(".luau"):
                chosen[fn[:-5]] = ("extra:" + os.path.basename(extra), os.path.join(extra, fn))
                conflicts = [c for c in conflicts if not c.startswith(fn[:-5] + ":")]
    if conflicts:
        print("CONFLICTS (merge by hand into an --extra dir):")
        print("\n".join("  " + c for c in conflicts))
        raise SystemExit(1)
    for path, (agent, src_path) in sorted(chosen.items()):
        shutil.copyfile(src_path, os.path.join(a.out, path + ".luau"))
        print(f"  {agent:>12}  {path}")
    for s in skipped:
        print(f"  SKIPPED non-owned export {s}")
    print(f"staged {len(chosen)} files into {a.out}")


if __name__ == "__main__":
    main()
