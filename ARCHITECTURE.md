# How kernel-livefix and `livefix.ko` work

This document describes the KernelSU module layout, the in-kernel patch engine, and the path from a
shipped `.lfpatch` to a hooked Honor STP scanner — without rebuilding the boot image.

## Big picture

```
┌─────────────────────────────────────────────────────────────────────────┐
│  KernelSU module (zip)  /data/adb/modules/kernel_livefix/               │
│  ┌──────────────┐   ┌─────────────┐   ┌──────────────────────────────┐  │
│  │ WebUI /      │   │ livefix-ctl │   │ prebuilt/<kmi>/              │  │
│  │ service.sh   │──►│ .sh         │──►│  livefix.ko                  │  │
│  └──────────────┘   │ livefix_cli │   │  patches/*.lfpatch           │  │
│                     └──────┬──────┘   │  patches/probes/*.sh         │  │
│                            │ ioctl /  └──────────────┬───────────────┘  │
│                            │ unix @livefix           │ insmod           │
└────────────────────────────┼─────────────────────────┼────────────────-─┘
                             │                         ▼
                    ┌────────▼────────────────────────────────────────┐
                    │  livefix.ko (GKI out-of-tree, per KMI build)    │
                    │  • resolve kallsyms + aarch64_insn_patch_text   │
                    │  • /dev/livefix + abstract UNIX @livefix        │
                    │  • branch hooks in kernel .text                 │
                    └────────┬────────────────────────────────────────┘
                             │ patched functions no longer run scanner logic
                             ▼
                    ┌────────────────────────────────────────────────┐
                    │  Vendor scanners (e.g. rscan.ko)               │
                    │  kcode_syscall_scan → kernel_stp_upload → …    │
                    └────────────────────────────────────────────────┘
```

The **KSU module** is policy and packaging: which patches exist, device probes, autostart, WebUI,
and logs. **`livefix.ko`** is the only component that modifies kernel text. Patch **logic** (symbol
names, hook type) lives in userspace blobs (`.lfpatch`), not in `insmod` parameters.

## `livefix.ko` — kernel engine

Sources: `kernel_module/`.

### Load and init

1. `insmod prebuilt/<kmi>/livefix.ko` (once per session, usually from `livefix-ctl.sh`).
2. `livefix_engine_init()`:
   - Resolves `kallsyms_lookup_name` via a short-lived **kprobe** (symbol is not exported on trimmed GKI).
   - Resolves `aarch64_insn_patch_text` the same way.
3. Registers control channels:
   - **Misc device** `/dev/livefix` — `LIVEFIX_IOC_APPLY`, `LIVEFIX_IOC_STATUS`.
   - **Unix stream socket** abstract name `livefix` (`\0livefix`) — one `struct livefix_apply_req` per connection (same layout as ioctl).

The module does **not** apply any hooks until userspace sends an apply request.

### How a hook is installed (AArch64 GKI)

Honor Magic V5–class kernels use **CFI**, **PAC**, **shadow call stack**, and **STRICT_KERNEL_RWX**.
Patching goes through the kernel’s official path:

1. **Resolve** target address: `kallsyms_lookup_name("kcode_syscall_scan")` (etc.).
2. **Check** the first instruction at the target is a **hint** (`paciasp`, `bti`, or `nop` — pattern `0xd503201f` family). Non-hint prologues are rejected.
3. **Check** a direct **`B`** branch from the target to a **gate** in the module fits ±128 MiB (module load window on this GKI).
4. **`aarch64_insn_patch_text`** writes:
   - At the **target**: `B <gate>` (replaces the hint).
   - At the **gate**: stolen hint, then hook-specific instructions.

Built-in gates (`livefix_gate_ret0.S`, `livefix_gate_ret.S`, `livefix_gate.S`):

| Hook (UAPI / `patch.env`) | Gate behavior                                                         |
|---------------------------|-----------------------------------------------------------------------|
| `ret0`                    | Stolen hint → `mov w0, #0` → `ret` (scanner thinks success / no hit)  |
| `ret`                     | Stolen hint → `ret` (void functions, e.g. `kernel_stp_upload`)        |
| `transparent`             | Stolen hint → `B` back to `target+4` (smoke test; behavior unchanged) |
| `gate` (blob)             | Custom `.text` from optional `gate.S` in patch source                 |

Up to **32** patch sites are tracked (`patch_slot`: address + original first instruction).

