#!/usr/bin/env python3
# Writes what llvm-reals-module's reals.mod and beyond.mod print on the VAX,
# from the definitions of F_floating and G_floating and Python's exact
# fractions, not by running them (PLAN.md Phase 17 step 3,
# doc/developer/vax-macro32-backend.md, section 19.7, proposals 5 and 6).
# Not run by the test.
#
#   python3 generate.py vax >guest-run.expected
#   python3 generate.py ieee   (what LLVM prints: checks this model against
#                               the programs' real output on Unix)
#
# The model of each program follows it line by line. A numeral in the source
# is a constant: on the VAX MACRO rounds it, ties away from zero, and on
# Unix it is the nearest IEEE value, ties to even. Arithmetic rounds the
# same way as each machine's constants, the VAX's to nearest, ties away
# (MACRO 9.2.8.3); a VAX result below the smallest value is 0, the
# floating-underflow fault being off. Ten and TenL are correctly rounded,
# ties to even, on both: on the VAX, beyond the range the largest value,
# below it the nearer of 0 and the smallest (DecimalToReal); on Unix,
# infinity, the subnormals and 0. Hex is the value's bytes in memory order,
# two hexadecimal digits each, as Reals.ConvertH writes them.
import sys
from fractions import Fraction as Q

MODE = sys.argv[1] if len(sys.argv) > 1 else 'vax'
VAX = MODE == 'vax'

# precision, the binary exponent of the smallest normal value's last bit,
# that of the largest's, and whether there are subnormals
if VAX:
    SINGLE = dict(p=24, low=-151, high=103, sub=False)
    DOUBLE = dict(p=53, low=-1076, high=970, sub=False)
else:
    SINGLE = dict(p=24, low=-149, high=104, sub=True)
    DOUBLE = dict(p=53, low=-1074, high=971, sub=True)
INF = 'inf'

def largest(fmt):
    return Q(2 ** fmt['p'] - 1) * Q(2) ** fmt['high']

def smallest(fmt):
    # the smallest normal value
    if fmt['sub']:
        return Q(2) ** (fmt['low'] + fmt['p'] - 1)
    return Q(2 ** (fmt['p'] - 1)) * Q(2) ** fmt['low']

def round_to(x, fmt, away, saturate=False, nearer_to_smallest=False):
    """x rounded to fmt: to nearest, ties away from zero or to even."""
    if x == 0:
        return Q(0)
    sign = -1 if x < 0 else 1
    a = abs(x)
    p = fmt['p']
    # the exponent of the last bit
    e = a.numerator.bit_length() - a.denominator.bit_length() - p
    while a / Q(2) ** e >= 2 ** p:
        e += 1
    while a / Q(2) ** e < 2 ** (p - 1):
        e -= 1
    if e < fmt['low']:
        if not fmt['sub']:
            # below the smallest: 0, or the smallest
            s = smallest(fmt)
            if nearer_to_smallest and a >= s / 2:
                return sign * s
            if not nearer_to_smallest:
                # hardware: rounded at the smallest exponent, else 0
                q = a / Q(2) ** fmt['low']
                n = int(q)
                r = q - n
                if r > Q(1, 2) or (r == Q(1, 2) and (away or n % 2)):
                    n += 1
                if n >= 2 ** (p - 1):
                    return sign * Q(n) * Q(2) ** fmt['low']
            return Q(0)
        e = fmt['low']
    q = a / Q(2) ** e
    n = int(q)
    r = q - n
    if r > Q(1, 2) or (r == Q(1, 2) and (away or n % 2)):
        n += 1
    if n == 2 ** p:
        n //= 2
        e += 1
    if e > fmt['high']:
        if saturate:
            return sign * largest(fmt)
        return INF if sign > 0 else '-' + INF
    return sign * Q(n) * Q(2) ** e

def const(text, fmt):
    """a numeral in the source: MACRO's rounding on the VAX"""
    return round_to(Q(text.replace('D', 'E').replace('d', 'e')), fmt, VAX)

def arith(x, fmt):
    return round_to(x, fmt, VAX)

def ten(e, fmt):
    v = Q(10) ** e
    if VAX:
        return round_to(v, fmt, False, saturate=True, nearer_to_smallest=True)
    return round_to(v, fmt, False)

# ---- bits ----

