#!/system/bin/sh
# Load livefix.ko once; apply .lfpatch via livefix_cli.

set -e
MODDIR="${MODDIR:-${0%/*}/..}"
# shellcheck source=scripts/common.sh
. "$MODDIR/scripts/common.sh"

AUTOSTART="$STATE_DIR/autostart.conf"
BROKEN="$STATE_DIR/broken.list"
APPLIED="$STATE_DIR/applied.list"
SESSION_BOOT="$STATE_DIR/session.boot_id"

usage() {
  echo "Usage: $0 {detect|status|sync-session|load-engine|unload-engine|bootstrap-autostart|apply <id>|apply <id> --force|unapply <id>|apply-all|clear-broken <id>}"
  exit 1
}

kmi_paths() {
  PROFILE="$(detect_kmi_profile)"
  [ -n "$PROFILE" ] || return 1
  KO="$MODDIR/prebuilt/$PROFILE/livefix.ko"
  CLI="$MODDIR/prebuilt/$PROFILE/bin/livefix_cli"
  PATCHDIR="$MODDIR/prebuilt/$PROFILE/patches"
  export PROFILE KO CLI PATCHDIR
}

conf_get() {
  local key="$1" file="$2" default="${3:-0}"
  local line
  [ -f "$file" ] || { echo "$default"; return; }
  line="$(grep -E "^${key}=" "$file" 2>/dev/null | tail -1)"
  [ -n "$line" ] || { echo "$default"; return; }
  echo "${line#*=}"
}

conf_set() {
  local key="$1" val="$2" file="$3"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if grep -qE "^${key}=" "$file" 2>/dev/null; then
    sed -i "s/^${key}=.*/${key}=${val}/" "$file"
  else
    echo "${key}=${val}" >>"$file"
  fi
}

is_broken() {
  [ -f "$BROKEN" ] && grep -qx "$1" "$BROKEN"
}

is_applied() {
  [ -f "$APPLIED" ] && grep -qx "$1" "$APPLIED"
}

sync_boot_session() {
  local cur
  cur="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null | tr -d '\n')"
  [ -n "$cur" ] || return 0
  if [ "$(cat "$SESSION_BOOT" 2>/dev/null | tr -d '\n')" != "$cur" ]; then
    rm -f "$APPLIED"
    echo "$cur" >"$SESSION_BOOT"
    log "new boot $cur — cleared applied.list (hooks do not survive reboot)"
  fi
}

engine_loaded() {
  lsmod 2>/dev/null | grep -q '^livefix '
}

engine_patch_count() {
  local n
  if ! engine_loaded; then
    echo 0
    return
  fi
  kmi_paths 2>/dev/null || true
  n="$([ -x "${CLI:-}" ] && "$CLI" status 2>/dev/null | sed -n 's/^patches=//p')"
  echo "${n:-0}"
}

mark_unapplied() {
  local id="$1"
  [ -f "$APPLIED" ] || return 0
  grep -vx "$id" "$APPLIED" >"$APPLIED.tmp" 2>/dev/null || true
  mv "$APPLIED.tmp" "$APPLIED"
  if [ -f "$APPLIED" ] && [ ! -s "$APPLIED" ]; then
    rm -f "$APPLIED"
  fi
}

mark_broken() {
  mkdir -p "$STATE_DIR"
  is_broken "$1" || echo "$1" >>"$BROKEN"
}

clear_broken() {
  local id="$1"
  [ -f "$BROKEN" ] || return 0
  grep -vx "$id" "$BROKEN" >"$BROKEN.tmp" 2>/dev/null || true
  mv "$BROKEN.tmp" "$BROKEN"
  if [ -f "$BROKEN" ] && [ ! -s "$BROKEN" ]; then
    rm -f "$BROKEN"
  fi
}

mark_applied() {
  mkdir -p "$STATE_DIR"
  grep -vx "$1" "$APPLIED" 2>/dev/null >"$APPLIED.tmp" || true
  echo "$1" >>"$APPLIED.tmp"
  mv "$APPLIED.tmp" "$APPLIED"
  clear_broken "$1"
}

run_probe() {
  local id="$1" probe
  probe="$PATCHDIR/probes/${id}.sh"
  if [ ! -f "$probe" ]; then
    log "probe $id: no script, assume compatible"
    return 0
  fi
  chmod 755 "$probe" 2>/dev/null || true
  # Probes use MODDIR/scripts/probes/lib (module) or PATCHDIR/probes/lib (shipped)
  export MODDIR
  export LIVEFIX_PROBE_LIB="$PATCHDIR/probes/lib"
  MODDIR="$MODDIR" sh "$probe"
}

