"""
    dales.jl

DALES's own constants, for reconstructing quantities it produced.

The readers reconstruct DALES-derived quantities — its `ω → w` conversion, its θ_l, etc
"""

"""
    DALES_CONSTANTS

DALES's parameters, from `modglobal.f90:73-101` and `modmicrodata3.f90:163-164`.

`riv` is omitted: it is declared in `modglobal.f90` and never referenced, the
sublimation latent heat its microphysics used being SB3's `rlvi`.
"""
const DALES_CONSTANTS = (;
    grav = 9.81,
    R_d = 287.04,
    R_v = 461.5,
    cp_d = 1004.0,
    L_v = 2.53e6,
    L_s = 2.834e6,
    L_f = 3.337e5,
    p_ref = 1.0e5,
    T_melt = 273.16,
    ρ_water = 998.0,
    von_karman = 0.4,
    stefan_boltzmann = 5.67e-8,
    e_s0 = 610.78,
    a_liquid = 17.27,
    b_liquid = 35.86,
    a_ice = 21.8745584,
    b_ice = 7.66,
    e12_min = 5.0e-5,
    T_mixed_high = 268.0,
    T_mixed_low = 253.0,
)

