#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# Fetch the exact Clang 22 toolchain used by the build, plus the AOSP
# build-tools (bc/flex/bison) that the legacy Kbuild tree expects on PATH.
#
# The toolchain is the upstream LLVM release tarball, pinned by both size and
# SHA-256 so a re-tagged or swapped artifact is rejected instead of silently
# used. (GitHub publishes the same digest for the asset: sha256:df0e1ecf...)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${TOOLCHAIN_ROOT:-$ROOT/.work/toolchain}"
BUILDTOOLS_DIR="${BUILDTOOLS_ROOT:-$ROOT/.work/build-tools}"

LLVM_VERSION="22.1.8"
LLVM_TARBALL="LLVM-${LLVM_VERSION}-Linux-X64.tar.xz"
LLVM_URL="https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}/${LLVM_TARBALL}"
LLVM_SHA256="df0e1ecf16caf3489a272a5eea4eec9b0d82878f6477fa309504f918a0006384"
LLVM_SIZE=1938859476
CLANG_DIR="$DEST/llvm-$LLVM_VERSION"
BUILDTOOLS_COMMIT="f61cfbcb609173e1040753a2b9e8fbe8517343f9"

die() { echo "ERROR: $*" >&2; exit 1; }

mkdir -p "$DEST" "$(dirname "$BUILDTOOLS_DIR")"

if [[ ! -x "$CLANG_DIR/bin/clang" || ! -x "$CLANG_DIR/bin/ld.lld" ]]; then
  rm -rf "$CLANG_DIR"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/llvm-dl.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT
  echo "Downloading $LLVM_URL"
  curl -fL --retry 3 --retry-delay 5 --connect-timeout 30 \
    -o "$tmp/$LLVM_TARBALL" "$LLVM_URL"

  size="$(stat -c%s "$tmp/$LLVM_TARBALL")"
  [[ "$size" == "$LLVM_SIZE" ]] \
    || die "$LLVM_TARBALL is $size bytes, expected $LLVM_SIZE"
  echo "$LLVM_SHA256  $tmp/$LLVM_TARBALL" | sha256sum -c - \
    || die "$LLVM_TARBALL failed its SHA-256 pin"

  mkdir -p "$CLANG_DIR"
  tar -xJf "$tmp/$LLVM_TARBALL" -C "$CLANG_DIR" --strip-components=1
  rm -rf "$tmp"
  trap - EXIT

  # Compiler-rt runtimes, docs and the bundled python tree are not used by an
  # arm64 kernel build; dropping them keeps the CI cache manageable.
  rm -rf "$CLANG_DIR"/lib/clang/*/lib
  rm -rf "$CLANG_DIR"/share "$CLANG_DIR"/docs "$CLANG_DIR"/python3 "$CLANG_DIR"/lib/python3*
fi

if [[ ! -x "$BUILDTOOLS_DIR/path/linux-x86/bc" ]]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fL --retry 3 \
    "https://codeload.github.com/LineageOS/android_prebuilts_build-tools/tar.gz/$BUILDTOOLS_COMMIT" \
    -o "$tmp/build-tools.tar.gz"
  mkdir -p "$BUILDTOOLS_DIR"
  tar -xzf "$tmp/build-tools.tar.gz" -C "$BUILDTOOLS_DIR" --strip-components=1
  rm -rf "$tmp"
  trap - EXIT
fi

export PATH="$CLANG_DIR/bin:$BUILDTOOLS_DIR/path/linux-x86:$BUILDTOOLS_DIR/linux-x86/bin:$PATH"
export LD_LIBRARY_PATH="$BUILDTOOLS_DIR/linux-x86/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

clang --version | head -1 | grep -F "clang version $LLVM_VERSION" \
  || die "clang is not $LLVM_VERSION"
ld.lld --version | grep -F "LLD $LLVM_VERSION" \
  || die "ld.lld is not $LLVM_VERSION"
llvm-ar --version | head -1 | grep -F "LLVM version $LLVM_VERSION" \
  || die "llvm-ar is not $LLVM_VERSION"
flex --version
bison --version | head -1
bc --version | head -1
echo "LLVM toolchain verified: Clang/LLD $LLVM_VERSION at $CLANG_DIR"
