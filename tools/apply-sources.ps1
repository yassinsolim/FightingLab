param([string]$Place = (Join-Path (Split-Path -Parent $PSScriptRoot) 'FightingLab.rbxlx'))
# Writes the scripts in src/ back into the place. Only script Source text changes; everything else in the file is kept
# byte for byte. Close the place in Roblox Studio first, or Studio will overwrite the result on its next save.
# New files create ModuleScripts; name them <Path>.server.luau / <Path>.client.luau for a Script / LocalScript.
# Scripts under the game's own folders that no longer have a file in src/ are removed from the place (at most 10 per
# run, as a guard against an incomplete src folder).
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$src = Join-Path $repo 'src'
$placePath = (Resolve-Path $Place).Path
$tmp = "$placePath.tmp"
$report = python (Join-Path $PSScriptRoot 'apply_sources_xml.py') --place $placePath --out $tmp --src $src
if ($LASTEXITCODE -ne 0) {
    Remove-Item $tmp -ErrorAction SilentlyContinue
    $report
    throw 'apply_sources_xml.py failed'
}
$report | Where-Object { $_ -notmatch '^unchanged' }

$prefixes = @('ReplicatedStorage.FightingLab', 'ServerScriptService.FightingLabServer',
    'ServerScriptService.FightingLabCharacterBoot', 'ServerScriptService.FightingLabWorldBoot',
    'ServerStorage.FightingLab', 'ServerStorage.UnitTest', 'StarterPlayer.StarterPlayerScripts.FightingLabClient')
$pruned = "$placePath.pruned"
$py = @((Join-Path $PSScriptRoot 'prune_scripts.py'), '--place', $tmp, '--out', $pruned, '--src', $src)
foreach ($p in $prefixes) { $py += @('--prefix', $p) }
$pruneReport = python @py
if ($LASTEXITCODE -ne 0) {
    Remove-Item $tmp, $pruned -ErrorAction SilentlyContinue
    $pruneReport
    throw 'prune_scripts.py failed'
}
$pruneReport | Where-Object { $_ -match '^removed' }
Move-Item $pruned $placePath -Force
Remove-Item $tmp -ErrorAction SilentlyContinue
"applied src/ to $placePath"
