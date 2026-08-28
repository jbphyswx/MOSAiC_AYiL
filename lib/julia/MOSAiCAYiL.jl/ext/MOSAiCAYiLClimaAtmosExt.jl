"""
    MOSAiCAYiLClimaAtmosExt

Loads when `ClimaAtmos` is available. Owns the AYiL forcing, setup, insolation,
Coriolis profiles, parameter overrides, and column grid — methods on types this
package defines. Does not assemble an `AtmosModel` or call `solve_atmos!`.
"""
module MOSAiCAYiLClimaAtmosExt

using ClimaAtmos: ClimaAtmos
using Dates: Dates
using MOSAiCAYiL: MOSAiCAYiL

const CC = ClimaAtmos.CC
const TD = ClimaAtmos.TD
const Insolation = ClimaAtmos.Insolation
const Intp = ClimaAtmos.Intp
const lazy = ClimaAtmos.lazy
const CP = ClimaAtmos.CP

MOSAiCAYiL.climaatmos_pkg_version() = Base.pkgversion(ClimaAtmos)

# Linear in height, flat outside the data — the interpolation `ColumnProfiles` and
# `interp_vertical_prof` use, as a scalar callable of `z`.
_column_profile(z, values) = Intp.extrapolate(
    Intp.interpolate((z,), values, Intp.Gridded(Intp.Linear())),
    Intp.Flat(),
)

# --- Parameters ------------------------------------------------------------- #

"""
    ClimaAtmos_MOSAiCAYiL_toml_overrides()
    ClimaAtmos_MOSAiCAYiL_toml_overrides(case; ccn, params)

ClimaParams override dict: [`MOSAiCAYiL.DALES_THERMODYNAMICS`](@ref), then the day's
CCN number when a case is given. `params` is a further dict that wins.
"""
MOSAiCAYiL.ClimaAtmos_MOSAiCAYiL_toml_overrides() =
    MOSAiCAYiL.parameter_overrides()

function MOSAiCAYiL.ClimaAtmos_MOSAiCAYiL_toml_overrides(
    c::MOSAiCAYiL.MOSAiCAYiLCase;
    ccn::Real = MOSAiCAYiL.n_ccn(c),
    params = nothing,
)
    overrides = MOSAiCAYiL.parameter_overrides()
    overrides["prescribed_cloud_droplet_number_concentration"] =
        Dict{String, Any}("value" => Float64(ccn), "type" => "float")
    if !isnothing(params)
        for (name, entry) in params
            overrides[string(name)] = entry
        end
    end
    return overrides
end

function MOSAiCAYiL.ClimaAtmos_MOSAiCAYiL_params(
    ::Type{FT},
    c::MOSAiCAYiL.MOSAiCAYiLCase;
    microphysics_model = ClimaAtmos.NonEquilibriumMicrophysics1M(),
    kwargs...,
) where {FT <: AbstractFloat}
    toml = CP.create_toml_dict(
        FT;
        override_file = MOSAiCAYiL.ClimaAtmos_MOSAiCAYiL_toml_overrides(
            c;
            kwargs...,
        ),
    )
    return ClimaAtmos.ClimaAtmosParameters(toml; microphysics_model)
end

MOSAiCAYiL.ClimaAtmos_MOSAiCAYiL_callback_kwargs(; kwargs...) =
    (; dt_rad = "10mins", kwargs...)

# --- Forcing ---------------------------------------------------------------- #

"""
    ClimaAtmosMOSAiCAYiLForcing

Large-scale forcing for one AYiL day: relaxation of temperature, total water and
horizontal wind toward the ERA5 testbed profiles above a diagnosed inversion,
horizontal advection of heat, moisture and momentum, and large-scale subsidence.

The profiles have no time axis. Each `scm_in` file is a 05:00–11:00 UTC composite
written twice with bitwise-identical records, so the cache samples once. Forcing
at `t = 0` is applied; it is not skipped.
"""
struct ClimaAtmosMOSAiCAYiLForcing{FT, V <: AbstractVector{FT}}
    z::V
    ta::V
    hus::V
    ua::V
    va::V
    wa::V
    dTdt_hadv::V
    dqtdt_hadv::V
    dudt_hadv::V
    dvdt_hadv::V
    inv_τ::FT
    ramp_depth::FT
    z_inv_min::FT
    z_inv_max::FT
    q_tot_threshold::FT
