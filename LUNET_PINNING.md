# Lunet Version Pinning Policy

## TL;DR

- **Always pin to a release tag** (e.g., `v0.1.2`) for stability and reproducibility
- Commit hashes should only be used when testing a specific unreleased fix
- Always upgrade to the nearest release tag once testing is complete

## Why Release Tags?

Release tags are **stable, immutable, and guaranteed to work**:
- ✅ Releases are tested by the Lunet maintainers
- ✅ Prebuilt binaries are available (faster setup)
- ✅ Everyone uses identical, well-tested code
- ✅ Changes are documented in release notes
- ❌ Commits may be unstable, rebased, or deleted

## When to Use Commits

Only use a commit hash when:
1. Testing a specific bug fix not yet in a release
2. Verifying a PR before merge
3. Investigating a regression

**Always** upgrade to the nearest release tag when done.

```bash
# Temporary: test a specific commit
export LUNET_REF=abc123def456
xmake test

# Once satisfied, pin to release tag
# Edit scripts/lunet-env.sh: v0.1.2
git commit -am "Upgrade Lunet to v0.1.2"
```

## Current Setup

**Pinned Version**: `v0.1.2`
**Location**: `scripts/lunet-env.sh` line 5
**Status**: Using prebuilt binary (fast setup)

```bash
PINNED_LUNET_REF_DEFAULT="v0.1.2"
```

## How to Upgrade

### Check for new releases
```bash
# Visit: https://github.com/lua-lunet/lunet/releases
# Or use gh CLI:
gh release list --repo lua-lunet/lunet
```

### Update pinning
```bash
# Edit scripts/lunet-env.sh
PINNED_LUNET_REF_DEFAULT="v0.1.3"  # New tag

# Clean old build
rm -rf .tmp/src/lunet-* .tmp/runtime/lunet-*

# Build and test
xmake test
```

## Prebuilt vs Source Build

### Release Tags (Prebuilt Available)
```bash
LUNET_REF=v0.1.2
```
- ✅ Fast: Downloads .tar.gz
- ✅ Small: ~20-50MB
- ✅ Simple: No build required

### Commits (Source Build Required)
```bash
LUNET_REF=abc123def456  # Or branch name
```
- ❌ Slow: 2-5 minute compile
- ❌ Large: Full source + build artifacts
- ✅ Flexible: Supports unreleased code
- ✅ Supports: Custom compiler flags

## For Developers

### Override for Custom Build
```bash
# Use your custom Lunet build
export LUNET_BIN=/path/to/my/lunet
xmake test

# Use instrumented version
export LUNET_BIN=/opt/lunet-asan/bin/lunet
xmake test
```

### Temporarily Test Different Version
```bash
# Test v0.1.1 without changing pinning
export LUNET_REF=v0.1.1
export LUNET_USE_PREBUILT=1
xmake run setup-lunet
xmake test

# Remember to switch back:
unset LUNET_REF LUNET_USE_PREBUILT
```

## CI/CD Best Practices

**In .github/workflows/test.yml**:
```yaml
- name: Setup Lunet
  run: xmake run setup-lunet
  # Uses PINNED_LUNET_REF_DEFAULT from scripts/lunet-env.sh

- name: Run tests
  run: xmake test
```

Always let the pinning in `scripts/lunet-env.sh` drive CI/CD - don't hardcode versions in workflows.

## Future Lunet Updates

When new Lunet versions are released:

1. **Read release notes** at https://github.com/lua-lunet/lunet/releases
2. **Test locally** with new version:
   ```bash
   export LUNET_REF=vX.Y.Z
   rm -rf .tmp/src/lunet-* .tmp/runtime/lunet-*
   xmake test
   ```
3. **If all pass**, update `scripts/lunet-env.sh`
4. **Commit** with message: `"Upgrade Lunet to vX.Y.Z"`
5. **Monitor** for any issues in production

---

This policy ensures lunet-backproxy is always built with a well-tested, stable Lunet version while remaining flexible for debugging and testing.

## Advanced: Instrumented Builds (Optional)

For development, consider building Lunet with instrumentation (ASan, trace, etc.). See [Lunet XMAKE_INTEGRATION.md](https://github.com/lua-lunet/lunet/blob/main/docs/XMAKE_INTEGRATION.md) for details.

**Key insight**: Instrumentation adds <10% overhead on many workloads, making it worthwhile for development and QA. Final release testing should use stripped builds.

```bash
# Dev build with ASan (catches memory errors)
cd .tmp/src/lunet-v0.1.2
xmake f -P . -m release --lunet_asan=y
xmake build -P .

# Use it
export LUNET_BIN=$(pwd)/build/release/lunet-run
cd /path/to/lunet-backproxy
xmake test
```

Then for release testing, fall back to the standard (stripped) build by unsetting `LUNET_BIN`.

### Runtime safety knobs and rationale

These knobs are intentionally included for debugging and QA:

- **Apple allocator debugging (macOS):**
  `LUNET_ENABLE_APPLE_MALLOC_DEBUG=1` enables `MallocScribble`, `MallocPreScribble`, heap checks, and stack logging defaults in `scripts/lunet-env.sh`. These are explicitly useful for surfacing use-after-free and heap corruption patterns.
- **Rust sanitizers for Lunet source builds:**
  `LUNET_RUST_SANITIZER=asan|tsan` enables `-Zsanitizer` flags in `scripts/setup-lunet.sh` and defaults `RUSTUP_TOOLCHAIN` to `nightly` when unset, because those sanitizer flows depend on nightly.
- **Lua C module loader verification:**
  `scripts/setup-lunet.sh` performs a loader check (`require("lunet")`, `require("lunet.sqlite3")`) using the runtime's `LUA_CPATH`. This catches "compiled but not loadable" failures (including wrong search paths and missing `luaopen_*` exports).

Disable loader validation only when diagnosing bootstrap internals:

```bash
LUNET_SKIP_LOADER_CHECK=1 xmake run setup-lunet
```
