# Targeted repair playbook

## Proxy and reconnect failures

1. Record the active desktop and CLI versions. Current clients include broader proxy handling than older Windows builds, so do not apply a historical workaround before testing current behavior.
2. Compare the intended local proxy endpoint with Windows system-proxy, user, and process settings, then compare every one with the proxy application's actual mixed/HTTP listener.
3. If the application uses a random mixed port, record the before/after ports. Prefer disabling random rotation and using one fixed endpoint, or update every consumer to the same endpoint. Do not assume the historically common port `10808` is correct on another machine.
4. Verify the exact configured listener. A browser working is not proof that Codex Desktop and the system proxy point to the same local port.
5. Change one variable only, restart the affected client, verify, and stop when the symptom is resolved.
6. Run `codex doctor` when available to separate HTTP reachability from WebSocket support.
7. If the current client still fails WebSocket while HTTPS works, test explicit process-scoped `HTTP_PROXY` and `HTTPS_PROXY` first. Only propose user-level persistence after that controlled test succeeds.
8. Show existing and proposed redacted endpoints, explain affected applications, obtain separate confirmation, then verify in a newly started process.
9. Do not enable TUN or global routing, change DNS, clear caches, or reinstall as a generic first response.

Treat explicit proxy variables as a conditional compatibility fallback, not a universal first step. Preserve a working setup across updates until a same-machine current-version test proves it is no longer needed.

Do not prescribe `.codex/.env` or `supports_websockets = false` solely because a community post recommends it. First establish that the current client or custom provider reads that setting and that the symptom belongs to the HTTPS-ok/WebSocket-fails family rather than simple port drift.

## Multiple client sources

List all `codex` resolutions and installed AppX packages. Do not assume npm plus desktop is wrong. Remove one source only when it is obsolete or causing version ambiguity, and use its official uninstaller.

## Plugin runtime or cache

Confirm marketplace source, installed/enabled state, required files, task-level tool attachment, redacted runtime signals, permissions, and exact process locks. A plugin can be installed and enabled without being attached to the current task. Stop only a process whose executable and role are confirmed. Reinstall through official plugin commands or UI. Do not delete an entire plugin tree to fix one plugin.

## State reset

Preserve `sessions` and `archived_sessions` for transcript salvage, and inventory `session_index.jsonl`, `history.jsonl`, state databases, backups, and desktop metadata without automatically restoring them. Exclude `auth.json` from ordinary backups and never read it. Keep the original state quarantined until both CLI visibility and Desktop task visibility are verified.

## Stop conditions

Stop and report when official installation repeatedly fails to create required product-owned state, permissions require ownership takeover, a target is shared with other software, an operation requires invented registry/manifest/credential data, or verification contradicts the diagnosis.
