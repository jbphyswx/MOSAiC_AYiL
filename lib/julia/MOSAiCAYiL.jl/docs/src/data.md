```@meta
CurrentModule = MOSAiCAYiL
```

# The days and their files

## The catalog

The 190 published days are a compile-time constant, ascending:

```@example data
using MOSAiCAYiL: MOSAiCAYiL as MA

MA.n_cases(), first(MA.MOSAiCAYiL_dates), last(MA.MOSAiCAYiL_dates)
```

A day is named by a `Date`, a `yyyymmdd` string, or a [`MOSAiCAYiL.MOSAiCAYiLCase`](@ref),
and the three are interchangeable everywhere:

```@example data
c = MA.case("20200503")
MA.date_string(c), MA.date_index(c), MA.case_name(c)
```

A date outside the catalog is an error

```@example data
try
    MA.case("20190101")
catch e
    e.msg
end
```

## Where the files come from

Day directories come from the lazy Zenodo artifact
[10.5281/zenodo.10491362](https://doi.org/10.5281/zenodo.10491362), about 1.5 GB unpacked.
It installs lazily on first use.

```julia
MA.data_root()                       # the artifact, installing it if needed
MA.data_root(; root = "/path/to/ayil_config_input_results")
MA.artifact_installed()              # already on disk? does not download
MA.data_available()                  # installed *and* serving day files
MA.available_dates()                 # the catalog days present under a root
```

Every reader takes the same `root` keyword, so a local tree is used by passing it through:

```julia
MA.testbed_forcing("20200503"; root = "/path/to/tree")
```

## What a day directory holds

```@example data
keys(MA.day_files("20200503"; root = "."))
```

Five of those are netCDF and are what [Reading a variable](reading.md) covers:

| file | what it is |
|---|---|
| `scm_in.a_year_in_les.<date>.nc` | the ERA5 testbed forcing the day was driven with |
| `profiles.001.nc` | slab-mean profiles, 286 levels × 24 records of 300 s |
| `tmser.001.nc` | column time series, 120 records of 60 s |
| `mphysprofiles.001.nc` | microphysics process rates |
| `samptend.001.nc` | conditionally-sampled tendency budgets |

The rest are DALES's plain-text inputs and its text copies of the time series. `namoptions`
is read with its groups kept, because the file needs them: `dtav` appears in nine groups
carrying two different values, `timeav` in five carrying two.

```julia
nl = MA.namelist(c)
MA.namelist_value(Int, nl, :nammicrophysics, :imicro)   # 11, the SB3 two-moment microphysics
MA.namelist_value(Float64, nl, :namfielddump, :dtav)    # 1800.0, which is FIELDDUMP_DT_S
MA.namelist_groups_with(nl, :dtav)                      # the nine groups carrying it
```

Eight entries are placeholders DALES overwrote from `scm_in` every substep. Reading one errors
and names the accessor carrying the value the run actually used, so a placeholder cannot be
mistaken for physics — `&physics ps` is out by about 970 Pa and `&physics thls` by about 21 K.
`namelist_placeholder` returns the raw string for provenance. See
[What the reference runs did](archive.md).

## Regenerating the committed tables

The per-day tables under `src/generated/` are written by the scripts in `gen/`. They define
their functions and call nothing, so including one to pass your own `root` does not first run
it against the artifact:

```bash
julia --project=gen -e 'include("gen/extract_day_scalars.jl");  write_day_scalars()'
julia --project=gen -e 'include("gen/extract_day_metadata.jl"); write_day_metadata()'
julia --project=gen -e 'include("gen/extract_cloud_tops.jl");   write_cloud_tops()'
```

Regenerating is also how those tables are checked: the archive is fixed, so a run that leaves
the file unchanged is the guarantee.