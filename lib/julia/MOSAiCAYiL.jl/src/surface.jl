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

"""
    qseaicefrctsurf(f, T_ocean, T_seaice, ps; backend, T_melt)

Surface saturation specific humidity from AYiL `qseaicefrctsurf`
(`modsurface.f90:1304-1319`):

```
e_s = f · e_sat,ice(T_seaice) + (1 − f) · e_sat,liq(T_ocean)
q_sat = (R_d / R_v) · e_s / p_s
```

The vapour pressures are Tetens/Murray, which is what `modsurface.f90` uses at every one of
its saturation sites — not the Murphy–Koop form the interior thermodynamics uses. The
`(R_d/R_v)·e_s/p_s` is likewise the surface convention, dropping the `(1−ε)e` term the
interior keeps.

`e_sat,ice` is used only when `T_seaice < T_melt`, otherwise the liquid formula. With
`rs = 0` the surface is saturated, so this *is* `q_skin`.

This is not `q_sat` of the blended temperature: `e_s` is exponential in `T`.
"""
function qseaicefrctsurf(
    f::FT, T_ocean::FT, T_seaice::FT, ps::FT;
    backend = DefaultThermodynamicsBackend(), T_melt::FT = T_freeze(backend, FT),
) where {FT}
    esi = tetens_saturation_vapor_pressure(
        backend, T_seaice, T_seaice > T_melt ? Liquid() : Ice(); T_melt,
    )
    esw = tetens_saturation_vapor_pressure(backend, T_ocean, Liquid(); T_melt)
    es = f * esi + (one(FT) - f) * esw
    return surface_q_vap_saturation(backend, es, ps)
end

qseaicefrctsurf(forcing; backend = DefaultThermodynamicsBackend()) = qseaicefrctsurf(
    forcing.surface.sea_ice_fraction,
    forcing.surface.t_skin_ocean,
    forcing.surface.t_skin_seaice,
    forcing.surface.ps;
    backend,
)
