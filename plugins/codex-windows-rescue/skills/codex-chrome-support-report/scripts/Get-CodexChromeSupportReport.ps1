[CmdletBinding()]
param(
    [string]$ExtensionId = 'hehggadaopoacecdllhhajmbjkdcmajg',
    [switch]$OfficialSetupCompleted,
    [switch]$ComputerUseWorks,
    [switch]$BuiltInBrowserWorks,
    [switch]$OrdinaryCodexWorks,
    [string[]]$StepsAttempted = @(),
    [string]$OutputPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ($ExtensionId -notmatch '^[a-p]{32}$') {
    throw 'ExtensionId must be a 32-character Chrome extension ID.'
}

function Convert-ToSafePath {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return $null }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    foreach ($replacement in @(
        [PSCustomObject]@{ From = $env:USERPROFILE; To = '%USERPROFILE%' },
        [PSCustomObject]@{ From = $env:LOCALAPPDATA; To = '%LOCALAPPDATA%' },
        [PSCustomObject]@{ From = $env:APPDATA; To = '%APPDATA%' }
    )) {
        if (-not [string]::IsNullOrWhiteSpace([string]$replacement.From)) {
            $text = $text.Replace([string]$replacement.From, [string]$replacement.To)
        }
    }

    return ($text -replace '(?i)[A-Z]:\\Users\\[^\\]+', '%USERPROFILE%')
}

function Get-FirstValue {
    param([AllowNull()][object]$Value)

    $items = @($Value)
    if ($items.Count -eq 0) { return $null }
    return $items[0]
}

$skillsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$doctorScript = Join-Path $skillsRoot 'codex-chrome-doctor\scripts\Test-CodexChromeBridge.ps1'
if (-not (Test-Path -LiteralPath $doctorScript -PathType Leaf)) {
    throw "Required read-only doctor script is missing: $doctorScript"
}

$doctorOutput = @(& $doctorScript -ExtensionId $ExtensionId)
$snapshot = ($doctorOutput -join [Environment]::NewLine) | ConvertFrom-Json
$os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
$appx = @(Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue | Select-Object -First 1)
$codexApp = Get-FirstValue $appx

$chromeVersion = Get-FirstValue @($snapshot.Chrome.Version)
$codexVersion = if ($null -ne $codexApp) { [string]$codexApp.Version } else { $null }

$pluginLines = foreach ($plugin in @($snapshot.PluginRoots)) {
    $root = Convert-ToSafePath $plugin.Root
    $version = if ($root -match '\\chrome\\([^\\]+)$') { $Matches[1] } else { 'unknown' }
    "- version ${version}: browser-client=$($plugin.BrowserClient); checker=$($plugin.Checker); installer=$($plugin.InstallScript); host-executable=$($plugin.HostExecutable)"
}
if (@($pluginLines).Count -eq 0) { $pluginLines = @('- No Chrome plugin root was found.') }

$extensionLines = foreach ($install in @($snapshot.ExtensionInstalls)) {
    "- profile $($install.Profile), version $($install.VersionDirectory), manifest=$($install.ManifestExists)"
}
if (@($extensionLines).Count -eq 0) { $extensionLines = @('- No configured ChatGPT Chrome Extension installation was found.') }

$registryLines = foreach ($entry in @($snapshot.RegistryEntries)) {
    "- $($entry.Path -replace '^HKCU:', 'HKCU' -replace '^HKLM:', 'HKLM'): exists=$($entry.Exists)"
}

$manifestLines = foreach ($manifest in @($snapshot.Manifests)) {
    $safePath = Convert-ToSafePath $manifest.Path
    "- ${safePath}: exists=$($manifest.Exists); valid-json=$($manifest.ValidJson); host-exists=$($manifest.HostExists); expected-origin=$($manifest.ExpectedOriginPresent)"
}

$runtimeLines = foreach ($signal in @($snapshot.RuntimeEvidence.Signals)) {
    "- $($signal.Name): present=$($signal.Present); count=$($signal.MatchCount)"
}
if (@($runtimeLines).Count -eq 0) { $runtimeLines = @('- No redacted runtime signals were available.') }

$hostProcessLines = foreach ($process in @($snapshot.NativeHostProcesses)) {
    "- extension-host.exe process $($process.ProcessId): executable=$(Convert-ToSafePath $process.ExecutablePath); command-line-returned=$($process.CommandLineReturned)"
}
if (@($hostProcessLines).Count -eq 0) { $hostProcessLines = @('- No running extension-host.exe process was found during collection.') }

