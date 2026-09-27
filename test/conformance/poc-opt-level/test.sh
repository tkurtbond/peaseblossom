#!/bin/sh
# Phase 11 D13: poc -opt <level> hands clang -O<level> for -build, and
# refuses a level clang does not document. bin/clang logs what it is given.
# With no -opt the level is 2, but 0 on 32-bit x86 (x87 arithmetic,
# LLVMToolchainDriver.DefaultOptimizationLevel): the host decides which, so
# that line says whether it was the one expected here. clang runs once per
# module and once to link, all at the same level, so each level is shown once.
. ../../testenv.sh
REAL_PATH=$PATH
CLANG_LOG=$PWD/clang.log
export REAL_PATH CLANG_LOG
PATH=$PWD/bin:$PATH
rm -f clang.log
: >result
for level in "" 2 z; do
  echo "-opt ${level:-(none)}:" >>result
  poc ${level:+-opt $level} -import-path ../../../rtl/llvm -o poc-opt-level -build opt.mod >>result 2>&1
  echo "exit=$?" >>result
  ./poc-opt-level >>result
  if [ -z "$level" ]; then
    case $(uname -m) in
      i386|i486|i586|i686) default=-O0 ;;
      *) default=-O2 ;;
    esac
    if [ "$(sort -u clang.log)" = "clang got $default" ]; then
      echo "clang got this host's default" >>result
    else
      sort -u clang.log >>result
    fi
  else
    sort -u clang.log >>result
  fi
  rm -f clang.log
done
for bad in 4 fast; do
  poc -opt $bad -import-path ../../../rtl/llvm -o poc-opt-level -build opt.mod >>result 2>&1
  echo "exit=$?" >>result
done
poc -opt >>result 2>&1
echo "exit=$?" >>result
. ../../testresult.sh
