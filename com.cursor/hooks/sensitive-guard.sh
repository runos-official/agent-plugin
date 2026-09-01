#!/bin/sh
# RunOS agent plugin: beforeMCPExecution guard.
#
# Cursor sends one JSON object on stdin. This script decides whether the call
# proceeds without a prompt, and prints that decision on stdout.
#
# WHAT THE HOST SENDS (cursor.com/docs/hooks.md, beforeMCPExecution)
# ------------------------------------------------------------------
#   tool_name          the MCP tool about to run
#   tool_input         the JSON params, AS A STRING
#   mcp_server_name    the server's key in mcp.json
#   command            stdio servers only: the launch command and args joined
#                      with spaces, so for RunOS it carries "mcp serve <tier>"
#
# WHY THIS PARSES INSTEAD OF PATTERN MATCHING
# -------------------------------------------
# The first version of this script split the payload on commas and braces and
# took the FIRST line matching the key. That is not a parse, and it was fully
# bypassable. A reviewer proved it with the documented field order:
#
#   IN : {"tool_name":"t","tool_input":{"env":{"mcp_server_name":"runos"}},
#         "mcp_server_name":"runos-sensitive-write","command":"./bin/runos-mcp"}
#   OUT: {"permission":"allow"}
#
# One extra map key defeated the whole guard, and on the write server the model
# itself chooses the key names (apps_secret-env-vars_set takes a free-form map).
# The documented shape says tool_input is a STRING, which would make that
# payload unreachable in a real Cursor, but a permission decision must not rest
# on how a host happens to serialise a field this year.
#
# So this script runs a real scanner (below) that tracks string state, escape
# state and brace depth, and reads mcp_server_name only at TOP LEVEL. A nested
# key at any other depth is reported separately and never mistaken for the
# host's own field.
#
# WHY IT KEYS ON THE SERVER NAME
# ------------------------------
# RunOS splits its tools across four MCP servers, and that split IS the access
# control. A tool moves between servers when the platform changes: vms_ssh-key
# returns a machine private key and moved from the read server to the
# sensitive-read server in manifest 41.0.0. A guard written against a hardcoded
# tool list before that change would still have waved it through afterwards.
#
# THE READ SERVER IS NOT CREDENTIAL FREE, AND THE TOOL CHECK IS ADDITIVE
# ----------------------------------------------------------------------
# This script used to blanket-allow the `runos` read server on the grounds that
# it returns no secret. That was measured false. On manifest 44.5.0 the plain
# `read` tier carries, among 294 commands:
#
#   services/grafana/{id}/credentials     the Grafana admin username and password
#   services/litellm/{id}/credentials     masterKey, uiUsername, uiPassword
#   services/langfuse/{id}/credentials    initialUserPassword, initialProjectSecretKey
#   services/vector/{id}/credentials      clickhousePassword
#   services/clickhouse/{id}/credentials  the admin and readonly passwords
#   services/litellm/{id}/api-keys        the configured AI provider API keys
#   services/minio/{id}/get-object        arbitrary stored object CONTENT
#
# EIGHT commands move to the sensitive_read tier in manifest
# 45.0.0, but that has not shipped. Anyone on an older CLI still has them on the
# tier every agent host gets by default. So the read server gets one extra
# check: a tool whose NAME is credential shaped is asked about, not allowed.
#
# That tool-name check is ADDITIVE ONLY. It can turn an allow into an ask and
# never the reverse, so it cannot go stale in the dangerous direction. When a
# tool moves to a sensitive server, the server rule above already asks; while it
# stays on read, the name rule asks. Both directions are covered, which is why
# this does not reintroduce the hardcoded-tool-list problem described above.
#
# Cost, measured against manifest 44.5.0: 14 of the 294 read-tier commands match
# and would prompt. Seven of those return a real secret. The other seven return
# only metadata or a URL, so they are prompts the user does not strictly need,
# on tools whose own names say "credential", "api-key" or "secret".
#
# FAIL BEHAVIOUR
# --------------
# hooks.json sets failClosed:true on this hook. Cursor's own documentation
# recommends that for a security-critical beforeMCPExecution hook, and the
# reason is the failure mode: a crashed fail-open guard waves a sensitive write
# through with no prompt and nothing anywhere reports it, while a crashed
# fail-closed guard denies calls loudly and the user can see and fix it. A
# silent absent control is worse than a visible outage.
#
# Inside the script the bias is the other way. Every path that cannot identify a
# RunOS server allows, because this hook fires for EVERY MCP server the user has
# installed, not only this plugin's. Denying an unrecognised payload would break
# unrelated servers. See com.cursor/hooks/guard_test.sh for the cases.
#
# This script never reads a credential and never prints one.

