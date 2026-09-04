"""
    ice_filters.jl

The filters behind [`BEST_SIMULATION_TOP_F`](@ref): where a day's reference ice
stops being reproducible, hence how high that day can be simulated, and where its
cloud top sits.

Runnable, so the tables in `ayil_info.jl` can be re-derived rather than trusted.
SB3 size/fall coefficients are [`SB3_PARTICLES`](@ref) in `microphysics.jl`.
"""

# --- One read per day, shared by every filter ------------------------------- #

"""
    ice_fields([FT = Float64,] date; root, time_inds, q_min)

The fields the filters need, read once: heights, density, cloud liquid and ice,
ice number, and the mask of levels and times SB3 counts as ice-bearing.

`time_inds` selects the output window. The first record is skipped by default, since some
cases are in principle problematic but start with subsaturated ice which rapidly ameliorates.

We use a window over the beginning by default to speed up analysis, and before significant sedimentation has occured, but
not too small that anomalous ice's transport is ignored in setting the cloud top.
"""
function ice_fields(
    date,
    ::Type{FT} = Float64,
    ;
    root = data_root(),
    time_inds = 2:12,
    q_min = zero(FT),
) where {FT}
    z, ρ, q_liq, q_ice, n_ice = open_archive(:profiles, date; root) do ds
        (
            FT.(vec(Array(ds["zt"]))),
            FT.(_read_oriented(ds, "rhof")),
            FT.(_read_oriented(ds, "sv005")),
            FT.(_read_oriented(ds, "sv008")),
            FT.(_read_oriented(ds, "sv007")),
        )
    end::Tuple{Vector{FT}, Matrix{FT}, Matrix{FT}, Matrix{FT}, Matrix{FT}}
    # `ice_rate` is DALES's `sed_q/ρ` — a mixing ratio times a fall speed, despite
    # the raw file labelling it kg/m2 — so dividing out the mixing ratio leaves the
    # mass-weighted fall speed the reference actually realized.
    ice_rate = open_archive(:mphys, date; root) do ds
        FT.(_read_oriented(ds, "ice_rate"))
    end::Matrix{FT}
    return ice_fields(; z, ρ, q_liq, q_ice, n_ice, ice_rate, time_inds, q_min)
end

function ice_fields(;
    z::AbstractVector,
    ρ::AbstractMatrix,
    q_liq::AbstractMatrix,
    q_ice::AbstractMatrix,
    n_ice::AbstractMatrix,
    ice_rate::AbstractMatrix,
    time_inds = 2:12,
    q_min = zero(nonmissingtype(eltype(q_ice))),
)
    at(a) = view(a, :, time_inds)
    qi, ni, ql, ρi, rate = at(q_ice), at(n_ice), at(q_liq), at(ρ), at(ice_rate)
    present = (qi .> q_min) .& isfinite.(qi) .& isfinite.(ni)
    return (;
        z, time_inds, ρ = ρi, q_liq = ql, q_ice = qi, n_ice = ni,
        ice_rate = rate, present,
    )
end

"""Highest `z` strictly below the lowest flagged level; `z[end]` if none is flagged."""
function z_max_below_flagged(z, flagged_by_level)
    k = findfirst(flagged_by_level)
    isnothing(k) && return last(z)
    return k == 1 ? zero(eltype(z)) : z[k - 1]
end

"""
    trim_top_adjacent_cloud(z, z_max, qs; top_tol)

Lower `z_max` below any cloud touching it.

Truncating at `z_max` can leave a cloud sliced against the top; for each field in
`qs`, cloud is more than `top_tol` of that field's maximum inside the region, and
where it reaches the top level the walk continues down until clear air. `0.0` when
nothing is left.
"""
function trim_top_adjacent_cloud(z, z_max, qs; top_tol = eps(float(eltype(z))))
    none = zero(eltype(z))
    for q in qs
        inside = findall(<=(z_max), z)
        isempty(inside) && return none
        window = view(q, inside, :)
        q_max = maximum(window; init = zero(eltype(q)))
        q_max > 0 || continue
        cloudy = [any(>(top_tol * q_max), view(window, i, :)) for i in axes(window, 1)]
        last(cloudy) || continue
        i = length(cloudy)
        while i > 0 && cloudy[i]      # walk down through the cloud on the boundary
            i -= 1
        end
        z_max = i == 0 ? none : z[inside[i]]
    end
    return z_max
end

