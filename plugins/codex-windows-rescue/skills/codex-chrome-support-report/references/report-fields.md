# Support report fields

The report may contain:

- Windows product, version, and build;
- Codex desktop version, when discoverable;
- Chrome product version, when discoverable;
- extension installation profile names and versions;
- plugin version and required-file presence;
- Native Host registry-key presence, never registry values beyond the redacted manifest path;
- manifest existence, JSON validity, host-file existence, and expected-origin status;
- whether the user confirmed the official remove/reinstall flow;
- whether ordinary Codex and Computer Use work;
- the first failing layer and the supported next action.

The report must exclude:

- `auth.json` contents;
- API-key, token, cookie, password, or account values;
- browsing history and page contents;
- complete process command lines;
- unrelated logs and screenshots;
- raw manifest contents or arbitrary registry values.
