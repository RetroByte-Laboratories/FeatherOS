#!/bin/bash
# ---------------------------------------------------------------------------
# fetch-base.sh — obtain + SHA256-verify the Ubuntu 22.04 desktop base ISO.
#
# Resolution order:
#   1. target file already present with a .sha256-verified marker
#   2. FEATHER_BASE_ISO — path to a seed/cache copy; downloaded there if
#      absent (so a CI cache dir can be warmed on the first run)
#   3. the mirror list BASE_ISO_URLS from build/config.sh
#
# Integrity is always checked against the upstream SHA256SUMS. Note the sums
# file lists ORIGINAL upstream filenames ("hash *ubuntu-22.04.5-...iso"), so
# verification is keyed by the upstream name — never by our local file name.
# ---------------------------------------------------------------------------
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=build/config.sh
source build/config.sh

TARGET="${1:-${FEATHER_WORK:-/tmp/feather-build}/base.iso}"
mkdir -p "$(dirname "$TARGET")"

log() { printf '\n\033[1;35m[feather-fetch]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[feather-fetch] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

verified() {
    local recorded actual
    [ -f "$TARGET" ] && [ -s "$TARGET.sha256-verified" ] || return 1
    recorded="$(cat "$TARGET.sha256-verified")"
    actual="$(sha256sum < "$TARGET" | awk '{print $1}')"
    [ "$recorded" = "$actual" ]
}

fetch_sums() { # $1 = directory that hosts SHA256SUMS
    curl -fsSL --max-time 60 -o "$TARGET.sums" "$1/SHA256SUMS"
}

# verify <upstream-filename> — checks $TARGET against $TARGET.sums.
# Returns 1 when the entry is missing; hard-fails on a real mismatch.
verify() {
    local name="$1" expected actual
    expected="$(awk -v n="$name" '{ l=$NF; sub(/^\*/,"",l); if (l == n) print $1 }' "$TARGET.sums" | head -1)"
    if [ -z "$expected" ]; then
        log "no entry for '$name' in $(basename "$TARGET.sums") — it starts with:"
        head -5 "$TARGET.sums" | sed 's/^/    | /'
        return 1
    fi
    actual="$(sha256sum < "$TARGET" | awk '{print $1}')"
    [ "$expected" = "$actual" ] || fail "SHA256 MISMATCH for $name (expected $expected, got $actual)"
    printf '%s\n' "$actual" > "$TARGET.sha256-verified"
    log "checksum OK: ${actual:0:16}… ($(du -h "$TARGET" | cut -f1))"
}

if verified; then
    log "base ISO already present and verified: $TARGET"
    exit 0
fi

# ---- path 2: seed/cache location -----------------------------------------
if [ -n "${FEATHER_BASE_ISO:-}" ]; then
    if [ ! -f "$FEATHER_BASE_ISO" ]; then
        log "$FEATHER_BASE_ISO not present — warming the cache from ${BASE_ISO_URLS[0]}"
        mkdir -p "$(dirname "$FEATHER_BASE_ISO")"
        curl -fL --retry 3 --retry-delay 5 -o "$FEATHER_BASE_ISO.part" "${BASE_ISO_URLS[0]}"
        mv -f "$FEATHER_BASE_ISO.part" "$FEATHER_BASE_ISO"
    fi
    log "seeding $TARGET from $FEATHER_BASE_ISO"
    ln -f "$FEATHER_BASE_ISO" "$TARGET" 2>/dev/null || cp -f "$FEATHER_BASE_ISO" "$TARGET"

    name="${BASE_ISO_URLS[0]##*/}"
    verified_sum=0
    for url in "${BASE_ISO_URLS[@]}"; do
        if fetch_sums "${url%/*}" && verify "$name"; then
            verified_sum=1
            break
        fi
    done
    [ "$verified_sum" = 1 ] || fail "could not verify cached ISO '$name' against upstream SHA256SUMS"
    log "base ISO ready: $TARGET"
    exit 0
fi

# ---- path 3: mirror list ---------------------------------------------------
ok=0
for url in "${BASE_ISO_URLS[@]}"; do
    dir="${url%/*}"
    name="${url##*/}"
    log "trying $url"
    if curl -fL --retry 3 --retry-delay 5 -o "$TARGET.part" "$url"; then
        log "downloaded $(du -h "$TARGET.part" | cut -f1)"
        mv -f "$TARGET.part" "$TARGET"
        if ! fetch_sums "$dir"; then
            log "could not fetch SHA256SUMS from $dir — discarding this download"
            rm -f "$TARGET" "$TARGET.sums"
            continue
        fi
        if ! verify "$name"; then
            log "no matching checksum for $name from $dir — trying the next mirror"
            rm -f "$TARGET" "$TARGET.sums"
            continue
        fi
        ok=1
        break
    else
        log "download failed (curl exit $?) — trying next mirror…"
    fi
done

[ "$ok" = 1 ] || fail "could not download any base ISO (tried ${#BASE_ISO_URLS[@]} URLs)"
log "base ISO ready: $TARGET ($(du -h "$TARGET" | cut -f1))"
