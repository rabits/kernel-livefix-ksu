#!/usr/bin/env bash
set -euo pipefail
KMI="${1:?KMI profile, e.g. android15-6.6}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
IMAGE="$(grep -E "^${KMI}=" "$ROOT/scripts/ddk-images.env" | cut -d= -f2-)"
if [ -z "$IMAGE" ]; then
  echo "unknown KMI $KMI (add to scripts/ddk-images.env)" >&2
  exit 1
fi
OUT="$ROOT/out/$KMI"
mkdir -p "$OUT"

echo "== LKM $KMI image=$IMAGE =="
docker run --rm --user "$(id -u)":"$(id -g)" \
  -v "$ROOT/kernel_module":/src -w /src \
  "$IMAGE" sh -c 'CC=clang make'
STRIP="${ANDROID_NDK_HOME:-/opt/android/sdk/ndk/27.2.12479018}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
if [ -x "$STRIP" ]; then
  "$STRIP" -d "$ROOT/kernel_module/livefix.ko"
fi
cp -f "$ROOT/kernel_module/livefix.ko" "$OUT/livefix.ko"
echo "-> $OUT/livefix.ko"
