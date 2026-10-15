#!/bin/sh
. ../../testenv.sh
# Phase 17 step 7 (doc/developer/vax-macro32-backend.md, section 21,
# proposal 8): poc's driver reaches the LLVM back end through LLVMBackEnd,
# src/driver/llvm's, or for poc on VAX/VMS src/driver/no-llvm's, which has
# no LLVM back end; the build's import path picks one. Each is compiled with
# its imports, under -OC as poc itself is, and their interfaces, as
# -show-interface prints them, must agree but for what each imports.
root=../../..
rm -rf work
mkdir work work/gen
: >result
"$root/tools/build-info" work/gen >>result 2>&1
for variant in llvm no-llvm; do
  mkdir work/$variant
  poc -OC -clear-library-path -import-path $root/src/front -import-path $root/src/back/llvm \
    -import-path $root/rtl/llvm -import-path $root/src/driver -import-path work/gen \
    -output-dir work/$variant -emit-llvm-ir $root/src/driver/$variant/LLVMBackEnd.Mod \
    >work/$variant.out 2>&1 || cat work/$variant.out >>result
  poc -OC -clear-library-path -import-path work/$variant -show-interface $root/src/driver/$variant/LLVMBackEnd.Mod \
    2>&1 | grep -v '^  IMPORT ' >work/$variant.interface
done
if diff work/llvm.interface work/no-llvm.interface >>result; then
  echo "the two interfaces agree" >>result
fi
rm -rf work
. ../../testresult.sh
