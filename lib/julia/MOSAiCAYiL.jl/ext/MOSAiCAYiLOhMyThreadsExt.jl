"""
    MOSAiCAYiLOhMyThreadsExt

Loads when `OhMyThreads` is available. Threaded map, reduce and foreach.

Threads share one process, so they also share NCDatasets' netCDF lock: work that opens
archive files serializes on it and contends. These are for work over data already in
memory; [`MOSAiCAYiL.pmap`](@ref) is the one that reads files concurrently.
"""
module MOSAiCAYiLOhMyThreadsExt

using OhMyThreads: OhMyThreads
using MOSAiCAYiL: MOSAiCAYiL

"""
    tmap(f, collection; scheduler = :dynamic, kwargs...)

`f` mapped over `collection` across threads, results in input order.

`collection` may be any iterable; `OhMyThreads.tmap` takes an `AbstractArray`, so a tuple of
`Date`s or a `KeySet` is materialized first. `scheduler` is `:dynamic`, `:static`,
`:greedy`, `:serial`, or a `Scheduler`; its own keywords (`ntasks`, `chunksize`, `split`)
are forwarded, and OhMyThreads accepts those only alongside a `Symbol` scheduler.
"""
MOSAiCAYiL.tmap(f, collection; kwargs...) =
    OhMyThreads.tmap(f, MOSAiCAYiL._parallel_items(collection); kwargs...)

"""
    tmap(f, T, collection; kwargs...)

As above, into a container of element type `T`, which allocates less than inferring it.
"""
MOSAiCAYiL.tmap(f, ::Type{T}, collection; kwargs...) where {T} =
    OhMyThreads.tmap(f, T, MOSAiCAYiL._parallel_items(collection); kwargs...)

"""
    tforeach(f, collection; kwargs...)

`f` applied to each of `collection` across threads, returning `nothing`.
"""
MOSAiCAYiL.tforeach(f, collection; kwargs...) =
    OhMyThreads.tforeach(f, MOSAiCAYiL._parallel_items(collection); kwargs...)

"""
    tmapreduce(f, op, collection; kwargs...)

`op` reduced over `f` mapped across threads. Both halves are threaded, unlike
[`MOSAiCAYiL.pmapreduce`](@ref), whose reduction is local.
"""
MOSAiCAYiL.tmapreduce(f, op, collection; kwargs...) =
    OhMyThreads.tmapreduce(f, op, MOSAiCAYiL._parallel_items(collection); kwargs...)

"""
    treduce(op, collection; kwargs...)

`op` reduced over `collection` across threads. `op` must be associative.
"""
MOSAiCAYiL.treduce(op, collection; kwargs...) =
    OhMyThreads.treduce(op, MOSAiCAYiL._parallel_items(collection); kwargs...)

"""
    tmap!(f, out, collection; kwargs...)

`f` mapped over `collection` across threads, written into `out`, which is returned.
"""
MOSAiCAYiL.tmap!(f, out, collection; kwargs...) =
    OhMyThreads.tmap!(f, out, MOSAiCAYiL._parallel_items(collection); kwargs...)

"""
    tcollect(generator; kwargs...)

A generator collected across threads, in order.
"""
MOSAiCAYiL.tcollect(generator; kwargs...) =
    OhMyThreads.tcollect(generator; kwargs...)

MOSAiCAYiL.tcollect(::Type{T}, generator; kwargs...) where {T} =
    OhMyThreads.tcollect(T, generator; kwargs...)

end
