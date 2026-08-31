# RunOS agent plugin

RunOS tools, guidance and a safety gate for AI coding agents.

The plugin gives an agent the RunOS platform: clusters, nodes, managed services,
applications, jobs and virtual machines. It ships in two formats from one tree.
It is an [Agent Plugin](https://agent-plugins.org) for any host that reads the
open standard, and a Cursor Plugin for Cursor, which adds rules, commands and
hooks on top.

The plugin carries no credential. It runs the RunOS CLI that is already
installed on your machine, and that CLI holds your session.

## Install

### Cursor

Install **RunOS** from the Cursor marketplace, then open **Customize** to see
what it added.

To develop against a local checkout instead:

```bash
ln -s "$PWD" ~/.cursor/plugins/local/runos
```

Then run **Developer: Reload Window**.

### Any other Agent Plugins host

Point the host at this directory. It reads `plugin.json`, `mcp.json` and
`skills/`. Everything under `com.cursor/` is ignored by a host that is not
Cursor, which is what the reverse-domain namespace is for.

### The RunOS CLI

The plugin needs the `runos` binary. Install it:

```bash
curl -fsSL https://get.runos.com/cli.sh | bash
```

```powershell
irm https://get.runos.com/cli.ps1 | iex
```

Then sign in once, in a terminal:

```bash
runos login
```

One sign-in serves every workspace and every editor, because the CLI stores the
session per machine rather than per project.

## Layout

```
plugin.json                Agent Plugins 1.0.0 manifest
mcp.json                   four RunOS MCP servers, read by both formats
skills/                    portable task routers, read by both formats
bin/runos-mcp              POSIX launcher
bin/runos-mcp.cmd          Windows launcher
com.cursor/                Cursor-only material
  rules/                   .mdc rules
  commands/                slash commands
  hooks/                   hooks.json and its scripts
.cursor-plugin/plugin.json Cursor manifest, points at com.cursor/
scripts/                   the leak gate and the manifest validator
```

`plugin.json` and `.cursor-plugin/plugin.json` do not collide: a host picks the
manifest for the format it implements. `skills/` and `mcp.json` are shared, so
neither format is degraded to serve the other.

## The MCP servers

`mcp.json` declares four servers. They are separate on purpose: the per-server
tool allow-list IS the access control, so which server is switched on decides
what an agent can reach.

| Server                  | Reaches                                    |
| ----------------------- | ------------------------------------------ |
| `runos`                 | read-only state                            |
| `runos-sensitive-read`  | credentials, kubeconfigs, keys             |
| `runos-write`           | creates, updates and deletes               |
| `runos-sensitive-write` | secret writes and credential rotation      |

**Enable only `runos` and leave the other three off** unless you need them.
Turn one on per task in Cursor's Customize panel, then turn it off again.

Agent Plugins 1.0.0 has no field for "enabled", so `mcp.json` cannot express
that default. Two things carry it instead: this instruction, and the
`beforeMCPExecution` hook in `com.cursor/hooks/`, which keys on the server name
and asks before any call to the three non-read servers. The hook keys on the
SERVER, never on a list of tool names, because tools move between servers:
`vms_ssh-key` moved from `runos` to `runos-sensitive-read` in manifest 41.0.0,
and any hardcoded tool list would have silently stopped matching it.

## Skills, rules, commands and hooks

### Skills, in `skills/` (both formats)

Four task routers. Each names the RunOS documentation topics to read, the tool
order, and the traps.

| Skill                   | Use it for                                        |
| ----------------------- | ------------------------------------------------- |
| `runos-deploy-app`      | deploying or redeploying an application           |
| `runos-managed-service` | adding, sizing or wiring a managed service        |
| `runos-iac`             | managing RunOS from files, and from a pipeline    |
| `runos-triage`          | diagnosing a failure, using reads only            |

**The skills route, they do not restate.** RunOS ships its documentation inside
the MCP server, and that documentation is the source of truth. A skill that
copied it would go stale the moment the platform moved, and nothing would report
the drift. So a skill names topic keys and states no RunOS fact of its own.

### Rules, in `com.cursor/rules/` (Cursor)

| Rule              | Applies                                                |
| ----------------- | ------------------------------------------------------ |
| `runos-bootstrap` | on description match, to open a session correctly       |
| `runos-safety`    | always, to gate writes and credential reads             |
| `runos-yaml`      | to RunOS configuration files in the workspace           |

`runos-bootstrap` mirrors the server's own gate: the read server answers nothing
until two documents have been read, where `mcp_bootstrap` counts as one and each
`mcp_topics_show` counts as one. A search does not count. Following the rule
costs two cheap calls; ignoring it costs a refused call and a wasted turn.

### Commands, in `com.cursor/commands/` (Cursor)

`/runos-check` reports whether this session can reach RunOS at all.
`/runos-deploy` and `/runos-triage` drive the matching skill end to end.

### Hooks, in `com.cursor/hooks/` (Cursor)

`sensitive-guard.sh` runs on `beforeMCPExecution` and returns `ask` for the three
non-read servers, with a message naming the risk. The read server passes without
a prompt.

`binary-check.sh` runs on `sessionStart` and reports a missing CLI or a missing
sign-in, each with its exact fix, before the agent wastes a tool call finding out.
Its sign-in probe is network free: it reads the CLI config file rather than
calling `runos status`, which refreshes the session against the identity provider
and so reports a signed-in user as signed out whenever the network is slow or
absent.

**Both hooks fail open**, which matches Cursor's own default. A hook that failed
closed would turn a typo in a shell script into a total outage of the read tools,
which is the wrong trade for a component whose job is a confirmation prompt. The
consequence is worth stating plainly: if the guard script is broken, a sensitive
call proceeds without its prompt. The per-server enable switch above is the
control that does not depend on a script running correctly.

## Authentication

The plugin ships no credential and cannot sign anyone in. The RunOS CLI
resolves a token in three steps, and the plugin inherits whichever one applies:

1. `RUNOS_API_KEY` in the environment.
2. A personal access token stored on disk by `runos login --api-key`.
3. The interactive `runos login` session.

Only the MCP tools need any of this. Rules, skills, commands and hooks are
static text and local scripts, so they load signed out, offline, and with no
`runos` binary present. That is deliberate: the half that always loads is the
half that explains the failure, so every skill opens with the auth
precondition.

That asymmetry is sharper than it first looks. Signed out, **every** RunOS tool
answers `not authenticated`, and that includes `mcp_bootstrap` and
`mcp_topics_show`. So a signed-out agent loads a skill telling it to read the
`apps-deploy` topic and then cannot fetch `apps-deploy`. Two things cover it: the
skill states the fix in text the agent already holds, and the `sessionStart` hook
reports the problem at the top of the session. If you see the agent ask you to
run `runos login` before it calls anything, that is this working.

### Headless and background agents

A background agent or a remote workspace has no browser and no on-disk session.
Set `RUNOS_API_KEY` in that environment. Both launchers pass the environment
through untouched, so the variable reaches the server.

`RUNOS_API_KEY` is deliberately **not** named in `mcp.json`. The Agent Plugins
specification allows exactly two placeholders in `env`, `${PLUGIN_ROOT}` and
`${PLUGIN_DATA}`, and requires clients to expand nothing else. An entry reading
`"RUNOS_API_KEY": "${RUNOS_API_KEY}"` would therefore set the variable to the
literal text `${RUNOS_API_KEY}`, which is a broken key rather than a
missing one, and it would override the real value inherited from the
environment. `scripts/validate_manifests.py` fails the build if anyone adds it.

A conforming client MAY sanitise the environment it gives a plugin subprocess.
If a host does that, the `RUNOS_API_KEY` route cannot work there, and the
on-disk session is the only way in.

## The launcher

`mcp.json` starts `./bin/runos-mcp`, not `runos`. The Agent Plugins
specification allows only a bare executable name or a plugin-relative path, and
it tells plugins not to depend on how a client searches for a bare name. A
GUI-launched editor also frequently starts without `~/.local/bin` on PATH. The
launcher does the search itself, in this order:

1. `$RUNOS_BIN`, which is authoritative: if it is set and does not resolve, the
   launcher stops rather than quietly running a different binary.
2. `runos` on `PATH`.
3. `~/.local/bin/runos`.
4. `/usr/local/bin/runos`.

It then `exec`s that one binary. One binary matters because several RunOS tools
read the filesystem, so a second copy at another version would answer from a
different view of your project.

If nothing resolves, the launcher writes the install command to stderr and
exits non-zero. It never writes to stdout, because stdout is the MCP channel.

Override it when your binary is somewhere else:

```bash
export RUNOS_BIN=/opt/runos/bin/runos
```

## Development

```bash
make hooks       # point git at .githooks, once per clone
make check       # leakcheck + the checker's tests + manifest validation
```

| Target                  | Does                                                     |
| ----------------------- | -------------------------------------------------------- |
| `make leakcheck`        | scan every tracked file for leaks                        |
| `make leakcheck-staged` | scan only the staged diff                                |
| `make leakcheck-test`   | test the leak checker itself                             |
| `make validate`         | validate both manifests against Agent Plugins 1.0.0      |

### The leak gate

This is a PUBLIC repo. `scripts/leakcheck.py` keeps internal identifiers and
credentials out of it, and the file is byte-identical in every public RunOS
repo. Credential shapes are a hard fail and can never be baselined. Internal
identifiers are ratcheted against `scripts/leakcheck.baseline`, which starts
empty here and should stay that way.

The gate has two run points in this repo:

1. `.githooks/pre-commit`, opt-in per clone and skippable, for fast feedback.
2. `.github/workflows/leakcheck.yml`, on every push and every pull request,
   whole tree, not skippable.

The checker's own header names a third run point, `scripts/release.sh`. That
belongs to the repos that ship a binary. This one does not, so run point 2 is
the last gate.

### Manifest validation

`make validate` checks `plugin.json` and `mcp.json` against the schemas
published at their canonical 1.0.0 identifiers, then applies the rules the
specification states in prose that a schema cannot express: the two documents
must target the same version, a `command` must be a bare name or a `./` path
that really exists in the package, and `${...}` may name only the two reserved
placeholders. `.github/workflows/schema.yml` runs the same script on every push.

## License

Elastic License 2.0. See [LICENSE](LICENSE).