"""Cloud of either phase somewhere at or below `z_max`."""
function has_cloud_below(fields, z_max; cloud_min = eltype(fields.q_liq)(1.0e-8))
    below = fields.z .<= z_max
    any(view(fields.q_liq, below, :) .+ view(fields.q_ice, below, :) .> cloud_min)
end

# --- Filters ---------------------------------------------------------------- #
#
# Each takes the shared fields and returns `(; valid, z_max)`. A driver caps the
# day at the smallest `z_max` any filter allows, so each does its own trim and its
# own cloud check rather than relying on a combined flag.

"""No constraint; the column's own top. The identity of the filter set."""
identity_filter(fields) = (; valid = true, z_max = last(fields.z))

"""
    ice_size_floor(fields; D_min, top_tol, q_min)

Invalid where the mean ice crystal is smaller than `D_min` while significant ice
is present.

`D_min = 130 μm` sits between the ~60 μm DALES pins at initialization and the
~1 mm of an ice cloud that has evolved.
"""
function ice_size_floor(
    fields;
    D_min = eltype(fields.z)(130.0e-6),
    q_min = eltype(fields.z)(1.0e-8),
    top_tol = eps(float(eltype(fields.z))),
    cloud_min = eltype(fields.z)(1.0e-8),
)
    (; z, q_liq, q_ice, n_ice, present) = fields
    ice = SB3_PARTICLES.cloud_ice
    x_floor = (D_min / ice.a)^(1 / ice.b)
    # Stage 1: find the valid region from the mean-crystal-size criterion.
    bad = present .& (n_ice .> 0) .& (q_ice .> q_min) .& (q_ice ./ n_ice .< x_floor)
    z_max = z_max_below_flagged(z, vec(any(bad, dims = 2)))
    # Stage 2: cutoff any cloud adjacent to the top of the domain, in liquid or ice
    z_max = trim_top_adjacent_cloud(z, z_max, (q_liq, q_ice); top_tol)
    # Stage 3: make sure there is actually cloud in the surviving region.
    return (; valid = z_max > 0 && has_cloud_below(fields, z_max; cloud_min), z_max)
end

"""
    ice_fall_speed_floor(fields; v_min, top_tol, q_min)

Invalid where the mass-weighted ice fall speed stays below `v_min` while
significant ice is present — ice that neither sediments nor autoconverts.

The speed is the *realized* one, `ice_rate / q_ice`, which carries the large
particles that do most of the falling. [`sb3_fall_speed`](@ref) computes the
speed SB3 predicts from the mean state instead; that is a strictly increasing
function of the same mean particle mass [`ice_size_floor`](@ref) tests, so it adds
no independent constraint and its magnitudes do not share this threshold.
"""
function ice_fall_speed_floor(
    fields;
    v_min = eltype(fields.z)(1.0e-2),
    q_min = eltype(fields.z)(1.0e-8),
    top_tol = eps(float(eltype(fields.z))),
    cloud_min = eltype(fields.z)(1.0e-8),
)
    (; z, q_liq, q_ice, ice_rate, present) = fields
    v = ice_rate ./ q_ice

    # Stage 1: find the valid region from the ice fall-speed criterion.
    bad = present .& isfinite.(v) .& (v .< v_min) .& (q_ice .> q_min)
    z_max = z_max_below_flagged(z, vec(any(bad, dims = 2)))
    # Stage 2: cutoff any cloud adjacent to the top of the domain, in liquid or ice
    z_max = trim_top_adjacent_cloud(z, z_max, (q_liq, q_ice); top_tol)
    # Stage 3: make sure there is actually cloud in the surviving region.
    return (; valid = z_max > 0 && has_cloud_below(fields, z_max; cloud_min), z_max)
end

"""
    extreme_n_ice(fields; kwargs...)

Invalid where the ice number itself is extreme, independently of the size and
fall-speed criteria. Not implemented; the two filters above already reject the
days this was meant to catch.
"""
extreme_n_ice(fields; kwargs...) =
    error("extreme_n_ice is not implemented; use ice_size_floor and ice_fall_speed_floor")

# --- Drivers ---------------------------------------------------------------- #

"""The filters used in production."""
const CANONICAL_ICE_FILTERS = (ice_size_floor, ice_fall_speed_floor)

