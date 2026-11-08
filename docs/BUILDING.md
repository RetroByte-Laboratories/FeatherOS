# Building FeatherOS 6.1 “Eiderdown”

FeatherOS is a **remaster** of the official `ubuntu-22.04.*-desktop-amd64`
image: the live rootfs is unpacked, given a full desktop transplant
(GNOME Shell → GNOME Flashback + Metacity, GDM → LightDM, snapd → nothing),
rebranded, re-squashed and repacked as a BIOS+UEFI hybrid ISO with the
original signed shim/GRUB boot blobs intact.

## Requirements

- Any Debian/Ubuntu host (CI uses `ubuntu-latest` = 24.04) with `sudo`
- **~30 GB** free disk for the build area, **~8 GB** RAM recommended
- Network access to `releases.ubuntu.com`, `archive.ubuntu.com`,
  `packages.mozilla.org`
- Tools (installed automatically in CI):
  `xorriso squashfs-tools mtools imagemagick python3 wget curl`
  (plus `qemu-system-x86 ovmf` for the optional smoke test)

## The stages

```bash
sudo bash build/build.sh all      # everything, in order
```

or stage by stage (useful when iterating):

| Stage       | What it does                                                          |
|-------------|-----------------------------------------------------------------------|
| `fetch`     | downloads the base ISO, verifies it against upstream `SHA256SUMS`     |
| `extract`   | `xorriso -osirrox` extracts the ISO tree; pulls out the hybrid MBR + EFI partition blobs from the original image |
| `unpack`    | `unsquashfs` the live rootfs                                          |
| `overlay`   | copies `build/overlay/` + branding assets into the rootfs             |
| `customize` | chroots and runs `build/chroot-inner.sh`: apt removes GNOME Shell/GDM/snapd, installs Flashback+Metacity+LightDM+Firefox+apps, compiles schemas, activates Plymouth, regenerates the initrd (bakes `casper.conf`) |
| `repack`    | re-squashfs (zstd), updates casper manifests, patches boot menus, patches `efi.img` grub.cfg (file-based media search via mtools), refreshes `md5sum.txt` |
| `iso`       | xorriso hybrid build: BIOS via `/boot/grub/i386-pc/eltorito.img`, UEFI via the appended EFI partition, MBR template reused from the original ISO |

Useful environment variables:

```bash
FEATHER_WORK=/path   # work dir (needs ≥20 GB; defaults to /mnt, then $HOME)
SLIM_BUILD=1         # omit LibreOffice / GIMP / Thunderbird
FEATHER_BASE_ISO=/path/to.iso   # use a pre-downloaded base ISO
```

Output: `out/FeatherOS-6.1-eiderdown-desktop-amd64.iso` + `out/build-info.txt`.

## CI (GitHub Actions)

`.github/workflows/build-iso.yml` builds everything on a runner:

- triggers: manual (`workflow_dispatch`, with slim/smoke/publish toggles) and
  `v*` tag pushes
- the ISO is **split into 1900 MB parts** (GitHub caps release assets at
  2 GiB) and published with `SHA256SUMS` via `build/publish-release.sh`
- the optional QEMU smoke test boots the ISO under TCG for both BIOS and
  UEFI (OVMF), screenshotting every 25 s into the `smoke-screenshots` artifact;
  it fails if QEMU/OVMF cannot start or either mode yields no screenshots
- the manual workflow can also download an existing release, verify its split
  asset checksums, reassemble the ISO, and QEMU-test it without rebuilding or
  publishing another release

To produce a release: push a tag or run the workflow with *Publish release*.
To test an existing release: run the workflow with *Test existing release*
selected, provide its tag, and keep *Boot-test the ISO* enabled.

## Why this approach

Remastering the official ISO (rather than debootstrap) means FeatherOS keeps:

- the exact Ubuntu 22.04 kernel, firmware set and driver stack,
- the signed shim/GRUB blobs → **Secure Boot keeps working**,
- the Ubiquity installer and casper live-boot machinery (battle-tested),
- full compatibility with every jammy how-to and package.

The result boots identically to Ubuntu — same casper flow, same installer —
with FeatherOS branding and a featherweight desktop on top.
