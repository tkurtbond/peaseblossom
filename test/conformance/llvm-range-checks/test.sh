#!/bin/sh
. ../../testenv.sh
# Each case, chosen by the program's argument, under both size models: poc
# with -range-checks against voc -r, then poc without it against voc without
# -r. The result holds poc's output and exit status; a line says so wherever
# poc and voc disagree - on the output of a run that does not stop, or on
# whether a run stops (voc's status for a stop is its own: 248, Halt(-8)).
# Known, and said so: voc -r does not stop CHR of a negative value (cases 7
# and 8; its __R compares signed).
# voc runs first and its files go before poc starts: poc leaves .sym files in
# the working directory, which voc would find and reject as not its own.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
cases="0 1 2 3 4 5 6 7 8 9"
for model in -O2 -OC
do
  for checks in on off
  do
    if [ $checks = on ]; then voc -r $model -m rangechecks.mod >/dev/null; else voc $model -m rangechecks.mod >/dev/null; fi
    mv rangechecks "voc$model-$checks"
    rm -f *.c *.h *.o *.sym
  done
done
: >result
for model in -O2 -OC
do
  for checks in on off
  do
    if [ $checks = on ]; then flag=-range-checks; else flag=; fi
    poc $model $flag -o "$exe" -build rangechecks.mod 2>&1 | grep -v '^semantic OK' >>result
    for case in $cases
    do
      printf '== %s %s case %s\n' "$model" "$flag" "$case" >>result
      "./$exe" "$case" >poc-out 2>&1; pocstatus=$?
      "./voc$model-$checks" "$case" >voc-out 2>&1; vocstatus=$?
      cat poc-out >>result
      printf 'exit=%d\n' "$pocstatus" >>result
      if [ $pocstatus = 0 ] && [ $vocstatus = 0 ]
      then cmp -s poc-out voc-out || echo "poc and voc print different values" >>result
      elif [ $pocstatus = 14 ] && [ $vocstatus = 0 ] && { [ $case = 7 ] || [ $case = 8 ]; }
      then echo "voc -r does not stop here (known: its CHR check compares signed)" >>result
      elif [ $pocstatus = 0 ] || [ $vocstatus = 0 ]
      then echo "poc and voc disagree on stopping (voc: $vocstatus)" >>result
      fi
    done
  done
done
rm -f poc-out voc-out voc-O2-on voc-O2-off voc-OC-on voc-OC-off
. ../../testresult.sh
