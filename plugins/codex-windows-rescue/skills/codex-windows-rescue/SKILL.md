---
name: codex-windows-rescue
description: Orchestrate safe diagnosis and recovery for Codex on Windows. Use for reconnect loops including proxy port drift, proxy or WebSocket failures, API/cc-switch/DeepSeek migration residue, duplicate CLI installations, plugin marketplace failures, Computer Use problems, Chrome missing Native Host, damaged local state, clean-reset planning, or missing local chat history. Always diagnose read-only first and require step-by-step explanation, confirmation, verification, and rollback for every mutation.
---

# Codex Windows Rescue

Coordinate the smallest safe workflow that matches the user's symptom. Do not treat every Codex problem as one failure or jump directly to reinstalling.

## Mandatory protocol

Read [references/safety-protocol.md](references/safety-protocol.md) before proposing any mutation. Apply its explain-confirm-act-verify contract to every sub-skill and command.

## Bootstrap boundary

If the user's Codex Desktop cannot answer and no CLI session can load this plugin, do not pretend the plugin can repair its own unavailable host. Direct the user to the repository's standalone `emergency-kit/Run-CodexEmergencyAudit.cmd`. It runs without Codex or network access and creates a local redacted read-only report. If the PC also lacks external access, the user can read the Markdown summary locally or transfer it to another device; web ChatGPT is an optional interpretation channel, not a runtime dependency. Resume the plugin workflow only after Desktop or CLI can host an agent again.

## Route the task

1. Start with `$codex-windows-doctor` for a read-only environment snapshot.
2. If the user previously used an API key, DeepSeek, cc-switch, API-Switch, a custom provider, or a local router and now wants ChatGPT subscription sign-in, route to `$codex-api-to-chatgpt-migration` before general repair.
3. Route approved, user-side repairs to `$codex-windows-repair`.
4. If normal Codex and Computer Use work but Chrome control fails, route to `$codex-chrome-doctor`.
5. If the official Chrome setup has already failed and Native Host registration remains missing or invalid, route to `$codex-chrome-support-report`.
6. If history disappeared after reset or reinstall, route to `$codex-session-restore` and restore only session data.

Read [references/decision-tree.md](references/decision-tree.md) when symptoms overlap.

## Boundaries

- Keep authentication, network, plugin runtime, Chrome Native Messaging, and session storage as separate layers.
- Treat ChatGPT subscription sign-in and API-key usage as distinct authentication and billing paths.
- Never read or display `auth.json`, API-key values, tokens, cookies, or complete process command lines that may contain secrets.
- Never delete `.codex` as a first response. Preserve or export sessions before any reset.
- Never remove `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`, v2rayN, or another shared API key merely because it appears in an audit.
- Never hand-create OpenAI Chrome Native Host manifests or registry entries. If the official setup repeatedly fails, produce a redacted support report and stop.
- Do not claim a product bug caused unrelated historical residue unless evidence connects them.
- Do not tell a user with an unusable Desktop and CLI to install this plugin as their first step; use the standalone emergency audit bridge.

## Finish

Report confirmed root causes, fixes and verification evidence, unresolved boundaries, backup locations, rollback paths, and the single safest next action.
