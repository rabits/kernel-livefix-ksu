/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Per-hook gate slots in module .text (RX). livefix_patch.c fills each slot
 * before branching from a patched symbol.
 */
	.section .text.livefix_gates_pool,"ax",%progbits
	.balign 4
	.global livefix_gates_pool
	.type livefix_gates_pool, %object
livefix_gates_pool:
	.rept 32
	.inst 0xd503201f	/* nop placeholder */
	.inst 0xd503201f
	.inst 0xd503201f
	.inst 0xd503201f
	.endr
	.size livefix_gates_pool, . - livefix_gates_pool
