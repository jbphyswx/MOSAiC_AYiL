"""
    fielddump.jl

DALES's 3D output, read from a path the caller supplies. Two shapes:

  - a **directory of per-rank tiles**, `fielddump.III.JJJ.NNN.nc`, each holding one MPI
    rank's slab — what DALES writes. Stitched onto the global grid here.
  - a **single global file**, already assembled.

The twelve SB3 scalars are written as `sv001` … `sv012` (`modfielddump.f90:135`) and resolve
onto the [`SB3_TO_PHYSICAL`](@ref) names.

Cell-centred fields are on `(time, zt, yt, xt)`. The winds are Arakawa-C staggered —
`u(time, zt, yt, xm)`, `v(time, zt, ym, xt)`, `w(time, zm, yt, xt)` — and stay that way:
the stagger is a property of the data, so nothing here silently collocates it.
"""

const FIELDDUMP_TILE_PATTERN = r"^fielddump\.(\d{3})\.(\d{3})\.(\d{3})\.nc$"

"""
    FielddumpTile

One file and the global index range it covers on the decomposed axes. A single global file
is one tile spanning everything, so both shapes use the same machinery.
"""
struct FielddumpTile
    path::String
    ix::Int
    iy::Int
    xrange::UnitRange{Int}
    yrange::UnitRange{Int}
end

"""
    FielddumpHandles

The open tile files of one fielddump, opened on first use and shared by all its variables.

A tile open costs about 6 ms, so a day of 40 tiles read variable by variable would spend
seconds reopening the same files. [`close_fielddump`](@ref) closes them.
"""
struct FielddumpHandles
    open::Dict{String, NC.NCDataset}
    lock::ReentrantLock
end

FielddumpHandles() = FielddumpHandles(Dict{String, NC.NCDataset}(), ReentrantLock())

tile_dataset(h::FielddumpHandles, path::AbstractString) =
    lock(h.lock) do
        get!(() -> NC.NCDataset(path, "r"), h.open, path)
    end

function Base.close(h::FielddumpHandles)
    lock(h.lock) do
        foreach(close, values(h.open))
        empty!(h.open)
    end
    return nothing
end

"""
    FielddumpVariable{T,N} <: AbstractArray{T,N}

One variable of a fielddump, across its tiles, holding no data.

Indexing reads only the tiles the request intersects, so a z-slice of a decomposed day costs
one strided read per tile rather than the whole field. `dims` names each axis, so the
Arakawa-C stagger survives: `v` is on `ym` and is stitched along `ym`, not `yt`.
"""
struct FielddumpVariable{T, N, TT <: AbstractVector{FielddumpTile}} <: AbstractArray{T, N}
    tiles::TT
    handles::FielddumpHandles
    raw::String
    dims::NTuple{N, String}
    sz::NTuple{N, Int}
    xaxis::Int                 # index into `dims` of the x-decomposed axis, 0 if none
    yaxis::Int                 # likewise for y
    units::String
end

Base.size(v::FielddumpVariable) = v.sz
Base.IndexStyle(::Type{<:FielddumpVariable}) = IndexCartesian()

_as_range(i::Integer, n) = i:i
_as_range(r::AbstractUnitRange, n) = first(r):last(r)
_as_range(::Colon, n) = 1:n
_as_range(x, n) = error(
    "A fielddump is indexed with integers, unit ranges or `:`; got $(typeof(x)).",
)

# The part of `want` this tile holds, as (global slice, tile-local slice).
function _tile_overlap(want::UnitRange{Int}, have::UnitRange{Int})
    lo, hi = max(first(want), first(have)), min(last(want), last(have))
    lo > hi && return nothing
    return (lo:hi, (lo - first(have) + 1):(hi - first(have) + 1))
end

