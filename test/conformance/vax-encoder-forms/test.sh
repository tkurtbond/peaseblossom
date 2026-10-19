#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 18 step 3e: the VAX encoder on a module that has every
# instruction of its opcode table and every form it chooses between
# (doc/developer/vax-object-language.md, sections 14.5 and 14.10), which
# EncoderForms.Mod makes as VaxInstructions' lines and writes twice: as
# MACRO-32, forms.mar, compared with expected-vax.mar, and as the image of
# the object VaxEncoder makes of them, forms.image, compared with
# expected-vax.image, the image of the object MACRO made from
# expected-vax.mar on the guest (tools/vax-macro-image).
. ../../vaxfixture.sh
rm -f forms.mar forms.image
poc -OC -import-path ../../../src/back/vax -import-path ../../../src/front -o vax-encoder-forms -build EncoderForms.Mod >result 2>&1
./vax-encoder-forms >>result 2>&1
vax_compare forms.mar expected-vax.mar
vax_image_compare forms.image expected-vax.image
. ../../testresult.sh