"""
    best_z_maxs(dates = MOSAiCAYiL_dates, [FT = Float64]; filters, z_floor, root, time_inds, kwargs...)

`date => z_max` for every day every filter accepts, capped at the smallest `z_max`
any of them allows.

Days that fail a filter, or that survive only below `z_floor`, are dropped. This
is what [`BEST_SIMULATION_TOP_F`](@ref) derives from, before the per-day hand check
and the collapse onto the grid heights that table records.

`kwargs...` reach the filters, so an unrecognised one fails inside a filter rather than here.

`mapper` is how the days are walked: `map` serially, or [`MOSAiCAYiL.pmap`](@ref)
across worker processes, each day being an independent pair of file reads.
"""
function best_z_maxs(
    dates = MOSAiCAYiL_dates,
    ::Type{FT} = Float64;
    filters = CANONICAL_ICE_FILTERS,
    z_floor::FT = FT(500),
    root = data_root(),
    time_inds = 2:12,
    mapper = map,
    kwargs...,
) where {FT}
    per_day = mapper(_parallel_items(dates)) do date
        fields = ice_fields(date, FT; root, time_inds)
        z_max = last(fields.z)
        valid = true
        for filter in filters
            out = filter(fields; kwargs...)
            out.valid || (valid = false; break)
            z_max = min(z_max, out.z_max)
        end
        return (date_string(date), valid ? z_max : nothing)
    end
    kept = Dict{String, FT}()
    for (key, z_max) in per_day
        (!isnothing(z_max) && z_max > z_floor) && (kept[key] = z_max)
    end
    return kept
end

"""
    get_cloud_tops(dates = keys(BEST_SIMULATION_TOP_F), [FT = Float64]; z_tops, tol, root, time_inds)

`(; cloud_top, failed)`: the highest level carrying at least `tol` of the day's
peak cloud liquid or ice, within the column each day is capped at.

Clouds sitting against the cap are walked down past, so a sliced cloud does not set the top;
a day whose cloud is entirely against the boundary has no top to report and is returned in
`failed` rather than given one derived from the cut.

`z_tops` is the cap per day. It defaults to [`BEST_SIMULATION_TOP_F`](@ref), the
heights days are actually simulated to, but the caps the filters themselves
produced ([`best_z_maxs`](@ref)) are a different and equally sensible choice, so
it is an argument rather than wired in.

`time_inds` spans the whole record here, unlike the ice filters' opening window:
where the cloud reaches is a question about the run, not about its initialization,
and restricting it puts the top hundreds to thousands of metres too low. With the
full record and the filters' own caps this reproduces every one of the 24
hand-checked days, `FAILED` cases included.

`mapper` is how the days are walked: `map` serially, or [`MOSAiCAYiL.pmap`](@ref)
across worker processes.
"""
function get_cloud_tops(
    dates = keys(BEST_SIMULATION_TOP_F),
    ::Type{FT} = Float64;
    z_tops = BEST_SIMULATION_TOP_F,
    tol::FT = FT(0.01),
    root = data_root(),
    time_inds = Colon(),
    mapper = map,
) where {FT}
    per_day = mapper(_parallel_items(dates)) do date
        fields = ice_fields(date, FT; root, time_inds)
        key = date_string(date)
        z_max = get(z_tops, key, last(fields.z))
        inside = findall(<=(z_max), fields.z)
        tops = FT[]
        ok = true
        for (q, phase) in ((fields.q_liq, :liquid), (fields.q_ice, :ice))
            window = view(q, inside, :)
            q_max = maximum(window; init = zero(FT))
            iszero(q_max) && continue      # this phase has no cloud; not a failure
            result = _cloud_top_below_boundary(fields.z, inside, window, q_max, tol)
            if result.success
                push!(tops, result.z_top)
            else
                @error "cloud only against the domain top" date phase z_max q_max
                ok = false
            end
        end
        return (key, ok ? (isempty(tops) ? z_max : maximum(tops)) : nothing)
    end
    cloud_top = Dict{String, FT}()
    failed = String[]
    for (key, top) in per_day
        isnothing(top) ? push!(failed, key) : (cloud_top[key] = top)
    end
    return (; cloud_top, failed)
end

# The highest cloudy level that is not part of a cloud touching the boundary.
function _cloud_top_below_boundary(z, inside, window, q_max, tol)
    cloudy = [any(>=(tol * q_max), view(window, i, :)) for i in axes(window, 1)]
    none = zero(eltype(z))
    i_top = findlast(cloudy)
    isnothing(i_top) && return (; z_top = none, success = true)
    i_top < length(inside) && return (; z_top = z[inside[i_top]], success = true)

    i = length(inside)
    while i > 0 && cloudy[i]
        i -= 1
    end
    i == 0 && return (; z_top = none, success = false)
    i_cloud = findlast(view(cloudy, 1:i))
    isnothing(i_cloud) && return (; z_top = none, success = false)
    return (; z_top = z[inside[i_cloud]], success = true)
end