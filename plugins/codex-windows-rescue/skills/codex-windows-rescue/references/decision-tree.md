# Windows Codex decision tree

## Reconnect loop, slow responses, or stream disconnected

1. Run the read-only doctor.
2. Compare the Windows system-proxy endpoint, process/user proxy endpoints, and the proxy application's actual mixed/HTTP listener. A random-port feature can leave Windows or Codex pointing at yesterday's port even while ordinary browser traffic appears normal.
3. If the configured loopback port is not listening, or different layers use different ports, align one fixed endpoint and verify before changing anything else. Do not combine this test with TUN, global routing, DNS, cache, or reinstall changes.
4. If endpoints align, separate ordinary HTTPS reachability from Responses WebSocket support.
5. Record the current client version and prefer current built-in proxy behavior. If HTTPS works but WebSocket still fails, test process-scoped `HTTP_PROXY` and `HTTPS_PROXY` as a compatibility fallback.
6. Treat `.codex/.env` and custom-provider `supports_websockets = false` as version/provider-specific ideas, not universal fixes. Do not assume `.env` is automatically loaded without current evidence.
7. If reconnecting happens only on the first turn, after tool calls, during remote-environment hydration, or while the app-server connection itself remains alive, classify it as an application/state family rather than a proxy-port failure.
8. Persist explicit variables only after the controlled test succeeds, then verify in a newly started process.
9. If the server reports a model/client mismatch after transport works, update the client and re-test.

Use these reconnect families in the report:

- `proxy-port-drift`: configured local endpoint does not match a listener, often after random-port rotation.
- `https-ok-websocket-fails`: ordinary requests work but the Responses WebSocket path does not.
- `app-state-or-runtime-race`: reconnecting is tied to first-turn state, tool completion, child-process startup, or remote hydration.
- `client-or-model-version-mismatch`: transport works and the server explicitly requires a newer client.
- `unclassified`: evidence is insufficient; change nothing and collect one more targeted observation.

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

1. Decide whether the task actually requires the signed-in Chrome profile; use the built-in `@Browser` for localhost or public browsing.
2. Confirm the extension exists in the active Google Chrome profile.
3. Confirm the Codex Chrome plugin files.
4. Confirm the Windows Native Messaging manifest and registry registration.
5. If static checks pass, inspect Native Host processes, redacted runtime backend/cache-lock signals, current-task tool attachment, and network/site policy.
6. Start one new task for a minimal runtime test; do not treat Computer Use or the built-in Browser as proof that Chrome works.
7. If the official matching troubleshooting step fails, route to `codex-chrome-support-report`; when the side chat loads but control fails, include `/feedback` and the task ID.
8. Stop repair attempts. Do not synthesize the manifest or registry entries manually.

## Chat history disappeared after reset

1. Locate trusted backups.
2. Inventory `sessions`, `archived_sessions`, `session_index.jsonl`, `history.jsonl`, state databases, backups, and desktop metadata.
3. Preview collisions.
4. Restore only those two transcript categories without overwriting current sessions.
5. Verify CLI and Desktop separately. If files exist but tasks remain invisible, diagnose index/path mapping and stop instead of copying the whole old `.codex`.

## Reinstall boundary

Use a clean reset only after read-only evidence shows that narrower repair cannot work. A clean reset is diagnostic, not a guaranteed cure for a product bug. Preserve projects, sessions, proxy variables, browser data, and rollback paths first.
