---
description: Check that this session can actually talk to RunOS, and report what is missing.
---

Establish whether RunOS is usable in this session, then report. Do not change anything.

1. Call `mcp_bootstrap`. If it refuses, stop here and read the credential
   failures below. Say nothing else, and do not retry.
2. Call `mcp_topics_show` once, with an exact key from the bootstrap index. This is
   the second of the two documents the read server requires before it answers
   anything else. A `mcp_topics_search` does not count towards that.
3. Call `cli_version-check`. Tell me if my CLI is behind.
4. Call `manifest_update` and tell me the manifest version it reports. I need to
   know whether I am on 45.0.0 or later, because before that the plain read
   server still returns real credentials for Grafana, LiteLLM, Langfuse, Vector
   and ClickHouse.
5. Call `config_get` and tell me which environment and which account this session is
   pointed at. Read it back to me before I ask you to do anything that writes.
6. Call `clusters_list` and name the clusters I can reach.

## The credential failures

Measured against the live CLI. Any of these means the same fix.

- `authentication required: run 'runos login' first`. The sign-in is expired,
  revoked or absent.
- a JSON error carrying `"statusCode": 401` and `"error": "Invalid token"`. The
  API key or the token was rejected.
- No RunOS tool exists at all. With no credential the servers exit before they
  speak MCP.

Tell me to run `runos login` in my terminal and reload the window. Do not retry.
On a background agent the route is an account API key in `RUNOS_API_KEY`
instead, and if that variable is set but EMPTY the CLI refuses it outright.

## Then report, in this order

- signed in, or not, and the exact fix if not
- the manifest version, and whether it is 45.0.0 or later
- the environment and account this session is pointed at
- the clusters available
- which RunOS MCP servers you can actually see in this session

This plugin declares only the `runos` read server. If you can see
`runos-write`, `runos-sensitive-read` or `runos-sensitive-write`, somebody added
them by hand, so name them: `runos-sensitive-write` carries `deploy` and
`storage-groups_wipe-device`. If a server is absent, say so plainly rather than
working around it.
