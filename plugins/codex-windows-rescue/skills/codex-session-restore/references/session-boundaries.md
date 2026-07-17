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

## Collision policy

- Same relative path and same hash: skip as already present.
- Same relative path and different hash: report a conflict and copy neither file over the other.
- Missing destination path: copy only after explicit approval.

## Source trust

Use only backup roots explicitly identified by the user or created by an earlier rescue step. Do not recursively search every drive for `.codex` because that may cross unrelated users, projects, or mounted backups.
