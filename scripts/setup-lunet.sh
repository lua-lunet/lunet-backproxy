#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PINNED_LUNET_REF_DEFAULT="6303e54e3a52a6aed30bdff058d7d77535e076aa"
LUNET_REF="${LUNET_REF:-${LUNET_VERSION:-$PINNED_LUNET_REF_DEFAULT}}"
LUNET_USE_PREBUILT="${LUNET_USE_PREBUILT:-0}"

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

if runtime_matches_host; then
    echo "Lunet runtime already prepared: $RUNTIME_DIR"
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
        xmake f -P . -m release --lunet_trace=n --lunet_verbose_trace=n -y
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

echo "Prepared Lunet runtime at $RUNTIME_DIR"
echo "LUNET_BIN=$RUNTIME_DIR/bin/lunet"
