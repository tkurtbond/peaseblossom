#!/bin/sh
. ../../testenv.sh
# Phase 13 step 9: every option poc accepts - each string Poc.Mod compares
# an argument with - appears in the usage text (poc -help),
# in poc(1) (doc/poc.1, as ".Fl <name>") and in the Reference Guide
# (doc/reference-guide.md, in backquotes). Each one missing is a line of
# result. -build and -o must be among those found, so that a change to how
# Poc.Mod is written cannot leave the list empty and the check passing.
root=../../..
# grep -E: OpenBSD's grep has no \| in a basic expression
options=$(grep -Eo '(option|arg) = "-+[A-Za-z][-A-Za-z0-9]*"' $root/src/driver/Poc.Mod |
  sed 's/.*"\(.*\)"/\1/' | sort -u)
usage=$(poc -help 2>&1)
: >result
for required in -build -o; do
  printf '%s\n' "$options" | grep -qx -- "$required" || echo "not found in Poc.Mod: $required" >>result
done
# an option's name ends where a character that can be in one does not follow
end='([^-A-Za-z0-9]|$)'
for option in $options; do
  name=${option#-}
  printf '%s\n' "$usage" | grep -Eq -- "$option$end" || echo "not in the usage text: $option" >>result
  grep -Eq "Fl $name$end" $root/doc/poc.1 || echo "not in poc(1): $option" >>result
  grep -Eq -- "\`$option$end" $root/doc/reference-guide.md || echo "not in the Reference Guide: $option" >>result
done
. ../../testresult.sh
