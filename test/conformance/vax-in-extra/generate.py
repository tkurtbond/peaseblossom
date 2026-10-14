#!/usr/bin/env python3
# PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
# 19.11, proposal 5): writes guest-run.expected, what llvm-in-extra's
# inextra.mod prints on the VAX. Its lines are llvm-in-extra's expected,
# but for those that print a real's bits in hex (Out.Hex of the LONGREAL
# as a HUGEINT, of the REAL as a LONGINT), which are G_floating's and
# F_floating's here. Those are computed from input.txt, read as In.LongReal
# and In.Real read a line, and converted as DecimalToReal converts: the
# nearest value, ties to even, the largest beyond the range, and the nearer
# of 0 and the smallest below it. Run it from this directory.
import re
from fractions import Fraction

# precision, the binary exponent of the smallest value's last bit and of
# the largest value's, the exponent's bias, and the fraction's bits
G = (53, -1076, 970, 1024, 52, 64)
F = (24, -151, 103, 128, 23, 32)

NUMERAL = re.compile(r'^[ \t]*([+-]?)((\d+)\.?(\d*)|\.(\d+))([EeDd]([+-]?\d+))?[ \t]*$')


def value(text):
    """the numeral's exact value, or None if In does not take the line"""
    m = NUMERAL.match(text)
    if not m:
        return None
    mantissa = m.group(2).replace('.', '') or '0'
    point = m.group(2).find('.')
    decimals = len(m.group(2)) - point - 1 if point >= 0 else 0
    v = Fraction(int(mantissa), 10 ** decimals)
    if m.group(7):
        v *= Fraction(10) ** int(m.group(7))
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


def bits(v, form):
    """the hex Out.Hex prints of v in that format: its words from the
    lowest address last"""
    p, bias, fraction, width = form[0], form[3], form[4], form[5]
    negative = v < 0
    m, e = nearest(abs(v), form)
    if m == 0:
        logical = 0
    else:
        logical = (int(negative) << (width - 1)) | ((e + p + bias) << fraction) | (m - 2 ** (p - 1))
    words = [(logical >> (width - 16 * (i + 1))) & 0xFFFF for i in range(width // 16)]
    return ''.join('%04X' % w for w in reversed(words))


with open('../llvm-in-extra/input.txt', newline='') as f:
    lines = [line.rstrip('\n').replace('\r', '') for line in f]
with open('../llvm-in-extra/expected') as f:
    expected = f.read().splitlines()

# the lines that In.LongReal and In.Real read, in order: from the one
# after "windows line"
reals = iter(lines[lines.index('windows line') + 1:])
x = Fraction(0)
r = Fraction(0)
long_count = short_count = 0
out = ['build status: %X10000001']
for line in expected:
    m = re.match(r'^(LongReal|Real) ([0-9A-F]+) (done|not done)$', line)
    if m:
        if m.group(1) == 'LongReal':
            long_count += 1
            if long_count == 5:
                x = Fraction(1)  # x := 1.0D0
            v = value(next(reals))
            if v is not None:
                x = v
            shown = bits(x, G)
        else:
            short_count += 1
            if short_count == 3:
                r = Fraction(1)  # r := 1.0
            v = value(next(reals))
            if v is not None:
                r = v
            shown = bits(r, F)
        done = 'done' if v is not None else 'not done'
        if done != m.group(3):
            raise SystemExit('the model disagrees with llvm-in-extra on: ' + line)
        line = '%s %s %s' % (m.group(1), shown, done)
    out.append(line)
out.append('run status: %X00000001')
with open('guest-run.expected', 'w') as f:
    f.write('\n'.join(out) + '\n')
