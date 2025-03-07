import math
from decimal import Decimal

P = 0.00329983
Pa = P * 0.95
Pb = P * 1.1

ONE_ETH = 10**18
# low = 11.20093057932891 * ONE_ETH
# hi = 12.379975903468795 * ONE_ETH

low = 0 * ONE_ETH
hi = 20 * ONE_ETH

epslon = 0.001
L = 1409862032491040733326409
x = 1000 * ONE_ETH # uni
y = 20 * ONE_ETH # eth

ONE_ETH = 10 ** 18

def get_R(Pa, P, Pb):
    Pa_sqrt = math.sqrt(Pa)
    Pb_sqrt = math.sqrt(Pb)
    P_sqrt = math.sqrt(P)

    return (P_sqrt - Pa_sqrt) / (1 / P_sqrt - 1 / Pb_sqrt)

def get_delta_x(delta_y, P, L):
    P_sqrt = math.sqrt(P)

    return abs(delta_y) / (P_sqrt) / (P_sqrt + abs(delta_y) / L)

def derive_R(y, x, delta_y, delta_x):
    return (y - delta_y) / (x + delta_x)

R = get_R(Pa, P, Pb)
print(Decimal(R * 2**96))
print(Decimal(epslon * 2**96))

loop = 0

while True:
    mid = low + (hi - low) / 2

    delta_x = get_delta_x(mid, P, L)

    R_now = derive_R(y, x, mid, delta_x)

    diff = (R - R_now) / R

    print("diff", diff, "delta y", mid, "delta x", delta_x)

    if abs(diff) < epslon:
        print("found, swap", mid / ONE_ETH, "for", delta_x / ONE_ETH, "loops", loop)
        break

    if R_now < R:
        hi = mid - 0.0001
    else:
        low = mid + 0.0001
        

    if loop == 100:
        print("loop exhausted")
        break

    loop += 1


