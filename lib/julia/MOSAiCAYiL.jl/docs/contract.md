# MOSAiCAYiL contract

Facts that disagree between the JAMES paper, AYiL DALES (`dales_ayil/src/`), and
the Zenodo `ayil_config_input_results` namelists. The Fortran that wrote the
archive is the authority for what the reference simulations did.

DALES paths below are `MOSAiC_AYiL/dales_ayil/src/`.

## Clocks

| Name | Seconds | Role |
|---|---|---|
| `PUBLISHED_RUNTIME_S` | 7200 | Zenodo `profiles.001.nc` / published `namoptions` run length. `t_end(case)` is this. |
| `PAPER_RUNTIME_S` | 10800 | Paper protocol, 3 h (Schnierstein et al. 2024 §2.3.1). This repo's regeneration default. |
| `EVALUATION_S` | 5400 | Paper Appendix C evaluation time (1.5 h). |
| `PROFILES_TIME` | `300:300:7200` | Published profile times. |

Do not read `t_end` from a namelist. The published comparison clock is 7200 s.

## Namelist placeholders vs `scm_in`

On all 190 days the namelist writes `xlat = 78.41`, `xlon = 8.47`,
`z0mav`, `z0hav`, `albedoav`. DALES overwrites those every step from `scm_in`
(`modtimedep.f90`). Physics in this package uses the day-scalar table
(`lat`/`lon`/`mom_rough`/`heat_rough`/`albedo`), not the namelist.

Nudging (`tb_taunudge = 10800`, `tb_zmidnudge = 300`, `tb_zminnudge = -1`) *is*
what ran, on 190/190 days. `tb_minzinv`/`tb_maxzinv` are Fortran defaults
(100 m / 5000 m), absent from the namelists.

## Ice initialization diameter

Paper §2.3.2 places ice at **55 μm**. The AYiL DALES default `d_ci` used by the
runs that wrote the archive is **60 μm**. Both numbers are stored
(`PAPER_ICE_INIT_DIAMETER_M`, `DALES_D_CI_M`). Do not collapse them.

## Inversion

Paper eq. (7) writes max `∂Θ_v/∂z`. AYiL `modtestbed.f90` `testbednudge`
(centred difference at lines 1521–1543) uses `∂θ_l/∂z` on 100–5000 m, liquid-only
`θ_l`. [`inversion_height`](@ref) implements the subroutine that ran.

## Surface

Paper §2.2.4 and AYiL `modsurface.f90` are the same `l_surficefrac` scheme:
two skins (ice from MetCity, ocean `max(T_ice, −1.8 °C)`), ice-fraction
weighting, Grachev 2007. One blended `tskin` for the heat flux
(`modsurface.f90:891-905`). Humidity is **not** `q_sat` of that blend: it is
`qseaicefrctsurf` (`modsurface.f90:1304-1319`), a vapour-pressure blend

```
e_s = f · e_sat,ice(T_seaice) + (1 − f) · e_sat,liq(T_ocean)
q_sat = (R_d / R_v) · e_s / p_s
```

with ice Tetens only when `T_seaice < T_melt`, and `q_sat = (R_d/R_v) es/ps`
(not `es/(ps-es)`). `z0` comes from `scm_in` `mom_rough`/`heat_rough`.

## Moisture

DALES nudges `q+ql`. ClimaAtmos `q_tot` is `q+ql+qi`. Thermodynamic horizontal
advection (`tadv`, `qadv+ladv+iadv`) is identically zero on 190/190 days;
momentum advection is not.

## Initial density (ClimaAtmos setup)

[`scm_in_air_density`](@ref) is the mutually consistent ERA5 column from
`pressure_f` and `T_v` (design.md §8) and is the **extension default**.
[`les_density`](@ref) is `profiles.001.nc` `rhof` at t = 300 s. Never `rhobf`.

## Grid

The vertical grid is the same 287 faces on all 190 days. Production faces are
the stored [`LES_FACES`](@ref) (`Float32`, top face `11949.301`).
[`stretch_faces`](@ref) is the paper Appendix A formula and is **not**
bit-identical in the stretch. `mosaic_grid(FT; faces)` takes a face vector only
— compose `truncate_faces_to_top` / `coarsen_faces_to_dz_min` yourself; there is
no parallel `z_top` / `dz_min` keyword and no per-day grid.
