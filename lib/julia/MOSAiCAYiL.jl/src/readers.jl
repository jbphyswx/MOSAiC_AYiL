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
    read_scm_in(date; root, time_index)

The ERA5 testbed forcing for one AYiL day, on an ascending height axis.

`scm_in` stores its levels top-down from about 85 km — 3037 to 3042 of them,
depending on the day — so every profile is reversed here.

`time_index` selects which time record to read. Each file is a single 05:00–11:00
UTC composite average written twice, and the two records are bitwise identical on
every shipped day.

`hus` is total water, `q + ql + qi`. `wa` is reconstructed as DALES does
(`modtestbed.f90:739-741`): vapour-only `T_v = T(1 + 0.61 q)`, DALES `R_d` and `g`.
Surface fluxes that are netCDF fill become `missing`.
"""
function read_scm_in(date; root = data_root(), time_index::Int = 1)
    path = scm_in_path(date; root)
    isfile(path) || error("No testbed forcing at $path")
    return NC.NCDataset(path, "r") do ds
        prof(name) = reverse(Array(ds[name])[:, time_index])
        scalar(name) = Array(ds[name])[time_index]
        function optional(name)
            v = scalar(name)
            return _is_fill(v) ? missing : v
        end

        z = reverse(Array(ds["height_f"])[:, time_index])

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

read_scm_in(c::MOSAiCAYiLCase; kwargs...) = read_scm_in(date_string(c); kwargs...)

"""
    scm_in_air_density(forcing)

Air density [kg/m³] from `scm_in` `pressure_f`, `t_local`, and `(q, ql, qi)` —
one mutually consistent ERA5 column (design.md §8). Does not hydrostatically
integrate from `ps`.

`T_v = T (1 + (R_v/R_d − 1) q − ql − qi)` with specific humidities; `ρ = p / (R_d T_v)`.
Returns `(z, ρ)`. Never use `rhobf` as air density.
"""
function scm_in_air_density(forcing)
    R_d = oftype(float(forcing.ta[1]), DALES_CONSTANTS.R_d)
    R_v = oftype(float(forcing.ta[1]), DALES_CONSTANTS.R_v)
    T_v =
        forcing.ta .* (
            1 .+ (R_v / R_d - 1) .* forcing.q .- forcing.ql .- forcing.qi
        )
    ρ = forcing.p ./ (R_d .* T_v)
    return (forcing.z, ρ)
end

"""
    les_density(date; root = data_root(), time_index = 1)

`(z, ρ)`: the DALES cell-centre heights [m] and the slab-mean air density
[kg/m³] from `profiles.001.nc` `rhof`.

`time_index = 1` is t = 300 s, the earliest sample, not t = 0. Not `rhobf`/`rhobh`.
"""
function les_density(date; root = data_root(), time_index::Int = 1)
    path = les_profiles_path(date; root)
    isfile(path) || error("No DALES output at $path")
    return NC.NCDataset(path, "r") do ds
        return (vec(Array(ds["zt"])), Array(ds["rhof"])[:, time_index])
    end
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
    namelist(case; root = data_root())

The case's DALES `namoptions` as a flat `Dict` of key to raw string value.

For inspection. Physics does not read placeholders (`xlat`/`xlon`/`z0mav`/`z0hav`/
`albedoav`); those come from `scm_in` via the day-scalar table.
"""
function namelist(c::MOSAiCAYiLCase; root = data_root())
    path = namoptions_path(c; root)
    isfile(path) || error("No namoptions at $path")
    out = Dict{String, String}()
    for line in eachline(path)
        stripped = strip(first(split(line, '!')))
        (isempty(stripped) || startswith(stripped, '&') || stripped == "/") && continue
        parts = split(stripped, '=', limit = 2)
        length(parts) == 2 || continue
        out[strip(parts[1])] = strip(parts[2])
    end
    isempty(out) && error("Parsed no key = value pairs from $path")
    return out
end

function _namelist_number(::Type{T}, nl, key, path_hint) where {T}
    haskey(nl, key) || error("`$key` is not in the AYiL namoptions ($path_hint)")
    raw = replace(nl[key], "d" => "e", "D" => "e")
    value = tryparse(T, raw)
    isnothing(value) && error("`$key = $(nl[key])` is not a $T")
    return value
end

"""Namelist `xlat` [degrees] — a placeholder; use [`latitude`](@ref) for physics."""
namelist_latitude(c::MOSAiCAYiLCase; root = data_root()) =
    _namelist_number(Float64, namelist(c; root), "xlat", namoptions_path(c; root))

"""Namelist `xlon` [degrees] — a placeholder; use [`longitude`](@ref) for physics."""
namelist_longitude(c::MOSAiCAYiLCase; root = data_root()) =
    _namelist_number(Float64, namelist(c; root), "xlon", namoptions_path(c; root))
