---
name: runos-deploy-app
description: Deploy or redeploy an application on RunOS. Use when the user asks to deploy an app, ship a build, push code to a RunOS cluster, fix a failed rollout, or edit an app config file. Routes to the RunOS MCP documentation topics; it does not restate them.
---

# Deploy an app on RunOS

This skill is a router. It tells you which RunOS topics to read and in what order.
It states no RunOS fact of its own. The topics are the source of truth.

## Before anything: the two preconditions

**1. Sign-in.** This skill loads whether or not the user is signed in. Every RunOS
MCP tool call is resolved against a credential. Recognise a credential failure by
what the platform really returns. These strings were measured against the live
CLI, not guessed:

- `authentication required: run 'runos login' first`. The interactive sign-in
  is expired, revoked or absent. This is the common one.
- a JSON error carrying `"statusCode": 401` and `"error": "Invalid token"`. The
  API key or the token is invalid or revoked.
- **no RunOS tool answers at all, because none exists.** With no credential the
  RunOS MCP servers exit before they speak MCP, so there is nothing to refuse.
  This is the state a brand new user is in.

A RunOS refusal carries its own `recovery` array. Follow that array, and read
`auth-credentials` for the full sequence. Do not improvise a recovery.

When no RunOS tool answers at all you cannot read that topic, because the server
never started. Only in that case, tell the user to run `runos login` in their
terminal and reload the window. Do not retry the tool. Do not look for a
credential yourself. The plugin ships none.

For a headless or background agent there is no browser, so the route is an
account API key in the `RUNOS_API_KEY` environment variable instead. Tell the
user that, and stop. `RUNOS_API_KEY` and `RUNOS_ACCOUNT_ID` must each be unset,
or set to a real value. Either one SET but EMPTY makes the CLI refuse outright,
and then no server starts.

**2. The two-document gate.** A RunOS MCP server refuses its tools until you
have read two documents in this session:

- `mcp_bootstrap` counts as one document.
- each `mcp_topics_show` counts as one document.
- `mcp_topics_search` finds keys. **A search does not count.**

**The gate is per server.** Call `mcp_bootstrap` once on every RunOS server you
use, not once per session. A server you have not bootstrapped refuses your first
call to it. That is usually the write the user has just approved.

Open every session with `mcp_bootstrap`, then `cli_version-check`, then at least
one `mcp_topics_show`. Read `cli-mcp-contract` for the rest of the call rules,
and for what the gate does when bootstrap itself fails.

## When a tool refuses, read the envelope first

A refusal comes either from RunOS or from the editor that hosts you. The two look
alike and need opposite answers. Decide which one you have before you speak.

The three strings above are RunOS. The following are the host, and they are not
RunOS refusals:

- `User rejected MCP: ... User chose to skip`. The host blocked the call. This is
  NOT evidence that the user saw a prompt, and NOT evidence that they declined.
  Tell them the host blocked the call and that they were not asked. Never say the
  user skipped, declined or rejected anything.
- `failed during live tool discovery`, or the RunOS tools vanishing mid session.
  The server died in this session. Say that, ask the user to reload the window,
  and stop.

Two rules cover both:

- **Never report a host failure as a sign-in problem.** Telling a signed-in user
  to run `runos login` after a blocked call wastes their time and is wrong.
- **Never state a RunOS fact you could not read.** When the documentation is
  unreachable, say so and stop. Do not answer from memory.

## Read these topics, in this order

1. `mcp_topics_show` with key `apps-overview`. The model, and which deploy path applies.
2. `mcp_topics_show` with key `apps-deploy`. The verbs, and what each one does.
3. `mcp_topics_show` with key `apps-config`. Every field of the app config file.

Read further only when the task needs it:

- `apps-env` for environment variables and secrets.
- `apps-build-args` for build-time values baked into a bundle.
- `apps-requires` when the app needs a managed service.
- `dockerfiles` when you write or fix a Dockerfile.
- `resource-classes` when you choose a size.
- `jobs` when a call returns a job id.

## Tool order

1. `mcp_bootstrap`, then `cli_version-check`, then the topic reads above.
2. `clusters_list` to resolve the target cluster, then `apps_list` or `apps_show`
   to find the app. Pass `cid` explicitly from here on. Never rely on a default.
3. `apps_pull` to write the live config to an ABSOLUTE path. `apps_diff` requires
   a `yaml_file`, so you need a pulled file before step 4. Ask the user where the
   file should land before you write it.
4. `apps_diff` with that `yaml_file` to preview the change. It is read-only.
5. Ask the user to confirm the exact app and the exact cluster, by name.
6. The write tool, only after the user agrees. See the write boundary below.
7. `jobs_show` or `jobs_follow` to watch the result.

`deploy` and `apps_sync` are not interchangeable. `deploy` builds when it needs to
and then rolls out. `apps_sync` is the declarative reconcile and never builds or
provisions. Read `apps-deploy` and `apps-requires` before you pick, and pick for a
reason you can state.

## Traps

**The write tools are not on the server this plugin declares.** The plugin ships
one read-only server. `deploy` is on `runos-sensitive-write`, and `apps_sync` is
on `runos-write`. Neither is declared, so on a default install the tool you need
for step 6 does not exist. That is a missing server, NOT a missing sign-in. Say
so, and tell the user to add the server to their own MCP configuration. Do not
tell a signed-in user to run `runos login`.

**Run `apps_diff` before you deploy a CLI-deployed app.** A CLI deploy sends the
local directory. Anything stale or uncommitted in that directory ships, so preview
it first. Read `apps-deploy` for what `apps_diff` does and does not detect, and do
not report "nothing will change" on its output alone.

**Always confirm with the user before deploying.** Name the app and the cluster in
the question, and wait for a yes. A destructive tool needs `confirm: true`, and you
may only pass it after the user agreed to that exact target. Never pass it to get
past a refusal.

**Pass every path as an ABSOLUTE path.** The RunOS MCP server runs with its
working directory set to the installed plugin folder, not to the user's project.
`mcp.json` sets `cwd` to the plugin root, which is the only value the Agent
Plugins specification allows there. So a relative `yaml_file` or `out` resolves
inside the plugin folder, and a pull writes the user's live config into the
plugin directory instead of their project.

**Never invent a config field.** Read `apps-config` and use what it lists. An
invented field is either rejected or silently ignored, and both waste a deploy.

**Do not hand-build a URL.** Read it back from the app after the deploy.

**A job id is not a result.** When a call returns a job id, the work has only been
queued. Follow it before you report success.

**When the deploy fails, switch to the `runos-triage` skill.** This skill covers
getting a deploy out. Diagnosing a failure is the other skill's job, and it opens
by reading `debugging`.
