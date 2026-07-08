Set-StrictMode -Version Latest

function Get-SpawnRoot {
    param([string]$BaseDir)

    if (-not [string]::IsNullOrWhiteSpace($BaseDir)) {
        return [System.IO.Path]::GetFullPath($BaseDir)
    }

    if (-not [string]::IsNullOrWhiteSpace($env:COPILOT_SPAWN_HOME)) {
        return [System.IO.Path]::GetFullPath($env:COPILOT_SPAWN_HOME)
    }

    return (Join-Path $HOME ".copilot\spawn-sessions")
}

function Get-CopilotHome {
    if (-not [string]::IsNullOrWhiteSpace($env:COPILOT_HOME)) {
        return [System.IO.Path]::GetFullPath($env:COPILOT_HOME)
    }

    return (Join-Path $HOME ".copilot")
}

function Get-CopilotSessionName {
    param([Parameter(Mandatory)][string]$SessionId)

    $id = Assert-SpawnSessionId -SessionId $SessionId
    $workspacePath = Join-Path (Join-Path (Join-Path (Get-CopilotHome) "session-state") $id) "workspace.yaml"
    if (-not (Test-Path -LiteralPath $workspacePath)) {
        return ""
    }

    foreach ($line in [System.IO.File]::ReadLines($workspacePath)) {
        if ($line -match '^\s*name:\s*(.+?)\s*$') {
            $name = $Matches[1].Trim()
            if (($name.StartsWith('"') -and $name.EndsWith('"')) -or ($name.StartsWith("'") -and $name.EndsWith("'"))) {
                $name = $name.Substring(1, $name.Length - 2)
            }
            return $name
        }
    }

    return ""
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Ensure-SpawnRoot {
    param([Parameter(Mandatory)][string]$Root)

    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
    $homeRoot = [System.IO.Path]::GetFullPath($HOME).TrimEnd('\')
    $leaf = Split-Path -Leaf $fullRoot

    if ($fullRoot -eq $homeRoot -or $fullRoot -match '^[A-Za-z]:$' -or $leaf -ne "spawn-sessions") {
        throw "Spawn root must be a dedicated directory named 'spawn-sessions'. Received: $Root"
    }

    Ensure-Directory -Path $fullRoot
    $markerPath = Join-Path $fullRoot ".copilot-session-spawn-root"
    if (-not (Test-Path -LiteralPath $markerPath)) {
        "This directory is managed by copilot-session-spawn." | Set-Content -LiteralPath $markerPath -Encoding UTF8
    }
}

function Read-JsonHashtable {
    param([Parameter(Mandatory)][string]$Path)

    $result = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $result
    }

    $text = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $result
    }

    $obj = $text | ConvertFrom-Json -Depth 100
    foreach ($prop in $obj.PSObject.Properties) {
        $result[$prop.Name] = $prop.Value
    }
    return $result
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Path,
        [int]$Depth = 50
    )

    $parent = Split-Path -Parent $Path
    if ($parent) {
        Ensure-Directory -Path $parent
    }

    $temp = "$Path.$PID.$([guid]::NewGuid().ToString('N')).tmp"
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

function Write-TextFileAtomic {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory)][string]$Path
    )

    $parent = Split-Path -Parent $Path
    if ($parent) {
        Ensure-Directory -Path $parent
    }

    $temp = "$Path.$PID.$([guid]::NewGuid().ToString('N')).tmp"
    $Lines | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

function Write-RawTextFileAtomic {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$Path
    )

    $parent = Split-Path -Parent $Path
    if ($parent) {
        Ensure-Directory -Path $parent
    }

    $temp = "$Path.$PID.$([guid]::NewGuid().ToString('N')).tmp"
    $Text | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

function Add-TextFileLocked {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Line,
        [Parameter(Mandatory)][string]$Path
    )

    $parent = Split-Path -Parent $Path
    if ($parent) {
        Ensure-Directory -Path $parent
    }

    $lockPath = "$Path.lock"
    $lockStream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    try {
        Add-Content -LiteralPath $Path -Value $Line -Encoding UTF8
    }
    finally {
        $lockStream.Dispose()
    }
}

function Assert-SpawnSessionId {
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [string]$ParameterName = "SessionId"
    )

    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($SessionId, [ref]$parsed)) {
        throw "$ParameterName must be a UUID. Received: $SessionId"
    }

    return $parsed.ToString()
}

function Get-ObjectProperty {
    param(
        $Object,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            return $Object[$Name]
        }
        return $null
    }

    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) {
        return $null
    }
    return $prop.Value
}

function Get-FirstObjectProperty {
    param(
        $Object,
        [Parameter(Mandatory)][string[]]$Names
    )

    foreach ($name in $Names) {
        $value = Get-ObjectProperty -Object $Object -Name $name
        if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
            return $value
        }
    }
    return $null
}

function ConvertTo-SpawnText {
    param($Value)

    if ($null -eq $Value) {
        return ""
    }

    if ($Value -is [string]) {
        return $Value
    }

    try {
        return ($Value | ConvertTo-Json -Depth 30 -Compress)
    }
    catch {
        return [string]$Value
    }
}

function Limit-Text {
    param(
        [AllowNull()][string]$Text,
        [int]$MaxChars = 4000
    )

    if ($null -eq $Text) {
        return ""
    }

    if ($Text.Length -le $MaxChars) {
        return $Text
    }

    return ($Text.Substring(0, [Math]::Max(0, $MaxChars)) + "`n[truncated]")
}

function Protect-ContextText {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) {
        return ""
    }

    $safe = $Text
    $safe = $safe -replace '(?i)\bgithub_pat_[A-Za-z0-9_]+\b', '<redacted-github-token>'
    $safe = $safe -replace '(?i)\bgh[pousr]_[A-Za-z0-9_]+\b', '<redacted-github-token>'
    $safe = $safe -replace '\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b', '<redacted-jwt>'
    $safe = [regex]::Replace($safe, '(?i)\b(token|api[-_]?key|secret|password|passwd|pwd)\b\s*[:=]\s*["'']?[^"''\s,;]+', '${1}=<redacted>')
    return $safe
}

function Get-IsoTimestamp {
    return [DateTimeOffset]::UtcNow.ToString("o")
}

function ConvertTo-PowerShellSingleQuoted {
    param([Parameter(Mandatory)][string]$Value)

    return "'" + ($Value -replace "'", "''") + "'"
}

function Get-MarkdownFence {
    param([AllowNull()][string]$Text)

    $max = 2
    if ($null -ne $Text) {
        foreach ($match in [regex]::Matches($Text, '~{3,}')) {
            if ($match.Value.Length -gt $max) {
                $max = $match.Value.Length
            }
        }
    }

    return "~" * ($max + 1)
}
