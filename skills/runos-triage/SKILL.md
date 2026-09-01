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
   Never quote a credential, a token, a key or a password into your answer, even
   when you read one as part of the evidence. Refer to it by its key name and say
   where it came from.

## Traps

**Respect the poll interval in the `jobs` topic.** That topic owns the number, and
at the time of writing it asks for at least 5 seconds between your own `jobs_show`
calls. Read it rather than trusting this sentence. Prefer `jobs_follow`, which
blocks for the duration of the job. The CLI's own one-second follow loop is a
different, delta-diffed poller. It is correct. Do not copy it and do not "fix" it.

**Read `debugging` before you pick a tool.** Reaching straight for logs is the
common mistake. Several symptoms are answered by status alone, and logs for the
wrong container cost a minute and prove nothing.

**Some errors mean retry, not failure.** `debugging` names which ones. Do not
report a cluster-reachability error to the user as a broken application.

**Triage is read-only.** Do not restart, redeploy or delete anything to see whether
it helps. That destroys the evidence and it is a write. If a write is genuinely the
next step, name the exact resource and the exact cluster, explain what it costs,
and wait for the user to agree to THAT before you do it.

**A credential read is not a free diagnostic.** Some tools return real secrets.
Before you call one, tell the user what you are about to read and why, then read
the minimum. Never write a credential into a file, a commit or a log line.

**Do not conclude from source.** A file you read is not a running system. Name the
tool output you based each conclusion on. If you have none, say the cause is
unknown.
