#!/bin/bash
# ---------------------------------------------------------------------------
# chroot-inner.sh — runs INSIDE the Ubuntu 22.04 live rootfs as root.
# Swaps GNOME Shell/GDM/snapd for GNOME Flashback + Metacity + LightDM,
# installs the FeatherOS app set, wires up branding, regenerates the initrd.
# ---------------------------------------------------------------------------
set -euo pipefail

SLIM="$(cat /tmp/feather-slim 2>/dev/null || echo 0)"
log()  { printf '\n\033[1;36m[feather-chroot]\033[0m %s\n' "$*"; }
note() { printf '\033[0;33m[feather-chroot]  ·\033[0m %s\n' "$*"; }

export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C.UTF-8

# ===========================================================================
# 0. apt sources — jammy lives on archive.ubuntu.com until EOL (2027-04),
#    then old-releases.ubuntu.com. Pick whichever actually serves dists.
# ===========================================================================
log "configuring apt sources"
if wget -q --spider "http://old-releases.ubuntu.com/ubuntu/dists/jammy/Release" 2>/dev/null; then
    MIRROR="http://old-releases.ubuntu.com/ubuntu/"
else
    MIRROR="http://archive.ubuntu.com/ubuntu/"
fi
cat > /etc/apt/sources.list <<EOF
deb $MIRROR jammy main restricted universe multiverse
deb $MIRROR jammy-updates main restricted universe multiverse
deb $MIRROR jammy-security main restricted universe multiverse
deb $MIRROR jammy-backports main restricted universe multiverse
EOF
rm -f /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources 2>/dev/null || true
apt-get update -qq
note "using mirror: $MIRROR"

# ===========================================================================
# 1. protect packages we want to KEEP before purging metas
# ===========================================================================
log "pinning core apps as manual installs"
for p in \
    gnome-control-center nautilus gedit gnome-terminal gnome-calculator eog \
    evince gnome-system-monitor gnome-font-viewer gnome-disk-utility gnome-logs \
    file-roller baobab yelp thunderbird network-manager-gnome \
    gnome-settings-daemon gnome-screenshot \
    yaru-theme-gtk yaru-theme-icon yaru-theme-sound \
    xorg xserver-xorg xserver-xorg-core xserver-xorg-video-all xserver-xorg-input-all \
    casper ubiquity ubiquity-frontend-gtk ubiquity-casper \
    plymouth xdg-user-dirs ubuntu-docs; do
    apt-mark manual "$p" >/dev/null 2>&1 || true
done

# ===========================================================================
# 2. remove GNOME Shell, GDM, the snap stack and Ubuntu meta packages
# ===========================================================================
log "removing GNOME Shell / GDM / snapd stack"
echo "lightdm shared/default-x-display-manager select lightdm" | debconf-set-selections
apt-get purge -y --allow-remove-essential \
    'ubuntu-desktop*' 'ubuntu-settings' \
    'gnome-shell*' 'gdm3' 'ubuntu-session' 'gnome-session-bin' 'mutter-*' \
    'snapd*' 'lxd*' 'gnome-software-plugin-snap' \
    'firefox*' \
    'ubuntu-advantage-tools' 'ubuntu-pro-client' \
    || true
