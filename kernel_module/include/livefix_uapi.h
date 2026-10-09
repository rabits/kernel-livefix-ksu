/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef _LIVEFIX_UAPI_H
#define _LIVEFIX_UAPI_H

#ifdef __KERNEL__
#include <linux/ioctl.h>
#include <linux/types.h>
#else
#include <stdint.h>
#include <sys/ioctl.h>
typedef uint32_t __u32;
typedef uint16_t __u16;
#endif

#define LIVEFIX_MAGIC 0x4c465850u /* LFXP */
#define LIVEFIX_UAPI_VERSION 2

#define LIVEFIX_IOC_MAGIC 'L'
#define LIVEFIX_IOC_APPLY _IOW(LIVEFIX_IOC_MAGIC, 0x01, struct livefix_apply_req)
#define LIVEFIX_IOC_STATUS _IOR(LIVEFIX_IOC_MAGIC, 0x02, struct livefix_status_resp)

enum livefix_hook {
	LIVEFIX_HOOK_RET0 = 1,
	LIVEFIX_HOOK_RET = 2,
	LIVEFIX_HOOK_TRANSPARENT = 3,
	LIVEFIX_HOOK_GATE_BLOB = 4,
};

#define LIVEFIX_SYM_MAX 480
#define LIVEFIX_ID_MAX 64

struct livefix_apply_req {
	__u32 magic;
	__u16 version;
	__u16 hook;
	__u32 persist;
	__u32 sym_len;
	char patch_id[LIVEFIX_ID_MAX];
	char syms[LIVEFIX_SYM_MAX];
};

struct livefix_status_resp {
	__u32 magic;
	__u32 version;
	__u32 patch_count;
	__u32 reserved;
};

struct livefix_patch_file_hdr {
	__u32 magic;
	__u16 version;
	__u16 hook;
	__u32 persist;
	__u32 sym_len;
	char patch_id[LIVEFIX_ID_MAX];
};

#endif