function Base.getindex(v::FielddumpVariable{T, N}, I::Vararg{Any, N}) where {T, N}
    want = ntuple(k -> _as_range(I[k], v.sz[k]), N)
    out = Array{T}(undef, map(length, want)...)
    for tile in v.tiles
        # which slice of `want` this tile owns on each decomposed axis
        parts = ntuple(N) do k
            k == v.xaxis ? _tile_overlap(want[k], tile.xrange) :
            k == v.yaxis ? _tile_overlap(want[k], tile.yrange) :
            (want[k], want[k])
        end
        any(isnothing, parts) && continue
        dest = ntuple(k -> (first(parts[k][1]) - first(want[k]) + 1):
                           (last(parts[k][1]) - first(want[k]) + 1), N)
        src = ntuple(k -> parts[k][2], N)
        ds = tile_dataset(v.handles, tile.path)
        out[dest...] = NC.variable(ds, v.raw)[src...]
    end
    # match Base's semantics: an axis indexed by a scalar is dropped
    all(i -> i isa Integer, I) && return out[1]
    scalar_axes = Tuple(k for k in 1:N if I[k] isa Integer)
    return isempty(scalar_axes) ? out : dropdims(out; dims = scalar_axes)
end

"""
    fielddump_physical_name(raw)

The canonical name of a fielddump variable: `sv001`…`sv012` become their
[`SB3_TO_PHYSICAL`](@ref) names, everything else passes through unchanged.

`modfielddump.f90:116-135` writes `u`, `v`, `w`, `qt`, `ql`, `thl`, `buoy`, `pressure`,
`exner`, `temperature`, the six `w*t` fluxes, and `sv001`…`svNNN`.
"""
function fielddump_physical_name(raw::AbstractString)
    m = match(r"^sv(\d{3})$", raw)
    m === nothing || return _sb3_physical(m.captures[1])
    return String(raw)
end

"""
    fielddump_tiles(run_dir; expnr = "001")

The `fielddump` tiles of a run, as `(; path, ix, iy)`, sorted by `(iy, ix)`.
"""
function fielddump_tiles(run_dir::AbstractString; expnr::AbstractString = "001")
    isdir(run_dir) || error("No run directory at $run_dir")
    tiles = NamedTuple{(:path, :ix, :iy), Tuple{String, Int, Int}}[]
    for name in readdir(run_dir)
        m = match(FIELDDUMP_TILE_PATTERN, name)
        m === nothing && continue
        m.captures[3] == expnr || continue
        push!(tiles, (; path = joinpath(run_dir, name),
                        ix = parse(Int, m.captures[1]),
                        iy = parse(Int, m.captures[2])))
    end
    isempty(tiles) && error(
        "No `fielddump.III.JJJ.$expnr.nc` tiles in $run_dir.",
    )
    return sort!(tiles; by = t -> (t.iy, t.ix))
end

"""
    fielddump_decomposition(tiles)

`(; ix, iy)` — the sorted distinct rank indices, i.e. the MPI decomposition the run used.

Read from the tiles rather than assumed: production AYiL is y-only over 40 ranks, but a
smoke run is not, and a hardcoded layout would silently mis-stitch it.
"""
fielddump_decomposition(tiles) =
    (; ix = sort!(unique(t.ix for t in tiles)), iy = sort!(unique(t.iy for t in tiles)))

# Offsets of each rank index along an axis, from the per-tile extent of that axis.
function _axis_offsets(sizes::AbstractVector{Int})
    offsets = similar(sizes)
    acc = 0
    for (i, n) in enumerate(sizes)
        offsets[i] = acc
        acc += n
    end
    return offsets, acc
end

