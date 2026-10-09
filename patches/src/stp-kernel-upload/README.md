# stp-kernel-upload

## Goal

**Kill-switch:** block all kernel → STP reporting by stubbing `kernel_stp_upload` (`kernel_stp.ko`).

## What it patches

- **Symbol:** `kernel_stp_upload`
- **Hook:** `ret` (void function — immediate return)

## Effect

No scanner in `rscan` / `eima` can push new state to `/proc/kernel_stp` while this hook is active. Strongest STP freeze; also blinds hisecd to **new** kernel events.

## When to enable

Last resort if multiple per-scanner patches are not enough, or you want one hook instead of several `ret0` stubs.

## Risks

- Broad: any feature relying on live `kernel_stp` updates may misbehave.
- Does not erase existing oeminfo DEBUG_LOCK; combine with `StpClear` if UI still shows old RISK.
- Heavy-handed for daily use; prefer targeted patches (`stp-kcode-syscall`, etc.) first.

## Suggested use

Off by default. Enable only for testing or short maintenance windows.
