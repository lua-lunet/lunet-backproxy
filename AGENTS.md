# AGENTS.md

Guidance for AI agents working on this Lua project.

## Technology Stack

This is a **Lua-only project** using **xmake** for build automation.

**Mandated technologies:**
- Lua 5.1+ (embedded in Lunet)
- Lunet (networking runtime)
- SQLite (via lunet-sqlite3)
- xmake (build system)
- NGINX (TLS termination, external)
- Shell scripts (for development workflows)

**Forbidden technologies:**
- Python, Node.js, Go, Rust, or any other language
- External build systems beyond xmake
- Third-party testing frameworks (use Lua + Lunet only)
- Any tool not already in the repository

## Testing

All testing must be done in **Lua** using the xmake test task:
```bash
xmake test
```

For load testing, write shell scripts with `curl` and `timeout`. Do not introduce Python, Lua libraries not in the repo, or external tools.

## Shell Commands

Development scripts must use:
- Standard POSIX shell (bash)
- `curl` for HTTP testing
- `timeout` or `gtimeout` for timeout handling
- `jq` for JSON parsing (already used in existing scripts)
- No Python, no external package managers

## Adding Dependencies

Before adding any new tool, library, or language:
1. Check if it can be done in pure Lua
2. Check if xmake can build/integrate it
3. If not Lua/xmake, do not add it
4. Document in this file

## Code Standards

- Lua only
- Follow existing module pattern (local M = {}, return M)
- No external Lua libraries beyond what's already present
- Build integration via xmake tasks, not makefiles or other systems
