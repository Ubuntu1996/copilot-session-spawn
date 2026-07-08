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
- Builds the context bundle on demand when spawning, then starts a child session with `copilot --yolo --session-id ... -i ...`.
- Provides an idle slash-style command file (`/spawn`) and a skill (`/session-spawn`).
- Supports busy-state spawning through an external launcher or hotkey.
- Provides `/merge` and `copilot-merge.ps1` to import a completed child session back into the parent context.

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
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\copilot-spawn.ps1 -ParentSessionId "<parent-session-id>" -Topic "Investigate the side topic"
```

You can also provide the exact parent session name:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\copilot-spawn.ps1 -ParentSessionName "<parent-session-name>" -Topic "Investigate the side topic"
```

Use `-PrintOnly` to print the child launch script and command without starting a new terminal.

Child sessions are started with `--yolo` by default, so tool, path, and URL permissions are auto-approved in the child. Use this only for trusted working directories, trusted side-topic prompts, and trusted inherited parent context. To opt out for a specific spawn, pass `-NoYolo`.

## Idle `/spawn`

When installed as a Copilot CLI plugin, `/spawn <parent-session-id-or-name> :: <topic>` can guide Copilot to run the launcher for idle use. It still goes through the current session's agent turn and therefore is not the busy-state path.

## Merge a child session back into the parent

When the parent session is idle, use:

```text
/merge [child-session-id|sub-topic-name|latest]
```

From a terminal, use:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\copilot-merge.ps1 -ParentSessionId "<parent-session-id>" -ChildName "Investigate the side topic"
```

If you run `/merge` inside the parent session, the active parent is refreshed automatically by hooks. If you run `copilot-merge.ps1` directly from a terminal, prefer passing `-ParentSessionId` because `active-session.json` may point at the child you used most recently.

If you omit the child argument, merge chooses the latest unmerged child spawned from the active parent. The merge command creates `merge-context.md` under the parent session's `merges\<child-session-id>\` directory; the parent session should read that file as completed side-topic context.
