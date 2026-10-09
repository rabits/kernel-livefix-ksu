#!/usr/bin/env bash
set -euo pipefail
KMI="${1:?KMI profile}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/out/$KMI/patches"
BIN_OUT="$ROOT/out/$KMI/bin"
mkdir -p "$OUT" "$BIN_OUT"

echo "== patches $KMI =="
for env in "$ROOT"/patches/src/*/patch.env; do
  id="$(basename "$(dirname "$env")")"
  gate_bin=""
  gate_s="$ROOT/patches/src/$id/gate.S"
  if [ -f "$gate_s" ]; then
    echo "  compile gate.S for $id (host clang aarch64)"
    tmp_o="$ROOT/out/$KMI/.gate_${id}.o"
    tmp_bin="$ROOT/out/$KMI/.gate_${id}.bin"
    aarch64-linux-gnu-gcc -c -o "$tmp_o" "$gate_s" 2>/dev/null || \
      clang --target=aarch64-linux-android29 -c -o "$tmp_o" "$gate_s"
    llvm-objcopy -O binary -j .text "$tmp_o" "$tmp_bin"
    gate_bin="$tmp_bin"
  fi
  if [ -n "$gate_bin" ]; then
    python3 "$ROOT/tools/mkpatch.py" "$env" "$OUT/${id}.lfpatch" --gate-bin "$gate_bin"
  else
    python3 "$ROOT/tools/mkpatch.py" "$env" "$OUT/${id}.lfpatch"
  fi
  mkdir -p "$OUT/meta"
  cp -f "$env" "$OUT/meta/${id}.env"
  probe="$ROOT/patches/src/$id/probe.sh"
  if [ -f "$probe" ]; then
    mkdir -p "$OUT/probes"
    cp -f "$probe" "$OUT/probes/${id}.sh"
    chmod 755 "$OUT/probes/${id}.sh"
  fi
done

mkdir -p "$OUT/probes/lib"
cp -f "$ROOT/scripts/probes/lib/honor_stp.sh" "$OUT/probes/lib/honor_stp.sh"

python3 "$ROOT/tools/gen_patch_index.py" \
  "$ROOT/patches/src" \
  "$OUT/index.json" \
  --kmi "$KMI" \
  --docs-out "$OUT/docs"

NDK="${ANDROID_NDK_HOME:-/opt/android/sdk/ndk/27.2.12479018}"
CC="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android29-clang"
echo "== livefix_cli =="
"$CC" -static -O2 -o "$BIN_OUT/livefix_cli" \
  "$ROOT/tools/livefix_cli.c" \
  -I"$ROOT/kernel_module/include"
"$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" "$BIN_OUT/livefix_cli"
echo "-> $BIN_OUT/livefix_cli"
