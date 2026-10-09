// SPDX-License-Identifier: GPL-2.0-only
/*
 * AF_UNIX abstract @livefix — same binary as ioctl apply (struct livefix_apply_req).
 */

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/delay.h>
#include <linux/kthread.h>
#include <linux/module.h>
#include <linux/net.h>
#include <linux/socket.h>
#include <linux/un.h>
#include <linux/uaccess.h>
#include <net/net_namespace.h>

#include "include/livefix_uapi.h"
#include "livefix_patch.h"

#define LIVEFIX_SOCK_NAME "livefix"

static struct socket *listen_sock;
static struct task_struct *listen_task;

static int livefix_handle_client(struct socket *sock)
{
	struct livefix_apply_req req;
	struct msghdr msg = {};
	struct kvec iov;
	int ret;

	iov.iov_base = &req;
	iov.iov_len = sizeof(req);
	ret = kernel_recvmsg(sock, &msg, &iov, 1, sizeof(req), 0);
	if (ret != sizeof(req))
		return ret < 0 ? ret : -EINVAL;

	return livefix_apply_request(&req);
}

static int livefix_listen_fn(void *data)
{
	for (;;) {
		struct socket *client;
		int ret;

		if (kthread_should_stop())
			break;
		ret = kernel_accept(listen_sock, &client, 0);
		if (ret) {
			if (ret == -EAGAIN || ret == -EINTR)
				continue;
			pr_err("accept %d\n", ret);
			msleep(100);
			continue;
		}
		ret = livefix_handle_client(client);
		if (ret)
			pr_err("client apply %d\n", ret);
		sock_release(client);
	}
	return 0;
}

int livefix_socket_init(void)
{
	struct sockaddr_un addr;
	int ret;

	ret = sock_create_kern(&init_net, AF_UNIX, SOCK_STREAM, 0, &listen_sock);
	if (ret)
		return ret;

	memset(&addr, 0, sizeof(addr));
	addr.sun_family = AF_UNIX;
	addr.sun_path[0] = '\0';
	strscpy(addr.sun_path + 1, LIVEFIX_SOCK_NAME, sizeof(addr.sun_path) - 1);

	ret = kernel_bind(listen_sock, (struct sockaddr *)&addr,
			  sizeof(addr.sun_family) + 1 + strlen(LIVEFIX_SOCK_NAME));
	if (ret)
		goto err_sock;

	ret = kernel_listen(listen_sock, 4);
	if (ret)
		goto err_sock;

	listen_task = kthread_run(livefix_listen_fn, NULL, "livefix_sock");
	if (IS_ERR(listen_task)) {
		ret = PTR_ERR(listen_task);
		goto err_sock;
	}

	pr_info("unix abstract @%s listening\n", LIVEFIX_SOCK_NAME);
	return 0;

err_sock:
	sock_release(listen_sock);
	listen_sock = NULL;
	return ret;
}

void livefix_socket_exit(void)
{
	if (listen_task)
		kthread_stop(listen_task);
	listen_task = NULL;
	if (listen_sock) {
		sock_release(listen_sock);
		listen_sock = NULL;
	}
}
