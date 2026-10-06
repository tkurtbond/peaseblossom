# '.' this file from a VAX fixture's test.sh, after ../../testenv.sh
# (doc/developer/vax-macro32-backend.md, section 10). Defines
#
#   vax_mar <Module>
#
# which runs poc -emit-macro32 <Module>.mod, appends what poc prints and its
# exit status to result, then compares the <Module>.mar written with
# expected-vax.mar, leaving out the reviewer's comment at its top (the lines
# starting ";;", which say why the output is right): "<Module>.mar matches
# expected-vax.mar", or the differences. Where the VAX development system can
# be used (tools/vax-assemble -available), expected-vax.mar is also assembled
# there with MACRO/OBJECT, and a failure, with MACRO's messages, is added to
# result; elsewhere that part is skipped, saying so on the output but not in
# result, so that result is the same on every host when all is well.

vax_mar() {
  poc -emit-macro32 "$1.mod" >>result 2>&1
  echo "exit $?" >>result
  grep -v '^;;' expected-vax.mar >expected-vax.stripped
  if [ ! -f "$1.mar" ]; then
    echo "$1.mar was not written" >>result
  elif diff "$1.mar" expected-vax.stripped >vax-diff 2>&1; then
    echo "$1.mar matches expected-vax.mar" >>result
  else
    echo "$1.mar differs from expected-vax.mar:" >>result
    cat vax-diff >>result
  fi
  rm -f expected-vax.stripped vax-diff
  vax_tools=../../../tools
  if "$vax_tools/vax-assemble" -available; then
    mkdir -p vax-assemble
    cp expected-vax.mar "vax-assemble/$1.mar"
    if ! "$vax_tools/vax-assemble" "vax-assemble/$1.mar" >vax-assemble/out 2>&1; then
      echo "expected-vax.mar does not assemble:" >>result
      cat vax-assemble/out >>result
    fi
    rm -rf vax-assemble
  else
    echo "SKIPPED: assembling expected-vax.mar (no VAX development system here)"
  fi
}