apt-get autoremove --purge -y || true
rm -rf /snap /var/snap /var/lib/snapd /root/snap /home/*/snap 2>/dev/null || true

# ===========================================================================
# 3. install the FeatherOS desktop: GNOME Flashback + Metacity + LightDM
# ===========================================================================
log "installing GNOME Flashback (Metacity) + LightDM"
apt-get install -y \
    gnome-session-flashback gnome-flashback gnome-flashback-common \
    gnome-panel metacity \
    lightdm lightdm-gtk-greeter
apt-get install -y gnome-applets alacarte || true
note "session desktop file: /usr/share/xsessions/featheros.desktop (FeatherOS)"

# ===========================================================================
# 4. Firefox — official Mozilla deb repository (no snap)
# ===========================================================================
log "installing Firefox from Mozilla apt repo"
install -d -m 0755 /etc/apt/keyrings
wget -qO /etc/apt/keyrings/packages.mozilla.org.asc \
    https://packages.mozilla.org/apt/repo-signing-key.gpg
cat > /etc/apt/sources.list.d/mozilla.list <<'EOF'
deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main
EOF
cat > /etc/apt/preferences.d/mozilla <<'EOF'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000
EOF
apt-get update -qq
apt-get install -y firefox

# ===========================================================================
# 5. application set
# ===========================================================================
log "installing application set"
apt-get install -y vlc || true
apt-get install -y gnome-software || true
if [ "$SLIM" != "1" ]; then
    apt-get install -y libreoffice-writer libreoffice-calc libreoffice-impress \
        libreoffice-gtk3 || true
    apt-get install -y gimp || true
fi

# ===========================================================================
# 6. FeatherOS defaults & branding
# ===========================================================================
log "compiling GSettings system defaults (theme, wallpaper, metacity)"
glib-compile-schemas /usr/share/glib-2.0/schemas/

log "setting default display manager + enabling live-session bootstrap"
echo /usr/bin/lightdm > /etc/X11/default-display-manager
systemctl enable feather-live-init.service 2>/dev/null || \
    ln -sf /etc/systemd/system/feather-live-init.service \
        /etc/systemd/system/graphical.target.wants/feather-live-init.service

log "activating Plymouth 'feather' theme"
update-alternatives --install \
    /usr/share/plymouth/themes/default.plymouth default.plymouth \
    /usr/share/plymouth/themes/feather/feather.plymouth 300 >/dev/null
update-alternatives --set default.plymouth \
    /usr/share/plymouth/themes/feather/feather.plymouth

# ===========================================================================
# 7. regenerate initrd — bakes casper.conf (live user/host) + plymouth art
# ===========================================================================
log "regenerating initramfs (casper.conf + plymouth theme)"
update-initramfs -k all -u

# ===========================================================================
# 8. trim the fat — FeatherOS stays lean: drop non-English translations,
#    localized man pages and bundled docs (keeps locale-gen data intact so
#    users can still generate any locale after install)
# ===========================================================================
log "trimming translations / man pages / bundled docs"
find /usr/share/locale -mindepth 1 -maxdepth 1 ! -name 'en*' ! -name 'locale.alias' \
    -exec rm -rf {} + 2>/dev/null || true
find /usr/share/man -mindepth 1 -maxdepth 1 ! -name 'man*' -exec rm -rf {} + 2>/dev/null || true
rm -rf /usr/share/doc/* /usr/share/doc-base/* 2>/dev/null || true
find /usr/share/help -mindepth 1 -maxdepth 1 ! -name 'C' -exec rm -rf {} + 2>/dev/null || true
rm -rf /usr/share/gnome-help/* 2>/dev/null || true

# ===========================================================================
# 9. cleanup for a tidy squashfs
# ===========================================================================
log "cleaning up"
apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb /var/cache/apt/*.bin \
       /var/lib/apt/lists/partial/* /tmp/* /var/tmp/* \
       /root/.bash_history /root/.wget-hsts /root/.cache 2>/dev/null || true
find /var/log -type f \( -name '*.gz' -o -name '*.1' -o -name '*.old' \) -delete 2>/dev/null || true
for f in /var/log/syslog /var/log/kern.log /var/log/auth.log /var/log/dpkg.log \
         /var/log/alternatives.log /var/log/bootstrap.log /var/log/fontconfig.log; do
    : > "$f" 2>/dev/null || true
done
: > /etc/machine-id 2>/dev/null || true

log "chroot customization complete"
note "installed packages: $(dpkg -l 2>/dev/null | grep -c '^ii' || true)"
