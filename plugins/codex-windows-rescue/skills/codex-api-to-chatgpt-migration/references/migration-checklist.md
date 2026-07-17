# API-to-ChatGPT migration checklist

## Active routing indicators

- A process whose command line matches an exact known local router script such as `.api-switch\proxy.js`.
- A listener on the router's configured local port, commonly but not universally `15721`.
- A startup item, scheduled task, service, or wrapper that launches the router.
- User-level `model_provider`, `model_providers`, `openai_base_url`, `chatgpt_base_url`, or profile configuration selecting the retired route.
- A Codex launcher or shim that resolves before the intended client.

Also inspect, without returning command strings or arguments:

- registry `Run` entries;
- user and common Startup folders;
- scheduled tasks;
- Windows services;
- PATH entries and command wrappers.

An indicator is a lead, not proof that it belongs exclusively to Codex.

## Common locations to inspect

- `%USERPROFILE%\.api-switch`
- `%USERPROFILE%\.api-switch.yaml`
- `%USERPROFILE%\.cc-switch`
- `%LOCALAPPDATA%\com.ccswitch.desktop`
- `%APPDATA%\com.ccswitch.desktop`
- `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\proxy-start.vbs`
- `%USERPROFILE%\.codex\config.toml`
- `%USERPROFILE%\.codex\*.config.toml`
- trusted-project `.codex\config.toml` files
- npm, standalone, and WindowsApps Codex command sources

These are candidates, not automatic deletion targets.

## Shared or ambiguous settings

Treat `OPENAI_API_KEY`, `DEEPSEEK_API_KEY`, custom `env_key` variables, and base-URL variables as shared until the user confirms no other application uses them. Never display their values. Remove only Codex references when possible.

If another application uses a provider key directly, preserve the key. Quarantining an old Codex router can still be safe when that application points to the provider's official endpoint rather than the router's local port. Verify the endpoint without exposing the key.

Treat `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, and `NO_PROXY` as network settings, not provider residue. Preserve them unless a separate network diagnosis proves they are wrong and the user approves changing them.

## Historical-only indicators

- Provider names inside `sessions`, `archived_sessions`, logs, exported reports, or disabled backup directories.
- Old installer files in Downloads.
- Databases inside a clearly quarantined directory when no process, startup item, config, environment variable, or PATH entry loads them.

Historical text does not become active configuration merely because a search finds it.

After reinstall, a newly generated `.codex`, AppX state directory, runtime cache, and active Codex processes are normal current state. Do not repeatedly clean them as residue.

## Complete migration stages

1. **Baseline:** record current Codex clients, auth-status command, network variables, and protected data.
2. **Active route:** preview and, after approval, stop only an exactly matched retired local router process.
3. **Persistence:** separately disable or quarantine each startup item, task, service, or wrapper that would restart that route.
4. **Router data:** quarantine one exact cc-switch/API-Switch path at a time. Do not permanently delete it yet.
5. **Codex provider config:** show key names and file paths without values; edit only the retired Codex provider reference after separate approval.
6. **Shared environment:** preserve shared keys and proxy variables. Change one variable and one scope only after ownership is clear and separately approved.
7. **Client sources:** resolve duplicate CLI or wrapper precedence only if it causes ambiguity; do not uninstall clients merely because two supported surfaces coexist.
8. **Authentication:** sign out or change login method only after a separate explanation and confirmation, then sign in with ChatGPT.
9. **Verification:** check normal Codex response, intended proxy behavior, inactive retired route, and unaffected API-using applications.
10. **Soak and disposal:** keep quarantine until the user is satisfied. Permanent deletion and provider-side key rotation are optional, later decisions with new confirmations.

At every stage, use the shared step card: finding, purpose, exact target, action, impact, protected items, rollback, and expected verification.

## Safe end state

- User can identify ChatGPT as the active Codex sign-in method.
- Retired router process and startup mechanism are inactive.
- Codex configuration no longer selects the retired provider.
- Shared API keys remain available to other approved software if needed.
- v2rayN and required proxy variables remain intact.
- Sessions and projects remain intact.
