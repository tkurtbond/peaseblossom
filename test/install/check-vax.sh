#!/bin/sh
# make check-install-vax: what a user of an installed poc and of make
# install-vax does to build for VAX/VMS on Unix, with only that poc: no
# voc, no source tree, no POC_IMPORT_PATH or POC_LIBRARY_PATH, and no -import-path.
# Usage: check-vax.sh <installed poc> <scratch directory> <kit program
# directory> [<kit directory> <guide directory>], the last two where
# install-vax put the kits and the guide (by default
# <prefix>/share/peaseblossom/vax and <prefix>/share/doc/peaseblossom-vax;
# a package's own). It builds tools/bootstrap/vax-kit/check's two programs, one
# against POCRTL, the other against VMSLIB and VMSDEF too, under -O2 and
# -OC (from the shareable images), and shows what each writes: only the
# program's own MACRO-32, and a .com that links the installed libraries.
# Nothing here uses the guest. Compares what it prints with expected-vax,
# beside it.
poc=$1; work=$2; programs=$(cd "$3" && pwd) || exit 1
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$work" && cd "$work" || exit 1
PATH=$(dirname "$poc"):/usr/bin:/bin
export PATH
# ls sorts as expected-vax does whatever the locale (rpmbuild's %check
# runs in C, a user's shell often in en_US).
LC_ALL=C
export LC_ALL
unset POC_IMPORT_PATH POC_LIBRARY_PATH LD_LIBRARY_PATH
prefix=$(dirname "$(dirname "$poc")")
kits=${4:-$prefix/share/peaseblossom/vax}
guide=${5:-$prefix/share/doc/peaseblossom-vax}

{
for model in O2 OC; do
  for program in KitHello KitVmsLib; do
    echo "== -$model $program"
    rm -rf "$model-$program"; mkdir "$model-$program"
    cp "$programs/$program.Mod" "$model-$program/"
    options=; [ $model = OC ] && options=-shared-libraries
    (cd "$model-$program" &&
     poc -$model -target vax-dec-vms $options -build $program.Mod &&
     ls && grep -e 'POC\$LIB_' -e '^\$ LINK' $program.com)
  done
done
echo "== a missing module, with POCRTL installed: no note that the runtime is not"
mkdir missing
printf 'MODULE Lonely;\n  IMPORT Out, Missing;\nEND Lonely.\n' > missing/Lonely.Mod
(cd missing && poc -target vax-dec-vms -build Lonely.Mod 2>&1 | grep -c 'runtime is not installed')
echo "== the libraries"
for model in O2 OC; do
  ls "$prefix/lib/poc/vax-dec-vms/$model" | grep '\.library$'
done
echo "== the kits"
ls "$kits" | sed 's/[0-9][0-9]*-[0-9][0-9]*-[0-9][0-9]*/<version>/'
echo "== the guide as text (as HTML and PDF too, when make doc made them)"
ls "$guide" | grep 'vax-vms-guide\.txt'
} > result 2>&1

if cmp -s "$here/expected-vax" result; then
  echo "check-install-vax: passed"
else
  echo "check-install-vax: FAILED"; diff "$here/expected-vax" result
  exit 1
fi
