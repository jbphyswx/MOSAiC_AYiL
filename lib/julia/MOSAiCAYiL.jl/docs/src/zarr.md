```@meta
CurrentModule = MOSAiCAYiL
```

# Zarr

`using Zarr` adds writing and reading of Zarr v3 stores.

```julia
using Zarr
using MOSAiCAYiL: MOSAiCAYiL as MA

MA.open_fielddump("path/to/run") do fd
    MA.write_zarr("day.zarr", fd; chunks = (320, 80, 200, 4))
end

z = MA.open_zarr("day.zarr")
z.dims["v"]                       # ("xt", "ym", "zt", "time")
z.units["n_rain"]                 # "kg^-1"
level = z.vars["thl"][:, :, 100, 1]

day = MA.load_zarr("day.zarr"; vars = ["thl"], time_indices = 1:1)
```

Writing streams a chunk-row at a time off the open fielddump, so converting a 6.2 GB day
never holds a variable whole.

Zarr.jl presents a store's axes in the reverse of the order they are written, so a store
written `(time, z, y, x)` indexes here as `(x, y, z, time)` — the same order a fielddump
has, and nothing is transposed in either direction.

## Chunks

`chunks` has no default. Zarr decompresses a whole chunk to read any element of it, and a
horizontal level and a vertical column want opposite shapes. On a 320 × 320 × 200 × 4 field:

| chunk shape | MB | one level | one column |
|---|---|---|---|
| `(320, 320, 1, 4)` | 1.6 | 46 ms | 1196 ms |
| `(80, 80, 50, 4)` | 4.9 | 184 ms | 48 ms |
| `(160, 160, 100, 4)` | 39 | 756 ms | 258 ms |
| `(16, 16, 200, 4)` | 0.8 | 991 ms | 1.8 ms |

Compressed size varies by under 10% across all of them, so the shape is an access-pattern
choice. Zarr's own guidance is at least 1 MB per chunk under Blosc, and 10–100 MB for object
stores; a whole variable here is 328 MB, so the object-store range leaves 3 to 33 chunks per
variable.

The compressor defaults to Blosc with zstd at level 3 and bitshuffle, and is a keyword.

## What the store carries

Each variable is written with its corrected units and the raw DALES name it came from:

```julia
z.units["n_rain"]                                  # "kg^-1", not the archive's "(kg/kg)"
z.variable_attrs["n_rain"]["dales_fielddump_name"] # "sv001"
z.attrs                                            # source, n_tiles
```

Axis names go into the v3 `dimension_names` field, so the Arakawa-C staggering survives the
round trip. Zarr.jl parses that field and keeps no place for it, so the package writes it
into `zarr.json` directly, the same read-modify-write its own v3 attribute writer uses.

A consolidated metadata block is written too, so a reader lists the variables from one file.

!!! note "Two Zarr.jl v3 limitations the package works around"
    `consolidate_metadata` descends into `string(prefix, "/", subname)`, which is an
    absolute key when the group sits at the store root, so it writes a block listing
    nothing. And the consolidated reader resolves a node's attributes against a key the
    block does not carry, so `units` comes back empty. `write_zarr` builds the block itself
    and `open_zarr` reads it itself; both were checked against Zarr v0.10.2.
