param(
    [Parameter(Mandatory)][string]$SessionId,
    [string]$BaseDir,
    [string]$TranscriptPath,
    [int]$MaxRecentEvents = 80,
    [int]$MaxEventChars = 4000,
    [int]$MaxCompactChars = 80000
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")
$SessionId = Assert-SpawnSessionId -SessionId $SessionId

function New-NormalizedEvent {
    param(
        [string]$Timestamp,
        [string]$Type,
        [string]$Role,
        [string]$Summary,
        [string]$Content
    )

    [ordered]@{
        timestamp = $Timestamp
        type = $Type
        role = $Role
        summary = Protect-ContextText -Text (Limit-Text -Text $Summary -MaxChars 800)
        content = Protect-ContextText -Text (Limit-Text -Text $Content -MaxChars $MaxEventChars)
    }
}

function Add-EventMarkdown {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        $Event
    )

    $title = "### [$($Event.timestamp)] $($Event.role) / $($Event.type)"
    $Lines.Add($title)
    if (-not [string]::IsNullOrWhiteSpace($Event.summary)) {
        $Lines.Add("")
        $Lines.Add($Event.summary)
    }
    if (-not [string]::IsNullOrWhiteSpace($Event.content)) {
        $eventFence = Get-MarkdownFence -Text $Event.content
        $Lines.Add("")
        $Lines.Add("${eventFence}text")
        $Lines.Add($Event.content)
        $Lines.Add($eventFence)
    }
    $Lines.Add("")
}

function Read-JsonLines {
    param([Parameter(Mandatory)][string]$Path)

    $records = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $Path)) {
        return $records
    }

    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        try {
            $records.Add(($line | ConvertFrom-Json -Depth 100))
        }
        catch {
            continue
        }
    }
    return $records
}

function Add-MergedChildSection {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$SessionDir,
        [int]$MaxMergeChars = 3000
    )

    $mergedPath = Join-Path $SessionDir "merged-children.jsonl"
    $records = @(Read-JsonLines -Path $mergedPath)
    if ($records.Count -eq 0) {
        return
    }

    $Lines.Add("")
    $Lines.Add("## Merged child sessions")
    $Lines.Add("")
    foreach ($record in $records) {
        $childId = [string](Get-ObjectProperty -Object $record -Name "childSessionId")
        $childName = [string](Get-ObjectProperty -Object $record -Name "childName")
        $childTopic = [string](Get-ObjectProperty -Object $record -Name "childTopic")
        $mergeTime = [string](Get-ObjectProperty -Object $record -Name "mergeTime")
        $mergeContextPath = [string](Get-ObjectProperty -Object $record -Name "mergeContextPath")

        $Lines.Add("### $childName")
        $Lines.Add("")
        $Lines.Add("- Child session ID: $childId")
        $Lines.Add("- Child topic: $childTopic")
        $Lines.Add("- Merge time: $mergeTime")
        $Lines.Add("- Merge context file: $mergeContextPath")
        if (-not [string]::IsNullOrWhiteSpace($mergeContextPath) -and (Test-Path -LiteralPath $mergeContextPath)) {
            $mergeContextText = Get-Content -LiteralPath $mergeContextPath -Raw
            $mergeFence = Get-MarkdownFence -Text $mergeContextText
            $Lines.Add("")
            $Lines.Add("${mergeFence}markdown")
            $Lines.Add((Limit-Text -Text $mergeContextText -MaxChars $MaxMergeChars))
            $Lines.Add($mergeFence)
        }
        $Lines.Add("")
    }
}

