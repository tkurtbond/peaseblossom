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
BACK_VAX_SRCS := $(wildcard src/back/vax/*.Mod)
DRIVER_SRCS := src/driver/Version.Mod src/driver/Libraries.Mod src/driver/Poc.Mod
# Phase 13 step 1: the commit `poc -version` names, written by tools/build-info
# on every make (it rewrites the file only when the commit or the tree's state
# changed, so only then is poc rebuilt)
BUILD_INFO := $(BUILD_DIR)/gen/BuildInfo.Mod
RTL_SRCS := $(wildcard rtl/llvm/*.Mod)
# Phase 12 step 5a: the C part of an rtl module, compiled with it by poc
RTL_C_SRCS := $(wildcard rtl/llvm/*.c)
# what Stage 0 builds with voc besides src/: Err and what it needs (Phase 11 D11)
STAGE0_RTL_SRCS := rtl/voc/FileDescriptorOutput.Mod rtl/llvm/RealDigits.Mod \
  rtl/llvm/FormattedOutput.Mod rtl/llvm/Err.Mod
STAGE1_BIN := $(BUILD_DIR)/stage1/bin/poc
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

.PHONY: FORCE all build install uninstall check-install seed check-seed dist dist-sign distcheck stage1 stage2 test-stage1 check check-strict check-opt2 check-lto test test-lexer test-parser test-semantic test-modules test-layout test-llvm test-misc clean clean-build clean-tests

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
# bootstrap root and the comparison oracle.
test-stage1: $(STAGE1_BIN) $(call RTL_LIBRARIES,$(BUILD_DIR)/stage1)
	POC_BIN_DIR=$(abspath $(BUILD_DIR)/stage1/bin) test/run-tests.sh $(ALL_TESTS)

# Both compilers and the fixed point: the suite under the voc-built poc, the
# suite under the poc-built one, then the Stage 1/Stage 2 comparison. Each
# part runs whatever an earlier one did, so a single run shows every failure.
check:
	@status=0; \
	$(MAKE) test || status=1; \
	$(MAKE) test-stage1 || status=1; \
	$(MAKE) stage2 || status=1; \
	$(MAKE) check-strict || status=1; \
	exit $$status

# Phase 11 D13: everything built with poc -opt 2 (clang -O2), including
# 32-bit x86, whose default is -O0 (LLVMToolchainDriver.
# DefaultOptimizationLevel) - the gate -O2 passed before it became the
# default elsewhere. The suite with every fixture's build optimized (a poc
# wrapper that adds -opt 2), then Stage 1 and Stage 2 built optimized in
# build/opt2 and compared, then the suite under that Stage 1.
# poc-exit-status, poc-output-streams and poc-opt-level test poc's command
# line, which the wrapper changes, so they are left out. So are the fixtures
# whose exact real results x87 arithmetic changes when optimized (the
# reason for the -O0 default): llvm-out-extra and llvm-math-extra on a
# 32-bit x86 host, and llvm-i686-runtime, which reruns them for 32-bit x86,
# on a 32-bit x86 host or a BSD (Linux i686 has SSE2). Each suite's poc has
# poc-rtl built optimized in its own ../lib/poc (Phase 12 steps 2d, 2e), as
# make builds it for build/bin/poc: the Stage 0 poc is copied to
# build/opt2/stage0/bin for that, so that its library path does not also
# have build/lib/poc's.
OPT2_DIR := $(abspath $(BUILD_DIR)/opt2)
OPT2_HOST_X87 := $(filter i386 i486 i586 i686,$(shell uname -m))
OPT2_HOST_BSD := $(filter-out Linux,$(shell uname -s))
OPT2_SKIP := poc-exit-status poc-output-streams poc-opt-level \
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
	POC_BIN_DIR=$(OPT2_DIR)/wrap0 test/run-tests.sh $(OPT2_TESTS) || status=1; \
	BOOTSTRAP_BUILD_DIR=$(OPT2_DIR) BOOTSTRAP_OPT=2 STAGE0_POC=$(abspath $(BUILD_DIR)/bin/poc) \
	  tools/bootstrap/stage1 || status=1; \
	BOOTSTRAP_BUILD_DIR=$(OPT2_DIR) BOOTSTRAP_OPT=2 tools/bootstrap/stage2 || status=1; \
	for model in O2 OC; do \
	  $(OPT2_DIR)/wrap1/poc -$$model -clear-library-path -output-dir $(OPT2_DIR)/stage1/lib/poc \
	    -library poc-rtl $(RTL_SRCS) >/dev/null || status=1; \
	done; \
	POC_BIN_DIR=$(OPT2_DIR)/wrap1 test/run-tests.sh $(OPT2_TESTS) || status=1; \
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
# against builds without it.
LTO_DIR := $(abspath $(BUILD_DIR)/lto)
LTO_SKIP := poc-exit-status poc-output-streams poc-opt-level poc-link-flags \
  llvm-libraries llvm-using-modules llvm-debug-info llvm-libraries-i686 \
  llvm-lto
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
	POC_BIN_DIR=$(LTO_DIR)/wrap test/run-tests.sh $(LTO_TESTS) || status=1; \
	exit $$status

# poc's own source stays inside Oberon2.pdf (PLAN.md, "Bootstrap
# terminology"): every module of src/ checked with -strict (Phase 11 B2),
# against the .sym files Stage 1 leaves in build/stage1/obj, under -OC, the
# size model poc is built with, by the Stage 1 poc (which, unlike voc's build,
# needs no LD_LIBRARY_PATH on the BSDs). rtl/llvm is the runtime, which needs
# SYSTEM.ADDRESS and external procedures, and is not checked.
check-strict: $(STAGE1_BIN)
	@status=0; \
	for f in $(SRCS); do \
	  out=$$($(STAGE1_BIN) -OC -strict -import-path $(BUILD_DIR)/stage1/obj -check $$f 2>&1); \
	  if [ "$$out" != "semantic OK" ]; then \
	    echo "$$out"; echo "check-strict: $$f uses more than Oberon2.pdf"; status=1; \
	  fi; \
	done; \
	if [ $$status = 0 ]; then echo "check-strict: poc's own source is strict Oberon2.pdf"; fi; \
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
# OpenBSD and NetBSD (pkgsrc). poc(1) and the guides come with steps 6-7.
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
LIBDIR ?= $(PREFIX)/lib
MANDIR ?= $(PREFIX)/$(if $(filter OpenBSD NetBSD,$(shell uname -s)),man,share/man)
DOCDIR ?= $(PREFIX)/share/doc/peaseblossom
STAGE2_BIN := $(BUILD_DIR)/stage2/bin/poc
STAGE2_LIB := $(BUILD_DIR)/stage2/lib/poc
INSTALL_MODELS := O2 OC O2-g OC-g
INSTALL_RTL := $(foreach m,$(INSTALL_MODELS),$(STAGE2_LIB)/$(HOST_TRIPLE)/$(m)/poc-rtl.library)
DOCS := README.md LICENSE doc/users-guide.md

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

install: $(STAGE2_BIN) $(INSTALL_RTL)
	@if [ "$(abspath $(BINDIR)/../lib)" != "$(abspath $(LIBDIR))" ]; then \
	  echo "note: LIBDIR is not BINDIR/../lib: the installed poc needs POC_LIBRARY_PATH=$(LIBDIR)/poc"; \
	fi
	install -d $(DESTDIR)$(BINDIR) $(DESTDIR)$(LIBDIR)/poc $(DESTDIR)$(DOCDIR)
	install -m 755 $(STAGE2_BIN) $(DESTDIR)$(BINDIR)/poc
	for model in O2 OC; do \
	  $(STAGE2_BIN) -$$model -clear-library-path -library-path $(STAGE2_LIB) \
	    -output-dir $(DESTDIR)$(LIBDIR)/poc -install-library poc-rtl >/dev/null || exit 1; \
	  $(STAGE2_BIN) -$$model -g -clear-library-path -library-path $(STAGE2_LIB) \
	    -output-dir $(DESTDIR)$(LIBDIR)/poc -install-library poc-rtl >/dev/null || exit 1; \
	done
	install -m 644 $(DOCS) $(DESTDIR)$(DOCDIR)

# Removes what install wrote: poc, poc-rtl's files (those its manifests
# name), the docs; then each directory left empty. Other libraries
# installed beside poc-rtl stay.
uninstall:
	rm -f $(DESTDIR)$(BINDIR)/poc
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
	-rmdir $(DESTDIR)$(DOCDIR) 2>/dev/null

# Installs into a scratch DESTDIR outside the source tree and runs
# test/install/check.sh with only the installed poc: no voc on PATH, no
# source tree, no POC_IMPORT_PATH or POC_LIBRARY_PATH. Then uninstalls, and
# checks that nothing is left.
check-install: $(STAGE2_BIN) $(INSTALL_RTL)
	@scratch=$$(mktemp -d "$${TMPDIR:-/tmp}/poc-check-install.XXXXXX") || exit 1; \
	status=0; \
	$(MAKE) --no-print-directory install DESTDIR=$$scratch/root PREFIX=/usr/local >/dev/null || status=1; \
	if [ $$status = 0 ]; then \
	  test/install/check.sh $$scratch/root/usr/local/bin/poc $$scratch/work || status=1; \
	  $(MAKE) --no-print-directory uninstall DESTDIR=$$scratch/root PREFIX=/usr/local >/dev/null || status=1; \
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

# Phase 13 step 5: make dist writes build/dist/peaseblossom-<version>.tar.gz
# and its SHA-256 sum: the tracked files of HEAD (git archive, so no build
# products or test outputs), the bootstrap seed as seed/, and COMMIT, the
# commit, which tools/build-info reads where there is no .git. Refused
# unless the tracked files are HEAD's and the Stage 2 poc that writes the
# seed was built from them (its -version names HEAD, not -dirty), so the
# seed is the source's. make distcheck unpacks the tarball in a scratch
# directory and, with voc out of reach, builds poc from its seed and runs
# make check-install there.
VERSION := $(shell sed -n 's/^ *number\* *= *"\(.*\)";.*/\1/p' src/driver/Version.Mod)
DIST_NAME := peaseblossom-$(VERSION)
DIST_DIR := $(BUILD_DIR)/dist
DIST_TARBALL := $(DIST_DIR)/$(DIST_NAME).tar.gz

dist: $(STAGE2_BIN)
	@git diff --quiet HEAD -- || { echo "dist: the tracked files differ from HEAD; commit first"; exit 1; }
	@head=$$(git rev-parse --short HEAD); \
	built=$$($(STAGE2_BIN) -version | sed -n '1s/^poc [^ ]* (\(.*\))$$/\1/p'); \
	if [ "$$built" != "$$head" ]; then \
	  echo "dist: the Stage 2 poc was built from '$$built', not $$head; make stage2 first"; exit 1; \
	fi
	rm -rf $(DIST_DIR); mkdir -p $(DIST_DIR)
	git archive --prefix=$(DIST_NAME)/ HEAD | tar -xf - -C $(DIST_DIR)
	git rev-parse --short HEAD > $(DIST_DIR)/$(DIST_NAME)/COMMIT
	SEED_DIR=$(abspath $(DIST_DIR)/$(DIST_NAME)/seed) tools/bootstrap/make-seed
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
	   $(MAKE) --no-print-directory VOC_BIN_DIR=/nonexistent check-install) \
	    || status=1; \
	  ver=$$($$scratch/$(DIST_NAME)/build/bin/poc -version 2>/dev/null | sed -n 1p); \
	  echo "distcheck: the tarball's poc says: $$ver"; \
	fi; \
	rm -rf $$scratch; \
	if [ $$status = 0 ]; then echo "distcheck: $(DIST_NAME).tar.gz builds without voc and installs"; fi; \
	exit $$status

# Runs every fixture in one pass (not category-by-category as separate
# make prerequisites) so one "make test" always reports the full picture,
# rather than GNU Make's normal fail-fast stopping at the first failing
# prerequisite target.
test: build
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

test-misc: build
	test/run-tests.sh $(MISC_TESTS)

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
