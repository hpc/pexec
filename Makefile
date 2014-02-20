# Makefile to "build" and install pexec

XCATPATCH := ./pexec-xcat.patch

ifeq ($(XCATROOT),)
   XCATROOT := /opt/xcat
endif

ifeq ($(bindir),)
   bindir := /usr/bin
endif

ifeq ($(mandir),)
   mandir := /usr/share/man
endif

.PHONY: all
all:
	@:

.PHONY: xcat
xcat:
	perl -pi -e "s,'/opt/xcat','$(XCATROOT)',g" $(XCATPATCH)
	patch -p0 -b < $(XCATPATCH)

.PHONY: install
install:
	mkdir -p "$(bindir)"
	mkdir -p "$(mandir)/man1"
	install -m 0755 pexec.pl "$(bindir)/pexec"
	pod2man pexec.pl "$(mandir)/man1/pexec.1"

.PHONY: install-xcat
install-xcat:
	mkdir -p "$(XCATROOT)/bin"
	mkdir -p "$(XCATROOT)/man/man1"
	install -m 0755 pexec.pl "$(XCATROOT)/bin/pexec"
	pod2man pexec.pl "$(XCATROOT)/man/man1/pexec.1"
