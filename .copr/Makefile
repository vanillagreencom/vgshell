# COPR's make_srpm entry point for COPR vanillagreen/vgshell. COPR runs
#   make -f <clone>/.copr/Makefile srpm outdir=<dir> spec=<Spec File field>
# as root in a mock chroot of its builder's Fedora, from the clone's root,
# with spec naming a shell or engine recipe under packaging/fedora/.
# docs/architecture/distribution.md.

here := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

.PHONY: srpm
srpm:
	dnf -y install bash curl git-core gzip rpm-build tar
	$(here)../packaging/fedora/srpm.sh --spec "$(spec)" --outdir "$(outdir)"
