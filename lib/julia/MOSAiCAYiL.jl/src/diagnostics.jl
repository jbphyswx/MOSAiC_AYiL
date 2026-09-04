"""
    diagnostics.jl

Quantities a user asks of a finished day: the forcing tendency DALES applied, the surface
energy budget, the resolved/subfilter split, cloud radiative effect, water paths and phase.

Everything here reads the published archive. The 3D fields are `fielddump.jl`.
"""

# --- The forcing DALES applied ---------------------------------------------- #

"""
    dales_nudging_rate(z, q_tot, z_inversion; timescale, ramp_depth, dt, q_threshold)

The inverse nudging timescales [1/s] DALES relaxes a column on, as
`(; heat, moisture)` (`modtestbed.f90:1545-1560`).

Both are [`nudge_ramp`](@ref) over `[z_inversion, z_inversion + ramp_depth]` times an inverse
timescale. DALES never relaxes faster than one step, so the rate is capped at `1/dt`; and
where the column is drier than `q_threshold` the **moisture** is relaxed *at* the step
instead, which is why the two differ.

This is the assembly [`nudging_parameters`](@ref) feeds, and it is model-agnostic: what
consumes the result is the caller's business.
"""
function dales_nudging_rate(
    z::AbstractVector{FT}, q_tot::AbstractVector{FT}, z_inversion::FT;
    timescale::FT = FT(NAMELIST.tb_taunudge),
    ramp_depth::FT = FT(NAMELIST.tb_zmidnudge),
    dt::FT = FT(ADVECTION.dtmax),
    q_threshold::FT = FT(DRY_AIR_NUDGE_THRESHOLD),
) where {FT}
    length(z) == length(q_tot) ||
        error("Got $(length(z)) heights for $(length(q_tot)) mixing ratios.")
    inv_τ = min(one(FT) / timescale, one(FT) / dt)
    inv_τ_dry = one(FT) / dt
    z_mid = z_inversion + ramp_depth
    ramp = [nudge_ramp(z[k], z_inversion, z_mid) for k in eachindex(z)]
    return (;
        heat = ramp .* inv_τ,
        moisture = [
            ramp[k] * (q_tot[k] < q_threshold ? inv_τ_dry : inv_τ) for k in eachindex(z)
        ],
    )
end

"""
    dales_forcing_tendency(; T, q_tot, u, v, targets, advection, rate)

The total tendency DALES applied to a column, as `(; dT_dt, dq_dt, du_dt, dv_dt)`.

Each is the large-scale advection plus a relaxation toward the target profile:
`dX/dt = −(X − X_target)·rate + dX/dt|_hadv`, with `rate` from
[`dales_nudging_rate`](@ref) — its `heat` component for `T`, `u` and `v`, and its `moisture`
component for `q_tot`.

`targets` and `advection` are the `scm_in` profiles on the caller's own levels; use
[`interpolate_forcing`](@ref) to put them there. Subsidence is **not** included: it acts on
the vertical gradient, which is the calling model's to form.
"""
function dales_forcing_tendency(;
    T::AbstractVector, q_tot::AbstractVector, u::AbstractVector, v::AbstractVector,
    targets::NamedTuple, advection::NamedTuple, rate::NamedTuple,
)
    dT_dt = @. -(T - targets.T) * rate.heat + advection.T
    dq_dt = @. -(q_tot - targets.q_tot) * rate.moisture + advection.q_tot
    du_dt = @. -(u - targets.u) * rate.heat + advection.u
    dv_dt = @. -(v - targets.v) * rate.heat + advection.v
    return (; dT_dt, dq_dt, du_dt, dv_dt)
end

# --- The surface energy budget ----------------------------------------------- #

