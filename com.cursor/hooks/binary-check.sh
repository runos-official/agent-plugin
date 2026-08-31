#!/bin/sh
# RunOS agent plugin: sessionStart probe.
#
# Cursor sends one JSON object on stdin and reads additional_context from
# stdout. This script tells the agent, at the top of the session, whether
# the two things every RunOS tool call needs are actually present:
#
#   1. the runos binary, which the MCP servers are launched from
#   2. a credential, which every tool call is resolved against
#
# It names the exact fix for each. Without this the user's first RunOS
# request fails on a tool call and reads like a broken plugin.
#
# THE PROBE IS NETWORK FREE
# -------------------------
# `runos status` is NOT usable here. On the interactive sign-in path it
# refreshes the token against the identity provider before it answers,
# so it reports a signed-in user as signed out whenever the network is
# slow or absent, and it costs a round trip on every session start.
# This script reads the config file instead and applies the same
# presence test the CLI's own network-free predicate applies:
#
#   RUNOS_API_KEY set and not blank            -> credentials present
#   config api_key set and not blank           -> credentials present
#   config firebase present AND refresh_token  -> credentials present
#
# Presence, not validity. An expired session still reads as present, and
# the tool call is what discovers otherwise. That is the correct trade:
# the alternative costs a network round trip at every session start.
#
# This script reads the config file but never prints any value from it.
# It prints only the two booleans and fixed English text.
#
# FAIL OPEN
# ---------
# Cursor's default when a hook fails is to add no context. This script
# matches that default. Every path either prints one JSON object and
# exits 0, or prints nothing. It never blocks a session and it never
# emits a permission decision, because sessionStart carries none.

# No `set -e`. A missing file or an unreadable config must not abort the
# script before it reaches its output.

emit() {
	# $1 is the context string. It must contain no double quote and no
	# backslash other than the two-character \n sequences used as line
	# breaks, because it is interpolated into JSON without escaping.
	printf '{"additional_context":"%s"}\n' "$1"
	exit 0
}

# Drain stdin so the host never sees a broken pipe. The payload carries
# nothing this probe needs.
cat >/dev/null 2>&1

# ---------------------------------------------------------------- binary

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

# ----------------------------------------------------------- credentials

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

# --------------------------------------------------------------- report

if [ -z "$runos_bin" ] && [ "$have_creds" = "no" ]; then
	emit "RunOS plugin check: the runos command line tool is NOT installed on this machine, and no RunOS credential was found.\\n\\nEvery RunOS tool in this session will fail until both are fixed. Tell the user to do these two steps in their terminal, in order, and wait. Do not call a RunOS tool before they confirm.\\n\\n1. Install the CLI. Point the user at the RunOS install instructions rather than guessing a command.\\n2. Run: runos login\\n\\nOn a background agent or a remote workspace there is no browser, so step 2 is instead an account API key in the RUNOS_API_KEY environment variable.\\n\\nThe RunOS skills and rules in this plugin still apply, so you can keep helping with anything that does not need a tool call."
fi

if [ -z "$runos_bin" ]; then
	emit "RunOS plugin check: the runos command line tool is NOT installed on this machine, or it is not on the PATH this editor sees.\\n\\nEvery RunOS MCP server is launched from that binary, so every RunOS tool in this session will fail. Tell the user to install the RunOS CLI in their terminal and then reload the window. Point them at the RunOS install instructions rather than guessing a command. If it IS installed but only on a login shell PATH, they can set RUNOS_BIN to its full path.\\n\\nDo not call a RunOS tool until they confirm. The RunOS skills and rules in this plugin still apply, so you can keep helping with anything that does not need a tool call."
fi

if [ "$have_creds" = "no" ]; then
	emit "RunOS plugin check: the runos command line tool is installed, but no RunOS credential was found on this machine.\\n\\nEvery RunOS tool call is resolved against a credential, so every one of them will answer not authenticated, including mcp_bootstrap and mcp_topics_show. That means you cannot even read the RunOS documentation topics until this is fixed.\\n\\nTell the user to run this in their terminal, then wait for them to confirm:\\n\\n  runos login\\n\\nOn a background agent or a remote workspace there is no browser and no config file, so the route is instead an account API key in the RUNOS_API_KEY environment variable.\\n\\nDo not retry a refused tool call and do not look for a credential yourself. This plugin ships none. The RunOS skills and rules still apply, so you can keep helping with anything that does not need a tool call."
fi

# Binary present and credentials present. Say nothing: the session start
# is not the place to spend context on good news.
exit 0
