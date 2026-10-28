#!/bin/sh
. ../../testenv.sh
# doc/developer/language-extensions.md, "External variables": poc
# -emit-macro32's output for VaxExternalVariable.mod and the module it
# imports, VaxExternalData.mod, against the reviewed expected-vax.mar and
# expected-vax-VaxExternalData.mar (../../vaxfixture.sh): each external
# variable is a .EXTERNAL under its linkage name, in capitals, given no
# storage, no zeroing and no root. Then -build's procedure, with -link lines
# naming the object of guest/hand-extdata.mar and the shareable image of
# guest/hand-extshr.mar (in guest/, so that vax_mar does not take them for
# imports), run where the VAX development system can be used
# (guest-external-variable.com), whose exit status is what the program's
# checks add up to.
. ../../vaxfixture.sh
: >result
vax_mar VaxExternalVariable
rm -f VaxExternalVariable.com
poc -target vax-dec-vms -link HAND-EXTDATA.OBJ -link EXTSHR/SHAREABLE -build VaxExternalVariable.mod >>result 2>&1
echo "build exit $?" >>result
vax_do guest-external-variable.com guest-external-variable.expected VaxExternalVariable.com \
  VaxExternalVariable.mar VaxExternalData.mar guest/hand-extdata.mar guest/hand-extshr.mar ../../../rtl/vax/PocRtl.mar
rm -f VaxExternalVariable.com
. ../../testresult.sh
