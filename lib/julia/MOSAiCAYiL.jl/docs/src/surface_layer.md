```@meta
CurrentModule = MOSAiCAYiL
```

# The surface layer

The AYiL runs prescribe the skin temperature and **compute** the fluxes: `isurf = 2`, with
`scm_in`'s `sfc_sens_flx` and `sfc_lat_flx` netCDF fill on all 190 days. So the surface flux
is not something the archive hands you — it is something DALES solved, and this page is that
solve.

`lmostlocal = false`, so one domain-mean Obukhov length is found per step from the slab-mean
level-1 state and copied everywhere.

```julia
using MOSAiCAYiL: MOSAiCAYiL as MA

MA.dales_surface_layer("20200503")
# (; L, ζ, Rib, C_m, C_s, r_a, ustar, θ_l_flux, q_tot_flux, θ_l_scale, q_scale)
```

## On your own grid

The flux is defined at the model's **own first level**, not at a fixed height. DALES's is
5 m; if yours is 100 m, the surface layer is solved between the skin and 100 m, and the
answer differs.

```julia
MA.surface_layer_fluxes(;
    θ_l = 258.0, q_tot = 1.0e-3, wind_speed = 4.0, z = 100.0,
    θ_l_skin = MA.surface_pottemp(MA.case("20200503")),
    q_skin = MA.qseaicefrctsurf(MA.testbed_forcing("20200503")),
    z0m = 8.0e-4, z0h = 8.5e-4,
)
```

`θ_l_flux` and `q_tot_flux` are kinematic and upward-positive. `θ_l_flux` is a **potential**
temperature flux — DALES's own inverse is too (`modtestbed.f90:572` divides by `c_p ρ` with no
Exner), so a sensible heat flux differs by `Π ≈ 1.005` at the surface.

## The stability functions

`larcticstab = true` selects Grachev et al. (2007) on the stable side, stated for
`0 ≤ ζ < 100`. The returned `ζ` says where a result sits in that range; nothing is clamped.

```@example surface
using MOSAiCAYiL: MOSAiCAYiL as MA
ζ = [-1.0, -0.1, 0.0, 0.1, 1.0, 10.0]
[MA.psim.(ζ) MA.psih.(ζ) MA.phim.(ζ) MA.phih.(ζ)]
```

Two things about them are easy to get wrong:

- **`φ` is uncapped on the arctic branch.** The cap of 6 at `ζ ≥ 1` belongs to the non-arctic
  branch alone. Arctic `φ_m` grows without bound, while arctic `φ_h` approaches 6 from below
  and never reaches it.
- **`ψ` and `φ` are not mutually consistent here**, which the DALES source itself notes
  (`modsurface.f90:1617-1621`). They are kept as written rather than reconciled.

## The Obukhov solve

[`MOSAiCAYiL.obukhov_length`](@ref) is Newton on
`Rib = ζ [ln(z/z0h) − ψ_h(ζ) + ψ_h(z0h/L)] / [ln(z/z0m) − ψ_m(ζ) + ψ_m(z0m/L)]²`, with the
derivative as a central difference at `L(1 ± 0.001)` — DALES's own method, not an analytic
one. `Rib = 0` returns the cap of `1e6`, and `L` is reset to `sign(Rib)·0.01` whenever
`Rib·L < 0`.

## Against the archive

On a stable day and an unstable one, at `t = 1200 s`:

| | `L` | `u*` | `wθ` | `wq` |
|---|---|---|---|---|
| 20200503, unstable | 1.9 % | 2.4 % | 6.6 % | 5.1 % |
| 20200720, stable | 5.9 % | 2.5 % | 1.8 % | 5.0 % |

against `tmser.001.nc`'s `obukh`, `ustar`, `wtheta` and `wq`. The residual is what the
comparison supports: the reference is a 60 s sample of a scheme carrying the previous step's
Obukhov length, against a 300 s slab mean solved from the reset.
