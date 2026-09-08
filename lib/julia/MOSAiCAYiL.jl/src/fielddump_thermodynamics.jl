"""
    fielddump_thermodynamics.jl

The pressure, temperature and air density of a fielddump, which DALES writes none of into an
old one. Lazy, because a decomposed day is gigabytes per variable.
"""

"""
    DerivedFielddumpVariable{T,N} <: AbstractArray{T,N}

A pointwise function of other fielddump variables and per-`(level, time)` columns, computed on
indexing rather than stored.

Indexing slices every source with the same request, so only the tiles it touches are read, and
the columns broadcast along the level and time axes. Axes indexed by a scalar are dropped, as
[`FielddumpVariable`](@ref) and `Base` do.
"""
struct DerivedFielddumpVariable{T, N, S <: Tuple, C <: Tuple, F} <: AbstractArray{T, N}
    sources::S
    columns::C
    f::F
    zaxis::Int
    taxis::Int
    sz::NTuple{N, Int}
    units::String
end

Base.size(v::DerivedFielddumpVariable) = v.sz
Base.IndexStyle(::Type{<:DerivedFielddumpVariable}) = IndexCartesian()

function Base.getindex(v::DerivedFielddumpVariable{T, N}, I::Vararg{Any, N}) where {T, N}
    want = ntuple(k -> _as_range(I[k], v.sz[k]), N)
    # slice with ranges so every axis survives and the columns can broadcast against them
    sliced = map(s -> s[want...], v.sources)
    levels, times = want[v.zaxis], want[v.taxis]
    shape = ntuple(
        k -> k == v.zaxis ? length(levels) : k == v.taxis ? length(times) : 1, N,
    )
    spread = map(v.columns) do column
        # emit the block in the variable's own axis order: `reshape` preserves linear
        # order, so a level-major block would land transposed when time comes first
        block = v.zaxis < v.taxis ? [column[k, t] for k in levels, t in times] :
                [column[k, t] for t in times, k in levels]
        reshape(block, shape)
    end
    out = v.f.(spread..., sliced...)
    all(i -> i isa Integer, I) && return out[1]
    scalar_axes = Tuple(k for k in 1:N if I[k] isa Integer)
    return isempty(scalar_axes) ? out : dropdims(out; dims = scalar_axes)
end

"""
    fielddump_long_name(raw, stated)

The long name a fielddump variable is really described by, given the one it states.

`thl` states "Liquid water potential temperature above 300K" (`modfielddump.f90:121`), which
is the **binary** path's offset: `:254-255` subtracts 300 before writing `field`, while the
netCDF path assigns `thl0` straight through. The netCDF values are the full `θ_l`.
"""
function fielddump_long_name(raw::AbstractString, stated::AbstractString)
    raw == "thl" && return "Liquid water potential temperature"
    return String(stated)
end

# Which axis of `dims` carries the levels, and which the time records.
function _fielddump_axes(dims::Tuple)
    zaxis = findfirst(d -> d in ("zt", "zm"), collect(dims))
    taxis = findfirst(==("time"), collect(dims))
    isnothing(zaxis) && error("A fielddump variable on $dims has no level axis.")
    isnothing(taxis) && error("A fielddump variable on $dims has no time axis.")
    return zaxis, taxis
end

# A column field on the fielddump's own `(level, time)` grid: interpolate along the levels,
# then along the records. `bc` decides what happens off either end of either axis.
function _column_onto(field, z_col, t_col, z_want, t_want, bc)
    by_level = reduce(
        hcat,
        interpolate_1d(z_want, z_col, view(field, :, j); bc) for j in axes(field, 2)
    )
    return reduce(
        vcat,
        permutedims(interpolate_1d(t_want, t_col, view(by_level, k, :); bc))
        for k in axes(by_level, 1)
    )
end

