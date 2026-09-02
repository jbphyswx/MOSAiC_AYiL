# ============================================================================================ #
# Thermodynamics
#
# The pipeline works directly on scalar fields `(T, p, q_tot)` — there is no thermodynamic state
# object. Derived quantities (condensate partition, density, virtual temperature, liquid-ice
# potential temperature) are recomputed on demand from those fields by a set of generic
# functions. The physics comes from a *backend* selected by dispatch on the `thermo_params`
# handle the caller threads through the pipeline:
#
#   * `DefaultThermodynamicsBackend` (defined here) — the physics of the AYiL runs, taken from
#     the DALES source that produced the archive. No external dependency.
#   * a backend added by a package extension, which dispatches these functions on its own
#     parameter set.
#
# Every constant below is DALES's own, cited to the file and line it comes from. DALES holds
# the latent heats *constant*, so no heat capacities of vapour, liquid or ice appear: a caller
# wanting a temperature-dependent latent heat passes `Δcp` to `latent_heat_generic` explicitly

# ============================================================================================ #

"""
    AbstractThermodynamicsBackend

Supertype for the built-in, dependency-free thermodynamics backend. Extension backends dispatch
on their own parameter set and need not subtype this.
"""
abstract type AbstractThermodynamicsBackend end
Base.broadcastable(backend::AbstractThermodynamicsBackend) = tuple(backend)

"""
    DefaultThermodynamicsBackend()

The thermodynamics of the AYiL runs: Murphy–Koop saturation vapour pressure in the interior,
Tetens/Murray at the surface, liquid-only saturation adjustment, and DALES's constants
throughout. An extension backend can be used instead by passing its parameter set as
`thermodynamics_backend`.
"""
struct DefaultThermodynamicsBackend <: AbstractThermodynamicsBackend end

# --- generic methods: declared here, methods added per backend (default below; extension backends add theirs) --
"""Equilibrium condensate partition `(q_liq, q_ice)` from `(T, p, q_tot)`."""
function equilibrium_condensate end
"""Moist air density [kg/m³]."""
function air_density end
"""Virtual temperature [K]."""
function virtual_temperature end
"""Liquid-ice potential temperature [K]."""
function liquid_ice_pottemp end
"""Dry potential temperature [K]."""
function dry_pottemp end
"""Exner function `(p/p_ref)^(R_d/c_p)`."""
function exner end
"""Temperature [K] from the liquid-ice potential temperature and the liquid content."""
function temperature_from_liquid_ice_pottemp end
"""Saturation adjustment from `(p, θ_liq_ice, q_tot)` → `(T, q_liq, q_ice)`."""
function saturation_adjust_pθq end
"""Saturation specific humidity over liquid."""
function q_vap_saturation_liq end
"""Saturation specific humidity over ice."""
function q_vap_saturation_ice end
"""Surface total specific humidity at saturation."""
function saturation_specific_humidity_from_pT end
"""Surface saturation total-water mixing ratio."""
function saturation_mixing_ratio_from_pT end
"""Saturation specific humidity from a saturation vapor pressure and a pressure."""
function q_vap_saturation_from_pressure end
"""Saturation specific humidity."""
function q_vap_saturation end
"""Saturation vapor pressure [Pa] for a phase."""
function saturation_vapor_pressure end
"""Saturation vapor pressure over liquid water [Pa]."""
function saturation_vapor_pressure_liq end
"""Saturation vapor pressure over ice [Pa]."""
function saturation_vapor_pressure_ice end
"""Tetens/Murray saturation vapor pressure [Pa], the form DALES uses at the surface."""
function tetens_saturation_vapor_pressure end
"""Surface saturation specific humidity in DALES's surface convention."""
function surface_q_vap_saturation end
"""Fraction of the condensate that is liquid."""
function liquid_fraction end
"""Dry-air gas constant [J/kg/K]."""
function R_d end
"""Water-vapor gas constant [J/kg/K]."""
function R_v end
"""Gravitational acceleration [m/s^2]."""
function grav end
"""Dry-air isobaric heat capacity [J/kg/K]."""
function cp_d end
"""Ratio of molar masses `M_v/M_d`, equal to `R_d/R_v`."""
function molmass_ratio end
"""Reference pressure for potential temperature [Pa]."""
function p_ref end
"""Freezing/melting temperature [K]."""
function T_freeze end
"""Upper bound of the mixed-phase temperature range [K]; all liquid at and above."""
function T_mixed_high end
"""Lower bound of the mixed-phase temperature range [K]; all ice at and below."""
function T_mixed_low end
"""Latent heat of vaporization [J/kg]."""
function L_v0 end
"""Latent heat of sublimation [J/kg]."""
function L_s0 end
"""Saturation vapor pressure anchor of the Tetens form [Pa]."""
function e_ref end
"""Tetens numerator coefficient over liquid water."""
function a_liquid end
"""Tetens denominator offset over liquid water [K]."""
function b_liquid end
"""Tetens numerator coefficient over ice."""
function a_ice end
"""Tetens denominator offset over ice [K]."""
function b_ice end
"""Latent heat at `T` [J/kg] from its reference value `LH_0` and the heat-capacity difference `Δcp`."""
function latent_heat_generic end
"""Latent heat of vaporization at `T` [J/kg]."""
function latent_heat_vapor end
"""Latent heat of sublimation at `T` [J/kg]."""
function latent_heat_sublim end

