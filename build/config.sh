#!/bin/bash
# ---------------------------------------------------------------------------
# FeatherOS build configuration — single source of truth for the identity.
# ---------------------------------------------------------------------------
# shellcheck shell=bash

export FEATHER_VERSION="6.1"
export FEATHER_CODENAME="eiderdown"
export FEATHER_PRETTY="FeatherOS 6.1 (Eiderdown)"
export FEATHER_BASE_RELEASE="22.04"
export FEATHER_BASE_CODENAME="jammy"
export FEATHER_ARCH="amd64"

# Output ISO name (mirrors Ubuntu naming style)
export ISO_NAME="FeatherOS-6.1-eiderdown-desktop-amd64.iso"
# ISO9660 volume label (max 32 chars)
export ISO_VOLID="FeatherOS 6.1 amd64"

# GitHub repo used for release publishing + os-release URLs
export GITHUB_REPO="RetroByte-Laboratories/FeatherOS"

# Live session identity (written into /etc/casper.conf)
export LIVE_USER="feather"
export LIVE_HOST="featheros"

# Base ISO download candidates, tried in order. Integrity is always checked
# against the SHA256SUMS file that ships next to each of these.
BASE_ISO_URLS=(
  "https://releases.ubuntu.com/22.04/ubuntu-22.04.5-desktop-amd64.iso"
  "https://releases.ubuntu.com/22.04/ubuntu-22.04-desktop-amd64.iso"
  "https://old-releases.ubuntu.com/releases/22.04/ubuntu-22.04.5-desktop-amd64.iso"
  "https://old-releases.ubuntu.com/releases/22.04/ubuntu-22.04-desktop-amd64.iso"
  "https://cdimage.ubuntu.com/ubuntu/releases/22.04/release/ubuntu-22.04.5-desktop-amd64.iso"
)
