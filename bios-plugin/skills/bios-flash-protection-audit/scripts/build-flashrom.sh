#!/usr/bin/env bash
# Build flashrom with the internal programmer (Intel PCH SPI, hardware
# sequencing) into ~/src/flashrom/build. Distro packages can be too old for a
# newer chipset (Ubuntu 22.04's 1.2 does not know Comet Lake), and Homebrew's
# Linux build ships without the internal programmer.
#
# Usage: build-flashrom.sh [tag]     (default v1.4.0)
# Installs build dependencies with apt (Debian/Ubuntu).
set -euo pipefail
tag=${1:-v1.4.0}
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
  git meson ninja-build pkg-config libpci-dev libusb-1.0-0-dev libftdi1-dev libjaylink-dev zlib1g-dev >/dev/null
mkdir -p ~/src && cd ~/src
[ -d flashrom ] || git clone -q --branch "$tag" --depth 1 https://github.com/flashrom/flashrom.git
cd flashrom
# Use the system meson/ninja; a Homebrew or pyenv python on PATH can shadow them.
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
meson setup build -Dprogrammer=internal -Dtests=disabled -Dman-pages=disabled -Ddocumentation=disabled >/dev/null
ninja -C build >/dev/null
./build/flashrom --version | head -1
