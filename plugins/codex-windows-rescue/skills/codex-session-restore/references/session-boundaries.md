# Session restoration boundaries

## Allowed categories

- `sessions`
- `archived_sessions`

Preserve their relative directory structure.

## Never copy as part of session restore

- `auth.json` or credential-store data;
- `config.toml` or profile files;
- plugins, marketplaces, cache, or `.tmp`;
- SQLite databases, UI state, logs, or sandbox binaries;
- provider configuration or API keys;
- the whole `.codex` directory.

## Read-only metadata inventory

The preview may report presence, file size, and directory counts for the following nearby state without reading or copying contents:

- `session_index.jsonl`;
- `history.jsonl`;
- `state_*.sqlite` and their journal/WAL sidecars;
- `.codex-global-state.json`;
- `session_backups`;
- `generated_images`.

These stores can affect task discovery, sidebar visibility, or resumability. Their presence does not make them safe to merge into a fresh installation. A transcript salvage operation must leave them untouched.

## What success means

- File recovery success: approved transcript files were copied and hash-verified.
- CLI visibility success: the restored task can be found from the CLI.
- Desktop visibility success: the restored task appears and opens in the Desktop app.

Do not claim complete restoration until the relevant surfaces have been checked. Copying `sessions` and `archived_sessions` alone guarantees only transcript-file salvage.

## Collision policy

- Same relative path and same hash: skip as already present.
- Same relative path and different hash: report a conflict and copy neither file over the other.
- Missing destination path: copy only after explicit approval.

## Source trust

Use only backup roots explicitly identified by the user or created by an earlier rescue step. Do not recursively search every drive for `.codex` because that may cross unrelated users, projects, or mounted backups.