$steps = @('Read-only Chrome bridge audit completed.')
if ($OfficialSetupCompleted) {
    $steps += 'User confirmed that the official Chrome plugin remove/reinstall setup flow was completed.'
}
if ($StepsAttempted.Count -gt 0) {
    $steps += @($StepsAttempted | ForEach-Object { [string]$_ })
}

$classification = [string]$snapshot.Classification
$diagnosis = switch ($classification) {
    'native-host-missing' {
        if ($OfficialSetupCompleted) {
            'The extension and bundled plugin are present, but the Windows Native Messaging registration is still absent after the official setup flow. This is classified as an installer or product-lifecycle failure; do not synthesize a workaround.'
        }
        else {
            'The Native Messaging registration is missing. The official Chrome plugin setup flow has not been attested as complete, so this is not yet classified as a product-lifecycle failure.'
        }
    }
    'native-host-invalid' { 'The Native Messaging manifest or its relationship to the registry and extension origin is invalid. Report the failing fields; do not rewrite product-owned state.' }
    'plugin-cache-or-host-lock-suspected' { 'Static bridge checks pass, but redacted logs indicate a plugin-cache or native-host file-lock failure. Identify the exact process and use the official plugin flow; do not delete the whole cache.' }
    'runtime-extension-backend-failure' { 'Static bridge checks pass, but recent redacted signals indicate that the extension backend is unavailable or timing out. Reinstalling the Native Host alone may not repair this runtime layer.' }
    'task-or-site-policy-blocked' { 'Static bridge checks pass, but recent redacted signals indicate a task, network, or site-policy block. Verify approvals and policy before reinstalling.' }
    'runtime-test-required' { 'Static checks pass and no decisive redacted runtime failure was found. Start a new task and perform one minimal Chrome connection test.' }
    default { "The first failing layer is classified as $classification. Follow the corresponding read-only Chrome doctor branch." }
}

$safeOsCaption = if ($null -ne $os) { [string]$os.Caption } else { 'Unavailable' }
$safeOsVersion = if ($null -ne $os) { [string]$os.Version } else { 'Unavailable' }
$safeOsBuild = if ($null -ne $os) { [string]$os.BuildNumber } else { 'Unavailable' }
$officialSetupText = if ($OfficialSetupCompleted) { 'Yes (user-confirmed)' } else { 'Not confirmed' }
$computerUseText = if ($ComputerUseWorks) { 'Yes (user-confirmed)' } else { 'Not confirmed' }
$builtInBrowserText = if ($BuiltInBrowserWorks) { 'Yes (user-confirmed)' } else { 'Not confirmed' }
$ordinaryCodexText = if ($OrdinaryCodexWorks) { 'Yes (user-confirmed)' } else { 'Not confirmed' }
$supportProblem = switch ($classification) {
    'native-host-missing' { 'The Chrome extension and bundled plugin files are present, but the Windows Native Messaging registration and manifest are absent.' }
    'native-host-invalid' { 'The Chrome extension and bundled plugin files are present, but the Native Messaging manifest or its registration is invalid.' }
    'extension-missing' { 'The configured ChatGPT Chrome Extension was not found in the scanned Chrome profiles.' }
    'plugin-files-missing' { 'The Chrome extension is present, but the expected bundled Codex Chrome plugin files were not found.' }
    'chrome-missing' { 'Google Chrome was not found on this Windows installation.' }
    'plugin-cache-or-host-lock-suspected' { 'The static Chrome bridge is present, but plugin-cache reconciliation or the running Native Host appears to be locked.' }
    'runtime-extension-backend-failure' { 'The static Chrome bridge is present, but the Codex runtime cannot expose or reliably communicate with the Chrome extension backend.' }
    'task-or-site-policy-blocked' { 'The static Chrome bridge is present, but task-level network access or website policy appears to block control.' }
    default { "The Chrome control chain reached the $classification classification." }
}

