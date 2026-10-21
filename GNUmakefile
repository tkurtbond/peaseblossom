# GNUmakefile - Peaseblossom (poc) build/test entry point.
#
# GNU Make required (uses $(filter)/$(filter-out) with multiple patterns);
# the "GNUmakefile" name itself is GNU Make's own convention for "this
# file needs GNU Make", checked before "Makefile"/"makefile".
#
# `make` (no target) builds poc - see "build" below, the first real
# target in this file. See PLAN.md/AGENTS.md for background: poc is
# bootstrapped by voc (tools/bootstrap/stage0), not yet self-hosted.

BUILD_DIR := build
BIN := $(BUILD_DIR)/bin/poc
CONFORMANCE_DIR := test/conformance

FRONT_SRCS := $(wildcard src/front/*.Mod)
BACK_LLVM_SRCS := $(wildcard src/back/llvm/*.Mod)
BACK_VAX_SRCS := $(wildcard src/back/vax/*.Mod) $(wildcard src/back/vax/host/*.Mod)
DRIVER_SRCS := src/driver/Version.Mod src/driver/Libraries.Mod src/driver/llvm/LLVMBackEnd.Mod \
  src/driver/Poc.Mod
# Phase 17 step 7: the LLVMBackEnd of a poc without the LLVM back end, which
# poc for VAX/VMS is built with (tools/bootstrap/vax-v1); checked by
# check-strict, not part of poc here
NO_LLVM_SRCS := src/driver/no-llvm/LLVMBackEnd.Mod
# Phase 18 step 4: where poc for VAX/VMS writes an object's records,
# src/back/vax/host's twin; checked by check-strict, not part of poc here
VAX_VMS_SRCS := $(wildcard src/back/vax/vms/*.Mod)
# Phase 13 step 1: the commit `poc -version` names, written by tools/build-info
# on every make (it rewrites the file only when the commit or the tree's state
# changed, so only then is poc rebuilt)
BUILD_INFO := $(BUILD_DIR)/gen/BuildInfo.Mod
RTL_SRCS := $(wildcard rtl/llvm/*.Mod)
# Phase 12 step 5a: the C part of an rtl module, compiled with it by poc
RTL_C_SRCS := $(wildcard rtl/llvm/*.c)
# what Stage 0 builds with voc besides src/: Err and what it needs (Phase 11
# D11), and Directories (Phase 16 step 4)
STAGE0_RTL_SRCS := rtl/voc/FileDescriptorOutput.Mod rtl/llvm/RealDigits.Mod \
  rtl/llvm/FormattedText.Mod rtl/llvm/FormattedOutput.Mod rtl/llvm/Err.Mod \
  rtl/voc/Directories.Mod
STAGE1_BIN := $(BUILD_DIR)/stage1/bin/poc
VAX_IMAGE_BIN := $(BUILD_DIR)/bin/vax-image
# Phase 12 step 2d: rtl/llvm as the library poc-rtl, for this host's triple
# and both size models, where each poc's default library path finds it
# (<its bin>/../lib/poc): so a program links the runtime already compiled.
HOST_TRIPLE := $(shell clang -dumpmachine)
RTL_LIBRARIES = $(1)/lib/poc/$(HOST_TRIPLE)/O2/poc-rtl.library $(1)/lib/poc/$(HOST_TRIPLE)/OC/poc-rtl.library
# The Stage 0 poc is a voc program, linked against voc's shared runtime,
# which only Linux finds by itself (as in tools/bootstrap/stage1 and
# test/testenv.sh): a command that runs it is prefixed with this.
VOC_BIN_DIR ?= /usr/local/sw/versions/voc/git/bin
VOC_LIB_DIR ?= $(VOC_BIN_DIR)/../lib
STAGE0_ENV = LD_LIBRARY_PATH="$(VOC_LIB_DIR)$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}"
SRCS := $(FRONT_SRCS) $(BACK_LLVM_SRCS) $(BACK_VAX_SRCS) $(DRIVER_SRCS)

# Conformance fixtures grouped by which part of poc they exercise, mirroring
# PLAN.md's directory layout (src/front/{Lexer,Parser,SemanticActions +
# Types/SymbolTable/ConstantEvaluator/PredeclaredProcedures,
# ModuleInterface,MemoryLayout}, src/back/llvm). Grouping is by
# test/conformance's own naming convention (a "lexer-"/"parser-"/etc.
# prefix), not a manually maintained list, so a newly added fixture is
# picked up automatically the next time make runs - and, if its name
# doesn't match any prefix below, it still runs (via test-misc/test)
# rather than silently being dropped.
ALL_TESTS := $(notdir $(wildcard $(CONFORMANCE_DIR)/*))
LEXER_TESTS := $(filter lexer-%,$(ALL_TESTS))
PARSER_TESTS := $(filter parser-%,$(ALL_TESTS))
SEMANTIC_TESTS := $(filter semantic-% oc-%,$(ALL_TESTS))
MODULE_TESTS := $(filter module-% import-path-% output-dir-%,$(ALL_TESTS))
LAYOUT_TESTS := $(filter layout-%,$(ALL_TESTS))
LLVM_TESTS := $(filter llvm-%,$(ALL_TESTS))
CATEGORIZED_TESTS := $(LEXER_TESTS) $(PARSER_TESTS) $(SEMANTIC_TESTS) $(MODULE_TESTS) $(LAYOUT_TESTS) $(LLVM_TESTS)
# Fixtures whose name matches no category above (e.g. "hello", Phase 0's
# own harness-plumbing smoke test) - still run, just not narrowly
# targetable by a single part of the compiler.
MISC_TESTS := $(filter-out $(CATEGORIZED_TESTS),$(ALL_TESTS))

.PHONY: FORCE all build installable install uninstall check-install installable-vax install-vax uninstall-vax check-install-vax check-install-vax-run seed check-seed doc doc-html doc-pdf doc-all doc-other-html doc-other-pdf dist dist-sign distcheck set-version check-hosts release-files stage1 stage2 test-stage1 check check-stage1 check-strict check-o2 check-opt2 check-lto test test-vax test-vax-asts test-vax-guest-poc vax-v1 vax-stages vax-kit check-vax-kit vax-image test-lexer test-parser test-semantic test-modules test-layout test-llvm test-misc clean clean-build clean-tests

build: $(BIN) $(call RTL_LIBRARIES,$(BUILD_DIR))

$(BIN): $(SRCS) $(STAGE0_RTL_SRCS) tools/bootstrap/voc-heap-gc-spill.c $(BUILD_INFO)
	tools/bootstrap/stage0

$(BUILD_INFO): FORCE
	tools/build-info $(BUILD_DIR)/gen

# poc-rtl for one size model (O2 or OC, the %), built by the poc of the
# same tree; -clear-library-path, so that nothing is taken from the copy it
# replaces
$(BUILD_DIR)/lib/poc/$(HOST_TRIPLE)/%/poc-rtl.library: $(BIN) $(RTL_SRCS) $(RTL_C_SRCS)
	$(STAGE0_ENV) $(BIN) -$* -clear-library-path -output-dir $(BUILD_DIR)/lib/poc -library poc-rtl $(RTL_SRCS)

$(BUILD_DIR)/stage1/lib/poc/$(HOST_TRIPLE)/%/poc-rtl.library: $(STAGE1_BIN) $(RTL_SRCS) $(RTL_C_SRCS)
	$(STAGE1_BIN) -$* -clear-library-path -output-dir $(BUILD_DIR)/stage1/lib/poc -library poc-rtl $(RTL_SRCS)

all: build

# Self-hosting (PLAN.md, "Bootstrap terminology"): stage1 builds poc with the
# Stage 0 poc, stage2 builds it again with Stage 1's and checks the two
# builds' output is identical (the fixed point). Stage 1 is compiled by poc
# itself, so it links rtl/llvm and is rebuilt when that changes too; stage2
# always reruns, being a comparison.
stage1: $(STAGE1_BIN)

$(STAGE1_BIN): $(BIN) $(SRCS) $(RTL_SRCS) $(RTL_C_SRCS) $(BUILD_INFO)
	tools/bootstrap/stage1

stage2: $(STAGE1_BIN)
	tools/bootstrap/stage2

# The whole suite under the poc that poc built (POC_BIN_DIR is what
# test/testenv.sh puts on PATH first; the tests cd, so it must be absolute).
# `make test` stays Stage 0 only - the fast loop, and voc remains the
# bootstrap root and the comparison oracle. This suite, check-opt2's and
# check-lto's leave the VAX guest alone (VAX_GUEST=skip, test/vaxfixture.sh):
# it sees only each fixture's expected-vax.mar, which make test's run checks.
test-stage1: $(STAGE1_BIN) $(call RTL_LIBRARIES,$(BUILD_DIR)/stage1) $(VAX_IMAGE_BIN)
	POC_BIN_DIR=$(abspath $(BUILD_DIR)/stage1/bin) VAX_GUEST=skip test/run-tests.sh $(ALL_TESTS)

# Both compilers and the fixed point: the suite under the voc-built poc, the
# suite under the poc-built one, then the Stage 1/Stage 2 comparison. Each
# part runs whatever an earlier one did, so a single run shows every failure.
check:
	@status=0; \
	$(MAKE) test || status=1; \
	$(MAKE) test-stage1 || status=1; \
	$(MAKE) stage2 || status=1; \
	$(MAKE) check-strict || status=1; \
	$(MAKE) check-o2 || status=1; \
	exit $$status

# check without the suite under the voc-built poc: what tools/check-hosts
# runs on every host but this one, since that suite tests voc's build of
# poc, which atla's make check covers, and Stage 1's tests the same source.
check-stage1:
	@status=0; \
	$(MAKE) test-stage1 || status=1; \
	$(MAKE) stage2 || status=1; \
	$(MAKE) check-strict || status=1; \
	$(MAKE) check-o2 || status=1; \
	exit $$status

# Phase 11 D13: everything built with poc -opt 2 (clang -O2), including
# 32-bit x86, whose default is -O0 (LLVMToolchainDriver.
# DefaultOptimizationLevel) - the gate -O2 passed before it became the
# default elsewhere. The suite with every fixture's build optimized (a poc
# wrapper that adds -opt 2), then Stage 1 and Stage 2 built optimized in
# build/opt2 and compared, then the suite under that Stage 1.
# poc-exit-status, poc-output-streams, poc-opt-level, poc-usage and
# poc-options-after-file test
# poc's command line, which the wrapper changes, so they are left out. So
# are the fixtures whose exact real results x87 arithmetic changes when
# optimized (the reason for the -O0 default): llvm-out-extra and llvm-math-extra on a
# 32-bit x86 host, and llvm-i686-runtime, which reruns them for 32-bit x86,
# on a 32-bit x86 host or a BSD (Linux i686 has SSE2). Each suite's poc has
# poc-rtl built optimized in its own ../lib/poc (Phase 12 steps 2d, 2e), as
# make builds it for build/bin/poc: the Stage 0 poc is copied to
# build/opt2/stage0/bin for that, so that its library path does not also
# have build/lib/poc's.
OPT2_DIR := $(abspath $(BUILD_DIR)/opt2)
OPT2_HOST_X87 := $(filter i386 i486 i586 i686,$(shell uname -m))
OPT2_HOST_BSD := $(filter-out Linux,$(shell uname -s))
OPT2_SKIP := poc-exit-status poc-output-streams poc-opt-level poc-usage poc-options-after-file \
  $(if $(OPT2_HOST_X87),llvm-out-extra llvm-math-extra) \
  $(if $(OPT2_HOST_X87)$(OPT2_HOST_BSD),llvm-i686-runtime)
OPT2_TESTS := $(filter-out $(OPT2_SKIP),$(ALL_TESTS))
check-opt2: build
	@rm -rf $(OPT2_DIR); mkdir -p $(OPT2_DIR)/stage0/bin $(OPT2_DIR)/wrap0 $(OPT2_DIR)/wrap1; \
	cp $(BIN) $(OPT2_DIR)/stage0/bin/poc; \
	printf '#!/bin/sh\nexec %s -opt 2 "$$@"\n' $(OPT2_DIR)/stage0/bin/poc > $(OPT2_DIR)/wrap0/poc; \
	printf '#!/bin/sh\nexec %s -opt 2 "$$@"\n' $(OPT2_DIR)/stage1/bin/poc > $(OPT2_DIR)/wrap1/poc; \
	chmod +x $(OPT2_DIR)/wrap0/poc $(OPT2_DIR)/wrap1/poc; \
	status=0; \
	for model in O2 OC; do \
	  $(STAGE0_ENV) $(OPT2_DIR)/wrap0/poc -$$model -clear-library-path -output-dir $(OPT2_DIR)/stage0/lib/poc \
	    -library poc-rtl $(RTL_SRCS) >/dev/null || status=1; \
	done; \
	POC_BIN_DIR=$(OPT2_DIR)/wrap0 VAX_GUEST=skip test/run-tests.sh $(OPT2_TESTS) || status=1; \
	BOOTSTRAP_BUILD_DIR=$(OPT2_DIR) BOOTSTRAP_OPT=2 STAGE0_POC=$(abspath $(BUILD_DIR)/bin/poc) \
	  tools/bootstrap/stage1 || status=1; \
	BOOTSTRAP_BUILD_DIR=$(OPT2_DIR) BOOTSTRAP_OPT=2 tools/bootstrap/stage2 || status=1; \
	for model in O2 OC; do \
	  $(OPT2_DIR)/wrap1/poc -$$model -clear-library-path -output-dir $(OPT2_DIR)/stage1/lib/poc \
	    -library poc-rtl $(RTL_SRCS) >/dev/null || status=1; \
	done; \
	POC_BIN_DIR=$(OPT2_DIR)/wrap1 VAX_GUEST=skip test/run-tests.sh $(OPT2_TESTS) || status=1; \
	exit $$status

# Phase 12 step 2g: the suite with every fixture's build a whole-program
# optimization (a poc wrapper that adds -lto), against poc-rtl built with
# -lto in its own ../lib/poc, as check-opt2 does. Not part of check. The
# fixtures that test poc's command line or print clang's commands are left
# out, and so are llvm-libraries (its manifests gain a line, lto) and
# llvm-using-modules (its .sym/.o pairs are compiled to bitcode, which poc
# refuses as a .o), and llvm-debug-info (the link's optimization moves the
# lines a backtrace shows), and llvm-libraries-i686 (on NetBSD its 32-bit
# builds print -lto's warning), and llvm-lto, which tests -lto itself
# against builds without it, and llvm-object-reuse (-lto reuses no object),
# and llvm-gc-compiled-roots (its .sym and .o pair would be bitcode).
LTO_DIR := $(abspath $(BUILD_DIR)/lto)
LTO_SKIP := poc-exit-status poc-output-streams poc-opt-level poc-link-flags \
  poc-usage poc-options-after-file llvm-libraries llvm-using-modules llvm-debug-info llvm-libraries-i686 \
  llvm-lto llvm-object-reuse llvm-gc-compiled-roots
LTO_TESTS := $(filter-out $(LTO_SKIP),$(ALL_TESTS))
check-lto: build
	@rm -rf $(LTO_DIR); mkdir -p $(LTO_DIR)/bin $(LTO_DIR)/wrap; \
	cp $(BIN) $(LTO_DIR)/bin/poc; \
	printf '#!/bin/sh\nexec %s -lto "$$@"\n' $(LTO_DIR)/bin/poc > $(LTO_DIR)/wrap/poc; \
	chmod +x $(LTO_DIR)/wrap/poc; \
	status=0; \
	for model in O2 OC; do \
	  $(STAGE0_ENV) $(LTO_DIR)/wrap/poc -$$model -clear-library-path -output-dir $(LTO_DIR)/lib/poc \
	    -library poc-rtl $(RTL_SRCS) >/dev/null || status=1; \
	done; \
	POC_BIN_DIR=$(LTO_DIR)/wrap VAX_GUEST=skip test/run-tests.sh $(LTO_TESTS) || status=1; \
	exit $$status

# poc's own source stays inside Oberon2.pdf (PLAN.md, "Bootstrap
# terminology"): every module of src/ checked with -strict (Phase 11 B2),
# against the .sym files Stage 1 leaves in build/stage1/obj, under -OC, the
# size model poc is built with, by the Stage 1 poc (which, unlike voc's build,
# needs no LD_LIBRARY_PATH on the BSDs). rtl/llvm is the runtime, which needs
# SYSTEM.ADDRESS and external procedures, and is not checked. The modules of
# src/back/vax/vms, for poc built for VMS, are checked for the VAX, against
# rtl/vax's RecordFiles, LineOutput and Platform, compiled for it into
# build/strict-vms (PLAN.md Phase 18 steps 4c and 6b), not against an
# installed POCRTL, which a host need not have.
check-strict: $(STAGE1_BIN)
	@status=0; \
	for f in $(SRCS) $(NO_LLVM_SRCS); do \
	  out=$$($(STAGE1_BIN) -OC -strict -import-path $(BUILD_DIR)/stage1/obj -check $$f 2>&1); \
	  if [ "$$out" != "semantic OK" ]; then \
	    echo "$$out"; echo "check-strict: $$f uses more than Oberon2.pdf"; status=1; \
	  fi; \
	done; \
	mkdir -p $(BUILD_DIR)/strict-vms; \
	$(STAGE1_BIN) -OC -target vax-dec-vms -import-path rtl/vax -output-dir $(BUILD_DIR)/strict-vms \
	  -emit-macro32 rtl/vax/RecordFiles.Mod >/dev/null || status=1; \
	for m in LineOutput Platform; do \
	  $(STAGE1_BIN) -OC -target vax-dec-vms -import-path $(BUILD_DIR)/strict-vms -import-path rtl/vax \
	    -output-dir $(BUILD_DIR)/strict-vms -emit-macro32 rtl/vax/$$m.Mod >/dev/null || status=1; \
	done; \
	for f in $(VAX_VMS_SRCS); do \
	  out=$$($(STAGE1_BIN) -OC -strict -target vax-dec-vms -import-path $(BUILD_DIR)/strict-vms -check $$f 2>&1); \
	  if [ "$$out" != "semantic OK" ]; then \
	    echo "$$out"; echo "check-strict: $$f uses more than Oberon2.pdf"; status=1; \
	  fi; \
	done; \
	if [ $$status = 0 ]; then echo "check-strict: poc's own source is strict Oberon2.pdf"; fi; \
	exit $$status

# poc's own source also type-checks under -O2 (doc/developer/DEVELOPER.md):
# no constant wider than 32 bits, though poc is built under -OC. Twice broken
# unnoticed (Phase 15's constants in VaxCodeGenerator, the unsigned types'
# in ConstantEvaluator), so checked here: Poc.Mod and all it imports
# compiled to LLVM IR under -O2 by the Stage 1 poc, in a directory of
# their own, then every module of src/ checked against the .sym files that
# leaves.
CHECK_O2_DIR := $(BUILD_DIR)/check-o2
check-o2: $(STAGE1_BIN) $(BUILD_INFO)
	@rm -rf $(CHECK_O2_DIR); mkdir -p $(CHECK_O2_DIR); \
	status=0; \
	out=$$(cd $(CHECK_O2_DIR) && $(abspath $(STAGE1_BIN)) -O2 -clear-library-path \
	  -import-path $(abspath src/front) -import-path $(abspath src/back/llvm) \
	  -import-path $(abspath src/back/vax) -import-path $(abspath src/back/vax/host) -import-path $(abspath rtl/llvm) \
	  -import-path $(abspath src/driver) -import-path $(abspath src/driver/llvm) \
	  -import-path $(abspath $(BUILD_DIR)/gen) -emit-llvm-ir $(abspath src/driver/Poc.Mod) 2>&1) || status=1; \
	if [ $$status != 0 ]; then echo "$$out"; fi; \
	if [ $$status = 0 ]; then \
	  for f in $(SRCS) $(NO_LLVM_SRCS); do \
	    out=$$($(STAGE1_BIN) -O2 -import-path $(CHECK_O2_DIR) -check $$f 2>&1); \
	    if [ "$$out" != "semantic OK" ]; then echo "$$out"; status=1; fi; \
	  done; \
	fi; \
	if [ $$status = 0 ]; then echo "check-o2: poc's own source type-checks under -O2"; \
	else echo "check-o2: poc's own source does not type-check under -O2"; fi; \
	exit $$status

# Phase 13 step 3: make install and make uninstall, GNU make (gmake on the
# BSDs), with PREFIX, DESTDIR and the usual directories. What is installed
# is the Stage 2 poc (built by poc, so it needs no libvoc), and poc-rtl for
# this host's triple, built by it, under both size models and each twice:
# as usual, and with -g in <model>-g, which poc -g links first, so that a
# debugger sees into the runtime while other programs stay small. Both go
# where the installed poc's default library path looks, $(BINDIR)/../lib/
# poc: LIBDIR must be $(BINDIR)/../lib (or a poc run elsewhere needs
# POC_LIBRARY_PATH). poc-rtl is put there by poc -install-library itself,
# which replaces an older copy and leaves any other library alone. MANDIR
# follows each system's hier(7): share/man on Linux and FreeBSD, man on
# OpenBSD and NetBSD (pkgsrc). poc(1) goes in MANDIR/man1, the guides in
# DOCDIR, and the HTML and PDF of the guides and poc(1) (make doc, below)
# in DOCDIR/html and DOCDIR/pdf.
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
LIBDIR ?= $(PREFIX)/lib
MAN_SUBDIR := $(if $(filter OpenBSD NetBSD,$(shell uname -s)),man,share/man)
MANDIR ?= $(PREFIX)/$(MAN_SUBDIR)
DOCDIR ?= $(PREFIX)/share/doc/peaseblossom
STAGE2_BIN := $(BUILD_DIR)/stage2/bin/poc
STAGE2_LIB := $(BUILD_DIR)/stage2/lib/poc
INSTALL_MODELS := O2 OC O2-g OC-g
INSTALL_RTL := $(foreach m,$(INSTALL_MODELS),$(STAGE2_LIB)/$(HOST_TRIPLE)/$(m)/poc-rtl.library)
DOCS := README.md LICENSE doc/users-guide.md doc/reference-guide.md

# the Stage 2 poc, made (and compared with Stage 1) only when it is not there
# or Stage 1 changed; `make stage2` always remakes it
$(STAGE2_BIN): $(STAGE1_BIN)
	tools/bootstrap/stage2

# poc-rtl built by the Stage 2 poc, with -g for <model>-g (GNU make takes the
# pattern with the shorter stem, so O2-g goes to the first rule)
$(STAGE2_LIB)/$(HOST_TRIPLE)/%-g/poc-rtl.library: $(STAGE2_BIN) $(RTL_SRCS) $(RTL_C_SRCS)
	$(STAGE2_BIN) -g -$* -clear-library-path -output-dir $(STAGE2_LIB) -library poc-rtl $(RTL_SRCS)

$(STAGE2_LIB)/$(HOST_TRIPLE)/%/poc-rtl.library: $(STAGE2_BIN) $(RTL_SRCS) $(RTL_C_SRCS)
	$(STAGE2_BIN) -$* -clear-library-path -output-dir $(STAGE2_LIB) -library poc-rtl $(RTL_SRCS)

# everything install copies, built, so that a package's build step can do
# all the building and its install step only copies
# (packaging/fedora/peaseblossom.spec)
installable: $(STAGE2_BIN) $(INSTALL_RTL)

install: $(STAGE2_BIN) $(INSTALL_RTL)
	@if [ "$(abspath $(BINDIR)/../lib)" != "$(abspath $(LIBDIR))" ]; then \
	  echo "note: LIBDIR is not BINDIR/../lib: the installed poc needs POC_LIBRARY_PATH=$(LIBDIR)/poc"; \
	fi
	install -d $(DESTDIR)$(BINDIR) $(DESTDIR)$(LIBDIR)/poc $(DESTDIR)$(DOCDIR) $(DESTDIR)$(MANDIR)/man1
	install -m 755 $(STAGE2_BIN) $(DESTDIR)$(BINDIR)/poc
	install -m 644 doc/poc.1 $(DESTDIR)$(MANDIR)/man1/poc.1
	for model in O2 OC; do \
	  $(STAGE2_BIN) -$$model -clear-library-path -library-path $(STAGE2_LIB) \
	    -output-dir $(DESTDIR)$(LIBDIR)/poc -install-library poc-rtl >/dev/null || exit 1; \
	  $(STAGE2_BIN) -$$model -g -clear-library-path -library-path $(STAGE2_LIB) \
	    -output-dir $(DESTDIR)$(LIBDIR)/poc -install-library poc-rtl >/dev/null || exit 1; \
	done
	install -m 644 $(DOCS) $(DESTDIR)$(DOCDIR)
	@for kind in html pdf; do \
	  if [ -d $(DOC_DIR)/$$kind ]; then from=$(DOC_DIR)/$$kind; \
	  elif [ -d doc/$$kind ]; then from=doc/$$kind; \
	  else echo "note: no $$kind documents to install (make doc makes them)"; continue; fi; \
	  echo "install the $$kind documents from $$from in $(DESTDIR)$(DOCDIR)/$$kind"; \
	  install -d $(DESTDIR)$(DOCDIR)/$$kind || exit 1; \
	  for name in $(DOC_INSTALL_NAMES); do \
	    install -m 644 $$from/$$name.$$kind $(DESTDIR)$(DOCDIR)/$$kind/$$name.$$kind || exit 1; \
	  done; \
	done

# Removes what install wrote: poc, poc-rtl's files (those its manifests
# name), the docs; then each directory left empty. Other libraries
# installed beside poc-rtl stay.
uninstall:
	rm -f $(DESTDIR)$(BINDIR)/poc $(DESTDIR)$(MANDIR)/man1/poc.1
	@for model in $(INSTALL_MODELS); do \
	  dir=$(DESTDIR)$(LIBDIR)/poc/$(HOST_TRIPLE)/$$model; \
	  if [ -f $$dir/poc-rtl.library ]; then \
	    for m in $$(awk '$$1 == "module" { print $$2 }' $$dir/poc-rtl.library); do \
	      rm -f $$dir/$$m.sym $$dir/$$m.owner; \
	    done; \
	    echo "rm -f $$dir/poc-rtl.library $$dir/libpoc-rtl.*"; \
	    rm -f $$dir/poc-rtl.library $$dir/libpoc-rtl.a $$dir/libpoc-rtl.so*; \
	  fi; \
	  rmdir $$dir 2>/dev/null || true; \
	done
	-rmdir $(DESTDIR)$(LIBDIR)/poc/$(HOST_TRIPLE) $(DESTDIR)$(LIBDIR)/poc 2>/dev/null
	cd $(DESTDIR)$(DOCDIR) 2>/dev/null && rm -f $(notdir $(DOCS))
	-cd $(DESTDIR)$(DOCDIR) 2>/dev/null && for kind in html pdf; do \
	  for name in $(DOC_INSTALL_NAMES); do rm -f $$kind/$$name.$$kind; done; \
	  rmdir $$kind 2>/dev/null; \
	done
	-rmdir $(DESTDIR)$(DOCDIR) $(DESTDIR)$(MANDIR)/man1 $(DESTDIR)$(MANDIR) 2>/dev/null

# Installs into a scratch DESTDIR outside the source tree and runs
# test/install/check.sh with only the installed poc: no voc on PATH, no
# source tree, no POC_IMPORT_PATH or POC_LIBRARY_PATH. Then uninstalls, and
# checks that nothing is left. Every directory is given, so that none set on
# the command line (as a package's build does) reaches the inner make.
CHECK_INSTALL_DIRS := PREFIX=/usr/local BINDIR=/usr/local/bin LIBDIR=/usr/local/lib \
  MANDIR=/usr/local/$(MAN_SUBDIR) DOCDIR=/usr/local/share/doc/peaseblossom

check-install: $(STAGE2_BIN) $(INSTALL_RTL)
	@scratch=$$(mktemp -d "$${TMPDIR:-/tmp}/poc-check-install.XXXXXX") || exit 1; \
	status=0; \
	$(MAKE) --no-print-directory install DESTDIR=$$scratch/root $(CHECK_INSTALL_DIRS) >/dev/null || status=1; \
	if [ $$status = 0 ]; then \
	  test/install/check.sh $$scratch/root/usr/local/bin/poc $$scratch/work || status=1; \
	  $(MAKE) --no-print-directory uninstall DESTDIR=$$scratch/root $(CHECK_INSTALL_DIRS) >/dev/null || status=1; \
	  left=$$(cd $$scratch/root && find . -type f); \
	  if [ -n "$$left" ]; then echo "check-install: uninstall left $$left"; status=1; \
	  else echo "check-install: uninstall removed everything"; fi; \
	fi; \
	rm -rf $$scratch; \
	exit $$status

# Phase 13 step 4: the bootstrap seed, poc's own IR for 64-bit and 32-bit
# targets, from which clang alone builds a Stage 0 poc where there is no voc
# (tools/bootstrap/make-seed and stage0-seed say how), in build/seed. Not
# kept in git: make dist puts it in the release tarball, as seed/. check-seed builds a Stage 0 from the
# seed and a Stage 1 with that, in build/seedcheck, and compares that Stage
# 1's output with the voc-built one's (the same fixed point).
seed: $(STAGE2_BIN)
	tools/bootstrap/make-seed

check-seed: seed $(STAGE1_BIN)
	@dir=$(abspath $(BUILD_DIR)/seedcheck); rm -rf $$dir; \
	SEED_DIR=$(abspath $(BUILD_DIR)/seed) BOOTSTRAP_BUILD_DIR=$$dir tools/bootstrap/stage0-seed || exit 1; \
	BOOTSTRAP_BUILD_DIR=$$dir tools/bootstrap/stage1 >/dev/null || exit 1; \
	status=0; \
	for f in $(BUILD_DIR)/stage1/obj/*; do \
	  if ! cmp -s $$f $$dir/stage1/obj/$$(basename $$f); then echo "DIFFERS: $$(basename $$f)"; status=1; fi; \
	done; \
	if [ $$status = 0 ]; then echo "check-seed: Stage 1 built by the seed's poc is Stage 1 built by voc's"; fi; \
	exit $$status

# The documents as HTML and PDF, in build/doc/html and build/doc/pdf: the
# User's Guide, the Reference Guide, the VAX/VMS Guide, poc(1), and
# doc/developer's in developer/. pandoc makes the Markdown ones from GitHub's Markdown, so they
# read as GitHub shows them; mandoc makes poc(1)'s HTML and groff its PDF.
# pandoc's HTML takes tools/doc/html-header.html's styles over its own.
# Each PDF is US Letter with 1-inch margins; pandoc's go through xelatex
# and tools/doc/pdf.lua, which keeps wide tables, long code lines and long
# names within them. make dist puts them all in the tarball, as doc/html
# and doc/pdf, so that a package needs none of these tools. install
# installs only the user's ones, DOC_INSTALL_NAMES (the guides and poc(1);
# the developer documents stay in the tarball, decided with the user
# 2026-10-05; the VAX/VMS Guide's are installed by install-vax), from
# build/doc, else from doc/, else says there are none.
PANDOC ?= pandoc
MANDOC ?= mandoc
GROFF ?= groff
DOC_PDF_ENGINE ?= xelatex
DOC_MAIN_FONT ?= DejaVu Serif
DOC_MONO_FONT ?= DejaVu Sans Mono
DOC_DIR := $(BUILD_DIR)/doc
DOC_MARKDOWN := doc/users-guide.md doc/reference-guide.md doc/vax-vms-guide.md $(sort $(wildcard doc/developer/*.md))
DOC_NAMES := $(patsubst doc/%.md,%,$(DOC_MARKDOWN)) poc.1
DOC_INSTALL_NAMES := users-guide reference-guide poc.1
DOC_HTML := $(DOC_NAMES:%=$(DOC_DIR)/html/%.html)
DOC_PDF := $(DOC_NAMES:%=$(DOC_DIR)/pdf/%.pdf)
# a table of contents, unless the document has its own (## Contents)
PANDOC_FLAGS = -f gfm --shift-heading-level-by=-1 -s $$(grep -q '^\#\# Contents' $< || echo --toc)

doc: doc-html doc-pdf
doc-html: $(DOC_HTML)
doc-pdf: $(DOC_PDF)

$(DOC_DIR)/html/poc.1.html: doc/poc.1
	@mkdir -p $(@D)
	$(MANDOC) -T html $< > $@.tmp && mv $@.tmp $@

$(DOC_DIR)/pdf/poc.1.pdf: doc/poc.1
	@mkdir -p $(@D)
	$(GROFF) -mdoc -Tpdf -P-pletter $< > $@.tmp && mv $@.tmp $@

$(DOC_DIR)/html/%.html: doc/%.md tools/doc/html-header.html
	@mkdir -p $(@D)
	$(PANDOC) $(PANDOC_FLAGS) -H tools/doc/html-header.html -t html5 $< -o $@

$(DOC_DIR)/pdf/%.pdf: doc/%.md tools/doc/pdf.lua tools/doc/pdf-header.tex
	@mkdir -p $(@D)
	$(PANDOC) $(PANDOC_FLAGS) --pdf-engine=$(DOC_PDF_ENGINE) \
	  -H tools/doc/pdf-header.tex --lua-filter=tools/doc/pdf.lua \
	  -V papersize=letter -V geometry:margin=1in \
	  -V mainfont="$(DOC_MAIN_FONT)" -V monofont="$(DOC_MONO_FONT)" $< -o $@

# The other documents, for reading here and never in the tarball:
# doc/README.md, doc/research's and doc/history's, made as make doc makes
# its own, in build/doc-other/html and build/doc-other/pdf, since make dist
# copies build/doc's whole. make doc-all makes these and make doc's.
DOC_OTHER_DIR := $(BUILD_DIR)/doc-other
DOC_OTHER_MARKDOWN := doc/README.md $(sort $(wildcard doc/research/*.md) \
  $(wildcard doc/history/*.md) $(wildcard doc/history/*/*.md))
