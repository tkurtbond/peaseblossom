#!/bin/sh
# Phase 13 step 3: what a user of an installed poc does, with only that poc
# and clang: no voc, no source tree, no POC_IMPORT_PATH or POC_LIBRARY_PATH.
# Usage: check.sh <installed poc> <scratch directory>. Run by make
# check-install; compares what it prints with expected, beside it.
poc=$1; work=$2
here=$(cd "$(dirname "$0")" && pwd)
clang=$(command -v clang) || { echo "check-install: no clang on PATH"; exit 1; }
mkdir -p "$work" && cd "$work" || exit 1
# a clean environment: the installed poc's directory and clang's, then the
# system's
PATH=$(dirname "$poc"):$(dirname "$clang"):/usr/bin:/bin
export PATH
unset POC_IMPORT_PATH POC_LIBRARY_PATH LD_LIBRARY_PATH

{
echo "== -version"
# the commit is there only in a build from a git checkout
poc -version | sed -n '1s/^poc [0-9][0-9.]*\( (.*)\)\{0,1\}$/poc <version>/p'

echo "== a program, as -O2 and -OC"
cat > Hello.Mod <<'MOD'
MODULE Hello;
  IMPORT Out;
BEGIN Out.String("hello"); Out.Ln
END Hello.
MOD
poc Hello.Mod && ./Hello
poc -OC -o hello-oc Hello.Mod && ./hello-oc

echo "== -g links poc-rtl's -g copy"
poc -g -verbose -o hello-g Hello.Mod 2>&1 | grep -c '/O2-g/libpoc-rtl\.a'
./hello-g

echo "== linked with the shared poc-rtl, run from elsewhere"
poc -shared-libraries -o hello-so Hello.Mod && mkdir -p moved && mv hello-so moved/ && moved/hello-so

echo "== a library of one's own, used from another directory"
mkdir -p greet prog
cat > greet/Greet.Mod <<'MOD'
MODULE Greet;
  IMPORT Out;
  PROCEDURE Hi*(name: ARRAY OF CHAR);
  BEGIN Out.String("hi, "); Out.String(name); Out.Ln
  END Hi;
END Greet.
MOD
cat > prog/Main.Mod <<'MOD'
MODULE Main;
  IMPORT Greet;
BEGIN Greet.Hi("library")
END Main.
MOD
(cd greet && poc -library greet Greet.Mod)
(cd prog && poc -library-path ../greet Main.Mod && ./Main)
(cd prog && poc -shared-libraries -library-path ../greet -o main-so Main.Mod && ./main-so)

echo "== poc through a symbolic link"
mkdir -p links && ln -s "$poc" links/poc
links/poc -o hello-link Hello.Mod && ./hello-link

echo "== a trap"
cat > Trap.Mod <<'MOD'
MODULE Trap;
  VAR p: POINTER TO RECORD x: INTEGER END;
BEGIN p.x := 1
END Trap.
MOD
poc Trap.Mod && ./Trap; echo "exit $?"

echo "== -help"
poc -help >/dev/null; echo "exit $?"
} > result 2>&1

if cmp -s "$here/expected" result; then
  echo "check-install: passed"
else
  echo "check-install: FAILED"; diff "$here/expected" result
  exit 1
fi
