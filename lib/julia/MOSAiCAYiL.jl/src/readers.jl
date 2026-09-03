"""
    readers.jl

Readers for `scm_in.*.nc` and `profiles.001.nc`, plus namelist inspection.
Physics does not read namelist placeholders.
"""

# `sfc_sens_flx` and `sfc_lat_flx` are absent from every testbed file, and the
# files declare no `_FillValue`, so NCDatasets hands back the netCDF default fill
# rather than `missing`. That is what turns an absent surface flux into 1e37 W/m².
const NC_FILL_FLOAT = 9.9692099683868690f36
const NC_FILL_DOUBLE = 9.9692099683868690e36

_is_fill(::Missing) = true
_is_fill(v::Float32) = v === NC_FILL_FLOAT
_is_fill(v::Float64) = v === NC_FILL_DOUBLE
_is_fill(::Any) = false

"""
    testbed_forcing(date; root, time_index)

The ERA5 testbed forcing for one AYiL day, on an ascending height axis: the state
profiles, the large-scale advective tendencies, the geostrophic wind and the surface
conditions the day was run with.

`scm_in` stores its levels top-down from about 85 km — 3037 to 3042 of them, depending
on the day — so every profile is turned around here, by [`read_variable`](@ref), which
also reaches the rest of [`SCM_IN`](@ref) under the raw names.

`time_index` selects which time record to read. Each file is a single 05:00–11:00
UTC composite average written twice, and the two records are bitwise identical on
every shipped day.

`hus` is total water, `q + ql + qi`. `wa` is reconstructed as DALES does
(`modtestbed.f90:739-741`): vapour-only `T_v = T(1 + 0.61 q)`, DALES `R_d` and `g`.
Surface fluxes that are netCDF fill become `missing`.
"""
function testbed_forcing(date; root = data_root(), time_index::Int = 1)
    path = scm_in_path(date; root)
    isfile(path) || error("No testbed forcing at $path")
    return NC.NCDataset(path, "r") do ds
        column(name) = read_variable(ds, name; file = :scm_in).data
        prof(name) = column(name)[:, time_index]
        scalar(name) = column(name)[time_index]
        function optional(name)
            v = scalar(name)
            return _is_fill(v) ? missing : v
        end

        z = prof("height_f")

        ta = prof("t_local")
        q = prof("q_local")
        ql = prof("ql_local")
        qi = prof("qi_local")
        hus = q .+ ql .+ qi
        p = prof("pressure_f")

        FT = eltype(ta)
        grav = FT(DALES_CONSTANTS.grav)
        R_d = FT(DALES_CONSTANTS.R_d)
        Tv = ta .* (1 .+ FT(0.61) .* q)
        wa = .-prof("omega") .* (R_d .* Tv) ./ (p .* grav)

        surface = (;
            ps = scalar("ps"),
            trajectory_latitude = scalar("lat"),
            trajectory_longitude = mod(scalar("lon") + 180, 360) - 180,
            albedo = scalar("albedo"),
            albedo_snow = scalar("albedo_snow"),
            snow = scalar("snow"),
            z0_momentum = scalar("mom_rough"),
            z0_heat = scalar("heat_rough"),
            sea_ice_fraction = scalar("sea_ice_frct"),
            t_skin = scalar("t_skin"),
            t_skin_ocean = scalar("t_skin_ocean"),
            t_skin_seaice = scalar("t_skin_seaice"),
            open_sst = scalar("open_sst"),
            land_sea_mask = scalar("lsm"),
            sensible_heat_flux = optional("sfc_sens_flx"),
            latent_heat_flux = optional("sfc_lat_flx"),
        )

        (;
            z,
            ta,
            hus,
            q,
            ql,
            qi,
            ua = prof("u_local"),
            va = prof("v_local"),
            p,
            o3 = prof("o3"),
            n_ccn = prof("n_ccn"),
            wa,
            tntha = prof("tadv"),
            tnhusha = prof("qadv") .+ prof("ladv") .+ prof("iadv"),
            tnua = prof("uadv"),
            tnva = prof("vadv"),
            ug = prof("ug"),
            vg = prof("vg"),
            surface,
        )
    end
end

testbed_forcing(c::MOSAiCAYiLCase; kwargs...) = testbed_forcing(date_string(c); kwargs...)

"""Linear in height, extrapolating past either end, as `modtestbed.f90:1096-1102` does."""
function _at_height(z_src::AbstractVector, v_src::AbstractVector, z)
    n = length(z_src)
    n >= 2 || error("Interpolating needs at least two source levels; got $n.")
    k = clamp(searchsortedlast(z_src, z), 1, n - 1)
    f = (z - z_src[k]) / (z_src[k + 1] - z_src[k])
    return v_src[k] + f * (v_src[k + 1] - v_src[k])