def fields(x, fmt):
    """sign, the exponent field, the fraction field"""
    p = fmt['p']
    if x == INF or x == '-' + INF:
        return (1 if x[0] == '-' else 0), (255 if p == 24 else 2047), 0
    sign = 1 if x < 0 else 0
    a = abs(x)
    if a == 0:
        return sign, 0, 0
    e = a.numerator.bit_length() - a.denominator.bit_length() - p
    while a / Q(2) ** e >= 2 ** p:
        e += 1
    while a / Q(2) ** e < 2 ** (p - 1):
        e -= 1
    if VAX:
        bias = 128 if p == 24 else 1024
        n = int(a / Q(2) ** e)
        # 0.1f * 2^(E - bias) = n * 2^e, n = 2^(p-1) + f: E - bias = e + p
        return sign, e + p + bias, n - 2 ** (p - 1)
    bias = 127 if p == 24 else 1023
    if e < fmt['low']:
        e = fmt['low']
    n = int(a / Q(2) ** e)
    if n < 2 ** (p - 1):
        return sign, 0, n
    return sign, e + p - 1 + bias, n - 2 ** (p - 1)

def bits(x, fmt):
    sign, ex, f = fields(x, fmt)
    return pack(sign, ex, f, fmt)

def pack(sign, ex, f, fmt):
    p = fmt['p']
    if not VAX:
        if p == 24:
            return sign << 31 | ex << 23 | f
        return sign << 63 | ex << 52 | f
    if p == 24:
        w0 = sign << 15 | ex << 7 | f >> 16
        return w0 | (f & 0xFFFF) << 16
    w0 = sign << 15 | ex << 4 | f >> 48
    return w0 | (f >> 32 & 0xFFFF) << 16 | (f >> 16 & 0xFFFF) << 32 | (f & 0xFFFF) << 48

def unpack(b, fmt):
    p = fmt['p']
    if not VAX:
        if p == 24:
            return b >> 31, b >> 23 & 255, b & (2 ** 23 - 1)
        return b >> 63, b >> 52 & 2047, b & (2 ** 52 - 1)
    if p == 24:
        w0, w1 = b & 0xFFFF, b >> 16
        return w0 >> 15, w0 >> 7 & 255, (w0 & 127) << 16 | w1
    w = [b >> 16 * i & 0xFFFF for i in range(4)]
    return w[0] >> 15, w[0] >> 4 & 2047, (w[0] & 15) << 48 | w[1] << 32 | w[2] << 16 | w[3]

def value(b, fmt):
    """the value of bits, as Reals.ConvertL reads it"""
    p = fmt['p']
    sign, ex, f = unpack(b, fmt)
    if VAX:
        if ex == 0:
            return Q(0)
        bias = 128 if p == 24 else 1024
        v = Q(2 ** (p - 1) + f) * Q(2) ** (ex - bias - p)
    else:
        bias = 127 if p == 24 else 1023
        if ex == 0:
            v = Q(f) * Q(2) ** fmt['low']
        else:
            v = Q(2 ** (p - 1) + f) * Q(2) ** (ex - bias - p + 1)
    return -v if sign else v

def hexbytes(b, count):
    return ''.join('%02X' % (b >> 8 * k & 255) for k in range(count))

def H(x):
    return hexbytes(bits(x, SINGLE), 4)

def HL(x):
    return hexbytes(bits(x, DOUBLE), 8)

def expo(b, fmt):
    return unpack(b, fmt)[1]

def set_expo(x, ex, fmt):
    sign, old, f = unpack(bits(x, fmt), fmt)
    mask = 256 if fmt['p'] == 24 else 2048
    if VAX and ex % mask == 0 and sign == 0:
        # x reaches Hex and ConvertH as a REAL or LONGREAL value parameter,
        # copied by a floating move, and the VAX takes any positive operand
        # with exponent 0 as an exact zero and writes a zero result as all
        # zeros (MACRO and Instruction Set Reference Manual 5.4,
        # "Floating-point 0")
        return 0
    return pack(sign, ex % mask, f, fmt)

