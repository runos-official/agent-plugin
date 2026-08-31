# Changelog

All notable changes to the RunOS agent plugin are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the plugin uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Agent Plugins 1.0.0 manifest at `plugin.json`, and a Cursor manifest at
  `.cursor-plugin/plugin.json` that points at `com.cursor/` for rules, commands
  and hooks. Skills and `mcp.json` are shared by both formats.
- `mcp.json` declaring the four RunOS MCP servers: `runos`,
  `runos-sensitive-read`, `runos-write` and `runos-sensitive-write`.
- `bin/runos-mcp` and `bin/runos-mcp.cmd`, which resolve the RunOS CLI in the
  order `$RUNOS_BIN`, `PATH`, `~/.local/bin`, then the system location, and
  `exec` that one binary with the environment passed through untouched.
- The leak gate, lifted from the RunOS CLI repo: `scripts/leakcheck.py`,
  `scripts/leakcheck.config`, `scripts/leakcheck_test.py`, an empty
  `scripts/leakcheck.baseline`, `.githooks/pre-commit` and
  `.github/workflows/leakcheck.yml`.
- `scripts/validate_manifests.py` and `.github/workflows/schema.yml`, which
  validate both manifests against the published Agent Plugins 1.0.0 schemas and
  then apply the specification rules a schema cannot express.
- Elastic License 2.0, matching the other public RunOS repositories.

### Notes

- `scripts/leakcheck.py`, `scripts/leakcheck_test.py` and
  `scripts/leakcheck.config` are byte-identical to the RunOS CLI copies. They
  are not forked. `.githooks/pre-commit` and the leak workflow ARE adapted,
  because this repository has two run points rather than three: it ships no
  binary, so it has no release script.
- `scripts/leakcheck.baseline` starts empty. A line in it records a leak that
  already shipped, so an empty baseline is the goal state, not a starting
  inconvenience.
- Agent Plugins 1.0.0 has no field for whether a server is enabled. The
  intended posture, `runos` on and the other three off, is therefore carried by
  the README and by the `beforeMCPExecution` hook, not by `mcp.json`.
- `RUNOS_API_KEY` is deliberately absent from `mcp.json`. The specification
  expands only `${PLUGIN_ROOT}` and `${PLUGIN_DATA}`, so an entry naming any
  other variable would be passed through as literal text and would override the
  real value inherited from the environment. The validator fails the build if
  anyone adds one.
