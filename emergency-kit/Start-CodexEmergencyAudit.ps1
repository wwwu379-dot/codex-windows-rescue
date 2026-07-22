[CmdletBinding()]
param(
    [string[]]$ProjectRoots = @(),
    [string]$OutputDirectory,
    [switch]$NoPause
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Convert-ToSafeString {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $null }

    $text = [string]$Value
    foreach ($replacement in @(
        [PSCustomObject]@{ From = $env:LOCALAPPDATA; To = '%LOCALAPPDATA%' },
        [PSCustomObject]@{ From = $env:APPDATA; To = '%APPDATA%' },
        [PSCustomObject]@{ From = $env:USERPROFILE; To = '%USERPROFILE%' }
    )) {
        if (-not [string]::IsNullOrWhiteSpace([string]$replacement.From)) {
            $text = $text.Replace([string]$replacement.From, [string]$replacement.To)
        }
    }

    return ($text -replace '(?i)(https?|socks5?|socks5h)://[^/@\s]+@', '$1://<redacted>@')
}

function Convert-ToRedactedObject {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return Convert-ToSafeString $Value }
    if ($Value -is [ValueType]) { return $Value }
    if ($Value -is [Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $result[[string]$key] = Convert-ToRedactedObject $Value[$key]
        }
        return [PSCustomObject]$result
    }
    if ($Value -is [Collections.IEnumerable]) {
        return @($Value | ForEach-Object { Convert-ToRedactedObject $_ })
    }

    $properties = @($Value.PSObject.Properties | Where-Object { $_.MemberType -in @('NoteProperty', 'Property') })
    if ($properties.Count -gt 0) {
        $result = [ordered]@{}
        foreach ($property in $properties) {
            $result[$property.Name] = Convert-ToRedactedObject $property.Value
        }
        return [PSCustomObject]$result
    }
    return Convert-ToSafeString $Value
}

function Get-PresenceLabel {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return 'unknown' }
    if ([bool]$Value) { return 'present' }
    return 'absent'
}

