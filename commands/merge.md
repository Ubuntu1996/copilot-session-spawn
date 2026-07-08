---
description: "Merge a completed side-topic child session back into the parent session context. Usage: /merge [child-session-id|sub-topic-name|latest]"
argument-hint: "[child-session-id|sub-topic-name|latest]"
---

Use this command when the user wants to import a completed side-topic child session into the current parent session.

Run the plugin merge script from this command's plugin directory. Do not interpolate `$ARGUMENTS` into a shell command string.

Resolution rules:

1. If the argument is empty or `latest`, merge the latest unmerged child spawned from this parent.
2. If the argument looks like a UUID or UUID prefix, pass it as `-ChildSessionId` when full UUID, or as `-ChildName` for prefix resolution.
3. Otherwise treat the argument as a child sub-topic/name query and pass it as `-ChildName`.
4. If quoting is ambiguous, write the query to a temporary UTF-8 file and invoke the launcher with `-ChildQueryFile <path>`.

After the script returns JSON, read the returned `mergeContextPath` as context. Treat it as completed child-session context that should become part of this parent session's working memory. Do not replay the child transcript; acknowledge the merge briefly and continue the parent topic normally.
