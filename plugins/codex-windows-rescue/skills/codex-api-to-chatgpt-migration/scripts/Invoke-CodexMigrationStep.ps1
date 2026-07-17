[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('StopApiSwitch', 'QuarantinePath')]
    [string]$Action,

    [int]$ExpectedProcessId,
    [string]$ExpectedPath,
    [string]$BackupRoot,
    [string]$OperationId,
    [switch]$Apply,
    [string]$ConfirmationToken
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-NormalizedPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path)).TrimEnd('\')
}

function Test-SamePath {
    param([string]$Left, [string]$Right)
    return [string]::Equals((Get-NormalizedPath $Left), (Get-NormalizedPath $Right), [StringComparison]::OrdinalIgnoreCase)
}

function Assert-ApplyGuard {
    if (-not $Apply) { return }
    if ($ConfirmationToken -ne 'APPLY-ONE-STEP') {
        throw 'Apply mode requires -ConfirmationToken APPLY-ONE-STEP after explicit approval for this exact step.'
    }
}

Assert-ApplyGuard

if ([string]::IsNullOrWhiteSpace($BackupRoot)) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    if ([string]::IsNullOrWhiteSpace($desktop)) {
        throw 'Windows did not return a valid Desktop known-folder path.'
    }
    $BackupRoot = Join-Path $desktop 'Codex-Rescue-Quarantine'
}
$BackupRoot = Get-NormalizedPath $BackupRoot

if ($Action -eq 'StopApiSwitch') {
    if ($ExpectedProcessId -le 0) {
        throw 'StopApiSwitch requires -ExpectedProcessId from the read-only preview.'
    }

    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $ExpectedProcessId" -ErrorAction SilentlyContinue
    $matches = $false
    if ($process -and $process.CommandLine) {
        $matches = $process.CommandLine -match '(?i)[\\/]\.api-switch[\\/]proxy\.js(?:\s|"|$)'
    }

    $result = [ordered]@{
        SchemaVersion = '1.0'
        Mode = if ($Apply) { 'Apply' } else { 'Preview' }
        Action = $Action
        ProcessId = $ExpectedProcessId
        ProcessExists = $null -ne $process
        ExactApiSwitchMatch = $matches
        PlannedChange = 'Stop only this exact API-Switch process without Force.'
        ProtectedItems = @('v2rayN', 'HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY', 'API key files', 'Codex sessions')
        Applied = $false
        Verified = $false
    }

    if ($Apply) {
        if (-not $process) { throw "Process $ExpectedProcessId no longer exists; discard the previous approval." }
        if (-not $matches) { throw "Process $ExpectedProcessId no longer matches the API-Switch script; refusing to stop it." }
        Stop-Process -Id $ExpectedProcessId -ErrorAction Stop
        Start-Sleep -Milliseconds 250
        $stillRunning = $null -ne (Get-Process -Id $ExpectedProcessId -ErrorAction SilentlyContinue)
        $result.Applied = $true
        $result.Verified = -not $stillRunning
        if ($stillRunning) { throw "Process $ExpectedProcessId is still running; no further action was attempted." }
    }

    [PSCustomObject]$result | ConvertTo-Json -Depth 6
    exit 0
}

if ([string]::IsNullOrWhiteSpace($ExpectedPath)) {
    throw 'QuarantinePath requires -ExpectedPath from the read-only preview.'
}

$allowedTargets = @(
    (Join-Path $env:USERPROFILE '.api-switch'),
    (Join-Path $env:USERPROFILE '.api-switch.yaml'),
    (Join-Path $env:USERPROFILE '.cc-switch'),
    (Join-Path $env:LOCALAPPDATA 'com.ccswitch.desktop'),
    (Join-Path $env:APPDATA 'com.ccswitch.desktop'),
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\proxy-start.vbs')
) | ForEach-Object { Get-NormalizedPath $_ }

$source = Get-NormalizedPath $ExpectedPath
$allowed = @($allowedTargets | Where-Object { Test-SamePath $_ $source }).Count -eq 1
if (-not $allowed) {
    throw "Target is not an allow-listed migration path: $source"
}

if ($Apply -and [string]::IsNullOrWhiteSpace($OperationId)) {
    throw 'Apply mode requires the -OperationId shown by the preview.'
}
if ([string]::IsNullOrWhiteSpace($OperationId)) {
    $OperationId = Get-Date -Format 'yyyyMMdd-HHmmss'
}
if ($OperationId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') {
    throw 'OperationId may contain only letters, digits, dot, underscore, and hyphen.'
}

$operationRoot = Join-Path $BackupRoot $OperationId
$destination = Join-Path $operationRoot (Split-Path -Leaf $source)
$sourceExists = Test-Path -LiteralPath $source
$destinationExists = Test-Path -LiteralPath $destination

$result = [ordered]@{
    SchemaVersion = '1.0'
    Mode = if ($Apply) { 'Apply' } else { 'Preview' }
    Action = $Action
    OperationId = $OperationId
    Source = $source
    AllowlistMatched = $allowed
    SourceExists = $sourceExists
    Destination = $destination
    DestinationExists = $destinationExists
    PlannedChange = 'Move this one exact path into quarantine; do not delete it.'
    ProtectedItems = @('v2rayN', 'proxy environment variables', 'API keys outside this path', 'Codex projects', 'Codex sessions')
    Applied = $false
    Verified = $false
}

if ($Apply) {
    if (-not $sourceExists) { throw "Source no longer exists; discard the previous approval: $source" }
    if ($destinationExists) { throw "Destination already exists; refusing to overwrite it: $destination" }
    if (-not (Test-Path -LiteralPath $operationRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $operationRoot -ErrorAction Stop | Out-Null
    }
    Move-Item -LiteralPath $source -Destination $destination -ErrorAction Stop
    $result.Applied = $true
    $result.Verified = (-not (Test-Path -LiteralPath $source)) -and (Test-Path -LiteralPath $destination)
    if (-not $result.Verified) { throw 'Move verification failed; no further action was attempted.' }
}

[PSCustomObject]$result | ConvertTo-Json -Depth 6
