#!/bin/sh
. ../../testenv.sh

case "$BACKEND" in
  voc)
    voc hello.mod -m
    ./hello >result
    ;;
  *)
    echo "hello: no recipe for backend '$BACKEND' yet" >&2
    exit 1
    ;;
esac

. ../../testresult.sh
