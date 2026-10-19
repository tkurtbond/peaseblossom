# '.' this file from a VAX fixture's test.sh, after ../../testenv.sh
# (doc/developer/vax-macro32-backend.md, sections 10 and 13). Defines
#
#   vax_mar <Module> [<poc option>...]
#
# which runs poc <poc option>... -emit-macro32 -emit-vax-object <Module>.mod
# (both files from one compile), appends what poc prints and its exit
# status to result, then compares the <Module>.mar
# written with expected-vax.mar, and each other module's of the program,
# <Import>.mar, with expected-vax-<Import>.mar, leaving out the reviewer's
# comment at the top (the lines starting ";;", which say why the output is
# right): "<Module>.mar matches expected-vax.mar", or the differences, and
# so for each import. Each module's object, which poc's encoder and object
# writer made (<Module>.obj), is read back by build/bin/vax-image (make
# vax-image), whose reader is not the writer, and its image, <Module>.image,
# is compared the same way with expected-vax.image or
# expected-vax-<Import>.image, the image of the object MACRO made from the
# expected .mar (tools/vax-macro-image; doc/developer/vax-object-language.md,
# sections 14.5 and 15.4), so that both are checked on every host. Where the
# VAX development system can be used
# (tools/vax-assemble -available), every expected .mar is also assembled
# there with MACRO/OBJECT, and every object poc wrote converted there and
# checked by ANALYZE/OBJECT (PLAN.md Phase 18 step 4c), and a failure, with
# MACRO's or ANALYZE's messages, is added to result; and when the fixture
# has runs, run-<name>.dbg, each a run of the
# program under the debugger (tools/vax-run), whose output is compared with
# run-<name>.log, a failure or a difference is added to result too.
# Elsewhere those parts are skipped, saying so on the output but not in
# result, so that result is the same on every host when all is well. They
# are skipped too when VAX_GUEST is "skip", as it is in the suite runs after
# make test's (GNUmakefile): the guest sees the expected .mar files, the
# same whichever poc runs the suite, and poc's objects, the same from every
# stage of poc (the fixed point), so one run's check is enough.

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

# The image of the object <Module>.obj, <Module>.image, by vax-image, whose
# complaint, if it has one, goes to result
vax_object_image() {
  vax_image=${VAX_IMAGE:-../../../build/bin/vax-image}
  [ -f "$1.obj" ] || return 0
  rm -f "$1.image"
  "$vax_image" "$1.obj" "$1.image" >>result 2>&1
}

# "<written>.image matches <expected>", or the differences, to result
vax_image_compare() {
  if [ ! -f "$2" ]; then
    echo "there is no $2" >>result
  elif [ ! -f "$1" ]; then
    echo "$1 was not written" >>result
  elif diff "$1" "$2" >vax-diff 2>&1; then
    echo "$1 matches $2" >>result
  else
    echo "$1 differs from $2:" >>result
    cat vax-diff >>result
  fi
  rm -f vax-diff
}

vax_mar() {
  vax_module=$1; shift
  # no object or image of an earlier run, which would hide one not written
  for vax_file in *.obj *.image; do
    case $vax_file in expected-vax.image|expected-vax-*.image) ;; *) rm -f "$vax_file" ;; esac
  done
  poc "$@" -emit-macro32 -emit-vax-object "$vax_module.mod" >>result 2>&1
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
  vax_object_image "$1"
  vax_image_compare "$1.image" expected-vax.image
  for vax_import in $vax_imports; do
    vax_object_image "$vax_import"
    vax_image_compare "$vax_import.image" "expected-vax-$vax_import.image"
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
    # and the objects poc wrote, each checked by ANALYZE/OBJECT there
    # (PLAN.md Phase 18 step 4c)
    for vax_file in "$1" $vax_imports; do
      [ -f "$vax_file.obj" ] && cp "$vax_file.obj" vax-assemble/
    done
    if ! "$vax_tools/vax-assemble" vax-assemble/*.mar $(ls vax-assemble/*.obj 2>/dev/null) >vax-assemble/out 2>&1; then
      echo "expected-vax.mar does not assemble, or an object poc wrote does not pass ANALYZE/OBJECT:" >>result
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
# parts are. With VAX_REPEAT=<n> above 1, the procedure is given n as its
# P1, and one that honours it (make test-vax-asts' fixtures) builds its
# programs once and runs them n times, printing the first run's output and
# only where a later one differs from it, so <expected> still holds; the
# run may then take 600 seconds and 120 more a run. With vax_mask=yes,
# the code addresses in VMS's fault messages and tracebacks (PC=, PSL=, a
# traceback line's last two columns), which any change to the code moves,
# are masked as xxxxxxxx in both before they are compared, as
# tools/vax-suite masks them, and POC2's home directory is written as
# POC's, which the debugger names when it opens a source file.
vax_do() {
  vax_tools=../../../tools
  vax_proc=$1; vax_expected=$2; shift 2
  vax_repeat=
  case ${VAX_REPEAT:-} in
    ""|*[!0-9]*|0|1) ;;
    *) vax_repeat="-p $VAX_REPEAT"
       echo "running $vax_proc's programs $VAX_REPEAT times (VAX_REPEAT)"
       : "${VAX_DO_TIMEOUT:=$((600 + 120 * VAX_REPEAT))}"; export VAX_DO_TIMEOUT ;;
  esac
  if [ "${VAX_GUEST:-}" = skip ]; then
    echo "SKIPPED: running $vax_proc on the VAX (VAX_GUEST=skip)"
  elif "$vax_tools/vax-assemble" -available; then
    mkdir -p vax-do
    # shellcheck disable=SC2086
    if ! "$vax_tools/vax-do" -o vax-do $vax_repeat "$vax_proc" "$@" >vax-do/out 2>&1; then
      echo "$vax_proc failed on the VAX:" >>result
      cat vax-do/out >>result
    else
      sed '$d' vax-do/out >vax-do/printed
      cp "$vax_expected" vax-do/expected
      if [ "${vax_mask:-}" = yes ]; then
        for vax_file in vax-do/printed vax-do/expected; do
          # and the account's directory, POC2's when POC's lock was taken
          # (tools/vax-lock.sh)
          sed -e 's/PC=[0-9A-F]\{8\}/PC=xxxxxxxx/g' -e 's/PSL=[0-9A-F]\{8\}/PSL=xxxxxxxx/g' \
              -e 's/ [0-9A-F]\{8\}  [0-9A-F]\{8\}$/ xxxxxxxx  xxxxxxxx/' \
              -e 's/\[USERS\.POC2\]/[USERS.POC]/g' "$vax_file" >"$vax_file.masked"
          mv "$vax_file.masked" "$vax_file"
        done
      fi
      if ! diff vax-do/expected vax-do/printed >vax-do/diff 2>&1; then
        echo "$vax_proc's output on the VAX differs from $vax_expected:" >>result
        cat vax-do/diff >>result
      fi
    fi
    rm -rf vax-do
  else
    echo "SKIPPED: running $vax_proc on the VAX (no VAX development system here)"
  fi
}
