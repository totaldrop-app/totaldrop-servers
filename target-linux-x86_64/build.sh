#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 The TotalDrop Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Build TotalDrop rendezvous and relay binaries for x86_64 Linux.
#
# Usage:
#   ./target-linux-x86_64/build.sh           # x86_64-unknown-linux-gnu (default)
#   ./target-linux-x86_64/build.sh --musl    # x86_64-unknown-linux-musl (static)
#   ./target-linux-x86_64/build.sh --gnu     # x86_64-unknown-linux-gnu
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TARGET="x86_64-unknown-linux-gnu"
for arg in "$@"; do
  case "${arg}" in
    --musl) TARGET="x86_64-unknown-linux-musl" ;;
    --gnu)  TARGET="x86_64-unknown-linux-gnu" ;;
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

cargo build \
  --release \
  --locked \
  --target "${TARGET}" \
  -p totaldrop-rendezvous \
  -p totaldrop-relay

OUT_DIR="${REPO_ROOT}/dist/linux-x86_64/${TARGET}"
mkdir -p "${OUT_DIR}"
install -m 0755 "${REPO_ROOT}/target/${TARGET}/release/totaldrop-rendezvous" "${OUT_DIR}/totaldrop-rendezvous"
install -m 0755 "${REPO_ROOT}/target/${TARGET}/release/totaldrop-relay" "${OUT_DIR}/totaldrop-relay"

(
  cd "${OUT_DIR}"
  sha256sum totaldrop-rendezvous totaldrop-relay | tee SHA256SUMS
)
echo "built x86_64 server binaries in ${OUT_DIR}"
