#!/system/bin/sh
MODDIR="${MODDIR:?}"
. "${LIVEFIX_PROBE_LIB:-$MODDIR/scripts/probes/lib}/honor_stp.sh"
honor_stp_probe
