"""
    interpolation.jl

Linear interpolation on a monotone 1D axis, with an explicit out-of-range policy.

One core for every axis the package interpolates along — height, time, or a caller's own —
so the boundary behaviour is a stated choice rather than a property of whichever helper was
reached.
"""

"""Supertype for the out-of-range policies of a 1D interpolant."""
abstract type AbstractBoundaryCondition end

"""Error when evaluating outside the node range. The default everywhere."""
struct ErrorBoundaryCondition <: AbstractBoundaryCondition end

"""Linear extrapolation off the end segment, outside the node range."""
struct ExtrapolateBoundaryCondition <: AbstractBoundaryCondition end

"""Return the nearest endpoint value outside the node range."""
struct NearestBoundaryCondition <: AbstractBoundaryCondition end

"""
    ConstantBoundaryCondition(value)

Return `value` outside the node range, promoted to the type an in-range evaluation returns.
"""
struct ConstantBoundaryCondition{T} <: AbstractBoundaryCondition
    value::T
end

# The interval `x` falls in. `searchsortedlast` is already O(1) on an `AbstractRange` and
# O(log N) on a `Vector`, so the cost follows the axis's type; a descending axis is scanned
# in place rather than reversed.
@inline function _find_interval(xp, x, asc::Bool)
    N = length(xp)
    if asc
        i = searchsortedlast(xp, x)
    else
        i = 1
        @inbounds while i < N && xp[i] > x
            i += 1
        end
        i -= 1
    end
    return clamp(i, 1, N - 1)
end

# in the element type the in-range branches produce, so the return type does not depend on
# where `x` falls
@inline _const_value(bc::ConstantBoundaryCondition, xp, fp, x) =
    convert(promote_type(eltype(fp), eltype(xp), typeof(x)), bc.value)

@inline function _eval_linear(xp::AbstractVector, fp::AbstractVector, bc, x)
    N = length(xp)
    @inbounds x0n = xp[1]
    if isone(N)
        y1 = convert(promote_type(eltype(fp), eltype(xp), typeof(x)), @inbounds fp[1])
        if (bc isa NearestBoundaryCondition) || (bc isa ExtrapolateBoundaryCondition)
            return y1
        elseif bc isa ConstantBoundaryCondition
            return x == x0n ? y1 : _const_value(bc, xp, fp, x)
        else
            x == x0n || error("x = $x is off the single node $x0n.")
            return y1
        end
    end
    @inbounds xmin, xmax = xp[1], xp[N]
    asc = xmin <= xmax

    # the first-node end and the last-node end, which for a descending axis are reached by
    # the opposite comparisons
    if (asc && x < xmin) || (!asc && x > xmin)
        if bc isa NearestBoundaryCondition
            return @inbounds fp[1] + (fp[1] - fp[1]) * (x - x0n) / oneunit(x - x0n)
        elseif bc isa ExtrapolateBoundaryCondition
            return @inbounds fp[1] + (fp[2] - fp[1]) * (x - xp[1]) / (xp[2] - xp[1])
        elseif bc isa ConstantBoundaryCondition
            return _const_value(bc, xp, fp, x)
        else
            error("x = $x is outside the interpolation range [$xmin, $xmax].")
        end
    elseif (asc && x > xmax) || (!asc && x < xmax)
        if bc isa NearestBoundaryCondition
            return @inbounds fp[N] + (fp[N] - fp[N]) * (x - x0n) / oneunit(x - x0n)
        elseif bc isa ExtrapolateBoundaryCondition
            return @inbounds fp[N - 1] +
                             (fp[N] - fp[N - 1]) * (x - xp[N - 1]) / (xp[N] - xp[N - 1])
        elseif bc isa ConstantBoundaryCondition
            return _const_value(bc, xp, fp, x)
        else
            error("x = $x is outside the interpolation range [$xmin, $xmax].")
        end
    end

    i = _find_interval(xp, x, asc)
    @inbounds x0, x1 = xp[i], xp[i + 1]
    @inbounds y0, y1 = fp[i], fp[i + 1]
    return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
end

"""
    Linear1DInterpolant(xp, fp; bc = ErrorBoundaryCondition())

A callable linear interpolant through the nodes `xp` and values `fp`.

`xp` must be monotone; ascending and descending axes are both taken as given, and a
descending axis is not reversed. `bc` decides what happens outside `xp`.
"""
struct Linear1DInterpolant{
    X <: AbstractVector, F <: AbstractVector, B <: AbstractBoundaryCondition,
}
    xp::X
    fp::F
    bc::B
end

function Linear1DInterpolant(
    xp::AbstractVector, fp::AbstractVector; bc::AbstractBoundaryCondition = ErrorBoundaryCondition(),
)
    length(xp) == length(fp) ||
        error("Got $(length(xp)) nodes for $(length(fp)) values.")
    isempty(xp) && error("An interpolant needs at least one node.")
    return Linear1DInterpolant(xp, fp, bc)
end

(s::Linear1DInterpolant)(x) = _eval_linear(s.xp, s.fp, s.bc, x)
Base.broadcastable(s::Linear1DInterpolant) = tuple(s)

"""
    interpolate_1d(x, xp, fp; bc = ErrorBoundaryCondition())

`fp` interpolated linearly from the nodes `xp` onto `x`, a scalar or an array.

`bc` is the out-of-range policy: [`ErrorBoundaryCondition`](@ref) (the default),
[`ExtrapolateBoundaryCondition`](@ref), [`NearestBoundaryCondition`](@ref) or
[`ConstantBoundaryCondition`](@ref).

Pairs where either the node or the value is `missing` are dropped before interpolating, so
an archive array of `Union{Missing, Float32}` can be handed over as it is read.
"""
function interpolate_1d(
    x, xp::AbstractVector, fp::AbstractVector;
    bc::AbstractBoundaryCondition = ErrorBoundaryCondition(),
)
    xpT = Base.nonmissingtype(eltype(xp))
    fpT = Base.nonmissingtype(eltype(fp))
    if xpT != eltype(xp) || fpT != eltype(fp)
        length(xp) == length(fp) ||
            error("Got $(length(xp)) nodes for $(length(fp)) values.")
        valid = .!ismissing.(xp) .& .!ismissing.(fp)
        T = promote_type(xpT, fpT)
        xp, fp = T.(xp[valid]), T.(fp[valid])
    end
    return Linear1DInterpolant(xp, fp; bc).(x)
end
