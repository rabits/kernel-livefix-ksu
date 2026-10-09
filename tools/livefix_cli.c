/*
 * Userspace client: apply .lfpatch via /dev/livefix or abstract unix @livefix
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include "../kernel_module/include/livefix_uapi.h"

static int apply_ioctl(const struct livefix_apply_req *req)
{
	int fd = open("/dev/livefix", O_RDWR | O_CLOEXEC);
	if (fd < 0)
		return -1;
	if (ioctl(fd, LIVEFIX_IOC_APPLY, req) < 0) {
		close(fd);
		return -1;
	}
	close(fd);
	return 0;
}

static int apply_unix(const struct livefix_apply_req *req)
{
	int fd;
	struct sockaddr_un sun;

	fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
	if (fd < 0)
		return -1;
	memset(&sun, 0, sizeof(sun));
	sun.sun_family = AF_UNIX;
	sun.sun_path[0] = '\0';
	strcpy(sun.sun_path + 1, "livefix");
	if (connect(fd, (struct sockaddr *)&sun,
		    sizeof(sun.sun_family) + 1 + strlen("livefix")) < 0) {
		close(fd);
		return -1;
	}
	if (write(fd, req, sizeof(*req)) != (ssize_t)sizeof(*req)) {
		close(fd);
		return -1;
	}
	close(fd);
	return 0;
}

static int load_lfpatch(const char *path, struct livefix_apply_req *req)
{
	FILE *f = fopen(path, "rb");
	unsigned char hdr[4 + 2 + 2 + 4 + 4 + 64];
	size_t n;
	char syms[LIVEFIX_SYM_MAX];
	uint32_t sym_len, gate_len;

	if (!f)
		return -1;
	n = fread(hdr, 1, sizeof(hdr), f);
	if (n != sizeof(hdr))
		goto bad;
	if (*(uint32_t *)hdr != LIVEFIX_MAGIC)
		goto bad;
	req->magic = LIVEFIX_MAGIC;
	req->version = *(uint16_t *)(hdr + 4);
	req->hook = *(uint16_t *)(hdr + 6);
	req->persist = *(uint32_t *)(hdr + 8);
	sym_len = *(uint32_t *)(hdr + 12);
	memcpy(req->patch_id, hdr + 16, LIVEFIX_ID_MAX);
	req->patch_id[LIVEFIX_ID_MAX - 1] = '\0';
	if (sym_len == 0 || sym_len >= LIVEFIX_SYM_MAX)
		goto bad;
	if (fread(syms, 1, sym_len, f) != sym_len)
		goto bad;
	memcpy(req->syms, syms, sym_len);
	req->sym_len = sym_len;
	if (fread(&gate_len, 1, 4, f) == 4) {
		if (gate_len > 0) {
			fprintf(stderr, "gate blob in %s not supported by cli yet\n", path);
			goto bad;
		}
	}
	fclose(f);
	return 0;
bad:
	fclose(f);
	return -1;
}

static int cmd_apply_file(const char *path)
{
	struct livefix_apply_req req;

	memset(&req, 0, sizeof(req));
	if (load_lfpatch(path, &req) < 0) {
		perror("load_lfpatch");
		return 1;
	}
	if (apply_ioctl(&req) == 0)
		return 0;
	if (apply_unix(&req) == 0)
		return 0;
	perror("apply");
	return 1;
}

static int cmd_status(void)
{
	struct livefix_status_resp st;
	int fd = open("/dev/livefix", O_RDWR | O_CLOEXEC);

	if (fd < 0) {
		perror("open /dev/livefix");
		return 1;
	}
	if (ioctl(fd, LIVEFIX_IOC_STATUS, &st) < 0) {
		perror("ioctl");
		close(fd);
		return 1;
	}
	close(fd);
	printf("patches=%u\n", st.patch_count);
	return 0;
}

int main(int argc, char **argv)
{
	if (argc < 2) {
		fprintf(stderr, "Usage: %s apply <file.lfpatch> | status\n", argv[0]);
		return 2;
	}
	if (strcmp(argv[1], "apply") == 0 && argc >= 3)
		return cmd_apply_file(argv[2]);
	if (strcmp(argv[1], "status") == 0)
		return cmd_status();
	return 2;
}
