---
name: runos-deploy-app
description: Deploy or redeploy an application on RunOS. Use when the user asks to deploy an app, ship a build, push code to a RunOS cluster, fix a failed rollout, or edit an app config file. Routes to the RunOS MCP documentation topics; it does not restate them.
---

# Deploy an app on RunOS

This skill is a router. It tells you which RunOS topics to read and in what order.
It states no RunOS fact of its own. The topics are the source of truth.

## Before anything: the two preconditions

**1. Sign-in.** This skill loads whether or not the user is signed in. Every RunOS
MCP tool call needs a token. If a RunOS tool answers `not authenticated`, stop and
tell the user to run `runos login` in their terminal, then wait. Do not retry the
tool. Do not look for a credential yourself. The plugin ships none.

For a headless or background agent there is no browser, so the route is the
`RUNOS_API_KEY` environment variable instead. Tell the user that, and stop.

**2. The two-document gate.** The RunOS read server refuses its tools until you
have read two documents in this session:

- `mcp_bootstrap` counts as one document.
- each `mcp_topics_show` counts as one document.
- `mcp_topics_search` finds keys. **A search does not count.**

So open every session with `mcp_bootstrap`, then at least one `mcp_topics_show`.
Read `cli-mcp-contract` for the rest of the call rules.

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

1. `mcp_bootstrap`, then the topic reads above.
2. `apps_list` or `apps_show` to find the app and confirm its cluster.
3. `apps_diff` to preview the change. It is read-only.
4. Ask the user to confirm the exact app and the exact cluster.
5. `deploy` (or `apps_sync`) only after the user agrees.
6. `jobs_show` or `jobs_follow` to watch the result.

## Traps

**Run `apps_diff` before you deploy a CLI-deployed app.** A CLI deploy sends the
local directory. Anything stale or uncommitted in that directory ships. `apps_diff`
is the only cheap way to see what is about to change, and it costs nothing.

**Always confirm with the user before deploying.** Name the app and the cluster in
the question, and wait for a yes. A destructive tool needs `confirm: true`, and you
may only pass it after the user agreed to that exact target. Never pass it to get
past a refusal.

**Never invent a config field.** Read `apps-config` and use what it lists. An
invented field is either rejected or silently ignored, and both waste a deploy.

**Do not hand-build a URL.** Read it back from the app after the deploy.

**A job id is not a result.** When a call returns a job id, the work has only been
queued. Follow it before you report success.
