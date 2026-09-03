```@meta
CurrentModule = MOSAiCAYiL
```

# The 3D fields

DALES writes its 3D output as `fielddump.III.JJJ.NNN.nc`, one file per MPI rank. A day is
320 × 320 × 200 × 4 in `Float32` — 328 MB per variable, 6.2 GB for all nineteen — so
[`MOSAiCAYiL.open_fielddump`](@ref) reads the metadata and leaves the fields on disk.

```julia
using MOSAiCAYiL: MOSAiCAYiL as MA

MA.open_fielddump("path/to/run") do fd
    fd.tiles                        # 40
    keys(fd.vars)                   # thl, qt, ql, u, v, w, buoy, q_rain, n_rain, …
    fd.dims["v"]                    # ("xt", "ym", "zt", "time")
    fd.units["n_rain"]              # "kg^-1"

    level  = fd.vars["thl"][:, :, 100, 1]     # (320, 320)
    column = fd.vars["w"][160, 160, :, :]     # (200, 4)
    box    = fd.vars["qt"][1:32, 1:32, 1:10, 1]
end
```

Each variable is an `AbstractArray`, and indexing reads only the tiles the request touches,
with Base's own semantics: an axis indexed by a scalar is dropped, ranges and `:` are kept.

`source` is a directory of tiles, or a single assembled file. Both take the same path.

## The staggering is kept

The winds sit on the Arakawa-C faces, and each is stitched along the axis it lives on:

| variable | axes |
|---|---|
| centred fields | `(xt, yt, zt, time)` |
| `u` | `(xm, yt, zt, time)` |
| `v` | `(xt, ym, zt, time)` |
| `w` | `(xt, yt, zm, time)` |

`fd.dims[name]` names them, and `fd.coords` carries all seven axes. Collocating is left to
the caller.

## The decomposition is read from the files

Production AYiL is decomposed over y across 40 ranks. The rank grid and each tile's extent
come from the tiles themselves:

```julia
tiles = MA.fielddump_tiles("path/to/run")     # (; path, ix, iy), sorted
MA.fielddump_decomposition(tiles)             # (; ix, iy)
```

A run with a different layout stitches correctly on the same code path.

## Vertical extent

`namfielddump khigh` sets how many of the LES grid's 286 levels are written — 200 in the
AYiL regeneration, reaching 2447 m — and `ncoarse` coarsens horizontally. Both are per-run
namelist choices, so the extent of a fielddump comes from the file:

```julia
size(fd.vars["thl"])       # (320, 320, 200, 4) for this run
fd.coords["zt"]
```

## Materializing

[`MOSAiCAYiL.load_fielddump`](@ref) reads what you ask for:

```julia
day = MA.load_fielddump("path/to/run"; vars = ["thl", "w"], time_indices = 1:1)
day.fields["thl"]          # (320, 320, 200, 1)
day.dims, day.coords, day.units
```

Names are the canonical ones: `sv001`…`sv012` resolve through
[`MOSAiCAYiL.fielddump_physical_name`](@ref), so `q_rain` and `n_cloud_ice` are what you ask
for. The units are corrected the same way — a number scalar reads `kg^-1`, and `qt`/`ql` read
`kg/kg` (the `1e-5kg/kg` label applies to DALES's legacy binary path).

## The file handles

The tile files stay open for the life of the handle, so repeated slicing costs no reopening.
Close them with the `do` form above, or explicitly:

```julia
fd = MA.open_fielddump("path/to/run")
try
    fd.vars["thl"][:, :, 1, 1]
finally
    MA.close_fielddump(fd)
end
```

On one 40-tile day this is the difference between 7 ms and 190 ms for a horizontal level,
and between 0.2 ms and 189 ms for a column.

## Sweeping many days

A fielddump handle holds open netCDF datasets, so the unit of parallelism is the day. Each
worker opens its own:

```julia
using Distributed
ids = MA.addprocs(8)
fields = MA.pmap(MA.load_fielddump, run_directories)
```

See [Parallel sweeps](parallel.md).
