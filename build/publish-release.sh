#!/bin/bash
# ---------------------------------------------------------------------------
# publish-release.sh — split the built ISO into <2GiB release-asset parts,
# write SHA256SUMS + release notes, create/patch the GitHub release and
# upload the assets. Uses the preinstalled `gh` CLI.
# ---------------------------------------------------------------------------
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=build/config.sh
source build/config.sh

log()  { printf '\n\033[1;35m[feather-release]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[feather-release] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

command -v gh >/dev/null || fail "gh CLI not found"
[ -n "${GH_TOKEN:-}" ] || [ -n "${GITHUB_TOKEN:-}" ] || fail "no GH_TOKEN in env"

ISO="out/$ISO_NAME"
[ -f "$ISO" ] || fail "ISO not found at $ISO — run the build first"

if [ "${GITHUB_REF_TYPE:-}" = "tag" ]; then
    TAG="$GITHUB_REF_NAME"
else
    TAG="v${FEATHER_VERSION}-${FEATHER_CODENAME}"
fi

# ---- split + checksums ---------------------------------------------------
log "splitting ISO into release-asset parts (1900M each)"
rm -f out/"$ISO_NAME".part-* out/SHA256SUMS
split -b 1900M -d "$ISO" "out/$ISO_NAME.part-"
( cd out && sha256sum "$ISO_NAME".part-* > SHA256SUMS )

# ---- release notes -------------------------------------------------------
cat > out/RELEASE_NOTES.md <<EOF
# FeatherOS $FEATHER_VERSION — “$FEATHER_CODENAME”

Built from commit \`$SHORT\` on $(date -u '+%Y-%m-%d %H:%M UTC').

A lightweight classic-desktop Linux OS based on **Ubuntu $FEATHER_BASE_RELEASE LTS**
— GNOME Flashback + Metacity + LightDM, custom Plymouth splash, zero snaps,
Firefox from Mozilla's apt repo, and the full Ubuntu 22.04 application set.

## Download

The ISO (~$(du -h "$ISO" | cut -f1)) is attached as split parts to stay under
GitHub's per-file asset limit. Join and verify:

\`\`\`bash
cat $ISO_NAME.part-* > $ISO_NAME
sha256sum -c SHA256SUMS
\`\`\`

Then write to USB with \`dd\`, balenaEtcher or Rufus. The image boots on both
BIOS and UEFI (including Secure Boot) and contains the classic Ubiquity
installer — “Install FeatherOS” appears right on the live desktop.

## Highlights

- GNOME Flashback session with Metacity (“Feather” Yaru-style window theme)
- LightDM with a FeatherOS greeter background
- Custom “feather” Plymouth boot splash
- Eiderdown wallpaper + FeatherOS branding end to end
- No snapd — apt and .deb only
- Live session autologins as \`feather\`; installed systems get a normal login

## Verification

See \`SHA256SUMS\`. Build metadata: \`build-info.txt\` artifact of the CI run.
EOF

# ---- publish -------------------------------------------------------------
log "ensuring release $TAG exists"
gh release view "$TAG" -R "$GITHUB_REPO" >/dev/null 2>&1 \
    || gh release create "$TAG" \
        -R "$GITHUB_REPO" \
        --title "FeatherOS $FEATHER_VERSION — $FEATHER_CODENAME" \
        --notes-file out/RELEASE_NOTES.md

log "uploading assets"
( cd out && gh release upload "$TAG" -R "$GITHUB_REPO" \
    "$ISO_NAME".part-* SHA256SUMS --clobber )

log "release $TAG published: https://github.com/$GITHUB_REPO/releases/tag/$TAG"
