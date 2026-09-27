#!/bin/sh
. ../../testenv.sh
# Each case, chosen by the program's argument, built with -trap-location, so
# the message names the assignment; then case 1 without it. A line says so
# wherever poc and voc disagree - on the output of a run that does not stop,
# or on whether a run stops (voc's status for this stop is 250, Halt(-6)).
# voc runs first and its files go before poc starts: poc leaves .sym files in
# the working directory, which voc would find and reject as not its own.
voc -m recordassign.mod >/dev/null
mv recordassign voc-recordassign
rm -f *.c *.h *.o *.sym
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
exe=$(basename "$PWD")
: >result
poc -trap-location -o "$exe" -build recordassign.mod 2>&1 | grep -v '^semantic OK' >>result
for case in 0 1 2 3 4 5
do
  printf '== case %s\n' "$case" >>result
  "./$exe" "$case" >poc-out 2>&1; pocstatus=$?
  ./voc-recordassign "$case" >voc-out 2>&1; vocstatus=$?
  cat poc-out >>result
  printf 'exit=%d\n' "$pocstatus" >>result
  if [ $pocstatus = 0 ] && [ $vocstatus = 0 ]
  then cmp -s poc-out voc-out || echo "poc and voc print different values" >>result
  elif [ $pocstatus = 0 ] || [ $vocstatus = 0 ]
  then echo "poc and voc disagree on stopping (voc: $vocstatus)" >>result
  fi
done
poc -o "$exe" -build recordassign.mod 2>&1 | grep -v '^semantic OK' >>result
printf '== without -trap-location, case 1\n' >>result
"./$exe" 1 >>result 2>&1
printf 'exit=%d\n' "$?" >>result
rm -f poc-out voc-out voc-recordassign
. ../../testresult.sh
