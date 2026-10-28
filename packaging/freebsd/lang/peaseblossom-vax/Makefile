# The FreeBSD port of what poc -target vax-dec-vms needs besides poc
# itself (make install-vax): the VAX runtime library POCRTL and VMS's
# interfaces, VMSDEF and VMSLIB, the two kits of poc for VAX/VMS, and the
# VAX/VMS Guide. A port of its own, since FreeBSD's ports have no
# subpackages, built from lang/peaseblossom's tarball (and its distinfo):
# poc is built from the seed again, and builds the libraries; the tarball
# has the kits and the guide as text already. It is all text, so NO_ARCH.

PORTNAME=	peaseblossom
DISTVERSION=	0.10.0
CATEGORIES=	lang
MASTER_SITES=	https://github.com/tkurtbond/peaseblossom/releases/download/v${DISTVERSION}/
PKGNAMESUFFIX=	-vax
DISTINFO_FILE=	${.CURDIR}/../peaseblossom/distinfo

MAINTAINER=	tkurtbond@gmail.com
COMMENT=	VAX/VMS target for poc: runtime libraries, kits, guide
WWW=		https://github.com/tkurtbond/peaseblossom

LICENSE=	BSD3CLAUSE
LICENSE_FILE=	${WRKSRC}/LICENSE

# poc, which builds the libraries, has run on amd64 and aarch64
ONLY_FOR_ARCHS=	aarch64 amd64

# poc refuses a library another version of poc wrote
RUN_DEPENDS=	peaseblossom=${DISTVERSION}:lang/peaseblossom

USES=		gmake
MAKEFILE=	GNUmakefile
ALL_TARGET=	installable-vax
INSTALL_TARGET=	install-vax
NO_ARCH=	yes
DOCSDIR=	${PREFIX}/share/doc/${PORTNAME}${PKGNAMESUFFIX}
MAKE_ARGS=	PREFIX=${PREFIX} DATADIR=${PREFIX}/share VAXKITDIR=${DATADIR}/vax \
		VAXDOCDIR=${DOCSDIR}
# installs poc and these into a scratch directory and builds programs for
# the VAX there (test/install/check-vax.sh)
TEST_TARGET=	check-install-vax

OPTIONS_DEFINE=	DOCS
PORTDOCS=	*

# the libraries' files are listed from the stage directory: the set of
# modules changes with the version
post-install:
	cd ${STAGEDIR}${PREFIX} && ${FIND} lib/poc/vax-dec-vms ${DATADIR_REL} -type f | ${SORT} >> ${TMPPLIST}

post-install-DOCS-off:
	${RM} -r ${STAGEDIR}${DOCSDIR}

.include <bsd.port.mk>
