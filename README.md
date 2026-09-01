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

Copy a local checkout into Cursor's plugin directory:

```bash
rsync -a --exclude .git "$PWD"/ ~/.cursor/plugins/local/runos/
```

Then run **Developer: Reload Window**.

Cursor must own the files. It refuses a symlink whose target is outside
`~/.cursor/plugins/local`, and it reports the refusal only in its
`Cursor Plugins` log, so a symlinked plugin appears to install and then
contributes nothing. Copy the checkout, and copy it again after you pull.

The plugin is not published to the Cursor marketplace yet.

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

### Platforms

macOS and Linux. **Windows is not supported**, and this is a limitation of the
standard rather than an oversight.

`mcp.json` can name only one `command`, and the published 1.0.0 stdio object is
closed over `type`, `command`, `args`, `env` and `cwd`. There is no per-platform
variant, and the specification's own words are that a client MAY use a
platform-specific interpreter to launch the resolved executable but MUST keep
`command` as one token. So a plugin has no way to select a `.cmd` on Windows,
and `./bin/runos-mcp` is an extensionless POSIX script that Windows cannot start.

An earlier version of this repository shipped a `bin/runos-mcp.cmd` and the
README called it "the Windows launcher". Nothing in the package could ever
select it, so it has been removed rather than left as an implied promise.
`make validate` now fails if a file appears in `bin/` that no `mcp.json` command
names. Windows support returns when Agent Plugins gains per-platform commands.

## Layout

```
plugin.json                Agent Plugins 1.0.0 manifest
mcp.json                   the RunOS read MCP server, read by both formats
skills/                    portable task routers, read by both formats
bin/runos-mcp              POSIX launcher
com.cursor/                Cursor-only material
  rules/                   .mdc rules
  commands/                slash commands
  hooks/                   hooks.json, its scripts, and their tests
.cursor-plugin/plugin.json Cursor manifest, points at com.cursor/
scripts/                   the leak gate, the scannability gate, the validator
```

`plugin.json` and `.cursor-plugin/plugin.json` do not collide: a host picks the
manifest for the format it implements. `skills/` and `mcp.json` are shared, so
neither format is degraded to serve the other.

## The MCP servers

RunOS splits its tools across four MCP servers, and the per-server tool
allow-list IS the access control, so which server is switched on decides what an
agent can reach.

| Server                  | Reaches                                                                                       | Declared here |
| ----------------------- | --------------------------------------------------------------------------------------------- | ------------- |
| `runos`                 | reads. Performs no mutation. See the warning below: it is not credential free.                  | yes           |
| `runos-sensitive-read`  | credentials, kubeconfigs, private keys                                                          | no            |
| `runos-write`           | creates, updates and deletes                                                                    | no            |
| `runos-sensitive-write` | deploys, builds, runs commands on machines, drops databases, wipes devices, rotates credentials | no            |

**`mcp.json` declares only `runos`.** That is a deliberate choice, and it is the
only way this requirement can be met: the published 1.0.0 stdio object has no
`enabled` field, so a manifest cannot declare a server and switch it off. The
options were to declare all four and admit that nothing prevents an install from
bringing `runos-sensitive-write` up live, or to declare one. This ships the
second. What is still unknown is whether a client auto-enables a server it
finds declared; that has not been observed in a real Cursor window.

`runos-sensitive-write` is the highest-risk category RunOS has. It carries
`deploy`, `apps_build`, `apps_run`, `run`, `nodes_join-command`,
`services_postgresql_exec-sql`, `services_postgresql_drop-database`,
`storage-groups_delete` and `storage-groups_wipe-device`. **`deploy` lives
there**, so the deploy workflow needs that server, and a user who turns it on
believing it only rotates credentials has also turned on `wipe-device`.

### The read server is NOT credential free

Do not read the table above as "the read server is safe". `runos` performs no
mutation, but on a CLI older than manifest 45.0.0 the plain `read` tier still
returns real secrets:

```
services/grafana/{id}/credentials      the Grafana admin username and password
services/litellm/{id}/credentials      masterKey, uiUsername, uiPassword
services/langfuse/{id}/credentials     initialUserPassword, initialProjectSecretKey
services/vector/{id}/credentials       clickhousePassword
services/clickhouse/{id}/credentials   the admin and readonly passwords
```

