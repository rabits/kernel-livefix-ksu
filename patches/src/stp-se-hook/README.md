# stp-se-hook

## Goal

Stop the **se-hook** hash scan (`sescan_hookhash`) that detects SELinux hook / integrity changes in the kernel.

## What it patches

- **Symbol:** `sescan_hookhash` (`rscan.ko`)
- **Hook:** `ret0`

## When to enable

Useful when `setenforce 0`, SELinux hook frameworks, or modules alter SELinux behavior and `se-hook` / related items start reporting RISK.

## Risks

Does not restore enforcing mode; only suppresses this kernel reporter.

## Suggested use

Off by default unless `se-hook` appears in `hwnff get_security_status` after root.
