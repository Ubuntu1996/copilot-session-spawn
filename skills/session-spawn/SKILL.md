---
name: session-spawn
description: Spawn a near-native side-topic Copilot CLI session from recorded public hook context. Use when the user wants a side topic in a new Copilot session.
---

This skill supports near-native session spawning using public Copilot CLI features.

Use the launcher script in this skill's plugin package. Prefer `-TopicFile` when the topic contains quotes, newlines, backticks, or other shell-sensitive characters:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\copilot-spawn.ps1 -Topic "<topic>"
```

Safer form:

```powershell
Set-Content -LiteralPath .\topic.txt -Value "<topic>" -Encoding UTF8
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\copilot-spawn.ps1 -TopicFile .\topic.txt
```

Important constraints:

1. Public Copilot CLI plugins cannot add a native built-in busy-time slash command to the stock CLI.
2. `/spawn` can exist as a command/skill-style prompt when the parent session is idle, but it still requires the current agent to process the prompt.
3. For spawning while the parent is busy streaming, the user must run `copilot-spawn.ps1` externally, for example from another terminal, a Windows Terminal action, or a hotkey.
4. The child imports a near-native context bundle as inherited memory. It does not copy private internal session rows.

When spawning, create an independent child session. Do not alter, cancel, or resume the parent session.