end

"""
    interpolate_forcing(forcing, z)

A day's forcing on the heights `z`, by the scheme DALES used to put it on the LES grid:
linear in height, level by level (`modtestbed.f90:1082-1121`).

`z` may run below the ERA5 column's lowest level (2 m) or above its top, and the result is
the linear extrapolation of the two nearest levels there, which is what DALES's own
unclamped `fac` gives. For the boundary condition at the ground use
[`surface_state`](@ref) instead: the skin is a surface, not the air continued downward.

Pressure is interpolated with everything else. DALES discards it and rebuilds its column
hydrostatically from `ps` ([`pressure_fromztop`](@ref)); do that if you need a column in
hydrostatic balance with its own temperature.
"""
function interpolate_forcing(forcing, z::AbstractVector)
    issorted(forcing.z) || error("The forcing's heights must be ascending.")
    on(field) = [_at_height(forcing.z, field, zk) for zk in z]
    return (;
        z = collect(z),
        ta = on(forcing.ta),
        hus = on(forcing.hus),
        q = on(forcing.q),
        ql = on(forcing.ql),
        qi = on(forcing.qi),
        ua = on(forcing.ua),
        va = on(forcing.va),
        p = on(forcing.p),
        o3 = on(forcing.o3),
        n_ccn = on(forcing.n_ccn),
        wa = on(forcing.wa),
        tntha = on(forcing.tntha),
        tnhusha = on(forcing.tnhusha),
        tnua = on(forcing.tnua),
        tnva = on(forcing.tnva),
        ug = on(forcing.ug),
        vg = on(forcing.vg),
        forcing.surface,
    )
end

"""
    scm_in_air_density(forcing)

Air density [kg/m³] from `scm_in` `pressure_f`, `t_local`, and `(q, ql, qi)` —
one mutually consistent ERA5 column. Does not hydrostatically integrate from `ps`:
`ps` and `pressure_f` are separate ERA5 fields and are not mutually hydrostatic

`T_v = T (1 + (R_v/R_d − 1) q − ql − qi)` with specific humidities; `ρ = p / (R_d T_v)`.
The condensate is the file's own `(ql, qi)`, so nothing is re-diagnosed from saturation.
Returns `(z, ρ)`. Never use `rhobf` as air density.
"""
function scm_in_air_density(forcing; backend = DefaultThermodynamicsBackend())
    q_tot = forcing.q .+ forcing.ql .+ forcing.qi
    ρ = air_density.(backend, forcing.ta, forcing.p, q_tot, forcing.ql, forcing.qi)
    return (forcing.z, ρ)
end

"""
    les_density(date, [FT = Float32]; root = data_root(), time_index = 1)

`(z, ρ)`: the DALES cell-centre heights [m] and the slab-mean air density
[kg/m³] from `profiles.001.nc` `rhof`, one column of [`dales_slab_column`](@ref).

`time_index = 1` is t = 300 s, the earliest sample, not t = 0. Not `rhobf`/`rhobh`.
"""
function les_density(
    date, ::Type{FT} = Float32; root = data_root(), time_index::Int = 1,
) where {FT}
    c = dales_slab_column(date, FT; root)
    return (c.z, c.rhof[:, time_index])
end

"""
    les_faces(date; faces = LES_FACES, root = data_root())

The cell faces [m] of the DALES grid. Default is the stored [`LES_FACES`](@ref).
Pass `faces = nothing` to reconstruct from this day's `zm` + `zt`.
"""
function les_faces(date; faces = LES_FACES, root = data_root())
    faces !== nothing && return faces
    path = les_profiles_path(date; root)
    isfile(path) || error("No DALES output at $path")
    return NC.NCDataset(path, "r") do ds
        zt = vec(Array(ds["zt"]))
        zm = vec(Array(ds["zm"]))
        return vcat(zm, 2 * last(zt) - last(zm))
    end
end

"""
    NamelistGroups

`&group => key => raw string`, the shape [`namelist`](@ref) returns.
"""
const NamelistGroups = Dict{Symbol, Dict{Symbol, String}}

