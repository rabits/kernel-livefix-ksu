// SPDX-License-Identifier: GPL-2.0-only

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/fs.h>
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/uaccess.h>

#include "include/livefix_uapi.h"
#include "livefix_patch.h"

static long livefix_ioctl(struct file *filp, unsigned int cmd, unsigned long arg)
{
	struct livefix_apply_req req;
	struct livefix_status_resp st;

	switch (cmd) {
	case LIVEFIX_IOC_APPLY:
		if (copy_from_user(&req, (void __user *)arg, sizeof(req)))
			return -EFAULT;
		return livefix_apply_request(&req);
	case LIVEFIX_IOC_STATUS:
		st.magic = LIVEFIX_MAGIC;
		st.version = LIVEFIX_UAPI_VERSION;
		st.patch_count = livefix_get_patch_count();
		st.reserved = 0;
		if (copy_to_user((void __user *)arg, &st, sizeof(st)))
			return -EFAULT;
		return 0;
	default:
		return -ENOTTY;
	}
}

static const struct file_operations livefix_fops = {
	.owner = THIS_MODULE,
	.unlocked_ioctl = livefix_ioctl,
#ifdef CONFIG_COMPAT
	.compat_ioctl = livefix_ioctl,
#endif
};

static struct miscdevice livefix_dev = {
	.minor = MISC_DYNAMIC_MINOR,
	.name = "livefix",
	.fops = &livefix_fops,
};

int livefix_misc_init(void)
{
	return misc_register(&livefix_dev);
}

void livefix_misc_exit(void)
{
	misc_deregister(&livefix_dev);
}
