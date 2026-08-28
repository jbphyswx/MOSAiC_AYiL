"""
    surface.jl

AYiL DALES surface blending (`modsurface.f90`, `l_surficefrac`).

Paper §2.2.4 and this code are the same scheme: two skin temperatures (ice from
MetCity, ocean `max(T_ice, −1.8 °C)`), ice-fraction weighting, Grachev 2007.
The heat flux uses one blended skin; humidity blends two saturation vapour
pressures. `z0h = 0.1 z0m` is how the forcing files were *filled*; the package
reads `scm_in` `mom_rough`/`heat_rough`.
"""

"""
    surface_temperature(forcing)
    surface_temperature(f, T_ocean, T_seaice)

The skin temperature [K] of a blended sea-ice and open-ocean surface,
`(1 - f) T_ocean + f T_seaice`, as DALES does at `isurf = 2` with `l_surficefrac`
(`modsurface.f90:891-905`). `scm_in t_skin` is this blend.
"""
surface_temperature(f, T_ocean, T_seaice) = (1 - f) * T_ocean + f * T_seaice

surface_temperature(forcing) = surface_temperature(
    forcing.surface.sea_ice_fraction,
    forcing.surface.t_skin_ocean,
    forcing.surface.t_skin_seaice,
)

"""Tetens/Murray saturation vapour pressure [Pa] over liquid (DALES `at`, `bt`)."""
function esat_liquid(T::FT; 
    e_s0::FT = FT(DALES_CONSTANTS.e_s0), 
    a::FT = FT(DALES_CONSTANTS.a_liquid),
    b::FT = FT(DALES_CONSTANTS.b_liquid), 
    T_melt::FT = FT(DALES_CONSTANTS.T_melt)
) where {FT}
    return e_s0 * exp(a * (T - T_melt) / (T - b))
end

"""Tetens/Murray saturation vapour pressure [Pa] over ice (DALES `at_i`, `bt_i`)."""
function esat_ice(T::FT; 
    e_s0::FT = FT(DALES_CONSTANTS.e_s0), 
    a::FT = FT(DALES_CONSTANTS.a_ice),
    b::FT = FT(DALES_CONSTANTS.b_ice), 
    T_melt::FT = FT(DALES_CONSTANTS.T_melt)
) where {FT}
    return e_s0 * exp(a * (T - T_melt) / (T - b))
end

"""
    qseaicefrctsurf(f, T_ocean, T_seaice, ps)

Surface saturation specific humidity from AYiL `qseaicefrctsurf`
(`modsurface.f90:1304-1319`):

```
e_s = f · e_sat,ice(T_seaice) + (1 − f) · e_sat,liq(T_ocean)
q_sat = (R_d / R_v) · e_s / p_s
```

`e_sat,ice` is used only when `T_seaice < T_melt`, otherwise the liquid formula.
With `rs = 0` the surface is saturated, so this *is* `q_skin`.

This is not `q_sat` of the blended temperature: `e_s` is exponential in `T`.
"""
function qseaicefrctsurf(f::FT, T_ocean::FT, T_seaice::FT, ps::FT; T_melt::FT = FT(DALES_CONSTANTS.T_melt)) where {FT}
    esi = T_seaice > T_melt ? esat_liquid(T_seaice) : esat_ice(T_seaice)
    esw = esat_liquid(T_ocean)
    es = f * esi + (one(FT) - f) * esw
    return (FT(DALES_CONSTANTS.R_d) / FT(DALES_CONSTANTS.R_v)) * es / ps
end

function qseaicefrctsurf(forcing; T_melt = DALES_CONSTANTS.T_melt)
    return qseaicefrctsurf(
        forcing.surface.sea_ice_fraction,
        forcing.surface.t_skin_ocean,
        forcing.surface.t_skin_seaice,
        forcing.surface.ps;
        T_melt,
    )
end
