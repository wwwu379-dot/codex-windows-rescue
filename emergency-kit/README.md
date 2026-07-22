# Codex Windows emergency kit

Use this fallback when Codex Desktop keeps reconnecting or cannot answer, and the CLI cannot install or run the rescue plugin.

## Non-technical steps

1. On GitHub, choose **Code -> Download ZIP**.
2. Extract the complete ZIP. Do not copy only this folder; the audit reuses read-only diagnostics from the plugin.
3. Open `emergency-kit` and double-click `Run-CodexEmergencyAudit.cmd`.
4. Open the `Codex-Emergency-Reports` folder created on the real Windows Desktop.
5. Send the newest Markdown report to web ChatGPT. Keep the JSON snapshot private unless trusted support specifically requests it.

The audit does not require a working Codex Desktop or model connection. It does not stop processes, delete files, change the registry, alter environment variables, uninstall applications, or repair anything. It creates only its two report files.

## Why it diagnoses instead of repairing

An automatic script cannot safely guess whether a proxy variable, old switch, second CLI, or `.codex` directory is active and necessary. The emergency kit gathers evidence first. A working agent can then explain each proposed action and request approval before making changes.

The launcher's execution-policy bypass applies only to that PowerShell process. The script is plain text and can be inspected before use.
