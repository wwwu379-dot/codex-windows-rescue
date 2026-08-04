[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

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

        $uriText = if ($candidate -match '^[A-Za-z][A-Za-z0-9+.-]*://') {
            $candidate
        }
        else {
            '{0}://{1}' -f $protocol, $candidate
        }

        try {
            $uri = [Uri]$uriText
            if (-not $uri.IsAbsoluteUri -or [string]::IsNullOrWhiteSpace($uri.Host)) { throw 'Not an absolute proxy URI.' }
            $endpointHost = $uri.Host.ToLowerInvariant()
            $results += [PSCustomObject]@{
                Source = $Source
                Scope = $Scope
                Protocol = $protocol
                Scheme = $uri.Scheme
                Host = $endpointHost
                Port = [int]$uri.Port
                IsLoopback = $endpointHost -in @('127.0.0.1', 'localhost', '::1')
                CredentialsPresent = -not [string]::IsNullOrWhiteSpace($uri.UserInfo)
                Parsed = $true
            }
        }
        catch {
            $results += [PSCustomObject]@{
                Source = $Source
                Scope = $Scope
                Protocol = $protocol
                Scheme = $null
                Host = '<unparsed>'
                Port = $null
                IsLoopback = $false
                CredentialsPresent = $candidate -match '@'
                Parsed = $false
                ParseErrorType = $_.Exception.GetType().FullName
            }
        }
    }
    return @($results)
}

function Get-ListenerSummary {
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
        return [PSCustomObject]@{
            Port = $Port
            Listening = $false
            OwningProcessIds = @()
            OwningProcessNames = @()
        }
    }
}

$variables = @()
$endpoints = @()
foreach ($name in @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY')) {
    foreach ($scope in @('Process', 'User', 'Machine')) {
        $value = [Environment]::GetEnvironmentVariable($name, $scope)
        $present = -not [string]::IsNullOrWhiteSpace($value)
        $variables += [PSCustomObject]@{
            Name = $name
            Scope = $scope
            Present = $present
            EntryCount = if ($name -eq 'NO_PROXY' -and $present) { @($value -split ',').Count } else { $null }
        }
        if ($present -and $name -ne 'NO_PROXY') {
            $endpoints += @(ConvertTo-ProxyEndpoints -Value $value -Source $name -Scope $scope -DefaultProtocol ($name -replace '_PROXY$', '').ToLowerInvariant())
        }
    }
}

$winInet = [ordered]@{
    Available = $false
    ProxyEnabled = $null
    ProxyServerPresent = $false
}
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
$portsToInspect = @(@(10808, 15721) + $configuredPorts | Sort-Object -Unique)
$listeners = @($portsToInspect | ForEach-Object { Get-ListenerSummary -Port ([int]$_) })
$unmatched = @($loopbackEndpoints | Where-Object {
    $port = $_.Port
    -not (@($listeners | Where-Object { $_.Port -eq $port -and $_.Listening }).Count -gt 0)
})

$classification = if ($configuredPorts.Count -gt 1) {
    'mixed-endpoint-configuration'
}
elseif ($loopbackEndpoints.Count -eq 0) {
    if ($winInet.Available -and $winInet.ProxyEnabled -eq $false) { 'system-proxy-disabled' } else { 'no-local-proxy-endpoint' }
}
elseif ($unmatched.Count -gt 0) {
    'proxy-endpoint-not-listening'
}
else {
    'proxy-endpoint-listening'
}

[PSCustomObject]@{
    SchemaVersion = '1.1'
    CollectedAt = (Get-Date).ToString('o')
    ReadOnly = $true
    NetworkRequestsPerformed = $false
    Environment = $variables
    WinInet = [PSCustomObject]$winInet
    Endpoints = @($endpoints)
    ConfiguredLoopbackPorts = $configuredPorts
    LocalListeners = $listeners
    Classification = $classification
    PortDriftSuspected = ($classification -in @('mixed-endpoint-configuration', 'proxy-endpoint-not-listening'))
    RandomPortSettingInspected = $false
    RecommendedFirstCheck = 'Compare the Windows system-proxy endpoint with the proxy application actual mixed/HTTP listener. If the application uses a random port, disable random-port rotation or update every consumer to the same fixed endpoint, then verify before changing any other network setting.'
} | ConvertTo-Json -Depth 10
