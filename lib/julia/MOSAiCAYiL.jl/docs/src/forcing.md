```@meta
CurrentModule = MOSAiCAYiL
```

# The forcing of a day

[`MOSAiCAYiL.testbed_forcing`](@ref) returns the ERA5 testbed forcing one AYiL day was run
with: the state profiles, the large-scale advective tendencies, the geostrophic wind, and
the surface conditions, on an ascending height axis.

```julia
using MOSAiCAYiL: MOSAiCAYiL as MA

f = MA.testbed_forcing("20200503")
f.z                        # 3040 levels, 2 m to 85 km, ascending
f.ta, f.hus, f.ua, f.va    # temperature, total water, wind
f.p, f.o3, f.n_ccn
f.wa                       # vertical velocity
f.tntha, f.tnhusha         # large-scale horizontal advection of heat and moisture
f.ug, f.vg
f.surface.ps, f.surface.t_skin, f.surface.sea_ice_fraction
```

`scm_in` stores its levels **top-down** from about 85 km, and the count is a property of the
day: 3037 on 9 days, 3038 on 79, 3039 on 48, 3040 on 21, 3041 on 24, 3042 on 9. Everything
here comes back ascending.

Each file is one 05:00–11:00 UTC composite written twice. The two records are bitwise
identical on all 190 days apart from `time`, `second` and `base_time`, so `time_index`
selects between copies of the same thing.

## Derived fields

- `hus` is `q + ql + qi`. DALES's own `qt` is `q + ql`, with ice carried separately.
- `wa` follows DALES: vapour-only `T_v = T(1 + 0.61 q)`, then `w = -ω R_d T_v / (p g)`.
- `tnhusha` is `qadv + ladv + iadv`.

Surface fluxes that are netCDF fill come back as `missing`:

```julia
f.surface.sensible_heat_flux === missing    # true on every day; DALES computed its own
```

## The other 50 variables

`testbed_forcing` surfaces 35 of `scm_in`'s 77 variables. The rest — `pressure_h`,
`height_h`, `q_skin`, `t_sea_ice`, the soil and vegetation fields, the net radiative fluxes —
are reachable by name:

```julia
MA.read_variable("fradLWnet", "20200503"; file = :scm_in)
MA.read_variable("t_soil", "20200503"; file = :scm_in)
```

[`MOSAiCAYiL.SCM_IN`](@ref) is the full table, with the name and units of each. Two entries
record what the file itself gets wrong: `q_skin` carries its units and its long name in each
other's attribute, and `sv` is labelled `whatever`.

## The surface, and getting onto your own grid

ERA5's column starts at **2 m**; DALES's grid starts at 5 m. Nothing defines *air* at
`z = 0`. What exists at the ground is the **skin**, a separate field:

```julia
MA.surface_temperature(f)   # the skin, (1-f) T_ocean + f T_seaice
MA.qseaicefrctsurf(f)       # its saturation humidity
f.surface.ps
f.surface.z0_momentum, f.surface.z0_heat
```

`scm_in` also carries `t_soil` and `t_sea_ice` on
four levels, but those are interior fields, unused at `isurf = 2`.

[`MOSAiCAYiL.surface_state`](@ref) packages the ground values under the same field names, and
[`MOSAiCAYiL.forcing_with_surface`](@ref) prepends them so a profile runs 0 → top in one
array. Index 1 is then the skin and 2 onward the air. On 20200503:

| z | | T | q |
|---|---|---|---|
| 0 m | surface (skin) | 258.775 K | 1.076e-3 |
| 1 m | air, extrapolated | 257.983 K | 9.556e-4 |
| 2 m | air, ERA5's lowest level | 257.922 K | 9.511e-4 |
| 5 m | air, DALES's first level | 257.738 K | 9.377e-4 |

Put the forcing on your own levels the way DALES did — linearly in height:

```julia
MA.interpolate_forcing(f, z)          # any ascending z, in metres
```

Below 2 m or above the top it extrapolates the two nearest levels, which is what DALES's own
unclamped weight gives.

### Where the flux comes from

The skin-to-air step is the surface layer, and it is what drives the fluxes. AYiL runs
`isurf = 2`: the skin is **prescribed** from observations and the fluxes are **computed**
(`scm_in`'s `sfc_sens_flx`/`sfc_lat_flx` are netCDF fill on all 190 days, read back as
`missing`).

```
thlflux = -(thl0(1) - tskin) / ra                                modsurface.f90:935
ra      = 1 / (Cs |U(z₁)|)                                                    :867
Cs      = κ² / {[ln(z₁/z0m) - ψm(...)] · [ln(z₁/z0h) - ψh(...)]}          :858-860
```

Every term is evaluated at the **model's own first level** `z₁` — 5 m in DALES. The 2 m
level plays no part: it is where the data starts, not where the flux is defined.

## Air density

```julia
z, ρ = MA.scm_in_air_density(f)      # from pressure_f, t_local and (q, ql, qi)
z, ρ = MA.les_density("20200503")    # profiles.001.nc `rhof` at t = 300 s
```

`scm_in_air_density` uses one mutually consistent ERA5 column: `T_v` from the file's own
condensate, then `ρ = p / (R_d T_v)`. `ps` and `pressure_f` are separate ERA5 fields, so this
integrates nothing.

`rhobf` and `rhobh` are DALES's anelastic base state — a reference profile. Air density is
`rhof`.

## Writing a forcing out

[`MOSAiCAYiL.write_forcing_file`](@ref) stores what `testbed_forcing` returns, plus the
nudging parameters, so the file reconstructs a forcing on its own:

```julia
MA.write_forcing_file("day.nc", MA.case("20200503"))
g = MA.read_forcing_file("day.nc")
g.nudging      # (; timescale, ramp_depth, z_min)
```

The units written are the package's own, as [`MOSAiCAYiL.SCM_IN`](@ref) gives them: a number
density is `m^-3`, an albedo is `1`. A surface field that is `missing` is left out of the
file, and reads back as `missing`.

## Nudging

DALES relaxes toward these profiles above a diagnosed inversion, on a 3 h timescale, over a
300 m ramp:

```@example forcing
using MOSAiCAYiL: MOSAiCAYiL as MA
MA.nudging_parameters(MA.case("20200503"))
```

`z_min < 0` is DALES's flag for diagnosed-inversion mode, which is what ran on all 190 days.
The inversion is the largest centred `∂θ_l/∂z` between
[`MOSAiCAYiL.INVERSION_SEARCH_MIN`](@ref) and [`MOSAiCAYiL.INVERSION_SEARCH_MAX`](@ref).
[`MOSAiCAYiL.inversion_height`](@ref) computes it, and every day's value is tabulated — see
[Facts with no I/O](facts.md).