function Get-NormalizedEvents {
    param([string]$Path)

    $events = [System.Collections.Generic.List[object]]::new()
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return $events
    }

    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        try {
            $obj = $line | ConvertFrom-Json -Depth 100
        }
        catch {
            continue
        }

        $type = [string](Get-ObjectProperty -Object $obj -Name "type")
        $timestamp = [string](Get-ObjectProperty -Object $obj -Name "timestamp")
        $data = Get-ObjectProperty -Object $obj -Name "data"

        switch ($type) {
            "user.message" {
                $content = Get-FirstObjectProperty -Object $data -Names @("transformedContent", "content")
                $events.Add((New-NormalizedEvent -Timestamp $timestamp -Type $type -Role "user" -Summary "User prompt" -Content (ConvertTo-SpawnText $content)))
            }
            "assistant.message" {
                $content = Get-ObjectProperty -Object $data -Name "content"
                $toolRequests = Get-ObjectProperty -Object $data -Name "toolRequests"
                $summary = "Assistant response"
                if ($null -ne $toolRequests) {
                    $summary = "Assistant response; tool requests: " + (Limit-Text -Text (ConvertTo-SpawnText $toolRequests) -MaxChars 800)
                }
                $events.Add((New-NormalizedEvent -Timestamp $timestamp -Type $type -Role "assistant" -Summary $summary -Content (ConvertTo-SpawnText $content)))
            }
            "tool.execution_start" {
                $toolName = [string](Get-ObjectProperty -Object $data -Name "toolName")
                $arguments = Get-ObjectProperty -Object $data -Name "arguments"
                $events.Add((New-NormalizedEvent -Timestamp $timestamp -Type $type -Role "tool_call" -Summary "Tool started: $toolName" -Content (ConvertTo-SpawnText $arguments)))
            }
            "tool.execution_complete" {
                $success = Get-ObjectProperty -Object $data -Name "success"
                $toolCallId = Get-ObjectProperty -Object $data -Name "toolCallId"
                $result = Get-ObjectProperty -Object $data -Name "result"
                $events.Add((New-NormalizedEvent -Timestamp $timestamp -Type $type -Role "tool_result" -Summary "Tool completed: $toolCallId success=$success" -Content (ConvertTo-SpawnText $result)))
            }
            "system.message" {
                $content = Get-ObjectProperty -Object $data -Name "content"
                $role = [string](Get-ObjectProperty -Object $data -Name "role")
                $events.Add((New-NormalizedEvent -Timestamp $timestamp -Type $type -Role "system" -Summary "System message role=$role" -Content (ConvertTo-SpawnText $content)))
            }
            "session.plan_changed" {
                $operation = Get-ObjectProperty -Object $data -Name "operation"
                $events.Add((New-NormalizedEvent -Timestamp $timestamp -Type $type -Role "session" -Summary "Plan changed" -Content (ConvertTo-SpawnText $operation)))
            }
            "session.mode_changed" {
                $events.Add((New-NormalizedEvent -Timestamp $timestamp -Type $type -Role "session" -Summary "Mode changed" -Content (ConvertTo-SpawnText $data)))
            }
            "permission.requested" {
                $events.Add((New-NormalizedEvent -Timestamp $timestamp -Type $type -Role "permission" -Summary "Permission requested" -Content (ConvertTo-SpawnText $data)))
            }
            "permission.completed" {
                $events.Add((New-NormalizedEvent -Timestamp $timestamp -Type $type -Role "permission" -Summary "Permission completed" -Content (ConvertTo-SpawnText $data)))
            }
            default {
                continue
            }
        }
    }

    return $events
}

$root = Get-SpawnRoot -BaseDir $BaseDir
Ensure-SpawnRoot -Root $root
$sessionDir = Join-Path (Join-Path $root "sessions") $SessionId
Ensure-Directory -Path $sessionDir

$metadataPath = Join-Path $sessionDir "metadata.json"
$metadata = Read-JsonHashtable -Path $metadataPath
if (-not [string]::IsNullOrWhiteSpace($TranscriptPath)) {
    $metadata["transcriptPath"] = $TranscriptPath
}
elseif ($metadata.Contains("transcriptPath")) {
    $TranscriptPath = [string]$metadata["transcriptPath"]
}

$events = Get-NormalizedEvents -Path $TranscriptPath
if (-not [string]::IsNullOrWhiteSpace($TranscriptPath) -and -not (Test-Path -LiteralPath $TranscriptPath)) {
    throw "Transcript path does not exist: $TranscriptPath"
}
$transcriptJsonlPath = Join-Path $sessionDir "transcript.jsonl"
$eventLines = foreach ($event in $events) {
    $event | ConvertTo-Json -Depth 30 -Compress
}
Write-TextFileAtomic -Lines @($eventLines) -Path $transcriptJsonlPath

$latestPromptPath = Join-Path $sessionDir "latest-prompt.txt"
$latestPrompt = ""
if (Test-Path -LiteralPath $latestPromptPath) {
    $latestPrompt = Get-Content -LiteralPath $latestPromptPath -Raw
}
$latestPromptStatus = if ($metadata.Contains("latestPromptStatus")) { [string]$metadata["latestPromptStatus"] } else { "" }
if ($events.Count -eq 0 -and [string]::IsNullOrWhiteSpace($latestPrompt)) {
    throw "No usable transcript events or latest prompt were available for session $SessionId."
}

$cwd = [string]($metadata["cwd"])
$snapshotTime = Get-IsoTimestamp
$eventCount = $events.Count
$recentStart = [Math]::Max(0, $eventCount - $MaxRecentEvents)
$recentEvents = @($events | Select-Object -Skip $recentStart)
$olderCount = [Math]::Max(0, $eventCount - $recentEvents.Count)

$fullLines = [System.Collections.Generic.List[string]]::new()
$fullLines.Add("# Parent Copilot session context")
$fullLines.Add("")
$fullLines.Add("Session ID: $SessionId")
$fullLines.Add("Working directory: $cwd")
$fullLines.Add("Snapshot time: $snapshotTime")
$fullLines.Add("Snapshot boundary: last completed agent turn plus latest submitted prompt if captured")
$fullLines.Add("Fork style: near-native public-feature fork")
$fullLines.Add("")
$fullLines.Add("## Conversation transcript")
$fullLines.Add("")
foreach ($event in $events) {
    Add-EventMarkdown -Lines $fullLines -Event $event
}

