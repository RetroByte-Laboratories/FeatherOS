#!/bin/bash
# ---------------------------------------------------------------------------
# smoke-test.sh — boot the freshly built FeatherOS ISO in QEMU (no KVM, pure
# TCG so it runs on CI) and take periodic screenshots via the QMP monitor,
# for both BIOS and UEFI (OVMF) paths. Screenshots land in out/smoke/.
# This is an informational check: it always exits 0 — eyeball the artifacts.
# ---------------------------------------------------------------------------
set -uo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=build/config.sh
source build/config.sh

ISO="out/$ISO_NAME"
SMK="out/smoke"
SECS_BIOS="${SMOKE_SECS_BIOS:-660}"
SECS_UEFI="${SMOKE_SECS_UEFI:-420}"

log()  { printf '\n\033[1;35m[feather-smoke]\033[0m %s\n' "$*"; }
note() { printf '\033[0;33m[feather-smoke]  ·\033[0m %s\n' "$*"; }

[ -f "$ISO" ] || { log "no ISO at $ISO — nothing to smoke test"; exit 0; }
command -v qemu-system-x86_64 >/dev/null || { log "qemu not installed — skipping"; exit 0; }
mkdir -p "$SMK"

CONV=""
command -v magick >/dev/null && CONV="magick" || CONV="convert"

qmp_screendump() {
    python3 - "$1" "$2" <<'PY'
import json, socket, sys
sock_path, outfile = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX)
s.settimeout(20)
s.connect(sock_path)
f = s.makefile('rw')
f.readline()                                   # greeting
json.dump({"execute": "qmp_capabilities"}, f); f.flush(); f.readline()
json.dump({"execute": "screendump", "arguments": {"filename": outfile}}, f); f.flush()
f.readline()
s.close()
PY
}

run_qemu() {
    local name="$1" mode="$2" secs="$3"
    local sock="$SMK/$name.qmp"
    local extra=()
    [ "$mode" = "uefi" ] && extra=(-bios /usr/share/ovmf/OVMF.fd)

    log "booting ($mode) — up to $((secs/60)) min, screenshot every 25s"
    rm -f "$sock" /tmp/feather-"$name".ppm
    qemu-system-x86_64 \
        -m 3072 -smp 2 -machine q35 \
        -cdrom "$ISO" -boot d \
        -display none -vga std -no-reboot -no-shutdown \
        -qmp unix:"$sock",server,nowait \
        "${extra[@]}" &
    local pid=$!

    local i=0
    while [ $((i * 25)) -lt "$secs" ] && kill -0 "$pid" 2>/dev/null; do
        sleep 25
        i=$((i + 1))
        if qmp_screendump "$sock" "/tmp/feather-$name.ppm" 2>/dev/null; then
            "$CONV" /tmp/feather-"$name".ppm "$SMK/$name-$(printf '%02d' "$i").png" 2>/dev/null \
                || cp /tmp/feather-"$name".ppm "$SMK/$name-$(printf '%02d' "$i").ppm"
            rm -f /tmp/feather-"$name".ppm
            note "$name: screenshot $i"
        fi
    done

    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    rm -f "$sock"
}

run_qemu "bios" "bios" "$SECS_BIOS"
run_qemu "uefi" "uefi" "$SECS_UEFI"

# summary
{
    echo "FeatherOS ISO smoke test — $(date -u)"
    echo "ISO: $(sha256sum "$ISO" | awk '{print $1}')"
    echo
    echo "BIOS screenshots: $(ls "$SMK"/bios-*.png 2>/dev/null | wc -l)"
    echo "UEFI screenshots: $(ls "$SMK"/uefi-*.png 2>/dev/null | wc -l)"
    echo
    echo "Inspect the PNGs: final frames should show the FeatherOS Plymouth"
    echo "splash, then the LightDM greeter / live desktop."
} > "$SMK/SUMMARY.txt"
log "done — screenshots in $SMK/"
exit 0