Verified against CLI manifest 44.5.0: 634 commands,
of which 294 are on `read` and only 15 on `sensitive_read`. Those five, plus the
LiteLLM provider api-keys command and the MinIO get-object command, and the
NetBird server credentials command whose declared output hid its admin password,
move to
`sensitive_read` in manifest 45.0.0, which has not shipped, so anyone on a
released CLI today still has them on the read tier.

Two more read-tier tools return more than plain state on every manifest:
`services/litellm/{id}/api-keys` returns the configured AI provider keys, and
`services/minio/{id}/get-object` returns stored object content.

Three tools named `credentials` do stay on `read` correctly, because they return
only host, port and URL fields: `prometheus`, `traefik` and `netbird-server`.

The `beforeMCPExecution` hook therefore asks before a credential-shaped tool on
the read server too, not only before the three non-read servers.

### Adding the other three servers

Add them to your own MCP configuration when you need them, and remove them
again afterwards. Each entry is the same, with only the last argument changing:

```json
{
  "mcpServers": {
    "runos-sensitive-read": {
      "command": "runos",
      "args": ["mcp", "serve", "sensitive-read"]
    },
    "runos-write": {
      "command": "runos",
      "args": ["mcp", "serve", "write"]
    },
    "runos-sensitive-write": {
      "command": "runos",
      "args": ["mcp", "serve", "sensitive-write"]
    }
  }
}
```

Keep the server names exactly as written. The safety hook keys on them, so a
renamed server is a server the hook cannot describe.

A GUI-launched editor frequently starts without `~/.local/bin` on `PATH`, and
these entries name the bare `runos` rather than this plugin's launcher, which
only resolves inside the plugin. If a server fails to start, run
`command -v runos` in your own terminal and put that absolute path in `command`.

All six forms above were launched and returned a matching `serverInfo.name`.

## The server's working directory is the plugin folder

The Agent Plugins specification requires it: when `cwd` is omitted a client MUST
use the plugin root, and `${PLUGIN_ROOT}` is the same thing. There is no form of
`mcp.json` that points a stdio server at your workspace.

Several RunOS tools read the filesystem, so **pass every path argument as an
absolute path**. A relative `yaml_file`, `config` or `out` resolves inside the
installed plugin folder. Run from this directory, `runos apps diff` answers "no
runos*.yaml found in current directory", and `apps_pull` would write its output
here. The safety rule tells the agent this; the note is repeated here because a
user whose deploy cannot find `runos.yaml` needs somewhere to read it.

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
non-read servers and for credential-shaped tools on the read server, with a
message naming the risk.

It reads the payload with a scanner that tracks string state, escape state and
brace depth, and takes `mcp_server_name` only at the TOP level. The first
version split the payload on commas and braces and took the first match, which a
review bypassed completely: a nested key named `mcp_server_name` inside
`tool_input` turned every `ask` into an `allow` for all three non-read servers.
On the write server the model itself picks the key names, so one extra map key
defeated the whole guard. `com.cursor/hooks/guard_test.sh` carries every payload
from that review and `make guard-test` runs them.

`binary-check.sh` runs on `sessionStart` and reports a missing CLI, a missing
sign-in, or a `RUNOS_API_KEY` / `RUNOS_ACCOUNT_ID` that is set but EMPTY, each
with its exact fix and the install command spelled out. Its sign-in probe is
network free: it reads the CLI config file rather than calling `runos status`,
which refreshes the session against the identity provider. Measured on one
machine with a valid session, `runos status --json` took 2131, 2275 and 2338 ms
online and 10042 ms with the network blackholed, that last figure being the
single 10-second HTTP client timeout in the CLI's token refresh. A small offline
flag on the CLI would be the better long-term fix, and it belongs in the CLI.

**The guard fails CLOSED, the probe fails open.** `hooks.json` sets
`failClosed: true` on `beforeMCPExecution`, which is what Cursor's own
documentation recommends for a security-critical hook of that kind. The reason
is the failure mode, not a preference: a crashed fail-open guard waves a
sensitive write through with no prompt and nothing anywhere reports it, while a
crashed fail-closed guard denies calls loudly and you can see and fix it. If
every RunOS tool in Cursor is suddenly denied, the guard is failing: check that
`com.cursor/hooks/sensitive-guard.sh` is executable and run `make guard-test`.
`sessionStart` carries no permission decision, so it has nothing to fail closed
about.