# No `set -e`. An unexpected non-zero from a helper must not abort the script
# before it reaches a decision.

allow() {
	printf '%s\n' '{"permission":"allow"}'
	exit 0
}

ask() {
	# $1 is the message. It is interpolated into JSON without escaping, so it
	# must contain no double quote and no backslash. Every caller passes a
	# fixed English string, optionally with $tool appended, and $tool is
	# reduced to [A-Za-z0-9._-] before it gets here.
	printf '{"permission":"ask","agent_message":"%s","user_message":"%s"}\n' "$1" "$1"
	exit 0
}

payload=$(cat 2>/dev/null)

# ------------------------------------------------------------------ scanner
#
# Walks the payload one character at a time, tracking whether it is inside a
# string, whether the previous character was a backslash, and the current
# brace/bracket depth. It pairs a string that is followed by ':' with the next
# string value, and prints one line per interesting field:
#
#     <depth> <key> <value>
#
# Depth 1 is the top level of the object the host sent. Anything deeper is
# inside tool_input or another nested structure and is NOT the host's own
# field.
#
# The value is reduced to [A-Za-z0-9._/@:+-] and truncated, so nothing that
# reaches the shell can break out of a variable or into the JSON this script
# prints. awk is a POSIX-required utility, so this needs nothing installed.

scan=$(printf '%s' "$payload" | awk '
{ doc = doc $0 "\n" }
END {
	n = length(doc)
	depth = 0; ins = 0; esc = 0
	buf = ""; last = ""; lastd = 0; pend = ""; pendd = 0; want = 0; hadesc = 0
	for (i = 1; i <= n; i++) {
		c = substr(doc, i, 1)
		if (ins) {
			if (esc) { buf = buf c; esc = 0 }
			else if (c == "\\") { esc = 1; hadesc = 1 }
			else if (c == "\"") {
				ins = 0
				if (want) { report(pendd, pend, hadesc ? "escaped." buf : buf); want = 0; pend = "" }
				else { last = buf; lastd = depth }
			}
			else buf = buf c
			continue
		}
		if (c == "\"") { ins = 1; buf = ""; hadesc = 0; continue }
		if (c == "{" || c == "[") { depth++; want = 0; continue }
		if (c == "}" || c == "]") { depth--; want = 0; continue }
		if (c == ":") { pend = last; pendd = lastd; want = 1; continue }
		if (c == ",") { want = 0; continue }
		if (c != " " && c != "\t" && c != "\r" && c != "\n") want = 0
	}
}
function report(d, k, v,   safe) {
	if (k != "mcp_server_name" && k != "tool_name" && k != "command") return
	safe = v
	gsub(/[^A-Za-z0-9._\/@:+-]/, "_", safe)
	safe = substr(safe, 1, 120)
	if (safe == "") safe = "_"
	printf "%d %s %s\n", d, k, safe
}
' 2>/dev/null)

# ------------------------------------------------------- classify a server
#
# Prints one word: read, sensitive-read, write, sensitive-write, unknown-runos
# or other. Used for both the authoritative value and every fallback candidate.

classify() {
	case "$1" in
	runos) printf 'read' ;;
	runos-sensitive-read) printf 'sensitive-read' ;;
	runos-write) printf 'write' ;;
	runos-sensitive-write) printf 'sensitive-write' ;;
	# A value that carried a JSON escape cannot be compared literally. The scanner
	# drops the backslash, so `runos-\u0077rite` arrived as `runos-u0077rite` and fell
	# through to `other`, which ALLOWS. That is a real bypass, because the payload names
	# runos-write and JSON says the two spellings are the same string. Anything that was
	# escaped is therefore unknown, and unknown is never allowed.
	escaped.*) printf 'unknown-runos' ;;
	runos*sensitive* | runos*write*) printf 'unknown-runos' ;;
	*) printf 'other' ;;
	esac
}

