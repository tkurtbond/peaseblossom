#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 16 step 2 (doc/developer/vax-macro32-backend.md, section
# 13): poc -target vax-dec-vms -build and -compile write the modules' .mar
# and a DCL procedure that assembles them and, for -build, links the image;
# the procedures are compared with expected-<name>.com, and where the VAX
# development system can be used they are run there and the program with
# them (../../vaxfixture.sh, vax_do). Then what the VAX target refuses, each
# with exit status 1 and no procedure written. The two modules whose names
# differ only in case are written here, in case-modules, not kept in the
# repository, which a case-insensitive file system could not check out.
# Such a system cannot hold the pair, so there that refusal is skipped,
# saying so on the output but not in result, which is the same on every
# host when all is well; it is compared with expected-case instead.
. ../../vaxfixture.sh
rm -f VaxBuild.com VaxBuildSums.com vaxprog.com VaxBuildClash.com
run() {
  echo "== poc $*" >>result
  poc "$@" >>result 2>&1
  echo "exit $?" >>result
}
compare() {
  if [ ! -f "$1" ]; then
    echo "$1 was not written" >>result
  elif diff "expected-$1" "$1" >com-diff 2>&1; then
    echo "$1 matches expected-$1" >>result
  else
    echo "$1 differs from expected-$1:" >>result
    cat com-diff >>result
  fi
  rm -f com-diff
}
: >result
run -target vax-dec-vms -build VaxBuild.mod
compare VaxBuild.com
ls *.mar | sed 's/^/written: /' >>result
run -target vax-dec-vms -compile VaxBuildSums.mod
compare VaxBuildSums.com
vax_do guest-build.com guest-build.expected VaxBuild.com VaxBuildSums.com \
  VaxBuild.mar VaxBuildSums.mar ../../../rtl/vax/PocRtl.mar
run -target vax-dec-vms -o vaxprog.EXE VaxBuild.mod
compare vaxprog.com
run -target vax-dec-vms -o bad.name.exe -build VaxBuild.mod
run -target vax-dec-vms -o a234567890123456789012345678901234567890 -build VaxBuild.mod
run -OC -target vax-dec-vms -build VaxBuild.mod
run -target vax-dec-vms -build VaxBuildClash.mod
rm -rf case-modules && mkdir case-modules
cat >case-modules/VaxCase.mod <<'EOF_MODULE'
MODULE VaxCase;
  (* imported by VaxBuildCase, with VAXCASE: on VMS both are VAXCASE.MAR
     and VAXCASE_INIT *)
END VaxCase.
EOF_MODULE
if [ -f case-modules/VAXCASE.mod ]; then
  echo "SKIPPED: modules differing only in case (this file system does not tell them apart)"
else
  cat >case-modules/VAXCASE.mod <<'EOF_MODULE'
MODULE VAXCASE;
  (* imported by VaxBuildCase, with VaxCase *)
END VAXCASE.
EOF_MODULE
  cat >case-modules/VaxBuildCase.mod <<'EOF_MODULE'
MODULE VaxBuildCase;
  (* two imports whose names differ only in case *)
  IMPORT VaxCase, VAXCASE;
END VaxBuildCase.
EOF_MODULE
  (cd case-modules && {
    echo "== poc -target vax-dec-vms -build VaxBuildCase.mod"
    poc -target vax-dec-vms -build VaxBuildCase.mod 2>&1
    echo "exit $?"
    ls *.com 2>/dev/null | sed 's/^/procedure: /'
  }) >case-modules/output
  if ! diff -b expected-case case-modules/output >case-modules/differences; then
    echo "the case refusal differs from expected-case:" >>result
    cat case-modules/differences >>result
  fi
fi
rm -rf case-modules
ls *.com | grep -v -e '^guest-' -e '^expected-' | sed 's/^/procedure: /' >>result
. ../../testresult.sh
