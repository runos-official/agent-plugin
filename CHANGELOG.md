# Changelog

All notable changes to the RunOS agent plugin are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the plugin uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-09-01

### Added

- Agent Plugins 1.0.0 manifest at `plugin.json`, and a Cursor manifest at
  `.cursor-plugin/plugin.json` that points at `com.cursor/` for rules, commands
  and hooks. Skills and `mcp.json` are shared by both formats.
- `mcp.json` declaring the RunOS read MCP server, `runos`.
- `bin/runos-mcp`, which resolves the RunOS CLI in the order `$RUNOS_BIN`,
  `PATH`, `~/.local/bin`, then the system location, and `exec`s that one binary
  with the environment passed through untouched.
- Four skills, three Cursor rules, three Cursor commands and two Cursor hooks.
- `com.cursor/hooks/guard_test.sh` and `com.cursor/hooks/binary_check_test.sh`,
  run by `make guard-test`, `make hook-test`, `make check` and CI. 84 and 36
  checks respectively.
- The leak gate, lifted from the RunOS CLI repo: `scripts/leakcheck.py`,
  `scripts/leakcheck.config`, `scripts/leakcheck_test.py`, an empty
  `scripts/leakcheck.baseline`, `.githooks/pre-commit` and
  `.github/workflows/leakcheck.yml`.
- `scripts/unscannable_check.py`, which fails on any tracked file the leak
  checker cannot read. See the note below.
- `scripts/validate_manifests.py` and `.github/workflows/schema.yml`, which
  validate both manifests against the published Agent Plugins 1.0.0 schemas,
  apply the specification rules a schema cannot express, and then apply this
  plugin's own rules.
- Elastic License 2.0, matching the other public RunOS repositories.

### Fixed after review

An adversarial review of the first version found these. Each is recorded with
what was measured, because several of them contradicted what the first version
asserted.

- **The `beforeMCPExecution` guard was fully bypassable.** It resolved the
  server name by splitting the payload on commas and braces and taking the first
  line-anchored match, so a nested key named `mcp_server_name` inside
  `tool_input` won on byte order and turned every `ask` into an `allow` for all
  three non-read servers. On the write server the model itself chooses the key
  names, so one extra map key defeated the guard. The guard now runs a scanner
  that tracks string state, escape state and brace depth and reads the field
  only at top level, with an awk-free most-restrictive-wins fallback for a host
  whose `awk` fails or misbehaves. Both serialisations of `tool_input` are
  covered, the documented string form and the object form the review used.
- **The guard blanket-allowed the read server, on a false premise.** The guard's
  comment, `runos-safety.mdc` and the README all stated that the `runos` server
  returns no credential. Measured against manifest 44.5.0: the plain `read` tier
  returns the Grafana admin password, the LiteLLM master key, the Langfuse
  initial user password and project secret key, the Vector ClickHouse password,
  the ClickHouse admin and readonly passwords, the LiteLLM provider API keys and
  arbitrary MinIO object content. The first five move to `sensitive_read` in
  manifest 45.0.0, which has not shipped, so a released CLI still has them on
  `read`. The guard now also asks on a credential-shaped tool name when the
  server is `runos`, and all three documents state what is true rather than what
  was assumed. That tool-name check is additive only, so it cannot go stale in
  the dangerous direction the "never key on a tool list" rule warns about.
- **The auth recovery string could never fire.** Every skill, rule, command and
  the sessionStart hook keyed recovery on the CLI's internal
  `auth.ErrNotAuthenticated` wording. That error is produced only where no
  credential path exists at all, and in that state the MCP server exits before
  it speaks MCP, so no tool returns it. The real states were measured by driving
  the live server: an invalid credential returns
  `{"error": "Invalid token", "statusCode": 401}`; an expired or absent
  interactive session returns `authentication required: run 'runos login'
  first`; with no credential on the machine `runos mcp serve read` exits 1 in
  about 33 ms with one stderr line and never speaks MCP. All eleven occurrences
  were corrected, and `make validate` now fails the build if the old wording
  reappears in shipped guidance.
- **Published measurements did not reproduce.** A timing table claimed 1788 ms
  with `authenticated: false` online and 50022 ms offline. Re-measured: 2131,
  2275 and 2338 ms online with `authenticated: true`, and 10042 ms offline,
  which is the single 10-second HTTP client timeout in the CLI's token refresh.
  The conclusion the table supported still holds and is now cited from the
  source instead. `VERIFICATION.md` records the correction rather than deleting
  it.
- **Both hook commands were written relative to the hooks directory.**
  `hooks.json` named `./sensitive-guard.sh`, which resolves to
  `<plugin-root>/sensitive-guard.sh` and does not exist. Cursor resolves a hook
  command against the plugin root: its documented tree puts `hooks/hooks.json`
  alongside a command of `./scripts/format-code.sh` with `scripts/` at the root.
  Both hooks would have been silently dead. They now name
  `./com.cursor/hooks/...` and `make validate` fails if a hook command does not
  resolve from the plugin root and is not executable.
- **The sessionStart hook reported all-clear in a state where nothing works.**
  With `RUNOS_API_KEY` set to an empty string and a valid session on disk it
  printed nothing. The CLI refuses a set-but-empty credential variable outright
  rather than falling back, so every MCP server was dead. It now checks both
  `RUNOS_API_KEY` and `RUNOS_ACCOUNT_ID` for that shape before anything else,
  and quotes the CLI's own error text.
- **The missing-binary message withheld the install command.** It told the agent
  to point the user at the install instructions without naming them, and an
  agent reading a hook does not have the README in context. Both install
  commands are now in the message, matching `bin/runos-mcp` and the README.