end

function MOSAiCAYiL.ClimaAtmosMOSAiCAYiLForcing(
    ::Type{FT},
    c::MOSAiCAYiL.MOSAiCAYiLCase;
    root = MOSAiCAYiL.data_root(),
    time_index::Int = 1,
    forcing = MOSAiCAYiL.read_scm_in(c; root, time_index),
    nudging = MOSAiCAYiL.nudging_parameters(c),
    z_inv_min::Real = MOSAiCAYiL.INVERSION_SEARCH_MIN,
    z_inv_max::Real = MOSAiCAYiL.INVERSION_SEARCH_MAX,
    q_tot_threshold::Real = MOSAiCAYiL.DRY_AIR_NUDGE_THRESHOLD,
) where {FT <: AbstractFloat}
    # A positive onset height would be DALES's fixed-ramp mode, which this term
    # does not implement; it would be silently ignored rather than honoured.
    nudging.z_min < 0 || error(
        "`nudging.z_min = $(nudging.z_min)` asks for a fixed nudging onset \
         height. Only the diagnosed-inversion mode is implemented.",
    )

    f = forcing
    v(x) = collect(FT, x)
    return ClimaAtmosMOSAiCAYiLForcing{FT, Vector{FT}}(
        v(f.z),
        v(f.ta),
        v(f.hus),
        v(f.ua),
        v(f.va),
        v(f.wa),
        v(f.tntha),
        v(f.tnhusha),
        v(f.tnua),
        v(f.tnva),
        FT(1 / nudging.timescale),
        FT(nudging.ramp_depth),
        FT(z_inv_min),
        FT(z_inv_max),
        FT(q_tot_threshold),
    )
end

# A ClimaCore broadcast is pointwise over the space and never exposes the level
# index, so a sampled profile is written level by level. The guard requires one
# level per value and one column: for a wider geometry `length(field)` exceeds the
# level count, and writing one column's profile into a flat index would be wrong.
function _fill_column!(field, values)
    n = length(values)
    (CC.Spaces.nlevels(axes(field)) == n && length(field) == n) || error(
        "The MOSAiC forcing fills a single column of $n levels; got a field with \
         $(CC.Spaces.nlevels(axes(field))) levels and $(length(field)) points.",
    )
    FT = eltype(field)
    @inbounds for k in 1:n
        field[k] = FT(values[k])
    end
    return nothing
end

function ClimaAtmos.external_forcing_cache(
    Y,
    forcing::ClimaAtmosMOSAiCAYiLForcing,
    params,
    start_date,
)
    FT = CC.Spaces.undertype(axes(Y.c))
    z = vec(Array(parent(CC.Fields.coordinate_field(Y.c).z)))
    sampled(values) = begin
        field = similar(Y.c, FT)
        _fill_column!(field, ClimaAtmos.interp_vertical_prof(z, forcing.z, values))
        field
    end
    thermo = ClimaAtmos.Parameters.thermodynamics_params(params)
    return (;
        z = collect(FT, z),
        Lv_over_cp = FT(
            TD.Parameters.LH_v0(thermo) / TD.Parameters.cp_d(thermo),
        ),
        Rd_over_cp = FT(TD.Parameters.R_d(thermo) / TD.Parameters.cp_d(thermo)),
        p_ref = FT(TD.Parameters.p_ref_theta(thermo)),
        ᶜT_nudge = sampled(forcing.ta),
        ᶜqt_nudge = sampled(forcing.hus),
        ᶜu_nudge = sampled(forcing.ua),
        ᶜv_nudge = sampled(forcing.va),
        ᶜls_subsidence = sampled(forcing.wa),
        ᶜdTdt_hadv = sampled(forcing.dTdt_hadv),
        ᶜdqtdt_hadv = sampled(forcing.dqtdt_hadv),
        ᶜdudt_hadv = sampled(forcing.dudt_hadv),
        ᶜdvdt_hadv = sampled(forcing.dvdt_hadv),
        ᶜθ_l = similar(Y.c, FT),
        ᶜinv_τ = similar(Y.c, FT),
        ᶜinv_τ_q = similar(Y.c, FT),
    )
