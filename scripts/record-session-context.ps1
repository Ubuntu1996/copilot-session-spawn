param(
    [Parameter(Mandatory)]
    [ValidateSet("sessionStart", "userPromptSubmitted", "agentStop", "preCompact")]
    [string]$Event,

    [string]$BaseDir
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) {
    return
}

try {
    $payload = $raw | ConvertFrom-Json -Depth 100
}
catch {
    return
}

$sessionId = [string](Get-FirstObjectProperty -Object $payload -Names @("sessionId", "session_id"))
if ([string]::IsNullOrWhiteSpace($sessionId)) {
    return
}
$sessionId = Assert-SpawnSessionId -SessionId $sessionId

$root = Get-SpawnRoot -BaseDir $BaseDir
Ensure-SpawnRoot -Root $root
$sessionRoot = Join-Path $root "sessions"
$sessionDir = Join-Path $sessionRoot $sessionId
Ensure-Directory -Path $sessionDir

$metadataPath = Join-Path $sessionDir "metadata.json"
$metadata = Read-JsonHashtable -Path $metadataPath

$cwd = [string](Get-FirstObjectProperty -Object $payload -Names @("cwd", "workingDirectory", "working_directory"))
$timestamp = Get-FirstObjectProperty -Object $payload -Names @("timestamp")
$transcriptPath = [string](Get-FirstObjectProperty -Object $payload -Names @("transcriptPath", "transcript_path"))
$source = [string](Get-FirstObjectProperty -Object $payload -Names @("source"))

if (-not [string]::IsNullOrWhiteSpace($cwd)) {
    $metadata["cwd"] = $cwd
}
if (-not [string]::IsNullOrWhiteSpace($source)) {
    $metadata["source"] = $source
}
if (-not [string]::IsNullOrWhiteSpace($transcriptPath)) {
    $metadata["transcriptPath"] = $transcriptPath
}

$metadata["sessionId"] = $sessionId
$sessionName = Get-CopilotSessionName -SessionId $sessionId
if (-not [string]::IsNullOrWhiteSpace($sessionName)) {
    $metadata["name"] = $sessionName
}
$metadata["lastHookEvent"] = $Event
$metadata["lastHookTimestamp"] = $timestamp
$metadata["updatedAt"] = Get-IsoTimestamp

if ($Event -eq "sessionStart") {
    $metadata["startedAt"] = $metadata["updatedAt"]
}

if ($Event -eq "userPromptSubmitted") {
    $prompt = [string](Get-FirstObjectProperty -Object $payload -Names @("prompt", "initialPrompt", "initial_prompt"))
    if ($null -ne $prompt) {
        $promptPath = Join-Path $sessionDir "latest-prompt.txt"
        Write-RawTextFileAtomic -Text (Protect-ContextText -Text $prompt) -Path $promptPath
        $metadata["latestPromptPath"] = $promptPath
        $metadata["latestPromptCapturedAt"] = $metadata["updatedAt"]
        $metadata["latestPromptStatus"] = "in_progress"
    }
}

if ($Event -eq "agentStop") {
    $metadata["latestPromptStatus"] = "completed"
    $metadata["lastCompletedAt"] = $metadata["updatedAt"]
}

Write-JsonFile -Value $metadata -Path $metadataPath -Depth 50

$active = [ordered]@{
    sessionId = $sessionId
    cwd = $metadata["cwd"]
    sessionDir = $sessionDir
    updatedAt = Get-IsoTimestamp
    latestPromptPath = if ($metadata.Contains("latestPromptPath")) { $metadata["latestPromptPath"] } else { $null }
    contextCompactPath = if ($metadata.Contains("contextCompactPath")) { $metadata["contextCompactPath"] } else { $null }
    manifestPath = if ($metadata.Contains("manifestPath")) { $metadata["manifestPath"] } else { $null }
}
Write-JsonFile -Value $active -Path (Join-Path $root "active-session.json") -Depth 30

# Keep hooks lightweight: context export is performed on demand by copilot-spawn.ps1.
