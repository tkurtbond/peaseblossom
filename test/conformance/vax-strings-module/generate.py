#!/usr/bin/env python3
# PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
# 19.13, proposal 2): writes guest-run.expected, what stringstest.mod and
# stringsextra.mod print on the VAX. stringstest's lines are llvm-strings'
# expected. stringsextra's are llvm-strings-extra's, but for those of
# Numbers that print a real's bits as a decimal integer (SYSTEM.VAL of the
# LONGREAL as a HUGEINT, of the REAL as a LONGINT, -O2's 32 bits), which
# are G_floating's and F_floating's words here. Those are computed from
# the numerals stringsextra.mod passes, read as Strings' Numeral reads
# them and converted as DecimalToReal converts: the nearest value, ties to
# even, the largest beyond the range, and the nearer of 0 and the smallest
# below it. Run it from this directory.
import re
from fractions import Fraction

# precision, the binary exponent of the smallest value's last bit and of
# the largest value's, the exponent's bias, the fraction's bits, the width
G = (53, -1076, 970, 1024, 52, 64)
F = (24, -151, 103, 128, 23, 32)

# Strings' Numeral: blanks, [+-] digits [. digits] [E|D [+-] digits], a
# digit before or after the point, an exponent only with digits; what
# follows is ignored
NUMERAL = re.compile(r'^[ \t\n\r]*([+-]?)(\d*)(?:\.(\d*))?(?:[EeDd]([+-]?\d+))?')
MAX_NUMERAL = 511


def numeral(text):
    """the value of the numeral at the start of text; None for none, and
    'long' for one longer than maxNumeral"""
    m = NUMERAL.match(text)
    whole, fraction = m.group(2), m.group(3) or ''
    if whole == '' and fraction == '':
        return None
    if len(m.group(0).lstrip(' \t\n\r')) > MAX_NUMERAL:
        return 'long'
    v = Fraction(int(whole + fraction or '0'), 10 ** len(fraction))
    if m.group(4):
        v *= Fraction(10) ** int(m.group(4))
    return -v if m.group(1) == '-' else v


def nearest(v, form):
    """(m, e), v's nearest m * 2^e as DecimalToReal finds it; m 0 for 0"""
    p, lowest, highest = form[0], form[1], form[2]
    if v == 0:
        return 0, 0
    smallest = Fraction(2) ** (p - 1) * Fraction(2) ** lowest
    if v < smallest:
        return (2 ** (p - 1), lowest) if v >= smallest / 2 else (0, 0)
    e = v.numerator.bit_length() - v.denominator.bit_length() - p
    while v / Fraction(2) ** e >= 2 ** p:
        e += 1
    while v / Fraction(2) ** e < 2 ** (p - 1):
        e -= 1
    scaled = v / Fraction(2) ** e
    q = scaled.numerator // scaled.denominator
    rest = scaled - q
    if rest > Fraction(1, 2) or (rest == Fraction(1, 2) and q % 2 == 1):
        q += 1
    if q == 2 ** p:
        q //= 2
        e += 1
    if e > highest:
        return 2 ** p - 1, highest
    return q, e


def as_integer(v, form):
    """v's words in that format, the one at the lowest address least
    significant, as a signed integer of the format's width"""
    p, bias, fraction, width = form[0], form[3], form[4], form[5]
    m, e = nearest(abs(v), form)
    logical = 0 if m == 0 else (int(v < 0) << (width - 1)) | ((e + p + bias) << fraction) | (m - 2 ** (p - 1))
    words = [(logical >> (width - 16 * (i + 1))) & 0xFFFF for i in range(width // 16)]
    n = sum(w << (16 * i) for i, w in enumerate(words))
    return n - (1 << width) if n >> (width - 1) else n


# Numbers' calls, in order: ('set', None) for each x := 42, else
# (LONGREAL or REAL, the string)
source = open('../llvm-strings-extra/stringsextra.mod').read()
body = source[source.index('PROCEDURE Numbers'):source.index('END Numbers')]
calls = []
long = ''
for line in body.splitlines():
    line = line.strip()
    if line.startswith('x := 42'):
        calls.append(('set', None))
    elif line.startswith('FOR k := 0 TO 598'):
        long = '1' * 599
    elif line.startswith('Strings.StrToLongReal(') or line.startswith('Strings.StrToReal('):
        kind = 'long' if 'StrToLongReal' in line else 'short'
        argument = line[line.index('(') + 1:line.index(',')]
        if argument == 'long':
            text = long
        else:
            text = argument.strip('"')
        calls.append((kind, text))

lines = []
x = Fraction(0)
for kind, text in calls:
    if kind == 'set':
        x = Fraction(42)
        continue
    v = numeral(text)
    if kind == 'long':
        if v is None:
            x = Fraction(0)
        elif v != 'long':
            x = v
        lines.append(str(as_integer(x, G)))
    elif v == 'long':
        # the long numeral leaves the REAL 7.0, which Out.Real prints
        lines.append('7.00E+00')
    else:
        lines.append(str(as_integer(v, F)))
extra = open('../llvm-strings-extra/expected').read().splitlines()
start = len(extra) - len(lines)
if start < 0 or extra[start - 1] != 'axxxxb a*b* yes':
    raise SystemExit('Numbers does not start where generate.py expects it')
with open('guest-run.expected', 'w') as f:
    f.write('build status: %X10000001\n== stringstest\n')
    f.write(open('../llvm-strings/expected').read())
    f.write('run status: %X00000001\n== stringsextra\n')
    f.write('\n'.join(extra[:start] + lines) + '\n')
    f.write('run status: %X00000001\n')