end

function ClimaAtmos.external_forcing_tendency!(
    Yₜ,
    Y,
    p,
    t,
    forcing::ClimaAtmosMOSAiCAYiLForcing,
)
    (;
        z,
        ᶜT_nudge,
        ᶜqt_nudge,
        ᶜu_nudge,
        ᶜv_nudge,
        ᶜls_subsidence,
        ᶜdTdt_hadv,
        ᶜdqtdt_hadv,
        ᶜdudt_hadv,
        ᶜdvdt_hadv,
        ᶜθ_l,
        ᶜinv_τ,
        ᶜinv_τ_q,
    ) = p.external_forcing
    (; ᶜT, ᶜp, ᶜq_liq) = p.precomputed
    FT = eltype(ᶜθ_l)
    thermo = ClimaAtmos.Parameters.thermodynamics_params(p.params)
    cp_d = TD.Parameters.cp_d(thermo)
    L_v = TD.Parameters.LH_v0(thermo)
    R_d = TD.Parameters.R_d(thermo)
    p_ref = TD.Parameters.p_ref_theta(thermo)

    @. ᶜθ_l = (ᶜT - FT(L_v / cp_d) * ᶜq_liq) * (FT(p_ref) / ᶜp)^FT(R_d / cp_d)
    z_inv = MOSAiCAYiL.inversion_height(
        ᶜθ_l,
        z,
        forcing.z_inv_min,
        forcing.z_inv_max,
    )
    z_mid = z_inv + forcing.ramp_depth

    # DALES never relaxes faster than one timestep, and relaxes moisture *at* the
    # timestep where the column is drier than the threshold.
    inv_τ = min(forcing.inv_τ, inv(p.dt))
    inv_τ_dry = inv(p.dt)
    ᶜz = CC.Fields.coordinate_field(axes(Y.c)).z
    ᶜq_tot = @. lazy(Y.c.ρq_tot / Y.c.ρ)
    @. ᶜinv_τ = MOSAiCAYiL.nudge_ramp(ᶜz, z_inv, z_mid) * inv_τ
    @. ᶜinv_τ_q =
        MOSAiCAYiL.nudge_ramp(ᶜz, z_inv, z_mid) *
        ifelse(ᶜq_tot < forcing.q_tot_threshold, inv_τ_dry, inv_τ)

    ClimaAtmos.nudge_uv!(Yₜ, Y, p, ᶜu_nudge, ᶜv_nudge, ᶜinv_τ)

    ᶜlg = CC.Fields.local_geometry_field(Y.c)
    ᶜuₕ_hadv = p.scratch.ᶜtemp_C12
    @. ᶜuₕ_hadv = ClimaAtmos.C12(CC.Geometry.UVVector(ᶜdudt_hadv, ᶜdvdt_hadv), ᶜlg)
    @. Yₜ.c.uₕ += ᶜuₕ_hadv

    ᶜdTdt = p.scratch.ᶜtemp_scalar
    ᶜdqtdt = p.scratch.ᶜtemp_scalar_2
    @. ᶜdTdt = -(ᶜT - ᶜT_nudge) * ᶜinv_τ + ᶜdTdt_hadv
    @. ᶜdqtdt = -(ᶜq_tot - ᶜqt_nudge) * ᶜinv_τ_q + ᶜdqtdt_hadv
    ClimaAtmos.apply_Tq_forcing!(Yₜ, Y, p, ᶜdTdt, ᶜdqtdt)

    ClimaAtmos.apply_subsidence_forcing!(Yₜ, Y, p, ᶜls_subsidence)
    return nothing
