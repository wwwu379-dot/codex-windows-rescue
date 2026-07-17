---
name: codex-chrome-support-report
description: Create a redacted OpenAI support report when Codex Chrome control remains disconnected after the official Chrome plugin setup. Use for missing Windows Native Messaging manifest or registry registration, while preserving a hard boundary against hand-written product state.
---

# Codex Chrome Support Report

Use this skill after `$codex-chrome-doctor` has found that the Chrome extension and bundled plugin files are present but the Windows Native Messaging Host is missing or invalid after the official remove/reinstall setup flow.

## What this skill does

1. Re-runs the existing read-only Chrome bridge check.
2. Collects only safe diagnostic metadata: Windows build, Codex desktop version, Chrome version, extension/plugin presence, manifest status, registry-key presence, and user-attested setup steps.
3. Classifies the result without claiming more than the evidence supports.
4. Produces a redacted Markdown report and a ready-to-paste English support request.
5. Tells the user what must remain private and does not upload or submit the report.

The report is displayed by default. Saving it to a file requires the user's explicit approval and an exact output path.

## Required safety boundaries

- Do not read or print `auth.json`, API keys, tokens, cookies, browsing history, or complete process command lines.
- Do not create or modify `com.openai.codexextension.json`.
- Do not write `NativeMessagingHosts` registry entries.
- Do not run `installManifest.mjs` directly. It is a product-internal function that requires desktop runtime arguments; invoking it outside the official setup flow can produce an invalid host configuration.
- Do not repeatedly uninstall Codex or Chrome when the official setup has already failed.
- Do not submit the report to OpenAI, GitHub, email, or any other service without separate user approval at action time.

## Run the report

First explain that the command is read-only and that the result will be shown before any optional save.

For a case where the official flow was completed and Computer Use and ordinary Codex work:

```powershell
scripts\Get-CodexChromeSupportReport.ps1 `
  -OfficialSetupCompleted `
  -ComputerUseWorks `
  -OrdinaryCodexWorks
```

If the user has not completed the official remove/reinstall setup, do not label the result a product lifecycle failure; route back to `$codex-chrome-doctor` and explain the supported setup step first.

Optional user-attested steps can be added without including screenshots or logs:

```powershell
scripts\Get-CodexChromeSupportReport.ps1 `
  -OfficialSetupCompleted `
  -StepsAttempted @('Removed the Chrome extension', 'Restarted Chrome and Codex')
```

Only after the user reviews the displayed report may it be saved:

```powershell
scripts\Get-CodexChromeSupportReport.ps1 `
  -OfficialSetupCompleted `
  -OutputPath "$env:USERPROFILE\Desktop\codex-chrome-support-report.md"
```

## Interpretation

- `native-host-missing` + official setup not completed: supported setup is still the next action.
- `native-host-missing` + official setup completed: classify as `installer-or-product-lifecycle-failure` and stop repair attempts.
- `native-host-invalid`: report the failing manifest fields without printing unrelated content; do not rewrite it.
- `ready-for-runtime-test`: start a new task and perform one minimal Chrome connection test.
- Any other classification: continue with the corresponding read-only Chrome doctor branch.

## Handoff

The final response must state:

- the first failing layer;
- what was checked and what was not checked;
- whether the official setup was user-attested as completed;
- whether Computer Use or ordinary Codex work as a comparison;
- that the report is not uploaded;
- the single safest next action.

If the report classifies an installer or product lifecycle failure, tell the user to attach the report to OpenAI support and wait for an official update. After an update, rerun the read-only doctor and generate a fresh report if needed.