Inside the guard the bias is the other way. This hook fires for EVERY MCP server
you have installed, not only this plugin's, so any payload that does not name a
RunOS server is allowed. Denying an unrecognised payload would break unrelated
servers.

**Neither hook runs in a Cursor cloud agent.** Cursor's hooks documentation
lists `sessionStart` and `beforeMCPExecution` under "Hooks not available in
cloud agents". A host that is not Cursor has no hook at all, because it ignores
`com.cursor/`. In both cases which servers you declared is the only control
left, which is the reason `mcp.json` declares one.

## Authentication

The plugin ships no credential and cannot sign anyone in. The RunOS CLI
resolves a token in three steps, and the plugin inherits whichever one applies:

1. `RUNOS_API_KEY` in the environment.
2. A personal access token stored on disk by `runos login --api-key`.
3. The interactive `runos login` session.

Only the MCP tools need any of this. Rules, skills, commands and hooks are
static text and local scripts, so they load signed out, offline, and with no
`runos` binary present. That is deliberate: the half that always loads is the
half that explains the failure, so every skill opens with the auth precondition.

### What a credential failure actually looks like

These strings were measured against the live CLI. Every skill, rule, command and
hook used to key its auth recovery on the CLI's internal
`auth.ErrNotAuthenticated` wording instead, which no RunOS MCP tool ever
returns: the only path that produces it is the path where the server does not
start, so the trigger the design called its sharpest feature could never fire.
`make validate` now fails the build if that wording reappears in any shipped
guidance.

| State | What you see |
| ----- | ------------ |
| Interactive sign-in expired, revoked or absent | every tool answers `authentication required: run 'runos login' first` |
| API key or token invalid or revoked | every tool answers `{"error": "Invalid token", "statusCode": 401}` |
| No credential on the machine at all | `runos mcp serve read` exits 1 with one stderr line, `You're not signed in. Run 'runos login' to get started.`, and never speaks MCP. No tool answers anything, because no tool exists. |
| `RUNOS_API_KEY` or `RUNOS_ACCOUNT_ID` set but EMPTY | the server exits 1 with `Error: RUNOS_API_KEY is set but empty; either unset it to fall back to interactive auth, or set it to a real value` |

The last row is worth its own line. A set-but-empty variable does not fall back
to the session on disk, it hard refuses, so a CI secret reference that expanded
to nothing takes every server down while everything else looks fine. The
`sessionStart` hook checks for it first, before anything else.

The signed-out case has a sharp consequence: `mcp_bootstrap` and
`mcp_topics_show` are RunOS tools too, so a signed-out agent loads a skill
telling it to read the `apps-deploy` topic and then cannot fetch `apps-deploy`.
Two things cover it: the skills state the fix in text the agent already holds,
and the `sessionStart` hook reports the problem at the top of the session.

### Headless and background agents

A background agent or a remote workspace has no browser and no on-disk session.
Set `RUNOS_API_KEY` in that environment. The launcher passes the environment
through untouched, so the variable reaches the server. Set it to a real value or
leave it unset; an empty value is refused.

Note what is absent there: in a Cursor cloud agent neither hook loads, so there
is no confirmation prompt and no session check. Which servers you declared is
the only control in that environment.

`RUNOS_API_KEY` is deliberately **not** named in `mcp.json`. The Agent Plugins
specification allows exactly two placeholders in `env`, `${PLUGIN_ROOT}` and
`${PLUGIN_DATA}`, and requires clients to expand nothing else. An entry reading
`"RUNOS_API_KEY": "${RUNOS_API_KEY}"` would therefore set the variable to the
literal text `${RUNOS_API_KEY}`, which is a broken key rather than a missing
one, and it would override the real value inherited from the environment.
`scripts/validate_manifests.py` fails the build if anyone adds it.

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

## What is still unverified

Kept here rather than in a report, because a reader deciding whether to trust
this plugin needs it. The verification runs headless, with no Cursor installation present,
and reviewed on, so nothing below has been observed in a real editor.

- **Whether Cursor finds the hooks at all.** `hooks.json` names
  `./com.cursor/hooks/sensitive-guard.sh`, plugin-root relative. That follows
  Cursor's documented tree, where `hooks/hooks.json` names
  `./scripts/format-code.sh` with `scripts/` at the root, and its rule for
  project hooks that a command is relative to the root and not to the hooks
  directory. The first version used `./sensitive-guard.sh` and would have
  resolved to nothing. `make validate` now checks that every hook command
  resolves from the plugin root and is executable, but only a real Cursor window
  proves the host agrees.
