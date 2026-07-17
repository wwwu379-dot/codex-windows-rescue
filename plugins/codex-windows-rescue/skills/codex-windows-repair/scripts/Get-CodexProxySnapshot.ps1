[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-EndpointSummary {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    try {
        $uri = [Uri]$Value
        if ($uri.IsAbsoluteUri) {
            return [PSCustomObject]@{
                Scheme = $uri.Scheme
                Host = $uri.Host
                Port = if ($uri.IsDefaultPort) { $null } else { $uri.Port }
                CredentialsPresent = -not [string]::IsNullOrWhiteSpace($uri.UserInfo)
            }
        }
    }
    catch {}
    return [PSCustomObject]@{ Scheme = $null; Host = '<unparsed>'; Port = $null; CredentialsPresent = $Value -match '@' }
}

$variables = @()
foreach ($name in @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY')) {
    foreach ($scope in @('Process', 'User', 'Machine')) {
        $value = [Environment]::GetEnvironmentVariable($name, $scope)
        $variables += [PSCustomObject]@{
            Name = $name
            Scope = $scope
            Present = -not [string]::IsNullOrWhiteSpace($value)
            Endpoint = if ($name -eq 'NO_PROXY') { $null } else { Get-EndpointSummary -Value $value }
            EntryCount = if ($name -eq 'NO_PROXY' -and -not [string]::IsNullOrWhiteSpace($value)) { @($value -split ',').Count } else { $null }
        }
    }
}

$candidatePorts = @($variables | Where-Object {
    $_.Endpoint -and $_.Endpoint.Host -in @('127.0.0.1', 'localhost', '::1') -and $_.Endpoint.Port
} | ForEach-Object { [int]$_.Endpoint.Port } | Sort-Object -Unique)

$listeners = foreach ($port in $candidatePorts) {
    try {
        $items = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop)
        [PSCustomObject]@{
            Port = $port
            Listening = $items.Count -gt 0
            OwningProcessIds = @($items | Select-Object -ExpandProperty OwningProcess -Unique)
        }
    }
    catch {
        [PSCustomObject]@{ Port = $port; Listening = $false; OwningProcessIds = @() }
    }
}

$winInet = [ordered]@{ Available = $false; ProxyEnabled = $null; ProxyServer = $null }
try {
    $settings = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
    $winInet.Available = $true
    $winInet.ProxyEnabled = [bool]$settings.ProxyEnable
    if ($settings.ProxyServer) {
        $winInet.ProxyServer = ($settings.ProxyServer -replace '://[^/@]+@', '://<redacted>@')
    }
}
catch {}

[PSCustomObject]@{
    SchemaVersion = '1.0'
    CollectedAt = (Get-Date).ToString('o')
    NetworkRequestsPerformed = $false
    Environment = $variables
    LocalListeners = @($listeners)
    WinInet = [PSCustomObject]$winInet
} | ConvertTo-Json -Depth 8