end

"""
    mosaic_scm_coriolis(FT, case; params, kwargs...)

ClimaAtmos `scm_coriolis` for one AYiL day: geostrophic wind from `scm_in` and
the Coriolis parameter at the day's drift position. Together with Coriolis this
is `-f × (u - u_g)`.
"""
function MOSAiCAYiL.mosaic_scm_coriolis(
    ::Type{FT},
    c::MOSAiCAYiL.MOSAiCAYiLCase;
    params,
    root = MOSAiCAYiL.data_root(),
    time_index::Int = 1,
    forcing = MOSAiCAYiL.read_scm_in(c; root, time_index),
    latitude::Real = MOSAiCAYiL.latitude(c),
    omega = ClimaAtmos.Parameters.Omega(params),
) where {FT <: AbstractFloat}
    z = collect(FT, forcing.z)
    return (;
        prof_ug = _column_profile(z, collect(FT, forcing.ug)),
        prof_vg = _column_profile(z, collect(FT, forcing.vg)),
        coriolis_param = FT(2 * omega * sind(latitude)),
    )
end

# --- Grid ------------------------------------------------------------------- #

"""
    mosaic_grid(FT; faces = LES_FACES, kwargs...)

A ClimaAtmos `ColumnGrid` from a face vector. The faces *are* the specification:
compose [`MOSAiCAYiL.truncate_faces_to_top`](@ref) and
[`MOSAiCAYiL.coarsen_faces_to_dz_min`](@ref) before passing `faces`. There is no
parallel `z_top` / `dz_min` keyword, and no per-day grid.
"""
function MOSAiCAYiL.mosaic_grid(
    ::Type{FT};
    faces::AbstractVector = MOSAiCAYiL.LES_FACES,
    kwargs...,
) where {FT <: AbstractFloat}
    zf = collect(FT, faces)
    issorted(zf) || error(
        "Cell faces must be increasing; got $(length(zf)) faces spanning \
         $(extrema(zf)) m.",
    )
    domain = CC.Domains.IntervalDomain(
        CC.Geometry.ZPoint(first(zf)),
        CC.Geometry.ZPoint(last(zf));
        boundary_names = (:bottom, :top),
    )
    z_mesh = CC.Meshes.IntervalMesh(domain, CC.Geometry.ZPoint.(zf))
    return ClimaAtmos.ColumnGrid(
        FT;
        z_elem = length(zf) - 1,
        z_max = last(zf),
        z_mesh,
        kwargs...,
    )
end

"""Centre-level heights [m] of `grid`, ascending."""
MOSAiCAYiL.mosaic_z(grid) = vec(
    Array(
        parent(
            CC.Fields.coordinate_field(
                ClimaAtmos.get_spaces(grid).center_space,
            ).z,
        ),
    ),
)

# --- Insolation ------------------------------------------------------------- #

"""
    MOSAiCInsolation{FT}(cos_zenith, toa_flux)

Insolation held at a fixed zenith angle, as the reference runs did
(`lcnstzenithtime = .true.`, `cnstzenithtime = 11` on all 190 days).

`toa_flux` is Insolation.jl's `S` (beam-normal), which ClimaAtmos 0.42 writes to
`RRTMGP.toa_sw_flux_dn` the same way `TimeVaryingInsolation` does. Polar night is
`(eps(FT), 0)`: no incoming flux, with the positive zenith cosine RRTMGP requires.
"""
struct MOSAiCInsolation{FT} <: ClimaAtmos.AbstractInsolation
    cos_zenith::FT
    toa_flux::FT
end

function MOSAiCAYiL.MOSAiCInsolation(
    ::Type{FT},
    c::MOSAiCAYiL.MOSAiCAYiLCase;
    reference_time::Dates.DateTime = MOSAiCAYiL.reference_datetime(c),
    latitude::Real = MOSAiCAYiL.latitude(c),
    longitude::Real = MOSAiCAYiL.longitude(c),
    insolation_params = Insolation.Parameters.InsolationParameters(FT),
) where {FT <: AbstractFloat}
    (; S, μ) =
        Insolation.insolation(reference_time, latitude, longitude, insolation_params)
    return μ > 0 ? MOSAiCInsolation{FT}(FT(μ), FT(S)) :
           MOSAiCInsolation{FT}(eps(FT), zero(FT))
