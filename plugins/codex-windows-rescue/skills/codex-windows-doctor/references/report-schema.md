# Read-only audit report schema

Report sections in this order:

1. **Current outcome:** what works and what is failing.
2. **Confirmed active problems:** evidence plus affected layer.
3. **Potential conflicts:** why each item is not yet proven causal.
4. **Historical-only items:** backups and session text that are not active configuration.
5. **Expected current state:** normal Codex, AppX, cache, and session locations.
6. **Protected items:** projects, proxy variables, browser profile, credentials, and backups that must not be changed.
7. **Recommended order:** one smallest next diagnostic or repair step at a time.

For each finding include the layer, evidence source, confidence, whether a local repair exists, and the verification needed after repair.

For network findings, include the current Codex version and distinguish native proxy handling from an explicit environment-variable fallback. For session findings, distinguish transcript-file presence from CLI visibility, Desktop sidebar visibility, and resumability; do not infer one from another.

Include persistence indicators from Startup folders, registry Run entries, scheduled tasks, services, and PATH wrappers, but never include their command strings or arguments. Mark inaccessible locations as unknown rather than treating them as absent or aborting the audit.

Never include API-key values, tokens, cookies, raw `auth.json`, or complete command lines.
