[CmdletBinding()]
param(
    [string[]]$ProjectRoots = @(),
    [string]$OutputPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Test-PathReadSafe {
    param(
        [string]$Path,
        [ValidateSet('Any', 'Container', 'Leaf')]
        [string]$PathType = 'Any'
    )
    try {
        if ($PathType -eq 'Any') {
            return [bool](Test-Path -LiteralPath $Path -ErrorAction Stop)
        }
        return [bool](Test-Path -LiteralPath $Path -PathType $PathType -ErrorAction Stop)
    }
    catch {
        # A read-only audit must continue when a protected or locked path cannot be probed.
        return $null
    }
}

function Get-SessionMetadataInventory {
    param([string]$CodexHome)

    $items = @()
    foreach ($name in @('session_index.jsonl', 'history.jsonl', '.codex-global-state.json')) {
        $path = Join-Path $CodexHome $name
        if (Test-PathReadSafe -Path $path -PathType Leaf) {
            $file = Get-Item -LiteralPath $path
            $items += [PSCustomObject]@{ Name = $name; Kind = 'File'; Bytes = [long]$file.Length; ItemCount = $null; ContentsRead = $false }
        }
    }
    foreach ($file in Get-ChildItem -LiteralPath $CodexHome -File -Filter 'state_*.sqlite*' -ErrorAction SilentlyContinue) {
        $items += [PSCustomObject]@{ Name = $file.Name; Kind = 'File'; Bytes = [long]$file.Length; ItemCount = $null; ContentsRead = $false }
    }
    foreach ($name in @('session_backups', 'generated_images')) {
        $path = Join-Path $CodexHome $name
        if (Test-PathReadSafe -Path $path -PathType Container) {
            $items += [PSCustomObject]@{
                Name = $name
                Kind = 'Directory'
                Bytes = $null
                ItemCount = @(Get-ChildItem -LiteralPath $path -File -Recurse -ErrorAction SilentlyContinue).Count
                ContentsRead = $false
            }
        }
    }
    return @($items | Sort-Object Name -Unique)
}

function Get-SafeEndpoint {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    try {
        $uri = [Uri]$Value
        if ($uri.IsAbsoluteUri) {
            $port = if ($uri.IsDefaultPort) { '' } else { ':' + $uri.Port }
            return '{0}://{1}{2}' -f $uri.Scheme, $uri.Host, $port
        }
    }
    catch {}
    if ($Value.Length -gt 160) { return '<present; value omitted>' }
    return ($Value -replace '://[^/@]+@', '://<redacted>@')
}

function Get-EnvironmentSummary {
    param([string]$Name, [switch]$Secret, [switch]$Endpoint)
    $scopes = foreach ($scope in @('Process', 'User', 'Machine')) {
        $value = [Environment]::GetEnvironmentVariable($Name, $scope)
        [PSCustomObject]@{
            Scope = $scope
            Present = -not [string]::IsNullOrWhiteSpace($value)
            SafeValue = if ([string]::IsNullOrWhiteSpace($value) -or $Secret) {
                $null
            }
            elseif ($Endpoint) {
                Get-SafeEndpoint -Value $value
            }
            else {
                $value
            }
        }
    }
    [PSCustomObject]@{ Name = $Name; Scopes = @($scopes) }
}

function Get-ConfigKeyMatches {
    param([string]$Path)
    if (-not (Test-PathReadSafe -Path $Path -PathType Leaf)) { return @() }
    $patterns = @(
        '^\s*(model_provider|openai_base_url|chatgpt_base_url|base_url|api_key|api_key_env_var|forced_login_method|profile|supports_websockets)\s*=',
        '^\s*\[(model_providers(?:\.[^\]]+)?|profiles(?:\.[^\]]+)?)\s*\]',
        '^\s*(env_key|experimental_bearer_token|requires_openai_auth)\s*='
    )
    $lineNumber = 0
    $matches = foreach ($line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        $lineNumber++
        $trimmed = $line.TrimStart()
        if ($trimmed.StartsWith('#')) { continue }
        foreach ($pattern in $patterns) {
            if ($line -match $pattern) {
                [PSCustomObject]@{ Line = $lineNumber; Key = $Matches[1] }
                break
            }
        }
    }
    return @($matches)
}

function Get-PortSummary {
    param([int]$Port)
    try {
        $items = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop)
        $processIds = @($items | Select-Object -ExpandProperty OwningProcess -Unique)
        $processNames = @($processIds | ForEach-Object {
            try { (Get-Process -Id $_ -ErrorAction Stop).ProcessName } catch { $null }
        } | Where-Object { $_ } | Sort-Object -Unique)
        return [PSCustomObject]@{
            Port = $Port
            Listening = $items.Count -gt 0
            OwningProcessIds = $processIds
            OwningProcessNames = $processNames
        }
    }
    catch {
        return [PSCustomObject]@{ Port = $Port; Listening = $false; OwningProcessIds = @(); OwningProcessNames = @() }
    }
}

