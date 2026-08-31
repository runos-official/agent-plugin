#!/bin/sh
# RunOS agent plugin: beforeMCPExecution guard.
#
# Cursor sends one JSON object on stdin. This script reads the server name
# from it and returns a permission decision on stdout.
#
# WHY THIS KEYS ON THE SERVER NAME, NEVER ON A TOOL LIST
# ------------------------------------------------------
# RunOS splits its tools across four MCP servers, and that split IS the
# access control. A tool can move between servers when the platform
# changes: vms_ssh-key returns a machine private key and moved from the
# read server to the sensitive-read server in manifest 41.0.0. A guard
# written against a hardcoded tool list before that change would still
# have waved it through afterwards. The server name does not go stale,
# so the server name is what this script matches.
#
# FAIL OPEN
# ---------
# Cursor's default when a hook fails is to allow. This script matches
# that default on purpose. A broken guard must never lock a user out of
# the read tools. Every path either prints one decision and exits 0, or
# prints nothing and lets the host apply its default. No path can emit a
# deny by accident, because the string "deny" is not in this file.
#
# This script never reads a credential and never prints one.

# No `set -e`. An unexpected non-zero from a helper must not abort the
# script before it reaches a decision.

allow() {
	printf '%s\n' '{"permission":"allow"}'
	exit 0
}

ask() {
	# $1 is the agent message. It must contain no double quote and no
	# backslash, because it is interpolated into JSON without escaping.
	printf '{"permission":"ask","agent_message":"%s","user_message":"%s"}\n' "$1" "$1"
	exit 0
}

payload=$(cat 2>/dev/null)

# Split the object on commas and braces so each key lands on its own
# line, then match the key anchored at the start of a line. This avoids
# the greedy-match problem a single sed substitution would have, and it
# cannot match an escaped copy of the key inside some other string value.
server=$(
	printf '%s' "$payload" |
		tr -d '\r\n' |
		tr ',{}' '\n\n\n' |
		sed -n 's/^[[:space:]]*"mcp_server_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
		head -n 1
)

# No server name means this is not a payload shape we understand. Defer
# to the host rather than guessing.
if [ -z "$server" ]; then
	allow
fi

case "$server" in
runos)
	# Plain reads. No mutation, no credential returned.
	allow
	;;
runos-sensitive-read)
	ask "RunOS sensitive read. This tool returns a live credential, such as a password, a connection string or a private key. The value enters this conversation and stays in it. Approve only if you want that value shown here."
	;;
runos-write)
	ask "RunOS write. This tool changes live infrastructure that other people may depend on, and there is no undo. Check the resource id and the cluster id in the arguments before you approve."
	;;
runos-sensitive-write)
	ask "RunOS sensitive write. This tool changes live infrastructure AND can expose a credential or run a command on a machine. It is the highest risk category RunOS has. Check the resource id and the cluster id before you approve."
	;;
runos*sensitive* | runos*write*)
	# A RunOS server this build does not know by name, whose name says it
	# is not a plain read. Ask rather than assume.
	ask "Unrecognised RunOS server whose name indicates a write or a credential read. This guard does not know it, so it cannot describe the risk. Read the tool name and the arguments before you approve."
	;;
*)
	# Not a RunOS server. Not this plugin's business.
	allow
	;;
esac

# Unreachable. Present so that an edit which breaks the case statement
# still falls through to the safe-for-availability default.
allow