$reportLines = [System.Collections.Generic.List[string]]::new()
$reportLines.Add('## Codex Windows Chrome control support report')
$reportLines.Add('')
$reportLines.Add('> Generated by a read-only diagnostic. No registry, manifest, Chrome profile, authentication, environment variable, or Codex state was modified.')
$reportLines.Add('')
$reportLines.Add('### Environment')
$reportLines.Add("- Windows: $safeOsCaption; version=$safeOsVersion; build=$safeOsBuild")
$reportLines.Add("- Codex desktop version: $(if ([string]::IsNullOrWhiteSpace($codexVersion)) { 'Unavailable' } else { $codexVersion })")
$reportLines.Add("- Chrome version: $(if ([string]::IsNullOrWhiteSpace($chromeVersion)) { 'Unavailable' } else { $chromeVersion })")
$reportLines.Add("- Extension ID: $ExtensionId")
$reportLines.Add("- Official Chrome setup completed: $officialSetupText")
$reportLines.Add("- Ordinary Codex works: $ordinaryCodexText")
$reportLines.Add("- Computer Use works: $computerUseText")
$reportLines.Add("- Built-in Browser works: $builtInBrowserText")
$reportLines.Add('')
$reportLines.Add('### Observed classification')
$reportLines.Add("- First failing layer: $classification")
$reportLines.Add("- Diagnosis: $diagnosis")
$reportLines.Add('')
$reportLines.Add('### Extension installation')
$reportLines.AddRange([string[]]$extensionLines)
$reportLines.Add('')
$reportLines.Add('### Bundled Chrome plugin')
$reportLines.AddRange([string[]]$pluginLines)
$reportLines.Add('')
$reportLines.Add('### Native Messaging registry status')
$reportLines.AddRange([string[]]$registryLines)
$reportLines.Add('')
$reportLines.Add('### Native host manifest status')
$reportLines.AddRange([string[]]$manifestLines)
$reportLines.Add('')
$reportLines.Add('### Native host process status')
$reportLines.AddRange([string[]]$hostProcessLines)
$reportLines.Add('')
$reportLines.Add('### Redacted runtime signals')
$reportLines.Add("- Recent log files scanned: $($snapshot.RuntimeEvidence.FilesScanned)")
$reportLines.Add('- Matching log lines and raw log content were not returned.')
$reportLines.AddRange([string[]]$runtimeLines)
$reportLines.Add('')
$reportLines.Add('### Steps reported as completed')
$reportLines.AddRange([string[]](@($steps | ForEach-Object { "- $_" })))
$reportLines.Add('')
$reportLines.Add('### Safety boundary')
$reportLines.Add('- No API keys, tokens, cookies, passwords, auth files, browsing history, or complete process command lines are included.')
$reportLines.Add('- No manual Native Host manifest or registry workaround was attempted.')
$reportLines.Add('- The report was not uploaded or submitted anywhere.')
$reportLines.Add('')
$reportLines.Add('## Support request')
$reportLines.Add('')
$reportLines.Add('Codex Windows Chrome control fails at a static bridge, runtime backend, cache-lock, or policy layer.')
$reportLines.Add('')
$reportLines.Add('Environment and evidence:')
$reportLines.Add("- Windows: $safeOsCaption, version $safeOsVersion, build $safeOsBuild")
$reportLines.Add("- Codex desktop version: $(if ([string]::IsNullOrWhiteSpace($codexVersion)) { 'unavailable' } else { $codexVersion })")
$reportLines.Add("- Chrome version: $(if ([string]::IsNullOrWhiteSpace($chromeVersion)) { 'unavailable' } else { $chromeVersion })")
$reportLines.Add("- Chrome extension ID: $ExtensionId")
$reportLines.Add("- Chrome bridge classification: $classification")
$reportLines.Add("- Official remove/reinstall setup completed: $officialSetupText")
$reportLines.Add("- Ordinary Codex works: $ordinaryCodexText")
$reportLines.Add("- Computer Use works: $computerUseText")
$reportLines.Add("- Built-in Browser works: $builtInBrowserText")
$reportLines.Add('')
$reportLines.Add("$supportProblem The official setup flow has been attempted as stated above. Please investigate the first failing layer and, if applicable, why the Windows Native Host setup step is not completing.")
$reportLines.Add('')
$reportLines.Add('If the Chrome side chat loads but control still fails, I will run /feedback in the affected task and include that task ID with this report.')
$reportLines.Add('')
$reportLines.Add('The attached report intentionally excludes credentials, cookies, auth files, browsing history, and raw manifest content.')
$supportBody = $reportLines -join "`r`n"

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $fullOutputPath = [IO.Path]::GetFullPath($OutputPath)
    $parent = Split-Path -Parent $fullOutputPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        throw "Output directory does not exist: $parent"
    }
    [IO.File]::WriteAllText($fullOutputPath, $supportBody, [Text.UTF8Encoding]::new($false))
}

$supportBody
