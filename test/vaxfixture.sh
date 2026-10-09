# '.' this file from a VAX fixture's test.sh, after ../../testenv.sh
# (doc/developer/vax-macro32-backend.md, sections 10 and 13). Defines
#
#   vax_mar <Module> [<poc option>...]
#
# which runs poc <poc option>... -emit-macro32 <Module>.mod, appends what
# poc prints and its exit status to result, then compares the <Module>.mar
# written with expected-vax.mar, and each other module's of the program,
# <Import>.mar, with expected-vax-<Import>.mar, leaving out the reviewer's
# comment at the top (the lines starting ";;", which say why the output is
# right): "<Module>.mar matches expected-vax.mar", or the differences, and
# so for each import. Where the VAX development system can be used
# (tools/vax-assemble -available), every expected .mar is also assembled
# there with MACRO/OBJECT, and a failure, with MACRO's messages, is added to
# result; and when the fixture has runs, run-<name>.dbg, each a run of the
# program under the debugger (tools/vax-run), whose output is compared with
# run-<name>.log, a failure or a difference is added to result too.
# Elsewhere those parts are skipped, saying so on the output but not in
# result, so that result is the same on every host when all is well. They
# are skipped too when VAX_GUEST is "skip", as it is in the suite runs after
# make test's (GNUmakefile): the guest sees only the expected .mar files,
# the same whichever poc runs the suite, so one run's check is enough.

# "<written>.mar matches <expected>", or the differences, to result
vax_compare() {
  grep -v '^;;' "$2" >expected-vax.stripped
  if [ ! -f "$1" ]; then
    echo "$1 was not written" >>result
  elif diff "$1" expected-vax.stripped >vax-diff 2>&1; then
    echo "$1 matches $2" >>result
  else
    echo "$1 differs from $2:" >>result
    cat vax-diff >>result
  fi
  rm -f expected-vax.stripped vax-diff
}

vax_mar() {
  vax_module=$1; shift
  poc "$@" -emit-macro32 "$vax_module.mod" >>result 2>&1
  echo "exit $?" >>result
  set -- "$vax_module"
  vax_compare "$1.mar" expected-vax.mar
  # the imports, which must each have their expected .mar
  vax_imports=
  for vax_file in *.mar; do
    case $vax_file in "$1.mar"|expected-vax*.mar) continue ;; esac
    vax_imports="$vax_imports ${vax_file%.mar}"
  done
  for vax_file in expected-vax-*.mar; do
    [ -f "$vax_file" ] || continue
    vax_import=${vax_file#expected-vax-}; vax_import=${vax_import%.mar}
    case " $vax_imports " in *" $vax_import "*) ;; *) vax_imports="$vax_imports $vax_import" ;; esac
  done
  for vax_import in $vax_imports; do
    vax_compare "$vax_import.mar" "expected-vax-$vax_import.mar"
  done
  vax_tools=../../../tools
  if [ "${VAX_GUEST:-}" = skip ]; then
    echo "SKIPPED: assembling and running expected-vax.mar (VAX_GUEST=skip)"
  elif "$vax_tools/vax-assemble" -available; then
    mkdir -p vax-assemble
    cp expected-vax.mar "vax-assemble/$1.mar"
    for vax_import in $vax_imports; do
      [ -f "expected-vax-$vax_import.mar" ] && cp "expected-vax-$vax_import.mar" "vax-assemble/$vax_import.mar"
    done
    if ! "$vax_tools/vax-assemble" vax-assemble/*.mar >vax-assemble/out 2>&1; then
      echo "expected-vax.mar does not assemble:" >>result
      cat vax-assemble/out >>result
    fi
    rm -rf vax-assemble
    vax_runs
  else
    echo "SKIPPED: assembling expected-vax.mar (no VAX development system here)"
    if ls run-*.dbg >/dev/null 2>&1; then
      echo "SKIPPED: running expected-vax.mar (no VAX development system here)"
    fi
  fi
}

# The program, expected-vax.mar and its imports' expected .mar, run under
# the debugger once for each run-<name>.dbg, its output compared with
# run-<name>.log
vax_runs() {
  ls run-*.dbg >/dev/null 2>&1 || return 0
  mkdir -p vax-run
  cp expected-vax*.mar run-*.dbg vax-run/
  if ! (cd vax-run && "../$vax_tools/vax-run" expected-vax.mar $(ls expected-vax-*.mar 2>/dev/null) run-*.dbg >out 2>&1); then
    echo "expected-vax.mar does not run:" >>result
    cat vax-run/out >>result
  else
    for dbg in run-*.dbg; do
      log=${dbg%.dbg}.log
      if ! diff "$log" "vax-run/${dbg%.dbg}.out" >vax-run/diff 2>&1; then
        echo "$dbg differs from $log:" >>result
        cat vax-run/diff >>result
      fi
    done
  fi
  rm -rf vax-run
}

# vax_do <proc.com> <expected> [<file>...]: where the VAX development
# system can be used, runs the DCL procedure there with the files
# (tools/vax-do; PLAN.md Phase 16 step 2) and compares what it printed,
# without vax-do's own last line, with <expected>: a failure or a
# difference is added to result. Skipped elsewhere, and when VAX_GUEST is
# "skip", saying so on the output but not in result, as vax_mar's guest
# parts are.
vax_do() {
  vax_tools=../../../tools
  vax_proc=$1; vax_expected=$2; shift 2
  if [ "${VAX_GUEST:-}" = skip ]; then
    echo "SKIPPED: running $vax_proc on the VAX (VAX_GUEST=skip)"
  elif "$vax_tools/vax-assemble" -available; then
    mkdir -p vax-do
    if ! "$vax_tools/vax-do" -o vax-do "$vax_proc" "$@" >vax-do/out 2>&1; then
      echo "$vax_proc failed on the VAX:" >>result
      cat vax-do/out >>result
    else
      sed '$d' vax-do/out >vax-do/printed
      if ! diff "$vax_expected" vax-do/printed >vax-do/diff 2>&1; then
        echo "$vax_proc's output on the VAX differs from $vax_expected:" >>result
        cat vax-do/diff >>result
      fi
    fi
    rm -rf vax-do
  else
    echo "SKIPPED: running $vax_proc on the VAX (no VAX development system here)"
  fi
}