### Persist vs `rmmod`

If any applied request had **`persist=1`** (default in shipped STP patches), `livefix_engine_exit()`
**does not** restore original instructions when the module is removed. Hooks stay until **reboot**.
Without persist, `rmmod` restores the saved hint at each site.

### Security / stability notes

- **CFI**: only direct `B` to the gate is used; indirect calls through patched functions are unchanged.
- **Duplicate apply**: applying the same symbol again patches already-branched code and can break; userspace tracks `state/applied.list` and skips re-apply unless `--force`.
- **Shared `ret0` gate**: every `HOOK=ret0` symbol branches to the same `livefix_gate_ret0`; the stolen hint at the gate is overwritten on each new `ret0` apply. Prefer one broad symbol (e.g. `rscan_dynamic_raw_unlock`) or apply multiple `ret0` patches only when prologues match.
- **Partial rscan stubs**: hooking only `kcode_syscall_scan` while `kcode_scan` / `sescan_hookhash` / … still run can correlate with rare panics in `rscan` — see `docs/CRASH_20261010.md`.
- **Wrong symbol / OTA kernel**: KMI-mismatched `livefix.ko` fails `insmod` (vermagic); wrong symbol name fails apply with log line.

## Userspace control

### `livefix_cli`

Static binary in `prebuilt/<kmi>/bin/livefix_cli`. Reads a `.lfpatch` file, fills `struct livefix_apply_req`,
sends it via `/dev/livefix` (falls back to `@livefix` socket).

### `.lfpatch` format (v2)

Built by `tools/mkpatch.py` from `patches/src/<id>/patch.env`:

- Header: magic `LFXP`, hook id, persist, patch id, symbol string(s) (comma-separated).
- Optional tail: custom gate machine code for `HOOK=gate`.

No ELF relocation — only metadata plus optional raw insn bytes.

### `livefix-ctl.sh`

Orchestration on device:

- `bootstrap-autostart` - Run `probes/<id>.sh`; seed `state/autostart.conf` from `meta/<id>.env` `AUTOSTART=` when probe passes and id is new
- `apply-all` -  Bootstrap, then for each `*.lfpatch` with autostart=1: probe → `livefix_cli apply`
- `apply <id> [--force]` -  Load engine if needed, probe, apply one patch; `--force` clears broken flag and re-applies
- `set-autostart` / `clear-broken` -  WebUI / maintenance

State under **`state/`** (survives module updates; not overwritten by zip):

- `autostart.conf` — which patches to run on `service.sh`
- `applied.list` — ids applied successfully this boot/session
- `broken.list` — ids that failed probe or cli apply (skipped on autostart until Retry / clear)

Logs: `livefix.log` (service), `dmesg` tag `livefix:`.

## KernelSU module lifecycle

1. **Install zip** (KernelSU / BakaSU Manager) → `/data/adb/modules/kernel_livefix/`.
2. **GhostLock / late-load** gives root → `autostart.sh` or `service.sh` runs (or user opens WebUI).
3. **`ensure_kptr`**: set `/proc/sys/kernel/kptr_restrict=0` if needed so `kallsyms` resolves scanner symbols.
4. **`bootstrap-autostart`**: device-specific **probes** (e.g. Honor: `/system/bin/hwnff`) decide which patches are relevant; suggested autostart from patch metadata is written once to `state/autostart.conf`.
5. **`apply-all`**: `insmod livefix.ko` once, then each enabled `.lfpatch`.
6. **Honor STP**: frozen scanners stop calling `kernel_stp_upload` with new RISK for those checks; `hwnff get_security_status` can stay **SAFE** if nothing else trips (see `docs/RISK_TRIGGERS.md`). Existing latched oeminfo RISK may still need `StpClear` once.

### WebUI

KernelSU WebUI runs `ksu.exec` against `livefix-ctl.sh` and `service.sh`: edit autostart, apply,
status, per-patch **Retry** on failed ids.

## Relation to Honor STP (example)

Typical autostart patch **`stp-kcode-syscall`**:

1. `rscan.ko` would run `kcode_syscall_scan()` on a timer, hash `sys_call_table`, report via `kernel_stp_upload`.
2. Livefix replaces the function entry with **`ret0`** → no scan, no new **credible** `kcode-syscall` RISK.
3. hisecd / oeminfo are unchanged unless something else reports RISK.
