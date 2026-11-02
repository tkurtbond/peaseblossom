#!/bin/sh
. ../../testenv.sh
# The predeclared unsigned types on VAX/VMS (doc/developer/predeclared-
# unsigned-types.md, step 4): llvm-predeclared-cardinal's cardinal.mod,
# under each size model. Its MACRO-32 and its object must be the reviewed
# ones, and on the guest, built both ways (vax_build), it must print what
# llvm-predeclared-cardinal's expected has for that model.
. ../../vaxfixture.sh
rtl=../../../rtl/vax
written="cardinal.mar FormattedOutput.mar FormattedText.mar LineOutput.mar Out.mar RealDigits.mar"
cp ../llvm-predeclared-cardinal/cardinal.mod .
: >result
for model in O2 OC; do
  case $model in O2) suffix=-O2 ;; OC) suffix=-OC ;; esac
  {
    echo "build status: %X10000001"
    sed -n "/^-$model:\$/,/^exit 0\$/p" ../llvm-predeclared-cardinal/expected | sed -e '1d' -e '$d'
    echo "run status: %X00000001"
  } >guest-run.expected
  rm -f *.sym $written cardinal.com
  poc -$model -target vax-dec-vms -import-path $rtl -emit-macro32 -emit-vax-object cardinal.mod >>result 2>&1
  echo "VAX emit -$model exit $?" >>result
  vax_compare cardinal.mar expected-vax$suffix.mar
  vax_object_image cardinal
  vax_image_compare cardinal.image expected-vax$suffix.image
  builds() {
    rm -f *.sym $written cardinal.com
    poc -$model -target vax-dec-vms $vax_way_option -import-path $rtl -build cardinal.mod >>result 2>&1
    echo "VAX build -$model exit $?" >>result
    vax_do guest-run.com guest-run.expected cardinal.com $written $rtl/PocRtl.mar
  }
  vax_build builds
done
rm -f *.sym *.obj *.image.tmp $written cardinal.com cardinal.mod cardinal.image guest-run.expected
for file in *.image; do
  case $file in expected-vax*) ;; *) rm -f "$file" ;; esac
done
. ../../testresult.sh