DOC_OTHER_NAMES := $(patsubst doc/%.md,%,$(DOC_OTHER_MARKDOWN))
DOC_OTHER_HTML := $(DOC_OTHER_NAMES:%=$(DOC_OTHER_DIR)/html/%.html)
DOC_OTHER_PDF := $(DOC_OTHER_NAMES:%=$(DOC_OTHER_DIR)/pdf/%.pdf)

doc-all: doc doc-other-html doc-other-pdf
doc-other-html: $(DOC_OTHER_HTML)
doc-other-pdf: $(DOC_OTHER_PDF)

$(DOC_OTHER_DIR)/html/%.html: doc/%.md tools/doc/html-header.html
	@mkdir -p $(@D)
	$(PANDOC) $(PANDOC_FLAGS) -H tools/doc/html-header.html -t html5 $< -o $@

$(DOC_OTHER_DIR)/pdf/%.pdf: doc/%.md tools/doc/pdf.lua tools/doc/pdf-header.tex
	@mkdir -p $(@D)
	$(PANDOC) $(PANDOC_FLAGS) --pdf-engine=$(DOC_PDF_ENGINE) \
	  -H tools/doc/pdf-header.tex --lua-filter=tools/doc/pdf.lua \
	  -V papersize=letter -V geometry:margin=1in \
	  -V mainfont="$(DOC_MAIN_FONT)" -V monofont="$(DOC_MONO_FONT)" $< -o $@

