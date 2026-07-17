# Explain-confirm-act-verify protocol

Use this protocol for every action that changes files, processes, applications, registry, environment variables, authentication, plugins, or installed software.

## 1. Explain

Before acting, show a step card containing:

- **Finding:** what was observed and the evidence.
- **Purpose:** why this action is relevant.
- **Exact target:** process ID, port, variable scope, application, or complete filesystem path.
- **Action:** what will be stopped, moved, copied, edited, installed, uninstalled, or left untouched.
- **Impact:** what may temporarily stop working.
- **Protected items:** what will not be changed.
- **Rollback:** how to undo the step.
- **Expected verification:** the exact success condition.

Use plain language first. Put commands and technical details underneath.

## 2. Confirm

- Obtain explicit confirmation for the displayed step only.
- Do not treat approval for one step as approval for later steps.
- Require separate confirmation for permanent deletion, environment-variable changes, logout, software uninstall, registry changes, and state-directory reset.
- If the observed target changes before execution, discard the approval and explain the new state.
- Read-only inspection may proceed after announcing its scope, but do not silently expand that scope.

## 3. Act

- Execute only the approved operation.
- Prefer an official command or bundled deterministic script.
- Prefer move-to-quarantine over deletion.
- Use exact process and path matching. Never stop processes by a broad name match alone.
- Stop on permission errors, ownership ambiguity, unexpected paths, or validation mismatch.
- Do not replace a failed safe action with a more forceful action without a new explanation and confirmation.

## 4. Verify

- Run the stated verification immediately.
- Report the observed result, not merely "completed" or "fixed."
- If verification fails, stop and re-diagnose. Do not continue the planned sequence as if the step succeeded.
- Preserve logs that contain paths and status only; redact secrets.

## Default safety policy

- Read-only and preview modes are the default.
- One-click or batch mode is disabled unless the user explicitly requests it after reviewing the full action list.
- Even in batch mode, permanent deletion, authentication changes, and environment-variable changes remain separate confirmations.
- Backups must use the real Windows known-folder path instead of a hard-coded `Desktop` path.
- PowerShell parser success is not runtime validation. Run non-mutating or fixture-based tests before trusting a script.
- Never log values of variables whose names contain `KEY`, `TOKEN`, `SECRET`, `PASSWORD`, or `AUTH`.
