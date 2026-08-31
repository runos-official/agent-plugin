---
description: Check that this session can actually talk to RunOS, and report what is missing.
---

Establish whether RunOS is usable in this session, then report. Do not change anything.

1. Call `mcp_bootstrap`. If it answers `not authenticated`, stop here and tell me to
   run `runos login` in my terminal. Say nothing else, and do not retry.
2. Call `mcp_topics_show` once, with an exact key from the bootstrap index. This is
   the second of the two documents the read server requires before it answers
   anything else. A `mcp_topics_search` does not count towards that.
3. Call `cli_version-check`. Tell me if my CLI is behind.
4. Call `config_get` and tell me which environment and which account this session is
   pointed at. Read it back to me before I ask you to do anything that writes.
5. Call `clusters_list` and name the clusters I can reach.

Then report, in this order:

- signed in, or not, and the exact fix if not
- the environment and account this session is pointed at
- the clusters available
- which RunOS MCP servers are enabled here, and which are not

Only the read server is enabled after this plugin is installed. If a write server is
off, say so plainly rather than working around it. I turn it on in Cursor's Customize
panel when I want it.
