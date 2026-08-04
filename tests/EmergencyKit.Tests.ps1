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
    if ($source -match '(?i)\b(Invoke-WebRequest|Invoke-RestMethod|Start-BitsTransfer|curl(?:\.exe)?|wget(?:\.exe)?|Test-NetConnection|Resolve-DnsName)\b') {
        throw 'Emergency audit contains a forbidden network command.'
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
        'The audit itself is fully local and performs no network requests.',
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
    if ($snapshot.SchemaVersion -ne '1.2') {
        throw "Unexpected snapshot schema version: $($snapshot.SchemaVersion)"
    }
    if ($snapshot.WindowsCodex.SchemaVersion -ne '1.2') {
        throw "Unexpected Windows snapshot schema version: $($snapshot.WindowsCodex.SchemaVersion)"
    }
    if ($snapshot.WindowsCodex.ProxyAlignment.NetworkRequestsPerformed -ne $false) {
        throw 'Emergency proxy alignment unexpectedly performed network requests.'
    }
    if (@($snapshot.WindowsCodex.ProxyAlignment.Endpoints | Where-Object { $_.Source -eq 'HTTP_PROXY' -and $_.Port -eq 10808 }).Count -eq 0) {
        throw 'Emergency audit did not parse the configured loopback proxy endpoint.'
    }
    if ($null -eq $snapshot.WindowsCodex.Sessions.MetadataInventory) {
        throw 'Snapshot does not include the read-only session metadata inventory.'
    }
    if ($null -ne $snapshot.ChromeBridge -and $null -eq $snapshot.ChromeBridge.RuntimeEvidence) {
        throw 'Chrome snapshot does not include redacted runtime evidence.'
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
