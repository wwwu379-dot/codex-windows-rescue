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
        return $null
    }
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
    return '<present; value omitted>'
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
                '<present; value omitted>'
            }
        }
    }
    return [PSCustomObject]@{ Name = $Name; Scopes = @($scopes) }
}

function Get-ConfigKeyMatches {
    param([string]$Path)
    if (-not (Test-PathReadSafe -Path $Path -PathType Leaf)) { return @() }

    $patterns = @(
        '^\s*(model_provider|openai_base_url|chatgpt_base_url|base_url|api_key|api_key_env_var|forced_login_method|profile)\s*=',
        '^\s*\[(model_providers(?:\.[^\]]+)?|profiles(?:\.[^\]]+)?)\s*\]',
        '^\s*(env_key|experimental_bearer_token|requires_openai_auth)\s*='
    )
    $lineNumber = 0
    $matches = foreach ($line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        $lineNumber++
        if ($line.TrimStart().StartsWith('#')) { continue }
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
        return [PSCustomObject]@{
            Port = $Port
            Listening = $items.Count -gt 0
            OwningProcessIds = @($items | Select-Object -ExpandProperty OwningProcess -Unique)
        }
    }
    catch {
        return [PSCustomObject]@{ Port = $Port; Listening = $false; OwningProcessIds = @() }
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

function Get-RuntimeSignalSummary {
    param([string]$Root, [int]$FileLimit = 20)

    $definitions = @(
        [PSCustomObject]@{ Name = 'ExtensionBackendUnavailable'; Pattern = 'Browser is not available:\s*extension|extension backend.{0,80}unavailable' },
        [PSCustomObject]@{ Name = 'OpenTabsTimeout'; Pattern = 'browser\.user\.openTabs|openTabs.{0,80}(timed out|timeout)' },
        [PSCustomObject]@{ Name = 'PluginCacheFileLock'; Pattern = 'plugin_cache_windows_file_lock|bundled_plugins_.{0,120}(Access is denied|os error 5)' },
        [PSCustomObject]@{ Name = 'NativeHostInstallRequested'; Pattern = 'chrome_native_host_install_requested' },
        [PSCustomObject]@{ Name = 'BuiltInBrowserReady'; Pattern = 'browser_use_iab_backend_startup_ready|iab backend startup ready' },
        [PSCustomObject]@{ Name = 'ExtensionBackendReady'; Pattern = '(extension|chrome).{0,80}backend.{0,80}startup.{0,40}ready' },
        [PSCustomObject]@{ Name = 'PolicyBlocked'; Pattern = 'network_access\s*=\s*false|admin-enforced policy|blocked by.{0,80}policy|security policy' }
    )
    $logFiles = @()
    foreach ($relative in @('log', 'logs')) {
        $logRoot = Join-Path $Root $relative
        if (Test-PathReadSafe -Path $logRoot -PathType Container) {
            $logFiles += @(Get-ChildItem -LiteralPath $logRoot -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in @('.log', '.jsonl', '.txt') })
        }
    }
    $logFiles = @($logFiles | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First $FileLimit)
    $signals = foreach ($definition in $definitions) {
        $matches = if ($logFiles.Count -gt 0) {
            @(Select-String -LiteralPath $logFiles.FullName -Pattern $definition.Pattern -AllMatches -ErrorAction SilentlyContinue)
        }
        else { @() }
        [PSCustomObject]@{ Name = $definition.Name; MatchCount = @($matches).Count; Present = @($matches).Count -gt 0 }
    }
    return [PSCustomObject]@{
        FilesScanned = $logFiles.Count
        NewestLogWriteTimeUtc = if ($logFiles.Count -gt 0) { $logFiles[0].LastWriteTimeUtc.ToString('o') } else { $null }
        RawLogContentReturned = $false
        Signals = @($signals)
    }
}

function Get-WindowsCodexSnapshot {
    param([string[]]$Roots)

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
    foreach ($root in $Roots) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        $projectConfig = Join-Path ([IO.Path]::GetFullPath($root)) '.codex\config.toml'
        if (Test-PathReadSafe -Path $projectConfig -PathType Leaf) { $configPaths += $projectConfig }
    }
    $configuration = @($configPaths | Sort-Object -Unique | ForEach-Object {
        [PSCustomObject]@{ Path = $_; SensitiveKeys = @(Get-ConfigKeyMatches -Path $_) }
    })

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
            [PSCustomObject]@{
                Name = $_.Name
                Version = $_.Version.ToString()
                InstallLocation = $_.InstallLocation
            }
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
    $candidatePaths = @($knownPaths | ForEach-Object {
        $exists = Test-PathReadSafe -Path $_
        [PSCustomObject]@{
            Path = $_
            Exists = $exists
            ProbeStatus = if ($null -eq $exists) { 'AccessDeniedOrUnavailable' } else { 'Readable' }
        }
    })

    $environment = @()
    foreach ($name in @(
        'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY',
        'OPENAI_BASE_URL', 'OPENAI_API_BASE', 'CHATGPT_BASE_URL',
        'DEEPSEEK_BASE_URL', 'CODEX_BASE_URL', 'CODEX_HOME', 'CODEX_SQLITE_HOME'
    )) {
        $environment += Get-EnvironmentSummary -Name $name -Endpoint:($name -notin @('NO_PROXY', 'CODEX_HOME', 'CODEX_SQLITE_HOME'))
    }
    foreach ($name in @('OPENAI_API_KEY', 'DEEPSEEK_API_KEY', 'CODEX_API_KEY', 'CODEX_ACCESS_TOKEN')) {
        $environment += Get-EnvironmentSummary -Name $name -Secret
    }

    $pluginSources = Join-Path $codexHome 'plugins\sources'
    $pluginCache = Join-Path $codexHome 'plugins\cache'
    $sessionPath = Join-Path $codexHome 'sessions'
    $archivedPath = Join-Path $codexHome 'archived_sessions'

    $os = $null
    try {
        $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $os = [PSCustomObject]@{
            Caption = $osInfo.Caption
            Version = $osInfo.Version
            BuildNumber = $osInfo.BuildNumber
        }
    }
    catch {}

    return [PSCustomObject]@{
        SchemaVersion = '1.1'
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
        Configuration = $configuration
        Environment = @($environment)
        RelevantProcesses = $processes
        PersistenceIndicators = @(Get-PersistenceIndicators)
        Ports = @((Get-PortSummary -Port 10808), (Get-PortSummary -Port 15721))
        CandidatePaths = $candidatePaths
        Plugins = [PSCustomObject]@{
            SourcesPath = $pluginSources
            SourcesExist = Test-PathReadSafe -Path $pluginSources -PathType Container
            SourceCount = @(Get-ChildItem -LiteralPath $pluginSources -Directory -ErrorAction SilentlyContinue).Count
            CachePath = $pluginCache
            CacheExists = Test-PathReadSafe -Path $pluginCache -PathType Container
            MarketplaceCount = @(Get-ChildItem -LiteralPath $pluginCache -Directory -ErrorAction SilentlyContinue).Count
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
}

function Get-ChromeBridgeSnapshot {
    param([string]$ExtensionId = 'hehggadaopoacecdllhhajmbjkdcmajg')

    $chromeCandidates = @(
        (Join-Path ${env:ProgramFiles} 'Google\Chrome\Application\chrome.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $chromePath = @($chromeCandidates | Where-Object {
        Test-PathReadSafe -Path $_ -PathType Leaf
    } | Select-Object -First 1)
    $chrome = if ($chromePath.Count -gt 0) {
        $item = Get-Item -LiteralPath $chromePath[0]
        [PSCustomObject]@{
            Installed = $true
            Path = $item.FullName
            Version = $item.VersionInfo.ProductVersion
        }
    }
    else {
        [PSCustomObject]@{ Installed = $false; Path = $null; Version = $null }
    }

    $extensionInstalls = @()
    $userData = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
    if (Test-PathReadSafe -Path $userData -PathType Container) {
        $profiles = @(Get-ChildItem -LiteralPath $userData -Directory -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -eq 'Default' -or $_.Name -like 'Profile *'
        })
        foreach ($profile in $profiles) {
            $extensionRoot = Join-Path $profile.FullName (Join-Path 'Extensions' $ExtensionId)
            if (Test-PathReadSafe -Path $extensionRoot -PathType Container) {
                foreach ($version in Get-ChildItem -LiteralPath $extensionRoot -Directory -ErrorAction SilentlyContinue) {
                    $extensionInstalls += [PSCustomObject]@{
                        Profile = $profile.Name
                        VersionDirectory = $version.Name
                        ManifestExists = Test-PathReadSafe -Path (Join-Path $version.FullName 'manifest.json') -PathType Leaf
                    }
                }
            }
        }
    }

    $codexHome = [Environment]::GetEnvironmentVariable('CODEX_HOME', 'Process')
    if ([string]::IsNullOrWhiteSpace($codexHome)) { $codexHome = Join-Path $env:USERPROFILE '.codex' }
    $pluginCache = Join-Path $codexHome 'plugins\cache'
    $pluginRoots = @()
    if (Test-PathReadSafe -Path $pluginCache -PathType Container) {
        $browserClients = @(Get-ChildItem -LiteralPath $pluginCache -Filter 'browser-client.mjs' -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
            $_.FullName -match '[\\/]chrome[\\/]'
        })
        foreach ($client in $browserClients) {
            $root = Split-Path -Parent (Split-Path -Parent $client.FullName)
            $pluginRoots += [PSCustomObject]@{
                Root = $root
                BrowserClient = Test-PathReadSafe -Path (Join-Path $root 'scripts\browser-client.mjs') -PathType Leaf
                Checker = Test-PathReadSafe -Path (Join-Path $root 'scripts\check-native-host-manifest.js') -PathType Leaf
                InstallScript = Test-PathReadSafe -Path (Join-Path $root 'scripts\installManifest.mjs') -PathType Leaf
                HostExecutable = Test-PathReadSafe -Path (Join-Path $root 'extension-host\windows\x64\extension-host.exe') -PathType Leaf
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
        $exists = Test-PathReadSafe -Path $path
        $manifestPath = $null
        if ($exists) {
            try {
                $manifestPath = (Get-Item -LiteralPath $path -ErrorAction Stop).GetValue('')
                if (-not [string]::IsNullOrWhiteSpace($manifestPath)) { $manifestCandidates += $manifestPath }
            }
            catch {}
        }
        $registryEntries += [PSCustomObject]@{
            Path = $path
            Exists = $exists
            ManifestPath = $manifestPath
        }
    }
    $manifestCandidates += Join-Path $env:LOCALAPPDATA 'OpenAI\extension\com.openai.codexextension.json'
    $manifestCandidates = @($manifestCandidates | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    } | Sort-Object -Unique)

    $manifestResults = @()
    foreach ($candidate in $manifestCandidates) {
        $expanded = [Environment]::ExpandEnvironmentVariables($candidate)
        $exists = Test-PathReadSafe -Path $expanded -PathType Leaf
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
                    $hostExists = Test-PathReadSafe -Path $hostPath -PathType Leaf
                }
                $originMatches = @($manifest.allowed_origins) -contains "chrome-extension://$ExtensionId/"
            }
            catch {
                $parseError = 'Manifest JSON could not be parsed; error details omitted.'
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
    $validManifest = @($manifestResults | Where-Object {
        $_.Exists -and $_.ValidJson -and $_.HostExists -and $_.ExpectedOriginPresent
    }).Count -gt 0
    $staticClassification = if (-not $chrome.Installed) { 'chrome-missing' }
    elseif (-not $extensionPresent) { 'extension-missing' }
    elseif (-not $pluginPresent) { 'plugin-files-missing' }
    elseif (-not $registrationPresent -or @($manifestResults | Where-Object Exists).Count -eq 0) { 'native-host-missing' }
    elseif (-not $validManifest) { 'native-host-invalid' }
    else { 'ready-for-runtime-test' }

    $nativeHostProcesses = @()
    try {
        $nativeHostProcesses = @(Get-CimInstance Win32_Process -Filter "Name = 'extension-host.exe'" -ErrorAction Stop | ForEach-Object {
            [PSCustomObject]@{
                ProcessId = [int]$_.ProcessId
                Name = $_.Name
                ExecutablePath = $_.ExecutablePath
                CommandLineReturned = $false
            }
        })
    }
    catch {}

    $runtimeEvidence = Get-RuntimeSignalSummary -Root $codexHome
    function Test-RuntimeSignal {
        param([string]$Name)
        return @($runtimeEvidence.Signals | Where-Object { $_.Name -eq $Name -and $_.Present }).Count -gt 0
    }
    $classification = if ($staticClassification -ne 'ready-for-runtime-test') { $staticClassification }
    elseif (Test-RuntimeSignal -Name 'PluginCacheFileLock') { 'plugin-cache-or-host-lock-suspected' }
    elseif ((Test-RuntimeSignal -Name 'ExtensionBackendUnavailable') -or (Test-RuntimeSignal -Name 'OpenTabsTimeout')) { 'runtime-extension-backend-failure' }
    elseif (Test-RuntimeSignal -Name 'PolicyBlocked') { 'task-or-site-policy-blocked' }
    else { 'runtime-test-required' }

    return [PSCustomObject]@{
        SchemaVersion = '1.1'
        CollectedAt = (Get-Date).ToString('o')
        ReadOnly = $true
        Classification = $classification
        StaticClassification = $staticClassification
        Chrome = $chrome
        ExtensionId = $ExtensionId
        ExtensionInstalls = $extensionInstalls
        PluginRoots = $pluginRoots
        RegistryEntries = $registryEntries
        Manifests = $manifestResults
        NativeHostProcesses = @($nativeHostProcesses)
        RuntimeEvidence = $runtimeEvidence
        BrowserRouting = [PSCustomObject]@{
            Chrome = 'Use for pages already signed in through the active Google Chrome profile.'
            BuiltInBrowser = 'Use @Browser for localhost, public pages, or browsing that should stay inside ChatGPT.'
            OtherChromiumBrowsersSupported = $false
        }
        ManualRegistryOrManifestCreationSupported = $false
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
$windows = Get-WindowsCodexSnapshot -Roots $ProjectRoots
$chrome = $null
$chromeError = $null
try {
    $chrome = Get-ChromeBridgeSnapshot
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
    SchemaVersion = '1.1'
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
Add-Line $lines "- Nearby task index/state items (inventory only): $(@($safeWindows.Sessions.MetadataInventory).Count)"
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
    Add-Line $lines "- Native Host processes: $(@($safeChrome.NativeHostProcesses).Count)"
    Add-Line $lines "- Recent diagnostic log files scanned: $($safeChrome.RuntimeEvidence.FilesScanned)"
    foreach ($signal in @($safeChrome.RuntimeEvidence.Signals | Where-Object Present)) {
        Add-Line $lines "- Runtime signal: $($signal.Name) ($($signal.MatchCount))"
    }
    Add-Line $lines '- Use @Chrome for the active signed-in Google Chrome profile; use @Browser for localhost, public pages, or in-app browsing.'
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
Add-Line $lines '5. If transcript files exist but tasks are missing from the Desktop sidebar, treat that as an index/state problem; do not restore an entire old .codex directory.'

[IO.File]::WriteAllLines($reportPath, $lines, [Text.UTF8Encoding]::new($false))
Write-Host "Report created: $reportPath" -ForegroundColor Green
Write-Host "Snapshot created: $snapshotPath" -ForegroundColor Green

[PSCustomObject]@{
    ReportPath = $reportPath
    SnapshotPath = $snapshotPath
    ReadOnly = $true
}
