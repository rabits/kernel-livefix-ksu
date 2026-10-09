/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Two instruction slots in module text. livefix overwrites them with
 * aarch64_insn_patch_text:
 *   slot 0: the hint stolen from the target prologue
 *   slot 1: B back to target+4
 * A direct B lands here, so CFI and BTI_KERNEL (off on this kernel) stay out of it.
 */
	.text
	.balign 4
	.global livefix_gate
	.type livefix_gate, %function
livefix_gate:
	.inst 0xd503201f
	.inst 0xd503201f
	.size livefix_gate, . - livefix_gate
