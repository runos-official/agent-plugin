#!/bin/sh
# RunOS agent plugin: sessionStart probe.
#
# Cursor sends one JSON object on stdin and reads additional_context from
# stdout. This script tells the agent, at the top of the session, whether the
# things every RunOS tool call needs are actually present:
#
#   1. the runos binary, which the MCP servers are launched from
#   2. a credential, which every tool call is resolved against
#   3. neither RUNOS_API_KEY nor RUNOS_ACCOUNT_ID set to an EMPTY string
#
# It names the exact fix for each, including the install command. Without this
# the user's first RunOS request fails on a tool call and reads like a broken
# plugin.
#
# WHY CHECK 3 EXISTS
# ------------------
# Measured against the installed CLI. A set-but-empty variable does not fall
# back, it hard refuses, and the MCP server never starts:
#
#   $ RUNOS_API_KEY="" runos mcp serve read
#   Error: RUNOS_API_KEY is set but empty; either unset it to fall back to
#   interactive auth, or set it to a real value
#   exit 1
#
#   $ RUNOS_ACCOUNT_ID="" runos mcp serve read
#   Error: RUNOS_ACCOUNT_ID is set but empty; ...
#   exit 1
#
# cmd/root.go calls auth.ValidateAuthEnvVars in PersistentPreRunE, and
# `mcp serve` is not in its skip list. An earlier version of this hook treated a
# blank RUNOS_API_KEY as "no env credential", fell through to the config file,
# found a session there and stayed SILENT while all four servers were dead. That
# is the CI and background-agent case the CLI added the error for: a secret
# reference that expanded to empty.
#
# THE PROBE IS NETWORK FREE
# -------------------------
# `runos status` is NOT usable here. cmd/status.go calls auth.RefreshIDToken on
# the interactive sign-in path, so it refreshes the token against the identity
# provider before it answers. Measured on this machine with a valid session:
# 2131, 2275 and 2338 ms online, and 10042 ms with the network blackholed
# through an unroutable address, which is the single 10 s http.Client timeout in
# internal/auth/firebase.go. It also answers authenticated:false whenever the
# network is absent, for a user who is perfectly signed in.
#
# This script reads the config file instead and applies the same presence test
# the CLI's own network-free predicate applies:
#
#   RUNOS_API_KEY set and not blank            -> credentials present
#   config api_key set and not blank           -> credentials present
#   config firebase present AND refresh_token  -> credentials present
#
# Presence, not validity. An expired session still reads as present, and the
# tool call is what discovers otherwise. That is the correct trade here, and the
# messages below name the expired case so the agent can recognise it.
#
# A small offline flag on the CLI, something like `runos status --offline`,
# would let this probe ask the CLI itself rather than re-implement its
# predicate. That is the better long-term fix and it belongs in the CLI.
#
# This script reads the config file but never prints any value from it. It
# prints only fixed English text.
#
# FAIL OPEN
# ---------
# sessionStart carries no permission decision, so there is nothing to fail
# closed about: the worst case is that the agent starts a session without this
# context. Every path either prints one JSON object and exits 0, or prints
# nothing.

# No `set -e`. A missing file or an unreadable config must not abort the script
# before it reaches its output.

emit() {
	# $1 is the context string. It must contain no double quote and no
	# backslash other than the two-character \n sequences used as line
	# breaks, because it is interpolated into JSON without escaping.
	printf '{"additional_context":"%s"}\n' "$1"
	exit 0
}

# Drain stdin so the host never sees a broken pipe. The payload carries nothing
# this probe needs.
cat >/dev/null 2>&1

# The install commands, kept identical to bin/runos-mcp and the README. An
# earlier version told the agent to point the user at the install instructions
# without naming them, which left a first-run user with no next step. The agent
# reading this hook does not have the README in context, because a README is
# neither a rule nor a skill.
INSTALL='On macOS or Linux:\\n\\n  curl -fsSL https://get.runos.com/cli.sh | bash\\n\\nOn Windows PowerShell:\\n\\n  irm https://get.runos.com/cli.ps1 | iex'

# ------------------------------------------------- set-but-empty env variables

blank_var=""
if [ -n "${RUNOS_API_KEY+set}" ] && [ -z "${RUNOS_API_KEY}" ]; then
	blank_var="RUNOS_API_KEY"
elif [ -n "${RUNOS_ACCOUNT_ID+set}" ] && [ -z "${RUNOS_ACCOUNT_ID}" ]; then
	blank_var="RUNOS_ACCOUNT_ID"
fi

if [ -n "$blank_var" ]; then
	emit "RunOS plugin check: the environment variable $blank_var is SET but EMPTY, and that stops every RunOS MCP server from starting.\\n\\nThe RunOS CLI refuses a set-but-empty credential variable rather than falling back to the on-disk session, so a session on disk does NOT rescue this. Running the server yourself would print:\\n\\n  Error: $blank_var is set but empty; either unset it to fall back to interactive auth, or set it to a real value\\n\\nTell the user to do ONE of these in the environment this editor was launched from, then reload the window:\\n\\n1. Unset it:  unset $blank_var\\n2. Or set it to a real value.\\n\\nThis is usually a CI or background-agent secret reference that expanded to nothing. Do not call a RunOS tool until they confirm. The RunOS skills and rules in this plugin still apply, so you can keep helping with anything that does not need a tool call."
