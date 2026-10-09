/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef LIVEFIX_PATCH_H
#define LIVEFIX_PATCH_H

#include <linux/types.h>
#include "include/livefix_uapi.h"

int livefix_engine_init(void);
void livefix_engine_exit(void);

int livefix_apply_request(const struct livefix_apply_req *req);
int livefix_apply_gate_blob(enum livefix_hook hook, u32 persist,
			    const char *syms, const u8 *gate_insn, u32 gate_len);
int livefix_get_patch_count(void);

#endif
