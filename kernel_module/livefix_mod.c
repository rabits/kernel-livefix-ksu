// SPDX-License-Identifier: GPL-2.0-only

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/kernel.h>
#include <linux/module.h>

#include "livefix_patch.h"

int livefix_misc_init(void);
void livefix_misc_exit(void);
int livefix_socket_init(void);
void livefix_socket_exit(void);

static int __init livefix_init(void)
{
	int ret;

	ret = livefix_engine_init();
	if (ret)
		return ret;

	ret = livefix_misc_init();
	if (ret)
		goto err_engine;

	ret = livefix_socket_init();
	if (ret) {
		pr_warn("unix socket disabled (%d), use /dev/livefix ioctl\n", ret);
		ret = 0;
	}

	pr_info("loaded (/dev/livefix)\n");
	return 0;

err_engine:
	livefix_engine_exit();
	return ret;
}

static void __exit livefix_exit(void)
{
	livefix_socket_exit();
	livefix_misc_exit();
	livefix_engine_exit();
}

module_init(livefix_init);
module_exit(livefix_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Kernel live branch-patch engine");
MODULE_AUTHOR("kernel-livefix");
