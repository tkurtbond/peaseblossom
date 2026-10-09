# $NetBSD$
#
# The pkgsrc package of poc, the Peaseblossom Oberon-2 compiler (PLAN.md,
# Phase 13 step 8). Built from the release tarball, whose seed/ is poc's
# own LLVM IR, so clang alone builds poc: voc is not needed.

DISTNAME=	peaseblossom-0.5.0
CATEGORIES=	lang
MASTER_SITES=	${MASTER_SITE_GITHUB:=tkurtbond/}
GITHUB_RELEASE=	v${PKGVERSION_NOREV}

MAINTAINER=	tkurtbond@gmail.com
HOMEPAGE=	https://github.com/tkurtbond/peaseblossom
COMMENT=	Oberon-2 compiler (poc) using LLVM
LICENSE=	modified-bsd

# poc has run on amd64 (artos, terhali) and i386 (yishana)
ONLY_FOR_PLATFORM=	NetBSD-*-x86_64 NetBSD-*-i386

# poc compiles and links every program with clang, which NetBSD's base
# system does not have
DEPENDS+=	clang-[0-9]*:../../lang/clang

USE_TOOLS+=		gmake
MAKE_FILE=		GNUmakefile
BUILD_TARGET=		installable
MAKE_FLAGS+=		PREFIX=${PREFIX} MANDIR=${PREFIX}/${PKGMANDIR}
MAKE_FLAGS+=		DOCDIR=${PREFIX}/share/doc/peaseblossom
INSTALL_MAKE_FLAGS=	${MAKE_FLAGS} DESTDIR=${DESTDIR}
# installs into a scratch directory and runs test/install/check.sh there
TEST_TARGET=		check-install

# poc runs clang itself, as its toolchain (and so does the seed's build),
# and needs the real one: pkgsrc's compiler wrappers include a "clang" that
# runs the package's C compiler (gcc). Without it, ${LOCALBASE}/bin/clang is
# found.
pre-build:
	${RM} -f ${WRAPPER_BINDIR}/clang

# poc-rtl's directory is named after the host's triple, as clang gives it:
# x86_64-unknown-netbsd11.0, i386-unknown-netbsdelf11.0
.include "../../mk/bsd.prefs.mk"
.if ${MACHINE_ARCH} == "i386"
POC_TRIPLE=	i386-unknown-netbsdelf${OS_VERSION}
.else
POC_TRIPLE=	${MACHINE_GNU_ARCH}-unknown-netbsd${OS_VERSION}
.endif
PLIST_SUBST+=	POC_TRIPLE=${POC_TRIPLE}

# make install leaves poc unstripped and poc-rtl as it was built, the -g
# copies with their DWARF
INSTALLATION_DIRS=	bin
post-install:
	${STRIP} ${DESTDIR}${PREFIX}/bin/poc

.include "../../mk/bsd.pkg.mk"
