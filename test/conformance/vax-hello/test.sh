#!/bin/sh
. ../../testenv.sh
# PLAN.md Phase 16 step 2: a hand-written MACRO-32 program, hand-hello.mar,
# assembled, linked and run on the VAX where the development system can be
# used (../../vaxfixture.sh, vax_do); its output compared with
# guest-hello.expected. Elsewhere only the skip is reported, so result is
# empty on every host when all is well.
. ../../vaxfixture.sh
: >result
vax_do guest-hello.com guest-hello.expected hand-hello.mar
. ../../testresult.sh
