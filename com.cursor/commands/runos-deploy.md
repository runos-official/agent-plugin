---
description: Deploy an app to RunOS, with the preview and the confirmation step that a deploy needs.
---

Deploy an app to RunOS. Follow the `runos-deploy-app` skill. Do not skip a step.

1. `mcp_bootstrap`, then `mcp_topics_show` for `apps-overview`, `apps-deploy` and
   `apps-config`. If any of those refuses with `authentication required: run
   'runos login' first`, or with a JSON error carrying `"statusCode": 401`, stop
   and tell me to run `runos login` in my terminal and reload the window. If no
   RunOS tool exists at all, that is the same problem: with no credential the
   servers never start.
2. Work out which app and which cluster I mean. If either is ambiguous, ask me.
   Do not pick the only one you can see and assume it is right.
3. Run `apps_diff`. It is read-only. Show me what will change, in plain words.
4. Ask me to confirm, naming the app id and the cluster id in the question. Wait.
5. Only after I say yes, call `deploy`.
6. Follow the job to a terminal state before you tell me it worked.

`deploy` lives on the `runos-sensitive-write` server, which this plugin does not
declare. If you cannot see it, tell me: I add it to my own MCP configuration, and
the README says how. Do not substitute another tool.

Pass every path argument as an ABSOLUTE path. The server's working directory is
the installed plugin folder, not my project.

If the deploy fails, switch to the `runos-triage` skill rather than retrying it.

Do not pass `confirm: true` on any call until I have agreed to that exact app and
that exact cluster.
