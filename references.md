1. Reading Real Numbers Accurately

    Paper: "How to Read Floating-Point Numbers Accurately" (PLDI 1990)

    Author: William D. Clinger (a major figure in Scheme standards like R4RS and R5RS)

    What it covers: Clinger addressed the problem of how to convert decimal string representations into binary floating-point numbers correctly rounded to the nearest representable value. Before this, many language implementations suffered from subtle off-by-one errors in the least significant bit due to naive conversion algorithms.

2. Printing Real Numbers Accurately

    Paper: "How to Print Floating-Point Numbers Accurately" (ACM SIGPLAN Notices, 1990)

    Authors: Guy L. Steele Jr. (co-designer of Scheme and Common Lisp) and Jon L. White

    What it covers: This paper introduced algorithms to print the shortest decimal representation of a binary floating-point number that rounds back to the exact same binary value when read back in. It revolutionized how languages handle float-to-string conversion without losing precision or printing an excessive, ugly number of trailing digits.

3. Printing Quickly and Accurately

    Paper: "Printing Floating-Point Numbers Quickly and Accurately" (PLDI 1996)

    Authors: Robert G. Burger and R. Kent Dybvig (creators of Chez Scheme)

    What it covers: While Steele and White's algorithm was accurate, it could be slow. Burger and Dybvig (from Indiana University/Chez Scheme) built upon it to create an algorithm that was both mathematically rigorous and fast enough for production compilers, heavily influencing how Scheme and other language runtimes format numbers efficiently.
