"""
    MOSAiCAYiLZarrExt

Loads when `Zarr` is available. Reads and writes the 3D fields as a Zarr v3 store.

Zarr.jl presents a store's axes reversed from the order they are written in
(`Zarr/src/metadata3.jl` reverses `shape` on read and again on write), so a store written
`(time, z, y, x)` indexes here as `(x, y, z, time)` — the order a fielddump already has,
and nothing is transposed in either direction.
"""
module MOSAiCAYiLZarrExt

using MOSAiCAYiL: MOSAiCAYiL
using Zarr: Zarr

"""The axes a store written here carries, under DALES's own names."""
const COORD_NAMES = ("xt", "xm", "yt", "ym", "zt", "zm", "time")

# `dimension_names` is the v3 field naming a variable's axes. Zarr.jl parses it but keeps
# no field for it and never writes it, so it is read from and written to `zarr.json`
# directly — the read-modify-write its own v3 `writeattrs` uses.
function _zarr_json(store, path)
    raw = store[path, "zarr.json"]
    raw === nothing && error("No zarr.json at `$path`")
    return Zarr.JSON.parse(String(copy(raw)); dicttype = Dict{String, Any})
end

function _write_zarr_json(store, path, md)
    b = IOBuffer()
    Zarr.JSON.print(b, md)
    store[path, "zarr.json"] = take!(b)
    return nothing
end

function _set_dimension_names(z::Zarr.ZArray, names)
    md = _zarr_json(z.storage, z.path)
    md["dimension_names"] = collect(reverse(names))   # in the store's own axis order
    _write_zarr_json(z.storage, z.path, md)
    return nothing
end

# The consolidated block is built here rather than by `Zarr.consolidate_metadata`, whose v3
# walk descends into `string(prefix, "/", subname)`: rooted at `""` that is an absolute key,
# every lookup misses, and it writes a block listing nothing.
function _consolidate!(store, names)
    members = Dict{String, Any}()
    for name in names
        md = _zarr_json(store, name)
        get(md, "node_type", "") == "array" &&
            !haskey(md, "storage_transformers") &&
            (md["storage_transformers"] = [])
        members[name] = md
    end
    root = _zarr_json(store, "")
    root["consolidated_metadata"] = Dict{String, Any}(
        "kind" => "inline", "must_understand" => false, "metadata" => members,
    )
    _write_zarr_json(store, "", root)
    return nothing
end

function _dimension_names(md)
    stored = get(md, "dimension_names", nothing)
    stored === nothing && return ()
    return Tuple(String(d) for d in reverse(stored))
end

# --- reading ----------------------------------------------------------------- #

"""
Every node's metadata by name, from the one consolidated block when the store has one.

Zarr.jl's consolidated reader resolves a node's attributes against a key the block does not
carry, so `units` and `dimension_names` are taken from the block parsed here instead of
from `ZArray.attrs`.
"""
function _node_metadata(store, names, consolidated::Bool)
    if consolidated
        cm = get(_zarr_json(store, ""), "consolidated_metadata", nothing)
        cm === nothing || return cm["metadata"]
    end
    return Dict{String, Any}(name => _zarr_json(store, name) for name in names)
end

function MOSAiCAYiL.open_zarr(source::AbstractString; consolidated::Bool = true)
    isdir(source) || error("No Zarr store at $source")
    g = Zarr.zopen(source, "r"; consolidated)
    g isa Zarr.ZGroup || error("$source is a Zarr array, not a group of variables")
    md = _node_metadata(g.storage, keys(g.arrays), consolidated)

    coords = Dict{String, Vector}()
    vars = Dict{String, Zarr.ZArray}()
    dims = Dict{String, Tuple}()
    units = Dict{String, String}()
    variable_attrs = Dict{String, Dict{String, Any}}()
    for (name, z) in g.arrays
        if ndims(z) == 1 && name in COORD_NAMES
            coords[name] = vec(z[:])
            continue
        end
        a = Dict{String, Any}(get(md[name], "attributes", Dict{String, Any}()))
        vars[name] = z
        dims[name] = _dimension_names(md[name])
        units[name] = get(a, "units", "")
        variable_attrs[name] = a
    end
    attrs = Dict{String, Any}(get(_zarr_json(g.storage, ""), "attributes", Dict{String, Any}()))
    return (; vars, coords, dims, units, attrs, variable_attrs, source)
