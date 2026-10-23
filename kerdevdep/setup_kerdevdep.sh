#!/usr/bin/env bash
#
# setup_kerdevdep.sh - Bootstrap kerdevdep portable dependencies
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- Compiler selection ---------------------------------------------------
# TheRagingBeast (TRB) Clang 18.0.0, the same toolchain the onyx-kaeru branch
# builds with. It is self-contained: LLVM/Clang 18 + lld + bundled aarch64/arm
# binutils, so no separate GCC prebuilt is downloaded.
#
# The compiler that ships a released kernel is third-party code, so it is
# checked out at an exact revision instead of a mutable branch. To update:
#   git ls-remote "$TRB_CLANG_REPO" "$TRB_CLANG_REF"
TRB_CLANG_VER="${TRB_CLANG_VER:-TheRagingBeast TRB Clang 18.0.0 (17092023)}"
TRB_CLANG_REPO="${TRB_CLANG_REPO:-https://gitlab.com/voltageos/clang.git}"
TRB_CLANG_REF="${TRB_CLANG_REF:-test}"
TRB_CLANG_PIN="${TRB_CLANG_PIN:-b0fa406b3f65eae210c60dda2e91dae979e4b3a8}"
AK3_URL="${AK3_URL:-https://github.com/osm0sis/AnyKernel3/archive/refs/heads/master.zip}"

log() { printf '\033[1;34m[kerdevdep] %s\033[0m\n' "$*"; }

mkdir -p bin clang anykernel usr/share/bison lib

# 1. Download TRB Clang if missing, pinned to an exact revision
if [[ ! -x "clang/bin/clang" ]]; then
    log "Downloading ${TRB_CLANG_VER} (pinned ${TRB_CLANG_PIN:0:12}) ..."
    if ! command -v git >/dev/null 2>&1; then
        echo "[-] git is required to fetch ${TRB_CLANG_VER}" >&2
        exit 1
    fi
    rm -rf clang
    git clone --filter=blob:none --no-checkout "$TRB_CLANG_REPO" clang
    if ! git -C clang checkout --detach "$TRB_CLANG_PIN"; then
        echo "[-] Pinned toolchain ${TRB_CLANG_PIN} is not reachable from ${TRB_CLANG_REPO}" >&2
        echo "    The upstream branch was likely rewritten. Re-resolve the pin with:" >&2
        echo "    git ls-remote ${TRB_CLANG_REPO} ${TRB_CLANG_REF}" >&2
        exit 1
    fi
    actual="$(git -C clang rev-parse HEAD)"
    if [[ "$actual" != "$TRB_CLANG_PIN" ]]; then
        echo "[-] Toolchain pin mismatch (expected ${TRB_CLANG_PIN}, got ${actual})" >&2
        exit 1
    fi
    log "Toolchain verified at ${actual}"
    rm -rf clang/.git
    if [[ ! -x "clang/bin/clang" ]]; then
        echo "[-] Toolchain bootstrap failed: clang/bin/clang is missing" >&2
        exit 1
    fi
    # Record which toolchain was fetched, so build.sh can detect a selection
    # change and re-fetch instead of reusing a stale compiler.
    printf 'trb:%s:%s\n' "$TRB_CLANG_REPO" "$TRB_CLANG_PIN" > clang/.kerdevdep-toolchain
fi

# 2. Download AnyKernel3 template if missing
if [[ ! -f "anykernel/anykernel.sh" ]]; then
    log "Downloading AnyKernel3 template ..."
    curl -L --fail --retry 3 -o ak3.zip "$AK3_URL"
    mkdir -p ak3-tmp
    unzip -q ak3.zip -d ak3-tmp
    cp -r ak3-tmp/AnyKernel3-master/. anykernel/
    rm -rf ak3-tmp ak3.zip anykernel/.github
fi

# 4. Fetch host utilities if missing
if command -v bison >/dev/null && command -v flex >/dev/null && command -v m4 >/dev/null; then
    log "Host utilities (bison, flex, m4) already installed on system."