abstract type AbstractPhase end
struct Vapor <: AbstractPhase end
struct Liquid <: AbstractPhase end
struct Ice <: AbstractPhase end

# ============================================================================================ #
# Default backend: the physics of the AYiL runs.
#
# Constants are DALES's, from `modglobal.f90:73-101`; the SB3 sublimation latent heat is
# `modmicrodata3.f90:163-164`. They are read from `DALES_CONSTANTS` rather than restated so a
# correction there cannot leave a stale copy here.
# ============================================================================================ #

@inline R_d(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(DALES_CONSTANTS.R_d)
@inline R_v(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(DALES_CONSTANTS.R_v)
@inline cp_d(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(DALES_CONSTANTS.cp_d)
@inline grav(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(DALES_CONSTANTS.grav)
@inline p_ref(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(DALES_CONSTANTS.p_ref)
@inline T_freeze(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(DALES_CONSTANTS.T_melt)
@inline T_mixed_high(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(DALES_CONSTANTS.T_mixed_high)
@inline T_mixed_low(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(DALES_CONSTANTS.T_mixed_low)
@inline L_v0(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(DALES_CONSTANTS.L_v)
@inline L_s0(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(DALES_CONSTANTS.L_s)
@inline e_ref(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(DALES_CONSTANTS.e_s0)

# Tetens/Murray (1967) coefficients, `modglobal.f90:91-93` and the ice pair alongside them.
@inline a_liquid(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(DALES_CONSTANTS.a_liquid)
@inline b_liquid(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(DALES_CONSTANTS.b_liquid)
@inline a_ice(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(DALES_CONSTANTS.a_ice)
@inline b_ice(::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} = FT(DALES_CONSTANTS.b_ice)

"""
    molmass_ratio(backend, FT)

`ε = M_v/M_d`, which DALES writes as `rd/rv` everywhere it appears (`modcape.f90:282`,
`modsurface.f90:1319`). Computed rather than stored so it cannot disagree with the gas
constants; ≈ 0.622, **not** the reciprocal 1.608.
"""
@inline molmass_ratio(b::DefaultThermodynamicsBackend, ::Type{FT} = Float64) where {FT} =
    R_d(b, FT) / R_v(b, FT)

# --- Latent heats ---------------------------------------------------------------------------- #
#
# DALES holds both constant. `latent_heat_generic` is the temperature-dependent form for a
# caller who has a `Δcp` to supply; nothing here supplies one.

@inline latent_heat_generic(b::DefaultThermodynamicsBackend, T::FT, LH_0::FT, Δcp::FT) where {FT} =
    LH_0 + Δcp * (T - T_freeze(b, FT))
@inline latent_heat_vapor(b::DefaultThermodynamicsBackend, T::FT) where {FT} = L_v0(b, FT)
@inline latent_heat_sublim(b::DefaultThermodynamicsBackend, T::FT) where {FT} = L_s0(b, FT)

# --- Saturation vapour pressure ---------------------------------------------------------------- #
#
# Two formulations, because DALES uses two. The interior thermodynamics evaluates Murphy & Koop
# (2005) — `modglobal.f90:348-351` tabulates it on 0.2 K and `modthermodynamics.f90` interpolates
# — while `modsurface.f90` uses Tetens/Murray (1967) at every one of its ten saturation sites.
# They differ by a few tenths of a percent near 273 K and by more in the cold, so which one is
# used where is part of reproducing the archive, not an implementation detail.

"""
    saturation_vapor_pressure_liq(backend, T)

Saturation vapour pressure over liquid water [Pa], Murphy & Koop (2005) eq. 10 — the
formulation DALES tabulates as `esatltab` (`modglobal.f90:348-349`) and uses in the interior.
"""
@inline function saturation_vapor_pressure_liq(::DefaultThermodynamicsBackend, T::FT) where {FT}
    lnT = log(T)
    return exp(
        FT(54.842763) - FT(6763.22) / T - FT(4.21) * lnT + FT(0.000367) * T +
        tanh(FT(0.0415) * (T - FT(218.8))) *
        (FT(53.878) - FT(1331.22) / T - FT(9.44523) * lnT + FT(0.014025) * T),
    )
end

"""
    saturation_vapor_pressure_ice(backend, T)

Saturation vapour pressure over ice [Pa], Murphy & Koop (2005) eq. 7 — DALES's `esatitab`
(`modglobal.f90:351`).
"""
@inline saturation_vapor_pressure_ice(::DefaultThermodynamicsBackend, T::FT) where {FT} = exp(
    FT(9.550426) - FT(5723.265) / T + FT(3.53068) * log(T) - FT(0.00728332) * T,
)

@inline function saturation_vapor_pressure(
    b::DefaultThermodynamicsBackend, T::FT, phase::AbstractPhase = Liquid(),
) where {FT}
    phase === Liquid() && return saturation_vapor_pressure_liq(b, T)
    phase === Ice() && return saturation_vapor_pressure_ice(b, T)
    error("saturation_vapor_pressure: phase must be Liquid() or Ice(), got $phase")
end

"""
    tetens_saturation_vapor_pressure(backend, T, phase)

Tetens/Murray (1967) saturation vapour pressure [Pa],
`e_s0 exp(a (T − T_melt) / (T − b))`, with DALES's coefficients (`modglobal.f90:91-93` for
liquid, the ice pair alongside them).

This is the form `modsurface.f90` uses — the surface fluxes and the two-skin blend are built
from it, not from [`saturation_vapor_pressure_liq`](@ref).
"""
@inline function tetens_saturation_vapor_pressure(
    b::DefaultThermodynamicsBackend, T::FT, phase::AbstractPhase = Liquid();
    T_melt::FT = T_freeze(b, FT), e_s0::FT = e_ref(b, FT),
) where {FT}
    a, c = if phase === Liquid()
        FT(a_liquid(b)), FT(b_liquid(b))
    elseif phase === Ice()
        FT(a_ice(b)), FT(b_ice(b))
    else
        error("tetens_saturation_vapor_pressure: phase must be Liquid() or Ice(), got $phase")
    end
    return e_s0 * exp(a * (T - T_melt) / (T - c))
end

# --- Saturation specific humidity ------------------------------------------------------------- #
#
# DALES uses two conventions, in two places, and they are not interchangeable.

"""
    q_vap_saturation_from_pressure(backend, e_sat, p)

Saturation specific humidity `ε e / (p − (1−ε) e)` — the interior convention
(`modcape.f90:282`, `modthermodynamics.f90`).

At low pressure `e_sat` can approach `p`, driving the denominator to zero or below; the air is
then unsaturatable and `1` is returned, so no condensate forms for any `q ≤ 1`.
"""
@inline function q_vap_saturation_from_pressure(
    b::DefaultThermodynamicsBackend, e_sat::FT, p::FT; ε::FT = molmass_ratio(b, FT),
) where {FT}
    denom = p - (one(FT) - ε) * e_sat
    return denom > zero(FT) ? ε * e_sat / denom : one(FT)
end

"""
    surface_q_vap_saturation(backend, e_sat, p_s)

Saturation specific humidity `ε e / p_s` — the **surface** convention
(`modsurface.f90:1304-1319`), which drops the `(1−ε)e` term the interior keeps.
"""
@inline surface_q_vap_saturation(
    b::DefaultThermodynamicsBackend, e_sat::FT, p_s::FT; ε::FT = molmass_ratio(b, FT),
) where {FT} = ε * e_sat / p_s

@inline q_vap_saturation_liq(b::DefaultThermodynamicsBackend, T::FT, p::FT; ε::FT = molmass_ratio(b, FT)) where {FT} =
    q_vap_saturation_from_pressure(b, saturation_vapor_pressure_liq(b, T), p; ε)

@inline q_vap_saturation_ice(b::DefaultThermodynamicsBackend, T::FT, p::FT; ε::FT = molmass_ratio(b, FT)) where {FT} =
    q_vap_saturation_from_pressure(b, saturation_vapor_pressure_ice(b, T), p; ε)

@inline q_vap_saturation(
    b::DefaultThermodynamicsBackend, T::FT, p::FT, phase::AbstractPhase; ε::FT = molmass_ratio(b, FT),
) where {FT} = q_vap_saturation_from_pressure(b, saturation_vapor_pressure(b, T, phase), p; ε)

"""
    liquid_fraction(backend, T)

`clamp((T − T_mixed_low) / (T_mixed_high − T_mixed_low), 0, 1)` — DALES's `ilratio`, over the
253–268 K mixed-phase range of `modglobal.f90:79-80`.

Note that the SB3 branch DALES ran computes this and then does **not** use it for the
saturation adjustment: `modthermodynamics.f90` `icethermo0` comments out the blended
`ilratio*qvsl + (1−ilratio)*qvsi` and takes `qsatur = qvsl`. See
[`saturation_adjust_pθq`](@ref).
"""
@inline function liquid_fraction(
    b::DefaultThermodynamicsBackend, T::FT;
    T_low::FT = T_mixed_low(b, FT), T_high::FT = T_mixed_high(b, FT),
) where {FT}
    return clamp((T - T_low) / (T_high - T_low), zero(FT), one(FT))
end

"""
    q_vap_saturation(backend, T, p)

Phase-blended saturation specific humidity, liquid and ice weighted by
[`liquid_fraction`](@ref). This is the *general* mixed-phase form; the archive's own
adjustment is liquid-only.
"""
@inline function q_vap_saturation(
    b::DefaultThermodynamicsBackend, T::FT, p::FT;
    ε::FT = molmass_ratio(b, FT), λ::FT = liquid_fraction(b, T),
) where {FT}
    qvsl = q_vap_saturation_liq(b, T, p; ε)
    qvsi = q_vap_saturation_ice(b, T, p; ε)
    return λ * qvsl + (one(FT) - λ) * qvsi
end

"""
    equilibrium_condensate(backend, T, p, q_tot; λ) -> (; q_liq, q_ice)

Condensate above saturation, partitioned by [`liquid_fraction`](@ref).

`λ = 1` reproduces the archive: saturation is taken over liquid alone and all
condensate in sat adjust is liquid (ice is present separately), as `icethermo0` does under SB3.
"""
@inline function equilibrium_condensate(
    b::DefaultThermodynamicsBackend, T::FT, p::FT, q_tot::FT;
    ε::FT = molmass_ratio(b, FT), λ::FT = liquid_fraction(b, T),
) where {FT}
    λ  = isnan(λ) ? liquid_fraction(b, T) : λ
    q_c = max(zero(FT), q_tot - q_vap_saturation(b, T, p; ε, λ))
    return (; q_liq = λ * q_c, q_ice = (one(FT) - λ) * q_c)
end

# --- Potential temperatures and the state ------------------------------------------------------ #

"""
    exner(backend, p)

`(p / p_ref)^(R_d/c_p)`, DALES's Exner function.
"""
@inline exner(b::DefaultThermodynamicsBackend, p::FT; p_ref::FT = p_ref(b, FT)) where {FT} =
    (p / p_ref)^(R_d(b, FT) / cp_d(b, FT))

@inline dry_pottemp(b::DefaultThermodynamicsBackend, T::FT, p::FT) where {FT} =
    T / exner(b, p)

"""
    liquid_ice_pottemp(backend, T, p, q_liq)

`θ_l = (T − (L_v/c_p) q_l) / Π` — DALES's liquid-only θ_l (`modtestbed.f90:701-702`; the
ice-inclusive variant at `:712-714` is commented out).
"""
@inline liquid_ice_pottemp(b::DefaultThermodynamicsBackend, T::FT, p::FT, q_liq::FT) where {FT} =
    (T - (L_v0(b, FT) / cp_d(b, FT)) * q_liq) / exner(b, p)

"""
    temperature_from_liquid_ice_pottemp(backend, θ_l, p, q_liq)

The inverse of [`liquid_ice_pottemp`](@ref): `T = Π θ_l + (L_v/c_p) q_l`.
"""
@inline temperature_from_liquid_ice_pottemp(
    b::DefaultThermodynamicsBackend, θ_l::FT, p::FT, q_liq::FT,
) where {FT} = exner(b, p) * θ_l + (L_v0(b, FT) / cp_d(b, FT)) * q_liq

@inline function virtual_temperature(
    b::DefaultThermodynamicsBackend, T::FT, q_tot::FT, q_liq::FT, q_ice::FT;
    ε::FT = molmass_ratio(b, FT),
) where {FT}
    q_vap = q_tot - q_liq - q_ice
    return T * (one(FT) + (one(FT) / ε - one(FT)) * q_vap - q_liq - q_ice)
end

@inline function virtual_temperature(
    b::DefaultThermodynamicsBackend, T::FT, p::FT, q_tot::FT; kwargs...,
) where {FT}
    (; q_liq, q_ice) = equilibrium_condensate(b, T, p, q_tot; kwargs...)
    return virtual_temperature(b, T, q_tot, q_liq, q_ice)
end

@inline air_density(
    b::DefaultThermodynamicsBackend, T::FT, p::FT, q_tot::FT, q_liq::FT, q_ice::FT,
) where {FT} = p / (R_d(b, FT) * virtual_temperature(b, T, q_tot, q_liq, q_ice))

@inline function air_density(b::DefaultThermodynamicsBackend, T::FT, p::FT, q_tot::FT; kwargs...) where {FT}
    (; q_liq, q_ice) = equilibrium_condensate(b, T, p, q_tot; kwargs...)
    return air_density(b, T, p, q_tot, q_liq, q_ice)
end

"""
    saturation_adjust_pθq(backend, p, θ_liq_ice, q_tot; λ, maxiter, tol, probe)

`(T, q_liq, q_ice)` consistent with `(p, θ_l, q_tot)`.

Newton iteration on `T` from `T = Π θ_l`, with `dθ_l/dT` taken as a difference over `probe`
as `icethermo0` does (`modthermodynamics.f90:510-565`); an analytic `1/Π` omits the latent
heat released by the condensate it is solving for and overshoots. The first guess is the
answer outright when it is unsaturated, which is the branch at `:580-585`.

`λ = 1` is what the archive ran: saturation over liquid alone and all adjustment condensate
liquid, ice being carried separately (`qsatur = qvsl1`, `:506`). DALES stops at 2e-3 K in
`T`; `tol` here is tighter, on the same equations.
"""
function saturation_adjust_pθq(
    b::DefaultThermodynamicsBackend, p::FT, θ_liq_ice::FT, q_tot::FT;
    λ::FT = FT(1), maxiter::Int = 100, tol::FT = FT(1e-6), probe::FT = FT(2e-3),
) where {FT}
    ε = molmass_ratio(b, FT)
    condensate(t) =
        let (; q_liq, q_ice) = equilibrium_condensate(b, t, p, q_tot; ε, λ)
            q_liq + q_ice
        end
    θ_of(t) = liquid_ice_pottemp(b, t, p, condensate(t))

    T = exner(b, p) * θ_liq_ice
    if condensate(T) > zero(FT)
        T_old = T + 2 * tol
        iter = 0
        while abs(T - T_old) > tol && iter < maxiter
            iter += 1
            T_old = T
            slope = (θ_of(T) - θ_of(T - probe)) / probe
            slope == zero(FT) && break
            T -= (θ_of(T) - θ_liq_ice) / slope
        end
    end
    (; q_liq, q_ice) = equilibrium_condensate(b, T, p, q_tot; ε, λ)
    return (; T, q_liq, q_ice)
end

# --- Surface ----------------------------------------------------------------------------------- #

"""
    saturation_specific_humidity_from_pT(backend, p_s, T, phase)

Surface saturation specific humidity, `ε e_sat / p_s` with the **Tetens** vapour pressure —
both conventions as `modsurface.f90` uses them.
"""
@inline saturation_specific_humidity_from_pT(
    b::DefaultThermodynamicsBackend, p_s::FT, T::FT, phase::AbstractPhase = Liquid(),
) where {FT} = surface_q_vap_saturation(b, tetens_saturation_vapor_pressure(b, T, phase), p_s)

"""
    saturation_mixing_ratio_from_pT(backend, p, T, phase)

Saturation *mixing ratio* `ε e_sat / (p − e_sat)` from the Tetens vapour pressure — mass of
vapour per mass of dry air, unlike the specific humidities elsewhere here.
"""
@inline function saturation_mixing_ratio_from_pT(
    b::DefaultThermodynamicsBackend, p::FT, T::FT, phase::AbstractPhase = Liquid();
    ε::FT = molmass_ratio(b, FT),
) where {FT}
    e_sat = tetens_saturation_vapor_pressure(b, T, phase)
    return ε * e_sat / (p - e_sat)
end