"""
    fielddump_thermodynamics(fd, column; backend)

`(; z, time, pressure, exner, temperature, density)` for a fielddump.

`pressure` and `exner` are `(nz, nt)`, **not** three-dimensional: DALES has no 3-D pressure —
`modfielddump.f90:325-328` broadcasts the slab-mean hydrostatic `presf(k)` over x and y — and
storing it per point would cost hundreds of megabytes to hold a few hundred distinct numbers.

`temperature` is `Π θ_l + (L_v/c_p) q_l`, the equation DALES's own `tmp0` solves
(`modthermodynamics.f90:568`), and `density` is `p/(R_d T_v)` with `q_vapour = q_tot − q_liq`
and no ice, which is how `rhof` is formed. It is **not** the anelastic `rhobf` — see
[`anelastic_base_density`](@ref). Both are [`DerivedFielddumpVariable`](@ref)s and read nothing
until indexed.

`column` is a [`dales_slab_column`](@ref) of the same run, whose `presf` and `exner` are
interpolated linearly onto the fielddump's own levels and times — first along the levels,
then along the records. The two grids need not agree, and a `Float32` column against
`Float64` coordinates is fine.

`bc` says what happens where the fielddump runs off either end of the column. The default
[`ErrorBoundaryCondition`](@ref) refuses, naming the value and the range the column covers.
The published `profiles.001.nc` stops at [`PUBLISHED_RUNTIME_S`](@ref) while a paper-length
run reaches [`PAPER_RUNTIME_S`](@ref), so a fielddump from the latter is off the end of the
former: read that run's own profiles with `dales_slab_column(date; root)`, or pass
[`ExtrapolateBoundaryCondition`](@ref) or [`ConstantBoundaryCondition`](@ref) to say what
to do instead.

Where a run wrote `pressure`, `exner` or `temperature` of its own they stay in `fd.vars`
untouched; this function always derives, so the two never shadow each other.
"""
function fielddump_thermodynamics(
    fd, column;
    backend = DefaultThermodynamicsBackend(),
    bc::AbstractBoundaryCondition = ErrorBoundaryCondition(),
)
    for name in ("thl", "qt", "ql")
        haskey(fd.vars, name) ||
            error("`fielddump_thermodynamics` needs `$name`, which $(fd.source) lacks.")
    end
    θ_l, q_tot, q_liq = fd.vars["thl"], fd.vars["qt"], fd.vars["ql"]
    dims = fd.dims["thl"]
    zaxis, taxis = _fielddump_axes(dims)

    z = fd.coords[dims[zaxis]]
    time = fd.coords["time"]
    pressure = _column_onto(column.presf, column.z, column.time, z, time, bc)
    Π = _column_onto(column.exner, column.z, column.time, z, time, bc)

    FT = promote_type(eltype(pressure), eltype(θ_l))
    L_over_cp = L_v0(backend, FT) / cp_d(backend, FT)
    R = R_d(backend, FT)
    rvord = R_v(backend, FT) / R

    temperature_of(Πk, θ, q_l) = FT(Πk) * FT(θ) + L_over_cp * FT(q_l)
    function density_of(pk, Πk, θ, q_t, q_l)
        T = temperature_of(Πk, θ, q_l)
        q_vap = FT(q_t) - FT(q_l)
        return FT(pk) / (R * T * (one(FT) + (rvord - one(FT)) * q_vap - FT(q_l)))
    end

    sz = size(θ_l)
    N = length(sz)
    temperature = DerivedFielddumpVariable{FT, N, typeof((θ_l, q_liq)), typeof((Π,)), typeof(temperature_of)}(
        (θ_l, q_liq), (Π,), temperature_of, zaxis, taxis, sz, "K",
    )
    density = DerivedFielddumpVariable{
        FT, N, typeof((θ_l, q_tot, q_liq)), typeof((pressure, Π)), typeof(density_of),
    }(
        (θ_l, q_tot, q_liq), (pressure, Π), density_of, zaxis, taxis, sz, "kg m^-3",
    )
    return (; z, time, pressure, exner = Π, temperature, density)
end
