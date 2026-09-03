```@meta
CurrentModule = MOSAiCAYiL
```

# MOSAiCAYiL.jl

The data and the facts of Schnierstein et al. (2024) MOSAiC **A Year in LES**: 190 Arctic
days of DALES large-eddy simulation, run along the MOSAiC drift.

This package reads what those runs consumed and produced — the ERA5 testbed forcing, the
profile and time-series output, and the 3D fields — under readable names and in corrected
units, and carries the per-day facts as committed tables so most questions need no files at
all.

```@example index
using MOSAiCAYiL: MOSAiCAYiL as MA

c = MA.case("20200503")
(MA.latitude(c), MA.t_skin(c), MA.scm_in_levels(c), MA.inversion_height(c))
```

Nothing above opened a file.

## Installing

The package lives in `lib/julia/MOSAiCAYiL.jl` of the `MOSAiC_AYiL` repository.

```bash
cd lib/julia/MOSAiCAYiL.jl
julia --project=. -e 'using Pkg; Pkg.instantiate(); using MOSAiCAYiL'
```

Julia 1.11 or 1.12. The archive itself is a lazy artifact and is not downloaded until
something asks for it.

## What is here

| | |
|---|---|
| [The days and their files](data.md) | the 190-day catalog, the artifact, and what a day directory holds |
| [Reading a variable](reading.md) | one call over all five archive files, with the units corrected |
| [The forcing of a day](forcing.md) | the ERA5 testbed profiles and surface, and writing them back out |
| [The 3D fields](fields3d.md) | `fielddump` output, read lazily off its MPI tiles |
| [Facts with no I/O](facts.md) | the committed per-day tables |
| [Thermodynamics](thermodynamics.md) | DALES's own constants and saturation, behind generic verbs |
| [The vertical grid](grid.md) | the 287 stored faces, and cutting or thinning them |
| [What the reference runs did](archive.md) | where the paper, the Fortran and the namelists disagree |

Three extensions load on demand: [Zarr](zarr.md) for writing and reading Zarr v3 stores,
[Parallel sweeps](parallel.md) for `Distributed` and `OhMyThreads`, and [ClimaAtmos](climaatmos.md) for
driving a single-column model with an AYiL day.

## The ensemble at a glance

The catalog spans 2019-10-16 to 2020-09-11. Every day was run on the same grid, with its own
ERA5 forcing; the inversion the nudging relaxes above, and the cloud top the ice filters
find, differ day to day.

![Inversion height and cloud top across the catalog](assets/catalog.png)

## A note on authority

Where the paper, the namelists and the AYiL DALES source disagree, **the Fortran that wrote
the archive is what this package implements**, and the disagreement is recorded. [What the reference runs did](archive.md) lists them.