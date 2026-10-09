// SPDX-License-Identifier: GPL-2.0-only

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/kernel.h>
#include <linux/kprobes.h>
#include <linux/module.h>
#include <linux/slab.h>
#include <linux/string.h>

#include "livefix_patch.h"

#define BRANCH_RANGE (1L << 27)
#define INSN_B 0x14000000u
#define HINT_MASK 0xfffff01fu
#define HINT_VAL 0xd503201fu
#define MAX_PATCHES 32
#define GATE_BLOB_MAX 64

extern void livefix_gate(void);
extern void livefix_gate_ret0(void);
extern void livefix_gate_ret(void);

typedef unsigned long (*kallsyms_lookup_name_t)(const char *name);
typedef int (*patch_text_t)(void *addrs[], u32 insns[], int cnt);

static kallsyms_lookup_name_t ksym_lookup;
static patch_text_t patch_text;
static bool persist_any;

static u8 gate_blob[GATE_BLOB_MAX];
static u32 gate_blob_len;
static unsigned long gate_blob_addr;

struct patch_slot {
	unsigned long addr;
	u32 orig;
	bool active;
};

static struct patch_slot patches[MAX_PATCHES];
static int patch_count;

static unsigned long lookup_by_kprobe(const char *name)
{
	struct kprobe kp = { .symbol_name = name };
	unsigned long addr;
	int ret;

	ret = register_kprobe(&kp);
	if (ret < 0)
		return 0;
	addr = (unsigned long)kp.addr;
	unregister_kprobe(&kp);
	return addr;
}

static unsigned long __attribute__((no_sanitize("cfi")))
lookup_symbol(const char *name)
{
	if (!ksym_lookup)
		return 0;
	return ksym_lookup(name);
}

static int __attribute__((no_sanitize("cfi")))
write_insn(void *addr, u32 insn)
{
	void *addrs[1] = { addr };
	u32 insns[1] = { insn };

	if (!patch_text)
		return -ENOENT;
	return patch_text(addrs, insns, 1);
}

static int encode_b(unsigned long pc, unsigned long dst, u32 *out)
{
	long off = (long)dst - (long)pc;

	if (off & 3)
		return -EINVAL;
	if (off < -BRANCH_RANGE || off >= BRANCH_RANGE)
		return -ERANGE;
	*out = INSN_B | ((u32)(off >> 2) & 0x03ffffff);
	return 0;
}

static bool insn_is_hint(u32 insn)
{
	return (insn & HINT_MASK) == HINT_VAL;
}

static unsigned long gate_for_hook(enum livefix_hook hook)
{
	switch (hook) {
	case LIVEFIX_HOOK_RET0:
		return (unsigned long)livefix_gate_ret0;
	case LIVEFIX_HOOK_RET:
		return (unsigned long)livefix_gate_ret;
	case LIVEFIX_HOOK_TRANSPARENT:
		return (unsigned long)livefix_gate;
	case LIVEFIX_HOOK_GATE_BLOB:
		return gate_blob_addr;
	default:
		return 0;
	}
}

static int install_branch_hook(unsigned long addr, unsigned long gate)
{
	u32 stolen, branch;
	int ret;

	if (patch_count >= MAX_PATCHES)
		return -ENOMEM;

	stolen = *(volatile u32 *)addr;
	if (!insn_is_hint(stolen)) {
		pr_err("%lx insn %08x not a hint\n", addr, stolen);
		return -EINVAL;
	}

	ret = encode_b(addr, gate, &branch);
	if (ret)
		return ret;

	ret = write_insn((void *)gate, stolen);
	if (ret)
		return ret;
	ret = write_insn((void *)addr, branch);
	if (ret)
		return ret;

	patches[patch_count].addr = addr;
	patches[patch_count].orig = stolen;
	patches[patch_count].active = true;
	patch_count++;
	return 0;
}

static int install_transparent(unsigned long addr)
{
	u32 stolen, back, hook_insn;
	unsigned long gate = (unsigned long)livefix_gate;
	int ret;

	if (patch_count >= MAX_PATCHES)
		return -ENOMEM;

	stolen = *(volatile u32 *)addr;
	if (!insn_is_hint(stolen))
		return -EINVAL;

	ret = encode_b(gate + 4, addr + 4, &back);
	if (ret)
		return ret;
	ret = encode_b(addr, gate, &hook_insn);
	if (ret)
		return ret;

	ret = write_insn((void *)gate, stolen);
	if (ret)
		return ret;
	ret = write_insn((void *)(gate + 4), back);
	if (ret)
		return ret;
	ret = write_insn((void *)addr, hook_insn);
	if (ret)
		return ret;

	patches[patch_count].addr = addr;
	patches[patch_count].orig = stolen;
	patches[patch_count].active = true;
	patch_count++;
	return 0;
}

