[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$target = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($TargetPath)).TrimEnd('\')
$matches = @()

try {
    foreach ($process in Get-CimInstance Win32_Process -ErrorAction Stop) {
        $commandMatch = $false
        $executableMatch = $false
        if ($process.CommandLine) {
            $commandMatch = $process.CommandLine.IndexOf($target, [StringComparison]::OrdinalIgnoreCase) -ge 0
        }
        if ($process.ExecutablePath) {
            $executableMatch = $process.ExecutablePath.StartsWith($target, [StringComparison]::OrdinalIgnoreCase)
        }
        if ($commandMatch -or $executableMatch) {
            $matches += [PSCustomObject]@{
                ProcessId = [int]$process.ProcessId
                Name = $process.Name
                ExecutablePath = $process.ExecutablePath
                TargetAppearsInCommandLine = $commandMatch
                ExecutableIsUnderTarget = $executableMatch
                CommandLineReturned = $false
            }
        }
    }
}
catch {}

[PSCustomObject]@{
    SchemaVersion = '1.0'
    CollectedAt = (Get-Date).ToString('o')
    TargetPath = $target
    TargetExists = Test-Path -LiteralPath $target
    Matches = @($matches)
} | ConvertTo-Json -Depth 6
