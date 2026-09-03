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
function surface_fluxes(date; root = data_root(), resolved::Bool = false)
    suffix = resolved ? "t" : "s"
    raw(name) = read_variable(name, date; root, translate_units = false)
    ρ = raw("rhof").data[1, :]
    wθ_l = raw("wthl" * suffix)
    wq_t = raw("wqt" * suffix).data[1, :]
    wθ_v = raw("wthv" * suffix).data[1, :]
    c_p, L_v = DALES_CONSTANTS.cp_d, DALES_CONSTANTS.L_v
    return (;
        wθ_l.time,
        hfss = ρ .* c_p .* wθ_l.data[1, :],
        hfls = ρ .* L_v .* wq_t,
        buoyancy = ρ .* c_p .* wθ_v,
        wθ_l = wθ_l.data[1, :],
        wq_t,
        wθ_v,
    )
end

"""
    flux_partition(name, date; root)

A flux split into its resolved and subfilter parts, as `(; z, time, resolved, subfilter,
total, resolved_fraction)`.

`name` is the stem DALES appends `r`, `s` and `t` to — `"wthl"`, `"wqt"`, `"wthv"`, `"wql"`.
The fraction is the resolved share of the total where the total is non-negligible, and zero
elsewhere.

Near the surface the subfilter part carries the flux and the fraction tends to zero; through
the mixed layer the resolved eddies take over.
"""
function flux_partition(name::AbstractString, date; root = data_root(), floor = 1.0e-12)
    part(suffix) = read_variable(name * suffix, date; root, translate_units = false)
    resolved = part("r")
    subfilter = part("s").data
    total = part("t").data
    # broadcast rather than comprehend, so the (level, time) shape survives
    meaningful = abs.(total) .> floor
    safe = ifelse.(meaningful, total, one(eltype(total)))
    fraction = ifelse.(meaningful, resolved.data ./ safe, zero(eltype(total)))
    return (;
        resolved.z, resolved.time, resolved = resolved.data, subfilter, total,
        resolved_fraction = fraction,
    )
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
function turbulence_kinetic_energy(date; root = data_root())
    raw(name) = read_variable(name, date; root, translate_units = false)
    u2, v2 = raw("u2r"), raw("v2r")
    w2r, w2s = raw("w2r"), raw("w2s")
    # the vertical variances live on the half levels; average adjacent faces onto zt
    onto_centres(a) = (a[1:(end - 1), :] .+ a[2:end, :]) ./ 2
    nz = size(u2.data, 1)
    w2r_c = vcat(onto_centres(w2r.data), w2r.data[end:end, :])[1:nz, :]
    w2s_c = vcat(onto_centres(w2s.data), w2s.data[end:end, :])[1:nz, :]
    resolved = (u2.data .+ v2.data .+ w2r_c) ./ 2
    subfilter = w2s_c ./ 2
    return (; u2.z, u2.time, resolved, subfilter, total = resolved .+ subfilter)
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
function toa_radiation(date; root = data_root())
    raw(name) = read_variable(name, date; root, file = :tmser, translate_units = false)
    up = raw("SW_up_TOA")
    down = raw("SW_dn_TOA").data
    return (;
        up.time,
        shortwave_up = up.data,
        shortwave_down = down,
        longwave_up = raw("LW_up_TOA").data,
        net_shortwave = up.data .+ down,
    )
end

"""
    water_paths(date; root)

Vertically integrated water [kg m⁻²] of each species, as `(; time, total, cloud_liquid,
rain, cloud_ice, snow, graupel, liquid, ice)`.

`tmser.001.nc` carries these as slab means; `liquid` and `ice` are the two phase sums, and
`total` is the archive's own `lwp_bar`, which is not their sum — it is the liquid path alone,
under a name that predates the ice species.
"""
function water_paths(date; root = data_root())
    raw(name) = read_variable(name, date; root, file = :tmser, translate_units = false).data
    cloud_liquid, rain = raw("clwp_bar"), raw("rlwp_bar")
    cloud_ice, snow, graupel = raw("icwp_bar"), raw("siwp_bar"), raw("giwp_bar")
    time = read_variable("lwp_bar", date; root, file = :tmser,
                         translate_units = false).time
    return (;
        time, total = raw("lwp_bar"), cloud_liquid, rain, cloud_ice, snow, graupel,
        liquid = cloud_liquid .+ rain, ice = cloud_ice .+ snow .+ graupel,
    )
end

"""
    surface_precipitation(date; root)

Surface precipitation of a day, as `(; time, total, liquid, ice)`.

`tmser.001.nc`'s `sfc_prec_av` is the total and `sfc_precw_av` the liquid part, so the ice
part is their difference.
"""
function surface_precipitation(date; root = data_root())
    raw(name) = read_variable(name, date; root, file = :tmser, translate_units = false)
    total = raw("sfc_prec_av")
    liquid = raw("sfc_precw_av").data
    return (; total.time, total = total.data, liquid, ice = total.data .- liquid)
end

"""
    phase_partition(date; root, floor)

The realized liquid fraction of the condensate, `q_liq/(q_liq + q_ice)`, as
`(; z, time, liquid_fraction, q_liquid, q_ice)`.

`q_liq` is `profiles.001.nc`'s `ql`, which under SB3 is the **cloud** liquid, and `q_ice` is
`sv008`. The fraction is zero where there is no condensate rather than undefined.

This is what the run produced; [`liquid_fraction`](@ref) is the temperature ramp the scheme
would impose, and the two are not the same thing.
"""
function phase_partition(date; root = data_root(), floor = 1.0e-12)
    raw(name) = read_variable(name, date; root, file = :profiles, translate_units = false)
    q_liquid = raw("ql")
    q_ice = raw("sv008").data
    condensate = q_liquid.data .+ q_ice
    present = condensate .> floor
    safe = ifelse.(present, condensate, one(eltype(condensate)))
    fraction = ifelse.(present, q_liquid.data ./ safe, zero(eltype(condensate)))
    return (; q_liquid.z, q_liquid.time, liquid_fraction = fraction,
            q_liquid = q_liquid.data, q_ice)
end
