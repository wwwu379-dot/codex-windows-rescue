# Targeted repair playbook

## Proxy and reconnect failures

1. Record the active desktop and CLI versions. Current clients include broader proxy handling than older Windows builds, so do not apply a historical workaround before testing current behavior.
2. Compare the intended local proxy endpoint with Windows system-proxy, user, and process settings.
3. Verify the local listener.
4. Run `codex doctor` when available to separate HTTP reachability from WebSocket support.
5. If the current client still fails WebSocket while HTTPS works, test explicit process-scoped `HTTP_PROXY` and `HTTPS_PROXY` first. Only propose user-level persistence after that controlled test succeeds.
6. Show existing and proposed redacted endpoints, explain affected applications, obtain separate confirmation, then verify in a newly started process.
7. Do not enable TUN or global routing as a generic fix.

Treat explicit proxy variables as a conditional compatibility fallback, not a universal first step. Preserve a working setup across updates until a same-machine current-version test proves it is no longer needed.

## Multiple client sources

List all `codex` resolutions and installed AppX packages. Do not assume npm plus desktop is wrong. Remove one source only when it is obsolete or causing version ambiguity, and use its official uninstaller.

## Plugin runtime or cache

Confirm marketplace source, installed/enabled state, required files, task-level tool attachment, redacted runtime signals, permissions, and exact process locks. A plugin can be installed and enabled without being attached to the current task. Stop only a process whose executable and role are confirmed. Reinstall through official plugin commands or UI. Do not delete an entire plugin tree to fix one plugin.

## State reset

Preserve `sessions` and `archived_sessions` for transcript salvage, and inventory `session_index.jsonl`, `history.jsonl`, state databases, backups, and desktop metadata without automatically restoring them. Exclude `auth.json` from ordinary backups and never read it. Keep the original state quarantined until both CLI visibility and Desktop task visibility are verified.

## Stop conditions

Stop and report when official installation repeatedly fails to create required product-owned state, permissions require ownership takeover, a target is shared with other software, an operation requires invented registry/manifest/credential data, or verification contradicts the diagnosis.
