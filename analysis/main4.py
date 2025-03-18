import math
from decimal import Decimal

P = 0.003298429816
Pa = P * 0.95
Pb = P * 1.1

ONE_ETH = 10**18

epslon = 0.001
L = 1409862032491040733326409
x = 1000 * ONE_ETH # uni
y = 0.1 * ONE_ETH # eth

def get_R(Pa, P, Pb):
    Pa_sqrt = math.sqrt(Pa)
    Pb_sqrt = math.sqrt(Pb)
    P_sqrt = math.sqrt(P)

    return (P_sqrt - Pa_sqrt) / (1 / P_sqrt - 1 / Pb_sqrt)

def get_delta_y(delta_x, P, L):
    P_sqrt = math.sqrt(P)

    P_new_sqrt = P_sqrt * L / (delta_x * P_sqrt + L)
    return calc_amount1(L, P_new_sqrt, P_sqrt)

def get_B(P, R, x, y, L):
    s = math.sqrt(P)
    B = y - R * x + L * s - R * L / s
    return -B

def get_C(R, L):
    return -1 * R * L

def derive_R(y, x, delta_y, delta_x):
    return (y + delta_y) / (x - delta_x)

R = get_R(Pa, P, Pb)
A = L
B = get_B(P, R, x, y, L)
C = get_C(R, L)

d = B**2 - 4*A*C

delta_y_1 = (-B + math.sqrt(B**2 - 4*A*C))/(2*A)
delta_y_2 = (-B - math.sqrt(B**2 - 4*A*C))/(2*A)

print(delta_y_1 / ONE_ETH, delta_y_2 / ONE_ETH)