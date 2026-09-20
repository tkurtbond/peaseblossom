#!/bin/sh
. ../../testenv.sh
# Golden .ll of procir's own part of the program (its globals, synthesized
# array descriptors, trap messages and functions) at both target word sizes,
# with register and label numbers normalized (they count across the whole
# program, runtime modules included, so any change to a runtime module would
# renumber them), and the whole program handed to clang for real.
POC_IMPORT_PATH=../../../rtl/llvm
export POC_IMPORT_PATH
: >result
for triple in i686-unknown-linux-gnu x86_64-unknown-linux-gnu; do
  echo "== $triple" >>result
  poc -target $triple -emit-llvm-ir procir.mod >/dev/null
  awk '
    keep { print; if ($0 ~ /^}/) keep = 0; next }
    /^(@procir\.|@\.arraydesc\.|@\.trap\.|define .* @procir[._])/ { print; if ($0 ~ /[{]$/) keep = 1 }
  ' procir.ll | sed -E 's/%t[0-9]+/%tN/g; s/(^|[^A-Za-z0-9_])L[0-9]+([^A-Za-z0-9_]|$)/\1LN\2/g' >>result
  if clang -target $triple -c procir.ll -o /dev/null 2>clang.err
  then echo "clang accepted $triple" >>result
  else echo "clang REJECTED $triple" >>result; cat clang.err >>result
  fi
  rm -f clang.err
done
. ../../testresult.sh
