MODULE lib;
  (* 000-todo.org's "output directory for build artifacts" item:
     -emit-interface should be able to write lib.sym into a directory
     other than the current one. test.sh creates "out" itself (not
     committed - an empty directory can't be, and it's exactly the kind
     of generated build artifact test/testenv.sh already expects to
     clean up). *)

  CONST X* = 1;

END lib.