- **Whether `{"permission":"allow"}` suppresses Cursor's own MCP approval
  prompt.** If it does not, the guard's `ask` adds a prompt and its `allow`
  changes nothing. If it does, an `allow` removes a prompt the user would
  otherwise have seen, which is why the read server no longer gets a blanket
  one.
- **Whether Cursor auto-enables a declared MCP server on install.**
- **Whether Cursor picks the root `plugin.json` or `.cursor-plugin/plugin.json`
  when both are present**, and whether it accepts the custom `rules`,
  `commands` and `hooks` path keys. If the root manifest wins, none of
  `com.cursor/` loads and the hooks never run.
- **Whether Cursor's `.mdc` glob matcher treats `*` as crossing a dot.**
  `runos-yaml.mdc` needs it for `runos.service.<cid>.<type>.<sid>.yaml`.
- **Whether Cursor serialises `beforeMCPExecution` `tool_input` as an object or
  as an escaped JSON string.** The documentation types it as a string. The guard
  is tested against both shapes and both are safe, so this no longer decides
  anything.
- **`sh` variants other than the one on the build machine.** The guard's scanner
  needs `awk`; it was exercised against one-true-awk 20200816 only. An `awk`
  that fails, and an `awk` that returns the wrong shape, both fall back to an
  awk-free most-restrictive-wins read, and `make guard-test` covers both.
- **Windows.** Not supported, see Platforms above.

## Development

```bash
make hooks       # point git at .githooks, once per clone
make check       # everything a push must pass
```

| Target                  | Does                                                     |
| ----------------------- | -------------------------------------------------------- |
| `make leakcheck`        | scan every tracked file for leaks                        |
| `make leakcheck-staged` | scan only the staged diff                                |
| `make unscannable`      | fail on a tracked file leakcheck cannot read             |
| `make leakcheck-test`   | test the leak checker itself                             |
| `make validate`         | validate the manifests and this plugin's own rules       |
| `make guard-test`       | test the `beforeMCPExecution` guard                      |
| `make hook-test`        | test the `sessionStart` probe                            |

### The leak gate

This is a PUBLIC repo. `scripts/leakcheck.py` keeps internal identifiers and
credentials out of it, and the file is byte-identical in every public RunOS
repo. Credential shapes are a hard fail and can never be baselined. Internal
identifiers are ratcheted against `scripts/leakcheck.baseline`, which starts
empty here and should stay that way.

The gate has two run points in this repo:

1. `.githooks/pre-commit`, opt-in per clone and skippable, for fast feedback.
2. `.github/workflows/leakcheck.yml`, on every push and every pull request,
   whole tree, not skippable by a committer.

The checker's own header names a third run point, `scripts/release.sh`. That
belongs to the repos that ship a binary. This one does not, so run point 2 is
the last gate.

**Run point 2 is not skippable, but it is not infallible.** `leakcheck.py` reads
a file as UTF-8 and returns `None` for content holding a NUL byte or non-UTF-8
bytes, then continues with no warning and no non-zero exit. A reviewer proved
the consequence here: a `.dat` file carrying a credential shape plus one NUL
byte, and a UTF-16 file carrying the same, both passed with `leakcheck: clean`
and exit 0, and the commit succeeded. The same content in a plain UTF-8 file was
caught. That gap is in the shared checker, which the RunOS CLI repo owns, so it
is not forked here; it is filed there. `scripts/unscannable_check.py` closes it
in this repository by failing on any tracked file leakcheck cannot read, and it
runs in the pre-commit hook and in CI beside leakcheck itself.

### Manifest validation

`make validate` checks `plugin.json` and `mcp.json` against the schemas
published at their canonical 1.0.0 identifiers, then applies the rules the
specification states in prose that a schema cannot express: the two documents
must target the same version, a `command` must be a bare name or a `./` path
that really exists in the package, and `${...}` may name only the two reserved
placeholders.

It then applies this plugin's own rules, each of which exists because a review
found it broken: every `hooks.json` command must resolve from the plugin root
and be executable, `bin/` must hold only files an `mcp.json` command names, and
no shipped guidance may tell an agent to key on a failure string the platform
never emits. `.github/workflows/schema.yml` runs the same script on every push,
plus both hook test suites.

## License

Elastic License 2.0. See [LICENSE](LICENSE).
