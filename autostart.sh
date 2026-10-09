#!/system/bin/sh
# GhostLock / late-load entry (same as service.sh).
MODDIR=${0%/*}
sh "$MODDIR/service.sh"
