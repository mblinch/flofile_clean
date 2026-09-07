#!/usr/bin/env bash
# Idempotent Cloud Agent setup for the quick_cap Flutter app.
# Installs the Linux desktop toolchain and a pinned Flutter SDK, then fetches
# Dart/Flutter dependencies. Safe to re-run.
set -euo pipefail

FLUTTER_VERSION="3.47.2"
FLUTTER_HOME="/opt/flutter-sdk"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Installing Linux desktop build dependencies"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
# clang/cmake/ninja + GTK for Flutter Linux desktop; libstdc++-14-dev matches the
# GCC toolchain clang selects on Ubuntu 24.04 so C++ linking succeeds.
sudo apt-get install -y -qq \
  clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev \
  g++ libstdc++-14-dev \
  curl xz-utils \
  xdotool imagemagick x11-utils

echo "==> Installing Flutter ${FLUTTER_VERSION} into ${FLUTTER_HOME}"
if [ ! -x "${FLUTTER_HOME}/bin/flutter" ]; then
  sudo mkdir -p "${FLUTTER_HOME}"
  sudo chown "$(id -u):$(id -g)" "${FLUTTER_HOME}"
  tarball="/tmp/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  curl -fsSL -o "${tarball}" \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  tar xf "${tarball}" -C "${FLUTTER_HOME}" --strip-components=1
  rm -f "${tarball}"
else
  echo "    Flutter already present, skipping download"
fi

# Persist PATH for interactive shells and this script.
export PATH="${FLUTTER_HOME}/bin:${PATH}"
if ! grep -q "${FLUTTER_HOME}/bin" "${HOME}/.bashrc" 2>/dev/null; then
  echo "export PATH=\"${FLUTTER_HOME}/bin:\$PATH\"" >> "${HOME}/.bashrc"
fi

git config --global --add safe.directory "${FLUTTER_HOME}" || true

echo "==> Configuring Flutter"
flutter config --no-analytics >/dev/null 2>&1 || true
flutter config --enable-linux-desktop >/dev/null 2>&1 || true
flutter --version

echo "==> Fetching dependencies (flutter pub get)"
cd "${REPO_ROOT}"
flutter pub get

echo "==> Setup complete"
