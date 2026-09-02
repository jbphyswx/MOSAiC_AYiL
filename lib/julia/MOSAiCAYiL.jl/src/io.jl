"""
    io.jl

Serialization of the testbed forcing one AYiL day is built from.

[`write_forcing_file`](@ref) writes exactly what [`testbed_forcing`](@ref) returns and
[`read_forcing_file`](@ref) reads it back in the same shape. Missing surface
fluxes are omitted from the file.
"""

"""
Profile fields of a forcing object, with the units they are written in.

The package's own spellings, as [`SCM_IN`](@ref) gives them
"""
const FORCING_PROFILE_UNITS = (;
    z = "m",
    ta = "K",
    hus = "kg/kg",
    q = "kg/kg",
    ql = "kg/kg",
    qi = "kg/kg",
    ua = "m/s",
    va = "m/s",
    p = "Pa",
    o3 = "kg/kg",
    n_ccn = "m^-3",
    wa = "m/s",
    tntha = "K/s",
    tnhusha = "kg/kg/s",
    tnua = "m/s^2",
    tnva = "m/s^2",
    ug = "m/s",
    vg = "m/s",
)

"""Surface fields of a forcing object, with the units they are written in."""
const FORCING_SURFACE_UNITS = (;
    ps = "Pa",
    trajectory_latitude = "degrees_north",
    trajectory_longitude = "degrees_east",
    albedo = "1",
    albedo_snow = "1",
    snow = "m",
    z0_momentum = "m",
    z0_heat = "m",
    sea_ice_fraction = "1",
    t_skin = "K",
    t_skin_ocean = "K",
    t_skin_seaice = "K",
    open_sst = "K",
    land_sea_mask = "1",
    sensible_heat_flux = "W/m^2",
    latent_heat_flux = "W/m^2",
)

"""
    write_forcing_file(path, forcing; date, nudging)

Write `forcing` — a [`testbed_forcing`](@ref) result — to `path`, returning it.

`nudging` is stored alongside so the file reconstructs a forcing without the namelist.
A surface field that is `missing` in `forcing` is left out of the file entirely.
"""
function write_forcing_file(
    path::AbstractString,
    forcing;
    date::AbstractString = "",
    nudging = nothing,
)
    mkpath(dirname(abspath(path)))
    NC.NCDataset(path, "c") do ds
        ds.attrib["title"] = "MOSAiC AYiL testbed forcing for one day"
        isempty(date) || (ds.attrib["date"] = date)
        if !isnothing(nudging)
            ds.attrib["nudging_timescale"] = Float64(nudging.timescale)
            ds.attrib["nudging_ramp_depth"] = Float64(nudging.ramp_depth)
            ds.attrib["nudging_z_min"] = Float64(nudging.z_min)
        end

        NC.defDim(ds, "z", length(forcing.z))
        for name in keys(FORCING_PROFILE_UNITS)
            values = getproperty(forcing, name)
            v = NC.defVar(ds, String(name), eltype(values), ("z",))
            v.attrib["units"] = getproperty(FORCING_PROFILE_UNITS, name)
            v[:] = values
        end
        for name in keys(FORCING_SURFACE_UNITS)
            value = getproperty(forcing.surface, name)
            value === missing && continue
            v = NC.defVar(ds, String(name), typeof(value), ())
            v.attrib["units"] = getproperty(FORCING_SURFACE_UNITS, name)
            v[] = value
        end
    end
    return path
end

write_forcing_file(
    path::AbstractString,
    c::MOSAiCAYiLCase;
    root = data_root(),
    time_index::Int = 1,
) = write_forcing_file(
    path,
    testbed_forcing(c; root, time_index);
    date = date_string(c),
    nudging = nudging_parameters(c),
)

"""
    read_forcing_file(path)

A forcing object from a file written by [`write_forcing_file`](@ref), shaped as
[`testbed_forcing`](@ref) returns plus the `nudging` the file carries.
"""
function read_forcing_file(path::AbstractString)
    isfile(path) || error("No MOSAiC forcing file at $path")
    return NC.NCDataset(path, "r") do ds
        for name in keys(FORCING_PROFILE_UNITS)
            haskey(ds, String(name)) ||
                error("$path has no `$name`; it was not written by `write_forcing_file`.")
        end
        profiles = NamedTuple{keys(FORCING_PROFILE_UNITS)}(
            map(n -> Array(ds[String(n)]), keys(FORCING_PROFILE_UNITS)),
        )
        surface = NamedTuple{keys(FORCING_SURFACE_UNITS)}(
            map(keys(FORCING_SURFACE_UNITS)) do n
                haskey(ds, String(n)) ? ds[String(n)][] : missing
            end,
        )
        nudging = if haskey(ds.attrib, "nudging_timescale")
            (;
                timescale = ds.attrib["nudging_timescale"],
                ramp_depth = ds.attrib["nudging_ramp_depth"],
                z_min = ds.attrib["nudging_z_min"],
            )
        else
            nothing
        end
        return (; profiles..., surface, nudging)
    end
end
