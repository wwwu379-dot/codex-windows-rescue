[CmdletBinding()]
param(
    [string]$ExtensionId = 'hehggadaopoacecdllhhajmbjkdcmajg',
    [string]$OutputPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ($ExtensionId -notmatch '^[a-p]{32}$') {
    throw 'ExtensionId must be a 32-character Chrome extension ID.'
}

$chromeCandidates = @(
    (Join-Path ${env:ProgramFiles} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$chromePath = @($chromeCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
$chrome = if ($chromePath.Count -gt 0) {
    $item = Get-Item -LiteralPath $chromePath[0]
    [PSCustomObject]@{ Installed = $true; Path = $item.FullName; Version = $item.VersionInfo.ProductVersion }
}
else {
    [PSCustomObject]@{ Installed = $false; Path = $null; Version = $null }
}

$extensionInstalls = @()
$userData = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
if (Test-Path -LiteralPath $userData -PathType Container) {
    $profiles = @(Get-ChildItem -LiteralPath $userData -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -eq 'Default' -or $_.Name -like 'Profile *'
    })
    foreach ($profile in $profiles) {
        $extensionRoot = Join-Path $profile.FullName (Join-Path 'Extensions' $ExtensionId)
        if (Test-Path -LiteralPath $extensionRoot -PathType Container) {
            foreach ($version in Get-ChildItem -LiteralPath $extensionRoot -Directory -ErrorAction SilentlyContinue) {
                $manifest = Join-Path $version.FullName 'manifest.json'
                $extensionInstalls += [PSCustomObject]@{
                    Profile = $profile.Name
                    VersionDirectory = $version.Name
                    ManifestExists = Test-Path -LiteralPath $manifest -PathType Leaf
                }
            }
        }
    }
}

$codexHome = [Environment]::GetEnvironmentVariable('CODEX_HOME', 'Process')
if ([string]::IsNullOrWhiteSpace($codexHome)) { $codexHome = Join-Path $env:USERPROFILE '.codex' }
$pluginCache = Join-Path $codexHome 'plugins\cache'
$pluginRoots = @()
if (Test-Path -LiteralPath $pluginCache -PathType Container) {
    $browserClients = @(Get-ChildItem -LiteralPath $pluginCache -Filter 'browser-client.mjs' -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
        $_.FullName -match '[\\/]chrome[\\/]'
    })
    foreach ($client in $browserClients) {
        $root = Split-Path -Parent (Split-Path -Parent $client.FullName)
        $pluginRoots += [PSCustomObject]@{
            Root = $root
            BrowserClient = Test-Path -LiteralPath (Join-Path $root 'scripts\browser-client.mjs') -PathType Leaf
            Checker = Test-Path -LiteralPath (Join-Path $root 'scripts\check-native-host-manifest.js') -PathType Leaf
            InstallScript = Test-Path -LiteralPath (Join-Path $root 'scripts\installManifest.mjs') -PathType Leaf
            HostExecutable = Test-Path -LiteralPath (Join-Path $root 'extension-host\windows\x64\extension-host.exe') -PathType Leaf
        }
    }
}
$pluginRoots = @($pluginRoots | Sort-Object Root -Unique)

$registryPaths = @(
    'HKCU:\Software\Google\Chrome\NativeMessagingHosts\com.openai.codexextension',
    'HKLM:\Software\Google\Chrome\NativeMessagingHosts\com.openai.codexextension',
    'HKLM:\Software\WOW6432Node\Google\Chrome\NativeMessagingHosts\com.openai.codexextension'
)
$registryEntries = @()
$manifestCandidates = @()
foreach ($path in $registryPaths) {
    $exists = Test-Path -LiteralPath $path
    $manifestPath = $null
    if ($exists) {
        try {
            $manifestPath = (Get-Item -LiteralPath $path -ErrorAction Stop).GetValue('')
            if (-not [string]::IsNullOrWhiteSpace($manifestPath)) { $manifestCandidates += $manifestPath }
        }
        catch {}
    }
    $registryEntries += [PSCustomObject]@{ Path = $path; Exists = $exists; ManifestPath = $manifestPath }
}
$manifestCandidates += Join-Path $env:LOCALAPPDATA 'OpenAI\extension\com.openai.codexextension.json'
$manifestCandidates = @($manifestCandidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)

$manifestResults = @()
foreach ($candidate in $manifestCandidates) {
    $expanded = [Environment]::ExpandEnvironmentVariables($candidate)
    $exists = Test-Path -LiteralPath $expanded -PathType Leaf
    $validJson = $false
    $hostPath = $null
    $hostExists = $false
    $originMatches = $false
    $parseError = $null
    if ($exists) {
        try {
            $manifest = Get-Content -Raw -LiteralPath $expanded -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $validJson = $true
            $hostPath = $manifest.path
            if (-not [string]::IsNullOrWhiteSpace($hostPath)) {
                $hostPath = [Environment]::ExpandEnvironmentVariables($hostPath)
                $hostExists = Test-Path -LiteralPath $hostPath -PathType Leaf
            }
            $expectedOrigin = "chrome-extension://$ExtensionId/"
            $originMatches = @($manifest.allowed_origins) -contains $expectedOrigin
        }
        catch {
            $parseError = $_.Exception.Message
        }
    }
    $manifestResults += [PSCustomObject]@{
        Path = $expanded
        Exists = $exists
        ValidJson = $validJson
        HostPath = $hostPath
        HostExists = $hostExists
        ExpectedOriginPresent = $originMatches
        ParseError = $parseError
    }
}

$extensionPresent = $extensionInstalls.Count -gt 0
$pluginPresent = @($pluginRoots | Where-Object { $_.BrowserClient -and $_.HostExecutable }).Count -gt 0
$registrationPresent = @($registryEntries | Where-Object { $_.Exists }).Count -gt 0
$validManifest = @($manifestResults | Where-Object { $_.Exists -and $_.ValidJson -and $_.HostExists -and $_.ExpectedOriginPresent }).Count -gt 0

$classification = if (-not $chrome.Installed) { 'chrome-missing' }
elseif (-not $extensionPresent) { 'extension-missing' }
elseif (-not $pluginPresent) { 'plugin-files-missing' }
elseif (-not $registrationPresent -or @($manifestResults | Where-Object { $_.Exists }).Count -eq 0) { 'native-host-missing' }
elseif (-not $validManifest) { 'native-host-invalid' }
else { 'ready-for-runtime-test' }

$result = [PSCustomObject]@{
    SchemaVersion = '1.0'
    CollectedAt = (Get-Date).ToString('o')
    ReadOnly = $true
    Classification = $classification
    Chrome = $chrome
    ExtensionId = $ExtensionId
    ExtensionInstalls = @($extensionInstalls)
    PluginRoots = @($pluginRoots)
    RegistryEntries = @($registryEntries)
    Manifests = @($manifestResults)
    ManualRegistryOrManifestCreationSupported = $false
}

$json = $result | ConvertTo-Json -Depth 10
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $parent = Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw "Output directory does not exist: $parent" }
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), $json, [Text.UTF8Encoding]::new($false))
}
$json
