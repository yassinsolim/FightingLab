param([string]$Place = (Join-Path (Split-Path -Parent $PSScriptRoot) 'FightingLab.rbxlx'))
# Writes the scripts in src/ back into the place. Only script Source text changes; everything else in the file is kept
# byte for byte. Close the place in Roblox Studio first, or Studio will overwrite the result on its next save.
# New files create ModuleScripts; name them <Path>.server.luau / <Path>.client.luau for a Script / LocalScript.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$placePath = (Resolve-Path $Place).Path
$tmp = "$placePath.tmp"
$report = python (Join-Path $PSScriptRoot 'apply_sources_xml.py') --place $placePath --out $tmp --src (Join-Path $repo 'src')
if ($LASTEXITCODE -ne 0) {
    Remove-Item $tmp -ErrorAction SilentlyContinue
    $report
    throw 'apply_sources_xml.py failed'
}
$report | Where-Object { $_ -notmatch '^unchanged' }
Move-Item $tmp $placePath -Force
"applied src/ to $placePath"