- **`runos-safety.mdc` understated `runos-sensitive-write`.** The README called
  it "secret writes and credential rotation". It is the only server carrying
  `deploy`, `apps_build`, `run`, `nodes_join-command`,
  `services_postgresql_exec-sql`, `services_postgresql_drop-database` and
  `storage-groups_wipe-device`. Both documents now say so.
- **`runos-bootstrap.mdc` told the agent to read a field that is often absent.**
  It said to read the error's `code` field and never the prose, but the 401 auth
  envelope carries `error` and `statusCode` only. The rule now says to branch on
  `code` when present and on `statusCode` otherwise, and names 401 explicitly.
- **`runos-yaml.mdc` did not cover the environment sidecars.** Its globs matched
  only `runos*.yaml`, so the committed plain sidecar and the gitignored secret
  sidecar named by the `apps-env` topic got no rule at all, and those are the
  files most likely to carry a secret into git. Globs added for both, and the
  rule now describes the pair and the one-key-in-one-file constraint.
- **Nothing told the agent that paths must be absolute.** The MCP server's
  working directory is the plugin folder. The specification requires it: a
  client MUST use the plugin root when `cwd` is omitted, and `${PLUGIN_ROOT}` is
  the same thing, so no `mcp.json` can point a stdio server at the workspace.
  Reproduced from this directory: `runos apps diff` answers "no runos*.yaml
  found in current directory". The safety rule, both path-passing skills, the
  deploy command and the README now say to pass absolute paths.
- **The README did not say that neither hook runs in a Cursor cloud agent.**
  Cursor's documentation lists `sessionStart` and `beforeMCPExecution` under
  hooks not available there, and that is precisely the headless environment the
  README recommends `RUNOS_API_KEY` for. Now stated in the README and in the
  safety rule.
- **The README pointed at a Cursor marketplace listing that does not exist.**
  Removed.

### Changed

- **`mcp.json` declares only the `runos` read server.** The requirement was that
  only the read server is enabled after install. The published 1.0.0 stdio
  object is closed over `type`, `command`, `args`, `env` and `cwd` and has no
  `enabled` field, so a manifest cannot declare a server and switch it off. The
  first version declared all four, stated the constraint, and never said that
  the requirement was therefore UNMET. The two real options were to declare all
  four and say plainly that an install may bring `runos-sensitive-write` up
  live, or to declare one and document the others as user-added. This ships the
  second, which is the only one that actually delivers the requirement. The
  README carries a copy-paste block for the other three, and all three were
  launched in both documented forms and returned their expected
  `serverInfo.name`. What is still unknown until a real Cursor window tests it:
  whether a client auto-enables a server it finds declared.
- **The `beforeMCPExecution` hook now sets `failClosed: true`.** Cursor's
  documentation recommends it for a security-critical hook of that kind, and the
  reason is the failure mode: a crashed fail-open guard waves a sensitive write
  through with no prompt and nothing reports it, while a crashed fail-closed
  guard denies calls loudly and can be seen and fixed. The first version argued
  for fail-open on availability grounds, which no longer holds now that the read
  server is known to return credentials. `sessionStart` keeps the default,
  because it carries no permission decision.
- **The sessionStart hook now always emits context.** It previously stayed
  silent when everything was present. It now says so in one short block and
  names the two refusal strings a tool really returns, which also makes it
  observable whether the hooks resolve at all.

### Removed

- **`bin/runos-mcp.cmd`.** Windows is not supported, and this is a limit of the
  standard. `mcp.json` names one `command`, the 1.0.0 stdio object has no
  per-platform variant, and the specification's only Windows clause is that a
  client MAY use a platform-specific interpreter to launch the resolved
  executable while keeping `command` as one token. So nothing in the package
  could ever select the `.cmd`, while the README called it "the Windows
  launcher". Shipping it implied support that did not exist. `make validate` now
  fails if `bin/` holds a file no `mcp.json` command names. Windows support
  returns when Agent Plugins gains per-platform commands.

### Notes

- `scripts/leakcheck.py`, `scripts/leakcheck_test.py` and
  `scripts/leakcheck.config` are byte-identical to the RunOS CLI copies. They
  are not forked. `.githooks/pre-commit` and the leak workflow ARE adapted,
  because this repository has two run points rather than three: it ships no
  binary, so it has no release script.
- **The leak gate has a hole, and it is not fixed here on purpose.**
  `leakcheck.py` reads a file as UTF-8 and returns `None` for content holding a
  NUL byte or non-UTF-8 bytes, then continues with no warning and no non-zero
  exit. Reproduced in this repository: a `.dat` file with a credential shape
  plus one NUL byte, a UTF-16 file, and a latin-1 file all passed with
  `leakcheck: clean` and exit 0, while the same content as plain UTF-8 failed
  with exit 1. Fixing it here would fork a file that is byte-identical across
  five public repos, which is a worse failure than the one being fixed, so the
  gap is filed against the CLI repository. `scripts/unscannable_check.py` closes
  it in this repository by failing on any tracked file leakcheck cannot read,
  and runs in the pre-commit hook, in CI and in `make check`.
- `scripts/leakcheck.baseline` starts empty. A line in it records a leak that
  already shipped, so an empty baseline is the goal state, not a starting
  inconvenience.
- `RUNOS_API_KEY` is deliberately absent from `mcp.json`. The specification
  expands only `${PLUGIN_ROOT}` and `${PLUGIN_DATA}`, so an entry naming any
  other variable would be passed through as literal text and would override the
  real value inherited from the environment. The validator fails the build if
  anyone adds one.
- `VERIFICATION.md` lists what has been measured and, at the end, what has NOT.
  No Cursor GUI was available on the machine this was built and reviewed on, so
  every claim about how Cursor itself behaves is documentation-grounded and
  unobserved. An earlier pass reported one of those as answered; it was not, and
  it has been demoted.
