# SPDX-License-Identifier: GPL-2.0-only
obj-m := livefix.o
livefix-y := livefix_mod.o livefix_patch.o livefix_misc.o livefix_socket.o \
	livefix_gate.o livefix_gate_ret0.o

ccflags-y += -I$(src)/include

KDIR ?= /lib/modules/$(shell uname -r)/build

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean

.PHONY: all clean
