#!/system/bin/sh
# Shared probe: Honor device with hwnff STP tooling (Magic V5 class).

honor_stp_probe() {
  if [ -f /system/bin/hwnff ] || [ -f /vendor/bin/hwnff ]; then
    return 0
  fi
  return 1
}
