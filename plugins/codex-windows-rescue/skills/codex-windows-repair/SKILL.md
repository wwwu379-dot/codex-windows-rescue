---
name: codex-windows-repair
description: Apply approved, evidence-based Windows Codex repairs one reversible step at a time after a read-only audit. Use for proxy port drift or inheritance, client-source conflicts, plugin cache or process locks, targeted state backup, safe quarantine, version mismatch, or clean-reset planning. Do not use for blind cleanup, secret deletion, unsupported Chrome Native Host synthesis, or repairs without explicit per-step confirmation.
---

# Codex Windows Repair

Repair only a confirmed user-side cause. Read the shared [safety protocol](../codex-windows-rescue/references/safety-protocol.md) before acting.

## Preconditions

- Require a current read-only finding from `$codex-windows-doctor` or a narrower diagnostic skill.
- State the intended verification before requesting approval.
- Back up the smallest relevant state, not the whole machine.
- Do not proceed when the target path, process, version, or ownership differs from the preview.

## Select the smallest repair

Read [references/repair-playbook.md](references/repair-playbook.md).

- Use `scripts/Get-CodexProxySnapshot.ps1` to inspect proxy inheritance and listeners without network changes.
- Use `scripts/Get-CodexProcessLocks.ps1` to identify exact Codex-related processes before asking to stop anything.
- Use `scripts/Backup-CodexState.ps1` to preview and copy only selected state categories. Authentication is excluded by design.

Prefer official update, login, plugin, and marketplace commands over manual cache or config manipulation.

## Clean-reset boundary

Treat a clean reset as a last-resort diagnostic. Before proposing it, preserve projects, export or copy only sessions, record proxy settings without exposing credentials, quarantine rather than delete, and explain that reinstalling cannot guarantee a product bug will disappear.

Do not execute a multi-stage self-uninstall from the running Codex process. Generate and validate a script, show every target, and let the user run it only after closing Codex.
