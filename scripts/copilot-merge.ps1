param(
    [Parameter(Position = 0)]
    [string]$ChildName,

    [string]$ChildSessionId,
    [string]$ChildQueryFile,
    [string]$ParentSessionId,
    [string]$BaseDir,
    [switch]$CopyPath,
    [switch]$AllowIncomplete
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

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

function Get-PropertyText {
    param(
        $Object,
        [Parameter(Mandatory)][string]$Name
    )

    $value = Get-ObjectProperty -Object $Object -Name $Name
    if ($null -eq $value) {
        return ""
    }
    return [string]$value
}

function ConvertTo-SingleLine {
    param(
        [AllowNull()][string]$Text,
        [int]$MaxChars = 300
    )

    if ($null -eq $Text) {
        return ""
    }

    return (Protect-ContextText -Text (Limit-Text -Text ($Text -replace '\s+', ' ').Trim() -MaxChars $MaxChars))
}

function Select-ChildRecord {
    param(
        [Parameter(Mandatory)]$Children,
        [AllowEmptyCollection()][string[]]$MergedIds,
        [string]$Query,
        [string]$ExplicitChildSessionId
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitChildSessionId)) {
        $id = Assert-SpawnSessionId -SessionId $ExplicitChildSessionId -ParameterName "ChildSessionId"
        $matches = @($Children | Where-Object { (Get-PropertyText -Object $_ -Name "childSessionId") -ieq $id })
        if ($matches.Count -eq 1) {
            return $matches[0]
        }
        throw "Child session $id was not found in this parent's children.jsonl."
    }

    $queryText = ""
    if (-not [string]::IsNullOrWhiteSpace($Query)) {
        $queryText = $Query.Trim()
    }

    if ([string]::IsNullOrWhiteSpace($queryText) -or $queryText -ieq "latest") {
        $unmerged = @($Children | Where-Object {
            $id = Get-PropertyText -Object $_ -Name "childSessionId"
            -not ($MergedIds -contains $id)
        })
        if ($unmerged.Count -eq 0) {
            throw "No unmerged child sessions were found for this parent. Pass a specific child session ID or name to re-merge."
        }
        return @($unmerged | Sort-Object { Get-PropertyText -Object $_ -Name "createdAt" } -Descending)[0]
    }

    $guidValue = [guid]::Empty
    if ([guid]::TryParse($queryText, [ref]$guidValue)) {
        $id = $guidValue.ToString()
        $matches = @($Children | Where-Object { (Get-PropertyText -Object $_ -Name "childSessionId") -ieq $id })
        if ($matches.Count -eq 1) {
            return $matches[0]
        }
        throw "Child session $id was not found in this parent's children.jsonl."
    }

    if ($queryText.Length -ge 7 -and $queryText -match '^[0-9A-Fa-f-]+$') {
        $matches = @($Children | Where-Object { (Get-PropertyText -Object $_ -Name "childSessionId").StartsWith($queryText, [StringComparison]::OrdinalIgnoreCase) })
        if ($matches.Count -eq 1) {
            return $matches[0]
        }
        if ($matches.Count -gt 1) {
            $ids = ($matches | ForEach-Object { Get-PropertyText -Object $_ -Name "childSessionId" }) -join ", "
            throw "Child session prefix '$queryText' is ambiguous. Matches: $ids"
        }
        throw "No child session ID prefix matched '$queryText'."
    }

    $exact = @($Children | Where-Object {
        (Get-PropertyText -Object $_ -Name "topic") -ieq $queryText -or
        (Get-PropertyText -Object $_ -Name "name") -ieq $queryText
    })
    if ($exact.Count -eq 1) {
        return $exact[0]
    }
    if ($exact.Count -gt 1) {
        $ids = ($exact | ForEach-Object { "$(Get-PropertyText -Object $_ -Name "childSessionId") ($(Get-PropertyText -Object $_ -Name "name"))" }) -join "; "
        throw "Child name '$queryText' is ambiguous. Matches: $ids"
    }

    $contains = @($Children | Where-Object {
        (Get-PropertyText -Object $_ -Name "topic").IndexOf($queryText, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        (Get-PropertyText -Object $_ -Name "name").IndexOf($queryText, [StringComparison]::OrdinalIgnoreCase) -ge 0
    })
    if ($contains.Count -eq 1) {
        return $contains[0]
    }
    if ($contains.Count -gt 1) {
        $ids = ($contains | ForEach-Object { "$(Get-PropertyText -Object $_ -Name "childSessionId") ($(Get-PropertyText -Object $_ -Name "name"))" }) -join "; "
        throw "Child name query '$queryText' is ambiguous. Matches: $ids"
    }

    throw "No child session matched '$queryText'."
}

$root = Get-SpawnRoot -BaseDir $BaseDir
Ensure-SpawnRoot -Root $root

if (-not [string]::IsNullOrWhiteSpace($ChildQueryFile)) {
    $ChildName = Get-Content -LiteralPath $ChildQueryFile -Raw
}

$activePath = Join-Path $root "active-session.json"
if ([string]::IsNullOrWhiteSpace($ParentSessionId)) {
    if (-not (Test-Path -LiteralPath $activePath)) {
        throw "No active parent session was recorded. Install hooks and restart Copilot CLI, or pass -ParentSessionId."
    }
    $active = Read-JsonHashtable -Path $activePath
    $ParentSessionId = [string]$active["sessionId"]
}
$ParentSessionId = Assert-SpawnSessionId -SessionId $ParentSessionId -ParameterName "ParentSessionId"

$parentDir = Join-Path (Join-Path $root "sessions") $ParentSessionId
$parentMetadataPath = Join-Path $parentDir "metadata.json"
if (-not (Test-Path -LiteralPath $parentMetadataPath)) {
    throw "No metadata found for parent session $ParentSessionId at $parentMetadataPath."
}

$childrenPath = Join-Path $parentDir "children.jsonl"
$children = @(Read-JsonLines -Path $childrenPath)
if ($children.Count -eq 0) {
    throw "No child sessions were found for parent session $ParentSessionId."
}

$mergedPath = Join-Path $parentDir "merged-children.jsonl"
$mergedRecords = @(Read-JsonLines -Path $mergedPath)
$mergedIds = @($mergedRecords | ForEach-Object { Get-PropertyText -Object $_ -Name "childSessionId" } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

$childRecord = Select-ChildRecord -Children $children -MergedIds $mergedIds -Query $ChildName -ExplicitChildSessionId $ChildSessionId
$resolvedChildId = Assert-SpawnSessionId -SessionId (Get-PropertyText -Object $childRecord -Name "childSessionId") -ParameterName "resolved childSessionId"
$childDir = Join-Path (Join-Path $root "sessions") $resolvedChildId
$childMetadataPath = Join-Path $childDir "metadata.json"
if (-not (Test-Path -LiteralPath $childMetadataPath)) {
    throw "No metadata found for child session $resolvedChildId at $childMetadataPath. Make sure the child session ran with hooks installed."
}

$childMetadata = Read-JsonHashtable -Path $childMetadataPath
$childTranscriptPath = if ($childMetadata.Contains("transcriptPath")) { [string]$childMetadata["transcriptPath"] } else { "" }
& (Join-Path $PSScriptRoot "export-context.ps1") -SessionId $resolvedChildId -BaseDir $root -TranscriptPath $childTranscriptPath
$childMetadata = Read-JsonHashtable -Path $childMetadataPath

$childContextCompactPath = if ($childMetadata.Contains("contextCompactPath")) { [string]$childMetadata["contextCompactPath"] } else { Join-Path $childDir "context-compact.md" }
if (-not (Test-Path -LiteralPath $childContextCompactPath)) {
    throw "No compact context was generated for child session $resolvedChildId."
}

$childTranscriptJsonlPath = if ($childMetadata.Contains("transcriptJsonlPath")) { [string]$childMetadata["transcriptJsonlPath"] } else { Join-Path $childDir "transcript.jsonl" }
$mergeDir = Join-Path (Join-Path $parentDir "merges") $resolvedChildId
Ensure-Directory -Path $mergeDir

$copiedChildContextPath = Join-Path $mergeDir "child-context-compact.md"
$copiedChildTranscriptPath = Join-Path $mergeDir "child-transcript.jsonl"
$childContextText = Get-Content -LiteralPath $childContextCompactPath -Raw
Write-RawTextFileAtomic -Text $childContextText -Path $copiedChildContextPath
if (Test-Path -LiteralPath $childTranscriptJsonlPath) {
    Write-RawTextFileAtomic -Text (Get-Content -LiteralPath $childTranscriptJsonlPath -Raw) -Path $copiedChildTranscriptPath
}

$mergeTime = Get-IsoTimestamp
$childTopic = Get-PropertyText -Object $childRecord -Name "topic"
$childNameValue = Get-PropertyText -Object $childRecord -Name "name"
$childCwd = if ($childMetadata.Contains("cwd")) { [string]$childMetadata["cwd"] } else { Get-PropertyText -Object $childRecord -Name "cwd" }
$childEventCount = if ($childMetadata.Contains("eventCount")) { [string]$childMetadata["eventCount"] } else { "unknown" }
$latestPromptStatus = if ($childMetadata.Contains("latestPromptStatus")) { [string]$childMetadata["latestPromptStatus"] } else { "unknown" }
if (-not $AllowIncomplete -and $latestPromptStatus -ne "completed") {
    throw "Child session $resolvedChildId is not marked completed (latestPromptStatus=$latestPromptStatus). Re-run with -AllowIncomplete to merge anyway."
}

$childTopicForMarkdown = ConvertTo-SingleLine -Text $childTopic
$childNameForMarkdown = ConvertTo-SingleLine -Text $childNameValue
$childCwdForMarkdown = ConvertTo-SingleLine -Text $childCwd -MaxChars 600

$mergeContextPath = Join-Path $mergeDir "merge-context.md"
$mergeLines = [System.Collections.Generic.List[string]]::new()
$mergeLines.Add("# Child session merge context")
$mergeLines.Add("")
$mergeLines.Add("Parent session ID: $ParentSessionId")
$mergeLines.Add("Child session ID: $resolvedChildId")
$mergeLines.Add("Merge time: $mergeTime")
$mergeLines.Add("Child topic/name: $childTopicForMarkdown $childNameForMarkdown")
$mergeLines.Add("Child cwd: $childCwdForMarkdown")
$mergeLines.Add("")
$mergeLines.Add("## How to merge this context")
$mergeLines.Add("")
$mergeLines.Add("Treat this as completed side-topic context that should now become part of the parent session's working memory.")
$mergeLines.Add("Do not replay the child transcript.")
$mergeLines.Add("Extract durable decisions, findings, files changed, commands run, unresolved follow-ups, and warnings.")
$mergeLines.Add("After reading, provide a concise merge acknowledgement and continue the parent topic normally.")
$mergeLines.Add("")
$mergeLines.Add("## Child outcome summary")
$mergeLines.Add("")
$mergeLines.Add("- Child session: $resolvedChildId")
$mergeLines.Add("- Child name: $childNameForMarkdown")
$mergeLines.Add("- Child topic: $childTopicForMarkdown")
$mergeLines.Add("- Child event count: $childEventCount")
$mergeLines.Add("- Latest prompt status at merge: $latestPromptStatus")
$mergeLines.Add("- Child compact context: $copiedChildContextPath")
$mergeLines.Add("- Child normalized transcript: $copiedChildTranscriptPath")
$mergeLines.Add("")
$mergeLines.Add("## Recent child transcript and context")
$mergeLines.Add("")
$childFence = Get-MarkdownFence -Text $childContextText
$mergeLines.Add("${childFence}markdown")
$mergeLines.Add((Limit-Text -Text $childContextText -MaxChars 60000))
$mergeLines.Add($childFence)
$mergeLines.Add("")
$mergeLines.Add("## Files and artifacts")
$mergeLines.Add("")
$mergeLines.Add("- Merge manifest: merge-manifest.json")
$mergeLines.Add("- Merge context: merge-context.md")
$mergeLines.Add("- Child context compact copy: child-context-compact.md")
$mergeLines.Add("- Child transcript copy: child-transcript.jsonl")
Write-TextFileAtomic -Lines @($mergeLines) -Path $mergeContextPath

$manifestPath = Join-Path $mergeDir "merge-manifest.json"
$mergeManifest = [ordered]@{
    mergeVersion = 1
    parentSessionId = $ParentSessionId
    childSessionId = $resolvedChildId
    childName = $childNameForMarkdown
    childTopic = $childTopicForMarkdown
    childCwd = $childCwd
    mergeTime = $mergeTime
    status = "ready"
    files = [ordered]@{
        manifest = $manifestPath
        mergeContext = $mergeContextPath
        childContextCompact = $copiedChildContextPath
        childTranscript = $copiedChildTranscriptPath
    }
}
Write-JsonFile -Value $mergeManifest -Path $manifestPath -Depth 50

$indexRecord = [ordered]@{
    parentSessionId = $ParentSessionId
    childSessionId = $resolvedChildId
    childName = $childNameForMarkdown
    childTopic = $childTopicForMarkdown
    mergeTime = $mergeTime
    mergeContextPath = $mergeContextPath
    manifestPath = $manifestPath
}
$indexLockPath = "$mergedPath.lock"
$indexLock = [System.IO.File]::Open($indexLockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
try {
    $latestMergedRecords = @(Read-JsonLines -Path $mergedPath)
    $remainingRecords = @($latestMergedRecords | Where-Object { (Get-PropertyText -Object $_ -Name "childSessionId") -ine $resolvedChildId })
    $indexLines = @(
        $remainingRecords | ForEach-Object { $_ | ConvertTo-Json -Depth 50 -Compress }
    )
    $indexLines += ($indexRecord | ConvertTo-Json -Depth 50 -Compress)
    Write-TextFileAtomic -Lines @($indexLines) -Path $mergedPath
}
finally {
    $indexLock.Dispose()
}

if ($CopyPath) {
    $mergeContextPath | Set-Clipboard
}

[ordered]@{
    parentSessionId = $ParentSessionId
    childSessionId = $resolvedChildId
    childName = $childNameForMarkdown
    childTopic = $childTopicForMarkdown
    mergeContextPath = $mergeContextPath
    manifestPath = $manifestPath
    status = "ready"
} | ConvertTo-Json -Depth 20
