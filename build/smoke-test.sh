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

OVMF_CODE=""
OVMF_VARS=""
for ovmf_dir in /usr/share/OVMF /usr/share/ovmf; do
    if [ -r "$ovmf_dir/OVMF_CODE_4M.fd" ] && [ -r "$ovmf_dir/OVMF_VARS_4M.fd" ]; then
        OVMF_CODE="$ovmf_dir/OVMF_CODE_4M.fd"
        OVMF_VARS="$ovmf_dir/OVMF_VARS_4M.fd"
        break
    elif [ -r "$ovmf_dir/OVMF_CODE.fd" ] && [ -r "$ovmf_dir/OVMF_VARS.fd" ]; then
        OVMF_CODE="$ovmf_dir/OVMF_CODE.fd"
        OVMF_VARS="$ovmf_dir/OVMF_VARS.fd"
        break
    fi
done

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
    local vars_copy="$SMK/$name-vars.fd"
    local extra=()
    if [ "$mode" = "uefi" ]; then
        extra=(
            -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE"
            -drive "if=pflash,format=raw,unit=1,file=$vars_copy"
        )
    fi

    log "booting ($mode) — up to $((secs/60)) min, screenshot every 25s"
    rm -f "$sock" "$vars_copy" /tmp/feather-"$name".ppm
    if [ "$mode" = "uefi" ]; then
        cp "$OVMF_VARS" "$vars_copy" || { log "could not copy OVMF variables image"; return 1; }
    fi
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
    rm -f "$sock" "$vars_copy"
}

run_qemu "bios" "bios" "$SECS_BIOS"
if [ -n "$OVMF_CODE" ] && [ -n "$OVMF_VARS" ]; then
    run_qemu "uefi" "uefi" "$SECS_UEFI"
else
    log "OVMF code/variables pair not found — skipping the UEFI boot test"
fi

# summary
{
    echo "FeatherOS ISO smoke test — $(date -u)"
    echo "ISO: $(sha256sum "$ISO" | awk '{print $1}')"
    echo
    echo "BIOS screenshots: $(ls "$SMK"/bios-*.png 2>/dev/null | wc -l)"
    echo "UEFI screenshots: $(ls "$SMK"/uefi-*.png 2>/dev/null | wc -l)"
    echo "UEFI firmware: ${OVMF_CODE:-not found (test skipped)}"
    echo
    echo "Inspect the PNGs: final frames should show the FeatherOS Plymouth"
    echo "splash, then the LightDM greeter / live desktop."
} > "$SMK/SUMMARY.txt"
log "done — screenshots in $SMK/"
exit 0
