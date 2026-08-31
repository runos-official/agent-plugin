---
name: runos-managed-service
description: Add, size, wire or change a RunOS managed service such as a database, cache, object store, registry or model server. Use when the user asks for a database, a queue, a cache, storage, or wants an app to depend on a service. Routes to the RunOS MCP documentation topics; it does not restate them.
---

# Add or change a managed service on RunOS

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

1. `mcp_topics_show` with key `services-overview`. The mental model, before any service task.
2. `mcp_topics_show` with key `service-limitations`. What actually exists. Read this
   before you name a type, not after.
3. `mcp_topics_show` with the key for the service type itself, once step 2 told you
   the type is real.
4. `mcp_topics_show` with key `apps-requires` when an app is to depend on the service.

Read further only when the task needs it:

- `resource-classes` when you choose a size or a high-availability tier.
- `storage-options` when durability matters.
- `services-dependencies` before you delete anything.
- `config-sets` for versioned advanced configuration.
- `services-iac` when the service is declared in a file.
- `jobs` when a call returns a job id.

## Tool order

1. `mcp_bootstrap`, then the topic reads above.
2. `services_list` to see what the account already runs.
3. `service-info_rrc` and `service-info_versions` to pick a size and a version from
   real values rather than guessed ones.
4. Ask the user to confirm the type, the size and the cluster.
5. The `services_<type>_add` or `services_<type>_update` tool, only after the user agrees.
6. `jobs_show` or `jobs_follow` to watch the result.

## Traps

**Never invent a service type.** The type list is manifest-driven and it moves. A
type you remember from another platform, or from an older RunOS, is not evidence.
Read `service-limitations`, and if the type is not there, say so to the user rather
than substituting the nearest thing. An unknown type is rejected, and a wrong type
that happens to exist is worse, because it provisions.

**Never invent a size or a version either.** Ask the tools, not your memory.

**Read the credentials from the tool, never from a template.** The exact
environment key names an app receives are given by `apps-requires`. A key the
platform does not know is dropped without an error.

**Check dependents before deleting.** Read `services-dependencies` first.

**A job id is not a result.** When a call returns a job id, the work has only been
queued. Follow it before you report success.
