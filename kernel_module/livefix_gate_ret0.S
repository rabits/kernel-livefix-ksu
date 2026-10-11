/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Gate for hook=ret0: stolen hint, then mov w0,#0, ret.
 * Patched target branches here instead of running the real function.
 */
	.text
	.balign 4
	.global livefix_gate_ret0
	.type livefix_gate_ret0, %function
livefix_gate_ret0:
	.inst 0xd503201f	/* legacy slot; per-hook gates use livefix_gates_pool */
	mov	w0, #0
	autiasp
	ret
	.size livefix_gate_ret0, . - livefix_gate_ret0

	.global livefix_gate_ret
	.type livefix_gate_ret, %function
livefix_gate_ret:
	.inst 0xd503201f	/* legacy slot */
	autiasp
	ret
	.size livefix_gate_ret, . - livefix_gate_ret
