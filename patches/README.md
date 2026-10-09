# Patch sources

Each subdirectory is one patch.

## Required

|    File     |                    Purpose                         |
|-------------|----------------------------------------------------|
| `patch.env` | Build metadata → `<id>.lfpatch`                    |
| `README.md` | Documentation                                      |
| `probe.sh`  | Exit 0 if this patch is compatible with the device |

### `patch.env`

|           Key           | Required |                     Description                                        |
|-------------------------|----------|------------------------------------------------------------------------|
| `HOOK`                  | Yes      | `ret0`, `ret`, `transparent`, or `gate` (with `gate.S`)                |
| `SYMS`                  | Yes      | One symbol or comma-separated list sharing the same hook gate          |
| `ID`                    | No       | Patch id (defaults to directory name if omitted)                       |
| `PERSIST`               | No       | Keep patches in kernel text after `rmmod livefix`                      |
| `TITLE` / `DESCRIPTION` | No       | WebUI + generated `index.json` (optional if `README.md` has a summary) |
| `AUTOSTART`             | No       | Documentation hint only; real autostart is `config/autostart.conf`     |

Optional advanced: `patches/src/<id>/gate.S` — custom AArch64 instructions placed in the module gate slot (`HOOK=gate` after build). Most patches only need `ret0` / `ret`.

## Creating a patch from scratch

Patches are **metadata + hook type**. The kernel module only knows how to branch to built-in gates
(`ret0`, `ret`, `transparent`) or an optional **raw gate blob** from `gate.S`. Optional `gate.S` is
compiled to a **`.text` binary** embedded in `.lfpatch`.

### 1. Pick a symbol

On a rooted device with scanners loaded:

```bash
adb shell su -c 'grep kcode_syscall_scan /proc/kallsyms'
# ffffffefd14b3840 t kcode_syscall_scan	[rscan]
```

Use the **name** without module suffix (`kcode_syscall_scan`). The target’s first instruction must
be a **hint** (`paciasp` / `bti` / `nop`) or livefix refuses the patch.

### 2. Add patch source

Create a directory under `patches/src/` named after your patch id (used in autostart and WebUI):

```bash
mkdir -p patches/src/demo-freeze-selinux
```

Create `patches/src/demo-freeze-selinux/patch.env`:

```env
ID=demo-freeze-selinux
TITLE=Freeze SELinux enforcing read
DESCRIPTION=Stub get_selinux_enforcing for rscan STP item se-enforcing.
HOOK=ret0
PERSIST=1
AUTOSTART=0
SYMS=get_selinux_enforcing
```

Add `patches/src/demo-freeze-selinux/README.md` describing goal, risks, and how to test (see any
shipped patch under `patches/src/*`).
