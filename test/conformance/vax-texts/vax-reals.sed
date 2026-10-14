# vax-texts: llvm-texts' lines that show a real number's bytes, IEEE 754's
# there, made F_floating's and G_floating's (design section 19.19,
# proposal 4), each checked by hand: VAX F is IEEE single with 2 more in
# its exponent field and its two words swapped, VAX G IEEE double so, its
# four words in the other order
s/bits:0000803F00000000000000C0|/bits:8040000020C0000000000000|/
s/^\(line 1 class 4 x=\[8\]\) 0000C03F$/\1 C0400000/
s/^\(line 1 class 4 x=\[8\]\) 000080BE$/\1 80BF0000/
s/^\(line 1 class 5 y=\[16\]\) 000000000088A340$/\1 C340008800000000/
s/^\(line 1 class 4 x=\[8\]\) F9021550$/\1 1551F902/
s/^\(line 1 class 4 x=\[8\]\) CDCC4C3C$/\1 4C3DCDCC/
s/^\(line 1 class 5 y=\[16\]\) 333333333333D33F$/\1 F33F333333333333/
s/^\(line 3 class 4 x=\[8\]\) 00004041$/\1 40420000/
