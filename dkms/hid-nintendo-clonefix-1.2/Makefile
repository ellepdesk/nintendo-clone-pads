# manual build: make ; DKMS uses dkms-build.sh instead
KDIR ?= /lib/modules/$(shell uname -r)/build
all:
	./dkms-build.sh $(KDIR)
clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
