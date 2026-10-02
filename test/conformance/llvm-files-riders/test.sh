#!/bin/sh
. ../../testenv.sh
# riders.mod under poc and voc, both size models: the same output (each
# run starts from the same files). signed.mod, poc's alone: what differs
# from voc on purpose, and the finalization of Files dropped unclosed.
setup() {
  rm -rf riders.sub riders.bin dropped.txt kept.txt .tmp.*
  mkdir riders.sub && echo "inner line" >riders.sub/inner.txt
}
for model in -O2 -OC
do
  setup
  voc $model riders.mod -m >/dev/null
  ./riders >"voc$model-output" 2>&1
  rm -f *.c *.h *.o *.sym riders
done
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
: >result
for model in -O2 -OC
do
  setup
  echo "== riders $model" >>result
  poc $model -o riders.exe -build riders.mod 2>&1 | grep -v '^semantic OK' >>result
  ./riders.exe >poc-output 2>&1
  cat poc-output >>result
  # voc's -O2 GetDate (MTimeAsClock) hands localtime a 4-byte LONGINT as a
  # time_t, which may stop it with "NIL access" (on the BSDs; see
  # llvm-platform-files): then only the lines voc printed before are compared
  if cmp -s poc-output "voc$model-output"
  then :
  elif [ $model = -O2 ] && grep -q 'NIL access' "voc$model-output"
  then
    grep -v 'NIL access' "voc$model-output" >voc-before
    head -n "$(wc -l <voc-before)" poc-output | cmp -s - voc-before \
      || echo "poc and voc disagree under $model" >>result
    rm -f voc-before
  else echo "poc and voc disagree under $model" >>result
  fi
done
for model in -O2 -OC
do
  setup
  echo "== signed $model" >>result
  poc $model -o signed.exe -build signed.mod 2>&1 | grep -v '^semantic OK' >>result
  ./signed.exe >>result 2>&1
  echo "exit=$?" >>result
  echo "kept.txt: $(tr -d "\\000" <kept.txt 2>/dev/null)" >>result
  echo "dropped.txt: $(ls dropped.txt 2>/dev/null)" >>result
  echo "temporary files left: $(ls -a | grep -c '^\.tmp\.')" >>result
done
rm -rf riders.sub riders.bin dropped.txt kept.txt .tmp.* poc-output voc-O2-output voc-OC-output *.sym
. ../../testresult.sh
