/* a native library a module's C++ part uses: libnative.a, which the
   fixture builds, so that linking it takes -link -L<dir> -link -lnative */
int native_triple(int x) { return 3 * x; }
