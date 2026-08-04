# Changelog

## 0.3.0

- Check Windows system-proxy, environment proxy endpoints, and actual local listeners before broader reconnect troubleshooting.
- Classify likely proxy port drift and mixed endpoint configuration, including random mixed-port scenarios, without reading or changing proxy-tool configuration.
- Split reconnect symptoms into proxy-port, HTTPS/WebSocket, app-state/runtime, and client/model version families.
- Keep `.codex/.env` presence read-only and avoid claiming it is automatically loaded; treat `supports_websockets = false` as a provider-specific workaround.
- Recognize the historical `Cannot redefine property: process` Chrome/Computer Use runtime signature and recommend version comparison/update before old cache workarounds.
- Upgrade the standalone emergency kit to schema 1.2 and make offline/no-Codex usage an explicit supported path.

## 0.2.0

- Expand Chrome diagnosis beyond Native Host registration to runtime backend failures, cache locks, task policy/tool attachment, and supported-browser routing.
- Treat explicit proxy environment variables as a version-aware fallback instead of a universal permanent fix.
- Distinguish transcript salvage from Desktop task-index/sidebar restoration and inventory related state read-only.
- Upgrade the standalone emergency kit to schema 1.1 with redacted Chrome runtime signals and session metadata inventory.
- Repair the emergency-kit Chinese README encoding and keep the kit fully self-contained.

## 0.1.0

- Initial Windows Codex diagnosis, migration, repair, Chrome bridge, support-report, and session-restore skills.
- Add the standalone read-only emergency audit for cases where Codex Desktop and CLI cannot run the plugin.
