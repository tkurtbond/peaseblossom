#!/bin/sh
# '.' this file from individual test.sh scripts, before running any compiler.
#
# Puts both the bootstrap compiler (voc) and poc's own build (once built by
# tools/bootstrap/stage0) on PATH, and cleans generated build artifacts left
# by a previous run. See PLAN.md, "Bootstrap terminology".
#
# A BACKEND-selection variant of this file existed briefly in Phase 0, in
# anticipation of PLAN.md Phase 8's LLVM/VAX backend split - removed as
# premature (poc had no backend at all until Phase 8). PLAN.md Phase 8
# step 3 revisited this once the LLVM backend actually existed and found
# a BACKEND variable still isn't needed: every fixture already names
# whichever compiler it wants directly (voc or poc), and that hasn't
# changed now that poc has its own LLVM backend - see llvm-build-run for
# a fixture that calls poc directly, same as every voc-based fixture
# calls voc directly. What step 3 actually needed was a shared helper for
# the one new repeated pattern LLVM fixtures introduce - see
# poc_build_run below - not a backend-selection mechanism.

: "${VOC_BIN_DIR:=/usr/local/sw/versions/voc/git/bin}"
: "${POC_BIN_DIR:=$PWD/../../../build/bin}"

echo "--- conformance test $(basename "$PWD") ---"

export PATH="$POC_BIN_DIR:$VOC_BIN_DIR:$PATH"

# A program voc builds is linked against voc's shared runtime (libvoc-O2.so,
# libvoc-OC.so), which lives next to bin. Linux finds it by itself here, but
# NetBSD and OpenBSD do not, and a non-interactive shell (ssh host cmd) does
# not read the profile that sets LD_LIBRARY_PATH for a login one - so a
# crosscheck fixture's voc-built program died with 'Shared object
# "libvoc-O2.so" not found' there.
: "${VOC_LIB_DIR:=$VOC_BIN_DIR/../lib}"
LD_LIBRARY_PATH="$VOC_LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH


# *.c/*.h (voc's own C intermediates) were missing from this list until
# GNUmakefile's clean-tests target (which reuses this exact line via a
# standalone `. testenv.sh`, not by duplicating it) surfaced real,
# already-gitignored leftovers this never actually removed.
rm -f *.o *.c *.h *.ll *.s *.sym *.exe result "$(basename "$PWD")"
# a fixture's MACRO-32 output, but never the reviewed expected-vax.mar, or
# an import's expected-vax-<Import>.mar, a VAX fixture compares it with
# (doc/developer/vax-macro32-backend.md, section 10)
for vax_file in *.mar; do
  case $vax_file in expected-vax.mar|expected-vax-*.mar) ;; *) rm -f "$vax_file" ;; esac
done

# PLAN.md Phase 8 step 3: compiles $1 (an Oberon-2 source file) via poc's
# LLVM backend into an executable named after this fixture's own
# directory (so the cleanup line above already removes a stale one from a
# previous run - the same "$(basename "$PWD")" convention test/conformance/
# hello already established for voc's own -m build), then runs it,
# appending both poc's own message and the program's stdout to "result".
# Centralizes the "poc -o <exe> -build <file>, then run <exe>" pattern so future
# fixtures promoted to compile+link+run+diff (PLAN.md's "Testing summary"
# for Phase 8) don't each hand-roll the exact clang-backed CLI incantation.
poc_build_run() {
  exe=$(basename "$PWD")
  poc -o "$exe" -build "$1" >result 2>&1
  "./$exe" >>result
}

# PLAN.md Phase 9: succeeds if clang can link and the kernel can run a
# 32-bit x86 executable here - needs the 32-bit C runtime (Fedora:
# glibc-devel.i686), which is absent from many machines, and an x86 host.
# Used by fixtures that build for i686-unknown-linux-gnu so they can skip
# themselves cleanly instead of failing on a box that cannot run them.
i686_can_run() {
  # only an x86 machine runs 32-bit *x86* code: on FreeBSD/arm64 `clang -m32`
  # builds (and the kernel may run) 32-bit ARM, a different program altogether
  case $(uname -m) in
    i386|i686|amd64|x86_64) ;;
    *) return 1 ;;
  esac
  probe=$(mktemp -d) || return 1
  printf 'int main(void){return 0;}\n' >"$probe/probe.c"
  if clang -m32 "$probe/probe.c" -o "$probe/probe" >/dev/null 2>&1 && "$probe/probe" >/dev/null 2>&1
  then rm -rf "$probe"; return 0
  else rm -rf "$probe"; return 1
  fi
}

# Whether a 32-bit x86 program linked with a shared library runs here too:
# NetBSD amd64's 32-bit compatibility has only static C libraries (no
# /usr/lib/i386/libc.so), so such a program fails with "Exec format error"
# there (artos, 2026-09-27).
i686_can_run_shared() {
  i686_can_run || return 1
  probe=$(mktemp -d) || return 1
  printf 'int f(void){return 0;}\n' >"$probe/f.c"
  printf 'int f(void); int main(void){return f();}\n' >"$probe/main.c"
  if clang -m32 -fPIC -shared "$probe/f.c" -o "$probe/libf.so" >/dev/null 2>&1 &&
     clang -m32 "$probe/main.c" -L"$probe" -lf -Wl,-rpath,"$probe" -o "$probe/main" >/dev/null 2>&1 &&
     "$probe/main" >/dev/null 2>&1
  then rm -rf "$probe"; return 0
  else rm -rf "$probe"; return 1
  fi
}

# The 32-bit x86 target triple to build i686_can_run's fixtures for: the one
# this project has always used on Linux, and on any other system the triple
# clang itself picks for -m32 - the host's own on a 32-bit machine (OpenBSD
# i386: i386-unknown-openbsd7.9), the 32-bit personality of a 64-bit one
# (NetBSD amd64: i386-unknown-netbsd10.0). A Linux triple cannot link on a BSD
# even when that BSD runs 32-bit programs.
i686_triple() {
  if [ "$(uname -s)" = Linux ]
  then echo i686-unknown-linux-gnu
  else clang -m32 -dumpmachine
  fi
}