elif [[ ! -x "usr/bin/bison" || ! -x "usr/bin/flex" ]]; then
    log "Fetching host utilities (bison, flex, m4, pahole, ccache, libelf) ..."
    mkdir -p .deb_cache
    (
        cd .deb_cache
        apt-get download bison flex m4 pahole libbpf1 libdw1 libelf1 libelf-dev ccache libfl2 libfl-dev libssl-dev libssl3 2>/dev/null || \
        apt-get download bison flex m4 pahole libbpf1 libdw1t64 libelf1t64 libelf-dev ccache libfl2 libfl-dev libssl-dev libssl3t64 2>/dev/null || true
        for deb in *.deb; do
            [[ -f "$deb" ]] && dpkg-deb -x "$deb" ../
        done
    )
    rm -rf .deb_cache
fi

# 5. Setup bin/ wrappers
cat << 'WRAPPERS' > bin/bison
#!/usr/bin/env bash
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -x "$SELF_DIR/usr/bin/bison" ]]; then
    export BISON_PKGDATADIR="$SELF_DIR/usr/share/bison"
    export M4="$SELF_DIR/bin/m4"
    export LD_LIBRARY_PATH="$SELF_DIR/lib:$SELF_DIR/lib/x86_64-linux-gnu:$SELF_DIR/usr/lib:$SELF_DIR/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
    exec "$SELF_DIR/usr/bin/bison" "$@"
else
    exec bison "$@"
fi
WRAPPERS
chmod +x bin/bison

cat << 'WRAPPERS' > bin/yacc
#!/usr/bin/env bash
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SELF_DIR/bison" -y "$@"
WRAPPERS
chmod +x bin/yacc

cat << 'WRAPPERS' > bin/flex
#!/usr/bin/env bash
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -x "$SELF_DIR/usr/bin/flex" ]]; then
    export LD_LIBRARY_PATH="$SELF_DIR/lib:$SELF_DIR/lib/x86_64-linux-gnu:$SELF_DIR/usr/lib:$SELF_DIR/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
    exec "$SELF_DIR/usr/bin/flex" "$@"
elif [[ -x "/usr/bin/flex" ]]; then
    exec /usr/bin/flex "$@"
else
    exec flex "$@"
fi
WRAPPERS
chmod +x bin/flex
ln -sf flex bin/lex
ln -sf flex bin/flex++

cat << 'WRAPPERS' > bin/m4
#!/usr/bin/env bash
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -x "$SELF_DIR/usr/bin/m4" ]]; then
    export LD_LIBRARY_PATH="$SELF_DIR/lib:$SELF_DIR/lib/x86_64-linux-gnu:$SELF_DIR/usr/lib:$SELF_DIR/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
    exec "$SELF_DIR/usr/bin/m4" "$@"
elif [[ -x "/usr/bin/m4" ]]; then
    exec /usr/bin/m4 "$@"
else
    exec m4 "$@"
fi
WRAPPERS
chmod +x bin/m4

cat << 'WRAPPERS' > bin/pahole
#!/usr/bin/env bash
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -x "$SELF_DIR/usr/bin/pahole" ]]; then
    export LD_LIBRARY_PATH="$SELF_DIR/lib:$SELF_DIR/lib/x86_64-linux-gnu:$SELF_DIR/usr/lib:$SELF_DIR/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
    exec "$SELF_DIR/usr/bin/pahole" "$@"
elif [[ -x "/usr/bin/pahole" ]]; then
    exec /usr/bin/pahole "$@"
else
    exec pahole "$@"
fi
WRAPPERS
chmod +x bin/pahole

cat << 'WRAPPERS' > bin/ccache
#!/usr/bin/env bash
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -x "$SELF_DIR/usr/bin/ccache" ]]; then
    export LD_LIBRARY_PATH="$SELF_DIR/lib:$SELF_DIR/lib/x86_64-linux-gnu:$SELF_DIR/usr/lib:$SELF_DIR/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
    exec "$SELF_DIR/usr/bin/ccache" "$@"
elif [[ -x "/usr/bin/ccache" ]]; then
    exec /usr/bin/ccache "$@"
else
    exec "$@"
fi
WRAPPERS
chmod +x bin/ccache

# Symlink clang binaries
for f in clang/bin/*; do
    name="$(basename "$f")"
    if [[ ! -e "bin/$name" ]]; then
        ln -sf "../clang/bin/$name" "bin/$name"
    fi
done

# Symlink host fallback utilities
for cmd in zip unzip cpio bc make git tar curl python3; do
    p="$(command -v "$cmd" 2>/dev/null || true)"
    if [[ -n "$p" && ! -e "bin/$cmd" ]]; then
        ln -sf "$p" "bin/$cmd"
    fi
done

log "kerdevdep dependencies successfully set up."