end

function ClimaAtmos.set_insolation_variables!(
    Y,
    p,
    t,
    insolation::MOSAiCInsolation,
)
    (; rrtmgp_solver) = p.radiation
    ClimaAtmos.RRTMGP.cos_zenith(rrtmgp_solver) .= insolation.cos_zenith
    ClimaAtmos.RRTMGP.toa_sw_flux_dn(rrtmgp_solver) .= insolation.toa_flux
    return nothing
end

# --- Setup ------------------------------------------------------------------ #

"""
    ClimaAtmosMOSAiCAYiLSetup

Initial state of one AYiL day, plus the forcing, insolation, and surface values
needed to pass the setup to `ClimaAtmos.AtmosSimulation`.

The default density is [`MOSAiCAYiL.scm_in_air_density`](@ref) (design.md §8),
not [`MOSAiCAYiL.les_density`](@ref). Pass `density = les_density(date)` to use
the archive's `rhof` at t = 300 s instead. Never `rhobf`.
"""
struct ClimaAtmosMOSAiCAYiLSetup{P, F, I, FT}
    profiles::P
    forcing::F
    insolation::I
    T_sfc::FT
    z0::FT
    albedo::FT
end

function MOSAiCAYiL.ClimaAtmosMOSAiCAYiLSetup(
    ::Type{FT},
    c::MOSAiCAYiL.MOSAiCAYiLCase;
    root = MOSAiCAYiL.data_root(),
    time_index::Int = 1,
    forcing_data = MOSAiCAYiL.read_scm_in(c; root, time_index),
    density = MOSAiCAYiL.scm_in_air_density(forcing_data),
    tke = MOSAiCAYiL.dales_tke_seed,
    insolation = MOSAiCAYiL.MOSAiCInsolation(FT, c),
    external_forcing = MOSAiCAYiL.ClimaAtmosMOSAiCAYiLForcing(
        FT,
        c;
        root,
        time_index,
        forcing = forcing_data,
    ),
    T_sfc::Real = MOSAiCAYiL.surface_temperature(forcing_data),
    z0::Real = forcing_data.surface.z0_momentum,
    albedo::Real = forcing_data.surface.albedo,
) where {FT <: AbstractFloat}
    z_scm = collect(FT, forcing_data.z)
    from_scm(values) = _column_profile(z_scm, collect(FT, values))
    z_ρ, ρ = density
    return ClimaAtmosMOSAiCAYiLSetup(
        (;
            T = from_scm(forcing_data.ta),
            u = from_scm(forcing_data.ua),
            v = from_scm(forcing_data.va),
            q_tot = from_scm(forcing_data.hus),
            q_ice = from_scm(forcing_data.qi),
            ρ = _column_profile(collect(FT, z_ρ), collect(FT, ρ)),
            tke,
        ),
        external_forcing,
        insolation,
        FT(T_sfc),
        FT(z0),
        FT(albedo),
    )
end

function ClimaAtmos.Setups.center_initial_condition(
    setup::ClimaAtmosMOSAiCAYiLSetup,
    local_geometry,
    params,
)
    (; z) = local_geometry.coordinates
    FT = typeof(z)
    p = setup.profiles
    T = FT(p.T(z))
    ρ = FT(p.ρ(z))
    q_tot = FT(p.q_tot(z))
    q_ice = FT(p.q_ice(z))
    thermo = ClimaAtmos.Parameters.thermodynamics_params(params)
    q_sat_liq = FT(TD.q_vap_saturation(thermo, T, ρ, TD.Liquid()))
    return ClimaAtmos.Setups.physical_state(;
        T,
        ρ,
        q_tot,
        q_liq = max(zero(FT), (q_tot - q_ice) - q_sat_liq),
        q_ice,
        u = FT(p.u(z)),
        v = FT(p.v(z)),
        tke = FT(p.tke(z)),
    )