"""
    surface_fluxes(date; root, resolved)

The surface energy fluxes of a day, as
`(; time, hfss, hfls, buoyancy, wθ_l, wq_t, wθ_v)`, upward positive.

`hfss = ρ c_p ⟨w'θ_l'⟩` and `hfls = ρ L_v ⟨w'q_t'⟩` [W m⁻²]; `buoyancy = ρ c_p ⟨w'θ_v'⟩` is
the buoyancy flux, which drives the boundary layer and which
[`surface_heat_fluxes`](@ref) does not report. The three kinematic fluxes are returned
alongside.

`resolved = false` takes the subfilter fluxes `wthls`/`wqts`/`wthvs`, which is what DALES's
surface scheme produced; `true` takes the totals `wthlt`/`wqtt`/`wthvt`, which include the
resolved eddies and are the larger at any level above the first.

`hfss` is built on a **potential**-temperature flux, as DALES's own inverse is
(`modtestbed.f90:572` divides by `c_p ρ` with no Exner), so it differs from `ρ c_p ⟨w'T'⟩` by
`Π ≈ 1.005` at the surface.
"""
surface_fluxes(date; root = data_root(), resolved::Bool = false) =
    open_archive(:profiles, date; root) do ds
        surface_fluxes(ds; resolved)
    end

function surface_fluxes(ds::NC.NCDataset; resolved::Bool = false)
    suffix = resolved ? "t" : "s"
    raw(name) = read_variable(ds, name; translate_units = false)
    wθ_l = raw("wthl" * suffix)
    return surface_fluxes(;
        time = wθ_l.time,
        ρ = raw("rhof").data[1, :],
        wθ_l = wθ_l.data[1, :],
        wq_t = raw("wqt" * suffix).data[1, :],
        wθ_v = raw("wthv" * suffix).data[1, :],
    )
end

function surface_fluxes(;
    time::AbstractVector,
    ρ::AbstractVector,
    wθ_l::AbstractVector,
    wq_t::AbstractVector,
    wθ_v::AbstractVector,
    c_p = DALES_CONSTANTS.cp_d,
    L_v = DALES_CONSTANTS.L_v,
)
    return (;
        time,
        hfss = ρ .* c_p .* wθ_l,
        hfls = ρ .* L_v .* wq_t,
        buoyancy = ρ .* c_p .* wθ_v,
        wθ_l,
        wq_t,
        wθ_v,
    )
end

"""A total flux at or below this is too small to divide, and the resolved fraction is zero."""
const FLUX_FRACTION_FLOOR = 1.0f-12

"""
    flux_partition(name, date; root, floor)

A flux split into its resolved and subfilter parts, as `(; z, time, resolved, subfilter,
total, resolved_fraction)`.

`name` is the stem DALES appends `r`, `s` and `t` to — `"wthl"`, `"wqt"`, `"wthv"`, `"wql"`.
The fraction is the resolved share of the total where the total is above `floor`, and zero
elsewhere.

Near the surface the subfilter part carries the flux and the fraction tends to zero; through
the mixed layer the resolved eddies take over.
"""
flux_partition(
    name::AbstractString, date;
    root = data_root(), floor::Real = FLUX_FRACTION_FLOOR,
) = open_archive(:profiles, date; root) do ds
    flux_partition(name, ds; floor)
end

function flux_partition(
    name::AbstractString, ds::NC.NCDataset; floor::Real = FLUX_FRACTION_FLOOR,
)
    part(suffix) = read_variable(ds, name * suffix; translate_units = false)
    resolved = part("r")
    return flux_partition(;
        resolved.z, resolved.time, resolved = resolved.data,
        subfilter = part("s").data, total = part("t").data, floor = nonmissingtype(eltype(part("t").data))(floor),
    )
end

function flux_partition(;
    z::AbstractVector,
    time::AbstractVector,
    resolved::AbstractArray,
    subfilter::AbstractArray,
    total::AbstractArray,
    floor::Real = nonmissingtype(eltype(total))(FLUX_FRACTION_FLOOR), 
)
    FT = nonmissingtype(eltype(total))
    # broadcast rather than comprehend, so the (level, time) shape survives
    meaningful = abs.(total) .> floor
    safe = ifelse.(meaningful, total, one(FT))
    fraction = ifelse.(meaningful, resolved ./ safe, zero(FT))
    return (; z, time, resolved, subfilter, total, resolved_fraction = fraction)