"""
    open_fielddump(source; expnr = "001")

A fielddump as `(; vars, coords, dims, units, tiles)` **without reading any field data**.

`vars` maps canonical name to a [`FielddumpVariable`](@ref), which is an `AbstractArray`:
index it and only the tiles the request touches are read. `coords` and `units` are metadata
and are read eagerly, being small.

Use this when a day is larger than you want in memory — a decomposed day is gigabytes per
variable. [`load_fielddump`](@ref) is the same thing materialized.

The tile files stay open, so repeated slicing does not pay to reopen them; hand the result
to [`close_fielddump`](@ref), or take the do-block form.

```julia
MOSAiCAYiL.open_fielddump("runs/20200720") do fd
    slice = fd.vars["thl"][:, :, 100, 1]    # one level, one time
    column = fd.vars["w"][160, 160, :, :]   # one column, all levels and times
end
```
"""
function open_fielddump(source::AbstractString; expnr::AbstractString = "001")
    handles = FielddumpHandles()
    tiles, coords, var_dims, var_units, var_types, nx, ny =
        isdir(source) ? _fielddump_layout_tiles(source, expnr, handles) :
        isfile(source) ? _fielddump_layout_file(source, handles) :
        (close(handles); error("No fielddump directory or file at $source"))

    vars = Dict{String, FielddumpVariable}()
    dims = Dict{String, Tuple}()
    units = Dict{String, String}()
    for (raw, d) in var_dims
        name = fielddump_physical_name(raw)
        xaxis = something(findfirst(x -> x in ("xt", "xm"), collect(d)), 0)
        yaxis = something(findfirst(x -> x in ("yt", "ym"), collect(d)), 0)
        sz = ntuple(length(d)) do k
            k == xaxis ? nx : k == yaxis ? ny : length(get(coords, d[k], 1:1))
        end
        T = var_types[raw]
        vars[name] = FielddumpVariable{T, length(d), typeof(tiles)}(
            tiles, handles, raw, Tuple(d), sz, xaxis, yaxis, var_units[raw],
        )
        dims[name] = Tuple(d)
        units[name] = var_units[raw]
    end
    return (; vars, coords, dims, units, handles, tiles = length(tiles), source)
end

"""
    open_fielddump(f, source; expnr = "001")

`f` applied to the open fielddump, closed afterwards however `f` returns.
"""
function open_fielddump(f::Function, source::AbstractString; kwargs...)
    fd = open_fielddump(source; kwargs...)
    try
        return f(fd)
    finally
        close_fielddump(fd)
    end
end

"""
    close_fielddump(fd)

Close the tile files [`open_fielddump`](@ref) opened. Indexing `fd` afterwards errors.
"""
close_fielddump(fd) = close(fd.handles)

"""
    load_fielddump(source; expnr, vars, time_indices)

The 3D fields of one simulation as `(; dims, coords, fields, units)`.

`source` is either a directory of `fielddump` tiles, which are stitched onto the global
grid, or a single file, which is read as it stands. `vars` selects variables by their
**canonical** name ([`fielddump_physical_name`](@ref)); `nothing` reads them all.

`fields` maps canonical name to an array whose axes are named in `dims[name]`, so a
staggered wind keeps its own axis (`xm`, `ym`, `zm`) rather than being collocated.

This materializes what it is asked for — a decomposed day is gigabytes per variable, so
`vars` and `time_indices` are the levers. [`open_fielddump`](@ref) reads nothing and defers
to indexing instead.
"""
function load_fielddump(
    source::AbstractString;
    expnr::AbstractString = "001",
    vars = nothing,
    time_indices = Colon(),
)
    return open_fielddump(source; expnr) do fd
        fields = Dict{String, Array}()
        for (name, v) in fd.vars
            (vars === nothing || name in vars || v.raw in vars) || continue
            idx = ntuple(k -> v.dims[k] == "time" ? time_indices : Colon(), ndims(v))
            fields[name] = v[idx...]
        end
        isempty(fields) && error("No fielddump variables selected from $source")
        coords = copy(fd.coords)
        if time_indices !== Colon() && haskey(coords, "time")
            coords["time"] = coords["time"][time_indices]
        end
        return (; fd.dims, coords, fields, fd.units, fd.source, fd.tiles)
    end
end

