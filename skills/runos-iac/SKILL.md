---
name: runos-iac
description: Manage RunOS infrastructure declaratively from YAML files, reconcile drift, or wire RunOS into a CI/CD pipeline. Use when the user mentions infrastructure as code, desired state, drift, pull, diff, sync, a pipeline, or a runner. Routes to the RunOS MCP documentation topics; it does not restate them.
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

In every one of those: stop, tell the user to run `runos login` in their terminal
and reload the window, then wait. Do not retry the tool. Do not look for a
credential yourself. The plugin ships none.

For a headless or background agent there is no browser, so the route is an
account API key in the `RUNOS_API_KEY` environment variable instead. Tell the
user that, and stop. If that variable is SET but EMPTY the CLI refuses it
outright and no server starts, so it must be unset or set to a real value. A CI runner is always this case.

**2. The two-document gate.** The RunOS read server refuses its tools until you
have read two documents in this session:

- `mcp_bootstrap` counts as one document.
- each `mcp_topics_show` counts as one document.
- `mcp_topics_search` finds keys. **A search does not count.**

So open every session with `mcp_bootstrap`, then at least one `mcp_topics_show`.
Read `cli-mcp-contract` for the rest of the call rules.

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

## The round trip

Learn this shape and use it every time. It is three steps and none of them is optional.

1. **Pull.** Write the live state into a file. Do this before you edit anything, so
   your file starts from what is really running rather than from what you assume.
   Use `apps_pull` or `services_pull`.
2. **Diff.** Preview the change. `apps_diff` and `services_diff` are read-only, so
   run them freely. Read the result and say out loud, to the user, what will change.
3. **Sync.** Apply. `apps_sync` and `services_sync` are writes. Ask the user to
   confirm the exact file and the exact cluster first.

Then follow the job, because a sync can be queued rather than immediate.

## Traps

**Diff before every sync, without exception.** A declarative apply reconciles the
whole file, so a field you left out is a field you may have changed. The diff is the
only place that difference is visible before it lands.

**Never edit a file you have not pulled.** An old committed file can carry a shape
the platform no longer accepts, and copying it forward is how that shape spreads.

**Pass every path as an ABSOLUTE path.** The RunOS MCP server's working
directory is the installed plugin folder, not the user's project, and the Agent
Plugins specification requires that: a client MUST use the plugin root when
`cwd` is omitted, so no `mcp.json` can point the server at the workspace. A
relative `yaml_file`, `config` or `out` therefore resolves inside the plugin
folder, where `apps_diff` answers "no runos*.yaml found in current directory"
and a pull would write its output.

**Confirm the filename against `apps-config` or `services-iac`.** Do not guess it
and do not infer it from another project.

**A pipeline signs in with an account API key, not a browser.** Never write a
credential into a file in the repository. Read `cicd` and `api-keys` for where it goes.

**A job id is not a result.** When a sync returns a job id, the work has only been
queued. Follow it before you report success.
