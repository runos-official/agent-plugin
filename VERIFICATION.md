# What has been verified, and how

Everything below was RUN. Nothing here is reasoned from source or from
documentation alone. Where a figure is quoted it is a figure that reproduced on
a stock host, and the method is given so it can be re-run.

A separate section at the end lists what has NOT been verified. The README
carries the same list, because a reader deciding whether to trust the plugin
needs it in the README rather than here.

## Corrections to an earlier version of this file

An earlier pass published a timing table for `runos status --json` claiming
1788 ms with `authenticated: false` online and 50022 ms with the network
unreachable. Neither number reproduced. Re-measured on one macOS machine with a
valid session on disk:

    runos status --json, online              2131 ms, 2275 ms, 2338 ms
                                             authenticated: true in all three
    runos status --json, network blackholed  10042 ms, 10087 ms
    through an unroutable RFC 5737 address   authenticated: false
                                             authErrorKind: network

10 seconds is the only timeout on that path. `internal/auth/firebase.go` builds
`http.Client{Timeout: 10 * time.Second}` and `RefreshIDToken` makes one POST
with no retries, so 50 s would need five such calls. The CONCLUSION the table
was offered for is sound and holds independently: `cmd/status.go` calls
`auth.RefreshIDToken` before it answers, so `runos status` is not network free
and must not be a session-start probe. `com.cursor/hooks/binary-check.sh` reads
the config file instead.

The earlier version also claimed the string `deny` did not appear in
`sensitive-guard.sh`. It appeared once, in the comment making the claim. The
guard's tests now assert on the OUTPUT instead, which is the thing that matters.

## The credential failure states, measured

This is the correction that mattered most. Every skill, rule, command and the
sessionStart hook keyed their auth recovery on the CLI's internal
`auth.ErrNotAuthenticated` wording. `internal/auth/resolve.go` produces it only
when no credential path exists at all, and in that state the MCP server exits
before it speaks MCP, so no tool ever returns it. The trigger could not fire.

Measured by driving the live read server over stdio and reading the tool
results:

| State | Measured result |
| ----- | --------------- |
| Invalid or revoked API key | `mcp_bootstrap`, `mcp_topics_show` and `clusters_list` each return `{"error": "Invalid token", "statusCode": 401}` with `isError: true` |
| Expired or invalid interactive refresh token | every tool returns `authentication required: run 'runos login' first` |
| Config present, no credential of any kind | same as above: `authentication required: run 'runos login' first` |
| No config and no credential | `runos mcp serve read` exits 1, writes one line to stderr, `You're not signed in. Run 'runos login' to get started.`, and writes 0 bytes to stdout. No tool answers anything. See the timing note below. |
| `RUNOS_API_KEY=""` | `Error: RUNOS_API_KEY is set but empty; either unset it to fall back to interactive auth, or set it to a real value`, exit 1, server does not start |
| `RUNOS_ACCOUNT_ID=""` | the same message naming `RUNOS_ACCOUNT_ID`, exit 1 |

The 401 envelope carries `statusCode` and no `code` field, so the rule now says
to branch on `code` when present and on `statusCode` otherwise, rather than on
`code` alone.

A timing note, because two passes disagreed and both were right. The
no-credential exit was reported as 341 ms by one reviewer and as 33 ms by the
next. It is a cold-start effect on macOS, isolated by running the same command
three times in a row:

    binary directly, minimal environment    324, 36, 36 ms
    binary directly, full environment        33, 33, 32 ms
    through bin/runos-mcp, full environment  42, 41, 45 ms

So: about 324 to 355 ms on the first execution after the binary has been idle,
and 32 to 45 ms warm, with the launcher costing about 9 ms. Neither figure was
wrong; neither was reproducible without saying which run it was. The number is
not load bearing for anything, and it is recorded only because two passes
published different values for it.

`make validate` fails the build if the old wording reappears in any shipped
guidance. That check found all eleven occurrences across the README, four
SKILL.md files, two rules and two commands when it was first run.

## The beforeMCPExecution guard

`make guard-test` runs 84 checks against `com.cursor/hooks/sensitive-guard.sh`.
Every payload from the review that broke the first version is in there.

The bypass, reproduced against the first version and re-run against this one:

    IN : {"tool_name":"t","tool_input":{"env":{"mcp_server_name":"runos"}},
          "mcp_server_name":"runos-sensitive-write","command":"./bin/runos-mcp"}

    before: {"permission":"allow"}
    now   : {"permission":"ask", ...}

