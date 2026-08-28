"""
    dales.jl

DALES's own constants, for reconstructing quantities it produced.

These exist separately from any ClimaParams override because the readers
reconstruct DALES-derived quantities — its `ω → w` conversion, its θ_l — and must
do so with the values DALES used whether or not a caller layered that config.
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

"""
Thermodynamic constants of the reference DALES runs, offered as ClimaParams
override entries. Every DALES constant with a counterpart is here, including those
whose values coincide with today's ClimaParams defaults.

`Thermodynamics` maps `gas_constant_dry_air` / `isobaric_specific_heat_dry_air`;
RRTMGP reads `molar_mass_*` / `adiabatic_exponent_dry_air`. Both pairs are set
and kept consistent.

Two differences no parameter can remove: DALES holds `L_v` constant where
Thermodynamics uses `L_v(T)`, so matching at `T_0` leaves CliMA 1.2% high at 260 K,
2.1% at 250 K and 4.0% at 230 K; and DALES's saturation vapour pressure is
Tetens/Murray rather than Clausius–Clapeyron.
"""
const DALES_THERMODYNAMICS = (;
    gas_constant_dry_air = (
        value = 287.04,
        description = "DALES `rd`; ClimaParams default 287.0 (+0.014%)",
    ),
    gas_constant_vapor = (
        value = 461.5,
        description = "DALES `rv`; equals the ClimaParams default, set so it cannot drift",
    ),
    isobaric_specific_heat_dry_air = (
        value = 1004.0,
        description = "DALES `cp`; ClimaParams default 1004.5 (-0.050%)",
    ),
    latent_heat_vaporization_at_reference = (
        value = 2.53e6,
        description = "DALES `rlv`; ClimaParams default 2.5008e6 (+1.168%)",
    ),
    latent_heat_sublimation_at_reference = (
        value = 2.834e6,
        description = "DALES SB3 `rlvi`, the value its microphysics used; `riv = 2.84e6` \
                       in modglobal is declared but never referenced. ClimaParams default \
                       2.8344e6 (-0.014%)",
    ),
    temperature_water_freeze = (
        value = 273.16,
        description = "DALES `tmelt`; ClimaParams default 273.15",
    ),
    potential_temperature_reference_pressure = (
        value = 1.0e5,
        description = "DALES `pref0`, the reference pressure of its Exner function; \
                       equals the ClimaParams default, set so it cannot drift",
    ),
    gravitational_acceleration = (
        value = 9.81,
        description = "DALES `grav`; equals the ClimaParams default, set so it cannot \
                       drift",
    ),
    molar_mass_dry_air = (
        value = 0.028966206103678928,
        description = "gas_constant / 287.04, so the molar mass matches \
                       `gas_constant_dry_air`",
    ),
    molar_mass_water = (
        value = 0.018016164247020586,
        description = "gas_constant / 461.5, so the molar mass matches \
                       `gas_constant_vapor`",
    ),
    adiabatic_exponent_dry_air = (
        value = 0.28589641434262952,
        description = "287.04 / 1004, matching `gas_constant_dry_air` / \
                       `isobaric_specific_heat_dry_air`",
    ),
    von_karman_constant = (
        value = 0.4,
        description = "DALES `fkar`, used by its Monin-Obukhov surface layer; equals the \
                       ClimaParams default, set so it cannot drift",
    ),
    stefan_boltzmann_constant = (
        value = 5.67e-8,
        description = "DALES `boltz`; equals the ClimaParams default, set so it cannot \
                       drift",
    ),
    density_liquid_water = (
        value = 998.0,
        description = "DALES `rhow`; ClimaParams default 1000 (-0.2%)",
    ),
)

"""
    parameter_overrides(set = DALES_THERMODYNAMICS)

`set` in the `ClimaParams` override form, carrying each entry's description.
"""
parameter_overrides(set = DALES_THERMODYNAMICS) = Dict{String, Any}(
    String(name) => Dict{String, Any}(
        "value" => entry.value,
        "type" => "float",
        "description" => entry.description,
    ) for (name, entry) in pairs(set)
)

"""
    dales_exner(p)

DALES's Exner function, `(p / p_ref)^(R_d/c_p)` with its own constants.
"""
dales_exner(p) =
    (p / oftype(float(p), DALES_CONSTANTS.p_ref))^oftype(
        float(p),
        DALES_CONSTANTS.R_d / DALES_CONSTANTS.cp_d,
    )

"""
    dales_presf(p_face, ρ, z_center, z_face)

Cell-centre pressure [Pa], which the archive does not carry, as one hydrostatic
step up from the face below.

`profiles.001.nc`'s `presh` is DALES's **half**-level pressure. Using it as a
centre pressure is a half-cell error worth 1.5 % in pressure and 0.91 K in a
temperature formed from it.
"""
dales_presf(p_face, ρ, z_center, z_face) =
    @. p_face - ρ * DALES_CONSTANTS.grav * (z_center - z_face)

"""
    dales_temperature(θ_l, q_l, p_face, ρ, z_center, z_face)

Slab-mean temperature [K], `θ_l Π + (L_v/c_p) q_l` on [`dales_presf`](@ref).

`q_l` and not the SB3 cloud-liquid scalar `sv005`: the thermodynamic liquid DALES's
saturation adjustment produced is what its θ_l carries.
"""
dales_temperature(θ_l, q_l, p_face, ρ, z_center, z_face) =
    @. dales_exner(dales_presf(p_face, ρ, z_center, z_face)) * θ_l +
       (DALES_CONSTANTS.L_v / DALES_CONSTANTS.cp_d) * q_l
