"""
    MOSAiCAYiLDistributedExt

Loads when `Distributed` is loaded. Multi-process sweeps over AYiL days.

Separate processes hold separate copies of NCDatasets' netCDF lock, so this is the backend
that makes archive reads concurrent.
"""
module MOSAiCAYiLDistributedExt

using Distributed: Distributed
using MOSAiCAYiL: MOSAiCAYiL

"""
    addprocs(n = Sys.CPU_THREADS - 1; load = true, kwargs...)

Add `n` worker processes and load `MOSAiCAYiL` on each, returning the new worker ids.

`Distributed.addprocs` alone leaves workers without the package, so every sweep over it
would fail on the first `MOSAiCAYiL` reference. `load = false` skips that step for a caller
loading its own module set. Extra keywords go to `addprocs` (`exeflags`, `dir`, `env`, …).
"""
function MOSAiCAYiL.addprocs(
    n::Integer = max(1, Sys.CPU_THREADS - 1);
    load::Bool = true,
    kwargs...,
)
    n > 0 || error("`n` must be positive; got $n.")
    added = Distributed.addprocs(n; kwargs...)
    load && Distributed.remotecall_eval(Main, added, :(using MOSAiCAYiL))
    return added
end

"""
    pmap(f, collection; pool, kwargs...)

`f` mapped over `collection` across worker processes, results in input order.

`collection` may be any iterable — a tuple of `Date`s, a `KeySet`, a generator — and is
materialized so the results can be ordered. Keywords are
[`Distributed.pmap`](@ref)'s: `on_error` to keep a sweep alive past a bad day,
`retry_delays`/`retry_check`, `batch_size`, `distributed`.

Workers need `MOSAiCAYiL`; [`addprocs`](@ref) is the way to get it there.

```julia
MOSAiCAYiL.addprocs(24)
tops = MOSAiCAYiL.pmap(MOSAiCAYiL.MOSAiCAYiL_dates) do date
    MOSAiCAYiL.ice_fields(date)
end
```
"""
function MOSAiCAYiL.pmap(
    f,
    collection;
    pool::Union{Distributed.AbstractWorkerPool, Nothing} = nothing,
    kwargs...,
)
    items = MOSAiCAYiL._parallel_items(collection)
    p = isnothing(pool) ? Distributed.CachingPool(Distributed.workers()) : pool
    return Distributed.pmap(f, p, items; kwargs...)
end

"""
    pforeach(f, collection; kwargs...)

`f` applied to each of `collection` across worker processes, returning `nothing`.

The results are discarded rather than gathered, so a sweep whose per-day value is large —
a full set of profiles — does not send it back to the caller.
"""
function MOSAiCAYiL.pforeach(f, collection; kwargs...)
    MOSAiCAYiL.pmap(x -> (f(x); nothing), collection; kwargs...)
    return nothing
end

"""
    pmapreduce(f, op, collection; init, kwargs...)

`op` reduced over `f` mapped across worker processes.

The map is distributed and the reduction is local, which is the right split while the map is
a file read and the reduction is arithmetic on its result.
"""
function MOSAiCAYiL.pmapreduce(f, op, collection; init = nothing, kwargs...)
    mapped = MOSAiCAYiL.pmap(f, collection; kwargs...)
    return isnothing(init) ? reduce(op, mapped) : reduce(op, mapped; init)
end

end