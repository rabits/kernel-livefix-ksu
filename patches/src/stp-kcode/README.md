# stp-kcode

## Goal

Disable the **kcode** kernel-text scan that feeds the `kcode` hwnff item (integrity category, usually non-credible).

## What it patches

- **Symbol:** `kcode_scan` (`rscan.ko`)
- **Hook:** `ret0`

## When to enable

If you see `kcode` flipping to RISK after long root sessions or kernel live patches, enable this in addition to `stp-kcode-syscall`.

## Risks

Same class as other scanner stubs: local kernel check only; does not affect bootloader or TEE attestation.

## Suggested use

Off by default. Set `stp-kcode=1` in `config/autostart.conf` if needed.