# Phase 13 step 5: make dist writes build/dist/peaseblossom-<version>.tar.gz
# and its SHA-256 sum: the tracked files of HEAD (git archive, so no build
# products or test outputs), the bootstrap seed as seed/, the two kits of
# poc for VAX/VMS as vax/POC-<version>.COM and vax/POC-VMS-<version>.COM
# (Phase 17 step 7), which are also written beside the tarball, the
# documents as
# HTML and PDF in doc/html and doc/pdf (make doc), and COMMIT, the
# commit, which tools/build-info reads where there is no .git. Refused
# unless the tracked files are HEAD's and the Stage 2 poc that writes the
# seed was built from them (its -version names HEAD, not -dirty), so the
# seed is the source's. make distcheck unpacks the tarball in a scratch
# directory and, with voc out of reach, builds poc from its seed and runs
# make check-install there, then make check-install-vax, which takes the
# kits and the guide as text from the tarball (pandoc out of reach too).
VERSION := $(shell sed -n 's/^ *number\* *= *"\(.*\)";.*/\1/p' src/driver/Version.Mod)
DIST_NAME := peaseblossom-$(VERSION)
DIST_DIR := $(BUILD_DIR)/dist
DIST_TARBALL := $(DIST_DIR)/$(DIST_NAME).tar.gz
# Phase 17 step 7: the kits of poc for VAX/VMS, the base kit and the
# STARLET kit (tools/bootstrap/make-vax-kit), in the tarball as vax/ and
# beside it, each a release's file of its own
VAX_KIT_NAMES := POC-$(subst .,-,$(VERSION)).COM POC-VMS-$(subst .,-,$(VERSION)).COM

