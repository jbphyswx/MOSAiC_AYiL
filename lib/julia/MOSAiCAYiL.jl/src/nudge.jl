"""
    nudge.jl

Pure functions for the AYiL DALES testbed nudging shape.

Paper eq. (7) writes max `∂Θ_v/∂z`. AYiL `modtestbed.f90` `testbednudge` uses
centred `∂θ_l/∂z` on 100–5000 m, liquid-only `θ_l`. This module implements the
subroutine that actually ran.
"""

"""Lower bound of the inversion search [m] (DALES `tb_minzinv`)."""
const INVERSION_SEARCH_MIN = NAMELIST.tb_minzinv

"""Upper bound of the inversion search [m] (DALES `tb_maxzinv`)."""
const INVERSION_SEARCH_MAX = NAMELIST.tb_maxzinv

"""
Total water below which moisture is relaxed within one step [kg/kg] (DALES
`qtthres`, `modtestbed.f90:1551`).
"""
const DRY_AIR_NUDGE_THRESHOLD = NAMELIST.qtthres

"""
    inversion_height(ᶜθ_l, z, z_min, z_max)

The height [m] of the largest `∂θ_l/∂z` on the levels with `z_min < z < z_max`,
by the centred difference `(θ_l[k+1] - θ_l[k-1]) / (z[k+1] - z[k-1])`.

`0` when no level lies in the window. The centred difference places the maximum
one level below a sharp jump in `θ_l`, which is a property of the DALES algorithm
this reproduces (`modtestbed.f90:1521-1543`).
"""
function inversion_height(ᶜθ_l, z, z_min, z_max)
    n = length(z)
    FT = eltype(ᶜθ_l)
    best = typemin(FT)
    k_inv = 0
    @inbounds for k in 2:(n - 1)
        z[k] > z_min || continue
        z[k] < z_max || break
        gradient = (ᶜθ_l[k + 1] - ᶜθ_l[k - 1]) / FT(z[k + 1] - z[k - 1])
        if gradient > best
            best = gradient
            k_inv = k
        end
    end
    return k_inv == 0 ? zero(FT) : FT(z[k_inv])
end

"""
    nudge_ramp(z, z_inv, z_mid)

The DALES relaxation shape: `0` at and below `z_inv`, rising linearly to `1` at
`z_mid`, and `1` above. A zero-depth ramp is a step at `z_inv`.
"""
nudge_ramp(z, z_inv, z_mid) =
    z <= z_inv ? zero(z) :
    (z_mid > z_inv ? min(one(z), (z - z_inv) / (z_mid - z_inv)) : one(z))
