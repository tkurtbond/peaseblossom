#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 12 step 5a: platformfiles under poc and voc, under both size
# models; each check prints ok or FAIL, so the outputs must be the same. The
# result holds poc's. voc runs first and its files go before poc starts: poc
# leaves Platform.sym in the working directory, which voc would find and
# reject as not its own.
# Known, and allowed for: voc's MTimeAsClock (check 25) under -O2 hands
# localtime the address of a 4-byte LONGINT as a time_t*, so localtime reads
# 4 bytes past it; where they are not zero (FreeBSD amd64) it returns NULL
# and voc stops, "NIL access". Then only the checks voc printed are compared.
PLATFORM_TEST_VALUE=files
export PLATFORM_TEST_VALUE
rm -f platform-files-a.txt platform-files-b.txt
for model in -O2 -OC
do
  voc $model platformfiles.mod -m >/dev/null
  ./platformfiles >"voc$model-output" 2>&1
  echo "exit=$?" >>"voc$model-output"
  rm -f *.c *.h *.o *.sym platformfiles
done

# Platform is an rtl module, with its C part (Platform.c): poc finds both,
# and Out (voc has no Console under -OC), through the import path
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
: >result
for model in -O2 -OC
do
  echo "== $model" >>result
  poc $model -o "$exe" -build platformfiles.mod 2>&1 | grep -v '^semantic OK' >>result
  "./$exe" >poc-output 2>&1
  echo "exit=$?" >>poc-output
  cat poc-output >>result
  head -n 24 poc-output >poc-output.24
  if cmp -s poc-output "voc$model-output"
  then :
  elif [ $model = -O2 ] && grep -q 'NIL access' "voc$model-output" \
       && grep ' ok$' "voc$model-output" | cmp -s - poc-output.24 2>/dev/null
  then : # voc stopped at check 25 (above)
  else echo "poc and voc disagree under $model" >>result
  fi
done
rm -f poc-output poc-output.24 voc-O2-output voc-OC-output platform-files-a.txt platform-files-b.txt
. ../../testresult.sh