def convert_l(b, n, fmt=None):
    v = value(b, fmt or DOUBLE)
    i = int(abs(v))
    return ''.join(str(i // 10 ** k % 10) for k in range(n))

out = []
def line(s):
    out.append(s)

def digits(x, n):
    b = bits(x, DOUBLE)
    line('ConvertL %d: %s' % (n, convert_l(b, n)))

# ---- reals.mod ----
for e in range(0, 39):
    line('Ten(%d) = %s' % (e, H(ten(e, SINGLE))))
for e in range(0, 23):
    line('TenL(%d) = %s' % (e, HL(ten(e, DOUBLE))))

def show_expo(x):
    line('Expo %s = %d' % (H(x), expo(bits(x, SINGLE), SINGLE)))

def show_expo_l(x):
    line('ExpoL %s = %d' % (HL(x), expo(bits(x, DOUBLE), DOUBLE)))

c = lambda t: const(t, SINGLE)
cl = lambda t: const(t, DOUBLE)
show_expo(c('0.0')); show_expo(c('1.0')); show_expo(c('-1.0')); show_expo(c('0.5')); show_expo(c('2.0E37'))
x = arith(c('1.0E-30') * c('1.0E-10'), SINGLE); show_expo(x)
show_expo(largest(SINGLE)); show_expo(-largest(SINGLE))
show_expo_l(cl('0.0')); show_expo_l(cl('1.0')); show_expo_l(cl('-2.0')); show_expo_l(cl('0.25'))
show_expo_l(cl('1.0E300')); y = arith(cl('1.0E-300') * cl('1.0E-23'), DOUBLE); show_expo_l(y)

def set_line(label, x, ex, fmt):
    b = set_expo(x, ex, fmt)
    line('%s: %s' % (label, hexbytes(b, 4 if fmt['p'] == 24 else 8)))

set_line('SetExpo 1.5, 129', c('1.5'), 129, SINGLE)
set_line('SetExpo -1.5, 100', c('-1.5'), 100, SINGLE)
set_line('SetExpo 1.0, 255', c('1.0'), 255, SINGLE)
set_line('SetExpo 3.0, 0', c('3.0'), 0, SINGLE)
set_line('SetExpo 1.0, 383', c('1.0'), 383, SINGLE)
set_line('SetExpoL 1.5, 1025', cl('1.5'), 1025, DOUBLE)
set_line('SetExpoL -1.5, 1000', cl('-1.5'), 1000, DOUBLE)
set_line('SetExpoL 1.0, 2047', cl('1.0'), 2047, DOUBLE)
set_line('SetExpoL 3.0, 0', cl('3.0'), 0, DOUBLE)
set_line('SetExpoL 1.0, 3071', cl('1.0'), 3071, DOUBLE)

digits(cl('0.0'), 3); digits(cl('7.0'), 1); digits(cl('7.0'), 4); digits(cl('9.99'), 3)
digits(cl('-42.7'), 4); digits(cl('123456789.0'), 9); digits(cl('1234567890.0'), 12)
y = arith(arith(cl('12345678.0') * cl('100000000.0'), DOUBLE) + cl('90123456.0'), DOUBLE); digits(y, 16)
y = arith(arith(cl('90071992.0') * cl('100000000.0'), DOUBLE) + cl('54740993.0'), DOUBLE); digits(y, 17)
y = arith(arith(cl('123456789.0') * cl('1000000000.0'), DOUBLE) + cl('12345678.0'), DOUBLE); digits(y, 18)
digits(cl('98765.4321'), 3); digits(cl('0.999'), 2)
line('Convert 12345.0, 8: %s' % convert_l(bits(c('12345.0'), DOUBLE), 8))
line('Convert -0.5, 2: %s' % convert_l(bits(c('-0.5'), DOUBLE), 2))
line('ConvertH 1.0: %s' % H(c('1.0')))
line('ConvertH -2.5: %s' % H(c('-2.5')))
line('ConvertH 0.1: %s' % H(c('0.1')))
line('ConvertHL 1.0: %s' % HL(cl('1.0')))
line('ConvertHL -2.5: %s' % HL(cl('-2.5')))
line('ConvertHL 0.1: %s' % HL(cl('0.1')))
reals_lines = len(out)

# ---- beyond.mod ----
for e in range(0, 310):
    line('TenL(%d) = %s' % (e, HL(ten(e, DOUBLE))))
for e in (-1, -22, -23, -300, -323, -324, 32767, -32768):
    line('TenL(%d) = %s' % (e, HL(ten(e, DOUBLE))))
for e in (39, -1, -10, -38, -45, -46, 32767, -32768):
    line('Ten(%d) = %s' % (e, H(ten(e, SINGLE))))
digits(cl('1.0E300'), 25)
y = arith(cl('4294967296.0') * cl('4294967296.0'), DOUBLE); digits(y, 20); digits(y, 22)
digits(largest(DOUBLE), 20)
y = arith(cl('1.0E-300') * cl('1.0E-23'), DOUBLE); digits(y, 3)
digits(cl('1.0E-5'), 3)
digits(cl('-1.0E20'), 21)
line('unchanged')

if MODE == 'ieee' and len(sys.argv) > 3:
    # compare with LLVM's own output of the two programs
    ok = True
    for name, part in ((sys.argv[2], out[:reals_lines]), (sys.argv[3], out[reals_lines:])):
        real = open(name).read().split('\n')[:-1]
        for k, (a, b) in enumerate(zip(part, real)):
            if a != b:
                print('%s:%d model %s, real %s' % (name, k + 1, a, b)); ok = False
        if len(part) != len(real):
            print('%s: %d lines in the model, %d real' % (name, len(part), len(real))); ok = False
    print('the IEEE model matches' if ok else 'the IEEE model differs')
else:
    # guest-run.com's output: the build's status, then each program's
    # lines and its status
    print('build status: %X10000001')
    print('== reals')
    print('\n'.join(out[:reals_lines]))
    print('run status: %X00000001')
    print('== beyond')
    print('\n'.join(out[reals_lines:]))
    print('run status: %X00000001')
