import math

P = 0.00329983
Pa = P * 0.95
Pb = P * 1.1

L = 1409862032491040733326409

ONE_ETH = 10 ** 18

x = 1000 * ONE_ETH # uni
y = 17 * ONE_ETH # eth

def get_R(Pa, P, Pb):
    Pa_sqrt = math.sqrt(Pa)
    Pb_sqrt = math.sqrt(Pb)
    P_sqrt = math.sqrt(P)

    return (P_sqrt - Pa_sqrt) / (1 / P_sqrt - 1 / Pb_sqrt)

def get_A(P, L):
    P_sqrt = math.sqrt(P)
    return P_sqrt / L

def get_B(P, R, x, y, L):
    P_sqrt = math.sqrt(P)

    return P + R - y * P_sqrt / L + R * x * P_sqrt / L

def get_C(R, x, y, P):
    return R * x * P - y * P

def get_delta_x(delta_y, P, L):
    P_sqrt = math.sqrt(P)

    return abs(delta_y) / (P_sqrt) / (P_sqrt + abs(delta_y) / L)

R = get_R(Pa, P, Pb)
A = get_A(P, L)
B = get_B(P, R, x, y, L)
C = get_C(R, x, y, P)

d = B**2 - 4*A*C

delta_y_1 = (-B + math.sqrt(B**2 - 4*A*C))/(2*A)
delta_y_2 = (-B - math.sqrt(B**2 - 4*A*C))/(2*A)

delta_x_1 = get_delta_x(delta_y_1, P, L)
delta_x_2 = get_delta_x(delta_y_2, P, L)

print("d", math.sqrt(d))
print("numerator", -B + math.sqrt(d), -B - math.sqrt(d))
print("R", R)
print("A", A)
print("B", B)
print("C", C)

solution = 0

if delta_y_1 > 0 and delta_x_1 > 0 and delta_y_1 < y:
    solution = delta_y_1
if delta_y_2 > 0 and delta_x_2 > 0 and delta_y_2 < y:
    solution = min(solution, delta_y_2)

# print("solution 1", delta_y_1 / ONE_ETH, delta_x_1 / ONE_ETH)
# print("solution 2", delta_y_2 / ONE_ETH, delta_x_2 / ONE_ETH)

print("solution", solution / ONE_ETH)
# print("solution 2", delta_y_2 / ONE_ETH * 1.05, delta_y_2 / ONE_ETH * 0.95)
