      
import math
from decimal import Decimal

# constants, dont change
q96 = 2**96
q192 = 2 ** 192
# =====================

# change here
tick_spacing = 60

low_range = 0.95
high_range = 1.1

P_sqrt = 4436738577262596212334852517
print(Decimal(P_sqrt * 1.03))
L = 447783784380916732911015

decimals0 = 18
decimals1 = 18

x = 0 # uni
y = 0.01 # eth

############## Calculation #############
def sqrt_to_price(P_sqrt, decimals0 = decimals0, decimals1 = decimals1):
    return (P_sqrt / q96)*(P_sqrt / q96) * 10**(decimals0 - decimals1)

def price_to_sqrt(p, decimals0 = decimals0, decimals1 = decimals1):
    p = p / 10**(decimals0 - decimals1)
    return int(math.sqrt(p) * q96)

def price_to_tick(p, tick_spacing):
    r = math.log(p, 1.0001)
    is_negative = r < 0

    r = math.floor(abs(r)) // tick_spacing * tick_spacing
    if is_negative:
        return -1 * r
    return r

def tick_to_price(tick):
    return math.pow(1.0001, tick)

X_to_wei = 10**decimals0
Y_to_wei = 10**decimals1

P = sqrt_to_price(P_sqrt)
Pa = tick_to_price(price_to_tick(P * low_range, tick_spacing))
Pb = tick_to_price(price_to_tick(P * high_range, tick_spacing))

pa_sqrt = price_to_sqrt(Pa)
pb_sqrt = price_to_sqrt(Pb)

x = x * X_to_wei
y = y * Y_to_wei

def get_R_from_tokens(y, x, delta_y, delta_x):
    return (y + delta_y) / (x + delta_x)

def get_R(sa, sp, sb):
    return (sp - sa) / (1 / sp - 1 / sb) / q192
    # return (P_sqrt - Pa_sqrt) * Pb_sqrt * P_sqrt / (Pb_sqrt - P_sqrt) / q192

def get_Ld(L):
    return L / q96

def get_Lm(L):
    return L * q96

def get_B(s, R, x, y, L):
    return y - L * s / q96 - R * x + R * L * q96 / s

def get_C(R, L):
    return -1 * R * L * q96

def derive_R(y, x, delta_y, delta_x):
    return (y + delta_y) / (x - delta_x)

def get_delta_y(L, P_new_sqrt, P_old_sqrt):
    return L * (P_new_sqrt - P_old_sqrt) / q96

def get_delta_x(L, P_new_sqrt, P_old_sqrt):
    return get_Lm(L) / P_new_sqrt - get_Lm(L) / P_old_sqrt

def is_valid_price(p_sqrt, pa_sqrt, pb_sqrt):
    if p_sqrt <= 0:
        return False
    return pa_sqrt <= p_sqrt and p_sqrt <= pb_sqrt

R = get_R(pa_sqrt, P_sqrt, pb_sqrt)
print("R", R, int(R * q96))

A = L / q96
B = get_B(P_sqrt, R, x, y, L)
C = get_C(R, L)

d = B**2 - 4*A*C

new_price_1 = (-B + math.sqrt(d))/(2*A)
new_price_2 = (-B - math.sqrt(d))/(2*A)

new_price = []
if is_valid_price(new_price_1, pa_sqrt, pb_sqrt):
    new_price = new_price_1
elif is_valid_price(new_price_2, pa_sqrt, pb_sqrt):
    new_price = new_price_2
else:
    raise Exception("not swapable")

delta_y = get_delta_y(L, new_price, P_sqrt)
delta_x = get_delta_x(L, new_price, P_sqrt)
if delta_x * delta_y > 0:
    raise Exception("cannot both buy or both sell")

print("token swap x and y", delta_x / X_to_wei, delta_y / Y_to_wei)
print("range", Pa, Pb)

delta_x = 2.135968341540823565 * X_to_wei
delta_y = -0.006718437499999999 * Y_to_wei

print("final positions", (x + delta_x) / X_to_wei, (y + delta_y) / Y_to_wei)