function ConvertTo-ProxyEndpoints {
    param(
        [string]$Value,
        [string]$Source,
        [string]$Scope,
        [string]$DefaultProtocol = 'http'
    )
    if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
    $results = @()
    foreach ($part in @($Value -split ';')) {
        $candidate = $part.Trim()
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $protocol = $DefaultProtocol
        if ($candidate -match '^(?<protocol>[A-Za-z][A-Za-z0-9+.-]*)=(?<endpoint>.+)$') {
            $protocol = $Matches.protocol.ToLowerInvariant()
            $candidate = $Matches.endpoint.Trim()
        }
        $uriText = if ($candidate -match '^[A-Za-z][A-Za-z0-9+.-]*://') { $candidate } else { '{0}://{1}' -f $protocol, $candidate }
        try {
            $uri = [Uri]$uriText
            if (-not $uri.IsAbsoluteUri -or [string]::IsNullOrWhiteSpace($uri.Host)) { throw 'Not an absolute proxy URI.' }
            $endpointHost = $uri.Host.ToLowerInvariant()
            $results += [PSCustomObject]@{
                Source = $Source; Scope = $Scope; Protocol = $protocol; Scheme = $uri.Scheme
                Host = $endpointHost; Port = [int]$uri.Port
                IsLoopback = $endpointHost -in @('127.0.0.1', 'localhost', '::1')
                CredentialsPresent = -not [string]::IsNullOrWhiteSpace($uri.UserInfo)
                Parsed = $true
            }
        }
        catch {
            $results += [PSCustomObject]@{
                Source = $Source; Scope = $Scope; Protocol = $protocol; Scheme = $null
                Host = '<unparsed>'; Port = $null; IsLoopback = $false
                CredentialsPresent = $candidate -match '@'; Parsed = $false
                ParseErrorType = $_.Exception.GetType().FullName
            }
        }
    }
    return @($results)
}

function Get-ProxyAlignmentSnapshot {
    $endpoints = @()
    foreach ($name in @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY')) {
        foreach ($scope in @('Process', 'User', 'Machine')) {
            $value = [Environment]::GetEnvironmentVariable($name, $scope)
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $protocol = ($name -replace '_PROXY$', '').ToLowerInvariant()
                $endpoints += @(ConvertTo-ProxyEndpoints -Value $value -Source $name -Scope $scope -DefaultProtocol $protocol)
            }
        }
    }

    $winInet = [ordered]@{ Available = $false; ProxyEnabled = $null; ProxyServerPresent = $false }
    try {
        $settings = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        $winInet.Available = $true
        $winInet.ProxyEnabled = [bool]$settings.ProxyEnable
        $winInet.ProxyServerPresent = -not [string]::IsNullOrWhiteSpace([string]$settings.ProxyServer)
        if ($winInet.ProxyEnabled -and $winInet.ProxyServerPresent) {
            $endpoints += @(ConvertTo-ProxyEndpoints -Value ([string]$settings.ProxyServer) -Source 'WinInet' -Scope 'User' -DefaultProtocol 'http')
        }
    }
    catch {}

    $loopbackEndpoints = @($endpoints | Where-Object { $_.Parsed -and $_.IsLoopback -and $_.Port })
    $configuredPorts = @($loopbackEndpoints | Select-Object -ExpandProperty Port -Unique | Sort-Object)
    $ports = @(@(10808, 15721) + $configuredPorts | Sort-Object -Unique)
    $listeners = @($ports | ForEach-Object { Get-PortSummary -Port ([int]$_) })
    $unmatched = @($loopbackEndpoints | Where-Object {
        $port = $_.Port
        -not (@($listeners | Where-Object { $_.Port -eq $port -and $_.Listening }).Count -gt 0)
    })
    $classification = if ($configuredPorts.Count -gt 1) { 'mixed-endpoint-configuration' }
    elseif ($loopbackEndpoints.Count -eq 0) {
        if ($winInet.Available -and $winInet.ProxyEnabled -eq $false) { 'system-proxy-disabled' } else { 'no-local-proxy-endpoint' }
    }
    elseif ($unmatched.Count -gt 0) { 'proxy-endpoint-not-listening' }
    else { 'proxy-endpoint-listening' }

    return [PSCustomObject]@{
        Classification = $classification
        PortDriftSuspected = ($classification -in @('mixed-endpoint-configuration', 'proxy-endpoint-not-listening'))
        WinInet = [PSCustomObject]$winInet
        Endpoints = @($endpoints)
        ConfiguredLoopbackPorts = $configuredPorts
        LocalListeners = $listeners
        RandomPortSettingInspected = $false
        NetworkRequestsPerformed = $false
    }
}

