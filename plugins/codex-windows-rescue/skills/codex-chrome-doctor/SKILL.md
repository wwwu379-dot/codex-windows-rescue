---
name: codex-chrome-doctor
description: Diagnose the Codex Chrome control chain on Windows when the extension says missing native host, the Chrome plugin is installed but cannot connect, browser-client reports Browser is not available, or Computer Use works while Chrome-specific control fails. Check extension, plugin files, Native Messaging manifest, registry registration, host executable, and allowed origins read-only; never synthesize product-owned registry or manifest state.
---

# Codex Chrome Doctor

Diagnose Chrome control as a separate chain:

`Chrome extension -> Windows Native Messaging registration -> native host executable -> Codex Chrome plugin -> Codex`

## Run read-only checks

Explain the scope, then run `scripts/Test-CodexChromeBridge.ps1`. Pass `-ExtensionId` only when the installed extension ID is known to differ from the default.

Read [references/chrome-control-chain.md](references/chrome-control-chain.md) to classify the first failing layer.

## Interpret outcomes

- Extension absent: use the official extension installation flow.
- Plugin files absent or disabled: use official plugin installation or enablement.
- Manifest or registry absent: repeat the official plugin setup once after fully restarting Chrome and Codex.
- Manifest invalid: report the invalid field without printing unrelated content.
- All static checks pass: start a new task and perform one minimal runtime connection test.
- If the official setup has already been completed and the manifest or registry remains absent, route to `$codex-chrome-support-report`.

## Hard boundary

Never manually run a bundled installer script, create `com.openai.codexextension.json`, invent `allowed_origins`, or write `NativeMessagingHosts` registry entries unless current official instructions explicitly require that exact action.

If official remove/reinstall completes but the manifest and registry remain absent, classify it as an installer or product lifecycle failure. Produce the redacted facts listed in the reference and stop. Do not reinstall all of Codex repeatedly.
