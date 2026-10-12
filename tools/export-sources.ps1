param([string]$Place = (Join-Path (Split-Path -Parent $PSScriptRoot) 'FightingLab.rbxlx'))
# Exports every game script from the place into src/ (a mirror), so git shows script changes after you edit in Studio.
# Save the place in Studio first so the .rbxlx on disk is current.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$src = Join-Path $repo 'src'
$placePath = (Resolve-Path $Place).Path
$tmp = Join-Path $env:TEMP ('fightinglab-export-' + [guid]::NewGuid().ToString('N'))

$prefixes = @('ReplicatedStorage.FightingLab', 'ServerScriptService.FightingLabServer',
    'ServerScriptService.FightingLabCharacterBoot', 'ServerScriptService.FightingLabWorldBoot',
    'ServerStorage.FightingLab', 'ServerStorage.UnitTest', 'StarterPlayer.StarterPlayerScripts.FightingLabClient')
$py = @((Join-Path $PSScriptRoot 'extract_sources.py'), '--place', $placePath, '--out', $tmp)
foreach ($p in $prefixes) { $py += @('--prefix', $p) }
python @py
if ($LASTEXITCODE -ne 0) { throw 'extract_sources.py failed' }

Get-ChildItem $src -Filter *.luau | Remove-Item
Copy-Item (Join-Path $tmp '*') $src -Force
Remove-Item $tmp -Recurse -Force

$env:FL_SRC = $src
@'
import datetime, json, os
d = os.environ["FL_SRC"]
paths = sorted(f[:-5] for f in os.listdir(d) if f.endswith(".luau"))
manifest = {"count": len(paths), "exportedFrom": f"FightingLab.rbxlx (exported {datetime.date.today().isoformat()})",
            "paths": paths}
with open(os.path.join(d, "export-manifest.json"), "w", encoding="utf-8", newline="\n") as fh:
    json.dump(manifest, fh, indent=2)
print(f"src: {len(paths)} scripts")
'@ | python -
git -C $repo status --short -- src