end

ClimaAtmos.Setups.external_forcing(
    setup::ClimaAtmosMOSAiCAYiLSetup,
    ::Type{FT},
) where {FT} = setup.forcing

ClimaAtmos.Setups.insolation_model(setup::ClimaAtmosMOSAiCAYiLSetup) =
    setup.insolation

function ClimaAtmos.Setups.surface_condition(
    setup::ClimaAtmosMOSAiCAYiLSetup,
    params,
)
    FT = eltype(params)
    return (;
        flux_scheme = ClimaAtmos.Setups.MoninObukhov(; z0 = FT(setup.z0)),
        temperature = ClimaAtmos.Setups.AnalyticTemperature(
            Returns(FT(setup.T_sfc)),
        ),
        overrides = nothing,
    )
end

# --- Diagnostics ClimaAtmos has no name for --------------------------------- #

_total_liquid(state, cache, time) =
    _total_liquid(state, cache, time, cache.atmos.microphysics_model)
_total_liquid(_, _, _, model) =
    error("`ql_all` needs a microphysics with prognostic rain; got $model")
_total_liquid(
    state,
    _,
    _,
    ::Union{
        ClimaAtmos.NonEquilibriumMicrophysics1M,
        ClimaAtmos.NonEquilibriumMicrophysics2M,
    },
) = @. lazy((state.c.ρq_lcl + state.c.ρq_rai) / state.c.ρ)

_total_ice(state, cache, time) =
    _total_ice(state, cache, time, cache.atmos.microphysics_model)
_total_ice(_, _, _, model) =
    error("`qi_all` needs a microphysics with prognostic snow; got $model")
_total_ice(
    state,
    _,
    _,
    ::Union{
        ClimaAtmos.NonEquilibriumMicrophysics1M,
        ClimaAtmos.NonEquilibriumMicrophysics2M,
    },
) = @. lazy((state.c.ρq_icl + state.c.ρq_sno) / state.c.ρ)

"""
    register_condensate_totals!()

Register `ql_all` and `qi_all`. Idempotent: a name already in the registry is
left alone.
"""
function MOSAiCAYiL.register_condensate_totals!(;
    registry = ClimaAtmos.Diagnostics.ALL_DIAGNOSTICS,
)
    haskey(registry, "ql_all") || ClimaAtmos.Diagnostics.add_diagnostic_variable!(
        short_name = "ql_all",
        units = "kg kg^-1",
        long_name = "Mass Fraction of Total Liquid Water",
        comments = "Cloud liquid plus rain, per mass of moist air.",
        compute = _total_liquid,
    )
    haskey(registry, "qi_all") || ClimaAtmos.Diagnostics.add_diagnostic_variable!(
        short_name = "qi_all",
        units = "kg kg^-1",
        long_name = "Mass Fraction of Total Ice",
        comments = "Cloud ice plus snow, per mass of moist air.",
        compute = _total_ice,
    )
    return nothing
end

function __init__()
    MOSAiCAYiL.register_condensate_totals!()
    return nothing
end

# --- Archive → ClimaAtmos diagnostic short names ---------------------------- #

