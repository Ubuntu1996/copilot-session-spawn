param(
    [Parameter(Position = 0)]
    [string]$Topic,

    [string]$ParentSessionId,
    [string]$TopicFile,
    [string]$BaseDir,
    [switch]$PrintOnly,
    [switch]$CopyCommand,
    [switch]$NoNewTab
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

if ([string]::IsNullOrWhiteSpace($Topic)) {
    $Topic = "Side topic"
}
if (-not [string]::IsNullOrWhiteSpace($TopicFile)) {
    $Topic = Get-Content -LiteralPath $TopicFile -Raw
}

$root = Get-SpawnRoot -BaseDir $BaseDir
Ensure-SpawnRoot -Root $root
$activePath = Join-Path $root "active-session.json"
if ([string]::IsNullOrWhiteSpace($ParentSessionId)) {
    if (-not (Test-Path -LiteralPath $activePath)) {
        throw "No active parent session was recorded. Install hooks and restart Copilot CLI, or pass -ParentSessionId."
    }
    $active = Read-JsonHashtable -Path $activePath
    $ParentSessionId = [string]$active["sessionId"]
}

if ([string]::IsNullOrWhiteSpace($ParentSessionId)) {
    throw "Parent session id is empty."
}
$ParentSessionId = Assert-SpawnSessionId -SessionId $ParentSessionId -ParameterName "ParentSessionId"

$parentDir = Join-Path (Join-Path $root "sessions") $ParentSessionId
$metadataPath = Join-Path $parentDir "metadata.json"
if (-not (Test-Path -LiteralPath $metadataPath)) {
    throw "No metadata found for parent session $ParentSessionId at $metadataPath."
}

$metadata = Read-JsonHashtable -Path $metadataPath
$transcriptPath = if ($metadata.Contains("transcriptPath")) { [string]$metadata["transcriptPath"] } else { "" }
if (-not [string]::IsNullOrWhiteSpace($transcriptPath)) {
    & (Join-Path $PSScriptRoot "export-context.ps1") -SessionId $ParentSessionId -BaseDir $root -TranscriptPath $transcriptPath
}

$metadata = Read-JsonHashtable -Path $metadataPath
$contextCompactPath = if ($metadata.Contains("contextCompactPath")) { [string]$metadata["contextCompactPath"] } else { Join-Path $parentDir "context-compact.md" }
if (-not (Test-Path -LiteralPath $contextCompactPath)) {
    throw "No compact context bundle found for parent session $ParentSessionId. The parent session needs at least one hook event with transcript context."
}

$cwd = if ($metadata.Contains("cwd")) { [string]$metadata["cwd"] } else { (Get-Location).Path }
if ([string]::IsNullOrWhiteSpace($cwd) -or -not (Test-Path -LiteralPath $cwd)) {
    $cwd = (Get-Location).Path
}

$childSessionId = [guid]::NewGuid().ToString()
$safeTopic = ($Topic -replace '[\r\n]+', ' ').Trim()
if ($safeTopic.Length -gt 80) {
    $safeTopic = $safeTopic.Substring(0, 80)
}
$childName = "Fork: $safeTopic"

$childrenDir = Join-Path $parentDir "children"
$childDir = Join-Path $childrenDir $childSessionId
Ensure-Directory -Path $childDir

$importPrompt = @"
Start a side-topic child session forked from parent session $ParentSessionId.
Read @$contextCompactPath as inherited context.
Do not re-answer old transcript.
First acknowledge the fork in one short sentence, then answer the side topic using the inherited context.
Side topic: $Topic
"@

$copilotArgs = @(
    "--session-id", $childSessionId,
    "--name", $childName,
    "-C", $cwd,
    "--add-dir", $parentDir,
    "-i", $importPrompt
)

$argsPath = Join-Path $childDir "copilot-args.json"
Write-JsonFile -Value $copilotArgs -Path $argsPath -Depth 10

$launchScript = Join-Path $childDir "launch-child.ps1"
$launchScriptContent = @"
`$ErrorActionPreference = "Stop"
`$argsPath = Join-Path `$PSScriptRoot "copilot-args.json"
`$copilotArgs = [string[]](Get-Content -LiteralPath `$argsPath -Raw | ConvertFrom-Json)
& copilot @copilotArgs
"@
Write-RawTextFileAtomic -Text $launchScriptContent -Path $launchScript

$childManifest = [ordered]@{
    childSessionId = $childSessionId
    parentSessionId = $ParentSessionId
    topic = $Topic
    name = $childName
    cwd = $cwd
    createdAt = Get-IsoTimestamp
    contextCompactPath = $contextCompactPath
    launchScript = $launchScript
    argsPath = $argsPath
    publicCliArgs = $copilotArgs
}
Write-JsonFile -Value $childManifest -Path (Join-Path $childDir "child-manifest.json") -Depth 50
Add-TextFileLocked -Line ($childManifest | ConvertTo-Json -Depth 50 -Compress) -Path (Join-Path $parentDir "children.jsonl")

$preview = "pwsh -NoExit -File " + (ConvertTo-PowerShellSingleQuoted -Value $launchScript)
if ($CopyCommand) {
    $preview | Set-Clipboard
}

if ($PrintOnly) {
    [ordered]@{
        childSessionId = $childSessionId
        parentSessionId = $ParentSessionId
        launchScript = $launchScript
        command = $preview
        contextCompactPath = $contextCompactPath
    } | ConvertTo-Json -Depth 20
    return
}

if (-not $NoNewTab) {
    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($null -ne $wt) {
        & $wt.Source @("new-tab", "--title", $childName, "pwsh", "-NoExit", "-File", $launchScript) | Out-Null
    }
    else {
        $quotedLaunchScript = '"' + ($launchScript -replace '"', '\"') + '"'
        Start-Process -FilePath "pwsh" -ArgumentList "-NoExit -File $quotedLaunchScript" | Out-Null
    }
}
else {
    $quotedLaunchScript = '"' + ($launchScript -replace '"', '\"') + '"'
    Start-Process -FilePath "pwsh" -ArgumentList "-NoExit -File $quotedLaunchScript" | Out-Null
}

[ordered]@{
    childSessionId = $childSessionId
    parentSessionId = $ParentSessionId
    launchScript = $launchScript
    command = $preview
    contextCompactPath = $contextCompactPath
} | ConvertTo-Json -Depth 20
