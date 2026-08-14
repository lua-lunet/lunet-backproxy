# Lunet Version Pinning Policy

## TL;DR

- **Always pin to a release tag** (currently `v0.9.2`) for stability and reproducibility.
- The pinned release is installed by a **vendored fetcher**, `scripts/lunet_fetch_release_v0.9.2.lua`, whose SHA-256 digests are verified against the GitHub release metadata before extraction.
- The repo **never clones or compiles Lunet**. Commit-hash testing happens outside the repo (see "Verified binaries vs custom builds").

## Why Release Tags?

Release tags are **stable, immutable, and guaranteed to work**:
- ✅ Releases are tested by the Lunet maintainers
- ✅ Release assets carry digests in GitHub release metadata; the fetcher verifies the SHA-256 of every artifact **before extraction** and fails closed on mismatch
- ✅ Everyone uses identical, well-tested code
- ✅ Changes are documented in release notes
- ❌ Commits may be unstable, rebased, or deleted

## Current Setup

**Pinned version**: `v0.9.2`
**Fetcher**: `scripts/lunet_fetch_release_v0.9.2.lua` (vendored in the repo)
**Install layout**: `.lunet/v0.9.2/`

```
.lunet/v0.9.2/
├── lunet-run        # runtime binary (the LUNET_BIN default)
├── lunet.so         # core C module
├── lunet/           # extension C modules (*.so, e.g. sqlite3.so)
└── types/           # type stubs / docs shipped with the release
```

Fetcher guarantees:

- **Verified**: SHA-256 of each downloaded asset is checked against the GitHub release metadata before anything is extracted; any mismatch aborts the install.
- **Fail-closed**: a partial or corrupt install is never left usable.
- **Atomic**: extraction lands in a staging area and is moved into place only on success.
- **Idempotent**: a valid existing `.lunet/v0.9.2/` install is reused without any network access.

Runtime binary path: `.lunet/v0.9.2/lunet-run`.

Supported xmake entry points in this repo:

```bash
xmake run setup-lunet   # fetch/install the pinned release (idempotent)
xmake run run-dmz
xmake run run-internal
xmake run run-echo
xmake run stress-e2e
xmake run stress-compare
xmake test              # optional gating: ENABLE_CONDUIT_DEMO=0 xmake test
```

## How to Upgrade

A version bump means **vendoring the new release's fetcher** — the repo stays free of any clone/compile machinery.

### Check for new releases

```bash
# Visit: https://github.com/lua-lunet/lunet/releases
# Or use gh CLI:
gh release list --repo lua-lunet/lunet
```

### Perform the upgrade

1. Copy the new release's `lunet_fetch_release_<tag>.lua` into `scripts/`
   (e.g. `scripts/lunet_fetch_release_v0.9.3.lua`).
2. Update the scripts that reference the tag/install path
   (`scripts/lunet-env.sh`, `scripts/setup-lunet.sh`, and any CI wiring) to the new tag.
3. Remove the old install: `rm -rf .lunet/<old-tag>` (e.g. `rm -rf .lunet/v0.9.2`).
4. `xmake run setup-lunet` to fetch and verify the new release.
5. `xmake test` to validate.

## Verified binaries vs custom builds

### Verified fetcher binaries (the only default path)

```bash
xmake run setup-lunet
```
- ✅ Digest-verified release assets (SHA-256 checked before extraction)
- ✅ Fast and idempotent: valid installs are reused without network access
- ✅ Simple: no compiler, no clone, no build tree in this repo

### Custom builds (developer override only)

When you need an unreleased fix, instrumentation, or custom flags, **build upstream Lunet yourself** following its [XMAKE_INTEGRATION.md](https://github.com/lua-lunet/lunet/blob/main/docs/XMAKE_INTEGRATION.md), then point the repo at your binary:

```bash
export LUNET_BIN=/path/to/your/build/lunet-run
xmake test
```

The repo itself never clones or compiles Lunet; `LUNET_BIN` is the single override consumed by `scripts/lunet-env.sh`, the xmake tasks, and all run/test scripts. Always record the exact upstream commit and build flags you used, and return to the pinned release once done.

## For Developers

### Override for a custom build

```bash
# Use your custom Lunet build
export LUNET_BIN=/path/to/my/lunet-run
xmake test

# Use an instrumented build (e.g. ASan)
export LUNET_BIN=/opt/lunet-asan/bin/lunet-run
xmake test

# Compare baseline vs instrumented performance
INSTRUMENTED_LUNET_BIN=/opt/lunet-asan/bin/lunet-run xmake run stress-compare
```

### Temporarily test a different release

Fetch another release with its own fetcher into a scratch dir (or build it yourself) and override:

```bash
export LUNET_BIN=/scratch/.lunet/vX.Y.Z/lunet-run
xmake test

# Remember to switch back:
unset LUNET_BIN
```

## CI/CD Best Practices

Pinning lives entirely in the repo's scripts: the vendored fetcher file (`scripts/lunet_fetch_release_<tag>.lua`) plus `scripts/lunet-env.sh`. Workflows only invoke entry points:

**In .github/workflows/test.yml**:

```yaml
- name: Setup Lunet
  run: xmake run setup-lunet

- name: Run tests
  run: xmake test
```

Never hardcode Lunet versions or download URLs in workflows — upgrading is a fetcher-swap commit (see "How to Upgrade").

## Future Lunet Updates

When new Lunet versions are released:

1. **Read release notes** at https://github.com/lua-lunet/lunet/releases
2. **Vendor the new fetcher**: copy the release's `lunet_fetch_release_<tag>.lua` into `scripts/`
3. **Test locally** with the new release:
   ```bash
   xmake run setup-lunet   # fetches into .lunet/<new-tag>
   xmake test
   ```
4. **If all pass**, update `scripts/lunet-env.sh` / setup wiring to the new tag and `rm -rf .lunet/<old-tag>`
5. **Commit** with message: `"Upgrade Lunet to vX.Y.Z"` and monitor for issues

---

This policy ensures lunet-backproxy is always built with a well-tested, digest-verified Lunet release while remaining flexible for debugging and testing.

## Advanced: Instrumented Builds (Optional)

For development, consider running Lunet with instrumentation (ASan, trace, etc.). Build it yourself per [Lunet XMAKE_INTEGRATION.md](https://github.com/lua-lunet/lunet/blob/main/docs/XMAKE_INTEGRATION.md) — this repo contains no build steps for Lunet itself — then use the `LUNET_BIN` override:

```bash
# Point the repo at your instrumented build
export LUNET_BIN=/path/to/lunet/build/release/lunet-run
xmake test
```

**Key insight**: Instrumentation adds <10% overhead on many workloads, making it worthwhile for development and QA. Final release testing should use the digest-verified release install (unset `LUNET_BIN`).
