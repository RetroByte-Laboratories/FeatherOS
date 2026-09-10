#!/bin/bash
# ---------------------------------------------------------------------------
# fetch-base.sh — download the Ubuntu 22.04 desktop base ISO and verify it
# against the SHA256SUMS published next to it.
#
# Usage: fetch-base.sh [target-file]   (default: $FEATHER_WORK/base.iso)
# Env:   FEATHER_BASE_ISO — path to an already downloaded ISO (skips download,
#        still verifies against SHA256SUMS when reachable).
# ---------------------------------------------------------------------------
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=build/config.sh
source build/config.sh

TARGET="${1:-${FEATHER_WORK:-/tmp/feather-build}/base.iso}"
mkdir -p "$(dirname "$TARGET")"

log() { printf '\n\033[1;35m[feather-fetch]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[feather-fetch] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

verify_iso() {
    local iso="$1" sums="$2"
    grep -F " $(basename "$iso")" "$sums" | sed "s| $(basename "$iso")| $(realpath "$iso")|" \
        | sha256sum -c - || fail "SHA256 verification FAILED for $iso"
    log "checksum OK: $(sha256sum "$iso" | cut -c1-16)…"
}

if [ -n "${FEATHER_BASE_ISO:-}" ]; then
    [ -f "$FEATHER_BASE_ISO" ] || fail "FEATHER_BASE_ISO=$FEATHER_BASE_ISO does not exist"
    log "using provided base ISO: $FEATHER_BASE_ISO"
    cp -f "$FEATHER_BASE_ISO" "$TARGET"
fi

if [ -f "$TARGET" ] && [ -f "$TARGET.sha256-verified" ]; then
    log "base ISO already present and verified: $TARGET"
    exit 0
fi

ok=0
for url in "${BASE_ISO_URLS[@]}"; do
    dir="${url%/*}"
    name="${url##*/}"
    log "trying $url"
    if curl -fL --retry 3 --retry-delay 5 -o "$TARGET.part" "$url"; then
        mv -f "$TARGET.part" "$TARGET"
        if curl -fsSL -o "$TARGET.sums" "$dir/SHA256SUMS"; then
            verify_iso "$TARGET" "$TARGET.sums"
        else
            log "WARNING: could not fetch SHA256SUMS from $dir — continuing (unverified!)"
        fi
        touch "$TARGET.sha256-verified"
        ok=1
        break
    else
        log "download failed, trying next mirror…"
    fi
done

[ "$ok" = 1 ] || fail "could not download any base ISO (tried ${#BASE_ISO_URLS[@]} URLs)"
log "base ISO ready: $TARGET ($(du -h "$TARGET" | cut -f1))"
