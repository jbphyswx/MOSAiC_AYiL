"""
    monin_obukhov.jl

The AYiL surface layer: Monin–Obukhov with the Grachev et al. (2007) arctic stable branch
(`modsurface.f90:850-940` for the coefficients and fluxes, `:1507-1657` for the Obukhov solve
and the stability functions).
"""

"""
Coefficients of the surface-layer stability functions, `modsurface.f90:1561-1657`.

`arctic` holds the Grachev et al. (2007) constants `larcticstab = true` selects. The source
notes that its ψ and φ are **not** mutually consistent there (`:1617-1621`), so the two are
kept as DALES writes them rather than reconciled.
"""
const STABILITY = (;
    businger = 16.0,
    stable_linear = 5.0,
    phi_cap = 6.0,
    arctic = (; am = 5.0, ah = 5.0, bh = 5.0, ch = 3.0),
)

"""
    psim(ζ; arctic_stable)

Integrated stability correction for momentum (`modsurface.f90:1561-1586`).

`ζ ≤ 0` is Businger–Dyer with `x = (1 − 16ζ)^(1/4)`. On the stable side `arctic_stable` selects
Grachev et al. (2007) with `a_m = 5`, `b_m = a_m/6.5`, stated for `0 ≤ ζ < 100`; otherwise the
Beljaars–Holtslag form.
"""
function psim(ζ::FT; arctic_stable::Bool = SURFACE_LAYER.larcticstab) where {FT}
    if ζ <= zero(FT)
        x = (one(FT) - FT(STABILITY.businger) * ζ)^FT(0.25)
        return FT(pi) / 2 - 2 * atan(x) + log((one(FT) + x)^2 * (one(FT) + x^2) / 8)
    elseif arctic_stable
        am = FT(STABILITY.arctic.am)
        bm = am / FT(6.5)
        bbm = ((one(FT) - bm) / bm)^(one(FT) / 3)
        x = (one(FT) + ζ)^(one(FT) / 3)
        return -3 * am / bm * (x - one(FT)) +
               am * bbm / (2 * bm) * (
            2 * log((x + bbm) / (one(FT) + bbm)) -
            log((x^2 - x * bbm + bbm^2) / (one(FT) - bbm + bbm^2)) +
            2 * sqrt(FT(3)) * (
                atan((2 * x - bbm) / (sqrt(FT(3)) * bbm)) -
                atan((2 - bbm) / (sqrt(FT(3)) * bbm))
            )
        )
    end
    return -FT(2) / 3 * (ζ - 5 / FT(0.35)) * exp(-FT(0.35) * ζ) - ζ - (FT(10) / 3) / FT(0.35)
end

"""
    psih(ζ; arctic_stable)

Integrated stability correction for heat (`modsurface.f90:1588-1615`), with `a_h = b_h = 5`
and `c_h = 3` on the Grachev branch.
"""
function psih(ζ::FT; arctic_stable::Bool = SURFACE_LAYER.larcticstab) where {FT}
    if ζ <= zero(FT)
        x = (one(FT) - FT(STABILITY.businger) * ζ)^FT(0.25)
        return 2 * log((one(FT) + x^2) / 2)
    elseif arctic_stable
        ah, bh, ch = FT(STABILITY.arctic.ah), FT(STABILITY.arctic.bh), FT(STABILITY.arctic.ch)
        bbh = sqrt(FT(5))
        return -bh / 2 * log(one(FT) + ch * ζ + ζ^2) +
               (-ah / bbh + bh * ch / (2 * bbh)) * (
            log((2 * ζ + ch - bbh) / (2 * ζ + ch + bbh)) - log((ch - bbh) / (ch + bbh))
        )
    end
    return -FT(2) / 3 * (ζ - 5 / FT(0.35)) * exp(-FT(0.35) * ζ) -
           (one(FT) + (FT(2) / 3) * ζ)^FT(1.5) - (FT(10) / 3) / FT(0.35) + one(FT)
end

"""
    phim(ζ; arctic_stable)

Local stability function for momentum (`modsurface.f90:1622-1639`).

The Grachev branch is **uncapped**; the cap of 6 at `ζ ≥ 1` belongs to the non-arctic branch
alone.
"""
function phim(ζ::FT; arctic_stable::Bool = SURFACE_LAYER.larcticstab) where {FT}
    ζ < zero(FT) && return (one(FT) - FT(STABILITY.businger) * ζ)^FT(-0.25)
    arctic_stable && return one(FT) +
           (FT(6.5) * ζ * (one(FT) + ζ)^(one(FT) / 3)) / (FT(1.3) + ζ)
    ζ < one(FT) && return one(FT) + FT(STABILITY.stable_linear) * ζ
    return FT(STABILITY.phi_cap)
end

