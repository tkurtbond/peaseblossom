# The OpenBSD port of poc, the Peaseblossom Oberon-2 compiler (PLAN.md,
# Phase 13 step 8). Built from the release tarball, whose seed/ is poc's
# own LLVM IR, so base clang alone builds poc: voc is not needed. Build it
# from ${PORTSDIR}/mystuff/lang/peaseblossom.

# poc has run on i386 (cymoril, erekose) and amd64 (jherek)
ONLY_FOR_ARCHS =	amd64 i386

COMMENT =		Oberon-2 compiler (poc) using LLVM

V =			0.5.0
DISTNAME =		peaseblossom-${V}
CATEGORIES =		lang
# poc names it libpoc-rtl.so.0.0 itself (LLVMToolchainDriver.Mod)
SHARED_LIBS =		poc-rtl			0.0

HOMEPAGE =		https://github.com/tkurtbond/peaseblossom
MAINTAINER =		T. Kurt Bond <tkurtbond@gmail.com>

# BSD-3-Clause
PERMIT_PACKAGE =	Yes

SITES =			https://github.com/tkurtbond/peaseblossom/releases/download/v${V}/

WANTLIB =		c m

# poc compiles and links every program with base clang
COMPILER =		base-clang
USE_GMAKE =		Yes
MAKE_FILE =		GNUmakefile
ALL_TARGET =		installable
MAKE_FLAGS =		PREFIX=${TRUEPREFIX} \
			DOCDIR=${TRUEPREFIX}/share/doc/peaseblossom
FAKE_FLAGS =		DESTDIR=${WRKINST}
# installs into a scratch directory and runs test/install/check.sh there
TEST_TARGET =		check-install

# poc-rtl's directory is named after the host's triple, as clang gives it:
# amd64-unknown-openbsd7.9, i386-unknown-openbsd7.9
.include <bsd.port.arch.mk>
POC_TRIPLE =		${MACHINE_ARCH}-unknown-openbsd${OSREV}
SUBST_VARS +=		POC_TRIPLE

# make install leaves poc unstripped and poc-rtl as it was built, the -g
# copies with their DWARF
post-install:
	strip ${PREFIX}/bin/poc

.include <bsd.port.mk>
