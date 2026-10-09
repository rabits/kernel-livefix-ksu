#!/system/bin/sh
# Load livefix.ko once; apply .lfpatch via livefix_cli.

set -e
MODDIR="${MODDIR:-${0%/*}/..}"
# shellcheck source=scripts/common.sh
. "$MODDIR/scripts/common.sh"

AUTOSTART="$STATE_DIR/autostart.conf"
BROKEN="$STATE_DIR/broken.list"
APPLIED="$STATE_DIR/applied.list"

usage() {
  echo "Usage: $0 {detect|status|bootstrap-autostart|apply <id>|apply <id> --force|apply-all|clear-broken <id>}"
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
  if ! lsmod 2>/dev/null | grep -q '^livefix '; then
    log "insmod $KO"
    insmod "$KO"
  fi
}

cmd_apply() {
  local id="$1" force="${2:-0}" patch
  [ -n "$id" ] || usage
  if [ "$force" != "1" ] && is_broken "$id"; then
    log_err "$id broken — use: $0 apply $id --force"
    return 1
  fi
  if [ "$force" != "1" ] && is_applied "$id"; then
    log "apply: $id already applied (use --force to retry)"
    return 0
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
  kmi_paths || return 1
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
  kmi_paths 2>/dev/null || true
  echo "profile=${PROFILE:-unknown}"
  echo "livefix_loaded=$(lsmod 2>/dev/null | grep -c '^livefix ' || echo 0)"
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
  bootstrap-autostart) cmd_bootstrap_autostart ;;
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
