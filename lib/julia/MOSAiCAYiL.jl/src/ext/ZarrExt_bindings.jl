# --- Optional weak-dep API (methods added when `MOSAiCAYiLZarrExt` loads on `using Zarr`) ---

"""
    open_zarr(source; consolidated = true)

A Zarr store as `(; vars, coords, dims, units, attrs, source)`, reading no field data.

Mirrors [`open_fielddump`](@ref): `vars` maps canonical name to a lazily-indexed array.
Zarr.jl presents a store's axes in the reverse of the order they are written in, so a
`(time, z, y, x)` store indexes here as `(x, y, z, time)` — the same order a fielddump
does.
"""
function open_zarr end

"""
    load_zarr(source; vars = nothing, time_indices = Colon())

The fields of a Zarr store, materialized. Mirrors [`load_fielddump`](@ref).
"""
function load_zarr end

"""
    write_zarr(dest, fd; chunks, vars, compressor, attrs)

Write a fielddump to a Zarr v3 store at `dest`, returning `dest`.

`fd` is an [`open_fielddump`](@ref) or [`load_fielddump`](@ref) result. From an open one
this streams a chunk-row at a time, so it never holds a variable whole.

`chunks` is the chunk shape, in the same axis order as the variable. 
"""
function write_zarr end
