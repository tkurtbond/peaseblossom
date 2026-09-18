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

.PHONY: all build test test-lexer test-parser test-semantic test-modules test-layout test-llvm test-misc clean clean-build clean-tests

build: $(BIN)

$(BIN): $(SRCS)
	tools/bootstrap/stage0

all: build

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
