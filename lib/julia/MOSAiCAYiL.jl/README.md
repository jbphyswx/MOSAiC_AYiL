# MOSAiCAYiL

Facts, archive access, and ClimaAtmos methods for Schnierstein et al. (2024)
MOSAiC **A Year in LES** (AYiL): 190 Arctic days of DALES large-eddy simulations.

This package owns the **data** and **facts** of the ensemble, plus ClimaAtmos
methods on types it defines. It does not assemble an `AtmosModel` /
`AtmosSimulation` and does not call `solve_atmos!`.

## Julia version

Use the machine default `julia` (currently 1.12.x here). Compat is
`julia = "1.11, 1.12"`. This package is **not** pinned to `julia +1.11.5`
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
`read_scm_in(c; root = "...")`.

```julia
MOSAiCAYiL.data_root(; root = "/path/to/ayil_config_input_results")
MOSAiCAYiL.read_scm_in(c; root = "...")
```

Regenerate the committed day-scalar table with:

```bash
julia --project=gen gen/extract_day_scalars.jl
# or: include(...); main(; root = "/path/to/ayil_config_input_results")
```

## ClimaAtmos extension

```julia
using ClimaAtmos
using MOSAiCAYiL
c = MOSAiCAYiL.case("20200503")
forcing = MOSAiCAYiL.ClimaAtmosMOSAiCAYiLForcing(Float64, c)
setup = MOSAiCAYiL.ClimaAtmosMOSAiCAYiLSetup(Float64, c)
grid = MOSAiCAYiL.mosaic_grid(Float64)  # LES faces; compose truncate/coarsen first
```

Default initial density is `scm_in_air_density` (design.md §8). Pass
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

Paper / Fortran / namelist disagreements: [`docs/contract.md`](docs/contract.md).
