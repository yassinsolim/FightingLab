# Regenerates the data modules that come from files in this repo, then run tools/apply-sources.ps1 to put them in the place:
#   characters/*.json            -> src/ServerStorage.FightingLab.CharacterSpecs.luau (fighter looks)
#   characters/ + data/ + clips  -> src/ReplicatedStorage.FightingLab.Credits.luau and CREDITS.md
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$src = Join-Path $repo 'src'

$entries = @()
foreach ($id in 'Kael', 'Sierra', 'Goran', 'Lumi', 'Rhys', 'Nia') {
    $entries += @('--entry', ("$id=" + (Join-Path $repo "characters\$id.json")))
}
python (Join-Path $PSScriptRoot 'json_to_luau.py') --out (Join-Path $src 'ServerStorage.FightingLab.CharacterSpecs.luau') @entries
if ($LASTEXITCODE -ne 0) { throw 'json_to_luau.py failed' }

python (Join-Path $PSScriptRoot 'gen_credits.py') --specs (Join-Path $repo 'characters') --out (Join-Path $repo 'CREDITS.md') `
    --external (Join-Path $repo 'data\credits-external.json') --world-assets (Join-Path $repo 'data\world-assets.json') `
    --clip-src $src --luau-out (Join-Path $src 'ReplicatedStorage.FightingLab.Credits.luau')
if ($LASTEXITCODE -ne 0) { throw 'gen_credits.py failed' }
git -C $repo status --short -- src CREDITS.md
