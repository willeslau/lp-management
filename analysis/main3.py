import math
from decimal import Decimal

P = 0.003298429816
Pa = P * 0.95
Pb = P * 1.1

ONE_ETH = 10**18
# low = 11.20093057932891 * ONE_ETH
# hi = 12.379975903468795 * ONE_ETH

low = 0 * ONE_ETH
hi = 1000 * ONE_ETH

epslon = 0.001
L = 1409862032491040733326409
x = 1000 * ONE_ETH # uni
y = 0.1 * ONE_ETH # eth

ONE_ETH = 10 ** 18


def calc_amount1(liq, pa, pb):
    if pa > pb:
        pa, pb = pb, pa
    return liq * (pb - pa)

def get_R(Pa, P, Pb):
    Pa_sqrt = math.sqrt(Pa)
    Pb_sqrt = math.sqrt(Pb)
    P_sqrt = math.sqrt(P)

    return (P_sqrt - Pa_sqrt) / (1 / P_sqrt - 1 / Pb_sqrt)

def get_delta_y(delta_x, P, L):
    P_sqrt = math.sqrt(P)

    P_new_sqrt = P_sqrt * L / (delta_x * P_sqrt + L)
    return calc_amount1(L, P_new_sqrt, P_sqrt)

def derive_R(y, x, delta_y, delta_x):
    return (y + delta_y) / (x - delta_x)

R = get_R(Pa, P, Pb)
print(R, Decimal(R * 2**96))
print(Decimal(epslon * 2**96))
print(Decimal(math.sqrt(P) * 2**96))

loop = 0

while True:
    mid = low + (hi - low) / 2

    delta_y = get_delta_y(mid, P, L)
    
    R_now = derive_R(y, x, mid, delta_y)

    diff = (R - R_now) / R

    print("diff", diff, "delta x", mid / ONE_ETH, "delta y", delta_y / ONE_ETH)

    if abs(diff) < epslon:
        print("found, swap", mid / ONE_ETH, "for", delta_y / ONE_ETH, "loops", loop)
        break

    if R_now < R:
        low = mid - 0.0001
    else:
        hi = mid + 0.0001
        

    if loop == 100:
        print("loop exhausted")
        break

    loop += 1