"""
    phih(ζ; arctic_stable)

Local stability function for heat (`modsurface.f90:1642-1659`). Uncapped on the Grachev
branch, as [`phim`](@ref) is.
"""
function phih(ζ::FT; arctic_stable::Bool = SURFACE_LAYER.larcticstab) where {FT}
    ζ < zero(FT) && return (one(FT) - FT(STABILITY.businger) * ζ)^FT(-0.5)
    arctic_stable &&
        return one(FT) + (5 * ζ + 5 * ζ^2) / (one(FT) + 3 * ζ + ζ^2)
    ζ < one(FT) && return one(FT) + FT(STABILITY.stable_linear) * ζ
    return FT(STABILITY.phi_cap)
end

"""
    surface_virtual_pottemp(backend, θ, q_tot)

`θ_v = θ (1 + (R_v/R_d − 1) q_tot)`, the form the surface layer uses at both ends
(`modsurface.f90:1508` for the air, `:1098` for the skin).

Condensate is **not** removed and `θ_l` stands in for `θ`, which is what DALES does here and
is not the interior [`virtual_temperature`](@ref) convention.
"""
surface_virtual_pottemp(backend, θ::FT, q_tot::FT) where {FT} =
    θ * (one(FT) + (R_v(backend, FT) / R_d(backend, FT) - one(FT)) * q_tot)

"""
    bulk_richardson(θ_v, θ_v_surface, z, wind_speed; grav, wind_floor)

DALES's surface bulk Richardson number, `(g/θ_vs) z (θ_v − θ_vs) / max(|U|², 0.01)`
(`modsurface.f90:1508-1513`). The squared wind is floored, not the wind.
"""
function bulk_richardson(
    θ_v::FT, θ_v_surface::FT, z::FT, wind_speed::FT;
    gravity::FT = FT(DALES_CONSTANTS.grav), wind_floor::FT = FT(0.01),
) where {FT}
    return gravity / θ_v_surface * z * (θ_v - θ_v_surface) /
           max(wind_speed^2, wind_floor)
end

# The function whose root the Obukhov solve seeks: Rib as a function of L.
function _richardson_of(L::FT, z::FT, z0m::FT, z0h::FT, arctic_stable::Bool) where {FT}
    heat = log(z / z0h) - psih(z / L; arctic_stable) + psih(z0h / L; arctic_stable)
    momentum = log(z / z0m) - psim(z / L; arctic_stable) + psim(z0m / L; arctic_stable)
    return z / L * heat / momentum^2
end

"""
    obukhov_length(Rib, z, z0m, z0h; L_init, tol, maxiter, arctic_stable, cap)

The Obukhov length [m] solving `Rib = ζ [ln(z/z0h) − ψ_h(ζ) + ψ_h(z0h/L)] /
[ln(z/z0m) − ψ_m(ζ) + ψ_m(z0m/L)]²` (`modsurface.f90:1516-1553`), by Newton with the
derivative taken as a central difference at `L(1 ± 0.001)`.

`Rib == 0` returns `cap`, which is what DALES does when there is no surface flux. `L` is reset
to `sign(Rib) 0.01` whenever `Rib L < 0` or `|L| == 1e5`, and that reset is also where
`L_init = nothing` starts. `|L|` is capped at `cap`. Errors after `maxiter`, as DALES stops.

DALES carries the previous step's `oblav` into the next solve and initialises it at `-1e10`
(`:842-843`), so a standalone call starting from the reset is the deterministic equivalent.
"""
function obukhov_length(
    Rib::FT, z::FT, z0m::FT, z0h::FT;
    L_init::Union{Nothing, FT} = nothing,
    tol::FT = FT(1.0e-4),
    maxiter::Int = 1000,
    arctic_stable::Bool = SURFACE_LAYER.larcticstab,
    cap::FT = FT(1.0e6),
) where {FT}
    z > z0m || error("The surface layer needs z > z0m; got z = $z and z0m = $z0m.")
    z > z0h || error("The surface layer needs z > z0h; got z = $z and z0h = $z0h.")
    iszero(Rib) && return cap

    reset(L) = (Rib * L < zero(FT) || abs(L) == FT(1.0e5)) ?
               (Rib > zero(FT) ? FT(0.01) : FT(-0.01)) : L
    L = reset(isnothing(L_init) ? sign(Rib) * FT(0.01) : L_init)

    for _ in 1:maxiter
        L_old = L
        residual = Rib - _richardson_of(L, z, z0m, z0h, arctic_stable)
        low, high = L - FT(0.001) * L, L + FT(0.001) * L
        slope = (
            -_richardson_of(low, z, z0m, z0h, arctic_stable) +
            _richardson_of(high, z, z0m, z0h, arctic_stable)
        ) / (low - high)
        iszero(slope) && break
        L = reset(L - residual / slope)
        if abs((L - L_old) / L) < tol
            return abs(L) > cap ? sign(L) * cap : L
        end
    end
    error("The Obukhov length did not converge in $maxiter iterations at Rib = $Rib.")
end

