[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$SourceRoot,
    [string]$DestinationRoot,
    [switch]$Apply,
    [string]$ConfirmationToken,
    [string]$ExpectedPlanHash
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-StringHash {
    param([string]$Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-MetadataInventory {
    param([string[]]$Roots)

    $results = @()
    foreach ($root in $Roots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $codexRoots = @($root)
        $codexRoots += @(Get-ChildItem -LiteralPath $root -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like '.codex*' } |
            Select-Object -ExpandProperty FullName)

        foreach ($codexRoot in @($codexRoots | Sort-Object -Unique)) {
            foreach ($name in @('session_index.jsonl', 'history.jsonl', '.codex-global-state.json')) {
                $path = Join-Path $codexRoot $name
                if (Test-Path -LiteralPath $path -PathType Leaf) {
                    $item = Get-Item -LiteralPath $path
                    $results += [PSCustomObject]@{
                        Root = $codexRoot
                        Name = $name
                        Kind = 'File'
                        Bytes = [long]$item.Length
                        ItemCount = $null
                        ContentsRead = $false
                    }
                }
            }
            foreach ($item in Get-ChildItem -LiteralPath $codexRoot -File -Filter 'state_*.sqlite*' -ErrorAction SilentlyContinue) {
                $results += [PSCustomObject]@{
                    Root = $codexRoot
                    Name = $item.Name
                    Kind = 'File'
                    Bytes = [long]$item.Length
                    ItemCount = $null
                    ContentsRead = $false
                }
            }
            foreach ($name in @('session_backups', 'generated_images')) {
                $path = Join-Path $codexRoot $name
                if (Test-Path -LiteralPath $path -PathType Container) {
                    $results += [PSCustomObject]@{
                        Root = $codexRoot
                        Name = $name
                        Kind = 'Directory'
                        Bytes = $null
                        ItemCount = @(Get-ChildItem -LiteralPath $path -File -Recurse -ErrorAction SilentlyContinue).Count
                        ContentsRead = $false
                    }
                }
            }
        }
    }
    return @($results | Sort-Object Root, Name -Unique)
}

if ([string]::IsNullOrWhiteSpace($DestinationRoot)) {
    $DestinationRoot = [Environment]::GetEnvironmentVariable('CODEX_HOME', 'Process')
    if ([string]::IsNullOrWhiteSpace($DestinationRoot)) { $DestinationRoot = Join-Path $env:USERPROFILE '.codex' }
}
$DestinationRoot = [IO.Path]::GetFullPath($DestinationRoot).TrimEnd('\')

$trustedRoots = @($SourceRoot | ForEach-Object {
    [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($_)).TrimEnd('\')
} | Sort-Object -Unique)

$sessionDirPaths = @()
foreach ($root in $trustedRoots) {
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
    $leaf = Split-Path -Leaf $root
    if ($leaf -in @('sessions', 'archived_sessions')) { $sessionDirPaths += $root }
    foreach ($category in @('sessions', 'archived_sessions')) {
        $direct = Join-Path $root $category
        if (Test-Path -LiteralPath $direct -PathType Container) { $sessionDirPaths += $direct }
    }
    $sessionDirPaths += @(Get-ChildItem -LiteralPath $root -Directory -Recurse -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -in @('sessions', 'archived_sessions') -and $_.Parent.Name -like '.codex*'
    } | Select-Object -ExpandProperty FullName)
}
$sessionDirPaths = @($sessionDirPaths | Sort-Object -Unique)
if ($sessionDirPaths.Count -eq 0) { throw 'No sessions or archived_sessions directories were found under the trusted source roots.' }

$plan = @()
foreach ($sessionDirPath in $sessionDirPaths) {
    $category = Split-Path -Leaf $sessionDirPath
    foreach ($file in Get-ChildItem -LiteralPath $sessionDirPath -File -Recurse -ErrorAction Stop) {
        $relative = $file.FullName.Substring($sessionDirPath.Length).TrimStart([char[]]@('\', '/'))
        $destination = Join-Path (Join-Path $DestinationRoot $category) $relative
        $sourceHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $destinationExists = Test-Path -LiteralPath $destination -PathType Leaf
        $destinationHash = $null
        $status = 'Copy'
        if ($destinationExists) {
            $destinationHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
            $status = if ($sourceHash -eq $destinationHash) { 'SkipSame' } else { 'Conflict' }
        }
        $plan += [PSCustomObject]@{
            Category = $category
            Source = $file.FullName
            Destination = $destination
            Bytes = [long]$file.Length
            SourceHash = $sourceHash
            DestinationHash = $destinationHash
            Status = $status
        }
    }
}

$canonical = @($plan | Sort-Object Source, Destination | ForEach-Object {
    '{0}|{1}|{2}|{3}|{4}' -f $_.Status, $_.Source, $_.Destination, $_.SourceHash, $_.DestinationHash
}) -join "`n"
$planHash = Get-StringHash -Value $canonical

if ($Apply) {
    if ($ConfirmationToken -ne 'RESTORE-SESSIONS') {
        throw 'Apply mode requires -ConfirmationToken RESTORE-SESSIONS after explicit approval.'
    }
    if ([string]::IsNullOrWhiteSpace($ExpectedPlanHash) -or $ExpectedPlanHash -ne $planHash) {
        throw 'The current plan does not match the approved preview. Run preview again and review the changed plan.'
    }
}

$copied = 0
$verified = 0
if ($Apply) {
    foreach ($item in $plan | Where-Object { $_.Status -eq 'Copy' }) {
        if (Test-Path -LiteralPath $item.Destination) {
            throw "Destination appeared after preview; refusing to overwrite: $($item.Destination)"
        }
        $parent = Split-Path -Parent $item.Destination
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            New-Item -ItemType Directory -Path $parent -ErrorAction Stop | Out-Null
        }
        Copy-Item -LiteralPath $item.Source -Destination $item.Destination -ErrorAction Stop
        $copied++
        $newHash = (Get-FileHash -LiteralPath $item.Destination -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($newHash -eq $item.SourceHash) { $verified++ } else { throw "Hash verification failed: $($item.Destination)" }
    }
}

[PSCustomObject]@{
    SchemaVersion = '1.1'
    Mode = if ($Apply) { 'Apply' } else { 'Preview' }
    RestoreMode = 'TranscriptSalvage'
    DesktopVisibilityGuaranteed = $false
    AutomaticIndexOrDatabaseMerge = $false
    PlanHash = $planHash
    TrustedSourceRoots = $trustedRoots
    SessionDirectories = $sessionDirPaths
    DestinationRoot = $DestinationRoot
    Summary = [PSCustomObject]@{
        Total = $plan.Count
        Copy = @($plan | Where-Object { $_.Status -eq 'Copy' }).Count
        SkipSame = @($plan | Where-Object { $_.Status -eq 'SkipSame' }).Count
        Conflict = @($plan | Where-Object { $_.Status -eq 'Conflict' }).Count
        Copied = $copied
        Verified = $verified
    }
    ExcludedState = @('auth.json', 'config.toml', 'plugins', 'cache', 'SQLite', 'logs', 'provider settings')
    MetadataInventory = @(Get-MetadataInventory -Roots $trustedRoots)
    VerificationRequired = @('CLI task visibility', 'Desktop sidebar visibility', 'Open or resume one restored task')
    Plan = @($plan)
} | ConvertTo-Json -Depth 10
