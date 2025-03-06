import math
from decimal import Decimal
q96 = 2**96

Pa = 2800
P = 2835
Pb = 3000

def get_R(Pa, P, Pb):
    Pa_sqrt = math.sqrt(Pa)
    Pb_sqrt = math.sqrt(Pb)
    P_sqrt = math.sqrt(P)

    return (P_sqrt - Pa_sqrt) / (1 / P_sqrt - 1 / Pb_sqrt)

def price_to_sqrtp(p):
    return int(math.sqrt(p) * q96)

sqrtp_low = price_to_sqrtp(Pa)
sqrtp_cur = price_to_sqrtp(P)
sqrtp_upp = price_to_sqrtp(Pb)

def liquidity0(amount, pa, pb):
    if pa > pb:
        pa, pb = pb, pa
    return (amount * (pa * pb) / q96) / (pb - pa)

def liquidity1(amount, pa, pb):
    if pa > pb:
        pa, pb = pb, pa
    return amount * q96 / (pb - pa)

ONE_ETH = 10**18
amount_eth = 1 * ONE_ETH
amount_usdc = 2835 * ONE_ETH

liq0 = liquidity0(amount_eth, sqrtp_cur, sqrtp_upp)
liq1 = liquidity1(amount_usdc, sqrtp_cur, sqrtp_low)
liq = int(min(liq0, liq1))

print("R", get_R(Pa, P, Pb), Decimal(get_R(Pa, P, Pb) * q96))
print(sqrtp_low)
print(sqrtp_cur)
print(sqrtp_upp)