fi

# ---------------------------------------------------------------------- binary

runos_bin=""
if [ -n "${RUNOS_BIN:-}" ] && [ -x "${RUNOS_BIN}" ]; then
	runos_bin="${RUNOS_BIN}"
elif command -v runos >/dev/null 2>&1; then
	runos_bin=$(command -v runos 2>/dev/null)
elif [ -x "${HOME:-}/.local/bin/runos" ]; then
	runos_bin="${HOME:-}/.local/bin/runos"
elif [ -x "/usr/local/bin/runos" ]; then
	runos_bin="/usr/local/bin/runos"
fi

# ----------------------------------------------------------------- credentials

have_creds="no"

if [ -n "$(printf '%s' "${RUNOS_API_KEY:-}" | tr -d '[:space:]')" ]; then
	have_creds="yes"
else
	cfg="${HOME:-}/.runos/config.json"
	if [ -r "$cfg" ]; then
		raw=$(tr -d '\r\n' <"$cfg" 2>/dev/null)

		# The nested firebase object carries its own api_key, which is a
		# project identifier and not a credential. Remove that object
		# before looking for the top-level api_key, so the two are never
		# confused. The firebase object holds only flat string fields, so
		# a brace-to-brace cut is exact here.
		stripped=$(printf '%s' "$raw" | sed 's/"firebase"[[:space:]]*:[[:space:]]*{[^}]*}//g')

		if printf '%s' "$stripped" | grep -q '"api_key"[[:space:]]*:[[:space:]]*"[^"]'; then
			have_creds="yes"
		elif printf '%s' "$raw" | grep -q '"firebase"[[:space:]]*:' &&
			printf '%s' "$raw" | grep -q '"refresh_token"[[:space:]]*:[[:space:]]*"[^"]'; then
			have_creds="yes"
		fi
	fi
fi

# ---------------------------------------------------------------------- report

if [ -z "$runos_bin" ] && [ "$have_creds" = "no" ]; then
	emit "RunOS plugin check: the runos command line tool is NOT installed on this machine, and no RunOS credential was found.\\n\\nEvery RunOS tool in this session will fail until both are fixed. Tell the user to do these two steps in their terminal, in order, then reload the window, and wait for them to confirm. Do not call a RunOS tool before they do.\\n\\n1. Install the CLI.\\n\\n$INSTALL\\n\\n2. Run: runos login\\n\\nOn a background agent or a remote workspace there is no browser, so step 2 is instead an account API key in the RUNOS_API_KEY environment variable.\\n\\nThe RunOS skills and rules in this plugin still apply, so you can keep helping with anything that does not need a tool call."
fi

if [ -z "$runos_bin" ]; then
	emit "RunOS plugin check: the runos command line tool is NOT installed on this machine, or it is not on the PATH this editor sees.\\n\\nEvery RunOS MCP server is launched from that binary, so every RunOS tool in this session will fail. Tell the user to install the RunOS CLI in their terminal and then reload the window:\\n\\n$INSTALL\\n\\nIf it IS installed but only on a login shell PATH, this editor cannot see it. Cursor launches the server as the bare command 'runos', so RUNOS_BIN does NOT help here. They must put it on the PATH the editor sees, for example by symlinking it into /usr/local/bin, or by launching Cursor from a terminal. Running 'command -v runos' in their own terminal prints its current path.\\n\\nDo not call a RunOS tool until they confirm. The RunOS skills and rules in this plugin still apply, so you can keep helping with anything that does not need a tool call."
fi

if [ "$have_creds" = "no" ]; then
	emit "RunOS plugin check: the runos command line tool is installed, but no RunOS credential was found on this machine.\\n\\nWith no credential at all the RunOS MCP servers do not start, so no RunOS tool answers anything. That includes mcp_bootstrap and mcp_topics_show, which means you cannot even read the RunOS documentation topics until this is fixed.\\n\\nTell the user to run this in their terminal, then reload the window, then wait for them to confirm:\\n\\n  runos login\\n\\nOn a background agent or a remote workspace there is no browser and no config file, so the route is instead an account API key in the RUNOS_API_KEY environment variable.\\n\\nDo not retry a refused tool call and do not look for a credential yourself. This plugin ships none. The RunOS skills and rules still apply, so you can keep helping with anything that does not need a tool call."
fi

# The binary is present and a credential is present. That is presence, not
# validity: an expired sign-in looks exactly like this from here. Say what a
# refusal will look like so the agent recognises it in one step instead of
# retrying, and say nothing else, because the session start is not the place to
# spend context on good news.
emit "RunOS plugin check: the runos CLI is installed and a credential is present. This is a presence check, not a validity check, so the credential may still be expired or revoked.\\n\\nIf a RunOS tool answers any of these, the credential is the problem and the fix is for the USER to run 'runos login' in their terminal and reload the window. Do not retry the tool and do not look for a credential yourself:\\n\\n  authentication required: run 'runos login' first\\n  a JSON error with statusCode 401 and error 'Invalid token'\\n\\nIf every RunOS tool is missing rather than refusing, the servers did not start. That is a different problem: the binary, or a set-but-empty RUNOS_API_KEY or RUNOS_ACCOUNT_ID."
