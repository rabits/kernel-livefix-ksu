# stp-rscan-raw-unlock

## Goal

Avoid **partial** livefix stubs inside the periodic Honor root scan path (`rootscan` → `rscan_dynamic_raw_unlock` → `kcode_scan` / `kcode_syscall_scan` / …). A lone `stp-kcode-syscall` hook can still leave sibling scanners running and has been associated with rare kernel oops in `rscan` (see `docs/CRASH_20261010.md`).

## What it patches

- **Symbol:** `rscan_dynamic_raw_unlock` (`rscan.ko`)
- **Hook:** `ret0` — returns `0` (no per-check error flags) without calling child scanners

## When to use

- **Instead of** or **together with** `stp-kcode-syscall`: prefer this patch alone if you only need to stop kernel rscan STP items.
- Enable autostart in WebUI / `state/autostart.conf` if you want it on every boot.

## Trade-offs

- Hides all dynamic rscan kernel checks at once (kcode, kcode-syscall, se-hookhash, selinux, root procs, setids).
- Does **not** stop `eima` or userspace STP; does not block `kernel_stp_upload` by itself (use `stp-kernel-upload` for that).
- `rscan_dynamic` still runs comparison / upload logic above the raw unlock layer; for a full freeze of uploads use `stp-kernel-upload`.

## Verify

```bash
dmesg | grep 'livefix:.*rscan_dynamic_raw_unlock'
# after StpClear, watch hwnff — kernel rscan items should not refresh
```
