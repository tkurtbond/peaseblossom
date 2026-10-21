# $NetBSD$
#
# The pkgsrc package of what poc -target vax-dec-vms needs besides poc
# itself (make install-vax): the VAX runtime library POCRTL and VMS's
# interfaces, VMSDEF and VMSLIB, the two kits of poc for VAX/VMS, and the
# VAX/VMS Guide. A package of its own, since pkgsrc has no subpackages,
# built from lang/peaseblossom's tarball (and its distinfo): poc is built
# from the seed again, and builds the libraries; the tarball has the kits
# and the guide as text already.

DISTNAME=	peaseblossom-0.8.0
PKGNAME=	${DISTNAME:S/peaseblossom/peaseblossom-vax/}
CATEGORIES=	lang
MASTER_SITES=	${MASTER_SITE_GITHUB:=tkurtbond/}
GITHUB_PROJECT=	peaseblossom
GITHUB_RELEASE=	v${PKGVERSION_NOREV}
DISTINFO_FILE=	${.CURDIR}/../../lang/peaseblossom/distinfo
PATCHDIR=	${.CURDIR}/../../lang/peaseblossom/patches

MAINTAINER=	tkurtbond@gmail.com
HOMEPAGE=	https://github.com/tkurtbond/peaseblossom
COMMENT=	VAX/VMS target for poc: runtime libraries, kits, guide
LICENSE=	modified-bsd

# poc, which builds the libraries, has run on amd64 and i386
ONLY_FOR_PLATFORM=	NetBSD-*-x86_64 NetBSD-*-i386

# poc is built with clang, and runs it
TOOL_DEPENDS+=	clang-[0-9]*:../../lang/clang
# poc refuses a library another version of poc wrote
DEPENDS+=	peaseblossom-${PKGVERSION_NOREV}{,nb[0-9]*}:../../lang/peaseblossom

USE_TOOLS+=		gmake
MAKE_FILE=		GNUmakefile
BUILD_TARGET=		installable-vax
INSTALL_TARGET=		install-vax
MAKE_FLAGS+=		PREFIX=${PREFIX} DATADIR=${PREFIX}/share
MAKE_FLAGS+=		VAXDOCDIR=${PREFIX}/share/doc/peaseblossom-vax
INSTALL_MAKE_FLAGS=	${MAKE_FLAGS} DESTDIR=${DESTDIR}
# installs poc and these into a scratch directory and builds programs for
# the VAX there (test/install/check-vax.sh)
TEST_TARGET=		check-install-vax

# as lang/peaseblossom: poc runs the real clang, not pkgsrc's wrapper
pre-build:
	${RM} -f ${WRAPPER_BINDIR}/clang

# the kits are named for the version with its periods made hyphens
PLIST_SUBST+=	KIT_V=${PKGVERSION_NOREV:S/./-/g}

.include "../../mk/bsd.pkg.mk"