$compactLines = [System.Collections.Generic.List[string]]::new()
$compactLines.Add("# Parent Copilot session context")
$compactLines.Add("")
$compactLines.Add("Session ID: $SessionId")
$compactLines.Add("Working directory: $cwd")
$compactLines.Add("Snapshot time: $snapshotTime")
$compactLines.Add("Snapshot boundary: last completed agent turn plus latest submitted prompt if captured")
$compactLines.Add("Fork style: near-native public-feature fork")
$compactLines.Add("")
$compactLines.Add("## How to use this context")
$compactLines.Add("")
$compactLines.Add("Treat this as inherited parent-session memory. Do not re-answer old parent prompts.")
$compactLines.Add("Use prior decisions, constraints, files, commands, and unresolved questions as background.")
$compactLines.Add("The child session is independent from the parent after this fork point.")
$compactLines.Add("")
Add-MergedChildSection -Lines $compactLines -SessionDir $sessionDir -MaxMergeChars 2500
$compactLines.Add("")
$compactLines.Add("## Older context")
$compactLines.Add("")
if ($olderCount -gt 0) {
    $compactLines.Add("$olderCount older normalized events were omitted from this compact seed. See context-full.md and transcript.jsonl if more detail is needed.")
}
else {
    $compactLines.Add("No older events were omitted.")
}
$compactLines.Add("")
$compactLines.Add("## Recent role-preserving transcript")
$compactLines.Add("")
foreach ($event in $recentEvents) {
    Add-EventMarkdown -Lines $compactLines -Event $event
}
$compactLines.Add("")
$compactLines.Add("## In-flight parent prompt, if any")
$compactLines.Add("")
if ([string]::IsNullOrWhiteSpace($latestPrompt) -or $latestPromptStatus -ne "in_progress") {
    $compactLines.Add("No parent prompt is currently marked as in progress.")
}
else {
    $latestPromptFence = Get-MarkdownFence -Text $latestPrompt
    $compactLines.Add("The latest submitted parent prompt may still be in progress if this fork was created while the parent was busy:")
    $compactLines.Add("")
    $compactLines.Add("${latestPromptFence}text")
    $compactLines.Add((Protect-ContextText -Text (Limit-Text -Text $latestPrompt -MaxChars 8000)))
    $compactLines.Add($latestPromptFence)
}
if (-not [string]::IsNullOrWhiteSpace($latestPrompt) -and $latestPromptStatus -ne "in_progress") {
    $completedPromptFence = Get-MarkdownFence -Text $latestPrompt
    $compactLines.Add("")
    $compactLines.Add("## Latest completed parent prompt")
    $compactLines.Add("")
    $compactLines.Add("The latest submitted parent prompt appears completed and is included as background only:")
    $compactLines.Add("")
    $compactLines.Add("${completedPromptFence}text")
    $compactLines.Add((Protect-ContextText -Text (Limit-Text -Text $latestPrompt -MaxChars 8000)))
    $compactLines.Add($completedPromptFence)
}
$compactLines.Add("")
$compactLines.Add("## Durable work context")
$compactLines.Add("")
$compactLines.Add("- Parent cwd: $cwd")
$compactLines.Add("- Parent session id: $SessionId")
$compactLines.Add("- Full context file: context-full.md")
$compactLines.Add("- Normalized transcript file: transcript.jsonl")
$compactLines.Add("- Fork manifest: fork-manifest.json")
$compactLines.Add("")
$compactLines.Add("## Instructions for child session")
$compactLines.Add("")
$compactLines.Add("You are a side-topic child session. Use this context as background only.")
$compactLines.Add("Do not modify the parent session. Continue independently from here.")

$contextFullPath = Join-Path $sessionDir "context-full.md"
$contextCompactPath = Join-Path $sessionDir "context-compact.md"
Write-TextFileAtomic -Lines @($fullLines) -Path $contextFullPath

$compactText = ($compactLines -join "`n")
if ($compactText.Length -gt $MaxCompactChars) {
    $compactText = $compactText.Substring(0, $MaxCompactChars) + "`n`n[compact context truncated]"
}
Write-RawTextFileAtomic -Text $compactText -Path $contextCompactPath

$manifestPath = Join-Path $sessionDir "fork-manifest.json"
$manifest = [ordered]@{
    bundleVersion = 1
    parentSessionId = $SessionId
    cwd = $cwd
    snapshotTime = $snapshotTime
    snapshotBoundary = "last_completed_turn_plus_latest_prompt"
    transcriptPath = $TranscriptPath
    eventCount = $eventCount
    olderOmittedEventCount = $olderCount
    recentEventCount = $recentEvents.Count
    files = [ordered]@{
        manifest = $manifestPath
        transcript = $transcriptJsonlPath
        contextFull = $contextFullPath
        contextCompact = $contextCompactPath
        latestPrompt = $latestPromptPath
    }
}
Write-JsonFile -Value $manifest -Path $manifestPath -Depth 50

$metadata["updatedAt"] = $snapshotTime
$metadata["contextCompactPath"] = $contextCompactPath
$metadata["contextFullPath"] = $contextFullPath
$metadata["transcriptJsonlPath"] = $transcriptJsonlPath
$metadata["manifestPath"] = $manifestPath
$metadata["eventCount"] = $eventCount
Write-JsonFile -Value $metadata -Path $metadataPath -Depth 50
