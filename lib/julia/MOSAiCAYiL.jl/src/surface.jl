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

"""
    surface_state(forcing; backend)

The surface boundary condition of a day at `z = 0`, under the names
[`testbed_forcing`](@ref) uses: `ta` the skin temperature
([`surface_temperature`](@ref)), `q` and `hus` its saturation humidity
([`qseaicefrctsurf`](@ref)), `p` the surface pressure `ps`, and zero wind and condensate.

This is a surface, not the air continued downward. `ps` is also the LES column's surface pressure:
`profiles.001.nc` `presh[1]` equals it bit-for-bit on 190/190 days
(`modthermodynamics.f90:372`).
"""
function surface_state(forcing; backend = DefaultThermodynamicsBackend())
    FT = eltype(forcing.ta)
    q_s = FT(qseaicefrctsurf(forcing; backend))
    return (;
        z = zero(FT),
        ta = FT(surface_temperature(forcing)),
        hus = q_s,
        q = q_s,
        ql = zero(FT),
        qi = zero(FT),
        ua = zero(FT),
        va = zero(FT),
        p = FT(forcing.surface.ps),
        wa = zero(FT),
    )
end

"""
    forcing_with_surface(forcing; backend)

A day's forcing with [`surface_state`](@ref) prepended, so every profile runs from the
ground to the top of the ERA5 column in one array.

Index 1 is the skin and indices 2 onward are the air, which are different quantities.
To drive a model, interpolate the
air with [`interpolate_forcing`](@ref) and pass [`surface_state`](@ref) to its surface
scheme.

`o3`, `n_ccn` and the large-scale terms (`tntha`, `tnhusha`, `tnua`, `tnva`, `ug`, `vg`)
hold the lowest level. `p` at the ground is `ps`, which sits below ERA5's `pressure_f` at
2 m on 92 of the 190 days, those being separate ERA5 products.
"""
function forcing_with_surface(forcing; kwargs...)
    s = surface_state(forcing; kwargs...)
    from_ground(field, value) = vcat(value, field)
    held(field) = vcat(first(field), field)
    return (;
        z = from_ground(forcing.z, s.z),
        ta = from_ground(forcing.ta, s.ta),
        hus = from_ground(forcing.hus, s.hus),
        q = from_ground(forcing.q, s.q),
        ql = from_ground(forcing.ql, s.ql),
        qi = from_ground(forcing.qi, s.qi),
        ua = from_ground(forcing.ua, s.ua),
        va = from_ground(forcing.va, s.va),
        p = from_ground(forcing.p, s.p),
        o3 = held(forcing.o3),
        n_ccn = held(forcing.n_ccn),
        wa = from_ground(forcing.wa, s.wa),
        tntha = held(forcing.tntha),
        tnhusha = held(forcing.tnhusha),
        tnua = held(forcing.tnua),
        tnva = held(forcing.tnva),
        ug = held(forcing.ug),
        vg = held(forcing.vg),
        forcing.surface,
    )
end
