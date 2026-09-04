# MOSAiCAYiL

Facts, archive access, and ClimaAtmos methods for Schnierstein et al. (2024)
MOSAiC **A Year in LES** (AYiL): 190 Arctic days of DALES large-eddy simulations.

This package owns the **data** and **facts** of the ensemble, plus ClimaAtmos
methods on types it defines. It does not assemble an `AtmosModel` /
`AtmosSimulation` and does not call `solve_atmos!`.

Full documentation: [`docs/src`](docs/src) — [reading](docs/src/reading.md),
[the forcing](docs/src/forcing.md), [the 3D fields](docs/src/fields3d.md),
[thermodynamics](docs/src/thermodynamics.md),
[what the reference runs did](docs/src/archive.md).

![Inversion height and cloud top over the MOSAiC drift](docs/src/assets/catalog.png)

## Julia version

Use the machine default `julia` (currently 1.12.x here). Compat is
`julia = "1.11, 1.12"`. This package is **not** pinned to `julia +1.11.9`
(that pin is TurbulenceConvection.jl / CalibrateEDMF.jl only).

```bash
cd lib/julia/MOSAiCAYiL.jl
julia --project=. -e 'using Pkg; Pkg.instantiate(); using MOSAiCAYiL'
```

## Data

Day directories come from the lazy Zenodo artifact
[10.5281/zenodo.10491362](https://doi.org/10.5281/zenodo.10491362)
(`ayil_config_input_results`). `MOSAiCAYiL.data_root()` defaults to
`MOSAiCAYiL.artifact_root()` (installs on first use, not at load).
`MOSAiCAYiL.data_available()` is true when that artifact is already on disk; it
does not download. A local tree is `data_root(; root = "...")` or
`testbed_forcing(c; root = "...")`.

```julia
MOSAiCAYiL.data_root(; root = "/path/to/ayil_config_input_results")
MOSAiCAYiL.testbed_forcing(c; root = "...")
```

Regenerate the committed day-scalar table with:

```bash
julia --project=gen -e 'include("gen/extract_day_scalars.jl"); write_day_scalars()'
# a local tree: write_day_scalars(; root = "/path/to/ayil_config_input_results")
```

## Facts with no I/O

Per-day numbers are committed tables, looked up by date — no artifact, no network, no file
handle. This is the figure above.

```julia
c = MOSAiCAYiL.case("20200503")
MOSAiCAYiL.latitude(c)          # 82.38144
MOSAiCAYiL.t_skin(c)            # 258.77515
MOSAiCAYiL.scm_in_levels(c)     # 3040 — a property of the day, 3037 to 3042
MOSAiCAYiL.inversion_height(c)  # 705.0
MOSAiCAYiL.cloud_top(c)
MOSAiCAYiL.day_scalars(c), MOSAiCAYiL.day_metadata(c)
```

## Reading

One call reaches every variable of the five archive files, under a readable name and with
the archive's unit mislabelling corrected:

```julia
MOSAiCAYiL.read_variable("t_local", "20200503"; file = :scm_in)   # ERA5 testbed forcing
MOSAiCAYiL.read_variable("sv008", "20200503")                     # profiles.001.nc
MOSAiCAYiL.read_variable("lwp_bar", "20200503"; file = :tmser)
```

`file` is `:scm_in`, `:profiles`, `:tmser`, `:mphys` or `:samptend`, and is required for the
handful of names that mean different things in different files. `testbed_forcing` is the
whole forcing of a day at once.

## 3D fields

`fielddump` output, either a directory of per-rank tiles or one assembled file. A day is
gigabytes per variable, so `open_fielddump` reads none of it and indexing pulls only the
tiles a request touches; `load_fielddump` materializes what you ask for.

```julia
MOSAiCAYiL.open_fielddump("path/to/run") do fd
    fd.dims["v"]                     # ("xt", "ym", "zt", "time") — the stagger is kept
    level  = fd.vars["thl"][:, :, 100, 1]
    column = fd.vars["w"][160, 160, :, :]
end

MOSAiCAYiL.load_fielddump("path/to/run"; vars = ["thl"], time_indices = 1:1)
```

The tile files stay open for the life of the handle, so repeated slicing does not reopen
them. Use the `do` form, or `close_fielddump`.

## Zarr

`using Zarr` adds reading and writing of Zarr v3 stores.

```julia
using Zarr
MOSAiCAYiL.open_fielddump("path/to/run") do fd
    MOSAiCAYiL.write_zarr("day.zarr", fd; chunks = (320, 80, 200, 4))
end
z = MOSAiCAYiL.open_zarr("day.zarr")
```

`chunks` has no default. Zarr decompresses a whole chunk to read any element of it, and
reading one horizontal level and reading one column want opposite shapes.

## The grid and the physics

Every day ran on the same 287 faces. [`LES_FACES`](src/grid.jl) is the file's own `Float32`
values.

![The DALES vertical grid](docs/src/assets/vertical_grid.png)

`DefaultThermodynamicsBackend` is DALES's own thermodynamics, dependency-free, with every
constant read from `DALES_CONSTANTS`. DALES uses two saturation formulations — Murphy–Koop
in the interior, Tetens/Murray at the surface — and which applies where is part of
reproducing the archive.

![Saturation vapour pressure](docs/src/assets/saturation.png)

## ClimaAtmos extension

```julia
using ClimaAtmos
using MOSAiCAYiL
c = MOSAiCAYiL.case("20200503")
fd = MOSAiCAYiL.testbed_forcing(c)                     # read scm_in once, share it
forcing = MOSAiCAYiL.ClimaAtmosMOSAiCAYiLForcing(Float64, c; forcing = fd)
setup = MOSAiCAYiL.ClimaAtmosMOSAiCAYiLSetup(Float64, c; forcing_data = fd)
grid = MOSAiCAYiL.ClimaAtmos_MOSAiCAYiL_grid(Float64)  # z = faces, an IntervalMesh, or a grid
```

Default initial density is `scm_in_air_density`. Pass
`density = MOSAiCAYiL.les_density(c)` for `rhof` at t = 300 s. Never `rhobf`.

Gated tests (not in `Pkg.test()`):

```bash
julia --project=test/environments/clima test/environments/clima/clima_ext.jl
```

## Tests

```bash
julia --project=test -e 'using Pkg; Pkg.instantiate()'
julia --project=test test/runtests.jl
```

Default tests do not load ClimaAtmos and do not hit the network. If the artifact
is already installed, they also check all 190 days.

```bash
julia ] activate examples
julia >  include('examples/read_the_archive.jl')
```

Paper / Fortran / namelist disagreements: [`docs/src/archive.md`](docs/src/archive.md).