cmd_bootstrap_autostart() {
  local meta id val probe_ok
  kmi_paths || return 1
  mkdir -p "$STATE_DIR"
  touch "$AUTOSTART"

  # One-time migration from legacy module path
  if [ -f "$MODDIR/config/autostart.conf" ] && [ ! -f "$STATE_DIR/migrated_autostart" ]; then
    while IFS= read -r line; do
      case "$line" in
        ""|"#"*) continue ;;
        *=*)
          id="${line%%=*}"
          val="${line#*=}"
          if ! grep -qE "^${id}=" "$AUTOSTART" 2>/dev/null; then
            echo "${id}=${val}" >>"$AUTOSTART"
          fi
          ;;
      esac
    done <"$MODDIR/config/autostart.conf"
    touch "$STATE_DIR/migrated_autostart"
    log "migrated config/autostart.conf -> state/autostart.conf"
  fi

  for meta in "$PATCHDIR/meta"/*.env; do
    [ -f "$meta" ] || continue
    id="$(basename "$meta" .env)"
    if ! run_probe "$id"; then
      log "bootstrap: $id probe failed, skip autostart seed"
      continue
    fi
    if grep -qE "^${id}=" "$AUTOSTART" 2>/dev/null; then
      continue
    fi
    val="$(conf_get AUTOSTART "$meta" 0)"
    echo "${id}=${val}" >>"$AUTOSTART"
    log "bootstrap: seeded autostart ${id}=${val}"
  done
}

ensure_engine() {
  kmi_paths || { log_err "unknown kernel profile"; return 1; }
  [ -f "$KO" ] || { log_err "missing $KO"; return 1; }
  [ -x "$CLI" ] || { log_err "missing $CLI"; return 1; }
  if ! engine_loaded; then
    log "insmod $KO"
    insmod "$KO" || return 1
  fi
}

cmd_load_engine() {
  sync_boot_session
  ensure_kptr
  ensure_engine
}

cmd_unload_engine() {
  if engine_loaded; then
    log "rmmod livefix (persist hooks stay in kernel text until reboot)"
    rmmod livefix 2>/dev/null || return 1
  fi
  rm -f "$APPLIED"
  log "cleared applied.list — re-apply patches after load-engine"
}

cmd_apply() {
  local id="$1" force="${2:-0}" patch
  [ -n "$id" ] || usage
  sync_boot_session
  if [ "$force" != "1" ] && is_broken "$id"; then
    log_err "$id broken — use: $0 apply $id --force"
    return 1
  fi
  if [ "$force" != "1" ] && is_applied "$id"; then
    if engine_loaded && [ "$(engine_patch_count)" != "0" ]; then
      log "apply: $id already applied (use --force to retry)"
      return 0
    fi
    log "apply: $id marked applied but engine empty — re-applying"
    mark_unapplied "$id"
  fi
  ensure_engine || return 1
  patch="$PATCHDIR/${id}.lfpatch"
  [ -f "$patch" ] || { log_err "no patch $patch"; return 1; }
  if ! run_probe "$id"; then
    log_err "probe failed for $id"
    mark_broken "$id"
    return 1
  fi
  if ! "$CLI" apply "$patch"; then
    log_err "livefix_cli apply failed for $id"
    mark_broken "$id"
    return 1
  fi
  mark_applied "$id"
  log "applied $id ($PROFILE)"
}

cmd_apply_all() {
  local patch id
  sync_boot_session
  kmi_paths || return 1
  ensure_kptr
  cmd_bootstrap_autostart || true
  for patch in "$PATCHDIR"/*.lfpatch; do
    [ -f "$patch" ] || continue
    id="$(basename "$patch" .lfpatch)"
    [ "$(conf_get "$id" "$AUTOSTART" 0)" = "1" ] || continue
    if is_broken "$id"; then
      log "skip broken $id"
      continue
    fi
    cmd_apply "$id" 0 || true
  done
}

cmd_status() {
  sync_boot_session
  kmi_paths 2>/dev/null || true
  echo "boot_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
  echo "session_boot=$(cat "$SESSION_BOOT" 2>/dev/null)"
  echo "profile=${PROFILE:-unknown}"
  echo "livefix_loaded=$(engine_loaded && echo 1 || echo 0)"
  echo "engine_patches=$(engine_patch_count)"
  echo "--- autostart ($AUTOSTART) ---"
  cat "$AUTOSTART" 2>/dev/null || true
  echo "--- broken ---"
  cat "$BROKEN" 2>/dev/null || true
  echo "--- applied ---"
  cat "$APPLIED" 2>/dev/null || true
  if [ -x "${CLI:-}" ]; then
    echo "--- engine ---"
    "$CLI" status 2>/dev/null || true
  fi
  echo "--- hwnff ---"
  hwnff get_security_status 2>/dev/null | head -18 || true
  echo "--- dmesg ---"
  dmesg | grep livefix | tail -10
}

case "${1:-}" in
  detect) detect_kmi_profile ;;
  status) cmd_status ;;
  sync-session) sync_boot_session ;;
  load-engine) cmd_load_engine ;;
  unload-engine) cmd_unload_engine ;;
  bootstrap-autostart) cmd_bootstrap_autostart ;;
  unapply) mark_unapplied "$2"; log "unapplied $2 (kernel hooks remain until reboot)" ;;
  apply)
    if [ "${3:-}" = "--force" ]; then
      clear_broken "$2"
      cmd_apply "$2" 1
    else
      cmd_apply "$2" 0
    fi
    ;;
  apply-all) ensure_kptr; cmd_apply_all ;;
  clear-broken) clear_broken "$2" ;;
  set-autostart)
    conf_set "$2" "$3" "$AUTOSTART"
    ;;
  *) usage ;;
esac
