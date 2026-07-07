# Copilot Session Spawn

Near-native side-topic session spawning for GitHub Copilot CLI using public extension points only.

This package does not modify Copilot CLI internals and does not clone private session storage. It records public hook payloads into a local fork bundle, then starts a new Copilot CLI session with inherited context through public CLI flags.

## Capabilities

- Records parent session metadata and latest prompts with lightweight public hooks.
- Builds a near-native fork bundle:
  - `fork-manifest.json`
  - `transcript.jsonl`
  - `context-full.md`
  - `context-compact.md`
  - `latest-prompt.txt`
- Builds the context bundle on demand when spawning, then starts a child session with `copilot --session-id ... -i ...`.
- Provides an idle slash-style command file (`/spawn`) and a skill (`/session-spawn`).
- Supports busy-state spawning through an external launcher or hotkey.

## Important limitation

The stock Copilot CLI public plugin model can load command files, but those commands are handled as prompt/model flows. They are useful when the parent is idle, but they are not equivalent to a native built-in busy-time command. For spawning while Copilot is streaming, use `scripts\copilot-spawn.ps1` from another terminal or a configured hotkey.

## Install hooks

From this directory:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

Restart Copilot CLI after installing hooks.

## Uninstall hooks

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1
```

This removes the hook configuration only. To delete recorded local spawn data, pass both `-DeleteData` and `-ForceDeleteData`; the script refuses to delete data unless the plugin marker file is present.

## Spawn a side-topic session

From any terminal:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\copilot-spawn.ps1 -Topic "Investigate the side topic"
```

Use `-PrintOnly` to print the child launch script and command without starting a new terminal.

## Idle `/spawn`

When installed as a Copilot CLI plugin, `/spawn <topic>` can guide Copilot to run the launcher for idle use. It still goes through the current session's agent turn and therefore is not the busy-state path.
