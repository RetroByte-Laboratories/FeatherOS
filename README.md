# FeatherOS 6.1 — “Eiderdown”

![Build FeatherOS ISO](https://github.com/RetroByte-Laboratories/FeatherOS/actions/workflows/build-iso.yml/badge.svg)

🌐 **[RetroByte Laboratories](https://retrobyte-laboratories.pages.dev/)** · The studio site and project home for [FeatherOS 6.1 Eiderdown](https://retrobyte-laboratories.pages.dev/featheros/).

**FeatherOS** is a lightweight, classic-desktop Linux distribution built on the
solid bones of **Ubuntu 22.04 LTS (jammy)** — but tuned to *feel* like using
Ubuntu 22.04 at its best: fast, familiar and feather-light.

Instead of GNOME Shell it ships the traditional **GNOME Flashback** session with
the **Metacity** window manager: real title bars, a classic panel, snappy
window switching, and a desktop that idles comfortably in a few hundred
megabytes of RAM. Modern under the hood, classic at heart.

| | |
|---|---|
| **Full name** | FeatherOS 6.1 “Eiderdown” |
| **Base** | Ubuntu 22.04 LTS (“jammy”), same kernel + installer lineage |
| **Desktop** | GNOME Flashback + Metacity, Yaru theme, custom “Feather” window theme |
| **Display manager** | LightDM (GTK greeter) |
| **Boot splash** | Custom Plymouth “feather” theme |
| **Browser** | Firefox (official Mozilla deb, no snap) |
| **Apps** | Files, Terminal, Text Editor, Calculator, Image Viewer, Document Viewer, System Monitor, Disks, Archive Manager, VLC, Thunderbird, LibreOffice (Writer/Calc/Impress), GIMP |
| **Snaps** | None. Zero. apt + .deb only |
| **Installer** | Ubiquity (the classic Ubuntu installer) |

<p align="center">
  <img src="assets/wallpapers/eiderdown.png" alt="FeatherOS 6.1 Eiderdown wallpaper" width="600"/>
  <br/><em>The default “Eiderdown” wallpaper</em>
</p>

---

## Download

Grab the latest ISO from the
**[Releases page](https://github.com/RetroByte-Laboratories/FeatherOS/releases)**
(built automatically by CI):

- `FeatherOS-6.1-eiderdown-desktop-amd64.iso` — bootable hybrid image
  (BIOS **and** UEFI, Secure Boot compatible), released as split parts with a
  `SHA256SUMS` file.

```bash
# 1. join the parts
cat FeatherOS-6.1-eiderdown-desktop-amd64.iso.part-* > FeatherOS-6.1-eiderdown-desktop-amd64.iso

# 2. verify
sha256sum -c SHA256SUMS

# 3. write to USB (replace sdX — this destroys data!)
sudo dd if=FeatherOS-6.1-eiderdown-desktop-amd64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

…or just use [balenaEtcher](https://etcher.balena.io/) / Rufus / Ventoy.

**Live session:** boots straight into an autologged-in `feather` user with an
*Install FeatherOS* icon on the desktop. **Installed system:** LightDM greeter,
your own user, no autologin.

## What it feels like

- The Ubuntu 22.04 you know — Yaru theming, Ubuntu fonts, same kernel,
  same installer — minus GNOME Shell, minus snaps, minus the drag.
- Classic two-panel layout: application menu + clock on top, window list +
  workspace switcher at the bottom.
- Real Metacity title bars with minimize / maximize / close, keyboard driven,
  instantly responsive on old hardware and virtual machines.
- Feather-purple boot splash, login screen and “Eiderdown” wallpaper.

## Release history

| Version | Codename | Note |
|---------|----------------|-------------------------------------------------|
| 4.4 | Puffin | first downloadable builds |
| 8.4 | Kerala Kite | Ubuntu 18.04-era experiments |
| 14.05 | Bit | Ubuntu 14.04-era experiments |
| **6.1** | **Eiderdown** | **this release — Ubuntu 22.04 base, Flashback/Metacity** |

## Building it yourself

FeatherOS is a fully reproducible remaster of the official Ubuntu 22.04 desktop
image: download → extract → customize the rootfs in a chroot → re-squash →
rebuild the hybrid ISO. Everything is scripted:

```bash
sudo bash build/build.sh all
```

See **[docs/BUILDING.md](docs/BUILDING.md)** for requirements, stage-by-stage
detail and CI instructions.

## Repository layout

```
assets/                 branding art (wallpaper, logo, splash, greeter)
build/
  config.sh             version / mirror / naming configuration
  build.sh              main orchestrator (fetch → extract → customize → iso)
  fetch-base.sh         downloads + checksum-verifies the Ubuntu 22.04 base ISO
  chroot-inner.sh       runs inside the rootfs: swap desktop, apps, branding
  smoke-test.sh         boots the ISO in QEMU and screenshots it (BIOS + UEFI)
  publish-release.sh    splits the ISO and publishes a GitHub release
  overlay/              files copied verbatim into the OS rootfs
docs/BUILDING.md        build documentation
.github/workflows/      CI: ISO build + static checks
```

## FAQ

**Why Ubuntu 22.04 as a base?** It’s the sweet spot: mature 5.15 kernel,
classic Ubiquity installer, Yaru look, and it still feels like “real Ubuntu”.
FeatherOS tracks the jammy archives (falling back to `old-releases` after
upstream EOL) so apt keeps working for years.

**Why Metacity / Flashback?** It is the lightest full-featured GTK desktop that
keeps the classic Ubuntu *workflow* — panels, menus, real window management —
while still running modern GNOME apps and the Yaru theme.

**Snaps?** No. Firefox comes straight from Mozilla’s official apt repository.

**Can I use it daily?** That’s the idea. It behaves exactly like an Ubuntu
22.04 install: same apt, same drivers, same hardware support.

---

FeatherOS is an independent community project by
**RetroByte Laboratories** and is not affiliated with Canonical Ltd.
Ubuntu is a trademark of Canonical Ltd. Base system packages remain under
their respective licenses.
