#!/bin/sh
. ../../testenv.sh
# rtl/llvm/Tasks.Mod and rtl/vax/Tasks.Mod are one file in two places
# (doc/developer/tasks.md, decision 1): what differs by system is in
# TaskWaiting. A change to one must be copied to the other.
if cmp ../../../rtl/llvm/Tasks.Mod ../../../rtl/vax/Tasks.Mod >/dev/null 2>&1
then echo "the same" >result
else
  echo "rtl/llvm/Tasks.Mod and rtl/vax/Tasks.Mod differ:" >result
  diff ../../../rtl/llvm/Tasks.Mod ../../../rtl/vax/Tasks.Mod >>result 2>&1
fi
. ../../testresult.sh
