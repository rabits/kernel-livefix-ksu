#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(grep '^version=' "$ROOT/module.prop" | cut -d= -f2)"
STAMP="$(date -u +%Y%m%d%H%M)"
ZIP_NAME="${1:-kernel-livefix_${VERSION}-${STAMP}.zip}"
STAGE="$ROOT/.zip-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/prebuilt"

# Sync built artifacts into prebuilt/<kmi>/
for kmi_dir in "$ROOT"/out/*/; do
  [ -d "$kmi_dir" ] || continue
  kmi="$(basename "$kmi_dir")"
  mkdir -p "$STAGE/prebuilt/$kmi/patches/docs" "$STAGE/prebuilt/$kmi/bin"
  [ -f "$kmi_dir/livefix.ko" ] && cp "$kmi_dir/livefix.ko" "$STAGE/prebuilt/$kmi/"
  if [ -d "$kmi_dir/patches" ]; then
    for f in "$kmi_dir/patches"/*.lfpatch "$kmi_dir/patches/index.json"; do
      [ -f "$f" ] && cp "$f" "$STAGE/prebuilt/$kmi/patches/"
    done
    [ -d "$kmi_dir/patches/docs" ] && cp -a "$kmi_dir/patches/docs/." "$STAGE/prebuilt/$kmi/patches/docs/"
    [ -d "$kmi_dir/patches/meta" ] && cp -a "$kmi_dir/patches/meta" "$STAGE/prebuilt/$kmi/patches/"
    [ -d "$kmi_dir/patches/probes" ] && cp -a "$kmi_dir/patches/probes" "$STAGE/prebuilt/$kmi/patches/"
  fi
  [ -f "$kmi_dir/bin/livefix_cli" ] && cp "$kmi_dir/bin/livefix_cli" "$STAGE/prebuilt/$kmi/bin/"
done

copy() { install -D "$1" "$STAGE/$2"; }

copy "$ROOT/module.prop" module.prop
copy "$ROOT/service.sh" service.sh
copy "$ROOT/autostart.sh" autostart.sh
copy "$ROOT/action.sh" action.sh
copy "$ROOT/customize.sh" customize.sh
copy "$ROOT/patches/src/README.md" patches/README.md
copy "$ROOT/scripts/probes/lib/honor_stp.sh" scripts/probes/lib/honor_stp.sh
copy "$ROOT/README.md" README.md
copy "$ROOT/scripts/common.sh" scripts/common.sh
copy "$ROOT/scripts/livefix-ctl.sh" scripts/livefix-ctl.sh
copy "$ROOT/webroot/index.html" webroot/index.html
copy "$ROOT/webroot/config.json" webroot/config.json
copy "$ROOT/webroot/icon.svg" webroot/icon.svg

chmod 755 "$STAGE"/*.sh "$STAGE"/scripts/*.sh "$STAGE"/customize.sh
find "$STAGE/prebuilt" -name livefix_cli -exec chmod 755 {} \;

python3 - "$STAGE" "$ROOT/$ZIP_NAME" <<'PY'
import sys, zipfile
from pathlib import Path
stage, out = Path(sys.argv[1]), Path(sys.argv[2])
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
    for p in sorted(stage.rglob("*")):
        if p.is_file():
            zf.write(p, p.relative_to(stage).as_posix())
print(f"packed {out} ({out.stat().st_size} bytes)")
PY
