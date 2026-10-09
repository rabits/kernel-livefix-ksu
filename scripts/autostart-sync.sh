#!/system/bin/sh
# Merge patch defaults into state/autostart.conf (probe + AUTOSTART from registry).
MODDIR="${MODDIR:-${0%/*}/..}"
# shellcheck source=scripts/common.sh
. "$MODDIR/scripts/common.sh"

kmi_paths || exit 0
REG="$PATCHDIR/autostart.registry"
STATE="$MODDIR/state/autostart.conf"
mkdir -p "$MODDIR/state"

[ -f "$REG" ] || {
  log "autostart-sync: no registry at $REG"
  exit 0
}

conf_has_key() {
  grep -qE "^${1}=" "$STATE" 2>/dev/null
}

conf_set_key() {
  local key="$1" val="$2"
  if conf_has_key "$key"; then
    sed -i "s/^${key}=.*/${key}=${val}/" "$STATE" 2>/dev/null || true
  else
    echo "${key}=${val}" >>"$STATE"
  fi
}

touch "$STATE"
while IFS='|' read -r id suggest probepath || [ -n "$id" ]; do
  id="${id%%#*}"
  id="$(echo "$id" | tr -d ' \r')"
  [ -n "$id" ] || continue
  case "$id" in \#*) continue ;; esac

  if conf_has_key "$id"; then
    continue
  fi

  compatible=1
  if [ -n "$probepath" ] && [ -f "$PATCHDIR/$probepath" ]; then
    if ! sh "$PATCHDIR/$probepath"; then
      compatible=0
      log "autostart-sync: $id probe failed (not registered)"
    fi
  fi
  [ "$compatible" = 1 ] || continue

  val="$suggest"
  [ "$val" = "1" ] || val=0
  conf_set_key "$id" "$val"
  log "autostart-sync: registered $id=$val (default from patch)"
done <"$REG"
