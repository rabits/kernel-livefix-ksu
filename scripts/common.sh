#!/system/bin/sh
# Shared helpers for kernel-livefix KSU module.

MODDIR="${MODDIR:-${0%/*}/..}"
MODDIR="$(cd "$MODDIR" && pwd)"
LOG="${KERNEL_LIVEFIX_LOG:-$MODDIR/livefix.log}"
STATE_DIR="$MODDIR/state"
LIVEFIX_CTL="$MODDIR/scripts/livefix-ctl.sh"

log() { echo "[$(date '+%F %T')] $*"; }
log_err() { log "ERROR: $*"; }

wait_for_kernelsu() {
  for _ in $(seq 1 180); do
    if [ -d /data/adb/ksu ] || [ -c /dev/kernelsu ]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

ensure_kptr() {
  local v
  v="$(cat /proc/sys/kernel/kptr_restrict 2>/dev/null)"
  if [ "$v" != "0" ]; then
    echo 0 > /proc/sys/kernel/kptr_restrict 2>/dev/null || true
  fi
}

detect_kmi_profile() {
  local rel ver
  rel="$(uname -r)"
  ver="$(cat /proc/version 2>/dev/null)"
  case "$rel" in
    6.6.*android15*) echo "android15-6.6" ;;
    6.12.*android16*) echo "android16-6.12" ;;
    6.18.*android17*) echo "android17-6.18" ;;
    5.15.*android14*) echo "android14-5.15" ;;
    6.1.*android14*) echo "android14-6.1" ;;
    5.15.*android13*) echo "android13-5.15" ;;
    5.10.*android13*) echo "android13-5.10" ;;
    5.10.*android12*) echo "android12-5.10" ;;
    *)
      if echo "$ver" | grep -q 'android15'; then echo "android15-6.6"; else echo ""; fi
      ;;
  esac
}