end

function MOSAiCAYiL.load_zarr(
    source::AbstractString;
    vars = nothing,
    time_indices = Colon(),
    consolidated::Bool = true,
)
    zs = MOSAiCAYiL.open_zarr(source; consolidated)
    fields = Dict{String, Array}()
    for (name, z) in zs.vars
        (vars === nothing || name in vars) || continue
        d = get(zs.dims, name, ())
        idx = ntuple(ndims(z)) do k
            k <= length(d) && d[k] == "time" ? time_indices : Colon()
        end
        fields[name] = z[idx...]
    end
    isempty(fields) && error("No variables selected from $source")
    coords = copy(zs.coords)
    if time_indices !== Colon() && haskey(coords, "time")
        coords["time"] = coords["time"][time_indices]
    end
    return (; zs.dims, coords, fields, zs.units, zs.attrs, zs.source)
end

# --- writing ----------------------------------------------------------------- #


_fill_value(::Type{T}) where {T <: AbstractFloat} = T(NaN)
_fill_value(::Type{T}) where {T} = zero(T)

_coord_units(axis) = axis == "time" ? "s" : "m"

function MOSAiCAYiL.write_zarr(
    dest::AbstractString,
    fd;
    vars = nothing,
    chunks,
    compressor = Zarr.BloscCompressor(cname = "zstd", clevel = 3, shuffle = 2),
    attrs = Dict{String, Any}(),
)
    ispath(dest) && error("$dest already exists")
    selected = sort!(filter(n -> vars === nothing || n in vars, collect(keys(fd.vars))))
    isempty(selected) && error("No fielddump variables selected from $(fd.source)")
    for name in selected
        v = fd.vars[name]
        length(chunks) == ndims(v) && continue
        error(
            "`$name` has $(ndims(v)) axes $(fd.dims[name]) of size $(size(v)); `chunks` \
             gives $(length(chunks)).",
        )
    end

    g = Zarr.zgroup(
        Zarr.DirectoryStore(dest), "", Zarr.ZarrFormat(3);
        attrs = merge(
            Dict{String, Any}("source" => string(fd.source), "n_tiles" => fd.tiles),
            attrs,
        ),
    )

    written = String[]
    for axis in sort!(collect(keys(fd.coords)))
        values = fd.coords[axis]
        isempty(values) && continue
        push!(written, axis)
        z = Zarr.zcreate(
            eltype(values), g, axis, length(values);
            chunks = (length(values),), fill_value = _fill_value(eltype(values)),
            compressor, attrs = Dict{String, Any}("units" => _coord_units(axis)),
        )
        z[:] = values
        _set_dimension_names(z, (axis,))
    end

    for name in selected
        push!(written, name)
        v = fd.vars[name]
        d = fd.dims[name]
        z = Zarr.zcreate(
            eltype(v), g, name, size(v)...;
            chunks, fill_value = _fill_value(eltype(v)), compressor,
            attrs = Dict{String, Any}(
                "units" => fd.units[name],
                "dales_fielddump_name" => v.raw,
            ),
        )
        _write_in_slabs!(z, v, d, chunks)
        _set_dimension_names(z, d)
    end

    _consolidate!(g.storage, written)
    return dest
end

# Copy one chunk-row at a time along the decomposed axis, so no variable is ever held whole.
function _write_in_slabs!(z, v, dims, chunks)
    axis = something(findfirst(d -> d in ("yt", "ym"), collect(dims)), 0)
    whole = ntuple(_ -> Colon(), ndims(v))
    if axis == 0
        z[whole...] = v[whole...]
        return z
    end
    for lo in 1:chunks[axis]:size(v, axis)
        hi = min(lo + chunks[axis] - 1, size(v, axis))
        idx = ntuple(k -> k == axis ? (lo:hi) : Colon(), ndims(v))
        z[idx...] = v[idx...]
    end
    return z
end

end
