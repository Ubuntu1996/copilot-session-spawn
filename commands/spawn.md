---
description: "Spawn a side-topic Copilot CLI session from an explicit parent session. Usage: /spawn <parent-session-id-or-name> :: <topic>"
argument-hint: "<parent-session-id-or-name> :: <topic>"
---

Use this command when the user asks to spawn a side-topic Copilot CLI session while the current session is idle.

Run the plugin launcher script from this command's plugin directory. Do not interpolate `$ARGUMENTS` into a shell command string.

Require the user to provide the parent session ID or exact parent session name. Do not assume the latest active session.

If the topic contains only simple text, pass it as the `-Topic` argument using safe PowerShell quoting and pass the parent through `-ParentSessionId` or `-ParentSessionName`. If quoting is ambiguous, write the topic to a temporary UTF-8 file and invoke the launcher with `-TopicFile <path>`.

Do not claim this is a native busy-time slash command; for busy-state spawning, the user must invoke `copilot-spawn.ps1` from another terminal or hotkey.
