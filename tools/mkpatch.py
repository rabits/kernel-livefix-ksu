#!/usr/bin/env python3
"""Build .lfpatch from patches/src/<id>/patch.env and optional gate.bin."""
from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

HOOKS = {"ret0": 1, "ret": 2, "transparent": 3, "gate": 4}
MAGIC = 0x4c465850
VERSION = 2


def parse_env(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("env_file")
    ap.add_argument("out_lfpatch")
    ap.add_argument("--gate-bin", default="")
    args = ap.parse_args()

    meta = parse_env(Path(args.env_file))
    pid = meta.get("ID") or Path(args.env_file).parent.name
    hook = HOOKS.get(meta.get("HOOK", "ret0").lower())
    if hook is None:
        print("unknown HOOK", file=sys.stderr)
        return 1
    syms = meta.get("SYMS", "")
    persist = int(meta.get("PERSIST", "1"))
    sym_bytes = syms.encode("ascii") + b"\x00"
    if len(sym_bytes) > 480:
        print("SYMS too long", file=sys.stderr)
        return 1

    gate = b""
    if args.gate_bin:
        gate = Path(args.gate_bin).read_bytes()
        hook = HOOKS["gate"]

    hdr = struct.pack(
        "<IHHII",
        MAGIC,
        VERSION,
        hook,
        persist,
        len(sym_bytes),
    )
    patch_id = pid.encode("ascii")[:63].ljust(64, b"\x00")
    blob = hdr + patch_id + sym_bytes
    if gate:
        blob += struct.pack("<I", len(gate)) + gate

    out = Path(args.out_lfpatch)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(blob)
    print(f"wrote {out} ({len(blob)} bytes) id={pid} hook={hook}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
