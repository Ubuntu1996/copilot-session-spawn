param(
    [string]$BaseDir,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

function Quote-PowerShellSingle {
    param([Parameter(Mandatory)][string]$Value)
    return "'" + ($Value -replace "'", "''") + "'"
}

$hookRoot = Join-Path $HOME ".copilot\hooks"
Ensure-Directory -Path $hookRoot
$spawnRoot = Get-SpawnRoot -BaseDir $BaseDir
Ensure-SpawnRoot -Root $spawnRoot

$hookPath = Join-Path $hookRoot "session-spawn.json"
if ((Test-Path -LiteralPath $hookPath) -and -not $Force) {
    throw "Hook file already exists at $hookPath. Re-run with -Force to overwrite."
}

$recordScript = Join-Path $PSScriptRoot "record-session-context.ps1"
$baseArg = ""
if (-not [string]::IsNullOrWhiteSpace($BaseDir)) {
    $baseArg = " -BaseDir $(Quote-PowerShellSingle $spawnRoot)"
}

function New-HookCommand {
    param([Parameter(Mandatory)][string]$Event)
    return "& $(Quote-PowerShellSingle $recordScript) -Event $Event$baseArg"
}

$config = [ordered]@{
    version = 1
    hooks = [ordered]@{
        sessionStart = @(
            [ordered]@{
                type = "command"
                powershell = New-HookCommand -Event "sessionStart"
                timeoutSec = 5
            }
        )
        userPromptSubmitted = @(
            [ordered]@{
                type = "command"
                powershell = New-HookCommand -Event "userPromptSubmitted"
                timeoutSec = 5
            }
        )
        agentStop = @(
            [ordered]@{
                type = "command"
                powershell = New-HookCommand -Event "agentStop"
                timeoutSec = 20
            }
        )
        preCompact = @(
            [ordered]@{
                type = "command"
                powershell = New-HookCommand -Event "preCompact"
                timeoutSec = 20
            }
        )
    }
}

Write-JsonFile -Value $config -Path $hookPath -Depth 20

[ordered]@{
    hookPath = $hookPath
    spawnRoot = $spawnRoot
    launcher = (Join-Path $PSScriptRoot "copilot-spawn.ps1")
    note = "Restart Copilot CLI for hook changes to load."
} | ConvertTo-Json -Depth 10
