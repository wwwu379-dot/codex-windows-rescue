---
name: codex-chrome-doctor
description: Diagnose Codex Chrome control on Windows when the extension says missing native host or Connected but control still fails, Chrome tools time out, the extension backend is unavailable, plugins disappear, or Computer Use works while Chrome fails. Check the Chrome profile, plugin files, Native Messaging bridge, host processes, redacted runtime signals, policy blocks, and browser routing read-only; never synthesize product-owned registry or manifest state.
---

# Codex Chrome Doctor

Diagnose Chrome control as a layered chain:

`supported Chrome profile -> extension -> Native Messaging -> host process -> plugin cache -> extension backend -> task policy/tool routing`

## Run read-only checks

Explain the scope, then run `scripts/Test-CodexChromeBridge.ps1`. Pass `-ExtensionId` only when the installed extension ID is known to differ from the default.

Read [references/chrome-control-chain.md](references/chrome-control-chain.md) to classify the first failing layer and decide whether the task should use `@Chrome` or the built-in `@Browser` instead.

## Interpret outcomes

- Extension absent: use the official extension installation flow.
- Plugin files absent or disabled: use official plugin installation or enablement.
- Manifest or registry absent: repeat the official plugin setup once after fully restarting Chrome and Codex.
- Manifest invalid: report the invalid field without printing unrelated content.
- `known-old-runtime-signature-update-first`: the logs contain the historical `Cannot redefine property: process` runtime signature. Record the installed desktop/plugin versions and update through the official channel before trying old cache workarounds.
- `plugin-cache-or-host-lock-suspected`: identify the exact `extension-host.exe` process and official plugin reconciliation failure; do not delete the whole cache.
- `runtime-extension-backend-failure`: the bridge can be valid while the current runtime does not expose or respond through the extension backend. Start one new task and retry once, then report.
- `task-or-site-policy-blocked`: inspect the current task's network/site approval state; reinstalling the bridge does not repair a policy block.
- `runtime-test-required`: start a new task and perform one minimal Chrome test in the same Chrome profile.
- If the official setup has already been completed and the manifest or registry remains absent, route to `$codex-chrome-support-report`.

If the Chrome side chat loads but Codex still cannot use Chrome, tell the user to run `/feedback` in the app and retain the task ID for support.

## Hard boundary

Never manually run a bundled installer script, create `com.openai.codexextension.json`, invent `allowed_origins`, or write `NativeMessagingHosts` registry entries unless current official instructions explicitly require that exact action.

Do not apply an older community cache repair solely because its screenshot resembles the current UI. Compare versions and current runtime evidence first; some widely shared Windows browser/Computer Use failures were fixed in later builds.

If official remove/reinstall completes but the manifest and registry remain absent, classify it as an installer or product lifecycle failure. Produce the redacted facts listed in the reference and stop. Do not reinstall all of Codex repeatedly.
