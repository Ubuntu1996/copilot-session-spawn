---
description: Spawn a side-topic Copilot CLI session using the latest recorded parent context. Usage: /spawn <topic>
argument-hint: <topic>
---

Use this command when the user asks to spawn a side-topic Copilot CLI session while the current session is idle.

Run the plugin launcher script from this command's plugin directory. Do not interpolate `$ARGUMENTS` into a shell command string.

If the topic contains only simple text, pass it as the `-Topic` argument using safe PowerShell quoting. If quoting is ambiguous, write the topic to a temporary UTF-8 file and invoke the launcher with `-TopicFile <path>`.

Do not claim this is a native busy-time slash command; for busy-state spawning, the user must invoke `copilot-spawn.ps1` from another terminal or hotkey.
