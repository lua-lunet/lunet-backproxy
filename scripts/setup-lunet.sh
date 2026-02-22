#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PINNED_LUNET_REF_DEFAULT="6303e54e3a52a6aed30bdff058d7d77535e076aa"
LUNET_REF="${LUNET_REF:-${LUNET_VERSION:-$PINNED_LUNET_REF_DEFAULT}}"
LUNET_USE_PREBUILT="${LUNET_USE_PREBUILT:-0}"
LUNET_RUST_SANITIZER="${LUNET_RUST_SANITIZER:-}"
LUNET_SKIP_LOADER_CHECK="${LUNET_SKIP_LOADER_CHECK:-0}"

normalize_rust_sanitizer() {
    case "$1" in
        "")
            printf "%s" ""
            ;;
        asan|address)
            printf "%s" "address"
            ;;
        tsan|thread)
            printf "%s" "thread"
            ;;
        *)
            echo "Unsupported LUNET_RUST_SANITIZER='$1' (supported: asan, tsan)." >&2
            exit 1
            ;;
    esac
}

append_rust_flag() {
    local flag="$1"
    if [ -z "${RUSTFLAGS:-}" ]; then
        export RUSTFLAGS="$flag"
    else
        export RUSTFLAGS="${RUSTFLAGS} $flag"
    fi
}

configure_rust_sanitizer_env() {
    local sanitizer="$1"
    if [ -z "$sanitizer" ]; then
        return 0
    fi
    if [ -z "${RUSTUP_TOOLCHAIN:-}" ]; then
        export RUSTUP_TOOLCHAIN="nightly"
    fi
    append_rust_flag "-Zsanitizer=${sanitizer}"
    echo "Enabled Rust sanitizer '${sanitizer}' (nightly toolchain is required for -Zsanitizer)."
}

# This repo must not rely on sibling checkouts like ../lunet.
# Some dev environments may still have a leftover symlink at ./lunet; warn, but ignore it.
if [ -L "$ROOT_DIR/lunet" ]; then
    echo "WARN: Found symlink $ROOT_DIR/lunet. This repo does not use sibling Lunet checkouts; using GitHub source via .tmp instead." >&2
fi

ref_slug() {
    printf "%s" "$1" | tr '/:' '__' | tr -c '[:alnum:]._-' '_'
}

REF_SLUG="$(ref_slug "$LUNET_REF")"
RUNTIME_DIR="$ROOT_DIR/.tmp/runtime/lunet-${REF_SLUG}"
SRC_DIR="$ROOT_DIR/.tmp/src/lunet-${REF_SLUG}"
RUST_SANITIZER_KIND="$(normalize_rust_sanitizer "$LUNET_RUST_SANITIZER")"

mkdir -p "$ROOT_DIR/.tmp/runtime" "$ROOT_DIR/.tmp/src"

OS_UNAME="$(uname -s)"
ARCH_UNAME="$(uname -m)"

case "$OS_UNAME" in
    Linux) TARGET_OS="linux" ;;
    Darwin) TARGET_OS="macos" ;;
    *)
        echo "Unsupported OS: $OS_UNAME"
        exit 1
        ;;
esac

case "$ARCH_UNAME" in
    x86_64|amd64) TARGET_ARCH="amd64" ;;
    arm64|aarch64) TARGET_ARCH="arm64" ;;
    *)
        echo "Unsupported architecture: $ARCH_UNAME"
        exit 1
        ;;
esac

runtime_matches_host() {
    if [ ! -x "$RUNTIME_DIR/bin/lunet" ] || [ ! -f "$RUNTIME_DIR/.version" ]; then
        return 1
    fi
    if ! grep -qx "$LUNET_REF" "$RUNTIME_DIR/.version"; then
        return 1
    fi

    local file_out
    file_out="$(file -b "$RUNTIME_DIR/bin/lunet" 2>/dev/null || true)"
    if [ -z "$file_out" ]; then
        return 1
    fi

    if [ "$TARGET_OS" = "linux" ] && [[ "$file_out" != *"ELF"* ]]; then
        return 1
    fi
    if [ "$TARGET_OS" = "macos" ] && [[ "$file_out" != *"Mach-O"* ]]; then
        return 1
    fi
    if [ "$TARGET_ARCH" = "amd64" ] && [[ "$file_out" != *"x86-64"* && "$file_out" != *"x86_64"* ]]; then
        return 1
    fi
    if [ "$TARGET_ARCH" = "arm64" ] && [[ "$file_out" != *"aarch64"* && "$file_out" != *"arm64"* ]]; then
        return 1
    fi

    return 0
}

validate_runtime_loader() {
    if [ "$LUNET_SKIP_LOADER_CHECK" = "1" ]; then
        return 0
    fi
    if [ ! -x "$RUNTIME_DIR/bin/lunet" ]; then
        return 1
    fi

    local check_script="$ROOT_DIR/.tmp/lua-loader-check-${REF_SLUG}.lua"
    cat >"$check_script" <<'LUA'
local modules = {
    "lunet",
    "lunet.sqlite3",
}

for _, name in ipairs(modules) do
    local ok, mod_or_err = pcall(require, name)
    if not ok then
        io.stderr:write(string.format("loader-check failed: require(%q): %s\n", name, tostring(mod_or_err)))
        os.exit(1)
    end
end

print("loader-check ok: lunet + lunet.sqlite3")
LUA

    local saved_lua_cpath="${LUA_CPATH:-}"
    export LUA_CPATH="$RUNTIME_DIR/lib/?.so;$RUNTIME_DIR/lib/?/?.so;;${saved_lua_cpath}"

    if ! "$RUNTIME_DIR/bin/lunet" "$check_script"; then
        echo "Lunet module loader check failed. Verify package.cpath and luaopen_* exports." >&2
        rm -f "$check_script"
        return 1
    fi
    rm -f "$check_script"
    return 0
}

