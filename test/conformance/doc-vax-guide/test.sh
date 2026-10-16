#!/bin/sh
. ../../testenv.sh
# The Peaseblossom VAX/VMS Guide's examples (doc/vax-vms-guide.md), in
# three parts. Each listing must be its file under doc/examples, exactly
# (tools/guide-examples, as doc-users-guide). Each program under
# doc/examples/vax must build for the VAX, from rtl/vax, rtl/vax/vms and
# rtl/vax/vmslib as source, Shell with its command table. And where the
# VAX development system can be used, guest-run.com builds and runs them
# there (vax_do), and what they print must be what the guide's sessions
# show: each block after a "<!-- vax-session: <name> -->" line, less its
# "$ " command lines, under "== <name>". WhereLogin prints POC's home, so
# this runs under POC's account alone.
. ../../vaxfixture.sh
VAX_USER=poc; export VAX_USER
unset POC_IMPORT_PATH POC_LIBRARY_PATH
root=../../..
rtl=$root/rtl/vax
guide=$root/doc/vax-vms-guide.md
rm -rf work
: >result
sh $root/tools/guide-examples check $guide $root/doc/examples work/listings >>result 2>&1
echo "listings exit $?" >>result
mkdir -p work/build
cp $root/doc/examples/vax/*/*.Mod $root/doc/examples/vax/*/*.cld work/build/
for program in Hello Versions WhereLogin WhereLogin2 Dates Factorial Words SystemInfo Greet Shell Warnings Probe Goodbye; do
  extra=
  [ $program = Shell ] && extra=ShellCommands.cld
  (cd work/build && poc -target vax-dec-vms -import-path ../../$rtl -import-path ../../$rtl/vms \
    -import-path ../../$rtl/vmslib -build $program.Mod $extra) >>result 2>&1
  echo "VAX build $program exit $?" >>result
done
# the sessions' output, as the guide shows it
awk '
  /^<!-- vax-session: / { name = $3; print "== " name; inblock = 0; want = 1; next }
  want && /^$/ && !inblock { next }
  want && /^    / { inblock = 1; line = substr($0, 5); if (line !~ /^\$ /) print line; next }
  { want = 0; inblock = 0 }
' $guide >work/sessions.expected
vax_do guest-run.com work/sessions.expected work/build/*.mar work/build/*.com work/build/*.cld \
  $rtl/PocRtl.mar
rm -rf work
. ../../testresult.sh
