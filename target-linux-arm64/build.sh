#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 The TotalDrop Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Build TotalDrop rendezvous and relay binaries for ARM64 (aarch64) Linux.
# Supports native builds on ARM64 hosts (Raspberry Pi 5, ARM64 NAS, Ampere)
# and cross-compilation from x86_64 when aarch64-linux-{gnu,musl}-gcc is installed.
#
# Usage:
#   ./target-linux-arm64/build.sh           # aarch64-unknown-linux-gnu (default)
#   ./target-linux-arm64/build.sh --musl    # aarch64-unknown-linux-musl (static)
#   ./target-linux-arm64/build.sh --gnu     # aarch64-unknown-linux-gnu
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TARGET="aarch64-unknown-linux-gnu"
for arg in "$@"; do
  case "${arg}" in
    --musl) TARGET="aarch64-unknown-linux-musl" ;;
    --gnu)  TARGET="aarch64-unknown-linux-gnu" ;;
    -h|--help)
      echo "usage: build.sh [--gnu | --musl]"
      exit 0
      ;;
    *)
      echo "unknown option: ${arg}" >&2
      echo "usage: build.sh [--gnu | --musl]" >&2
      exit 2
      ;;
  esac
done

cd "${REPO_ROOT}"

if [[ -z "${RUSTUP_TOOLCHAIN:-}" ]] && ! rustup which cargo >/dev/null 2>&1; then
  export RUSTUP_TOOLCHAIN="stable"
fi

if ! rustup target list --installed | grep -qx "${TARGET}"; then
  echo "error: Rust target ${TARGET} is not installed for active toolchain." >&2
  echo "hint:  rustup target add ${TARGET}" >&2
  exit 1
fi

HOST_ARCH="$(uname -m)"
if [[ "${HOST_ARCH}" != "aarch64" && "${HOST_ARCH}" != "arm64" ]]; then
  if [[ "${TARGET}" == "aarch64-unknown-linux-gnu" ]]; then
    if ! command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
      echo "error: cross-compiling to ${TARGET} requires aarch64-linux-gnu-gcc on ${HOST_ARCH}." >&2
      exit 1
    fi
    export CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc
    export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc
  else
    if command -v aarch64-linux-musl-gcc >/dev/null 2>&1; then
      export CC_aarch64_unknown_linux_musl=aarch64-linux-musl-gcc
      export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=aarch64-linux-musl-gcc
    elif command -v clang >/dev/null 2>&1 && command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
      export CC_aarch64_unknown_linux_musl=clang
      export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=aarch64-linux-gnu-gcc
    else
      echo "error: cross-compiling to ${TARGET} requires aarch64-linux-musl-gcc on ${HOST_ARCH}." >&2
      exit 1
    fi
  fi
fi

cargo build \
  --release \
  --locked \
  --target "${TARGET}" \
  -p totaldrop-rendezvous \
  -p totaldrop-relay

OUT_DIR="${REPO_ROOT}/dist/linux-arm64/${TARGET}"
mkdir -p "${OUT_DIR}"
install -m 0755 "${REPO_ROOT}/target/${TARGET}/release/totaldrop-rendezvous" "${OUT_DIR}/totaldrop-rendezvous"
install -m 0755 "${REPO_ROOT}/target/${TARGET}/release/totaldrop-relay" "${OUT_DIR}/totaldrop-relay"

(
  cd "${OUT_DIR}"
  sha256sum totaldrop-rendezvous totaldrop-relay | tee SHA256SUMS
)
echo "built arm64 server binaries in ${OUT_DIR}"
