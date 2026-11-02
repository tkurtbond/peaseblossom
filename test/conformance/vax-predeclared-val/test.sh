#!/bin/sh
. ../../testenv.sh
# The predeclared VAL(T, x) on VAX/VMS (doc/developer/predeclared-unsigned-
# types.md, step 4). valchecks.mod's MACRO-32 and object under -range-checks
# must be the reviewed ones. Then llvm-predeclared-val's cases and constants
# under each size model, built both ways (vax_build). The cases are one
# program, of a procedure each, built as valplain and, with -range-checks,
# as valchecked; each image is run on the guest once for each case, the
# case's number its argument, with SYS$ERROR a file typed after it. What it
# prints must be what llvm-predeclared-val's expected has for that model,
# status 14 being %X10000072.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
written="valplain.mar valchecked.mar constants.mar Args.mar Modules.mar Platform.mar GarbageCollectedHeap.mar Out.mar LineOutput.mar FormattedOutput.mar FormattedText.mar RealDigits.mar"
llvm=../llvm-predeclared-val
: >result
vax_mar valchecks -range-checks
rm -f valchecks.mar valchecks.obj valchecks.image valchecks.sym

# The module $1: Case<n>, for the line n of cases.txt, chosen by the argument
write_cases() {
  {
    echo "MODULE $1;"
    echo "  IMPORT SYSTEM, Args, Out;"
    echo "  VAR which: LONGINT;"
    n=0
    while read -r from value to print; do
      n=$((n + 1))
      cat <<PROCEDURE
  PROCEDURE Case$n;
    VAR x: $from; r: $to;
  BEGIN
    x := $value;
    r := VAL($to, x);
    IF r # SYSTEM.VAL($to, x) THEN Out.String("differs from SYSTEM.VAL ") END;
    Out.$print(r, 0); Out.Ln
  END Case$n;
PROCEDURE
    done <$llvm/cases.txt
    echo "BEGIN"
    echo "  Args.GetInt(1, which);"
    echo "  CASE which OF"
    i=1
    while [ $i -le $n ]; do
      [ $i -eq 1 ] && printf '    ' || printf '  | '
      echo "$i: Case$i"
      i=$((i + 1))
    done
    echo "  END"
    echo "END $1."
  } >"$1.mod"
}

# What guest-run.com must print for the model $1, from LLVM's expected
write_expected() {
  awk -v model="-$1" '
    $1 == model {
      n++
      line = $0; sub(/^.*\): /, "", line)
      split(line, part, " / ")
      plain = part[1]; checked = part[2]
      trapped = checked ~ /\(exit 14\)$/
      sub(/ \(exit [0-9]+\)$/, "", checked)
      print "== " n; print plain
      if (trapped) { print "status: %X10000072"; print checked }
      else { print checked; print "status: %X00000001" }
    }
    $0 == "== constants " model { print "== constants"; inside = 1; next }
    /^== constants / { inside = 0 }
    inside { print }
  ' $llvm/expected
}

cp $llvm/constants.mod .
write_cases valplain
write_cases valchecked
for model in O2 OC; do
  write_expected $model >guest-run.expected
  builds() {
    rm -f *.sym $written valplain.com valchecked.com constants.com
    poc -$model -target vax-dec-vms $vax_way_option -import-path $rtl -build valplain.mod >>result 2>&1
    echo "VAX build valplain -$model exit $?" >>result
    poc -$model -range-checks -target vax-dec-vms $vax_way_option -import-path $rtl -build valchecked.mod >>result 2>&1
    echo "VAX build valchecked -$model exit $?" >>result
    poc -$model -target vax-dec-vms $vax_way_option -import-path $rtl -build constants.mod >>result 2>&1
    echo "VAX build constants -$model exit $?" >>result
    vax_do guest-run.com guest-run.expected valplain.com valchecked.com constants.com $written $rtl/PocRtl.mar
  }
  vax_build builds
done
rm -f *.sym *.obj $written valplain.com valchecked.com constants.com
rm -f valplain.mod valchecked.mod constants.mod guest-run.expected
. ../../testresult.sh
