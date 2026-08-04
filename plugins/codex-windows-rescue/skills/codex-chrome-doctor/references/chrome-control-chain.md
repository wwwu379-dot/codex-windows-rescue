# Chrome control chain

## Layer 1: Chrome extension

Confirm the expected extension ID exists under the Chrome profile the user is actually using. A filesystem check proves installation, not whether Chrome currently enables it. Other Chromium browsers are not a supported substitute.

## Layer 2: Codex Chrome plugin

Confirm an installed plugin version and required files such as:

- `scripts/browser-client.mjs`
- `scripts/check-native-host-manifest.js`
- `extension-host/windows/x64/extension-host.exe`

Plugin files do not prove Native Messaging registration exists.

## Layer 3: Windows Native Messaging

Check:

- `HKCU\Software\Google\Chrome\NativeMessagingHosts\com.openai.codexextension`
- supported machine-level equivalents;
- the manifest path referenced by the registry;
- `%LOCALAPPDATA%\OpenAI\extension\com.openai.codexextension.json` as the common user-level location.

If a manifest exists, verify valid JSON, a real host executable path, and an allowed origin matching the installed extension. Do not print credentials or unrelated browser data.

## Layer 4: Runtime connection

Attempt runtime control only after static layers pass. Use the official Chrome control skill or bundled client. Do not substitute desktop Computer Use or unrelated browser automation because that would test a different chain.

Static success does not prove runtime success. Distinguish these cases:

- the runtime exposes only the built-in browser and not the extension backend;
- the extension backend exists but `browser.user.openTabs()` or equivalent startup calls time out;
- `extension-host.exe` locks a mutable plugin-cache entry and plugin reconciliation fails;
- the current task does not have the Chrome tool attached or the model routes to another browser;
- the task or requested site is blocked by network/site policy.

Use recent logs only as redacted signals: return signal names and counts, never matching lines or full log content. A stale signal is supporting evidence, not proof of the current failure.

## Choose the right browser

- Use `@Chrome` when the task needs the user's existing signed-in Chrome profile, open tabs, or selected page text.
- Use `@Browser` for localhost, public pages, or browsing that should remain inside ChatGPT.
- Do not diagnose a successful built-in-browser task as proof that the Chrome extension chain works.

## Redacted support facts

Include Windows build, desktop version, Chrome and extension versions, active Chrome profile, plugin version and required-file presence, Native Host registration/manifest status, host-process presence, redacted runtime-signal counts, official reinstall steps attempted, and whether Computer Use, built-in Browser, and ordinary Codex work. Exclude tokens, cookies, `auth.json`, API keys, raw log lines, and browsing history.
