```@meta
CurrentModule = MOSAiCAYiL
```

# ClimaAtmos

`using ClimaAtmos` adds methods on the types this package defines: a forcing, a setup, an
insolation, a Coriolis profile, the parameter overrides and a column grid. The extension
assembles no `AtmosModel` and calls no `solve_atmos!`.

```julia
using ClimaAtmos
using MOSAiCAYiL: MOSAiCAYiL as MA

c = MA.case("20200503")
FT = Float64

params  = MA.ClimaAtmos_MOSAiCAYiL_params(FT, c)
forcing = MA.ClimaAtmosMOSAiCAYiLForcing(FT, c)
setup   = MA.ClimaAtmosMOSAiCAYiLSetup(FT, c)
grid    = MA.ClimaAtmos_MOSAiCAYiL_grid(FT)
```

## The grid

`z` is the vertical specification: a vector of cell faces [m], a ClimaCore `IntervalMesh`, or
a grid, which is returned unchanged. It defaults to the DALES column, and any other column is
yours to build — with ClimaCore's own stretching, or by hand:

```julia
MA.ClimaAtmos_MOSAiCAYiL_grid(FT; z = range(0, 4000; length = 41))

mesh = ClimaAtmos.CC.Meshes.IntervalMesh(
    ClimaAtmos.CC.Domains.IntervalDomain(
        ClimaAtmos.CC.Geometry.ZPoint(0.0),
        ClimaAtmos.CC.Geometry.ZPoint(4000.0);
        boundary_names = (:bottom, :top),
    ),
    ClimaAtmos.CC.Meshes.GeneralizedExponentialStretching(50.0, 500.0);
    nelems = 40,
)
MA.ClimaAtmos_MOSAiCAYiL_grid(FT; z = mesh)
```

## Parameters

DALES's constants are handed to ClimaParams as overrides, keyed by ClimaParams' own names.
The mapping is a mapping, not a second table of numbers, so a correction to
[`MOSAiCAYiL.DALES_CONSTANTS`](@ref) cannot leave a stale value behind.

`Thermodynamics` reads `gas_constant_dry_air` and `isobaric_specific_heat_dry_air`; RRTMGP's
gas optics reads `molar_mass_*` and `adiabatic_exponent_dry_air`. Both pairs are set and
kept consistent, the molar masses being derived from the gas constants.

Two differences survive any parameter choice: DALES holds `L_v` constant where
`Thermodynamics` uses `L_v(T)`, so matching at `T_0` leaves CliMA 1.2% high at 260 K, 2.1% at
250 K and 4.0% at 230 K; and DALES's saturation vapour pressure is Tetens/Murray where
`Thermodynamics` integrates Clausius–Clapeyron.

The day's CCN number rides along as
`prescribed_cloud_droplet_number_concentration`.

## Forcing

Relaxation of temperature, total water and horizontal wind toward the ERA5 profiles above a
diagnosed inversion, plus horizontal advection and large-scale subsidence. The profiles have
no time axis: each `scm_in` file is one composite, so the cache samples once, and forcing at
`t = 0` is applied.

Only the diagnosed-inversion mode is implemented. A positive `nudging.z_min` asks for
DALES's fixed-ramp mode and errors.

## Setup

The initial state is the ERA5 column. Density defaults to
[`MOSAiCAYiL.scm_in_air_density`](@ref); pass `density = MA.les_density(date)` for the
archive's `rhof` at t = 300 s.

Liquid is split off at initialization by saturating with `Thermodynamics`, with the file's
own ice held out:

```julia
q_liq = max(0, (q_tot - q_ice) - q_sat_liq(T, ρ))
```

## Insolation

The reference runs froze the zenith angle at 11:00 UTC (`lcnstzenithtime = .true.`,
`cnstzenithtime = 11`) on all 190 days, so
[`MOSAiCAYiL.ClimaAtmosMOSAiCAYiLInsolation`](@ref) holds `cos_zenith` and the beam-normal flux fixed.
Polar night is `(eps(FT), 0)`: no incoming flux, with the positive zenith cosine RRTMGP
requires.

## Comparing against the archive

[`MOSAiCAYiL.ClimaAtmos_MOSAiCAYiL_field`](@ref) builds a ClimaAtmos diagnostic short name out of the
archive, so the two sides carry the same name and units:

```julia
MA.ClimaAtmos_MOSAiCAYiL_field("clw", "20200503")     # from sv005
MA.ClimaAtmos_MOSAiCAYiL_field("hus", "20200503")     # qt + the ice, rain, snow and graupel scalars
MA.ClimaAtmos_MOSAiCAYiL_field("ta", "20200503")      # from thl and the centre pressure
MA.ClimaAtmos_MOSAiCAYiL_field("rlds", "20200503")    # surface longwave down
MA.ClimaAtmos_MOSAiCAYiL_translated_names()
```

`ql_all` and `qi_all` have no ClimaAtmos name, so the extension registers them: cloud liquid
plus rain, and cloud ice plus snow, per mass of moist air.

## Gated tests

The extension's tests sit outside `Pkg.test()`:

```bash
julia --project=test/environments/clima test/environments/clima/clima_ext.jl
```
