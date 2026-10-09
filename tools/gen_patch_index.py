#!/usr/bin/env python3
"""Generate patches/index.json by scanning patches/src/*/patch.env (+ README.md)."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def parse_env(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src_root", type=Path, help="patches/src")
    ap.add_argument("out_json", type=Path)
    ap.add_argument("--kmi", required=True)
    ap.add_argument("--docs-out", type=Path, default=None, help="copy README.md per patch here")
    args = ap.parse_args()

    patches = []
    for env_path in sorted(args.src_root.glob("*/patch.env")):
        patch_dir = env_path.parent
        pid = patch_dir.name
        meta = parse_env(env_path)
        pid = meta.get("ID", pid)
        syms = [s.strip() for s in meta.get("SYMS", "").split(",") if s.strip()]
        title = meta.get("TITLE", pid)
        desc = meta.get("DESCRIPTION", "")
        readme = patch_dir / "README.md"
        if readme.is_file() and not desc:
            for line in readme.read_text().splitlines():
                line = line.strip()
                if line and not line.startswith("#"):
                    desc = line
                    break
        entry = {
            "id": pid,
            "title": title,
            "description": desc,
            "hook": meta.get("HOOK", "ret0"),
            "symbols": syms,
            "persist": meta.get("PERSIST", "1") == "1",
            "suggested_autostart": meta.get("AUTOSTART", "0") == "1",
        }
        if readme.is_file():
            entry["readme"] = f"docs/{pid}.md"
            if args.docs_out:
                dest = args.docs_out / f"{pid}.md"
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_text(readme.read_text())
        patches.append(entry)

    doc = {
        "schema": 2,
        "kmi": args.kmi,
        "patch_format": "lfpatch-v2",
        "patches": patches,
    }
    args.out_json.parent.mkdir(parents=True, exist_ok=True)
    args.out_json.write_text(json.dumps(doc, indent=2) + "\n")
    print(f"wrote {args.out_json} ({len(patches)} patches)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