"""
    namelist(date; root = data_root())

The day's DALES `namoptions` as `&group => key => raw string`, with `!` comments stripped.

Group identity is kept because the file needs it: `dtav` appears in nine groups carrying two
different values, `timeav` in five carrying two, `lstat` in two. Reach a value with
[`namelist_value`](@ref), which parses it and refuses a
[`NAMELIST_PLACEHOLDERS`](@ref) entry.
"""
function namelist(date; root = data_root())
    path = namoptions_path(date; root)
    isfile(path) || error("No namoptions at $path")
    out = NamelistGroups()
    group = nothing
    for line in eachline(path)
        stripped = strip(first(split(line, '!')))
        isempty(stripped) && continue
        if startswith(stripped, '&')
            group = Symbol(lowercase(stripped[(nextind(stripped, 1)):end]))
            haskey(out, group) && error("`&$group` appears twice in $path")
            out[group] = Dict{Symbol, String}()
            continue
        end
        if stripped == "/"
            group = nothing
            continue
        end
        parts = split(stripped, '=', limit = 2)
        length(parts) == 2 || continue
        isnothing(group) &&
            error("`$(strip(parts[1]))` is outside any &group in $path")
        out[group][Symbol(lowercase(strip(parts[1])))] = String(strip(parts[2]))
    end
    isempty(out) && error("Parsed no groups from $path")
    return out
end

"""
    namelist_groups_with(nl, key)

Every group of `nl` carrying `key`, ascending. Empty when none does.
"""
namelist_groups_with(nl::NamelistGroups, key::Symbol) =
    sort!([g for (g, kv) in nl if haskey(kv, key)])

function _unique_group(nl::NamelistGroups, key::Symbol)
    groups = namelist_groups_with(nl, key)
    isempty(groups) && error("`$key` is in no group of this namelist.")
    length(groups) == 1 || error(
        "`$key` is in $(length(groups)) groups — \
         $(join(("&" .* String.(groups)), ", ")); pass one, as \
         `namelist_value(nl, :$(first(groups)), :$key)`.",
    )
    return first(groups)
end

_parse_namelist(::Type{String}, raw::AbstractString) = String(strip(raw, ['\'', '"']))

function _parse_namelist(::Type{Bool}, raw::AbstractString)
    flag = lowercase(strip(raw, '.'))
    flag in ("true", "t") && return true
    flag in ("false", "f") && return false
    return nothing
end

_parse_namelist(::Type{T}, raw::AbstractString) where {T <: Real} =
    tryparse(T, replace(raw, "d" => "e", "D" => "e"))

"""
    namelist_value([T,] nl, group, key)
    namelist_value([T,] nl, key)

The value of `&group`'s `key`. With `T`, parsed: `Bool` reads `.true.`/`.false.`, a `Real`
reads Fortran's `d` exponent, `String` strips the quotes.

Without `group`, a key carried by more than one group errors and names them. A
[`NAMELIST_PLACEHOLDERS`](@ref) entry errors naming the accessor that supersedes it;
[`namelist_placeholder`](@ref) returns its raw string.
"""
function namelist_value(nl::NamelistGroups, group::Symbol, key::Symbol)
    haskey(nl, group) || error(
        "`&$group` is not in this namelist; it has \
         $(join(("&" .* String.(sort!(collect(keys(nl))))), ", ")).",
    )
    entries = nl[group]
    haskey(entries, key) || error(
        "`$key` is not in `&$group`; it has \
         $(join(String.(sort!(collect(keys(entries)))), ", ")).",
    )
    accessor = get(NAMELIST_PLACEHOLDERS, (group, key), nothing)
    isnothing(accessor) || error(
        "`&$group $key` is a placeholder DALES overwrote from `scm_in` every substep; the \
         value the run used is `$accessor(case)`. `namelist_placeholder` returns the raw \
         string.",
    )
    return entries[key]
end

function namelist_value(::Type{T}, nl::NamelistGroups, group::Symbol, key::Symbol) where {T}
    value = _parse_namelist(T, namelist_value(nl, group, key))
    isnothing(value) &&
        error("`&$group $key = $(nl[group][key])` is not a $T.")
    return value
end

namelist_value(nl::NamelistGroups, key::Symbol) =
    namelist_value(nl, _unique_group(nl, key), key)

namelist_value(::Type{T}, nl::NamelistGroups, key::Symbol) where {T} =
    namelist_value(T, nl, _unique_group(nl, key), key)

"""
    namelist_placeholder(nl, group, key)

The raw string of a [`NAMELIST_PLACEHOLDERS`](@ref) entry, which is not what the run used.
"""
function namelist_placeholder(nl::NamelistGroups, group::Symbol, key::Symbol)
    haskey(NAMELIST_PLACEHOLDERS, (group, key)) ||
        error("`&$group $key` is not a placeholder; use `namelist_value`.")
    return nl[group][key]
end

"""Namelist `xlat` [degrees] — a placeholder; use [`latitude`](@ref) for physics."""
namelist_latitude(date; root = data_root()) =
    parse(Float64, namelist_placeholder(namelist(date; root), :domain, :xlat))

"""Namelist `xlon` [degrees] — a placeholder; use [`longitude`](@ref) for physics."""
namelist_longitude(date; root = data_root()) =
    parse(Float64, namelist_placeholder(namelist(date; root), :domain, :xlon))