end

"""
    turbulence_kinetic_energy(date; root)

Resolved, subfilter and total TKE [m²/s²] of each level and time, as
`(; z, time, resolved, subfilter, total)`.

The resolved part is `(u'² + v'² + w'²)/2` from `u2r`, `v2r` and `w2r`; the subfilter part is
taken from `w2s`, the only component the archive carries, so `total` is a lower bound on the
true subfilter energy rather than the whole of it.

`u2r` and `v2r` sit on `zt` and `w2r`/`w2s` on `zm`, so the vertical component is
interpolated onto the full levels before the sum.
"""
turbulence_kinetic_energy(date; root = data_root()) =
    open_archive(:profiles, date; root) do ds
        turbulence_kinetic_energy(ds)
    end

function turbulence_kinetic_energy(ds::NC.NCDataset)
    raw(name) = read_variable(ds, name; translate_units = false)
    u2 = raw("u2r")
    return turbulence_kinetic_energy(;
        u2.z, u2.time, u2 = u2.data, v2 = raw("v2r").data,
        w2r = raw("w2r").data, w2s = raw("w2s").data,
    )
end

function turbulence_kinetic_energy(;
    z::AbstractVector,
    time::AbstractVector,
    u2::AbstractArray,
    v2::AbstractArray,
    w2r::AbstractArray,
    w2s::AbstractArray,
)
    # the vertical variances live on the half levels; average adjacent faces onto zt
    onto_centres(a) = (a[1:(end - 1), :] .+ a[2:end, :]) ./ 2
    nz = size(u2, 1)
    w2r_c = vcat(onto_centres(w2r), w2r[end:end, :])[1:nz, :]
    w2s_c = vcat(onto_centres(w2s), w2s[end:end, :])[1:nz, :]
    resolved = (u2 .+ v2 .+ w2r_c) ./ 2
    subfilter = w2s_c ./ 2
    return (; z, time, resolved, subfilter, total = resolved .+ subfilter)
end

# --- Radiation and water ------------------------------------------------------ #

"""
    toa_radiation(date; root)

Top-of-atmosphere radiative fluxes [W m⁻²] of a day, as
`(; time, shortwave_up, shortwave_down, longwave_up, net_shortwave)`.

**The clear-sky fluxes are not available.** `SW_up_ca_TOA`, `SW_dn_ca_TOA`, `LW_up_ca_TOA`
and `LW_dn_ca_TOA` are declared in `tmser.001.nc` and are identically zero on every day, so
no cloud radiative effect can be formed from this archive — the difference against them would
just return the all-sky flux. `LW_dn_TOA` is zero for the physical reason that nothing shines
down onto the top of the atmosphere.

`SW_dn_TOA` is stored negative, and both shortwave fields are zero through the polar night.
`net_shortwave` is their sum, which is the convention that makes it the absorbed flux.
"""
toa_radiation(date; root = data_root()) =
    open_archive(:tmser, date; root) do ds
        toa_radiation(ds)
    end

function toa_radiation(ds::NC.NCDataset)
    raw(name) = read_variable(ds, name; file = :tmser, translate_units = false)
    up = raw("SW_up_TOA")
    return toa_radiation(;
        up.time, shortwave_up = up.data,
        shortwave_down = raw("SW_dn_TOA").data, longwave_up = raw("LW_up_TOA").data,
    )
end

toa_radiation(;
    time::AbstractVector,
    shortwave_up::AbstractVector,
    shortwave_down::AbstractVector,
    longwave_up::AbstractVector,
) = (;
    time, shortwave_up, shortwave_down, longwave_up,
    net_shortwave = shortwave_up .+ shortwave_down,
)