ask_for() {
	case "$1" in
	sensitive-read)
		ask "RunOS sensitive read. This tool returns a live credential, such as a password, a connection string or a private key. The value enters this conversation and stays in it. Approve only if you want that value shown here."
		;;
	write)
		ask "RunOS write. This tool changes live infrastructure that other people may depend on, and there is no undo. Check the resource id and the cluster id in the arguments before you approve."
		;;
	sensitive-write)
		ask "RunOS sensitive write. This tool changes live infrastructure AND can expose a credential or run a command on a machine. It is the highest risk category RunOS has, and it is the server that carries deploy, apps_build, run, the postgresql exec-sql and drop-database tools, and storage-groups_wipe-device. Check the resource id and the cluster id before you approve."
		;;
	unknown-runos)
		ask "Unrecognised RunOS server whose name indicates a write or a credential read. This guard does not know it, so it cannot describe the risk. Read the tool name and the arguments before you approve."
		;;
	esac
}

# ------------------------------------------------------ credential-shaped tool

tool_returns_secret() {
	# $1 is a tool name, already reduced to a safe charset. Matched case
	# insensitively against the shapes RunOS uses for a command that returns
	# a secret or arbitrary stored content.
	lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
	case "$lower" in
	*credential* | *api-key* | *api_key* | *apikey* | *secret* | *password* | \
		*token* | *private-key* | *private_key* | *ssh-key* | *ssh_key* | \
		*kubeconfig* | *get-object* | *get_object*)
		return 0
		;;
	esac
	return 1
}

ask_read_credential() {
	ask "RunOS read server, credential shaped tool: $1. The RunOS read server performs no mutation, but it is NOT credential free. On manifest 44.5.0 the plain read tier still carries the Grafana, LiteLLM, Langfuse, Vector and ClickHouse credentials commands, the LiteLLM provider api-keys command, and the MinIO get-object command, which returns stored object content. The NetBird server credentials command is an eighth: it also returns an admin password, and its declared output named only two URLs, so a tier audit read from the manifest could not see it. All eight move to the sensitive read tier in manifest 45.0.0, which has not shipped. Approve only if you want that value in this conversation."
}

# Only one awk implementation was available to test this against
# (one-true-awk 20200816). A variant that FAILS is handled: $scan comes back
# empty and the fallback below runs. A variant that silently produces the wrong
# SHAPE would not be, so check the shape before trusting it. Every line must be
# "<depth> <key> <value>"; if any is not, throw the whole scan away.
if [ -n "$scan" ] && printf '%s\n' "$scan" | grep -qv '^-\{0,1\}[0-9][0-9]* [a-z_][a-z_]* .'; then
	scan=""
fi

# ------------------------------------------------------------- the decision
#
# $scan is `<depth> <key> <value>` lines. Read it with sed, not awk, so that a
# host with no awk fails in exactly one place (the scanner) and lands in the
# fallback below rather than half way through this block.

top_servers=$(printf '%s\n' "$scan" | sed -n 's/^1 mcp_server_name //p' | sort -u)
top_tools=$(printf '%s\n' "$scan" | sed -n 's/^1 tool_name //p' | sort -u)
top_command=$(printf '%s\n' "$scan" | sed -n 's/^1 command //p' | tr '\n' ' ')

# The scanner turns every separator inside `command` into an underscore, so
# put single spaces back before matching the "mcp serve <tier>" shape.
cmd_norm=$(printf '%s' "$top_command" | tr -c 'A-Za-z0-9-' ' ' | tr -s ' ')

n_top=0
for s in $top_servers; do
	n_top=$((n_top + 1))
done

if [ "$n_top" -gt 1 ]; then
	# Two DIFFERENT top-level values for the same key. No honest host sends
	# that. Do not try to pick one.
	ask "This MCP call carries more than one different top-level mcp_server_name. That is not a shape any host sends, so this guard cannot tell which RunOS server it targets. Read the tool name and the arguments before you approve."
fi

