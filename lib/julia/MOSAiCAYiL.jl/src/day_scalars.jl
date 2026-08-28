"""
    day_scalars.jl

Accessors for the committed structure-of-arrays in `generated/day_scalars.jl`.
Lookups are `searchsortedfirst` on the sorted 190-date catalog — no I/O.
"""

_day_index(c::MOSAiCAYiLCase) = date_index(c)
_day_index(d::Dates.Date) = date_index(d)
_day_index(date::AbstractString) = date_index(date)

_soa(field, i) = getfield(DAY_SCALARS, field)[i]

latitude(c) = _soa(:lat, _day_index(c))
longitude(c) = _soa(:lon, _day_index(c))
albedo(c) = _soa(:albedo, _day_index(c))
albedo_snow(c) = _soa(:albedo_snow, _day_index(c))
snow(c) = _soa(:snow, _day_index(c))
mom_rough(c) = _soa(:mom_rough, _day_index(c))
heat_rough(c) = _soa(:heat_rough, _day_index(c))
sea_ice_frct(c) = _soa(:sea_ice_frct, _day_index(c))
t_skin(c) = _soa(:t_skin, _day_index(c))
t_skin_ocean(c) = _soa(:t_skin_ocean, _day_index(c))
t_skin_seaice(c) = _soa(:t_skin_seaice, _day_index(c))
open_sst(c) = _soa(:open_sst, _day_index(c))
ps(c) = _soa(:ps, _day_index(c))
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