The first version split the payload on commas and braces and took the first
line-anchored match, so a nested key won on byte order. The coupling table with
the spoof present, then and now:

    server                    before   now
    runos                     allow    allow   (correct: the real server IS read)
    runos-sensitive-read      allow    ask
    runos-write               allow    ask
    runos-sensitive-write     allow    ask

The guard now runs a scanner that tracks string state, escape state and brace
depth, and reads `mcp_server_name` only at depth 1. Both serialisations of
`tool_input` are covered: the object form the review used, and the escaped
string form Cursor's documentation specifies. Also covered and asserted:
a spoof inside an array element, a pretty-printed payload, two different
top-level values for the same key, two top-level `tool_name` values where the
second is the credential-shaped one, and a payload whose `mcp_server_name` and
launch `command` name different serve tiers.

The launch `command` is used as a second, independent signal. Cursor documents
it for stdio servers as the launch command and args joined with spaces, so for a
RunOS server it carries `mcp serve <tier>`. Three cases are asserted: a RunOS
name whose command names a different tier asks; a server under an unrecognised
NAME whose command launches the write, sensitive-read or sensitive-write tier
asks, so renaming a server cannot walk a non-read tier past the guard; and a
renamed READ server is allowed, because a prompt on every read is not worth it.

The scanner needs `awk`. Two failure modes are tested with a stub on PATH: an
`awk` that exits non-zero, and an `awk` that runs and prints the wrong shape.
Both discard the scan and fall back to an awk-free, order-immune,
most-restrictive-wins read that still returns `ask` for the bypass payload. Only
the verification covers one awk implementation (one-true-awk 20200816).

### The read server is not credential free

The first version blanket-allowed `runos`, and its comment, the safety rule and
the README all said that server returns no credential. Measured false against
CLI manifest 44.5.0: 634 commands, 294 on `read` and 15
on `sensitive_read`. On the plain `read` tier:

    services/grafana/{id}/credentials      username, PASSWORD, dashboardUrl
    services/litellm/{id}/credentials      masterKey, uiUsername, uiPassword
    services/langfuse/{id}/credentials     initialUserPassword, initialProjectSecretKey
    services/vector/{id}/credentials       clickhousePassword
    services/clickhouse/{id}/credentials   admin, readonly
    services/litellm/{id}/api-keys         the configured AI provider keys
    services/minio/{id}/get-object         key, size, contentType, CONTENT

Those five `credentials` commands move to `sensitive_read` in manifest 45.0.0,
which has not shipped, so a released CLI still has them on `read` today. Three
other `credentials` commands correctly stay on `read` because their output is
only host, port and URL fields: `prometheus`, `traefik` and `netbird-server`.

The guard now asks on a credential-shaped tool name even when the server is
`runos`. That check is ADDITIVE: it can turn an allow into an ask and never the
reverse, so a tool moving to a sensitive server is still covered by the server
rule. Measured cost against 44.5.0: 14 of the 294 read-tier commands match, of
which 7 return a real secret and 7 return only metadata or a URL. The word
"valkey" contains "key" and was checked explicitly: `services_valkey_list`,
`_logs`, `_show` and `_status` do NOT match and are asserted not to.

## The sessionStart probe

`make hook-test` runs 36 checks against `com.cursor/hooks/binary-check.sh`,
each against a sandbox `HOME` and a sandbox `PATH`, so no case depends on the
host's own configuration.

The case that mattered: with `RUNOS_API_KEY=""` and a valid session on disk, the
first version printed NOTHING, which its own comment called "binary present and
credentials present". In that exact state the real binary answers:

    $ RUNOS_API_KEY="" runos mcp serve read
    Error: RUNOS_API_KEY is set but empty; either unset it to fall back to
    interactive auth, or set it to a real value
    exit 1

Four dead servers and silence from the plugin. The probe now checks both
variables for the set-but-empty shape before anything else and names the CLI's
own error text and the fix.

Also asserted: the install commands are present in both missing-binary messages,
both URLs return HTTP 200, the old "point the user at the RunOS install
instructions rather than guessing a command" wording is gone, a `firebase` block
with no refresh token does NOT read as a credential, the hook never exits
non-zero, its output is always valid JSON, and it never prints a value from the
config or the environment (asserted with marker values planted in both).

## Every topic key the plugin names is real