"""
ClimaAtmos diagnostic short name → how it is built from the archive.

Each entry is a function of a reader (`raw` → archive values), so conversions
live where they happen: `× ρ` for number scalars, `× 100` for cloud fraction,
and the phase sum that makes `hus` total water rather than DALES `qt`.
"""
const CLIMAATMOS_FROM_DALES =
    Dict{String, @NamedTuple{f::Function, units::String}}(
        "clw" => (f = read -> read("sv005"), units = "kg kg^-1"),
        "cli" => (f = read -> read("sv008"), units = "kg kg^-1"),
        "husra" => (f = read -> read("sv002"), units = "kg kg^-1"),
        "hussn" => (f = read -> read("sv010") .+ read("sv012"), units = "kg kg^-1"),
        "hus" => (
            f = read -> read("qt") .+ read("sv008") .+ read("sv002") .+
                        read("sv010") .+ read("sv012"),
            units = "kg kg^-1",
        ),
        "ql_all" => (f = read -> read("sv005") .+ read("sv002"), units = "kg kg^-1"),
        "qi_all" => (
            f = read -> read("sv008") .+ read("sv010") .+ read("sv012"),
            units = "kg kg^-1",
        ),
        "ua" => (f = read -> read("u"), units = "m s^-1"),
        "va" => (f = read -> read("v"), units = "m s^-1"),
        "rhoa" => (f = read -> read("rhof"), units = "kg m^-3"),
        "pfull" => (
            f = read -> MOSAiCAYiL.dales_presf(
                read("presh"), read("rhof"), read("zt"), read("zm"),
            ),
            units = "Pa",
        ),
        "cl" => (f = read -> 100 .* read("cfrac"), units = "%"),
        "rld" => (f = read -> abs.(read("lwd")), units = "W m^-2"),
        "rlu" => (f = read -> abs.(read("lwu")), units = "W m^-2"),
        "rsd" => (f = read -> abs.(read("swd")), units = "W m^-2"),
        "rsu" => (f = read -> abs.(read("swu")), units = "W m^-2"),
        "rldcs" => (f = read -> abs.(read("lwdca")), units = "W m^-2"),
        "rlucs" => (f = read -> abs.(read("lwuca")), units = "W m^-2"),
        "rsdcs" => (f = read -> abs.(read("swdca")), units = "W m^-2"),
        "rsucs" => (f = read -> abs.(read("swuca")), units = "W m^-2"),
        "cdnc" => (f = read -> read("sv003") .* read("rhof"), units = "m^-3"),
        "ncra" => (f = read -> read("sv001") .* read("rhof"), units = "m^-3"),
        "ta" => (
            f = read -> MOSAiCAYiL.dales_temperature(
                read("thl"), read("ql"), read("presh"), read("rhof"),
                read("zt"), read("zm"),
            ),
            units = "K",
        ),
    )

"""
Radiative fluxes ClimaAtmos reports as surface or top scalars and DALES writes
as face profiles. `:top` is DALES's highest lower-face (~11765 m), not TOA.
"""
const CLIMAATMOS_FLUX_FROM_DALES = Dict(
    "rlds" => ("lwd", :surface),
    "rlus" => ("lwu", :surface),
    "rsds" => ("swd", :surface),
    "rsus" => ("swu", :surface),
    "rlut" => ("lwu", :top),
    "rsut" => ("swu", :top),
    "rsdt" => ("swd", :top),
)

function MOSAiCAYiL.climaatmos_field(
    short_name::AbstractString,
    date;
    root = MOSAiCAYiL.data_root(),
)
    if haskey(CLIMAATMOS_FLUX_FROM_DALES, short_name)
        raw, level = CLIMAATMOS_FLUX_FROM_DALES[short_name]
        f = MOSAiCAYiL.dales_field(raw, date; root, translate_units = false)
        k = level === :surface ? 1 : size(f.data, 1)
        return (; z = f.z[k], f.time, data = abs.(f.data[k, :]), units = "W m^-2")
    end
    spec = get(CLIMAATMOS_FROM_DALES, short_name) do
        error(
            "No DALES translation for ClimaAtmos `$short_name`; known names are " *
            join(sort(MOSAiCAYiL.climaatmos_translated_names()), ", "),
        )
    end
    sources = NamedTuple[]
    function read(raw)
        f = MOSAiCAYiL.dales_field(raw, date; root, translate_units = false)
        push!(sources, f)
        return f.data
    end
    data = spec.f(read)
    axes = first(sources)
    return (; axes.z, axes.time, data, spec.units)
end

MOSAiCAYiL.climaatmos_translated_names() = vcat(
    collect(keys(CLIMAATMOS_FROM_DALES)),
    collect(keys(CLIMAATMOS_FLUX_FROM_DALES)),
)

end # module
