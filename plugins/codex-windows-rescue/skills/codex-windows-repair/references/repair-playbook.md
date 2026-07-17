# Targeted repair playbook

## Proxy and reconnect failures

1. Compare the intended local proxy endpoint with user and process environment settings.
2. Verify the local listener.
3. Run `codex doctor` when available to separate HTTP reachability from WebSocket support.
4. If explicit user-level `HTTP_PROXY` and `HTTPS_PROXY` are required, show existing and proposed redacted endpoints, explain affected applications, obtain separate confirmation, then verify in a newly started process.
5. Do not enable TUN or global routing as a generic fix.

## Multiple client sources

List all `codex` resolutions and installed AppX packages. Do not assume npm plus desktop is wrong. Remove one source only when it is obsolete or causing version ambiguity, and use its official uninstaller.

## Plugin runtime or cache

Confirm marketplace source, installed/enabled state, required files, permissions, and exact process locks. Stop only a process whose executable and role are confirmed. Reinstall through official plugin commands or UI. Do not delete an entire plugin tree to fix one plugin.

## State reset

Preserve `sessions` and `archived_sessions`. Exclude `auth.json` from ordinary backups and never read it. Keep the original state quarantined until the new environment and restored sessions are verified.

## Stop conditions

Stop and report when official installation repeatedly fails to create required product-owned state, permissions require ownership takeover, a target is shared with other software, an operation requires invented registry/manifest/credential data, or verification contradicts the diagnosis.
