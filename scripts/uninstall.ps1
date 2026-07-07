param(
    [switch]$DeleteData,
    [switch]$ForceDeleteData
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$hookPath = Join-Path (Join-Path $HOME ".copilot\hooks") "session-spawn.json"
if (Test-Path -LiteralPath $hookPath) {
    Remove-Item -LiteralPath $hookPath -Force
}

if ($DeleteData) {
    $spawnRoot = Get-SpawnRoot
    $markerPath = Join-Path $spawnRoot ".copilot-session-spawn-root"
    $fullRoot = [System.IO.Path]::GetFullPath($spawnRoot).TrimEnd('\')
    $homeRoot = [System.IO.Path]::GetFullPath($HOME).TrimEnd('\')

    if (-not $ForceDeleteData) {
        throw "Data deletion requires -ForceDeleteData. Re-run with -DeleteData -ForceDeleteData after verifying the path: $spawnRoot"
    }
    if (-not (Test-Path -LiteralPath $markerPath)) {
        throw "Refusing to delete $spawnRoot because the plugin marker file is missing."
    }
    if ($fullRoot -eq $homeRoot -or $fullRoot -match '^[A-Za-z]:$' -or (Split-Path -Leaf $fullRoot) -ne "spawn-sessions") {
        throw "Refusing to delete broad path: $spawnRoot"
    }
    if (Test-Path -LiteralPath $spawnRoot) {
        Remove-Item -LiteralPath $spawnRoot -Recurse -Force
    }
}

[ordered]@{
    removedHook = $hookPath
    deletedData = [bool]$DeleteData
    note = "Restart Copilot CLI for hook changes to unload."
} | ConvertTo-Json -Depth 10
