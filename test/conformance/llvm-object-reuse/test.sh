#!/bin/sh
. ../../testenv.sh
# Ongoing implementation enhancements, item 3: an object whose stamp
# matches is reused, not compiled again. A module's .ll ends with a symbol
# @<M>.-build.<stamp>, the hash of its clang -c command and its IR; a C
# part's .d (clang -MD) ends with "# poc-build <stamp>", the hash of its
# command and every file it read. Each step lists the files clang -c
# compiled, then runs the program:
#   1. the first build compiles everything; again, nothing;
#   2. touching every file, or a comment in A, compiles nothing;
#   3. A's body: A only; A's interface: A, and B and M, whose IR declares
#      A's procedures;
#   4. a.h, a header of A.c: A.c only;
#   5. another -opt compiles everything; -rebuild compiles everything;
#   6. -compile reuses the A.o -build made (A.ll does not depend on the
#      runtime the program brings); an A.o without the stamp is compiled again;
#   7. -lto reuses nothing.
unset POC_IMPORT_PATH POC_LIBRARY_PATH
build() {
  echo "-- $1"
  shift
  if poc "$@" -verbose -o m -build M.Mod >build.out 2>&1; then
    grep -E '^clang(\+\+)? -c' build.out | grep -oE "'(A|B|M)\.(ll|c)'" | sed 's/^/compiled /'
    ./m
  else
    echo "poc failed:"; cat build.out
  fi
}
rm -rf work && mkdir work && cp src/* work/ && cd work
: >../result
echo "== 1." >>../result
build "first build" >>../result
build "again" >>../result
echo "== 2." >>../result
sleep 1; touch *
build "touched" >>../result
sed 's/RETURN 3/RETURN 3 (* a comment *)/' A.Mod >A.tmp && mv A.tmp A.Mod
build "a comment in A" >>../result
echo "== 3." >>../result
sed 's/RETURN 3 (\* a comment \*)/RETURN 4/' A.Mod >A.tmp && mv A.tmp A.Mod
build "A's body" >>../result
# a here-document, not sed: OpenBSD's sed does not make \n a line break
cat >A.Mod <<'EOF'
MODULE A;
  PROCEDURE ["C", "a_twice"] Twice*(x: INTEGER): INTEGER;
  PROCEDURE Three*(): INTEGER; BEGIN RETURN 4 END Three;
  PROCEDURE Five*(): INTEGER; BEGIN RETURN 5 END Five;
END A.
EOF
build "A's interface" >>../result
echo "== 4." >>../result
printf '#define MUL 3\n' >a.h
build "a.h" >>../result
echo "== 5." >>../result
build "-opt 1" -opt 1 >>../result
build "-opt 1 again" -opt 1 >>../result
build "-rebuild" -opt 1 -rebuild >>../result
echo "== 6." >>../result
compiles() { poc "$@" -verbose -compile A.Mod 2>&1 | grep -c "^clang -c .*'A\.ll'"; }
(echo "-- -compile"; compiles -opt 1; echo "-- -compile again"; compiles -opt 1) >>../result
clang -c -o A.o -x c /dev/null
build "A.o without the stamp" -opt 1 >>../result
echo "== 7." >>../result
build "-lto" -opt 1 -lto >>../result
build "-lto again" -opt 1 -lto >>../result
cd ..
rm -rf work
. ../../testresult.sh
