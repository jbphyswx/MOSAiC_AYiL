```@meta
CurrentModule = MOSAiCAYiL
```

# Thermodynamics

The package carries DALES's own thermodynamics, dependency-free, behind generic verbs
dispatched on a backend. [`MOSAiCAYiL.DefaultThermodynamicsBackend`](@ref) is the physics of
the AYiL runs; an extension can dispatch the same verbs on its own parameter set.

```@example thermo
using MOSAiCAYiL: MOSAiCAYiL as MA
b = MA.DefaultThermodynamicsBackend()

MA.R_d(b), MA.cp_d(b), MA.L_v0(b), MA.molmass_ratio(b)
```

Every constant is read from [`MOSAiCAYiL.DALES_CONSTANTS`](@ref), which is transcribed from
`modglobal.f90:73-101` and `modmicrodata3.f90:163-164`. `molmass_ratio` is `ε = R_d/R_v ≈
0.622`, the way DALES writes it everywhere; the reciprocal 1.608 is equally common elsewhere
and silently wrong here.

Each verb takes an optional `FT`:

```@example thermo
MA.R_d(b, Float32), MA.exner(b, 9.0f4)
```

## Saturation vapour pressure

DALES uses two formulations, in two places, and which one applies where is part of
reproducing the archive.

- The interior evaluates **Murphy & Koop (2005)**, which DALES tabulates on 0.2 K and
  interpolates: [`saturation_vapor_pressure_liq`](@ref) and
  [`saturation_vapor_pressure_ice`](@ref).
- `modsurface.f90` uses **Tetens/Murray (1967)** at every one of its saturation sites:
  [`tetens_saturation_vapor_pressure`](@ref).

![Saturation vapour pressure](assets/saturation.png)

They agree to about a tenth of a percent near 273 K and separate in the cold — 4.3% at
220 K.

```@example thermo
T = 250.0
MA.saturation_vapor_pressure_liq(b, T), MA.tetens_saturation_vapor_pressure(b, T)
```

## Saturation specific humidity

Two conventions, also from two places:

```@example thermo
p, e = 1.0e5, MA.saturation_vapor_pressure_liq(b, 270.0)
interior = MA.q_vap_saturation_from_pressure(b, e, p)   # ε e / (p − (1−ε) e)
surface  = MA.surface_q_vap_saturation(b, e, p)         # ε e / p
interior, surface
```

The surface form drops the `(1−ε)e` term the interior keeps
(`modsurface.f90:1304-1319`). Use each where DALES uses it.

## Potential temperature and saturation adjustment

`θ_l` is liquid-only, as `modtestbed.f90:701-702` has it:

```@example thermo
p, θ_l, q_liq = 9.0e4, 268.0, 1.0e-4
T = MA.temperature_from_liquid_pottemp(b, θ_l, p, q_liq)
T, MA.liquid_pottemp(b, T, p, q_liq)
```

[`saturation_adjust_pθq`](@ref) solves `(p, θ_l, q_tot)` for `(T, q_liq, q_ice)`:

```@example thermo
MA.saturation_adjust_pθq(b, 1.0e5, 275.0, 1.0e-2)
```

It iterates Newton on `T` with `dθ_l/dT` taken as a difference over 0.002 K, which is what
`icethermo0` does. Under SB3 the archive saturated over **liquid alone** — `qsatur = qvsl1`
— with ice carried separately, and `λ = 1` reproduces that. The general mixed-phase form is
available by passing `λ`, or by letting it default to
[`liquid_fraction`](@ref) over the 253–268 K range.

## Hydrostatic pressure

`profiles.001.nc` stores `presh`, the **half-level** pressure. The centre pressure comes
from one hydrostatic step anchored on it:

```julia
p = MA.pressure_from_face(presh, rhof, zt, zm)
```

[`pressure_fromztop`](@ref) is the port of DALES's own `fromztop`, integrating from `ps`
through the column and returning both branches:

```julia
(; presf, presh) = MA.pressure_fromztop(ps, θ, q_tot, q_liq, zt)
```

`θ` there is the **dry** potential temperature, DALES's `th0av = θ_l + (L_v/c_p) q_l / Π`.
On 20200503 this reconstructs the archive's own `presh` to 9.6e-6 relative.

## Surface

The AYiL surface is a two-skin blend, and the humidity blends two **vapour pressures**
before saturating:

```@example thermo
f, T_ocean, T_seaice, ps = 0.99, 271.35, 258.8, 1.0e5
MA.surface_temperature(f, T_ocean, T_seaice), MA.qseaicefrctsurf(f, T_ocean, T_seaice, ps)
```

`e_s = f e_sat,ice(T_seaice) + (1−f) e_sat,liq(T_ocean)`, then `q_sat = ε e_s / p_s`. This
differs from saturating at the blended temperature, `e_s` being exponential in `T`.
