---
name: codex-session-restore
description: Safely salvage local Codex transcript files on Windows after reinstall, reset, or state quarantine by previewing and copying only `sessions` and `archived_sessions` from trusted backups. Use when old tasks disappeared but backup `.codex` directories remain. Distinguish transcript recovery from Desktop sidebar/index recovery, inventory related metadata read-only, and never restore authentication, config, plugins, caches, SQLite state, provider settings, or the entire old `.codex` directory.
---

# Codex Session Restore

Restore conversation files without reintroducing the state that caused the reset. This is transcript salvage: copying the files does not guarantee that every task will immediately appear in the Desktop sidebar or remain resumable.

## Preview

1. Ask the user to close Codex so session indexes are not changing.
2. Identify the exact trusted backup roots.
3. Run `scripts/Restore-CodexSessions.ps1` without `-Apply`.
4. Show source directories, file counts, destination, existing-file skips, conflicts, and a read-only inventory of nearby task-index/state files.
5. Explain that the script will not copy config, auth, plugins, cache, logs, or databases.

Read [references/session-boundaries.md](references/session-boundaries.md) before requesting approval.

## Restore

After the user approves the displayed preview, run the same command with `-Apply -ConfirmationToken RESTORE-SESSIONS`. Do not add new source roots after approval.

The script must never overwrite an existing destination file. Treat a different file at the same relative path as a conflict and leave both source and destination untouched.

## Verify

Compare copied, skipped, and conflict counts with the preview. Restart Codex and verify three things separately: CLI task visibility, Desktop sidebar visibility, and opening/resuming one restored task. If transcript files exist but UI history is incomplete, diagnose `session_index.jsonl`, `history.jsonl`, `state_*.sqlite`, `.codex-global-state.json`, and Desktop app state read-only. Never merge or overwrite those stores automatically. Keep original backups until history is stable.
