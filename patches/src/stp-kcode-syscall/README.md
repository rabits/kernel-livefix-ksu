# stp-kcode-syscall

## Goal

Stop Honor’s **kcode-syscall** integrity check from reporting RISK when the syscall table is hooked (typical with KernelSU / root hooks).

## What it patches

- **Symbol:** `kcode_syscall_scan` (`rscan.ko`)
- **Hook:** `ret0` — function returns `0` without scanning `sys_call_table` (SHA256 compare never runs)

## Why it matters

`kcode-syscall` is **credible** in hwnff STP. A hit often flips the **overall** security status to RISK several minutes after root comes up, even when other items stay SAFE.

## Risks / trade-offs

- Hides syscall-table tampering from Honor’s kernel scanner only; other checks (eima, userspace, TEE) are unchanged.
- Does not clear an already latched RISK in oeminfo — use `StpClear` or reboot after scanners are frozen.

## Suggested use

Enable autostart (`config/autostart.conf`: `stp-kcode-syscall=1`). This is the default shipped configuration.

## Verify

```bash
dmesg | grep livefix
hwnff get_security_status   # after StpClear, kcode-syscall should not return to RISK while patched
```