function Get-IndicatorTags {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $tags = @()
    if ($Text -match '(?i)api-switch|[\\/]\.api-switch[\\/]') { $tags += 'API-Switch' }
    if ($Text -match '(?i)cc-?switch|ccswitch') { $tags += 'cc-switch' }
    if ($Text -match '(?i)deepseek') { $tags += 'DeepSeek' }
    if ($Text -match '(?i)proxy-start\.vbs') { $tags += 'proxy-start.vbs' }
    if ($Text -match '(?i)(?:^|[\\/])codex(?:\.cmd|\.ps1|\.exe)?(?:\s|$|[\\/])') { $tags += 'Codex-wrapper' }
    return @($tags | Sort-Object -Unique)
}

function Get-PersistenceIndicators {
    $findings = @()

    foreach ($location in @(
        [PSCustomObject]@{ Scope = 'User'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' },
        [PSCustomObject]@{ Scope = 'Machine'; Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' },
        [PSCustomObject]@{ Scope = 'Machine32'; Path = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' }
    )) {
        try {
            $item = Get-ItemProperty -LiteralPath $location.Path -ErrorAction Stop
            foreach ($property in $item.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }) {
                $tags = @(Get-IndicatorTags -Text ([string]$property.Value))
                if ($tags.Count -gt 0) {
                    $findings += [PSCustomObject]@{
                        Kind = 'RegistryRun'
                        Scope = $location.Scope
                        Name = $property.Name
                        Indicators = $tags
                        CommandReturned = $false
                    }
                }
            }
        }
        catch {}
    }

    foreach ($startup in @(
        [Environment]::GetFolderPath('Startup'),
        [Environment]::GetFolderPath('CommonStartup')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) {
        try {
            foreach ($item in Get-ChildItem -LiteralPath $startup -File -ErrorAction Stop) {
                $tags = @(Get-IndicatorTags -Text $item.Name)
                if ($tags.Count -gt 0) {
                    $findings += [PSCustomObject]@{
                        Kind = 'StartupFolder'
                        Scope = if ($startup -eq [Environment]::GetFolderPath('Startup')) { 'User' } else { 'Machine' }
                        Name = $item.Name
                        Indicators = $tags
                        CommandReturned = $false
                    }
                }
            }
        }
        catch {}
    }

    try {
        foreach ($task in Get-ScheduledTask -ErrorAction Stop) {
            $actionText = @($task.Actions | ForEach-Object { '{0} {1}' -f $_.Execute, $_.Arguments }) -join ' '
            $tags = @(Get-IndicatorTags -Text $actionText)
            if ($tags.Count -gt 0) {
                $findings += [PSCustomObject]@{
                    Kind = 'ScheduledTask'
                    Scope = 'System'
                    Name = '{0}{1}' -f $task.TaskPath, $task.TaskName
                    Indicators = $tags
                    CommandReturned = $false
                }
            }
        }
    }
    catch {}

    try {
        foreach ($service in Get-CimInstance Win32_Service -ErrorAction Stop) {
            $tags = @(Get-IndicatorTags -Text ('{0} {1} {2}' -f $service.Name, $service.DisplayName, $service.PathName))
            if ($tags.Count -gt 0) {
                $findings += [PSCustomObject]@{
                    Kind = 'Service'
                    Scope = 'System'
                    Name = $service.Name
                    DisplayName = $service.DisplayName
                    State = $service.State
                    StartMode = $service.StartMode
                    Indicators = $tags
                    CommandReturned = $false
                }
            }
        }
    }
    catch {}

    return @($findings)
}

function Get-PathIndicators {
    $findings = @()
    foreach ($scope in @('Process', 'User', 'Machine')) {
        $value = [Environment]::GetEnvironmentVariable('PATH', $scope)
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        foreach ($entry in $value.Split(';') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) {
            $tags = @(Get-IndicatorTags -Text $entry)
            if ($tags.Count -gt 0) {
                $findings += [PSCustomObject]@{
                    Scope = $scope
                    Entry = $entry
                    Indicators = $tags
                }
            }
        }
    }
    return @($findings)
}

$codexHome = [Environment]::GetEnvironmentVariable('CODEX_HOME', 'Process')
if ([string]::IsNullOrWhiteSpace($codexHome)) {
    $codexHome = [Environment]::GetEnvironmentVariable('CODEX_HOME', 'User')
}
if ([string]::IsNullOrWhiteSpace($codexHome)) {
    $codexHome = Join-Path $env:USERPROFILE '.codex'
}
$codexHome = [IO.Path]::GetFullPath($codexHome)

$configPaths = @()
$mainConfig = Join-Path $codexHome 'config.toml'
if (Test-PathReadSafe -Path $mainConfig -PathType Leaf) { $configPaths += $mainConfig }
if (Test-PathReadSafe -Path $codexHome -PathType Container) {
    $configPaths += @(Get-ChildItem -LiteralPath $codexHome -Filter '*.config.toml' -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
}
foreach ($root in $ProjectRoots) {
    if ([string]::IsNullOrWhiteSpace($root)) { continue }
    $projectConfig = Join-Path ([IO.Path]::GetFullPath($root)) '.codex\config.toml'
    if (Test-PathReadSafe -Path $projectConfig -PathType Leaf) { $configPaths += $projectConfig }
}
$configPaths = @($configPaths | Sort-Object -Unique)
$configSummary = foreach ($path in $configPaths) {
    [PSCustomObject]@{ Path = $path; SensitiveKeys = @(Get-ConfigKeyMatches -Path $path) }
}

$commandSources = @()
try {
    $commandSources = @(Get-Command codex -All -ErrorAction Stop | ForEach-Object {
        [PSCustomObject]@{
            CommandType = $_.CommandType.ToString()
            Path = if ($_.Path) { $_.Path } else { $_.Source }
            Version = if ($_.Version) { $_.Version.ToString() } else { $null }
        }
    })
}
catch {}

$appxPackages = @()
try {
    $appxPackages = @(Get-AppxPackage -Name OpenAI.Codex -ErrorAction Stop | ForEach-Object {
        [PSCustomObject]@{ Name = $_.Name; Version = $_.Version.ToString(); InstallLocation = $_.InstallLocation }
    })
}
catch {}

$processes = @()
try {
    $processes = @(Get-CimInstance Win32_Process -ErrorAction Stop | ForEach-Object {
        $category = $null
        if ($_.Name -match '^(codex|chatgpt)(\.exe)?$') { $category = 'Codex' }
        elseif ($_.CommandLine -and $_.CommandLine -match '[\\/]\.api-switch[\\/]proxy\.js') { $category = 'API-Switch' }
        elseif (($_.Name -match 'cc-?switch|ccswitch') -or ($_.CommandLine -and $_.CommandLine -match 'cc-?switch|ccswitch')) { $category = 'cc-switch' }
        if ($category) {
            [PSCustomObject]@{
                ProcessId = [int]$_.ProcessId
                Name = $_.Name
                Category = $category
                ExecutablePath = $_.ExecutablePath
            }
        }
    })
}
catch {}

$knownPaths = @(
    (Join-Path $env:USERPROFILE '.api-switch'),
    (Join-Path $env:USERPROFILE '.api-switch.yaml'),
    (Join-Path $env:USERPROFILE '.cc-switch'),
    (Join-Path $env:LOCALAPPDATA 'com.ccswitch.desktop'),
    (Join-Path $env:APPDATA 'com.ccswitch.desktop'),
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\proxy-start.vbs'),
    (Join-Path $env:LOCALAPPDATA 'OpenAI\Codex'),
    (Join-Path $env:LOCALAPPDATA 'Packages\OpenAI.Codex_2p2nqsd0c76g0')
)
$pathSummary = @($knownPaths | ForEach-Object {
    $exists = Test-PathReadSafe -Path $_
    [PSCustomObject]@{
        Path = $_
        Exists = $exists
        ProbeStatus = if ($null -eq $exists) { 'AccessDeniedOrUnavailable' } else { 'Readable' }
    }
})

$pluginSources = Join-Path $codexHome 'plugins\sources'
$pluginCache = Join-Path $codexHome 'plugins\cache'
$sessionPath = Join-Path $codexHome 'sessions'
$archivedPath = Join-Path $codexHome 'archived_sessions'

$nativeHostPaths = @(
    'HKCU:\Software\Google\Chrome\NativeMessagingHosts\com.openai.codexextension',
    'HKLM:\Software\Google\Chrome\NativeMessagingHosts\com.openai.codexextension',
    'HKLM:\Software\WOW6432Node\Google\Chrome\NativeMessagingHosts\com.openai.codexextension'
)

$environment = @()
foreach ($name in @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY', 'OPENAI_BASE_URL', 'OPENAI_API_BASE', 'CHATGPT_BASE_URL', 'DEEPSEEK_BASE_URL', 'CODEX_BASE_URL', 'CODEX_HOME', 'CODEX_SQLITE_HOME')) {
    $environment += Get-EnvironmentSummary -Name $name -Endpoint:($name -ne 'NO_PROXY' -and $name -notmatch 'HOME$')
}
foreach ($name in @('OPENAI_API_KEY', 'DEEPSEEK_API_KEY', 'CODEX_API_KEY', 'CODEX_ACCESS_TOKEN')) {
    $environment += Get-EnvironmentSummary -Name $name -Secret
}

$persistenceIndicators = @(Get-PersistenceIndicators)
$pathIndicators = @(Get-PathIndicators)
$proxyAlignment = Get-ProxyAlignmentSnapshot

$os = $null
try {
    $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $os = [PSCustomObject]@{ Caption = $osInfo.Caption; Version = $osInfo.Version; BuildNumber = $osInfo.BuildNumber }
}
catch {}

$snapshot = [PSCustomObject]@{
    SchemaVersion = '1.2'
    CollectedAt = (Get-Date).ToString('o')
    OperatingSystem = $os
    CodexHome = $codexHome
    CodexHomeExists = Test-PathReadSafe -Path $codexHome -PathType Container
    AuthStorage = [PSCustomObject]@{
        AuthFileExists = Test-PathReadSafe -Path (Join-Path $codexHome 'auth.json') -PathType Leaf
        ContentsRead = $false
    }
    CommandSources = $commandSources
    AppxPackages = $appxPackages
    Configuration = @($configSummary)
    DotEnv = [PSCustomObject]@{
        Path = Join-Path $codexHome '.env'
        Exists = Test-PathReadSafe -Path (Join-Path $codexHome '.env') -PathType Leaf
        ContentsRead = $false
        AutomaticLoadingAssumed = $false
    }
    Environment = @($environment)
    RelevantProcesses = @($processes)
    PersistenceIndicators = $persistenceIndicators
    PathIndicators = $pathIndicators
    Ports = @($proxyAlignment.LocalListeners)
    ProxyAlignment = $proxyAlignment
    CandidatePaths = $pathSummary
    Plugins = [PSCustomObject]@{
        SourcesPath = $pluginSources
        SourcesExist = Test-PathReadSafe -Path $pluginSources -PathType Container
        SourceCount = @(Get-ChildItem -LiteralPath $pluginSources -Directory -ErrorAction SilentlyContinue).Count
        CachePath = $pluginCache
        CacheExists = Test-PathReadSafe -Path $pluginCache -PathType Container
        MarketplaceCount = @(Get-ChildItem -LiteralPath $pluginCache -Directory -ErrorAction SilentlyContinue).Count
    }
    ChromeNativeHost = [PSCustomObject]@{
        Registry = @($nativeHostPaths | ForEach-Object {
            $exists = Test-PathReadSafe -Path $_
            [PSCustomObject]@{
                Path = $_
                Exists = $exists
                ProbeStatus = if ($null -eq $exists) { 'AccessDeniedOrUnavailable' } else { 'Readable' }
            }
        })
        CommonManifestPath = Join-Path $env:LOCALAPPDATA 'OpenAI\extension\com.openai.codexextension.json'
        CommonManifestExists = Test-PathReadSafe -Path (Join-Path $env:LOCALAPPDATA 'OpenAI\extension\com.openai.codexextension.json') -PathType Leaf
    }
    Sessions = [PSCustomObject]@{
        SessionsPath = $sessionPath
        SessionFileCount = @(Get-ChildItem -LiteralPath $sessionPath -File -Recurse -ErrorAction SilentlyContinue).Count
        ArchivedSessionsPath = $archivedPath
        ArchivedFileCount = @(Get-ChildItem -LiteralPath $archivedPath -File -Recurse -ErrorAction SilentlyContinue).Count
        MetadataInventory = @(Get-SessionMetadataInventory -CodexHome $codexHome)
        TranscriptFilesGuaranteeDesktopVisibility = $false
    }
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
