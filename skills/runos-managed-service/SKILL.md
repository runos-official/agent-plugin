---
name: runos-managed-service
description: Add, size, wire or change a RunOS managed service such as a database, cache, object store, registry or model server. Use when the user asks for a database, a queue, a cache, storage, or wants an app to depend on a service. Routes to the RunOS MCP documentation topics; it does not restate them.
---

# Add or change a managed service on RunOS

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

1. `mcp_topics_show` with key `services-overview`. The mental model, before any service task.
2. `mcp_topics_show` with key `service-limitations`. What actually exists. Read this
   before you name a type, not after.
3. `mcp_topics_show` with the key for the service type itself, once step 2 told you
   the type is real. The `mcp_bootstrap` topic index lists the per-type keys. Take
   the key from that index, never from memory.
4. `mcp_topics_show` with key `apps-requires` when an app is to depend on the service.

Read further only when the task needs it:

- `resource-classes` when you choose a size or a high-availability tier.
- `storage-options` when durability matters.
- `services-dependencies` before you delete anything.
- `config-sets` for versioned advanced configuration.
- `services-iac` when the service is declared in a file.
- `jobs` when a call returns a job id.

## Tool order

1. `mcp_bootstrap`, then `cli_version-check`, then the topic reads above.
2. `clusters_list` to resolve the target cluster, then `services_list` to see what
   the account already runs. Pass `cid` explicitly from here on.
3. `service-info_rrc` and `service-info_versions` to pick a size and a version from
   real values rather than guessed ones.
4. Ask the user to confirm the type, the size and the cluster.
5. The `services_<type>_add` or `services_<type>_update` tool, only after the user
   agrees. See the write boundary below.
6. `jobs_show` or `jobs_follow` to watch the result.

## Traps

**Never invent a service type.** The type list is manifest-driven and it moves. A
type you remember from another platform, or from an older RunOS, is not evidence.
Read `service-limitations`, and if the type is not there, say so to the user rather
than substituting the nearest thing. An unknown type is rejected, and a wrong type
that happens to exist is worse, because it provisions.

**Never invent a size or a version either.** Ask the tools, not your memory.

**Read the environment key names from `apps-requires`, never from a template.**
The platform decides the exact key names an app receives. A key the platform does
not know is dropped without an error. This is about key NAMES. Do not read a
credential value unless the task genuinely needs it, and never repeat one back.

**The write tools are not on the server this plugin declares.** The plugin ships one
read-only server. Every `services_<type>_add`, `_update` and `_delete` tool is on
`runos-write`, which is not declared, so on a default install step 5 has no tool.
That is a missing server, NOT a missing sign-in. Say so, and tell the user to add
the server to their own MCP configuration.

**Deleting a service destroys its data.** This skill's domain holds the most
destructive tools in RunOS: service deletes, database drops, bucket deletes and
storage wipes. Read `services-dependencies` first and check what depends on the
service. Then name the exact service, the exact cluster and what is lost, and wait
for the user to say yes to THAT. A destructive tool needs `confirm: true`, and you
may only pass it after the user agreed to that exact target. Never pass it to get
past a refusal. A refusal is the platform protecting the user's data, not an
obstacle to route around.

**A job id is not a result.** When a call returns a job id, the work has only been
queued. Follow it before you report success.
