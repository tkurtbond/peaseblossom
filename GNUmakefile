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
DRIVER_SRCS := src/driver/Poc.Mod
RTL_SRCS := $(wildcard rtl/llvm/*.Mod)
STAGE1_BIN := $(BUILD_DIR)/stage1/bin/poc
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

.PHONY: all build stage1 stage2 test-stage1 check check-strict test test-lexer test-parser test-semantic test-modules test-layout test-llvm test-misc clean clean-build clean-tests

build: $(BIN)

$(BIN): $(SRCS)
	tools/bootstrap/stage0

all: build

# Self-hosting (PLAN.md, "Bootstrap terminology"): stage1 builds poc with the
# Stage 0 poc, stage2 builds it again with Stage 1's and checks the two
# builds' output is identical (the fixed point). Stage 1 is compiled by poc
# itself, so it links rtl/llvm and is rebuilt when that changes too; stage2
# always reruns, being a comparison.
stage1: $(STAGE1_BIN)

$(STAGE1_BIN): $(BIN) $(SRCS) $(RTL_SRCS)
	tools/bootstrap/stage1

stage2: $(STAGE1_BIN)
	tools/bootstrap/stage2

# The whole suite under the poc that poc built (POC_BIN_DIR is what
# test/testenv.sh puts on PATH first; the tests cd, so it must be absolute).
# `make test` stays Stage 0 only - the fast loop, and voc remains the
# bootstrap root and the comparison oracle.
test-stage1: $(STAGE1_BIN)
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
