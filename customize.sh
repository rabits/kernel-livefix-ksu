#!/system/bin/sh
SKIPUNZIP=0
ui_print "Kernel Livefix: chmod scripts"
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/autostart.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/scripts/livefix-ctl.sh" 0 0 0755
set_perm_recursive "$MODPATH/scripts" 0 0 0755 0644
set_perm_recursive "$MODPATH/prebuilt" 0 0 0755 0755
mkdir -p "$MODPATH/state"
