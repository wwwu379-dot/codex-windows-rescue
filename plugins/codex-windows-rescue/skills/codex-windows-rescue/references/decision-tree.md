# Windows Codex decision tree

## Reconnect loop, slow responses, or stream disconnected

1. Run the read-only doctor.
2. Separate ordinary HTTPS reachability from Responses WebSocket support.
3. Check whether Codex inherited the intended proxy without changing VPN mode.
4. If explicit `HTTP_PROXY` and `HTTPS_PROXY` are required, preserve them and verify with `codex doctor`.
5. Check the active Codex version only after transport works.

## Previously used API key, cc-switch, DeepSeek, or a local router

1. Run API-to-ChatGPT migration before other repair.
2. Distinguish active local proxy processes and startup items from historical files.
3. Distinguish Codex-specific provider configuration from API keys used by other applications.
4. Quarantine one exact component at a time.
5. Confirm ChatGPT sign-in only after old routing is inactive.

## Plugin catalog is empty or bundled plugins are missing

1. Check installed app and CLI sources.
2. Check marketplace and cache existence without deleting state.
3. Check permissions and exact process locks.
4. Repair the plugin runtime separately from Chrome Native Messaging.

## Computer Use works but Chrome control fails

1. Confirm the Chrome extension.
2. Confirm the Codex Chrome plugin files.
3. Confirm the Windows Native Messaging manifest and registry registration.
4. If the final two items are absent after official reinstall, route to `codex-chrome-support-report`.
5. Stop repair attempts. Do not synthesize the manifest or registry entries manually.

## Chat history disappeared after reset

1. Locate trusted backups.
2. Count `sessions` and `archived_sessions` files.
3. Preview collisions.
4. Restore only those two categories without overwriting current sessions.

## Reinstall boundary

Use a clean reset only after read-only evidence shows that narrower repair cannot work. A clean reset is diagnostic, not a guaranteed cure for a product bug. Preserve projects, sessions, proxy variables, browser data, and rollback paths first.
