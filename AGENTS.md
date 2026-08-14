# AGENTS.md

Guidance for AI agents working on this Lua project.

## Technology Stack

This is a **Lua-only project** using **xmake** for build automation.

## Build And Runtime Policy

This repository is pinned to **Lunet release tag `v0.9.2`** and must not depend on ad-hoc local Lunet trees.

- Primary setup command:
  ```bash
  xmake run setup-lunet
  ```
- Compatibility alias:
  ```bash
  xmake run build-lunet
  ```

Runtime bootstrap rules:
- Use `scripts/setup-lunet.sh` and `scripts/lunet-env.sh`.
- **Best practice**: Pin to a Lunet release tag (e.g., `v0.9.2`) for stability and reproducibility.
- Commit hashes should only be used when testing a specific fix or unreleased feature; always upgrade to the nearest release tag. Commit-hash testing means building upstream Lunet yourself and pointing `LUNET_BIN` at the result — this repo never clones or compiles Lunet.
- Instrumented or custom Lunet builds are used by exporting `LUNET_BIN=/path/to/lunet-run` (plus `LUA_CPATH` if the custom layout needs it); `stress-compare` uses `INSTRUMENTED_LUNET_BIN`.
- The installed runtime path `.lunet/v0.9.2/lunet-run` self-resolves its Lua/C modules (no `LUA_CPATH` needed for the fetched runtime).
- Default acquisition is the vendored, SHA-256-verified release fetcher (`scripts/lunet_fetch_release_v0.9.2.lua`) installing into `.lunet/v0.9.2/`; there is no repo-local compilation of Lunet.
- Typed-Lua support is consumed via `.lunet/v0.9.2/types/` (LuaCATS + Teal declarations) for editor/type checking only; do not convert app code to Teal without an explicit decision.
- Do not rely on `../lunet` sibling checkouts or unpublished local Lunet changes.
- Canonical Lunet xmake/instrumentation docs are upstream: https://github.com/lua-lunet/lunet/blob/main/docs/XMAKE_INTEGRATION.md

Supported xmake entry points in this repo:
- `xmake run setup-lunet`
- `xmake run run-dmz`
- `xmake run run-internal`
- `xmake run run-echo`
- `xmake run stress-e2e`
- `xmake run stress-compare`
- `xmake test`
- Optional conduit integration gating for tests: `ENABLE_CONDUIT_DEMO=0 xmake test`

When debugging runtime-level issues:
- Instrumentation must remain optional.
- For baseline performance, run with non-instrumented runtime (release profile).
- For diagnostics, run with instrumented runtime (trace/ASan) and compare overhead explicitly (`xmake run stress-compare`).
- If zero-cost tracing is needed, use a source build of Lunet with its xmake trace/ASan options enabled, and document the exact flags and commit used.
- Do not switch the project to random local Lunet revisions.

## Architecture And Security Policy

Follow the Unix way and QMail security model:

- Keep `lunet-backproxy` focused on one job: high-speed request brokering over outbound worker tunnels.
- Preserve strict process separation between edge security components and backproxy runtime.
- Do not add perimeter security features to backproxy if dedicated components already solve them.

Perimeter and attack-handling concerns must be handled by dedicated fronting software (OpenResty/NGINX/WAF and related tooling), including:

- TLS termination and certificate lifecycle
- DDoS/flood handling and connection abuse controls
- slow-client mitigation, throttling, and rate limiting
- edge authentication/access controls
- CVE-driven hardening and patch cadence

Backproxy must remain barebones, fast, and libuv-focused. It is not the TLS/security gateway.

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
