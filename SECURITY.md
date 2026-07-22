# Security policy

## Safe handling

Do not commit or attach any of the following:

- API keys, access tokens, refresh tokens, cookies, or `auth.json`.
- Full process command lines when they may contain credentials.
- Codex session databases or private conversation exports.
- Chrome profiles, browsing history, bookmarks, or extension storage.
- Cleanup logs, backup directories, or screenshots containing secrets.

The plugin and standalone emergency kit are designed to redact reports and keep diagnostics local. They do not submit reports or upload data automatically. Emergency JSON snapshots should remain private unless trusted support specifically requests one.

## Reporting a security issue

If you find a vulnerability in this plugin, do not publish credentials or a working exploit in a public issue. Open a private security report through the repository's GitHub security reporting flow when available, or contact the repository maintainer privately before public disclosure.

When reporting, include the smallest reproducible description and remove all secret values and personal paths that are not necessary to understand the problem.
