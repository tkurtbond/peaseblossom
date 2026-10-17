# The OpenBSD port of poc, the Peaseblossom Oberon-2 compiler (PLAN.md,
# Phase 13 step 8). Built from the release tarball, whose seed/ is poc's
# own LLVM IR, so base clang alone builds poc: voc is not needed. Build it
# from ${PORTSDIR}/mystuff/lang/peaseblossom. Two packages: -main, poc and
# poc-rtl; -vax, what poc -target vax-dec-vms needs besides (make
# install-vax), all text, so for every architecture.

# poc has run on i386 (cymoril, erekose) and amd64 (jherek)
ONLY_FOR_ARCHS =	amd64 i386

MULTI_PACKAGES =	-main -vax
COMMENT-main =		Oberon-2 compiler (poc) using LLVM
COMMENT-vax =		VAX/VMS target for poc: runtime libraries, kits, guide

V =			0.6.0
DISTNAME =		peaseblossom-${V}
CATEGORIES =		lang
# poc names it libpoc-rtl.so.0.0 itself (LLVMToolchainDriver.Mod)
SHARED_LIBS =		poc-rtl			0.0

HOMEPAGE =		https://github.com/tkurtbond/peaseblossom
MAINTAINER =		T. Kurt Bond <tkurtbond@gmail.com>

# BSD-3-Clause
PERMIT_PACKAGE =	Yes

SITES =			https://github.com/tkurtbond/peaseblossom/releases/download/v${V}/

WANTLIB-main =		c m
PKG_ARCH-vax =		*
# poc refuses a library another version of poc wrote
RUN_DEPENDS-vax =	${BASE_PKGPATH},-main=${V}

# poc compiles and links every program with base clang
COMPILER =		base-clang
USE_GMAKE =		Yes
MAKE_FILE =		GNUmakefile
# the tarball has the VAX kits and the VAX/VMS Guide as text already:
# installable-vax builds only the libraries
ALL_TARGET =		installable installable-vax
INSTALL_TARGET =	install install-vax
MAKE_FLAGS =		PREFIX=${TRUEPREFIX} \
			DOCDIR=${TRUEPREFIX}/share/doc/peaseblossom \
			VAXDOCDIR=${TRUEPREFIX}/share/doc/peaseblossom-vax
FAKE_FLAGS =		DESTDIR=${WRKINST}
# each installs into a scratch directory and runs test/install/check.sh,
# or check-vax.sh, there
TEST_TARGET =		check-install check-install-vax

# poc-rtl's directory is named after the host's triple, as clang gives it:
# amd64-unknown-openbsd7.9, i386-unknown-openbsd7.9
.include <bsd.port.arch.mk>
POC_TRIPLE =		${MACHINE_ARCH}-unknown-openbsd${OSREV}
# the kits are named for the version with its periods made hyphens
KIT_V =			${V:S/./-/g}
SUBST_VARS +=		POC_TRIPLE KIT_V

# make install leaves poc unstripped and poc-rtl as it was built, the -g
# copies with their DWARF
post-install:
	strip ${PREFIX}/bin/poc

.include <bsd.port.mk>
