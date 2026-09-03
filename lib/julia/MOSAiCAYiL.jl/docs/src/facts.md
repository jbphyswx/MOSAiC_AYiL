```@meta
CurrentModule = MOSAiCAYiL
```

# Facts with no I/O

Per-day numbers are committed as tables and looked up by date. These need no artifact, no
network and no file handle.

```@example facts
using MOSAiCAYiL: MOSAiCAYiL as MA

c = MA.case("20200503")
MA.day_scalars(c)
```

```@example facts
MA.day_metadata(c)
```

Every accessor takes a `Date`, a `yyyymmdd` string or a case:

```@example facts
MA.latitude("20200503") == MA.latitude(c) == MA.latitude(MA.MOSAiCAYiL_dates[113])
```

## The surface scalars

Read from `scm_in` time record 1, one value per day. Longitude is wrapped to [-180, 180).

| accessor | |
|---|---|
| [`MOSAiCAYiL.latitude`](@ref), [`MOSAiCAYiL.longitude`](@ref) | the drift position |
| [`MOSAiCAYiL.t_skin`](@ref), [`MOSAiCAYiL.t_skin_ocean`](@ref), [`MOSAiCAYiL.t_skin_seaice`](@ref) | the two skins and their blend |
| [`MOSAiCAYiL.sea_ice_frct`](@ref) | ice fraction |
| [`MOSAiCAYiL.albedo`](@ref), [`MOSAiCAYiL.albedo_snow`](@ref), [`MOSAiCAYiL.snow`](@ref) | surface radiative state |
| [`MOSAiCAYiL.mom_rough`](@ref), [`MOSAiCAYiL.heat_rough`](@ref) | `z0` for momentum and heat |
| [`MOSAiCAYiL.ps`](@ref), [`MOSAiCAYiL.open_sst`](@ref) | surface pressure, open-water SST |
| [`MOSAiCAYiL.n_ccn`](@ref) | CCN number, uniform in z on every day |

These are the values DALES used. The namelist's `xlat`, `xlon`, `z0mav`, `z0hav`, `albedoav`,
`seaicefrct`, `ps` and `thls` are placeholders it overwrote every substep — see
[What the reference runs did](archive.md). [`MOSAiCAYiL.xday`](@ref) is the day of year the
insolation used, and [`MOSAiCAYiL.surface_pottemp`](@ref) is the skin potential temperature
DALES carries as `thls`.

## The day's metadata

```@example facts
MA.scm_in_levels(c), MA.inversion_height(c), MA.cloud_top(c)
```

- [`MOSAiCAYiL.scm_in_levels`](@ref) — the `scm_in` full-level count, 3037 to 3042.
- [`MOSAiCAYiL.inversion_height`](@ref) — the first LES record's inversion, on all 190 days.
- [`MOSAiCAYiL.cloud_top`](@ref) — the cloud top below that day's domain top.
- [`MOSAiCAYiL.tskin_obs`](@ref), [`MOSAiCAYiL.tskin_seaice_correction`](@ref) — the
  observed skin temperature and the correction built from it.
- [`MOSAiCAYiL.inp_fletcher_n`](@ref), [`MOSAiCAYiL.inp_fletcher_b`](@ref) — the day's
  ice-nucleus coefficients, estimated from the Polarstern observations.

![Inversion height and cloud top across the catalog](assets/catalog.png)

## Where a fact is undefined

Cloud tops exist for 73 of the 76 days a domain top is known for. On three days the cloud
reaches that top, so no top below it exists, and asking errors:

```@example facts
MA.CLOUD_TOP_UNDETERMINED
```

```@example facts
try
    MA.cloud_top("20200702")
catch e
    e.msg
end
```

The 76 days themselves are [`MOSAiCAYiL.best_dates`](@ref): the days whose reference ice is
reproducible, with the height each can be simulated to in
[`MOSAiCAYiL.BEST_SIMULATION_TOP_F`](@ref). The filters behind that table are runnable —
[`MOSAiCAYiL.best_z_maxs`](@ref) and [`MOSAiCAYiL.get_cloud_tops`](@ref) re-derive it from
the archive.

## Ensemble constants

Values that are the same on all 190 days live in `constants.jl` instead of a table:

```@example facts
MA.PUBLISHED_RUNTIME_S, MA.PROFILES_TIME, MA.INP_MEYERS_N, MA.SOIL_MOISTURE_BOUNDS
```

[`MOSAiCAYiL.DALES_CONSTANTS`](@ref) holds DALES's own parameters, transcribed from
`modglobal.f90` and `modmicrodata3.f90`:

```@example facts
MA.DALES_CONSTANTS
```
