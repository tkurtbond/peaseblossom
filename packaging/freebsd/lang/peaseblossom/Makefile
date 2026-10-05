# The FreeBSD port of poc, the Peaseblossom Oberon-2 compiler (PLAN.md,
# Phase 13 step 8). Built from the release tarball, whose seed/ is poc's
# own LLVM IR, so base clang alone builds poc: voc is not needed.

PORTNAME=	peaseblossom
DISTVERSION=	0.3.1
CATEGORIES=	lang
MASTER_SITES=	https://github.com/tkurtbond/peaseblossom/releases/download/v${DISTVERSION}/

MAINTAINER=	tkurtbond@gmail.com
COMMENT=	Oberon-2 compiler (poc) using LLVM
WWW=		https://github.com/tkurtbond/peaseblossom

LICENSE=	BSD3CLAUSE
LICENSE_FILE=	${WRKSRC}/LICENSE

# poc has run on amd64 (alerik) and aarch64 (rackhir); it compiles and
# links every program with base clang, so it needs nothing else
ONLY_FOR_ARCHS=	aarch64 amd64

USES=		gmake
MAKEFILE=	GNUmakefile
ALL_TARGET=	installable
MAKE_ARGS=	PREFIX=${PREFIX} DOCDIR=${DOCSDIR}

PLIST_FILES=	bin/poc share/man/man1/poc.1.gz

OPTIONS_DEFINE=	DOCS
PORTDOCS=	*

# make install leaves poc unstripped and poc-rtl as it was built, the -g
# copies with their DWARF. poc-rtl's files are listed from the stage
# directory: they are named after the host's triple, and the set of modules
# changes with the version.
post-install:
	${STRIP_CMD} ${STAGEDIR}${PREFIX}/bin/poc
	cd ${STAGEDIR}${PREFIX} && ${FIND} lib/poc -type f | ${SORT} >> ${TMPPLIST}

post-install-DOCS-off:
	${RM} -r ${STAGEDIR}${DOCSDIR}

# what a user does with the installed poc (needs DOCS: it looks for the
# guides)
do-test:
	cd ${WRKSRC} && ${SH} test/install/check.sh ${STAGEDIR}${PREFIX}/bin/poc ${WRKDIR}/check-install

.include <bsd.port.mk>
