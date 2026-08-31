#!/usr/bin/env python3
"""Validate this plugin against the published Agent Plugins 1.0.0 schemas.

Two layers, because one of them is not enough.

LAYER 1: the published schemas, fetched from their canonical identifiers and
checked with the `jsonschema` library. This is the authority on the closed key
sets. If `jsonschema` is missing, the script builds a local virtualenv at
.venv/ and re-execs itself, so the same real validation runs on a developer's
machine and in CI. It never validates with a hand-rolled substitute, because a
home-made checker that passes is worse than no checker at all.

LAYER 2: the rules the specification states in prose and the schemas cannot
express. The spec text is authoritative where the two disagree (spec 7.2.1).
These are the rules that actually bite:

  * mcp.json's declared version MUST match plugin.json's (spec 10.1).
  * A stdio `command` MUST be a bare name or a "./" plugin-relative path, and a
    bundled executable MUST use the relative form (spec 7.2.1).
  * `${...}` in `env`, `args` or `cwd` is expanded for PLUGIN_ROOT and
    PLUGIN_DATA and NOTHING else (spec 9.2). Any other placeholder is passed
    through literally. Writing "${RUNOS_API_KEY}" in env would therefore set
    that variable to that same literal text rather than to a key, which is a
    broken credential rather than a missing one, and it would also override
    the real value inherited from the environment. This check exists to stop
    exactly that.
  * Skills live at skills/<name>/SKILL.md and are never discovered recursively.

Exit codes: 0 clean, 1 findings, 2 usage or environment error.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VENV = os.path.join(ROOT, ".venv")

PLUGIN_SCHEMA_URL = "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"
MCP_SCHEMA_URL = "https://agent-plugins.org/schemas/1.0.0/mcp.schema.json"

RESERVED_PLACEHOLDERS = {"PLUGIN_ROOT", "PLUGIN_DATA"}
PLACEHOLDER_RE = re.compile(r"\$\{([A-Za-z0-9_]+)\}")

ERRORS = []


def err(where: str, message: str) -> None:
    ERRORS.append("%s: %s" % (where, message))


def ensure_jsonschema():
    """Import jsonschema, building a local venv and re-execing if it is absent."""
    try:
        import jsonschema  # noqa: F401
        return
    except ImportError:
        pass

    venv_python = os.path.join(VENV, "bin", "python3")
    if os.name == "nt":
        venv_python = os.path.join(VENV, "Scripts", "python.exe")

    if os.path.abspath(sys.executable) == os.path.abspath(venv_python):
        sys.stderr.write("validate: jsonschema still missing inside %s\n" % VENV)
        sys.exit(2)

    # Build and populate the venv only when it is not already there. Without
    # this test the install ran on EVERY invocation, because the interpreter
    # that reaches this point is by definition the one without the library.
    if not os.path.exists(venv_python):
        sys.stderr.write("validate: building %s (one time)\n" % VENV)
        subprocess.check_call([sys.executable, "-m", "venv", VENV])
        sys.stderr.write("validate: installing jsonschema into %s\n" % VENV)
        subprocess.check_call(
            [venv_python, "-m", "pip", "install", "--quiet", "--disable-pip-version-check", "jsonschema"]
        )
    os.execv(venv_python, [venv_python, os.path.abspath(__file__)] + sys.argv[1:])


def fetch(url: str):
    with urllib.request.urlopen(url, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def load(path: str):
    full = os.path.join(ROOT, path)
    if not os.path.exists(full):
        err(path, "missing")
        return None
    try:
        with open(full, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except json.JSONDecodeError as exc:
        err(path, "is not valid JSON: %s" % exc)
        return None


def schema_check(name: str, document, schema) -> None:
    import jsonschema

    validator = jsonschema.Draft202012Validator(schema)
    for problem in sorted(validator.iter_errors(document), key=lambda e: list(e.path)):
        location = "/".join(str(p) for p in problem.path) or "<root>"
        err(name, "%s -> %s" % (location, problem.message))


def check_placeholders(name: str, where: str, text: str) -> None:
    for found in PLACEHOLDER_RE.findall(text):
        if found not in RESERVED_PLACEHOLDERS:
            err(
                name,
                "%s contains ${%s}. Clients expand ONLY ${PLUGIN_ROOT} and "
                "${PLUGIN_DATA} (spec 9.2), so this is passed through as "
                "literal text, not as the value of %s." % (where, found, found),
            )


def check_spec_rules(plugin, mcp) -> None:
    # 10.1 The two documents must target the same Agent Plugins version.
    if plugin and mcp:
        plugin_version = str(plugin.get("$schema", "")).split("/schemas/")[-1].split("/")[0]
        mcp_version = str(mcp.get("$schema", "")).split("/schemas/")[-1].split("/")[0]
        if plugin_version != mcp_version:
            err(
                "mcp.json",
                "targets Agent Plugins %s but plugin.json targets %s. A mismatch "
                "makes the MCP configuration invalid (spec 10.1)." % (mcp_version, plugin_version),
            )

    if not mcp:
        return

    for server_name, server in (mcp.get("mcpServers") or {}).items():
        label = "mcp.json[%s]" % server_name
        if server.get("type") != "stdio":
            continue

        command = server.get("command", "")
        # 7.2.1 A bare name or a "./" plugin-relative path, nothing else.
        if command.startswith("./"):
            target = os.path.join(ROOT, command[2:])
            if not os.path.isfile(target):
                err(label, "command %s does not exist in the package" % command)
            elif not os.access(target, os.X_OK):
                err(label, "command %s is not executable (chmod +x it)" % command)
        elif "/" in command or "\\" in command:
            err(
                label,
                "command %r is neither a bare executable name nor a './' "
                "plugin-relative path (spec 7.2.1)." % command,
            )

        for index, argument in enumerate(server.get("args") or []):
            check_placeholders(label, "args[%d]" % index, argument)
        for key, value in (server.get("env") or {}).items():
            check_placeholders(label, "env[%s]" % key, value)
        if "cwd" in server:
            check_placeholders(label, "cwd", server["cwd"])
            # 7.2.1 A ${PLUGIN_ROOT}-rooted value must stay inside the root.
            resolved = server["cwd"].replace("${PLUGIN_ROOT}", ROOT).replace("${PLUGIN_DATA}", ROOT)
            if os.path.relpath(os.path.normpath(resolved), ROOT).startswith(".."):
                err(label, "cwd %r escapes the plugin root" % server["cwd"])


def check_skills() -> None:
    """Skills are fixed at skills/<name>/SKILL.md and never found recursively."""
    skills_dir = os.path.join(ROOT, "skills")
    if not os.path.isdir(skills_dir):
        return
    for entry in sorted(os.listdir(skills_dir)):
        path = os.path.join(skills_dir, entry)
        if not os.path.isdir(path):
            if entry != ".gitkeep":
                err("skills/", "%s is a file. Skills must be directories." % entry)
            continue
        if not os.path.isfile(os.path.join(path, "SKILL.md")):
            err("skills/%s" % entry, "has no SKILL.md, so no client will discover it.")


def main() -> int:
    ensure_jsonschema()

    plugin = load("plugin.json")
    mcp = load("mcp.json")

    if plugin is not None:
        schema_check("plugin.json", plugin, fetch(PLUGIN_SCHEMA_URL))
    if mcp is not None:
        schema_check("mcp.json", mcp, fetch(MCP_SCHEMA_URL))

    check_spec_rules(plugin, mcp)
    check_skills()

    # The Cursor manifest has no published schema. Check only that it parses
    # and that every component path it names exists, which is the failure a
    # user would otherwise meet as a silently missing component.
    cursor = load(".cursor-plugin/plugin.json")
    if cursor is not None:
        for field in ("rules", "commands", "hooks", "skills", "agents"):
            value = cursor.get(field)
            for candidate in [value] if isinstance(value, str) else (value or []):
                if not os.path.exists(os.path.join(ROOT, candidate)):
                    err(".cursor-plugin/plugin.json", "%s -> %s does not exist" % (field, candidate))

    if ERRORS:
        sys.stderr.write("\nvalidate FAILED\n")
        for problem in ERRORS:
            sys.stderr.write("  %s\n" % problem)
        sys.stderr.write("\n")
        return 1

    print("validate: clean (Agent Plugins 1.0.0 schemas + specification rules)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
