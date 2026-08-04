[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$pluginRoot = Join-Path $repositoryRoot 'plugins\codex-windows-rescue'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('codex-windows-rescue-test-' + [Guid]::NewGuid().ToString('N'))

try {
    foreach ($script in Get-ChildItem -LiteralPath $repositoryRoot -Filter '*.ps1' -File -Recurse) {
        $tokens = $null
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors)
        if (@($errors).Count -gt 0) { throw "Parser error in $($script.FullName): $($errors[0].Message)" }
    }

    $manifest = Get-Content -Raw -LiteralPath (Join-Path $pluginRoot '.codex-plugin\plugin.json') | ConvertFrom-Json
    if ($manifest.version -notmatch '^0\.2\.0\+codex\.\d{14}$') { throw "Unexpected plugin version: $($manifest.version)" }
    if ($manifest.interface.defaultPrompt.Count -gt 3) { throw 'Plugin manifest has more than three default prompts.' }

    foreach ($skill in Get-ChildItem -LiteralPath (Join-Path $pluginRoot 'skills') -Directory) {
        $skillFile = Join-Path $skill.FullName 'SKILL.md'
        if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) { throw "Missing SKILL.md: $($skill.FullName)" }
        $firstLines = @(Get-Content -LiteralPath $skillFile -TotalCount 12)
        $nameLine = @($firstLines | Where-Object { $_ -match '^name:\s*(.+)$' } | Select-Object -First 1)
        if ($nameLine.Count -eq 0) { throw "Missing skill name frontmatter: $skillFile" }
        $declaredName = ($nameLine[0] -replace '^name:\s*', '').Trim()
        if ($declaredName -ne $skill.Name) { throw "Skill folder/name mismatch: $($skill.Name) != $declaredName" }
    }

    $source = Join-Path $testRoot 'backup\.codex.old'
    $destination = Join-Path $testRoot 'current'
    [void](New-Item -ItemType Directory -Path (Join-Path $source 'sessions\2026\08') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $source 'archived_sessions') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $source 'session_backups') -Force)
    'session' | Set-Content -LiteralPath (Join-Path $source 'sessions\2026\08\task.jsonl')
    'archive' | Set-Content -LiteralPath (Join-Path $source 'archived_sessions\old.jsonl')
    'index placeholder' | Set-Content -LiteralPath (Join-Path $source 'session_index.jsonl')
    'sqlite placeholder' | Set-Content -LiteralPath (Join-Path $source 'state_5.sqlite')
    'backup placeholder' | Set-Content -LiteralPath (Join-Path $source 'session_backups\one.jsonl')

    $restoreScript = Join-Path $pluginRoot 'skills\codex-session-restore\scripts\Restore-CodexSessions.ps1'
    $restore = (& $restoreScript -SourceRoot $source -DestinationRoot $destination | Out-String) | ConvertFrom-Json
    if ($restore.SchemaVersion -ne '1.1' -or $restore.RestoreMode -ne 'TranscriptSalvage') { throw 'Session restore schema/mode is outdated.' }
    if ($restore.DesktopVisibilityGuaranteed -ne $false -or $restore.AutomaticIndexOrDatabaseMerge -ne $false) { throw 'Session restore overstates Desktop/index behavior.' }
    if (@($restore.MetadataInventory).Count -lt 3) { throw 'Session restore did not inventory nearby index/state files.' }
    if (@($restore.Plan).Count -ne 2) { throw 'Session restore planned files outside the two transcript categories.' }

    $fakeCodex = Join-Path $testRoot 'fake-codex'
    $fakeChrome = Join-Path $testRoot 'fake-chrome'
    $fakeLocal = Join-Path $testRoot 'fake-local'
    [void](New-Item -ItemType Directory -Path (Join-Path $fakeCodex 'logs') -Force)
    [void](New-Item -ItemType Directory -Path $fakeChrome -Force)
    [void](New-Item -ItemType Directory -Path $fakeLocal -Force)
    @'
plugin_cache_windows_file_lock
Browser is not available: extension
SECRET-LINE-SHOULD-NOT-BE-RETURNED
'@ | Set-Content -LiteralPath (Join-Path $fakeCodex 'logs\diagnostic.log')

    $chromeScript = Join-Path $pluginRoot 'skills\codex-chrome-doctor\scripts\Test-CodexChromeBridge.ps1'
    $chrome = (& $chromeScript -CodexHome $fakeCodex -ChromeUserData $fakeChrome -LocalAppData $fakeLocal | Out-String) | ConvertFrom-Json
    if ($chrome.SchemaVersion -ne '1.1') { throw 'Chrome doctor schema is outdated.' }
    if ($chrome.RuntimeEvidence.RawLogContentReturned -ne $false) { throw 'Chrome doctor claims raw log content was returned.' }
    if (@($chrome.RuntimeEvidence.Signals | Where-Object Present).Count -lt 2) { throw 'Chrome doctor did not recognize synthetic runtime signals.' }
    $chromeJson = $chrome | ConvertTo-Json -Depth 12
    if ($chromeJson -like '*SECRET-LINE-SHOULD-NOT-BE-RETURNED*') { throw 'Chrome doctor leaked raw log content.' }

    Write-Host 'PASS: plugin compatibility checks completed.' -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
