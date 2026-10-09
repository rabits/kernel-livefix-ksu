#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# Space-separated override: KMI_PROFILES="android15-6.6"
PROFILES="${KMI_PROFILES:-android12-5.10 android13-5.10 android13-5.15 android14-5.15 android14-6.1 android15-6.6 android16-6.12}"

# Cleanup
if [ -d "$ROOT/.zip-stage" ]; then
  rm -rf "$ROOT/.zip-stage"
fi
if [ -d "$ROOT/out" ]; then
  rm -rf "$ROOT/out"
fi

for kmi in $PROFILES; do
  "$ROOT/_build-lkm.sh" "$kmi" || {
    echo "warn: LKM build failed for $kmi (image missing?)" >&2
    continue
  }
  "$ROOT/_build-patches.sh" "$kmi" || exit 1
done

# Require at least android15-6.6 for Magic V5 smoke
if [ ! -f "$ROOT/out/android15-6.6/livefix.ko" ]; then
  echo "error: android15-6.6 livefix.ko not built" >&2
  exit 1
fi

"$ROOT/_build-zip.sh" "${1:-}"
