#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 18 step 6a (doc/developer/vax-object-language.md, section
# 17): the two ways to build for vax-dec-vms. vax-build's VaxBuild and
# VaxBuildSums built with -vax-objects: -build writes each module's .obj,
# no .mar, and a procedure that assembles nothing and links them;
# -compile writes the objects and no procedure; with -g the procedure
# links /DEBUG, and from MACRO-32 assembles /DEBUG too; the last of
# -vax-objects and -vax-macro32 counts. Each procedure is compared with
# expected-<name>.com, and where the VAX development system can be used
# the program built from objects is linked by its procedure there and run
# (vax_do; tools/vax-do converts the objects it sends), and must compute
# what vax-build's does. Then -emit-macro32, -emit-vax-object and
# -emit-vax-image, given together, write each file they name from one
# compile, each alone only its own; and what is refused: an -emit- command
# as an option to another command. (A library of objects is vax-library's.)
. ../../vaxfixture.sh
rm -rf work
mkdir work
cp ../vax-build/VaxBuild.mod ../vax-build/VaxBuildSums.mod work/
: >result
run() {
  echo "== poc $*" >>result
  (cd work && poc "$@") >>result 2>&1
  echo "exit $?" >>result
}
compare() {
  if [ ! -f "work/$1" ]; then
    echo "$1 was not written" >>result
  elif diff "expected-$1" "work/$1" >com-diff 2>&1; then
    echo "$1 matches expected-$1" >>result
  else
    echo "$1 differs from expected-$1:" >>result
    cat com-diff >>result
  fi
  rm -f com-diff
}
# the files a command wrote, then removed
written() {
  (cd work && ls *.mar *.obj *.image *.com 2>/dev/null) | LC_ALL=C sort | sed 's/^/written: /' >>result
  (cd work && rm -f *.mar *.obj *.image *.com *.sym)
}
run -target vax-dec-vms -vax-objects -build VaxBuild.mod
compare VaxBuild.com
mkdir work/guest
cp work/VaxBuild.com work/VaxBuild.obj work/VaxBuildSums.obj work/guest/
written
run -target vax-dec-vms -vax-objects -compile VaxBuildSums.mod
written
run -target vax-dec-vms -vax-objects -g -o VaxBuildDebug -build VaxBuild.mod
compare VaxBuildDebug.com
written
run -target vax-dec-vms -g -o VaxBuildMacroDebug -build VaxBuild.mod
compare VaxBuildMacroDebug.com
written
run -target vax-dec-vms -vax-objects -vax-macro32 -o VaxBuildLast -build VaxBuild.mod
written
run -emit-macro32 -emit-vax-object VaxBuild.mod
written
run -emit-vax-object VaxBuild.mod -emit-vax-image
written
run -emit-vax-image VaxBuild.mod
written
run -target vax-dec-vms -build VaxBuild.mod -emit-macro32
written
vax_do guest-build.com guest-build.expected work/guest/VaxBuild.com work/guest/VaxBuild.obj \
  work/guest/VaxBuildSums.obj ../../../rtl/vax/PocRtl.mar
rm -rf work
. ../../testresult.sh
