"""
    day_scalars.jl

Accessors for the committed structure-of-arrays in `generated/day_scalars.jl`.
Lookups are `searchsortedfirst` on the sorted 190-date catalog — no I/O.
"""

_day_index(c::MOSAiCAYiLCase) = date_index(c)
_day_index(d::Dates.Date) = date_index(d)
_day_index(date::AbstractString) = date_index(date)

_soa(field, i) = getfield(DAY_SCALARS, field)[i]

"""Latitude [degrees_north] of the drift on this day, `scm_in` `lat`."""
latitude(c) = _soa(:lat, _day_index(c))

"""Longitude [degrees_east] of the drift, `scm_in` `lon` wrapped to [-180, 180)."""
longitude(c) = _soa(:lon, _day_index(c))

"""Surface albedo, `scm_in` `albedo`. DALES overwrote the namelist's `albedoav` with this."""
albedo(c) = _soa(:albedo, _day_index(c))

"""Snow albedo, `scm_in` `albedo_snow`."""
albedo_snow(c) = _soa(:albedo_snow, _day_index(c))

"""Snow depth [m liquid equivalent], `scm_in` `snow`."""
snow(c) = _soa(:snow, _day_index(c))

"""Roughness length for momentum [m], `scm_in` `mom_rough`."""
mom_rough(c) = _soa(:mom_rough, _day_index(c))

"""Roughness length for heat [m], `scm_in` `heat_rough`."""
heat_rough(c) = _soa(:heat_rough, _day_index(c))

"""Sea-ice fraction, `scm_in` `sea_ice_frct`, weighting the two-skin surface blend."""
sea_ice_frct(c) = _soa(:sea_ice_frct, _day_index(c))

"""
Skin temperature [K], `scm_in` `t_skin`, which is the blend
`(1 - f) t_skin_ocean + f t_skin_seaice`. [`surface_temperature`](@ref) forms it.
"""
t_skin(c) = _soa(:t_skin, _day_index(c))

"""Open-ocean skin temperature [K], `scm_in` `t_skin_ocean`."""
t_skin_ocean(c) = _soa(:t_skin_ocean, _day_index(c))

"""Sea-ice skin temperature [K], `scm_in` `t_skin_seaice`, scaled to the MetCity observations."""
t_skin_seaice(c) = _soa(:t_skin_seaice, _day_index(c))

"""Open sea surface temperature [K], `scm_in` `open_sst`."""
open_sst(c) = _soa(:open_sst, _day_index(c))

"""Surface pressure [Pa], `scm_in` `ps`."""
ps(c) = _soa(:ps, _day_index(c))

"""
CCN number concentration [m^-3], `scm_in` `n_ccn`.

Uniform in height on every day, so one number describes the column.
"""
n_ccn(c) = _soa(:n_ccn, _day_index(c))

"""Per-day surface scalars as a NamedTuple, with no I/O."""
day_scalars(c) = (;
    lat = latitude(c),
    lon = longitude(c),
    albedo = albedo(c),
    albedo_snow = albedo_snow(c),
    snow = snow(c),
    mom_rough = mom_rough(c),
    heat_rough = heat_rough(c),
    sea_ice_frct = sea_ice_frct(c),
    t_skin = t_skin(c),
    t_skin_ocean = t_skin_ocean(c),
    t_skin_seaice = t_skin_seaice(c),
    open_sst = open_sst(c),
    ps = ps(c),
    n_ccn = n_ccn(c),
)
