[CmdletBinding()]
param(
    [string[]]$ProjectRoots = @(),
    [string]$OutputPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$doctorScript = Join-Path $PSScriptRoot '..\..\codex-windows-doctor\scripts\Get-CodexWindowsSnapshot.ps1'
if (-not (Test-Path -LiteralPath $doctorScript -PathType Leaf)) {
    throw "Required doctor script is missing: $doctorScript"
}

$full = (& $doctorScript -ProjectRoots $ProjectRoots) | ConvertFrom-Json
$candidateNames = @('.api-switch', '.api-switch.yaml', '.cc-switch', 'com.ccswitch.desktop', 'proxy-start.vbs')
$migrationPaths = @($full.CandidatePaths | Where-Object {
    $leaf = Split-Path -Leaf $_.Path
    $candidateNames -contains $leaf
})
$providerEnvironment = @($full.Environment | Where-Object {
    $_.Name -match 'OPENAI|DEEPSEEK|CODEX_(API_KEY|ACCESS_TOKEN)|BASE_URL'
})

$snapshot = [PSCustomObject]@{
    SchemaVersion = '1.0'
    CollectedAt = $full.CollectedAt
    IntendedEndState = 'ChatGPT sign-in for Codex'
    AuthStatusCommandRecommended = 'codex login status'
    AuthContentsRead = $false
    CommandSources = $full.CommandSources
    Configuration = $full.Configuration
    ProviderEnvironment = $providerEnvironment
    NetworkEnvironment = @($full.Environment | Where-Object { $_.Name -match '^(HTTP|HTTPS|ALL|NO)_PROXY$' })
    RouterProcesses = @($full.RelevantProcesses | Where-Object { $_.Category -in @('API-Switch', 'cc-switch') })
    RouterPorts = @($full.Ports | Where-Object { $_.Port -eq 15721 })
    PersistenceIndicators = @($full.PersistenceIndicators)
    PathIndicators = @($full.PathIndicators)
    MigrationCandidatePaths = $migrationPaths
    ProtectedPaths = @(
        (Join-Path $env:USERPROFILE 'Documents\Codex'),
        (Join-Path $full.CodexHome 'sessions'),
        (Join-Path $full.CodexHome 'archived_sessions')
    )
    ProtectedSettings = @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY')
}

$json = $snapshot | ConvertTo-Json -Depth 10
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $parent = Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        throw "Output directory does not exist: $parent"
    }
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), $json, [Text.UTF8Encoding]::new($false))
}
$json
