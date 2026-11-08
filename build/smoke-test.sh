#!/bin/bash
# ---------------------------------------------------------------------------
# smoke-test.sh — boot the FeatherOS ISO in QEMU TCG and take periodic
# screenshots via QMP for both BIOS and UEFI (OVMF). Screenshots and QEMU logs
# land in out/smoke/. A requested smoke test fails if QEMU/OVMF cannot start or
# either mode produces no screenshots; inspect the images for the live desktop.
# ---------------------------------------------------------------------------
set -uo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=build/config.sh
source build/config.sh

ISO="out/$ISO_NAME"
SMK="out/smoke"
SECS_BIOS="${SMOKE_SECS_BIOS:-660}"
SECS_UEFI="${SMOKE_SECS_UEFI:-420}"
INTERVAL="${SMOKE_INTERVAL:-25}"

log()  { printf '\n\033[1;35m[feather-smoke]\033[0m %s\n' "$*"; }
note() { printf '\033[0;33m[feather-smoke]  ·\033[0m %s\n' "$*"; }
fail() { log "ERROR: $*" >&2; exit 1; }

[ -f "$ISO" ] || fail "no ISO at $ISO"
command -v qemu-system-x86_64 >/dev/null || fail "qemu-system-x86_64 is not installed"
mkdir -p "$SMK"

CONV=""
if command -v magick >/dev/null; then
    CONV=magick
elif command -v convert >/dev/null; then
    CONV=convert
fi

OVMF_CODE=""
OVMF_VARS=""
for ovmf_dir in /usr/share/OVMF /usr/share/ovmf /usr/share/qemu; do
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
[ -n "$OVMF_CODE" ] || fail "OVMF code/variables pair not found; install the ovmf package"

qmp_screendump() {
    python3 - "$1" "$2" <<'PY'
import json, socket, sys
sock_path, outfile = sys.argv[1], sys.argv[2]
sock = socket.socket(socket.AF_UNIX)
sock.settimeout(20)
sock.connect(sock_path)
stream = sock.makefile('rwb')
stream.readline()                                # QMP greeting

def execute(command, request_id, arguments=None):
    payload = {"execute": command, "id": request_id}
    if arguments is not None:
        payload["arguments"] = arguments
    stream.write((json.dumps(payload) + "\r\n").encode())
    stream.flush()
    while True:
        line = stream.readline()
        if not line:
            raise RuntimeError("QMP closed before replying")
        response = json.loads(line)
        if response.get("id") == request_id:
            if "error" in response:
                raise RuntimeError(response["error"].get("desc", "QMP command failed"))
            return response

execute("qmp_capabilities", 1)
execute("screendump", 2, {"filename": outfile})
stream.close()
sock.close()
PY
}

count_screenshots() {
    find "$SMK" -maxdepth 1 -type f \
        \( -name "$1-*.png" -o -name "$1-*.ppm" \) | wc -l
}

run_qemu() {
    local name="$1" mode="$2" secs="$3"
    local sock="$SMK/$name.qmp" qlog="$SMK/$name-qemu.log"
    local vars_copy="$SMK/$name-vars.fd" pid i=0 shots
    local -a extra=()
    if [ "$mode" = "uefi" ]; then
        extra=(
            -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE"
            -drive "if=pflash,format=raw,unit=1,file=$vars_copy"
        )
    fi

    log "booting ($mode) — up to $((secs/60)) min, screenshot every ${INTERVAL}s"
    rm -f "$sock" "$vars_copy" "/tmp/feather-$name.ppm" \
        "$SMK/$name-"*.png "$SMK/$name-"*.ppm "$qlog"
    if [ "$mode" = "uefi" ]; then
        cp "$OVMF_VARS" "$vars_copy" || { log "could not copy OVMF variables image"; return 1; }
    fi
    qemu-system-x86_64 \
        -accel tcg,thread=multi -m 3072 -smp 2 -machine q35 \
        -cdrom "$ISO" -boot d \
        -display none -vga std -no-reboot -no-shutdown \
        -qmp unix:"$sock",server,nowait \
        "${extra[@]}" >"$qlog" 2>&1 &
    pid=$!

    # Fail quickly on bad QEMU/firmware arguments instead of sleeping through
    # the full test interval with a dead VM.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [ -S "$sock" ] && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.5
    done
    if [ ! -S "$sock" ]; then
        wait "$pid" 2>/dev/null || true
        log "$name QEMU did not start its QMP socket"
        tail -n 40 "$qlog" >&2 || true
        return 1
    fi

    while [ $((i * INTERVAL)) -lt "$secs" ] && kill -0 "$pid" 2>/dev/null; do
        sleep "$INTERVAL"
        i=$((i + 1))
        if ! kill -0 "$pid" 2>/dev/null; then
            note "$name QEMU exited after $((i * INTERVAL))s"
            break
        fi
        if qmp_screendump "$sock" "/tmp/feather-$name.ppm" 2>/dev/null; then
            if [ -n "$CONV" ]; then
                "$CONV" "/tmp/feather-$name.ppm" "$SMK/$name-$(printf '%02d' "$i").png" 2>/dev/null \
                    || cp "/tmp/feather-$name.ppm" "$SMK/$name-$(printf '%02d' "$i").ppm"
            else
                cp "/tmp/feather-$name.ppm" "$SMK/$name-$(printf '%02d' "$i").ppm"
            fi
            rm -f "/tmp/feather-$name.ppm"
            note "$name: screenshot $i"
        fi
    done

    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    rm -f "$sock" "$vars_copy"
    shots="$(count_screenshots "$name")"
    if [ "$shots" -eq 0 ]; then
        log "$name QEMU produced no screenshots"
        tail -n 40 "$qlog" >&2 || true
        return 1
    fi
    note "$name: captured $shots screenshot(s); QEMU log: $qlog"
}

bios_status=0
uefi_status=0
run_qemu "bios" "bios" "$SECS_BIOS" || bios_status=$?
run_qemu "uefi" "uefi" "$SECS_UEFI" || uefi_status=$?

{
    echo "FeatherOS ISO smoke test — $(date -u)"
    echo "ISO: $(sha256sum "$ISO" | awk '{print $1}')"
    echo "BIOS status: $bios_status; screenshots: $(count_screenshots bios)"
    echo "UEFI status: $uefi_status; screenshots: $(count_screenshots uefi)"
    echo "UEFI firmware: $OVMF_CODE"
    echo
    echo "Inspect the screenshots: they should show the FeatherOS Plymouth"
    echo "splash followed by the LightDM greeter or live desktop."
} > "$SMK/SUMMARY.txt"

if [ "$bios_status" -ne 0 ] || [ "$uefi_status" -ne 0 ]; then
    log "one or more QEMU boot tests failed; see $SMK/SUMMARY.txt and the QEMU logs"
    exit 1
fi
log "both BIOS and UEFI smoke tests captured screenshots in $SMK/"