dist: $(STAGE2_BIN) doc
	@git diff --quiet HEAD -- || { echo "dist: the tracked files differ from HEAD; commit first"; exit 1; }
	@head=$$(git rev-parse --short HEAD); \
	built=$$($(STAGE2_BIN) -version | sed -n '1s/^poc [^ ]* (\(.*\))$$/\1/p'); \
	if [ "$$built" != "$$head" ]; then \
	  echo "dist: the Stage 2 poc was built from '$$built', not $$head; make stage2 first"; exit 1; \
	fi
	rm -rf $(DIST_DIR); mkdir -p $(DIST_DIR)
	git archive --prefix=$(DIST_NAME)/ HEAD | tar -xf - -C $(DIST_DIR)
	git rev-parse --short HEAD > $(DIST_DIR)/$(DIST_NAME)/COMMIT
	cp -R $(DOC_DIR)/html $(DOC_DIR)/pdf $(DIST_DIR)/$(DIST_NAME)/doc/
	mkdir -p $(DIST_DIR)/$(DIST_NAME)/doc/text
	PANDOC=$(PANDOC) tools/doc/plain-text doc/vax-vms-guide.md $(DIST_DIR)/$(DIST_NAME)/doc/text/vax-vms-guide.txt
	SEED_DIR=$(abspath $(DIST_DIR)/$(DIST_NAME)/seed) tools/bootstrap/make-seed
	PANDOC=$(PANDOC) POC_BIN_DIR=$(abspath $(dir $(STAGE2_BIN))) VAX_KIT_DIR=$(abspath $(DIST_DIR)/vax-kit) \
	  tools/bootstrap/make-vax-kit >/dev/null
	mkdir -p $(DIST_DIR)/$(DIST_NAME)/vax
	cd $(DIST_DIR)/vax-kit && cp $(VAX_KIT_NAMES) ../$(DIST_NAME)/vax/ && mv $(VAX_KIT_NAMES) ..
	rm -rf $(DIST_DIR)/vax-kit
	cd $(DIST_DIR) && tar -cf - $(DIST_NAME) | gzip -9 > $(DIST_NAME).tar.gz
	cd $(DIST_DIR) && if command -v sha256sum >/dev/null; then sha256sum $(DIST_NAME).tar.gz; \
	  else sha256 -r $(DIST_NAME).tar.gz; fi > $(DIST_NAME).tar.gz.sha256
	rm -rf $(DIST_DIR)/$(DIST_NAME)
	@echo "dist: wrote $(DIST_TARBALL) ($$(wc -c < $(DIST_TARBALL)) bytes)"

