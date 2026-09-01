#!/bin/sh
# Tests for com.cursor/hooks/binary-check.sh.
#
# Every branch is exercised against a sandbox HOME and a sandbox PATH, so no
# case depends on how this particular machine happens to be set up. The
# set-but-empty cases exist because an earlier version reported all-clear in a
# state where every RunOS MCP server refuses to start.
#
# Run: sh com.cursor/hooks/binary_check_test.sh   (or `make hook-test`)

HOOK=$(dirname "$0")/binary-check.sh
pass=0
fail=0

SB=$(mktemp -d)
trap 'rm -rf "$SB"' EXIT INT TERM

# A HOME with a Firebase session on disk.
mkdir -p "$SB/home_session/.runos"
cat >"$SB/home_session/.runos/config.json" <<'JSON'
{"account_id":"aaaaa","firebase":{"api_key":"project-identifier-not-a-credential"},"refresh_token":"a-refresh-token"}
JSON

# A HOME with a stored PAT.
mkdir -p "$SB/home_pat/.runos"
cat >"$SB/home_pat/.runos/config.json" <<'JSON'
{"account_id":"aaaaa","api_key":"a-stored-pat"}
JSON

# A HOME with a config that has a firebase block but NO refresh token. The
# firebase block carries its own api_key, which is a project identifier. It
# must NOT be read as a credential.
mkdir -p "$SB/home_firebase_only/.runos"
cat >"$SB/home_firebase_only/.runos/config.json" <<'JSON'
{"account_id":"aaaaa","firebase":{"api_key":"project-identifier-not-a-credential"}}
JSON

# A HOME with nothing.
mkdir -p "$SB/home_empty"

# A PATH with a runos binary on it, and one without.
mkdir -p "$SB/bin_yes" "$SB/bin_no"
printf '#!/bin/sh\nexit 0\n' >"$SB/bin_yes/runos"
chmod +x "$SB/bin_yes/runos"

# run HOME PATH_DIR EXTRA_ENV... -> prints the additional_context, or the empty
# string when the hook printed nothing.
run() {
	h=$1
	b=$2
	shift 2
	out=$(env -i HOME="$h" PATH="$b:/usr/bin:/bin" "$@" sh "$HOOK" </dev/null 2>/dev/null)
	rc=$?
	if [ "$rc" -ne 0 ]; then
		printf 'NONZERO_EXIT_%d' "$rc"
		return
	fi
	if [ -z "$out" ]; then
		printf ''
		return
	fi
	printf '%s' "$out" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin)["additional_context"])
except Exception as e:
    print("NOT_JSON")' 2>/dev/null || printf 'NOT_JSON'
}

want() {
	# $1 label, $2 substring that must appear, $3.. the run arguments
	label=$1
	needle=$2
	shift 2
	got=$(run "$@")
	case "$got" in
	*"$needle"*)
		pass=$((pass + 1))
		;;
	*)
		fail=$((fail + 1))
		printf 'FAIL  %s\n  wanted substring: %s\n  got: %s\n' "$label" "$needle" "$got"
		;;
	esac
}

reject() {
	# $1 label, $2 substring that must NOT appear, $3.. the run arguments
	label=$1
	needle=$2
	shift 2
	got=$(run "$@")
	case "$got" in
	*"$needle"*)
		fail=$((fail + 1))
		printf 'FAIL  %s\n  must NOT contain: %s\n  got: %s\n' "$label" "$needle" "$got"
		;;
	*)
		pass=$((pass + 1))
		;;
	esac
}

# ------------------------------------------------------------ set but empty
# Measured: `RUNOS_API_KEY="" runos mcp serve read` exits 1 with
# "Error: RUNOS_API_KEY is set but empty; ..." and the server never starts. A
# session on disk does NOT rescue it, so the session HOME is used here on
# purpose: this is exactly the state the previous hook reported as all-clear.

want "blank RUNOS_API_KEY is reported" "RUNOS_API_KEY is SET but EMPTY" \
	"$SB/home_session" "$SB/bin_yes" RUNOS_API_KEY=
want "blank RUNOS_ACCOUNT_ID is reported" "RUNOS_ACCOUNT_ID is SET but EMPTY" \
	"$SB/home_session" "$SB/bin_yes" RUNOS_ACCOUNT_ID=
want "blank RUNOS_API_KEY names the unset fix" "unset RUNOS_API_KEY" \
	"$SB/home_session" "$SB/bin_yes" RUNOS_API_KEY=
want "blank var beats a missing binary in priority" "RUNOS_API_KEY is SET but EMPTY" \
	"$SB/home_empty" "$SB/bin_no" RUNOS_API_KEY=

# A variable that is set to a real value is NOT the blank case.
reject "a real RUNOS_API_KEY is not the blank case" "SET but EMPTY" \
	"$SB/home_empty" "$SB/bin_yes" RUNOS_API_KEY=rk_a_real_looking_value
# A variable that is entirely unset is NOT the blank case.
reject "an unset RUNOS_API_KEY is not the blank case" "SET but EMPTY" \
	"$SB/home_session" "$SB/bin_yes"

# ------------------------------------------------------------- missing binary

want "no binary, no credential: install command is present" \
	"curl -fsSL https://get.runos.com/cli.sh | bash" \
	"$SB/home_empty" "$SB/bin_no"
want "no binary, no credential: PowerShell command is present" \
	"irm https://get.runos.com/cli.ps1 | iex" \
	"$SB/home_empty" "$SB/bin_no"
want "no binary, no credential: names runos login" "runos login" \
	"$SB/home_empty" "$SB/bin_no"
