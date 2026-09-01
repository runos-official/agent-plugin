---
description: Diagnose a failing app, service or job on RunOS, using reads only.
---

Diagnose the failure I describe. Follow the `runos-triage` skill. This is read-only
work: change nothing.

1. `mcp_bootstrap`, then `mcp_topics_show` for `debugging`. Read `debugging` before
   you pick any tool. It is the triage router and it will save you a wrong guess.
   If several unrelated tools refuse at once, suspect the credential before the
   platform: `authentication required: run 'runos login' first`, or a JSON error
   carrying `"statusCode": 401`, means the sign-in, not the app. Tell me to run
   `runos login` and reload the window. Do not retry.
2. Status first. `apps_status`, the matching service status tool, or `jobs_show`.
3. Then the narrow tool `debugging` pointed you at, and only that one.
4. Leave at least 5 seconds between your own `jobs_show` calls. Prefer `jobs_follow`.

Report:

- the symptom, in one sentence
- the evidence, naming the tool each piece came from
- the most likely cause, and how confident you are
- the fix you propose, as a proposal

Do not restart, redeploy or delete anything to see whether it helps. That destroys
the evidence and it is a write. Propose it and wait for me.

If you have no tool output to base a conclusion on, say the cause is unknown. Do not
infer it from source files in this workspace.