static int apply_one_symbol(const char *name, enum livefix_hook hook)
{
	unsigned long addr, gate;
	u32 dummy;
	int ret;

	addr = lookup_symbol(name);
	if (!addr) {
		pr_err("symbol %s not found\n", name);
		return -ENOENT;
	}

	if (hook == LIVEFIX_HOOK_TRANSPARENT) {
		ret = encode_b(addr, (unsigned long)livefix_gate, &dummy);
		if (ret)
			return ret;
		return install_transparent(addr);
	}

	gate = gate_for_hook(hook);
	if (!gate)
		return -EINVAL;
	ret = encode_b(addr, gate, &dummy);
	if (ret)
		return ret;
	return install_branch_hook(addr, gate);
}

static int apply_symbol_list(const char *syms, enum livefix_hook hook)
{
	char buf[128];
	const char *p = syms;
	int ret;

	while (*p) {
		size_t len = 0;

		while (*p == ' ' || *p == ',')
			p++;
		if (!*p)
			break;
		while (p[len] && p[len] != ',')
			len++;
		if (len >= sizeof(buf))
			len = sizeof(buf) - 1;
		memcpy(buf, p, len);
		buf[len] = '\0';
		p += len;

		ret = apply_one_symbol(buf, hook);
		if (ret)
			return ret;
	}
	return 0;
}

int livefix_apply_gate_blob(enum livefix_hook hook, u32 persist,
			    const char *syms, const u8 *gate_insn, u32 gate_len)
{
	unsigned long gate;
	int i, ret;

	if (hook != LIVEFIX_HOOK_GATE_BLOB)
		return -EINVAL;
	if (!gate_insn || gate_len < 4 || gate_len > GATE_BLOB_MAX)
		return -EINVAL;
	if (!insn_is_hint(*(const u32 *)gate_insn))
		return -EINVAL;

	memcpy(gate_blob, gate_insn, gate_len);
	gate_blob_len = gate_len;
	gate_blob_addr = (unsigned long)gate_blob;

	for (i = 0; i + 4 <= gate_len; i += 4) {
		ret = write_insn(gate_blob + i, *(u32 *)(gate_blob + i));
		if (ret)
			return ret;
	}

	if (persist)
		persist_any = true;

	gate = gate_blob_addr;
	pr_info("gate blob %u bytes @ %lx\n", gate_len, gate);
	return apply_symbol_list(syms, LIVEFIX_HOOK_GATE_BLOB);
}

int livefix_apply_request(const struct livefix_apply_req *req)
{
	enum livefix_hook hook;

	if (!req || req->magic != LIVEFIX_MAGIC)
		return -EINVAL;
	if (req->version != LIVEFIX_UAPI_VERSION)
		return -EINVAL;
	if (req->sym_len == 0 || req->sym_len >= LIVEFIX_SYM_MAX)
		return -EINVAL;
	if (req->syms[req->sym_len - 1] != '\0')
		return -EINVAL;

	hook = req->hook;
	if (hook < LIVEFIX_HOOK_RET0 || hook > LIVEFIX_HOOK_GATE_BLOB)
		return -EINVAL;

	if (req->persist)
		persist_any = true;

	pr_info("apply id=%s hook=%u syms=%s\n", req->patch_id, hook, req->syms);
	return apply_symbol_list(req->syms, hook);
}

int livefix_get_patch_count(void)
{
	return patch_count;
}

int livefix_engine_init(void)
{
	ksym_lookup = (kallsyms_lookup_name_t)lookup_by_kprobe("kallsyms_lookup_name");
	if (!ksym_lookup)
		return -ENOENT;

	patch_text = (patch_text_t)lookup_symbol("aarch64_insn_patch_text");
	if (!patch_text)
		return -ENOENT;

	pr_info("engine ready (kallsyms %px patch_text %px)\n", ksym_lookup, patch_text);
	return 0;
}

void livefix_engine_exit(void)
{
	int i, ret;

	if (persist_any) {
		pr_info("persist: leaving %d patch(es)\n", patch_count);
		return;
	}
	for (i = 0; i < patch_count; i++) {
		if (!patches[i].active)
			continue;
		ret = write_insn((void *)patches[i].addr, patches[i].orig);
		if (ret)
			pr_err("restore %lx failed %d\n", patches[i].addr, ret);
		patches[i].active = false;
	}
	patch_count = 0;
}