if [ "$n_top" -eq 1 ]; then
	kind=$(classify "$top_servers")

	# Cross-check against the launch command, which for a RunOS stdio server
	# carries "mcp serve <tier>". A payload that spoofs the name but not the
	# command, or the command but not the name, disagrees here. Match the
	# longer tier names first so "sensitive-write" is not read as "write".
	case "$cmd_norm" in
	*"mcp serve sensitive-write"*) cmd_kind=sensitive-write ;;
	*"mcp serve sensitive-read"*) cmd_kind=sensitive-read ;;
	*"mcp serve write"*) cmd_kind=write ;;
	*"mcp serve read"*) cmd_kind=read ;;
	*) cmd_kind="" ;;
	esac

	# The launch command is a second, independent signal, and the two are
	# used together rather than either alone.
	#
	#   name is a RunOS server, command names a DIFFERENT tier
	#       -> the two disagree, so neither can be trusted. Ask.
	#   name is not a RunOS server, command launches a NON-READ RunOS tier
	#       -> a renamed server reaching write or credential tools. Ask.
	#       The README says to keep the names exactly for this reason.
	#   name is not a RunOS server, command launches the READ tier
	#       -> a renamed read server. Not worth a prompt on every call.
	if [ -n "$cmd_kind" ] && [ "$kind" != other ] && [ "$cmd_kind" != "$kind" ]; then
		ask "This MCP call names one RunOS server but launches another. The mcp_server_name and the launch command disagree, so this guard cannot describe the risk. Read the tool name and the arguments before you approve."
	fi

	if [ "$kind" = other ]; then
		case "$cmd_kind" in
		sensitive-read | write | sensitive-write)
			ask "This MCP server is not named as a RunOS server, but it launches the RunOS $cmd_kind tier, so it can do everything that tier can. This guard cannot describe the risk under a name it does not know. Read the tool name and the arguments before you approve."
			;;
		esac
	fi

	case "$kind" in
	read)
		# Check EVERY top-level tool name, not just the first. A duplicate
		# top-level key is a malformed payload, and taking only the first
		# would let a benign name shadow a credential-shaped one.
		for t in $top_tools; do
			if tool_returns_secret "$t"; then
				# The scanner already reduced this to a safe charset.
				# Reduce again in case an awk variant handled the
				# character class differently: this value is
				# interpolated into JSON without escaping.
				ask_read_credential "$(printf '%s' "$t" | tr -cd 'A-Za-z0-9._-')"
			fi
		done
		allow
		;;
	other)
		# Not a RunOS server. Not this plugin's business.
		allow
		;;
	*)
		ask_for "$kind"
		;;
	esac
fi

# ------------------------------------------------------------- the fallback
#
# No top-level mcp_server_name. Either the scanner could not run, or the host
# sent a shape this build does not recognise. Do not trust a nested value as if
# it were the host's own field. Instead take the MOST RESTRICTIVE reading of
# every candidate in the payload, which is immune to field order: a spoofed
# extra key can only ADD a reason to ask, never remove one.

# These two extractions must not use awk: reaching here can mean awk is the
# thing that failed. sed, tr, sort and grep are POSIX-required too. Splitting
# on every brace and bracket puts each key on its own line; the match is NOT
# anchored, so a spoofed copy at any depth is COLLECTED rather than skipped,
# which is the whole point of taking the most restrictive reading.
flat=$(printf '%s' "$payload" | tr -d '\r\n' | tr ',{}[]' '\n\n\n\n\n')
all_servers=$(printf '%s\n' "$flat" |
	sed -n 's/.*"mcp_server_name"[[:space:]]*:[[:space:]]*.\{0,2\}"\([^"\\]*\)".*/\1/p' |
	tr -cd 'A-Za-z0-9._/@:+ -\n' | sort -u)
all_tools=$(printf '%s\n' "$flat" |
	sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*.\{0,2\}"\([^"\\]*\)".*/\1/p' |
	tr -cd 'A-Za-z0-9._- \n' | sort -u)

worst=other
for cand in $all_servers; do
	k=$(classify "$cand")
	case "$k" in
	sensitive-write) worst=sensitive-write ;;
	write) [ "$worst" = "sensitive-write" ] || worst=write ;;
	sensitive-read) case "$worst" in sensitive-write | write) ;; *) worst=sensitive-read ;; esac ;;
	unknown-runos) case "$worst" in other | read) worst=unknown-runos ;; esac ;;
	read) [ "$worst" = "other" ] && worst=read ;;
	esac
done

case "$worst" in
sensitive-read | write | sensitive-write | unknown-runos)
	ask_for "$worst"
	;;
read)
	for t in $all_tools; do
		if tool_returns_secret "$t"; then
			ask_read_credential "$(printf '%s' "$t" | tr -cd 'A-Za-z0-9._-')"
		fi
	done
	allow
	;;
esac

# Nothing in this payload names a RunOS server. Some other plugin's MCP call,
# or a shape this build does not understand. Allow: denying here would break
# every unrelated MCP server the user has installed.
allow
