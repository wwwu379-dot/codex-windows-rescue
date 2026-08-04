# Codex Windows Rescue

A safety-first Codex plugin for diagnosing and recovering Codex on Windows.

This plugin is especially useful when Codex was originally configured with an API key, DeepSeek, cc-switch, API-Switch, a custom provider, or a local router, and was later changed to ChatGPT subscription sign-in. That migration can leave several independent layers behind: active local proxies, startup entries, provider selection, duplicate CLI installations, cached state, and browser-bridge registration.

## Who this is for

Use it when you see one or more of these symptoms:

- Codex keeps reconnecting, is unusually slow, or reports a failed WebSocket or HTTP request.
- Codex was previously connected to DeepSeek, another API provider, cc-switch, API-Switch, or a local router.
- You later started using ChatGPT Plus/Pro/Business sign-in and want to retire only the old Codex route.
- The desktop app and CLI appear to use different versions or configurations.
- Computer Use or the built-in browser works but Chrome control reports `missing native host`, times out, or cannot connect.
- A reset or reinstall made local conversation history disappear.

## The migration problem this plugin addresses

Signing in with ChatGPT does not automatically remove an older API-based setup. A complete migration may require checking all of these separately:

1. Active local routers and listening ports, such as an API-Switch process.
2. Startup folders, Run entries, scheduled tasks, or services that restart them.
3. cc-switch or provider databases that still mark DeepSeek or another provider as current.
4. User-level and project-level Codex configuration, profiles, wrappers, and duplicate CLI sources.
5. Environment variables and proxy variables that may be shared by other software.
6. Codex caches, plugin state, AppX state, and old session databases.

The plugin classifies each finding before proposing a change. It does not treat the existence of a file as permission to delete it.

## What it includes

- A standalone read-only emergency audit for cases where neither Desktop nor CLI can host the plugin.
- A read-only Windows Codex environment audit.
- A guided API/provider-to-ChatGPT migration workflow.
- Proxy inheritance, duplicate-client, process-lock, and selective-state checks.
- Reversible quarantine and targeted backup instead of blind deletion.
- Layered Chrome diagnosis covering the supported Chrome profile, Native Messaging, extension backend, cache locks, task tool attachment, and policy signals—without synthesizing registry or manifest state.
- A redacted support report when the official Chrome setup fails to register the Native Host.
- Transcript-only session salvage that never restores authentication, plugins, cache, provider settings, task databases, or an entire `.codex` directory.

## Safety model

Every mutation follows **explain -> confirm -> act -> verify**. Audits and previews are the default; quarantine is preferred over permanent deletion; one approved change is applied at a time.

The plugin:

- never reads or prints API-key values, tokens, cookies, `auth.json`, or complete secret-bearing command lines;
- never revokes a provider-side API key merely because Codex is migrating to ChatGPT sign-in;
- preserves projects, browser profiles, sessions, v2rayN, and shared proxy variables unless the user explicitly approves a narrowly scoped action;
- distinguishes v2rayN's local proxy from an unrelated API-Switch port;
- does not hand-write OpenAI Chrome Native Host manifests or registry entries;
- stops and prepares a redacted support report when the official Chrome setup has already failed;
- never uploads diagnostics or submits support requests automatically.

## Recommended first use

### If Codex cannot answer at all

The plugin cannot run inside a Codex session that never starts. Use the standalone [emergency kit](emergency-kit/README.md) first:

1. Download and extract the repository ZIP.
2. Copy the self-contained `emergency-kit` folder anywhere you like, keeping its three files together.
3. Double-click `emergency-kit/Run-CodexEmergencyAudit.cmd`.
4. Send the generated Markdown report to web ChatGPT.
5. When either Desktop or CLI works again, install this plugin and continue with the interactive workflow.

This closes the bootstrap gap: the emergency kit is a read-only diagnostic bridge, while the plugin remains the explain-and-confirm repair layer.

### If Desktop or CLI still works

Install the plugin, start a new Codex task, and begin with a read-only request:

```text
Diagnose my Windows Codex problem without changing anything first.
```

If the machine previously used an API key, DeepSeek, cc-switch, or a local router, use:

```text
Audit my old API and cc-switch configuration, then guide me step by step to ChatGPT sign-in. Do not delete or modify anything until I approve each exact action.
```

For Chrome:

```text
Check why Codex Chrome control cannot connect. Start read-only and do not create registry entries or native-host manifests.
```

## Install from GitHub

Add its personal marketplace and install the plugin:

```powershell
codex plugin marketplace add https://github.com/wwwu379-dot/codex-windows-rescue.git --sparse .agents/plugins
codex plugin add codex-windows-rescue@personal
```

Start a new Codex task after installation so the new skills are loaded.

## Chrome limitation by design

The plugin can inspect the Chrome control chain: the supported Google Chrome profile, extension, bundled Chrome plugin, Native Host manifest, registry registration, extension backend, cache locks, and task-policy signals. A valid Native Host proves installation only; it does not prove the current task has a working Chrome backend.

Use `@Chrome` when Codex must use the active signed-in Google Chrome profile. Use the built-in `@Browser` for localhost, public pages, or browsing that should stay inside ChatGPT. Other Chromium browsers are not treated as interchangeable with supported Google Chrome control.

It deliberately does **not** invent or manually write `com.openai.codexextension` state. If the official remove/reinstall setup has completed but the manifest or registry registration is still missing, it classifies the case as an installer or product-lifecycle failure, generates a redacted support report, and stops. This prevents a fragile workaround from silently breaking after an update.

## Session restore limitation by design

The restore workflow safely copies only `sessions` and `archived_sessions`. This salvages transcript files, but newer Codex builds may also use task indexes, history files, SQLite state, and Desktop app state for sidebar discovery and resumability. The plugin inventories those stores read-only and requires separate CLI/Desktop verification; it never auto-merges an old database into a fresh installation.

## Local development

The marketplace definition is at `.agents/plugins/marketplace.json`; the plugin itself is under `plugins/codex-windows-rescue`.

The public repository should contain only the marketplace, plugin source, emergency kit, tests, README, license, and security policy. Keep local work directories, logs, backups, `.codex`, and generated outputs outside the published tree.

Validate the plugin with the official Codex plugin validation tools before installing it into a live environment.

## License

MIT. See [LICENSE](LICENSE).