The skills, rules and commands name 25 documentation topic keys between them.
Each was checked by FETCHING it with `runos mcp topics show --key <k>` against
the live dev conductor and confirming the returned `key:` line matches. All 25
resolve:

    api-keys             apps-build-args      apps-config          apps-deploy
    apps-env             apps-overview        apps-requires        auth-credentials
    cicd                 cli-mcp-contract     config-sets          debugging
    dockerfiles          iac-desired-state    jobs                 logs
    metrics              resource-classes     resource-ids         service-limitations
    services-dependencies services-iac        services-overview    storage-options
    vcs-deployment

A note on method, because two obvious approaches both give wrong answers.
Grepping the bootstrap index for a key gives false PASSES, because a short key is
a substring of unrelated prose. Grepping the fetched topic for the word "error"
gives a false FAILURE for `cli-mcp-contract`, whose first lines tell the reader
what to do when they are reading an error. That false failure was reproduced
again while writing this file, which is why the check now compares the returned
key line.

This matters because the plugin's whole design is that skills ROUTE rather than
restate. A skill naming a key that does not exist is worse than no skill: the
agent burns a turn on a refusal and has nothing to fall back on.

## The three authentication paths

Required by the plan, and driven end to end through `bin/runos-mcp` rather than
against the binary directly:

    PATH 1  config moved aside, no credential anywhere
            exit 1, stderr "You're not signed in. Run 'runos login' to get
            started.", never spoke MCP

    PATH 2  config restored, interactive session on disk
            spoke MCP, serverInfo.name "runos", mcp_bootstrap returned the real
            instructions with no error

    PATH 3  RUNOS_API_KEY set, with the working config ALSO on disk
            spoke MCP, and mcp_bootstrap answered
            {"error": "Invalid token", "statusCode": 401}

Path 3 is the background-agent case and the one most likely to be silently
broken, so it is worth saying what it proves. The key used was invalid on
purpose: no real API key was minted for a test. The working on-disk session was
left in place. The server answered 401 rather than succeeding, which is only
possible if `RUNOS_API_KEY` reached the child process AND took precedence over
the on-disk session. That is exactly the property the launcher must not break,
and a launcher that scrubbed the environment would have returned path 2's
success instead.

## The launcher

    ./bin/runos-mcp mcp serve read           returns a valid MCP initialize result,
                                             serverInfo.name "runos",
                                             protocolVersion 2024-11-05
    RUNOS_BIN=/nonexistent                   exit 127, 0 bytes on stdout, stderr
                                             names the install command and says it
                                             will not silently fall back
    PATH=/usr/bin:/bin, RUNOS_BIN unset      `command -v runos` is empty, and the
                                             $HOME/.local/bin fallback still
                                             returns a valid initialize result
    PATH stripped AND an empty HOME          exit 127, 0 bytes on stdout, stderr
                                             names the install command

Branch 4, `/usr/local/bin/runos`, is NOT tested here with its real path
constant. On a stock macOS host `/usr/local/bin` is root-owned and not writable
by the invoking user, so the test cannot place a file there.
`.github/workflows/schema.yml` exercises that branch in CI, where the runner can.

## The four server names and their serve subcommands

`runos mcp serve --help` shows NO subcommands, which reads as though
`mcp serve read` does not exist. It does: the four subcommands are declared with
`Hidden: true` in the CLI, so help omits them deliberately. Anyone auditing
`mcp.json` against `--help` alone will reach the wrong conclusion.

All four were launched and each returned a `serverInfo.name` matching the name
this plugin uses for it: `runos`, `runos-sensitive-read`, `runos-write`,
`runos-sensitive-write`. The three the README tells a user to add by hand were
launched in both documented forms, bare `runos` on PATH and an absolute path,
and all six returned the matching name.

## The leak gate, and the hole in it

`make leakcheck-test` passes: 70 checks, 0 failures. A plain UTF-8 file carrying
a credential shape is caught and the pre-commit hook blocks the commit.

The hole, reproduced here: `leakcheck.py` reads a file as UTF-8 and returns
`None` for content holding a NUL byte or non-UTF-8 bytes, then continues with no
warning and no non-zero exit. Three files were staged, each carrying the same
denylisted content:

    a .dat file with a credential shape plus one NUL byte   leakcheck: clean, exit 0
    a UTF-16 file with a credential shape                   leakcheck: clean, exit 0
    a latin-1 file with a credential shape, no NUL byte     leakcheck: clean, exit 0
    the same content as plain UTF-8                         FAILED, exit 1

