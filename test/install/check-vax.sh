#!/bin/sh
# make check-install-vax: what a user of an installed poc and of make
# install-vax does to build for VAX/VMS on Unix, with only that poc: no
# voc, no source tree, no POC_IMPORT_PATH or POC_LIBRARY_PATH, and no -import-path.
# Usage: check-vax.sh <installed poc> <scratch directory> <kit program
# directory>. It builds tools/bootstrap/vax-kit/check's two programs, one
# against POCRTL, the other against VMSLIB and VMSDEF too, under -O2 and
# -OC (from the shareable images), and shows what each writes: only the
# program's own MACRO-32, and a .com that links the installed libraries.
# Nothing here uses the guest. Compares what it prints with expected-vax,
# beside it.
poc=$1; work=$2; programs=$3
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$work" && cd "$work" || exit 1
PATH=$(dirname "$poc"):/usr/bin:/bin
export PATH
unset POC_IMPORT_PATH POC_LIBRARY_PATH LD_LIBRARY_PATH
prefix=$(dirname "$(dirname "$poc")")

{
for model in O2 OC; do
  for program in KitHello KitVmsLib; do
    echo "== -$model $program"
    rm -rf "$model-$program"; mkdir "$model-$program"
    cp "$programs/$program.Mod" "$model-$program/"
    options=; [ $model = OC ] && options=-shared-libraries
    (cd "$model-$program" &&
     poc -$model -target vax-dec-vms $options -build $program.Mod &&
     ls && grep 'POC\$LIB_\|^\$ LINK' $program.com)
  done
done
echo "== the libraries"
for model in O2 OC; do
  ls "$prefix/lib/poc/vax-dec-vms/$model" | grep '\.library$'
done
echo "== the kits"
ls "$prefix/share/peaseblossom/vax" | sed 's/[0-9][0-9]*-[0-9][0-9]*-[0-9][0-9]*/<version>/'
echo "== the guide"
ls "$prefix/share/doc/peaseblossom" | grep vax-vms-guide
for kind in html pdf; do
  ls "$prefix/share/doc/peaseblossom/$kind" | grep vax-vms-guide
done
} > result 2>&1

if cmp -s "$here/expected-vax" result; then
  echo "check-install-vax: passed"
else
  echo "check-install-vax: FAILED"; diff "$here/expected-vax" result
  exit 1
fi
