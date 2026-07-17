---
name: codex-api-to-chatgpt-migration
description: Safely migrate Windows Codex from API-key, DeepSeek, cc-switch, API-Switch, custom-provider, local-router, or proxy-wrapper setups to ChatGPT subscription sign-in. Use when a user previously configured another API or provider, later subscribed to ChatGPT Plus/Pro/Business, and wants to remove only Codex-related active residue without breaking other applications, v2rayN, shared API keys, projects, sessions, or browser data.
---

# Codex API to ChatGPT Migration

Treat this as an authentication and provider migration, not a generic cleanup. ChatGPT subscription sign-in and API-key usage are separate paths; do not revoke or delete an API key merely because the user now uses ChatGPT.

## Start read-only

Explain the audit scope and run `scripts/Get-CodexMigrationSnapshot.ps1`.

Read [references/migration-checklist.md](references/migration-checklist.md) to classify findings as active routing, shared configuration, historical data, or unrelated software state.

## Build a migration plan

Use this order, skipping absent items:

1. Confirm the intended end state: ChatGPT sign-in for Codex.
2. Identify active API-Switch or equivalent local router processes and ports.
3. Identify startup items that revive those routers.
4. Identify cc-switch/API-Switch data that still declares a current Codex provider.
5. Identify user-level Codex provider/base-URL configuration and profile files.
6. Identify environment variables, but ask whether other software uses them.
7. Identify duplicate Codex command sources or wrappers.
8. Confirm the active login method through the profile UI or `codex login status`; never parse credentials.

Cover every persistence layer before calling the migration complete: active processes and listeners, Startup folders, registry Run entries, scheduled tasks, services, PATH or command wrappers, Codex user/project config, provider environment-variable names, duplicate client installations, and quarantined historical data. Presence alone is not permission to remove anything.

For each finding, classify ownership before proposing a change:

- **Codex-only active residue:** eligible for one-step quarantine after approval.
- **Shared with another application:** preserve it and remove only the Codex reference, if one exists.
- **Historical or already quarantined:** leave it alone during migration.
- **Normal current Codex state:** never describe it as residue merely because it was newly created after reinstall.

## Apply one approved step

Read the shared [safety protocol](../codex-windows-rescue/references/safety-protocol.md). Use `scripts/Invoke-CodexMigrationStep.ps1` only for an exact API-Switch process or one allow-listed path. Run it without `-Apply` first. After the user approves that exact preview, run only that one action with `-Apply -ConfirmationToken APPLY-ONE-STEP`.

Do not automate environment-variable removal or provider-config editing. Present the exact scope and handle each with separate confirmation because other applications may depend on them.

Do not combine stopping a router, disabling persistence, quarantining its files, editing provider config, changing authentication, uninstalling a client, or permanently deleting backups into one approval. Each is a separate user-visible step card.

## Verify the migration

Confirm the retired local router and startup item are inactive, the active Codex config does not select the retired route, the intended command source is unambiguous, ChatGPT sign-in is active, required proxy variables remain unchanged, and normal Codex requests succeed.

Keep quarantined files until the user confirms other API-using applications still work.

Permanent deletion is an optional later phase, never part of initial migration. Explain that deleting a local key copy does not revoke the provider-side key. Recommend provider-side rotation only when exposure is plausible, such as sharing, source-control upload, malware, or unexplained usage; do not rotate a key merely because another approved application still uses it.
