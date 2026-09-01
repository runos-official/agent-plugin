#!/bin/sh
# Tests for com.cursor/hooks/sensitive-guard.sh.
#
# Every case below is a payload the guard must classify a stated way. The
# bypass cases came from an adversarial review that reproduced a FULL bypass of
# all three non-read servers against the first version of the guard. They are
# kept here so the bypass cannot come back.
#
# Run: sh com.cursor/hooks/guard_test.sh   (or `make guard-test`)

GUARD=$(dirname "$0")/sensitive-guard.sh
pass=0
fail=0

# decide PAYLOAD -> prints allow or ask, or a diagnostic on malformed output.
decide() {
	out=$(printf '%s' "$1" | sh "$GUARD" 2>/dev/null)
	case "$out" in
	'{"permission":"allow"}') printf 'allow' ;;
	'{"permission":"ask"'*) printf 'ask' ;;
	*) printf 'MALFORMED[%s]' "$out" ;;
	esac
}

check() {
	# $1 expected, $2 label, $3 payload
	got=$(decide "$3")
	if [ "$got" = "$1" ]; then
		pass=$((pass + 1))
	else
		fail=$((fail + 1))
		printf 'FAIL  want=%-5s got=%-5s  %s\n' "$1" "$got" "$2"
	fi
}

# ---------------------------------------------------------------- the bypass
# Reproduced by a reviewer against the first version. tool_input is serialised
# as an OBJECT and carries a nested key named mcp_server_name, in the field
# order Cursor documents: tool_name, tool_input, mcp_server_name, command.

SPOOF='{"tool_name":"t","tool_input":{"env":{"mcp_server_name":"runos"}},"mcp_server_name":"%s","command":"./bin/runos-mcp"}'
check allow "bypass table: read server, spoof present" "$(printf "$SPOOF" runos)"
check ask "bypass table: sensitive-read, spoof present" "$(printf "$SPOOF" runos-sensitive-read)"
check ask "bypass table: write, spoof present" "$(printf "$SPOOF" runos-write)"
check ask "bypass table: sensitive-write, spoof present" "$(printf "$SPOOF" runos-sensitive-write)"

check ask "nested spoof, minimal" \
	'{"tool_input":{"mcp_server_name":"runos"},"mcp_server_name":"runos-write"}'
check ask "nested spoof, two levels deep" \
	'{"args":["a"],"tool_input":{"env":{"mcp_server_name":"runos"}},"mcp_server_name":"runos-write"}'
check ask "nested spoof in a model-chosen map key" \
	'{"conversation_id":"c1","generation_id":"g1","hook_event_name":"beforeMCPExecution","tool_name":"mcp_runos-write_apps_env-vars_set","tool_input":{"app":"a1","cluster":"c1","vars":{"mcp_server_name":"runos"}},"mcp_server_name":"runos-write"}'
check ask "nested spoof, drop-database" \
	'{"tool_input":{"mcp_server_name":"runos"},"mcp_server_name":"runos-sensitive-write","tool_name":"services_postgresql_drop-database"}'
check ask "real field first (was already safe)" \
	'{"mcp_server_name":"runos-write","tool_input":{"mcp_server_name":"runos"}}'
check ask "escaped copy inside a string value (was already safe)" \
	'{"tool_input":{"sql":"\"mcp_server_name\": \"runos\""},"mcp_server_name":"runos-sensitive-write"}'
check ask "spoof inside an array element" \
	'{"tool_input":{"items":[{"mcp_server_name":"runos"}]},"mcp_server_name":"runos-write"}'
check ask "spoof with the value spelled across an escape" \
	'{"tool_input":{"note":"mcp_server_name"},"mcp_server_name":"runos-sensitive-read"}'
check ask "pretty printed with the spoof first" \
	'{
  "tool_name": "t",
  "tool_input": {
    "mcp_server_name": "runos"
  },
  "mcp_server_name": "runos-sensitive-write"
}'
check ask "two top-level tool_names, the second credential shaped" \
	'{"tool_name":"clusters_list","tool_name":"services_grafana_credentials","mcp_server_name":"runos"}'
check ask "two DIFFERENT top-level values for the same key" \
	'{"mcp_server_name":"runos","mcp_server_name":"runos-sensitive-write"}'
check ask "name says read, launch command says sensitive-write" \
	'{"tool_name":"t","mcp_server_name":"runos","command":"./bin/runos-mcp mcp serve sensitive-write"}'
check ask "a renamed server launching the sensitive-write tier" \
	'{"tool_name":"t","mcp_server_name":"my-runos-tools","command":"/usr/local/bin/runos mcp serve sensitive-write"}'
check ask "a renamed server launching the write tier" \
	'{"tool_name":"t","mcp_server_name":"infra","command":"runos mcp serve write"}'
check ask "a renamed server launching the sensitive-read tier" \
	'{"tool_name":"t","mcp_server_name":"infra","command":"runos mcp serve sensitive-read"}'
