# RunOS agent-plugin. This is a PUBLIC repo: every target below exists to keep
# it that way, or to prove the plugin manifests are valid.

GREEN := \033[0;32m
NC    := \033[0m

.DEFAULT_GOAL := help

# ============================================================================
# Leak gate (PUBLIC repo)
# ============================================================================

# Point git at the tracked hook directory. Run this once per clone.
.PHONY: hooks
hooks:
	@git config core.hooksPath .githooks
	@echo "$(GREEN)core.hooksPath = .githooks$(NC) (pre-commit now runs leakcheck on the staged diff)"

# Scan every tracked file for credentials and un-baselined internal identifiers.
.PHONY: leakcheck
leakcheck:
	@python3 scripts/leakcheck.py

# Scan only the staged diff, the same way the pre-commit hook does.
.PHONY: leakcheck-staged
leakcheck-staged:
	@python3 scripts/leakcheck.py --staged

# Ratchet the baseline down after you REMOVE an identifier from the source.
# Never run this to get a new identifier past the gate.
.PHONY: leakcheck-update
leakcheck-update:
	@python3 scripts/leakcheck.py --update

# Test the checker itself: what it must catch and what it must not.
.PHONY: leakcheck-test
leakcheck-test:
	@python3 scripts/leakcheck_test.py

# Fail on a tracked file leakcheck cannot READ. leakcheck silently skips any
# file holding a NUL byte or non-UTF-8 bytes, so a credential in a binary or a
# UTF-16 file passes it with exit 0. That gap belongs to the CLI repo, which
# owns the shared checker, so this closes it here without forking the file.
.PHONY: unscannable
unscannable:
	@python3 scripts/unscannable_check.py

# ============================================================================
# Manifests
# ============================================================================

# Validate plugin.json and mcp.json against the published Agent Plugins 1.0.0
# schemas. Downloads the schemas, so it needs a network. CI runs the same
# script.
.PHONY: validate
validate:
	@python3 scripts/validate_manifests.py

# ============================================================================
# Hooks (Cursor)
# ============================================================================

# Test the beforeMCPExecution guard. Includes every payload from the review
# that reproduced a full bypass of all three non-read servers.
.PHONY: guard-test
guard-test:
	@sh com.cursor/hooks/guard_test.sh

# Test the sessionStart probe against a sandbox HOME and PATH.
.PHONY: hook-test
hook-test:
	@sh com.cursor/hooks/binary_check_test.sh

# ============================================================================
# Everything a push must pass
# ============================================================================

.PHONY: check
check: leakcheck unscannable leakcheck-test validate guard-test hook-test

.PHONY: help
help:
	@echo "RunOS agent-plugin"
	@echo ""
	@echo "  make hooks            Point git at .githooks (run once per clone)"
	@echo "  make leakcheck        Scan every tracked file for leaks (PUBLIC repo gate)"
	@echo "  make leakcheck-staged Scan only the staged diff"
	@echo "  make leakcheck-update Ratchet the baseline down after removing an identifier"
	@echo "  make leakcheck-test   Test the leak checker itself"
	@echo "  make unscannable      Fail on a tracked file leakcheck cannot read"
	@echo ""
	@echo "  make guard-test       Test the beforeMCPExecution guard"
	@echo "  make hook-test        Test the sessionStart probe"
	@echo ""
	@echo "  make validate         Validate both manifests against Agent Plugins 1.0.0"
	@echo "  make check            everything above"