"""
    water_paths(date; root)

Vertically integrated water [kg m⁻²] of each species, as `(; time, total, cloud_liquid,
rain, cloud_ice, snow, graupel, liquid, ice)`.

`tmser.001.nc` carries these as slab means; `liquid` and `ice` are the two phase sums, and
`total` is the archive's own `lwp_bar`, which is not their sum — it is the liquid path alone,
under a name that predates the ice species.
"""
water_paths(date; root = data_root()) =
    open_archive(:tmser, date; root) do ds
        water_paths(ds)
    end

function water_paths(ds::NC.NCDataset)
    raw(name) = read_variable(ds, name; file = :tmser, translate_units = false)
    total = raw("lwp_bar")
    return water_paths(;
        total.time, total = total.data,
        cloud_liquid = raw("clwp_bar").data, rain = raw("rlwp_bar").data,
        cloud_ice = raw("icwp_bar").data, snow = raw("siwp_bar").data,
        graupel = raw("giwp_bar").data,
    )
end

water_paths(;
    time::AbstractVector,
    total::AbstractVector,
    cloud_liquid::AbstractVector,
    rain::AbstractVector,
    cloud_ice::AbstractVector,
    snow::AbstractVector,
    graupel::AbstractVector,
) = (;
    time, total, cloud_liquid, rain, cloud_ice, snow, graupel,
    liquid = cloud_liquid .+ rain, ice = cloud_ice .+ snow .+ graupel,
)

"""
    surface_precipitation(date; root)

Surface precipitation of a day, as `(; time, total, liquid, ice)`.

`tmser.001.nc`'s `sfc_prec_av` is the total and `sfc_precw_av` the liquid part, so the ice
part is their difference.
"""
surface_precipitation(date; root = data_root()) =
    open_archive(:tmser, date; root) do ds
        surface_precipitation(ds)
    end

function surface_precipitation(ds::NC.NCDataset)
    raw(name) = read_variable(ds, name; file = :tmser, translate_units = false)
    total = raw("sfc_prec_av")
    return surface_precipitation(;
        total.time, total = total.data, liquid = raw("sfc_precw_av").data,
    )
end

surface_precipitation(;
    time::AbstractVector, total::AbstractVector, liquid::AbstractVector,
) = (; time, total, liquid, ice = total .- liquid)

"""Condensate at or below this is too little to partition, and the liquid fraction is zero."""
const CONDENSATE_FLOOR = 1.0f-12

"""
    phase_partition(date; root, floor)

The realized liquid fraction of the condensate, `q_liq/(q_liq + q_ice)`, as
`(; z, time, liquid_fraction, q_liquid, q_ice)`.

`q_liq` is `profiles.001.nc`'s `ql`, which under SB3 is the **cloud** liquid, and `q_ice` is
`sv008`. The fraction is zero where the condensate is at or below `floor` rather than
undefined.

This is what the run produced; [`liquid_fraction`](@ref) is the temperature ramp the scheme
would impose, and the two are not the same thing.
"""
phase_partition(date; root = data_root(), floor::Real = CONDENSATE_FLOOR) =
    open_archive(:profiles, date; root) do ds
        phase_partition(ds; floor)
    end

function phase_partition(ds::NC.NCDataset; floor::Real = CONDENSATE_FLOOR)
    raw(name) = read_variable(ds, name; file = :profiles, translate_units = false)
    q_liquid = raw("ql")
    return phase_partition(;
        q_liquid.z, q_liquid.time, q_liquid = q_liquid.data,
        q_ice = raw("sv008").data, floor = nonmissingtype(eltype(q_liquid.data))(floor),
    )
end

function phase_partition(;
    z::AbstractVector,
    time::AbstractVector,
    q_liquid::AbstractArray,
    q_ice::AbstractArray,
    floor::Real = nonmissingtype(eltype(q_liquid))(CONDENSATE_FLOOR), 
)
    FT = nonmissingtype(eltype(q_liquid))
    condensate = q_liquid .+ q_ice
    present = condensate .> floor
    safe = ifelse.(present, condensate, one(FT))
    fraction = ifelse.(present, q_liquid ./ safe, zero(FT))
    return (; z, time, liquid_fraction = fraction, q_liquid, q_ice)
end
