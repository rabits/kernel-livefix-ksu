#!/system/bin/sh
MODDIR=${0%/*}
# shellcheck source=scripts/common.sh
. "$MODDIR/scripts/common.sh"

exec >>"$LOG" 2>&1
log "service.sh start"

[ -f "$MODDIR/disable" ] && { log "disabled"; exit 0; }

if ! wait_for_kernelsu; then
  log_err "KernelSU not ready"
  exit 1
fi

ensure_kptr
sh "$MODDIR/scripts/livefix-ctl.sh" bootstrap-autostart
sh "$MODDIR/scripts/livefix-ctl.sh" apply-all
log "service.sh done"