"""
    fielddump_units(raw, stated)

The units a fielddump variable is really in, given the `units` attribute it states.

Two labels are wrong as stated.

`modfielddump.f90:135` labels all twelve SB3 scalars `(kg/kg)`, but the number contents are
per unit *mass* — `modmicrodata3.f90:106-117` declares `in_hr`, `in_cl`, `in_in`, `in_cc`,
`in_ci`, `in_hs`, `in_hg` as `[kg^{-1}]`. So a number scalar reads `kg^-1`, not `kg/kg`.
Values are returned as stored; multiplying by air density is the caller's step.

`qt` and `ql` are labelled `1e-5kg/kg` (`:119-120`) but the netCDF path writes them
unscaled: `:228-229` and `:241-242` apply the `1.0E5` factor to the legacy binary `field`
and assign `qt0`/`ql0` straight into `vars`. They are plain `kg/kg`.
"""
function fielddump_units(raw::AbstractString, stated::AbstractString)
    startswith(fielddump_physical_name(raw), "n_") && return "kg^-1"
    stated == "1e-5kg/kg" && return "kg/kg"
    return spelled_units(stated)
end


# --- Layout: where each variable's data lives, without reading any of it ------ #

const _COORD_NAMES = ("xt", "xm", "yt", "ym", "zt", "zm", "time")

function _variable_metadata(ds)
    var_dims = Dict{String, Tuple}()
    var_units = Dict{String, String}()
    var_types = Dict{String, DataType}()
    for raw in keys(ds)
        raw in _COORD_NAMES && continue
        var_dims[raw] = NC.dimnames(ds[raw])
        var_units[raw] = fielddump_units(raw, get(ds[raw].attrib, "units", ""))
        var_types[raw] = eltype(NC.variable(ds, raw))
    end
    return var_dims, var_units, var_types
end

function _fielddump_layout_file(path, handles)
    ds = tile_dataset(handles, path)
    coords = Dict{String, Vector}()
    for c in _COORD_NAMES
        haskey(ds, c) && (coords[c] = vec(Array(NC.variable(ds, c))))
    end
    var_dims, var_units, var_types = _variable_metadata(ds)
    nx = get(ds.dim, "xt", get(ds.dim, "xm", 1))
    ny = get(ds.dim, "yt", get(ds.dim, "ym", 1))
    tiles = [FielddumpTile(path, 0, 0, 1:nx, 1:ny)]
    return tiles, coords, var_dims, var_units, var_types, nx, ny
end

function _fielddump_layout_tiles(run_dir, expnr, handles)
    found = fielddump_tiles(run_dir; expnr)
    (; ix, iy) = fielddump_decomposition(found)

    x_sizes = zeros(Int, length(ix))
    y_sizes = zeros(Int, length(iy))
    for t in found
        ds = tile_dataset(handles, t.path)
        x_sizes[searchsortedfirst(ix, t.ix)] = ds.dim["xt"]
        y_sizes[searchsortedfirst(iy, t.iy)] = ds.dim["yt"]
    end
    x_off, nx = _axis_offsets(x_sizes)
    y_off, ny = _axis_offsets(y_sizes)

    tiles = map(found) do t
        i, j = searchsortedfirst(ix, t.ix), searchsortedfirst(iy, t.iy)
        FielddumpTile(
            t.path, t.ix, t.iy,
            (x_off[i] + 1):(x_off[i] + x_sizes[i]),
            (y_off[j] + 1):(y_off[j] + y_sizes[j]),
        )
    end

    coords = Dict{String, Vector}()
    ds1 = tile_dataset(handles, first(found).path)
    for c in ("zt", "zm", "time")
        haskey(ds1, c) && (coords[c] = vec(Array(NC.variable(ds1, c))))
    end
    var_dims, var_units, var_types = _variable_metadata(ds1)
    # the decomposed axes are assembled from the tiles, in the type the tiles store them
    for (axis, n) in (("xt", nx), ("xm", nx), ("yt", ny), ("ym", ny))
        coords[axis] = Vector{eltype(NC.variable(ds1, axis))}(undef, n)
    end
    for tile in tiles
        ds = tile_dataset(handles, tile.path)
        for axis in ("xt", "xm")
            haskey(ds, axis) && (coords[axis][tile.xrange] = vec(Array(NC.variable(ds, axis))))
        end
        for axis in ("yt", "ym")
            haskey(ds, axis) && (coords[axis][tile.yrange] = vec(Array(NC.variable(ds, axis))))
        end
    end
    return tiles, coords, var_dims, var_units, var_types, nx, ny
end
