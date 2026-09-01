---
name: runos-triage
description: Diagnose a failure on RunOS. Use when something crashed, will not start, returns an error, times out, restarts in a loop, or a deploy or job failed. Routes to the RunOS MCP documentation topics; it does not restate them.
---

# Triage a failure on RunOS

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

In every one of those: stop, tell the user to run `runos login` in their terminal
and reload the window, then wait. Do not retry the tool. Do not look for a
credential yourself. The plugin ships none.

For a headless or background agent there is no browser, so the route is an
account API key in the `RUNOS_API_KEY` environment variable instead. Tell the
user that, and stop. If that variable is SET but EMPTY the CLI refuses it
outright and no server starts, so it must be unset or set to a real value.

A credential failure is itself a common cause of the symptom you are triaging. If
several unrelated tools refuse at once, suspect the credential before the platform.

**2. The two-document gate.** The RunOS read server refuses its tools until you
have read two documents in this session:

- `mcp_bootstrap` counts as one document.
- each `mcp_topics_show` counts as one document.
- `mcp_topics_search` finds keys. **A search does not count.**

So open every session with `mcp_bootstrap`, then at least one `mcp_topics_show`.
Read `cli-mcp-contract` for the rest of the call rules.

## Read these topics, in this order

1. `mcp_topics_show` with key `debugging`. Read this **first**, every time. It is the
   triage router and it tells you which observability tool the symptom calls for.
   Reading it first is cheaper than guessing wrong twice.
2. `mcp_topics_show` with key `logs` when the symptom is a crash, an exception or a
   missing value at runtime.
3. `mcp_topics_show` with key `metrics` when the symptom is pressure, slowness or volume.
4. `mcp_topics_show` with key `jobs` when a job id is in play or an operation never finished.

Read further only when `debugging` sends you there:

- `apps-deploy` and `apps-env` for a deploy or a configuration failure.
- `cli-mcp-contract` when it is the tool call itself that is being refused.
- `auth-credentials` when the refusal is about the credential.

## Tool order

1. `mcp_bootstrap`, then `debugging`.
2. Status first: `apps_status`, `services_<type>_status`, or `jobs_show`.
3. Then the narrow tool `debugging` pointed you at, such as `apps_logs`,
   `apps_builds`, `services_vector_search-logs`, or a resource-metrics tool.
4. Report the evidence you actually read, and name the tool you read it from.

## Traps

**Leave at least 5 seconds between your own `jobs_show` calls.** Polling faster
gains you nothing and adds load. Prefer `jobs_follow`, which is built for waiting.
The CLI's own one-second follow loop is a different, delta-diffed poller. It is
correct. Do not copy it and do not "fix" it.

**Read `debugging` before you pick a tool.** Reaching straight for logs is the
common mistake. Several symptoms are answered by status alone, and logs for the
wrong container cost a minute and prove nothing.

**Some errors mean retry, not failure.** `debugging` names which ones. Do not
report a cluster-reachability error to the user as a broken application.

**Triage is read-only.** Do not restart, redeploy or delete anything to see whether
it helps. That destroys the evidence and it is a write. Ask the user first.

**Do not conclude from source.** A file you read is not a running system. Name the
tool output you based each conclusion on. If you have none, say the cause is
unknown.
