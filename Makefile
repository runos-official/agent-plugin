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
# Everything a push must pass
# ============================================================================

.PHONY: check
check: leakcheck leakcheck-test validate

.PHONY: help
help:
	@echo "RunOS agent-plugin"
	@echo ""
	@echo "  make hooks            Point git at .githooks (run once per clone)"
	@echo "  make leakcheck        Scan every tracked file for leaks (PUBLIC repo gate)"
	@echo "  make leakcheck-staged Scan only the staged diff"
	@echo "  make leakcheck-update Ratchet the baseline down after removing an identifier"
	@echo "  make leakcheck-test   Test the leak checker itself"
	@echo ""
	@echo "  make validate         Validate both manifests against Agent Plugins 1.0.0"
	@echo "  make check            leakcheck + leakcheck-test + validate"