# a detached, ASCII-armored GPG signature of the tarball, <tarball>.asc,
# with gpg's default key (GPG_KEY names another): optional, made when the
# person releasing chooses to (decided with the user, Phase 13 step 5)
dist-sign:
	@test -f $(DIST_TARBALL) || { echo "dist-sign: no $(DIST_TARBALL); make dist first"; exit 1; }
	gpg --armor --detach-sign $(if $(GPG_KEY),--local-user $(GPG_KEY)) --output $(DIST_TARBALL).asc $(DIST_TARBALL)

distcheck: dist
	@scratch=$$(mktemp -d "$${TMPDIR:-/tmp}/poc-distcheck.XXXXXX") || exit 1; \
	status=0; \
	gzip -dc $(DIST_TARBALL) | tar -xf - -C $$scratch || status=1; \
	if [ $$status = 0 ]; then \
	  (cd $$scratch/$(DIST_NAME) && unset POC_IMPORT_PATH POC_LIBRARY_PATH && \
	   $(MAKE) --no-print-directory VOC_BIN_DIR=/nonexistent check-install && \
	   PANDOC=/nonexistent $(MAKE) --no-print-directory VOC_BIN_DIR=/nonexistent check-install-vax) \
	    || status=1; \
	  ver=$$($$scratch/$(DIST_NAME)/build/bin/poc -version 2>/dev/null | sed -n 1p); \
	  echo "distcheck: the tarball's poc says: $$ver"; \
	fi; \
	rm -rf $$scratch; \
	if [ $$status = 0 ]; then echo "distcheck: $(DIST_NAME).tar.gz builds without voc and installs"; fi; \
	exit $$status