`scripts/leakcheck.py`, `scripts/leakcheck_test.py` and `scripts/leakcheck.config`
are byte-identical to the RunOS CLI copies, which is the canonical home, so the
file is NOT forked here. `scripts/unscannable_check.py` closes the hole in this
repository by failing on any tracked file leakcheck cannot read, and it catches
all three files above. It runs in `.githooks/pre-commit`, in
`.github/workflows/leakcheck.yml` and in `make check`. The underlying gap is
filed against the CLI repository, which owns the shared checker and where a fix
reaches all five public repos.

## What has NOT been verified

The verification runs headless, with no Cursor installation present, so nothing
below has been observed in a running editor. The README says so too.

- Whether Cursor resolves a plugin hook command against the plugin root.
  `hooks.json` now names `./com.cursor/hooks/sensitive-guard.sh`, which follows
  the documented plugin tree and the documented rule for project hooks. The
  first version used `./sensitive-guard.sh` and would have resolved to nothing,
  and with `failClosed: true` that would now be a visible outage rather than a
  silent absent guard. `make validate` checks the path resolves from the plugin
  root and is executable, but only a real Cursor window proves the host agrees.
- Whether `{"permission":"allow"}` suppresses Cursor's own MCP approval prompt.
- Whether a client auto-enables an MCP server it finds declared.
- Whether Cursor picks the root `plugin.json` or `.cursor-plugin/plugin.json`
  when both are present, and whether it accepts the custom `rules`, `commands`
  and `hooks` path keys. An earlier pass reported this as ANSWERED. It is not,
  and it could not have been: there is no editor here to answer it.
- Whether Cursor's `.mdc` glob matcher treats `*` as crossing a dot.
- Windows. Not supported, and `bin/runos-mcp.cmd` has been removed rather than
  shipped as a file no manifest can select.
- `awk` implementations other than one-true-awk 20200816.

---

# Independent verification by the COORDINATING agent

These three checks were run by the coordinator, not by the agent that wrote the files, and not by the
agent that later rewrote this document. They were lost once when this file was overwritten, so they are
appended here under their own heading.

## 1. Every documentation topic key the plugin names is real

The four skills and three rules name 24 topic keys between them. Each was checked by actually FETCHING it
with `runos mcp topics show --key <k>` against the live dev conductor, not by grepping an index. All 24
return a real topic:

    api-keys            apps-build-args     apps-config          apps-deploy
    apps-env            apps-overview       apps-requires        auth-credentials
    cicd                cli-mcp-contract    config-sets          debugging
    dockerfiles         iac-desired-state   jobs                 logs
    metrics             resource-classes    resource-ids         service-limitations
    services-iac        services-overview   storage-options      vcs-deployment

This matters because the plugin's whole design is that skills ROUTE rather than restate. A skill naming a
key that does not exist is worse than no skill: the agent burns a turn on a refusal with nothing to fall
back on.

A NOTE ON METHOD, because the first two attempts at this check were both wrong. Grepping the bootstrap
index for a key gives false PASSES, because a short key is a substring of unrelated prose. Grepping the
FETCHED topic for the word "error" gives a false FAILURE, because `cli-mcp-contract` opens by telling the
reader what to do when they are reading an error. Fetch each key and check a topic comes back.

## 2. The two-document gate behaves exactly as the skills describe

Driven over stdio against the live read server with real JSON-RPC, four separate sessions:

    A. a tool call with NO documents read
       clusters_list -> "ERROR: You must call the mcp_bootstrap tool before using any other tool"

    B. mcp_bootstrap, then a tool
       clusters_list -> "ERROR: You have read 1/2 required documents."
       So mcp_bootstrap counts as ONE document, exactly as the skills say.

    C. mcp_bootstrap, then mcp_topics_SEARCH, then a tool
       the search returned 8 matching topics, so the search itself succeeded
       clusters_list -> "ERROR: You have read 1/2 required documents."
       So A SEARCH DOES NOT COUNT. This is the claim most likely to be wrong and it is right.

    D. mcp_bootstrap, then mcp_topics_show, then a tool
       clusters_list -> a real cluster list.

The skills are the plugin's product, and a wrong statement here costs the user a wasted turn on every
session. It also confirms the `runos-bootstrap.mdc` rule: telling the agent to search first and then call a
tool leaves it one document short, and the refusal names a requirement the agent believes it has met.

## 3. The four serve subcommands exist but are HIDDEN

`runos mcp serve --help` shows NO subcommands, which reads as though `mcp serve read` does not exist. It
does. The four are declared with `Hidden: true` in `cli/cmd/mcp.go`. Confirmed by running the server and
getting a real MCP initialize response back with `serverInfo.name` of `runos`.

Anyone auditing `mcp.json` against `--help` alone will reach the wrong conclusion. I did, briefly.
