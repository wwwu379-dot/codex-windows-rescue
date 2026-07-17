[CmdletBinding()]
param(
    [string]$SourceRoot,
    [string]$DestinationRoot,
    [ValidateSet('Config', 'Sessions', 'ArchivedSessions', 'Plugins')]
    [string[]]$Categories = @('Config', 'Sessions', 'ArchivedSessions'),
    [string]$OperationId,
    [switch]$Apply,
    [string]$ConfirmationToken
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = [Environment]::GetEnvironmentVariable('CODEX_HOME', 'Process')
    if ([string]::IsNullOrWhiteSpace($SourceRoot)) { $SourceRoot = Join-Path $env:USERPROFILE '.codex' }
}
$SourceRoot = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')

if ([string]::IsNullOrWhiteSpace($DestinationRoot)) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    if ([string]::IsNullOrWhiteSpace($desktop)) { throw 'Windows did not return a valid Desktop known-folder path.' }
    $DestinationRoot = Join-Path $desktop 'Codex-Rescue-Backups'
}
$DestinationRoot = [IO.Path]::GetFullPath($DestinationRoot).TrimEnd('\')

if ($DestinationRoot.StartsWith($SourceRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
    [string]::Equals($DestinationRoot, $SourceRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'DestinationRoot must not be inside SourceRoot.'
}

if ($Apply -and $ConfirmationToken -ne 'BACKUP-CODEX-STATE') {
    throw 'Apply mode requires -ConfirmationToken BACKUP-CODEX-STATE after approval for this preview.'
}
if ($Apply -and [string]::IsNullOrWhiteSpace($OperationId)) {
    throw 'Apply mode requires the -OperationId shown by the preview.'
}
if ([string]::IsNullOrWhiteSpace($OperationId)) { $OperationId = Get-Date -Format 'yyyyMMdd-HHmmss' }
if ($OperationId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { throw 'Invalid OperationId.' }

$operationRoot = Join-Path $DestinationRoot $OperationId
$plans = @()

foreach ($category in @($Categories | Sort-Object -Unique)) {
    if ($category -eq 'Config') {
        $files = @()
        $main = Join-Path $SourceRoot 'config.toml'
        if (Test-Path -LiteralPath $main -PathType Leaf) { $files += Get-Item -LiteralPath $main }
        if (Test-Path -LiteralPath $SourceRoot -PathType Container) {
            $files += @(Get-ChildItem -LiteralPath $SourceRoot -Filter '*.config.toml' -File -ErrorAction SilentlyContinue)
        }
        $files = @($files | Sort-Object FullName -Unique)
        $plans += [PSCustomObject]@{
            Category = $category
            Source = $SourceRoot
            Destination = Join-Path $operationRoot 'config'
            Exists = $files.Count -gt 0
            FileCount = $files.Count
            Bytes = [long](($files | Measure-Object -Property Length -Sum).Sum)
            Files = @($files | Select-Object -ExpandProperty FullName)
        }
        continue
    }

    $folderName = switch ($category) {
        'Sessions' { 'sessions' }
        'ArchivedSessions' { 'archived_sessions' }
        'Plugins' { 'plugins' }
    }
    $source = Join-Path $SourceRoot $folderName
    $files = @(Get-ChildItem -LiteralPath $source -File -Recurse -ErrorAction SilentlyContinue)
    $plans += [PSCustomObject]@{
        Category = $category
        Source = $source
        Destination = Join-Path $operationRoot $folderName
        Exists = Test-Path -LiteralPath $source -PathType Container
        FileCount = $files.Count
        Bytes = [long](($files | Measure-Object -Property Length -Sum).Sum)
        Files = @()
    }
}

$result = [ordered]@{
    SchemaVersion = '1.0'
    Mode = if ($Apply) { 'Apply' } else { 'Preview' }
    OperationId = $OperationId
    SourceRoot = $SourceRoot
    DestinationRoot = $operationRoot
    AuthenticationIncluded = $false
    Plans = @($plans)
    Applied = $false
    Verified = $false
}

if ($Apply) {
    if (Test-Path -LiteralPath $operationRoot) { throw "Backup operation directory already exists: $operationRoot" }
    New-Item -ItemType Directory -Path $operationRoot -ErrorAction Stop | Out-Null

    foreach ($plan in $plans | Where-Object { $_.Exists }) {
        if ($plan.Category -eq 'Config') {
            New-Item -ItemType Directory -Path $plan.Destination -ErrorAction Stop | Out-Null
            foreach ($file in $plan.Files) {
                Copy-Item -LiteralPath $file -Destination $plan.Destination -ErrorAction Stop
            }
        }
        else {
            Copy-Item -LiteralPath $plan.Source -Destination $operationRoot -Recurse -ErrorAction Stop
        }
    }

    $result.Applied = $true
    $verified = $true
    foreach ($plan in $plans | Where-Object { $_.Exists }) {
        if (-not (Test-Path -LiteralPath $plan.Destination)) { $verified = $false }
    }
    $result.Verified = $verified
    if (-not $verified) { throw 'Backup verification failed; no source data was deleted.' }
}

[PSCustomObject]$result | ConvertTo-Json -Depth 8
