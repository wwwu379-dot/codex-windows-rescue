# Chrome control chain

## Layer 1: Chrome extension

Confirm the expected extension ID exists under at least one Chrome profile and is enabled. Extension presence does not prove the desktop bridge works.

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

## Redacted support facts

Include Windows build, desktop version, Chrome and extension versions, plugin version and required-file presence, Native Host registration/manifest status, official reinstall steps attempted, and whether Computer Use and ordinary Codex work. Exclude tokens, cookies, `auth.json`, API keys, and browsing history.