"""
    drag_coefficients(L, z, z0m, z0h; arctic_stable, κ) -> (; C_m, C_s)

`C_m = κ²/[ln(z/z0m) − ψ_m(z/L) + ψ_m(z0m/L)]²` and `C_s`, whose denominator is that momentum
logarithm times the matching heat one (`modsurface.f90:858-860`).
"""
function drag_coefficients(
    L::FT, z::FT, z0m::FT, z0h::FT;
    arctic_stable::Bool = SURFACE_LAYER.larcticstab,
    κ::FT = FT(DALES_CONSTANTS.von_karman),
) where {FT}
    momentum = log(z / z0m) - psim(z / L; arctic_stable) + psim(z0m / L; arctic_stable)
    heat = log(z / z0h) - psih(z / L; arctic_stable) + psih(z0h / L; arctic_stable)
    return (; C_m = κ^2 / momentum^2, C_s = κ^2 / (momentum * heat))
end

"""
    surface_layer_fluxes([FT = Float64]; θ_l, q_tot, wind_speed, z, θ_l_skin, q_skin, z0m, z0h, …)

The surface layer of one column, as `(; L, ζ, Rib, C_m, C_s, r_a, ustar, θ_l_flux,
q_tot_flux, θ_l_scale, q_scale)`.

`θ_l_flux` [K m/s] and `q_tot_flux` [kg/kg m/s] are kinematic and upward-positive, as
`modsurface.f90:935-936` forms them: `−(θ_l − θ_l,skin)/r_a` with `r_a = 1/(C_s |U|)` and `|U|`
floored at `wind_floor`. `θ_l_flux` is a **potential**-temperature flux. `q_skin` is reduced by
`f_sal` for salinity, as DALES does.

`θ_l_scale = −θ_l_flux/u*` and `q_scale = −q_tot_flux/u*` are the Monin–Obukhov scales, derived
here rather than carried by DALES. `ζ = z/L` says where the result sits in the Grachev
functions' stated `0 ≤ ζ < 100`; it is reported, never clamped.

This is the domain-mean solve `isurf = 2` with `lmostlocal = false` ran: one `L` for the whole
domain, from the slab-mean level-1 state (`modsurface.f90:1507-1555`).

`FT` is positional because a `where` parameter cannot be bound from keyword arguments; every
state keyword is then checked against it.
"""
function surface_layer_fluxes(
    ::Type{FT} = Float64;
    θ_l::FT,
    q_tot::FT,
    wind_speed::FT,
    z::FT,
    θ_l_skin::FT,
    q_skin::FT,
    z0m::FT,
    z0h::FT,
    f_sal::FT = FT(SURFACE_LAYER.f_sal),
    wind_floor::FT = FT(SURFACE_LAYER.wind_floor),
    arctic_stable::Bool = SURFACE_LAYER.larcticstab,
    backend = DefaultThermodynamicsBackend(),
    κ::FT = FT(DALES_CONSTANTS.von_karman),
    kwargs...,
) where {FT}
    θ_v = surface_virtual_pottemp(backend, θ_l, q_tot)
    θ_v_surface = surface_virtual_pottemp(backend, θ_l_skin, q_skin)
    Rib = bulk_richardson(
        θ_v, θ_v_surface, z, wind_speed; gravity = grav(backend, FT),
    )
    L = obukhov_length(Rib, z, z0m, z0h; arctic_stable, kwargs...)
    (; C_m, C_s) = drag_coefficients(L, z, z0m, z0h; arctic_stable, κ)

    wind = max(wind_speed, wind_floor)
    r_a = one(FT) / (C_s * wind)
    ustar = sqrt(C_m) * wind
    θ_l_flux = -(θ_l - θ_l_skin) / r_a
    q_tot_flux = -(q_tot - q_skin * f_sal) / r_a
    return (;
        L,
        ζ = z / L,
        Rib,
        C_m,
        C_s,
        r_a,
        ustar,
        θ_l_flux,
        q_tot_flux,
        θ_l_scale = -θ_l_flux / ustar,
        q_scale = -q_tot_flux / ustar,
    )
end

"""
    dales_surface_layer(date; root, time_index, backend)

[`surface_layer_fluxes`](@ref) on one archived day: the level-1 slab means of
[`dales_slab_column`](@ref) against the skin of [`testbed_forcing`](@ref), with the roughness
lengths that day ran with.
"""
function dales_surface_layer(
    date;
    root = data_root(),
    time_index::Int = 1,
    backend = DefaultThermodynamicsBackend(),
    kwargs...,
)
    column = dales_slab_column(date, Float64; root, backend)
    forcing = testbed_forcing(date; root)
    ps = Float64(forcing.surface.ps)
    return surface_layer_fluxes(
        Float64;
        θ_l = column.θ_l[1, time_index],
        q_tot = column.q_tot[1, time_index],
        wind_speed = hypot(column.u[1, time_index], column.v[1, time_index]),
        z = column.z[1],
        θ_l_skin = surface_pottemp(Float64(surface_temperature(forcing)), ps; backend),
        q_skin = Float64(qseaicefrctsurf(forcing; backend)),
        z0m = Float64(forcing.surface.z0_momentum),
        z0h = Float64(forcing.surface.z0_heat),
        backend,
        kwargs...,
    )
end