if runtime_matches_host; then
    echo "Lunet runtime already prepared: $RUNTIME_DIR"
    validate_runtime_loader
    exit 0
fi

ASSET_NAME=""
if [ "$LUNET_USE_PREBUILT" = "1" ] && [[ "$LUNET_REF" =~ ^v[0-9] ]]; then
    if [ "$TARGET_OS" = "linux" ] && [ "$TARGET_ARCH" = "amd64" ]; then
        ASSET_NAME="lunet-linux-amd64.tar.gz"
    elif [ "$TARGET_OS" = "macos" ]; then
        ASSET_NAME="lunet-macos.tar.gz"
    fi
fi

rm -rf "$RUNTIME_DIR"
mkdir -p "$RUNTIME_DIR/bin" "$RUNTIME_DIR/lib/lunet"

if [ -n "$ASSET_NAME" ]; then
    URL="https://github.com/lua-lunet/lunet/releases/download/${LUNET_REF}/${ASSET_NAME}"
    ARCHIVE="$ROOT_DIR/.tmp/${ASSET_NAME}"
    STAGE="$ROOT_DIR/.tmp/lunet-stage-${REF_SLUG}"

    echo "Downloading Lunet ${LUNET_REF} release asset: ${ASSET_NAME}"
    curl -fL "$URL" -o "$ARCHIVE"

    rm -rf "$STAGE"
    mkdir -p "$STAGE"
    tar -xzf "$ARCHIVE" -C "$STAGE"

    LUNET_BIN_SRC="$(find "$STAGE" -type f -name 'lunet-run' | head -1)"
    LUNET_SO_SRC="$(find "$STAGE" -type f -name 'lunet.so' | head -1)"
    SQLITE_SO_SRC="$(find "$STAGE" -type f -name 'sqlite3.so' | head -1)"

    if [ -z "$LUNET_BIN_SRC" ] || [ -z "$LUNET_SO_SRC" ] || [ -z "$SQLITE_SO_SRC" ]; then
        echo "Release asset did not contain required files (lunet-run, lunet.so, sqlite3.so)."
        exit 1
    fi

    cp "$LUNET_BIN_SRC" "$RUNTIME_DIR/bin/lunet"
    cp "$LUNET_SO_SRC" "$RUNTIME_DIR/lib/lunet.so"
    cp "$SQLITE_SO_SRC" "$RUNTIME_DIR/lib/lunet/sqlite3.so"
else
    echo "Building Lunet from github.com/lua-lunet/lunet ref ${LUNET_REF}"
    configure_rust_sanitizer_env "$RUST_SANITIZER_KIND"

    if ! command -v git >/dev/null 2>&1; then
        echo "Missing required tool: git"
        exit 1
    fi
    if ! command -v xmake >/dev/null 2>&1; then
        echo "Missing required tool: xmake"
        exit 1
    fi

    rm -rf "$SRC_DIR"
    git clone https://github.com/lua-lunet/lunet.git "$SRC_DIR"
    (
        cd "$SRC_DIR"
        git checkout "$LUNET_REF"
    )

    (
        cd "$SRC_DIR"
        unset XMAKE_PROJECT_DIR
        xmake_config_args=(-P . -m release --lunet_trace=n --lunet_verbose_trace=n -y)
        if [ "$RUST_SANITIZER_KIND" = "address" ] || [ "${LUNET_ENABLE_LUNET_ASAN:-0}" = "1" ]; then
            xmake_config_args+=(--lunet_asan=y)
        fi
        xmake f "${xmake_config_args[@]}"
        xmake build -P .
        xmake build -P . lunet-sqlite3
    )

    LUNET_BIN_SRC="$(find "$SRC_DIR/build" -type f -name 'lunet-run' | head -1)"
    LUNET_SO_SRC="$(find "$SRC_DIR/build" -type f -name 'lunet.so' | head -1)"
    SQLITE_SO_SRC="$(find "$SRC_DIR/build" -type f -name 'sqlite3.so' | head -1)"

    if [ -z "$LUNET_BIN_SRC" ] || [ -z "$LUNET_SO_SRC" ] || [ -z "$SQLITE_SO_SRC" ]; then
        echo "Built Lunet did not produce required files (lunet-run, lunet.so, sqlite3.so)."
        exit 1
    fi

    cp "$LUNET_BIN_SRC" "$RUNTIME_DIR/bin/lunet"
    cp "$LUNET_SO_SRC" "$RUNTIME_DIR/lib/lunet.so"
    cp "$SQLITE_SO_SRC" "$RUNTIME_DIR/lib/lunet/sqlite3.so"
fi

chmod +x "$RUNTIME_DIR/bin/lunet"
echo "$LUNET_REF" > "$RUNTIME_DIR/.version"
validate_runtime_loader

echo "Prepared Lunet runtime at $RUNTIME_DIR"
echo "LUNET_BIN=$RUNTIME_DIR/bin/lunet"