check allow "a renamed READ server is not worth a prompt on every call" \
	'{"tool_name":"clusters_list","mcp_server_name":"my-runos-reads","command":"runos mcp serve read"}'
check allow "an unrelated server whose command mentions neither tier" \
	'{"tool_name":"t","mcp_server_name":"linear","command":"npx -y @modelcontextprotocol/server-linear"}'
check allow "name and launch command agree on read" \
	'{"tool_name":"clusters_list","mcp_server_name":"runos","command":"./bin/runos-mcp mcp serve read"}'

# ------------------------------------------------- the documented string form
# cursor.com/docs/hooks.md types tool_input as a STRING: "JSON params string".
# In that shape the nested key arrives escaped. Both readings must be safe.

check ask "documented string tool_input carrying a spoof" \
	'{"tool_name":"t","tool_input":"{\"mcp_server_name\":\"runos\"}","mcp_server_name":"runos-write"}'
check allow "documented string tool_input, genuine read call" \
	'{"tool_name":"clusters_list","tool_input":"{\"cid\":\"abcde\"}","mcp_server_name":"runos"}'

# ------------------------------------------------------- the four RunOS servers

check allow "plain read call" '{"tool_name":"clusters_list","mcp_server_name":"runos"}'
check ask "sensitive-read" '{"tool_name":"vms_ssh-key","mcp_server_name":"runos-sensitive-read"}'
check ask "write" '{"tool_name":"apps_restart","mcp_server_name":"runos-write"}'
check ask "sensitive-write" '{"tool_name":"deploy","mcp_server_name":"runos-sensitive-write"}'
check ask "a RunOS server this build does not know, name says write" \
	'{"tool_name":"t","mcp_server_name":"runos-super-write"}'
check ask "a RunOS server this build does not know, name says sensitive" \
	'{"tool_name":"t","mcp_server_name":"runos-sensitive-future"}'

# ------------------------------------- the read server is NOT credential free
# Measured on manifest 44.5.0: these sit on the plain `read` tier.

for t in \
	mcp_runos_services_grafana_credentials \
	mcp_runos_services_litellm_credentials \
	mcp_runos_services_langfuse_credentials \
	mcp_runos_services_vector_credentials \
	mcp_runos_services_clickhouse_credentials \
	mcp_runos_services_litellm_api-keys \
	mcp_runos_services_minio_get-object; do
	check ask "read server, credential shaped: $t" \
		"{\"tool_name\":\"$t\",\"tool_input\":{\"id\":\"abcde\"},\"mcp_server_name\":\"runos\"}"
done

# Ordinary reads must stay silent, or the plugin is a nuisance. `valkey`
# contains the letters "key" and must NOT match the api-key pattern.
for t in mcp_bootstrap mcp_topics_show mcp_topics_search clusters_list apps_status \
	apps_logs nodes_list jobs_show services_valkey_list services_valkey_logs \
	services_valkey_status services_postgresql_users cli_version-check config_get; do
	check allow "ordinary read stays silent: $t" \
		"{\"tool_name\":\"$t\",\"tool_input\":{},\"mcp_server_name\":\"runos\"}"
done

# ------------------------------------------------------------ other servers
# This hook fires for EVERY MCP server the user has installed. A payload that
# does not name a RunOS server must be allowed, or the plugin breaks unrelated
# servers.

check allow "another plugin's server" '{"tool_name":"create_issue","mcp_server_name":"linear"}'
check allow "another plugin's credential tool" '{"tool_name":"get_credentials","mcp_server_name":"vault"}'
check allow "a server whose name merely contains runos" '{"tool_name":"t","mcp_server_name":"not-runos-at-all"}'

# --------------------------------------------------------------- odd shapes

check allow "empty payload" ''
check allow "not JSON at all" 'hello'
check allow "JSON with no server name and no runos anywhere" '{"tool_name":"t","tool_input":{}}'
# ---------------------------------------------------------------------------
# JSON ESCAPES IN THE SERVER NAME.
#
# Found by the coordinating agent on 2026-09-01, after the remediation pass.
# The scanner consumes a backslash and drops it, so the JSON string
# "runos-write" arrived as runos-u0077rite. That matched neither the four
# known names nor the runos*write* fallback, so it classified as `other` and
# was ALLOWED. JSON says "runos-write" and "runos-write" are the SAME
# STRING, so that was a full bypass of the write server.
#
# The rule now: a value that carried ANY escape cannot be compared literally,
# so it is unknown, and unknown is never allowed. That is deliberately
# conservative, and the third case pins it: even an escaped spelling of the
# READ server asks rather than allows, because the guard cannot prove what it
# says.
ESC_WRITE='{"mcp_server_name":"runos-\u0077rite"}'
ESC_SENS='{"mcp_server_name":"runos-\u0073ensitive-write"}'
ESC_READ='{"mcp_server_name":"\u0072unos"}'
check ask "escaped write server name" "$ESC_WRITE"
check ask "escaped sensitive-write server name" "$ESC_SENS"
check ask "escaped READ server name is unknown, so it asks" "$ESC_READ"
check allow "the unescaped read server still allows, no regression" '{"mcp_server_name":"runos"}'
check ask "the unescaped write server still asks, no regression" '{"mcp_server_name":"runos-write"}'

