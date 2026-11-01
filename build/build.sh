#!/bin/bash
# ---------------------------------------------------------------------------
# build.sh — FeatherOS 6.1 "Eiderdown" main build orchestrator.
#
# Remasters the official Ubuntu 22.04 desktop ISO:
#   fetch     download + verify base ISO
#   extract   loop-mount it and copy the tree (sans old squashfs) + blobs
#   unpack    unsquashfs the live rootfs
#   overlay   copy FeatherOS files + branding into the rootfs
#   customize chroot: swap GNOME Shell for Flashback/Metacity, apps, initrd
#   repack    trim + re-squash, patch boot menus / efi.img / md5s / manifests
#   iso       build the final hybrid ISO with xorriso
#   all       everything above, in order
#
# MUST run as root (chroot + mounts). Work dir is chosen automatically
# (FEATHER_WORK overrides); the pipeline is written to fit ~15GB.
# ---------------------------------------------------------------------------
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=build/config.sh
source build/config.sh

MODE="${1:-all}"
SLIM="${SLIM_BUILD:-0}"

log()   { printf '\n\033[1;35m[feather-build]\033[0m %s\n' "$*"; }
stage() { printf '\n\033[1;45;97m== %s ==\033[0m\n' "$*"; }
fail()  { printf '\033[1;31m[feather-build] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }
disk()  { df -h "$1" 2>/dev/null | awk 'NR==2{printf "%s free of %s", $4, $2}'; }

[ "$(id -u)" = 0 ] || fail "build.sh must run as root (try: sudo bash build/build.sh $MODE)"

# ---- work directory ------------------------------------------------------
# Evaluate candidates, pick the one with the most free space; need >= 12GB.
# FEATHER_WORK is an explicit override. Keep all diagnostics on stderr because
# pick_workdir's stdout is captured to obtain the selected path.
pick_workdir() {
    local cands=() d avail best="" best_avail=0

    if [ -n "${FEATHER_WORK:-}" ]; then
        d="$FEATHER_WORK"
        mkdir -p "$d" 2>/dev/null || fail "cannot create FEATHER_WORK directory: $d"
        avail="$(df -BG --output=avail "$d" 2>/dev/null | tail -1 | tr -dc '0-9')"
        log "using FEATHER_WORK $d: ${avail:-?}GB free $(disk "$d")" >&2
        [ -n "${avail:-}" ] || fail "cannot determine free space for FEATHER_WORK: $d"
        [ "$avail" -ge 12 ] || fail "FEATHER_WORK $d has only ${avail}GB free (need >=12GB)"
        printf '%s' "$d"
        return
    fi

    cands+=(/mnt/feather-build "$HOME/feather-build" /tmp/feather-build ./feather-build-work)
    for d in "${cands[@]}"; do
        mkdir -p "$d" 2>/dev/null || continue
        avail="$(df -BG --output=avail "$d" 2>/dev/null | tail -1 | tr -dc '0-9')"
        log "candidate workdir $d: ${avail:-?}GB free $(disk "$d")" >&2
        [ -n "${avail:-}" ] || continue
        if [ "$avail" -gt "$best_avail" ]; then best="$d"; best_avail="$avail"; fi
    done
    [ -n "$best" ] || fail "no usable work directory found"
    [ "$best_avail" -ge 12 ] || fail "best workdir $best has only ${best_avail}GB free (need >=12GB)"
    printf '%s' "$best"
}
WORK="$(pick_workdir)"
ISO_SRC="$WORK/iso-src"
ROOTFS="$WORK/rootfs"
BASE_ISO="$WORK/base.iso"
ISOMNT="$WORK/isomnt"
OUTDIR="$(pwd)/out"
mkdir -p "$OUTDIR"

log "FeatherOS $FEATHER_VERSION “$FEATHER_CODENAME” build"
log "workdir: $WORK ($(disk "$WORK"))   |   slim: $SLIM"
[ "$SLIM" = 1 ] && log "SLIM build: LibreOffice / GIMP / Thunderbird will be omitted"

# early build metadata (updated again when the ISO is finished)
cat > "$OUTDIR/build-info.txt" <<EOF
FeatherOS $FEATHER_PRETTY
status:     running — started $(date -u '+%Y-%m-%d %H:%M:%S UTC')
base:       Ubuntu $FEATHER_BASE_RELEASE LTS ($FEATHER_BASE_CODENAME)
workdir:    $WORK ($(disk "$WORK"))
slim:       $SLIM
EOF

# ---- helpers -------------------------------------------------------------
require_cmds() {
    local c
    for c in "$@"; do command -v "$c" >/dev/null || fail "missing command: $c"; done
}

mount_chroot() {
    mount -t proc  proc  "$ROOTFS/proc"
    mount --rbind /sys  "$ROOTFS/sys"  2>/dev/null || mount -t sysfs sys "$ROOTFS/sys"
    mount --rbind /dev  "$ROOTFS/dev"
    mount --make-rslave "$ROOTFS/dev" 2>/dev/null || true
}

umount_chroot() {
    umount -l "$ROOTFS/proc" 2>/dev/null || true
    umount -l "$ROOTFS/sys"  2>/dev/null || true
    umount -l "$ROOTFS/dev"  2>/dev/null || true
}

# Extract the hybrid-boot blobs (MBR template + EFI partition image) from the
# ORIGINAL ISO — they are reused verbatim when rebuilding (keeps signed
# shim/GRUB intact).
extract_iso_blobs() {
    python3 - "$BASE_ISO" "$WORK" <<'PY'
import struct, sys
iso, out = sys.argv[1:3]
with open(iso, 'rb') as f:
    mbr = f.read(512)
assert mbr[510:512] == b'\x55\xaa', "base ISO has no hybrid MBR — unexpected layout"
target = None
for i in range(4):
    e = mbr[446 + 16*i: 446 + 16*(i+1)]
    if e[4] == 0:
        continue
    start, cnt = struct.unpack('<II', e[8:16])
    if i == 1:  # partition 2 = EFI system partition on Ubuntu hybrids
        target = (start, cnt)
if not target:
    raise SystemExit("EFI partition (p2) not found in base ISO MBR")
with open(out + "/boot_hybrid.img", "wb") as f:
    f.write(mbr[:432])
with open(iso, 'rb') as f:
    f.seek(target[0] * 512)
    with open(out + "/efi.img", "wb") as f2:
        f2.write(f.read(target[1] * 512))
print(f"blobs: boot_hybrid.img=432B efi.img={target[1]*512}B")
PY
}

# ---- stages --------------------------------------------------------------
do_fetch() {
    stage "STAGE: fetch base ISO"
    require_cmds curl sha256sum
    bash build/fetch-base.sh "$BASE_ISO"
    log "disk after fetch: $(disk "$WORK")"
}

do_extract() {
    stage "STAGE: extract ISO tree + boot blobs"
    require_cmds python3 cp find
    [ -f "$BASE_ISO" ] || fail "base ISO missing — run 'build.sh fetch' first"
    rm -rf "$ISO_SRC"; mkdir -p "$ISO_SRC" "$ISOMNT"

    if mount -o loop,ro "$BASE_ISO" "$ISOMNT" 2>/dev/null; then
        log "loop-mounted base ISO; copying ISO tree including the live squashfs"
        ( cd "$ISOMNT" && find . -type f -print0 \
            | xargs -0 cp -a --parents --target-dir "$ISO_SRC" )
        umount "$ISOMNT"
    else
        log "loop mount unavailable — falling back to full xorriso extraction"
        require_cmds xorriso
        xorriso -osirrox on -indev "$BASE_ISO" -extract / "$ISO_SRC"
    fi
    rmdir "$ISOMNT" 2>/dev/null || true

    extract_iso_blobs
    # the base ISO has served its purpose — reclaim ~4.7GB
    rm -f "$BASE_ISO" "$BASE_ISO.sums" "$BASE_ISO.sha256-verified"
    log "ISO tree ready; disk: $(disk "$WORK")"
    ls "$ISO_SRC" | sed 's/^/    /'
}

do_unpack() {
    stage "STAGE: unsquashfs live rootfs"
    require_cmds unsquashfs
    local sq="$ISO_SRC/casper/filesystem.squashfs"
    if [ -f "$sq" ]; then
        unsquashfs -no-progress -force-uid 0 -force-gid 0 -d "$ROOTFS" "$sq"
        rm -f "$sq"           # we will write a fresh one; reclaim ~3.2GB now
    else
        unsquashfs -no-progress -force-uid 0 -force-gid 0 -d "$ROOTFS" \
            /dev/null 2>/dev/null || true
        # tree came from loop-mount path (no squashfs present): nothing to do
        log "no squashfs in tree (loop-mount path) — rootfs must exist already"
        [ -d "$ROOTFS" ] || fail "no rootfs and no squashfs to unpack"
    fi
    log "rootfs unpacked; disk: $(disk "$WORK")"
}

do_overlay() {
    stage "STAGE: overlay FeatherOS files + branding"
    require_cmds python3
    cp -a build/overlay/. "$ROOTFS/"

    local conv=""
    command -v magick >/dev/null && conv="magick" || conv="convert"
    require_cmds "$conv"

    # backgrounds
    install -D -m 0644 assets/wallpapers/eiderdown.png "$ROOTFS/usr/share/backgrounds/eiderdown.png"
    install -D -m 0644 assets/greeter/greeter-bg.png   "$ROOTFS/usr/share/backgrounds/feather-greeter.png"

    # plymouth theme art
    local pdir="$ROOTFS/usr/share/plymouth/themes/feather"
    mkdir -p "$pdir"
    cp -f assets/plymouth/boot-bg.png "$pdir/bg.png"
    "$conv" assets/branding/feather-logo.png -resize 256x256 "$pdir/logo.png"

    # hicolor icons from the single logo source
    local s
    for s in 16 24 32 48 64 128 256; do
        install -D -m 0644 assets/branding/feather-logo.png \
            "$ROOTFS/usr/share/icons/hicolor/${s}x${s}/apps/feather-logo.png"
        "$conv" assets/branding/feather-logo.png -resize "${s}x${s}" \
            "$ROOTFS/usr/share/icons/hicolor/${s}x${s}/apps/feather-logo.png"
    done
    install -D -m 0644 assets/branding/feather-logo.png "$ROOTFS/usr/share/pixmaps/feather-logo.png"
    "$conv" assets/branding/feather-logo.png -resize 128x128 "$ROOTFS/usr/share/pixmaps/feather-logo.png"
    install -D -m 0644 assets/branding/feather-logo.png "$ROOTFS/usr/share/featheros/logo/feather-logo.png"

    # network for the chroot (preserve the original resolv.conf symlink)
    if [ -L "$ROOTFS/etc/resolv.conf" ]; then
        printf '%s' "$(readlink "$ROOTFS/etc/resolv.conf")" > "$WORK/resolv.link"
    else
        : > "$WORK/resolv.link"
    fi
    rm -f "$ROOTFS/etc/resolv.conf"
    cp -L /etc/resolv.conf "$ROOTFS/etc/resolv.conf"

    # no service restarts inside the chroot
    printf '#!/bin/sh\nexit 101\n' > "$ROOTFS/usr/sbin/policy-rc.d"
    chmod 0755 "$ROOTFS/usr/sbin/policy-rc.d"

    # pass build options in
    printf '%s' "$SLIM" > "$ROOTFS/tmp/feather-slim"
    cp -f build/chroot-inner.sh "$ROOTFS/tmp/feather-chroot-inner.sh"
}

do_customize() {
    stage "STAGE: chroot customization (desktop swap, apps, initrd)"
    mount_chroot
    chroot "$ROOTFS" /usr/bin/env -i \
        HOME=/root TERM="${TERM:-xterm}" PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        DEBIAN_FRONTEND=noninteractive \
        bash /tmp/feather-chroot-inner.sh
    umount_chroot

    # restore runtime state
    rm -f "$ROOTFS/usr/sbin/policy-rc.d" "$ROOTFS/tmp/feather-chroot-inner.sh" \
          "$ROOTFS/tmp/feather-slim" "$ROOTFS/etc/resolv.conf"
    local link; link="$(cat "$WORK/resolv.link")"
    if [ -n "$link" ]; then ln -s "$link" "$ROOTFS/etc/resolv.conf"; fi

    rm -rf "$ROOTFS/run/user"/* 2>/dev/null || true
    log "customization done; disk: $(disk "$WORK")"
}

do_repack() {
    stage "STAGE: trim + re-squash rootfs + patch ISO tree"
    require_cmds mksquashfs mdir mcopy md5sum

    # casper metadata
    chroot "$ROOTFS" dpkg-query -W -f='${Package} ${Version}\n' | sort \
        > "$ISO_SRC/casper/filesystem.manifest"
    grep -Ev '^(casper|ubiquity|ubiquity-)' "$ISO_SRC/casper/filesystem.manifest" \
        > "$ISO_SRC/casper/filesystem.manifest-desktop" || true
    du -sx --block-size=1 "$ROOTFS" | cut -f1 > "$ISO_SRC/casper/filesystem.size"
    log "rootfs size: $(du -sh "$ROOTFS" | cut -f1)"

    log "squashing rootfs (zstd)…"
    rm -f "$ISO_SRC/casper/filesystem.squashfs"
    mksquashfs "$ROOTFS" "$ISO_SRC/casper/filesystem.squashfs" \
        -noappend -no-progress -comp zstd -Xcompression-level 15 -b 1M

    # free ~10GB before the ISO build
    rm -rf "$ROOTFS"
    log "squashfs written; disk: $(disk "$WORK")"

    # release identity inside the image tree (files from the ISO are 444 —
    # remove then recreate rather than truncating in place)
    rm -f "$ISO_SRC/.disk/info"
    echo "FeatherOS 6.1 (Eiderdown) — Release $FEATHER_ARCH" > "$ISO_SRC/.disk/info"
    [ -f "$ISO_SRC/README.diskdefines" ] && \
        sed -i 's/Ubuntu 22\.04[^"]*/FeatherOS 6.1 (Eiderdown)/g; s/Ubuntu/FeatherOS/g' \
            "$ISO_SRC/README.diskdefines" || true

    # boot menu branding (keep kernel cmdline + paths untouched)
    local f
    for f in "$ISO_SRC"/boot/grub/grub.cfg "$ISO_SRC"/boot/grub/loopback.cfg \
             "$ISO_SRC"/isolinux/*.cfg; do
        [ -f "$f" ] || continue
        sed -i -E 's/(menuentry[[:space:]]+"[^"]*)Ubuntu([^"]*")/\1FeatherOS 6.1\2/g;
                   s/Try or install Ubuntu/Try or install FeatherOS 6.1/g' "$f"
        log "patched $(basename "$f")"
    done

    # efi.img: make the embedded grub.cfg find the media by file (the original
    # searched by ISO uuid which changes on rebuild). Uses mtools, no mounting.
    local p
    for p in EFI/ubuntu/grub.cfg EFI/boot/grub.cfg; do
        if mcopy -i "$WORK/efi.img" -n "::$p" "$WORK/efi-grub.cfg" 2>/dev/null; then
            printf 'search --file --set=root --no-floppy /boot/grub/grub.cfg\nset prefix=($root)'"'"'/boot/grub'"'"'\nconfigfile $prefix/grub.cfg\n' \
                > "$WORK/efi-grub.cfg.new"
            mcopy -i "$WORK/efi.img" -o "$WORK/efi-grub.cfg.new" "::$p"
            log "patched $p inside efi.img"
        fi
    done

    # refresh md5 manifest of the ISO tree
    ( cd "$ISO_SRC" && rm -f md5sum.txt \
        && find . -type f ! -path './md5sum.txt' -print0 | sort -z \
        | xargs -0 md5sum > md5sum.txt )
    log "ISO tree patched + md5sum.txt refreshed"
}

do_iso() {
    stage "STAGE: building hybrid ISO (BIOS + UEFI)"
    require_cmds xorriso
    local out="$OUTDIR/$ISO_NAME"
    rm -f "$out"
    # Recipe reproduces Ubuntu jammy's hybrid layout: grub BIOS via El Torito
    # (/boot/grub/i386-pc/eltorito.img from the tree), MBR template + EFI
    # partition reused from the original ISO, EFI boot via appended partition.
    ( cd "$ISO_SRC" && xorriso -as mkisofs -r \
        -V "$ISO_VOLID" \
        -o "$out" \
        --grub2-mbr "$WORK/boot_hybrid.img" \
        -partition_offset 16 \
        --mbr-force-bootable \
        -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b "$WORK/efi.img" \
        -appended_part_as_gpt \
        -iso_mbr_part_type a2a0d0ebe5b9334487c068b6b72699c7 \
        -c /boot.catalog \
        -b /boot/grub/i386-pc/eltorito.img \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        --grub2-boot-info \
        -eltorito-alt-boot \
        -e '--interval:appended_partition_2:::' \
        -no-emul-boot \
        . )
    log "ISO built: $out ($(du -h "$out" | cut -f1))"

    {
        echo "FeatherOS $FEATHER_PRETTY"
        echo "status:     complete $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
        echo "base:       Ubuntu $FEATHER_BASE_RELEASE LTS ($FEATHER_BASE_CODENAME)"
        echo "workdir:    $WORK"
        echo "sha256:     $(sha256sum "$out" | awk '{print $1}')"
        echo "packages:   $(wc -l < "$ISO_SRC/casper/filesystem.manifest")"
    } > "$OUTDIR/build-info.txt"

    [ -n "${SUDO_USER:-}" ] && chown -R "$SUDO_USER" "$OUTDIR" || true
    stage "DONE — $out"
}

case "$MODE" in
    fetch)     do_fetch ;;
    extract)   do_extract ;;
    unpack)    do_unpack ;;
    overlay)   do_overlay ;;
    customize) do_customize ;;
    repack)    do_repack ;;
    iso)       do_iso ;;
    all)
        do_fetch
        do_extract
        do_unpack
        do_overlay
        do_customize
        do_repack
        do_iso
        ;;
    *) fail "unknown mode: $MODE (use: all|fetch|extract|unpack|overlay|customize|repack|iso)" ;;
esac
