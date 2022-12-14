# you need: pip install sympy== 1.7.1
from sympy import *

s = Symbol('s')
z = Symbol('z')
Q = Symbol('Q')    # resonance
T = Symbol('T')    # sampling interval
w0 = Symbol('w0')  # cutoff freq

# z2s = 2 / T * (z - 1) / (z + 1)
s2z = 2 / T * (z - 1) / (z + 1)

def tod(e):
    """Converts Python expr to D."""
    return repr(e).replace("**", "^^") + ";"

def print_coeff(hs):
    hz = simplify(hs.subs(s, s2z))  # Z transform
    npole = degree(denom(hs), s)
    print("  // === Transfer function ===")
    print("  // H(s) =", tod(hs))  # transfer function in Laplace domain
    print("  // H(z) =", tod(hz))  # transfer function in Z domain
    print("  // #pole =", npole)
    print("  // === Filter coeffients ===")
    print(f"  nFIR = {npole + 1};")
    print(f"  nIIR = {npole};")
    # FIR coeff
    dhz = collect(expand(denom(hz) * z ** -npole), z)
    nhz = collect(expand(numer(hz) * z ** -npole), z)
    a0 = dhz.coeff(z, 0)  # to normalize a0 = 1
    for i in range(npole + 1):
        print(f"  b[{i}] =", tod(nhz.coeff(z, -i) / a0))
    # IIR coeff
    for i in range(1, npole + 1):
        print(f"  a[{i-1}] =", tod(dhz.coeff(z, -i) / a0))
    print("  return;")

print("// -*- mode: d -*-")
print("// DON'T MODIFY THIS FILE AS GENERATED BY resource/filter_coeff.py.")
print()

print("case FilterKind.LP6:")
print_coeff(hs = 1 / (s / w0 + 1))
print()

print("case FilterKind.HP6:")
print_coeff(hs = s / (s + w0))
print()

print("case FilterKind.LP12:")
print_coeff(hs = 1 / (s**2 / w0**2 + s / w0 / Q + 1))
print()

print("case FilterKind.HP12:")
print_coeff(hs = (s**2 / w0**2) / (s**2 / w0**2 + s / w0 / Q + 1))
print()

print("case FilterKind.BP12:")
print_coeff(hs = (s / w0 / Q) / (s**2 / w0**2 + s / w0 / Q + 1))
print()

print("case FilterKind.LP24:")
print("  // Defined in VAFD Sec 5.1, Eq 5.1.")
print("  // https://www.discodsp.net/VAFilterDesign_2.1.0.pdf")
# print_coeff(hs = 1 / (s**2 / w0**2 + s / w0 / Q + 1)**2)
print_coeff(hs = 1 / expand((Q + (1 + s / w0) ** 4)))
print()

print("case FilterKind.LPDL:")
print("  // Defined in VAFD Sec 5.10, Eq 5.29.")
print("  // https://www.discodsp.net/VAFilterDesign_2.1.0.pdf")
print_coeff(hs = 1 / expand(8 * (1 + s / w0)**4 - 8 * (1 + s/w0)**2 + 1 + Q))
print()