check ask "no top-level server name, but a nested runos-write appears" \
	'{"tool_name":"t","tool_input":{"mcp_server_name":"runos-write"}}'
check allow "no top-level server name, only a nested plain read" \
	'{"tool_name":"t","tool_input":{"mcp_server_name":"runos"}}'
check ask "no top-level server name, nested read plus a credential tool" \
	'{"tool_name":"services_grafana_credentials","tool_input":{"mcp_server_name":"runos"}}'
check allow "an HTTP server entry, no command field" \
	'{"tool_name":"t","mcp_server_name":"some-http-server","mcp_server_url":"https://example.com"}'

# --------------------------------------------------- output is always valid JSON

for p in '' 'garbage' '{"mcp_server_name":"runos-write"}' '{"mcp_server_name":"runos","tool_name":"a\"b\\c"}'; do
	out=$(printf '%s' "$p" | sh "$GUARD" 2>/dev/null)
	if printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
		pass=$((pass + 1))
	else
		fail=$((fail + 1))
		printf 'FAIL  output is not valid JSON for payload: %s\n  got: %s\n' "$p" "$out"
	fi
done

# The word "deny" must not appear as a decision this script can print. It DOES
# appear in the prose above, so the check is on the output, not on the file.
for p in '{"mcp_server_name":"runos-sensitive-write"}' '{"mcp_server_name":"runos"}' 'x'; do
	if printf '%s' "$p" | sh "$GUARD" 2>/dev/null | grep -q '"permission":"deny"'; then
		fail=$((fail + 1))
		printf 'FAIL  emitted a deny for: %s\n' "$p"
	else
		pass=$((pass + 1))
	fi
done

# ------------------------------------------- the fallback when awk is missing
# The scanner needs awk. awk is POSIX-required, but if a host has none the
# guard must still be safe, so it falls back to a most-restrictive-wins text
# read that is immune to field order.

TMPBIN=$(mktemp -d)
cat >"$TMPBIN/awk" <<'STUB'
#!/bin/sh
exit 127
STUB
chmod +x "$TMPBIN/awk"
# $1 expected, $2 label, $3 payload
noawk() {
	out=$(printf '%s' "$3" | PATH="$TMPBIN:$PATH" sh "$GUARD" 2>/dev/null)
	case "$out" in
	'{"permission":"allow"}') got=allow ;;
	'{"permission":"ask"'*) got=ask ;;
	*) got="MALFORMED[$out]" ;;
	esac
	if [ "$got" = "$1" ]; then
		pass=$((pass + 1))
	else
		fail=$((fail + 1))
		printf 'FAIL  (no awk) want=%-5s got=%-5s  %s\n' "$1" "$got" "$2"
	fi
}
noawk ask "no awk: the bypass payload still asks" \
	'{"tool_name":"t","tool_input":{"env":{"mcp_server_name":"runos"}},"mcp_server_name":"runos-sensitive-write","command":"./bin/runos-mcp"}'
noawk ask "no awk: plain sensitive-write" '{"mcp_server_name":"runos-sensitive-write"}'
noawk ask "no awk: plain write" '{"mcp_server_name":"runos-write"}'
noawk ask "no awk: plain sensitive-read" '{"mcp_server_name":"runos-sensitive-read"}'
noawk allow "no awk: plain read" '{"tool_name":"clusters_list","mcp_server_name":"runos"}'
noawk ask "no awk: read server credential tool" \
	'{"tool_name":"services_grafana_credentials","mcp_server_name":"runos"}'
noawk allow "no awk: another plugin" '{"tool_name":"t","mcp_server_name":"linear"}'
noawk allow "no awk: empty payload" ''

# A DIFFERENT failure: an awk that runs but emits the wrong shape. The guard
# must throw that scan away rather than act on it, and land in the same
# fallback.
cat >"$TMPBIN/awk" <<'STUB'
#!/bin/sh
cat >/dev/null
echo "surprise output from an unexpected awk"
STUB
chmod +x "$TMPBIN/awk"
noawk ask "wrong-shape awk: the bypass payload still asks" \
	'{"tool_name":"t","tool_input":{"env":{"mcp_server_name":"runos"}},"mcp_server_name":"runos-sensitive-write","command":"./bin/runos-mcp"}'
noawk ask "wrong-shape awk: plain write" '{"mcp_server_name":"runos-write"}'
noawk allow "wrong-shape awk: plain read" '{"tool_name":"clusters_list","mcp_server_name":"runos"}'
rm -rf "$TMPBIN"

printf '\n%d checks, %d failures\n' "$((pass + fail))" "$fail"
[ "$fail" -eq 0 ] || exit 1