function Add-Line {
    param([Collections.Generic.List[string]]$Lines, [string]$Text = '')
    [void]$Lines.Add($Text)
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$doctorScript = Join-Path $repositoryRoot 'plugins\codex-windows-rescue\skills\codex-windows-doctor\scripts\Get-CodexWindowsSnapshot.ps1'
$chromeScript = Join-Path $repositoryRoot 'plugins\codex-windows-rescue\skills\codex-chrome-doctor\scripts\Test-CodexChromeBridge.ps1'
foreach ($requiredScript in @($doctorScript, $chromeScript)) {
    if (-not (Test-Path -LiteralPath $requiredScript -PathType Leaf)) {
        throw "The downloaded repository is incomplete. Missing: $requiredScript"
    }
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    if ([string]::IsNullOrWhiteSpace($desktop)) { $desktop = [Environment]::GetFolderPath('MyDocuments') }
    if ([string]::IsNullOrWhiteSpace($desktop)) {
        throw 'Windows did not return a Desktop or Documents path. Pass -OutputDirectory explicitly.'
    }
    $OutputDirectory = Join-Path $desktop 'Codex-Emergency-Reports'
}

$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
if (-not (Test-Path -LiteralPath $outputRoot -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $outputRoot -Force -ErrorAction Stop)
}

Write-Host 'Running a read-only Codex Windows audit. Existing system state will not be changed.' -ForegroundColor Cyan
$windows = ((& $doctorScript -ProjectRoots $ProjectRoots) -join [Environment]::NewLine) | ConvertFrom-Json
$chrome = $null
$chromeError = $null
try {
    $chrome = ((& $chromeScript) -join [Environment]::NewLine) | ConvertFrom-Json
}
catch {
    $chromeError = Convert-ToSafeString $_.Exception.Message
}

$safeWindows = Convert-ToRedactedObject $windows
$safeChrome = Convert-ToRedactedObject $chrome
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportPath = Join-Path $outputRoot "Codex-Emergency-Report-$timestamp.md"
$snapshotPath = Join-Path $outputRoot "Codex-Emergency-Snapshot-$timestamp.json"

$snapshot = [PSCustomObject]@{
    SchemaVersion = '1.0'
    CollectedAt = (Get-Date).ToString('o')
    ReadOnly = $true
    ExistingStateChanged = $false
    WindowsCodex = $safeWindows
    ChromeBridge = $safeChrome
    ChromeAuditError = $chromeError
}
[IO.File]::WriteAllText($snapshotPath, ($snapshot | ConvertTo-Json -Depth 16), [Text.UTF8Encoding]::new($false))

$httpProxy = @($safeWindows.Environment | Where-Object { $_.Name -eq 'HTTP_PROXY' })
$httpsProxy = @($safeWindows.Environment | Where-Object { $_.Name -eq 'HTTPS_PROXY' })
$port10808 = @($safeWindows.Ports | Where-Object { $_.Port -eq 10808 }) | Select-Object -First 1
$port15721 = @($safeWindows.Ports | Where-Object { $_.Port -eq 15721 }) | Select-Object -First 1
$thirdPartyPaths = @($safeWindows.CandidatePaths | Where-Object {
    $_.Exists -eq $true -and $_.Path -match '(?i)api-switch|ccswitch|cc-switch|proxy-start'
})

$lines = [Collections.Generic.List[string]]::new()
Add-Line $lines '# Codex Windows Emergency Audit'
Add-Line $lines
Add-Line $lines 'Use this report when Codex Desktop cannot answer and the CLI cannot load the rescue plugin.'
Add-Line $lines
Add-Line $lines '## Read-only guarantee'
Add-Line $lines
Add-Line $lines 'No existing files, registry entries, environment variables, processes, services, tasks, or applications were changed; only these diagnostic report files were created.'
Add-Line $lines
Add-Line $lines '## Quick summary'
Add-Line $lines
Add-Line $lines "- Codex home: $(Get-PresenceLabel $safeWindows.CodexHomeExists)"
Add-Line $lines "- Desktop AppX installations: $(@($safeWindows.AppxPackages).Count)"
Add-Line $lines "- Codex command sources: $(@($safeWindows.CommandSources).Count)"
Add-Line $lines "- Plugin sources directory: $(Get-PresenceLabel $safeWindows.Plugins.SourcesExist)"
Add-Line $lines "- Plugin marketplaces in cache: $($safeWindows.Plugins.MarketplaceCount)"
Add-Line $lines "- HTTP_PROXY present in any scope: $(@($httpProxy.Scopes | Where-Object Present).Count -gt 0)"
Add-Line $lines "- HTTPS_PROXY present in any scope: $(@($httpsProxy.Scopes | Where-Object Present).Count -gt 0)"
Add-Line $lines "- Port 10808 listening: $([bool]$port10808.Listening)"
Add-Line $lines "- Port 15721 listening: $([bool]$port15721.Listening)"
Add-Line $lines "- Third-party switch/route paths still present: $($thirdPartyPaths.Count)"
Add-Line $lines "- Session files: $($safeWindows.Sessions.SessionFileCount)"
Add-Line $lines "- Archived session files: $($safeWindows.Sessions.ArchivedFileCount)"
if ($null -ne $safeChrome) {
    Add-Line $lines "- Chrome bridge classification: $($safeChrome.Classification)"
}
elseif ($chromeError) {
    Add-Line $lines "- Chrome bridge audit: unavailable ($chromeError)"
}
Add-Line $lines
Add-Line $lines '## Installed Codex surfaces'
Add-Line $lines
if (@($safeWindows.AppxPackages).Count -eq 0 -and @($safeWindows.CommandSources).Count -eq 0) {
    Add-Line $lines '- No Desktop AppX or Codex command source was detected.'
}
foreach ($item in @($safeWindows.AppxPackages)) {
    Add-Line $lines "- Desktop AppX: $($item.Name) $($item.Version)"
}
foreach ($item in @($safeWindows.CommandSources)) {
    Add-Line $lines "- Command: $($item.CommandType) | $($item.Path) | $($item.Version)"
}
Add-Line $lines
Add-Line $lines '## Historical switch and route indicators'
Add-Line $lines
if ($thirdPartyPaths.Count -eq 0 -and @($safeWindows.PersistenceIndicators).Count -eq 0) {
    Add-Line $lines '- No known API-Switch, cc-switch, or proxy-start path/persistence indicator was detected.'
}
foreach ($item in $thirdPartyPaths) { Add-Line $lines "- Existing path: $($item.Path)" }
foreach ($item in @($safeWindows.PersistenceIndicators)) {
    Add-Line $lines "- Persistence: $($item.Kind) | $($item.Name) | $(@($item.Indicators) -join ', ')"
}
Add-Line $lines
Add-Line $lines '## Chrome bridge'
Add-Line $lines
if ($null -ne $safeChrome) {
    Add-Line $lines "- Classification: $($safeChrome.Classification)"
    Add-Line $lines "- Chrome installed: $($safeChrome.Chrome.Installed)"
    Add-Line $lines "- Extension installations: $(@($safeChrome.ExtensionInstalls).Count)"
    Add-Line $lines "- Complete plugin roots found: $(@($safeChrome.PluginRoots).Count)"
    Add-Line $lines "- Native Host registry entries present: $(@($safeChrome.RegistryEntries | Where-Object Exists).Count)"
    Add-Line $lines "- Native Host manifests present: $(@($safeChrome.Manifests | Where-Object Exists).Count)"
    Add-Line $lines '- Manual registry or manifest creation is not supported by this kit.'
}
else {
    Add-Line $lines "- Audit unavailable: $chromeError"
}
Add-Line $lines
Add-Line $lines '## What to do next'
Add-Line $lines
Add-Line $lines '1. Do not post the JSON snapshot publicly. Keep it for a trusted support session.'
Add-Line $lines '2. Send this Markdown report to web ChatGPT and say: "My Codex Desktop and CLI cannot use the rescue plugin. Please interpret this read-only emergency report and explain one safe step at a time."'
Add-Line $lines '3. Do not delete .codex, environment variables, proxy tools, or Chrome data only because they appear in this report.'
Add-Line $lines '4. When either Desktop or CLI works again, install the full codex-windows-rescue plugin for interactive diagnosis and recovery.'

[IO.File]::WriteAllLines($reportPath, $lines, [Text.UTF8Encoding]::new($false))
Write-Host "Report created: $reportPath" -ForegroundColor Green
Write-Host "Snapshot created: $snapshotPath" -ForegroundColor Green

[PSCustomObject]@{
    ReportPath = $reportPath
    SnapshotPath = $snapshotPath
    ReadOnly = $true
}