# What the VAX/VMS target needs on Unix besides poc (Phase 17's exit
# review; decided with the user 2026-10-17), for a peaseblossom-vax
# package or a build from source: make install-vax installs the libraries
# POCRTL, VMSDEF and VMSLIB for vax-dec-vms, under -O2 and -OC, beside
# poc-rtl in LIBDIR/poc, where poc -target vax-dec-vms finds them with no
# -import-path; the two kits of poc for VAX/VMS (make vax-kit) in
# VAXKITDIR, since a program built against those libraries needs the
# same version's kit on VMS; and the VAX/VMS Guide in VAXDOCDIR, as text
# (tools/doc/plain-text, as the kit has it) and, when make doc has made
# them, as HTML and PDF. rtl/vax's source is not installed: the libraries
# hold each module's .mar and .sym, and the kit the source. The libraries
# are built by the Stage 2 poc in build/stage2/lib/poc, as poc-rtl is,
# and so are the kits, in build/stage2/vax-kit. uninstall-vax removes
# what install-vax wrote, the libraries' files by their manifests.
# check-install-vax installs poc and them into a scratch DESTDIR and runs
# test/install/check-vax.sh, which builds programs for the VAX with the
# installed poc alone, then uninstalls both and checks that nothing is
# left. None of these uses the guest. VAX_GUIDE=no leaves the guide as
# text out: of the kits, which then go in build/stage2/vax-kit-without-guide
# so that a kit without it is never taken for one with it, and of what
# install-vax installs. check-install-vax sets it itself, and says so,
# when there is neither pandoc to write the guide nor the tarball's copy
# (a git checkout on a host without pandoc); nothing else does.
VAX_GUIDE ?= yes
DATADIR ?= $(PREFIX)/share
VAXKITDIR ?= $(DATADIR)/peaseblossom/vax
# the VAX/VMS Guide's own directory, apart from install's DOCDIR, as the
# peaseblossom-vax package keeps it
VAXDOCDIR ?= $(PREFIX)/share/doc/peaseblossom-vax
VAX_LIB := $(STAGE2_LIB)/vax-dec-vms
VAX_LIBRARIES := POCRTL VMSDEF VMSLIB
VAX_RTL_SRCS := $(sort $(wildcard rtl/vax/*.Mod)) rtl/vax/PocRtl.mar
VMSDEF_SRCS := $(sort $(wildcard rtl/vax/vms/*.Mod))
VMSLIB_SRCS := $(sort $(wildcard rtl/vax/vmslib/*.Mod))
INSTALL_VAX_LIBS := $(foreach m,O2 OC,$(foreach l,$(VAX_LIBRARIES),$(VAX_LIB)/$(m)/$(l).library))
VAX_KIT_DIR := $(BUILD_DIR)/stage2/vax-kit$(if $(filter no,$(VAX_GUIDE)),-without-guide)
VAX_KITS := $(VAX_KIT_NAMES:%=$(VAX_KIT_DIR)/%)
VAX_GUIDE_TEXT := $(DOC_DIR)/vax-vms-guide.txt
# in the release tarball, made by make dist, the kits (vax/) and the guide
# as text (doc/text/) are there already: installed from there, as install
# takes the tarball's doc/html, so that a package builds only the
# libraries, needing neither pandoc nor the VAX cross-compile of poc
VAX_KIT_SOURCES := $(if $(wildcard $(VAX_KIT_NAMES:%=vax/%)),$(VAX_KIT_NAMES:%=vax/%),$(VAX_KITS))
VAX_GUIDE_TEXT_SOURCE := $(if $(filter no,$(VAX_GUIDE)),,$(or $(wildcard doc/text/vax-vms-guide.txt),$(VAX_GUIDE_TEXT)))

$(VAX_LIB)/%/POCRTL.library: $(STAGE2_BIN) $(VAX_RTL_SRCS)
	@echo "POCRTL for vax-dec-vms -$*"
	@$(STAGE2_BIN) -$* -target vax-dec-vms -clear-library-path -output-dir $(STAGE2_LIB) \
	  -library POCRTL $(VAX_RTL_SRCS) >/dev/null

$(VAX_LIB)/%/VMSDEF.library: $(VAX_LIB)/%/POCRTL.library $(VMSDEF_SRCS)
	@echo "VMSDEF for vax-dec-vms -$*"
	@$(STAGE2_BIN) -$* -target vax-dec-vms -clear-library-path -library-path $(STAGE2_LIB) \
	  -output-dir $(STAGE2_LIB) -library VMSDEF $(VMSDEF_SRCS) >/dev/null

$(VAX_LIB)/%/VMSLIB.library: $(VAX_LIB)/%/VMSDEF.library $(VMSLIB_SRCS)
	@echo "VMSLIB for vax-dec-vms -$*"
	@$(STAGE2_BIN) -$* -target vax-dec-vms -clear-library-path -library-path $(STAGE2_LIB) \
	  -output-dir $(STAGE2_LIB) -library VMSLIB $(VMSLIB_SRCS) >/dev/null

# both kits from one run of make-vax-kit, remade when any source of theirs
# changes (poc's, the runtime's, the templates or the guide)
$(VAX_KITS) &: $(STAGE2_BIN) $(VAX_RTL_SRCS) $(VMSDEF_SRCS) $(VMSLIB_SRCS) doc/vax-vms-guide.md \
    tools/bootstrap/make-vax-kit tools/doc/plain-text $(wildcard tools/bootstrap/vax-kit/*)
	PANDOC=$(PANDOC) POC_BIN_DIR=$(abspath $(dir $(STAGE2_BIN))) VAX_KIT_DIR=$(abspath $(VAX_KIT_DIR)) \
	  VAX_KIT_GUIDE=$(VAX_GUIDE) tools/bootstrap/make-vax-kit >/dev/null

$(VAX_GUIDE_TEXT): doc/vax-vms-guide.md tools/doc/plain-text
	@mkdir -p $(@D)
	PANDOC=$(PANDOC) tools/doc/plain-text $< $@

installable-vax: $(INSTALL_VAX_LIBS) $(VAX_KIT_SOURCES) $(VAX_GUIDE_TEXT_SOURCE)

install-vax: $(INSTALL_VAX_LIBS) $(VAX_KIT_SOURCES) $(VAX_GUIDE_TEXT_SOURCE)
	install -d $(DESTDIR)$(LIBDIR)/poc $(DESTDIR)$(VAXKITDIR) $(DESTDIR)$(VAXDOCDIR)
	for model in O2 OC; do \
	  for library in $(VAX_LIBRARIES); do \
	    $(STAGE2_BIN) -$$model -target vax-dec-vms -clear-library-path -library-path $(STAGE2_LIB) \
	      -output-dir $(DESTDIR)$(LIBDIR)/poc -install-library $$library >/dev/null || exit 1; \
	  done; \
	done
	install -m 644 $(VAX_KIT_SOURCES) $(DESTDIR)$(VAXKITDIR)
	$(if $(VAX_GUIDE_TEXT_SOURCE),install -m 644 $(VAX_GUIDE_TEXT_SOURCE) $(DESTDIR)$(VAXDOCDIR)/vax-vms-guide.txt)
	@for kind in html pdf; do \
	  if [ -f $(DOC_DIR)/$$kind/vax-vms-guide.$$kind ]; then from=$(DOC_DIR)/$$kind; \
	  elif [ -f doc/$$kind/vax-vms-guide.$$kind ]; then from=doc/$$kind; \
	  else echo "note: no $$kind VAX/VMS Guide to install (make doc makes it)"; continue; fi; \
	  echo "install the $$kind VAX/VMS Guide from $$from in $(DESTDIR)$(VAXDOCDIR)/$$kind"; \
	  install -d $(DESTDIR)$(VAXDOCDIR)/$$kind || exit 1; \
	  install -m 644 $$from/vax-vms-guide.$$kind $(DESTDIR)$(VAXDOCDIR)/$$kind/ || exit 1; \
	done

uninstall-vax:
	@for model in O2 OC; do \
	  dir=$(DESTDIR)$(LIBDIR)/poc/vax-dec-vms/$$model; \
	  for library in $(VAX_LIBRARIES); do \
	    if [ -f $$dir/$$library.library ]; then \
	      for m in $$(awk '$$1 == "module" { print $$2 }' $$dir/$$library.library); do \
	        rm -f $$dir/$$m.mar $$dir/$$m.sym $$dir/$$m.owner; \
	      done; \
	      for p in $$(awk '$$1 == "part" { print $$2 }' $$dir/$$library.library); do \
	        rm -f $$dir/$$p.mar; \
	      done; \
	      echo "rm -f $$dir/$$library.library $$dir/$${library}_build.com $$dir/$${library}_setup.com"; \
	      rm -f $$dir/$$library.library $$dir/$${library}_build.com $$dir/$${library}_setup.com; \
	    fi; \
	  done; \
	  rmdir $$dir 2>/dev/null || true; \
	done
	@# each directory removed if it is empty: uninstall empties poc-rtl's
	rmdir $(DESTDIR)$(LIBDIR)/poc/vax-dec-vms $(DESTDIR)$(LIBDIR)/poc 2>/dev/null || true
	cd $(DESTDIR)$(VAXKITDIR) 2>/dev/null && rm -f $(VAX_KIT_NAMES) || true
	rmdir $(DESTDIR)$(VAXKITDIR) $(DESTDIR)$(DATADIR)/peaseblossom 2>/dev/null || true
	cd $(DESTDIR)$(VAXDOCDIR) 2>/dev/null && rm -f vax-vms-guide.txt || true
	cd $(DESTDIR)$(VAXDOCDIR) 2>/dev/null && for kind in html pdf; do \
	  rm -f $$kind/vax-vms-guide.$$kind; rmdir $$kind 2>/dev/null; \
	done || true
	rmdir $(DESTDIR)$(VAXDOCDIR) 2>/dev/null || true

check-install-vax:
	@if [ -f doc/text/vax-vms-guide.txt ] || command -v $(PANDOC) >/dev/null 2>&1; then \
	  $(MAKE) --no-print-directory check-install-vax-run; \
	else \
	  echo "check-install-vax: no pandoc ($(PANDOC)) to write the VAX/VMS Guide as text: kits and install without it"; \
	  $(MAKE) --no-print-directory VAX_GUIDE=no check-install-vax-run; \
	fi

check-install-vax-run: $(STAGE2_BIN) $(INSTALL_RTL) $(INSTALL_VAX_LIBS) $(VAX_KIT_SOURCES) $(VAX_GUIDE_TEXT_SOURCE)
	@scratch=$$(mktemp -d "$${TMPDIR:-/tmp}/poc-check-install-vax.XXXXXX") || exit 1; \
	status=0; \
	for target in install install-vax; do \
	  $(MAKE) --no-print-directory $$target DESTDIR=$$scratch/root $(CHECK_INSTALL_DIRS) \
	    DATADIR=/usr/local/share VAXKITDIR=/usr/local/share/peaseblossom/vax \
	    VAXDOCDIR=/usr/local/share/doc/peaseblossom-vax >/dev/null || status=1; \
	done; \
	if [ $$status = 0 ]; then \
	  VAX_GUIDE=$(VAX_GUIDE) test/install/check-vax.sh $$scratch/root/usr/local/bin/poc $$scratch/work \
	    $(abspath tools/bootstrap/vax-kit/check) $$scratch/root/usr/local/share/peaseblossom/vax \
	    $$scratch/root/usr/local/share/doc/peaseblossom-vax || status=1; \
	  for target in uninstall-vax uninstall; do \
	    $(MAKE) --no-print-directory $$target DESTDIR=$$scratch/root $(CHECK_INSTALL_DIRS) \
	      DATADIR=/usr/local/share VAXKITDIR=/usr/local/share/peaseblossom/vax \
	    VAXDOCDIR=/usr/local/share/doc/peaseblossom-vax >/dev/null || status=1; \
	  done; \
	  left=$$(cd $$scratch/root && find . -type f); \
	  if [ -n "$$left" ]; then echo "check-install-vax: uninstall left $$left"; status=1; \
	  else echo "check-install-vax: uninstall removed everything"; fi; \
	fi; \
	rm -rf $$scratch; \
	exit $$status

# The rest of a release (doc/developer/DEVELOPER.md, section 7):
# set-version sets VERSION, given on the command line, in Version.Mod and
# every package (tools/set-version); check-hosts checks the tree on every
# host at once (tools/check-hosts: CHECK_HOSTS names other hosts,
# CHECK_TARGETS adds targets to each run, CHECK_COMMIT checks a commit
# instead of the tree); release-files gathers and signs the files a release
# attaches in build/release/<version> (tools/release-files).
set-version:
	@test "$(origin VERSION)" = "command line" || { echo "set-version: give the version, make set-version VERSION=x.y.z"; exit 1; }
	tools/set-version $(VERSION)

check-hosts:
	tools/check-hosts $(if $(CHECK_COMMIT),-c $(CHECK_COMMIT)) $(addprefix -t ,$(CHECK_TARGETS)) $(CHECK_HOSTS)

release-files:
	tools/release-files

# Runs every fixture in one pass (not category-by-category as separate
# make prerequisites) so one "make test" always reports the full picture,
# rather than GNU Make's normal fail-fast stopping at the first failing
# prerequisite target.
test: build $(VAX_IMAGE_BIN)
	test/run-tests.sh $(ALL_TESTS)

test-lexer: build
	test/run-tests.sh $(LEXER_TESTS)

test-parser: build
	test/run-tests.sh $(PARSER_TESTS)

test-semantic: build
	test/run-tests.sh $(SEMANTIC_TESTS)

test-modules: build
	test/run-tests.sh $(MODULE_TESTS)

test-layout: build
	test/run-tests.sh $(LAYOUT_TESTS)

test-llvm: build
	test/run-tests.sh $(LLVM_TESTS)

test-misc: build $(VAX_IMAGE_BIN)
	test/run-tests.sh $(MISC_TESTS)

# PLAN.md Phase 16 step 5: the programs test/vax-suite.list names, built
# for the VAX and run on the VAX/VMS development system, each compared with
# the same program built by the LLVM backend and run here (tools/vax-suite;
# doc/developer/vax-macro32-backend.md, section 16), each built both ways,
# from MACRO-32 and from poc's objects (VAX_WAYS=macro32 or objects for one;
# Phase 18 step 6d). Not part of make test: it needs the guest, and holds it
# for the whole run.
test-vax: build
	tools/vax-suite

# PLAN.md Phase 16 step 6: the bootstrap on VAX/VMS (doc/developer/
# vax-macro32-backend.md, section 17). vax-v1 cross-compiles poc's own
# source for the VAX here; vax-stages links it on the guest, compiles poc
# there with it (V2) and with V2's image (V3), and compares their output
# with V1's: objects, or .mar with VAX_STAGES_FLAGS=-way macro32 (PLAN.md
# Phase 18 step 7). Not part of make check: vax-stages holds the guest for
# about an hour and a half.
vax-v1: build
	tools/bootstrap/vax-v1

# PLAN.md Phase 16 step 6: the fixtures' compilations under poc on the
# guest (V1's image), each compared with the host's poc for the VAX
# (tools/vax-guest-poc; doc/developer/vax-macro32-backend.md, section 17).
# Not part of make check: it holds the guest for the whole run.
test-vax-guest-poc: build
	tools/vax-guest-poc

# PLAN.md Phase 17 step 8: the AST fixtures, whose failures are a matter
# of chance, with VAX_REPEAT (test/vaxfixture.sh, vax_do): each builds its
# programs once on the guest and runs them VAX_ASTS_REPEAT times (default
# 20), printing only where a later run differs from the first. Two at a
# time, one on each of the guest's accounts. Not part of make check: it
# holds both accounts, about five minutes at 20.
VAX_ASTS_REPEAT ?= 20
VAX_AST_TESTS = vax-asts vax-asts-heap vax-conditions-handlers vax-subprocesses

test-vax-asts: build
	VAX_REPEAT=$(VAX_ASTS_REPEAT) test/run-tests.sh -j 2 $(VAX_AST_TESTS)

VAX_STAGES_FLAGS ?=

vax-stages: build
	tools/bootstrap/vax-stages $(VAX_STAGES_FLAGS)

# PLAN.md Phase 18 step 3: build/bin/vax-image, which runs a VAX object's
# records (MACRO's, as DUMP/RECORD's text, or poc's) into the image
# VaxImage prints (tools/vax-image/ObjectImage.Mod; tools/vax-macro-image;
# doc/developer/vax-object-language.md, section 14.5). Built with the poc
# of this tree; VAX_IMAGE_BIN is defined near the top, since the test
# targets need it (every VAX fixture reads poc's objects back with it).

vax-image: $(VAX_IMAGE_BIN)

$(VAX_IMAGE_BIN): $(BIN) $(call RTL_LIBRARIES,$(BUILD_DIR)) tools/vax-image/ObjectImage.Mod src/back/vax/VaxImage.Mod
	$(STAGE0_ENV) $(BIN) -OC -import-path src/back/vax -output-dir $(BUILD_DIR)/vax-image -o $@ tools/vax-image/ObjectImage.Mod

# PLAN.md Phase 17 step 7: poc for VAX/VMS as two text files, each a DCL
# procedure that unpacks itself on VMS (doc/developer/vax-macro32-backend.md,
# section 21): vax-kit writes them, build/vax-kit/POC-<version>.COM, poc,
# and POC-VMS-<version>.COM, VMSDEF and VMSLIB, on this host alone;
# check-vax-kit installs them on the guest, as a site would, and builds
# and runs programs with them (CHECK_VAX_KIT_FLAGS=-full also checks
# the fixed point there). Not part of make check: check-vax-kit holds the
# guest for an hour or more.
vax-kit: build
	PANDOC=$(PANDOC) tools/bootstrap/make-vax-kit

check-vax-kit: build
	tools/bootstrap/check-vax-kit $(CHECK_VAX_KIT_FLAGS)

# Removes poc's own build output (tools/bootstrap/stage0's target).
clean-build:
	rm -rf $(BUILD_DIR)

# Removes generated conformance-test artifacts, without running any
# tests. Reuses test/testenv.sh itself for this - sourcing it already
# performs exactly this cleanup as its first side effect (see that
# file's own header comment) - rather than keeping a second copy of its
# artifact-pattern list here to go stale against.
clean-tests:
	@for name in $(ALL_TESTS); do \
	  (cd $(CONFORMANCE_DIR)/$$name && . ../../testenv.sh >/dev/null); \
	done

clean: clean-build clean-tests
