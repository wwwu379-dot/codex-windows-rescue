[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$emergencyScript = Join-Path $repositoryRoot 'emergency-kit\Start-CodexEmergencyAudit.ps1'
$emergencyLauncher = Join-Path $repositoryRoot 'emergency-kit\Run-CodexEmergencyAudit.cmd'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('codex-emergency-kit-test-' + [Guid]::NewGuid().ToString('N'))
$isolatedKit = Join-Path $testRoot 'emergency-kit'
$testOutput = Join-Path $testRoot 'reports'
$previousApiKey = $env:OPENAI_API_KEY
$previousProxy = $env:HTTP_PROXY

try {
    if (-not (Test-Path -LiteralPath $emergencyScript -PathType Leaf)) {
        throw "Emergency audit script is missing: $emergencyScript"
    }
    if (-not (Test-Path -LiteralPath $emergencyLauncher -PathType Leaf)) {
        throw "Emergency audit launcher is missing: $emergencyLauncher"
    }

    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $emergencyScript,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if (@($parseErrors).Count -gt 0) {
        throw "Emergency audit script has parser errors: $($parseErrors[0].Message)"
    }

    $source = Get-Content -LiteralPath $emergencyScript -Raw
    if ($source -match '(?i)\b(Remove-Item|Set-ItemProperty|New-ItemProperty|Stop-Process|Remove-AppxPackage|setx)\b') {
        throw 'Emergency audit contains a forbidden mutation command.'
    }

    [void](New-Item -ItemType Directory -Path $testRoot -Force)
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'emergency-kit') -Destination $isolatedKit -Recurse
    $isolatedScript = Join-Path $isolatedKit 'Start-CodexEmergencyAudit.ps1'

    if (Test-Path -LiteralPath (Join-Path $testRoot 'plugins')) {
        throw 'The isolated emergency-kit test unexpectedly contains the plugin repository.'
    }

    [void](New-Item -ItemType Directory -Path $testOutput -Force)
    $env:OPENAI_API_KEY = 'TEST-SECRET-MUST-NOT-APPEAR'
    $env:HTTP_PROXY = 'http://test-user:test-password@127.0.0.1:10808'

    $result = & $isolatedScript -OutputDirectory $testOutput -NoPause

    if (-not (Test-Path -LiteralPath $result.ReportPath -PathType Leaf)) {
        throw 'The human-readable emergency report was not created.'
    }
    if (-not (Test-Path -LiteralPath $result.SnapshotPath -PathType Leaf)) {
        throw 'The machine-readable emergency snapshot was not created.'
    }

    $report = Get-Content -LiteralPath $result.ReportPath -Raw
    $snapshotText = Get-Content -LiteralPath $result.SnapshotPath -Raw
    $snapshot = $snapshotText | ConvertFrom-Json

    foreach ($requiredText in @(
        'Codex Windows Emergency Audit',
        'Read-only guarantee',
        'What to do next',
        'No existing files, registry entries, environment variables, processes, services, tasks, or applications were changed; only these diagnostic report files were created.'
    )) {
        if ($report -notlike "*$requiredText*") {
            throw "Report is missing required text: $requiredText"
        }
    }

    foreach ($forbiddenText in @(
        'TEST-SECRET-MUST-NOT-APPEAR',
        'test-password',
        'test-user'
    )) {
        if ($report -like "*$forbiddenText*" -or $snapshotText -like "*$forbiddenText*") {
            throw "Sensitive test value leaked into emergency output: $forbiddenText"
        }
    }

    if (-not $snapshot.ReadOnly) {
        throw 'Snapshot does not declare itself read-only.'
    }
    if ($snapshot.SchemaVersion -ne '1.0') {
        throw "Unexpected snapshot schema version: $($snapshot.SchemaVersion)"
    }

    Write-Host 'PASS: emergency kit generates redacted read-only reports without Codex.' -ForegroundColor Green
}
finally {
    $env:OPENAI_API_KEY = $previousApiKey
    $env:HTTP_PROXY = $previousProxy
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
