```@meta
CurrentModule = MOSAiCAYiL
```

# Parallel sweeps

Two extensions load on demand and give the package its own `map`-shaped verbs.

```julia
using Distributed
using MOSAiCAYiL: MOSAiCAYiL as MA

ids = MA.addprocs(24)                       # workers with MOSAiCAYiL loaded on each
tops = MA.pmap(MA.load_fielddump, run_directories)
MA.pforeach(f, MA.MOSAiCAYiL_dates)
MA.pmapreduce(f, +, MA.MOSAiCAYiL_dates)
```

```julia
using OhMyThreads
MA.tmap(f, MA.MOSAiCAYiL_dates)
MA.tmapreduce(f, +, values)
MA.treduce(+, values)
MA.tcollect(f(x) for x in values)
```

They accept the catalog's own containers. `MOSAiCAYiL_dates` is a `Tuple` and `keys(...)` is
a `KeySet`, both of which `OhMyThreads.tmap` rejects, so the wrappers materialize first.

## Use processes for reading

netcdf-c is not thread safe, and since NCDatasets 0.14.12 one process-global `ReentrantLock`
serializes every one of its C calls. Threads share that lock; worker processes each hold
their own.

Measured over a 190-day `ice_fields` sweep on a 96-core host:

| backend | wall | speedup |
|---|---|---|
| serial | 5.93 s | 1.00× |
| 8 threads | 12.27 s | **0.48×** |
| 8 processes | 0.97 s | 6.13× |
| 24 processes | 0.41 s | 14.6× |
| 48 processes | 0.29 s | 21.4× |

Threading an archive read is a regression. The threaded verbs are for work over data already
in memory.

Worker compilation is charged to the first sweep: without a warm-up the same measurement
reads 1.02×.

## The sweeps take a mapper

The drivers that walk the catalog take `mapper`, so the same code runs serially or across
workers:

```julia
MA.best_z_maxs(dates; mapper = MA.pmap)
MA.get_cloud_tops(dates; mapper = MA.pmap)
```

Results are identical to `mapper = map`.

## Sweeping the 3D fields

A fielddump handle holds open netCDF datasets, which do not cross a process boundary, so the
unit of parallelism is the day and each worker opens its own files:

```julia
fields = MA.pmap(MA.load_fielddump, run_directories)
```

A closure passed to a worker must name something the worker can resolve. `addprocs` loads
`MOSAiCAYiL` there, so its own functions work; a local alias defined in your script does
not exist on the worker.
