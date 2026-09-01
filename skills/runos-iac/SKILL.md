---
name: runos-iac
description: Manage RunOS infrastructure declaratively from YAML files, reconcile drift, or wire RunOS into a CI/CD pipeline. Use when the user mentions RunOS infrastructure as code, RunOS desired state, drift on a RunOS cluster, or pulling, diffing and syncing a RunOS config file, including from a CI pipeline or runner. Routes to the RunOS MCP documentation topics; it does not restate them.
---

# RunOS as declarative infrastructure

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

1. `mcp_topics_show` with key `iac-desired-state`. The model, and the word
   "manifest", which names more than one thing here. Read this first or you will
   argue with the user about the wrong file.
2. `mcp_topics_show` with key `services-iac` for service files.
3. `mcp_topics_show` with key `cicd` when a pipeline or a runner is involved.

Read further only when the task needs it:

- `apps-config` for every field of the app file.
- `resource-ids` for what an identifier means across a create and an update.
- `vcs-deployment` when the build runs on the provider rather than in-cluster.
- `api-keys` when the pipeline needs its own credential.

## Tool order

1. `mcp_bootstrap`, then `cli_version-check`, then the topic reads above.
2. `clusters_list` to resolve the target cluster. Pass `cid` explicitly from here
   on. Never rely on a default.
3. The round trip below.

## The round trip

Learn this shape and use it every time. It is three steps and none of them is optional.

1. **Pull.** Write the live state into a file. Do this before you edit anything, so
   your file starts from what is really running rather than from what you assume.
   Use `apps_pull` or `services_pull`. Always pass `out` as an ABSOLUTE path, and
   ask the user where the file should land before you write it. With `out` unset
   the file is written inside the installed plugin folder.
2. **Diff.** Preview the change. `apps_diff` and `services_diff` are read-only, so
   run them freely. Read the result and say out loud, to the user, what will change.
3. **Sync.** Apply. `apps_sync` and `services_sync` are writes. Ask the user to
   confirm the exact file and the exact cluster first, by name.

Then follow the job, because a sync can be queued rather than immediate.

## Traps

**The sync tools are not on the server this plugin declares.** The plugin ships one
read-only server. `apps_sync` and `services_sync` are on `runos-write`, which is not
declared, so on a default install step 3 of the round trip has no tool. That is a
missing server, NOT a missing sign-in. Say so, and tell the user to add the server
to their own MCP configuration.

**Diff before every sync, without exception.** A declarative apply reconciles the
whole file, so a field you left out is a field you may have changed. The diff is the
only place that difference is visible before it lands.

**Find out what a sync does to a resource your file does not mention.** A file that
lists one app or one service may not describe everything on that cluster. Read
`iac-desired-state` for the reconcile scope BEFORE the first sync, not after.

**Never edit a file you have not pulled.** An old committed file can carry a shape
the platform no longer accepts, and copying it forward is how that shape spreads.

**Pass every path as an ABSOLUTE path.** The RunOS MCP server runs with its
working directory set to the installed plugin folder, not to the user's project.
`mcp.json` sets `cwd` to the plugin root, which is the only value the Agent
Plugins specification allows there. So a relative `yaml_file` or `out` resolves
inside the plugin folder, and a pull writes the user's live config into the
plugin directory instead of their project.

**Confirm the filename against `apps-config` or `services-iac`.** Do not guess it
and do not infer it from another project.

**A pipeline signs in with an account API key, not a browser.** Never write a
credential into a file in the repository. Read `cicd` and `api-keys` for where it
goes, and for how to scope the key.

**A pipeline removes the confirmation step.** Every safeguard in this skill rests
on asking the user first, and inside a runner there is nobody to ask. A sync that
runs on every push applies whatever the branch says, including a change nobody
reviewed. Say this out loud when you wire one up, and put a human gate in front of
any pipeline that syncs a production cluster.

**A job id is not a result.** When a sync returns a job id, the work has only been
queued. Follow it before you report success.