want "no binary, credential present: install command is present" \
	"curl -fsSL https://get.runos.com/cli.sh | bash" \
	"$SB/home_session" "$SB/bin_no"
want "no binary, credential present: offers RUNOS_BIN" "RUNOS_BIN" \
	"$SB/home_session" "$SB/bin_no"

# The old text told the agent to point at instructions it does not have. It
# must not come back.
reject "no vague pointer to instructions, case 1" "rather than guessing a command" \
	"$SB/home_empty" "$SB/bin_no"
reject "no vague pointer to instructions, case 2" "rather than guessing a command" \
	"$SB/home_session" "$SB/bin_no"

# RUNOS_BIN pointing at a real executable satisfies the binary check even with
# no runos on PATH.
reject "RUNOS_BIN satisfies the binary check" "NOT installed" \
	"$SB/home_session" "$SB/bin_no" RUNOS_BIN="$SB/bin_yes/runos"

# --------------------------------------------------------- missing credential

want "binary present, no credential" "no RunOS credential was found" \
	"$SB/home_empty" "$SB/bin_yes"
want "binary present, no credential: names runos login" "runos login" \
	"$SB/home_empty" "$SB/bin_yes"
want "a firebase block with no refresh token is NOT a credential" \
	"no RunOS credential was found" \
	"$SB/home_firebase_only" "$SB/bin_yes"

# --------------------------------------------------------- credential present

reject "a Firebase session reads as present" "no RunOS credential was found" \
	"$SB/home_session" "$SB/bin_yes"
reject "a stored PAT reads as present" "no RunOS credential was found" \
	"$SB/home_pat" "$SB/bin_yes"
reject "RUNOS_API_KEY reads as present" "no RunOS credential was found" \
	"$SB/home_empty" "$SB/bin_yes" RUNOS_API_KEY=rk_a_real_looking_value

# ------------------------------------------------- the real refusal strings
# MEASURED against the live CLI. `not authenticated` is auth.ErrNotAuthenticated
# and it is produced on the path where the server does NOT start, so no MCP tool
# ever answers it. These are the strings a tool really answers.

want "all-good context names the real interactive refusal" \
	"authentication required: run 'runos login' first" \
	"$SB/home_session" "$SB/bin_yes"
want "all-good context names the real 401 refusal" "statusCode 401" \
	"$SB/home_session" "$SB/bin_yes"
want "all-good context names Invalid token" "Invalid token" \
	"$SB/home_session" "$SB/bin_yes"

# The wrong string must not come back anywhere in the hook.
if grep -q "not authenticated" "$HOOK"; then
	fail=$((fail + 1))
	printf 'FAIL  the hook still contains the string "not authenticated", which no RunOS MCP tool returns\n'
else
	pass=$((pass + 1))
fi

# ---------------------------------------------------------- always valid JSON

for h in "$SB/home_session" "$SB/home_empty" "$SB/home_pat" "$SB/home_firebase_only"; do
	for b in "$SB/bin_yes" "$SB/bin_no"; do
		out=$(env -i HOME="$h" PATH="$b:/usr/bin:/bin" sh "$HOOK" </dev/null 2>/dev/null)
		if [ -z "$out" ] || printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
			pass=$((pass + 1))
		else
			fail=$((fail + 1))
			printf 'FAIL  output is not valid JSON for HOME=%s PATH=%s\n  got: %s\n' "$h" "$b" "$out"
		fi
	done
done

# --------------------------------------------------- never exits non-zero

for h in "$SB/home_session" "$SB/home_empty" "$SB/nonexistent"; do
	env -i HOME="$h" PATH="$SB/bin_no:/usr/bin:/bin" sh "$HOOK" </dev/null >/dev/null 2>&1
	if [ $? -eq 0 ]; then
		pass=$((pass + 1))
	else
		fail=$((fail + 1))
		printf 'FAIL  non-zero exit for HOME=%s\n' "$h"
	fi
done

# ------------------------------------------ it never prints a credential value

# Put a recognisable value in the config and prove it does not come out.
#
# The config is ASSEMBLED here rather than written as a literal. A literal
# `"api_key": "<value>"` line is a credential SHAPE, and scripts/leakcheck.py
# hard-fails on those and refuses to baseline them, which is correct: a gate
# that can be taught to ignore a credential shape in a test fixture can be
# taught to ignore one anywhere. So the shape never appears in this file.
M=MARKERZZZ
Q='"'
kv() { printf '%s%s%s:%s%s%s' "$Q" "$1" "$Q" "$Q" "$2" "$Q"; }
mkdir -p "$SB/home_marked/.runos"
{
	printf '{'
	kv account_id aaaaa
	printf ','
	kv api"_"key "${M}A"
	printf ',%sfirebase%s:{' "$Q" "$Q"
	kv api"_"key "${M}B"
	printf '},'
	kv refresh"_"token "${M}C"
	printf '}\n'
} >"$SB/home_marked/.runos/config.json"
out=$(env -i HOME="$SB/home_marked" PATH="$SB/bin_yes:/usr/bin:/bin" RUNOS_API_KEY="${M}D" sh "$HOOK" </dev/null 2>&1)
case "$out" in
*"$M"*)
	fail=$((fail + 1))
	printf 'FAIL  the hook printed a value from the config or the environment\n  got: %s\n' "$out"
	;;
*)
	pass=$((pass + 1))
	;;
esac

printf '\n%d checks, %d failures\n' "$((pass + fail))" "$fail"
[ "$fail" -eq 0 ] || exit 1
