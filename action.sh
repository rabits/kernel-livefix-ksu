#!/system/bin/sh
MODDIR=${0%/*}
case "${1:-status}" in
  start) sh "$MODDIR/service.sh" ;;
  status) sh "$MODDIR/scripts/livefix-ctl.sh" status ;;
  apply) sh "$MODDIR/scripts/livefix-ctl.sh" apply "$2" ;;
  *) sh "$MODDIR/scripts/livefix-ctl.sh" status ;;
esac
