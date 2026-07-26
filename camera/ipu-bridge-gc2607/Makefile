# SPDX-License-Identifier: GPL-2.0
#
# Out-of-tree build of the GC2607-patched ipu-bridge module.
# ipu-bridge.c is produced by pre-build.sh; it is not checked in.

obj-m := ipu-bridge.o

KDIR ?= /lib/modules/$(shell uname -r)/build
PWD  := $(shell pwd)

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
	rm -f ipu-bridge.c

.PHONY: all clean
