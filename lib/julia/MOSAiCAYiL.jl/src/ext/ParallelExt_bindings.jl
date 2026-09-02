# --- Optional weak-dep API (methods added when the parallel extensions load) ---
#
# `pmap`, `pforeach`, `pmapreduce` and `addprocs` come from `MOSAiCAYiLDistributedExt`
# (`using Distributed`); `tmap`, `tforeach`, `tmapreduce`, `treduce`, `tmap!` and `tcollect`
# from `MOSAiCAYiLOhMyThreadsExt` (`using OhMyThreads`).
#
# Reading this archive is bound by a lock: netcdf-c is not thread safe, and since
# NCDatasets 0.14.12 one process-global `ReentrantLock` serializes every one of its C
# calls
#

"""Items of `collection` as an indexable vector, which `tmap` requires and `pmap` orders by."""
_parallel_items(c::AbstractArray) = c
_parallel_items(c) = collect(c)

"""
    pmap(f, collection; kwargs...)

`f` mapped over `collection` across worker processes, results in input order.
"""
function pmap end

"""
    pforeach(f, collection; kwargs...)

`f` applied to each of `collection` across worker processes, returning `nothing`.
"""
function pforeach end

"""
    pmapreduce(f, op, collection; kwargs...)

`op` reduced over `f` mapped across worker processes.
"""
function pmapreduce end

"""
    addprocs(n; kwargs...)

Add `n` worker processes with `MOSAiCAYiL` loaded on each, returning their ids.
"""
function addprocs end

"""
    tmap(f, collection; kwargs...)

`f` mapped over `collection` across threads, results in input order.
"""
function tmap end

"""
    tforeach(f, collection; kwargs...)

`f` applied to each of `collection` across threads, returning `nothing`.
"""
function tforeach end

"""
    tmapreduce(f, op, collection; kwargs...)

`op` reduced over `f` mapped across threads.
"""
function tmapreduce end

"""
    treduce(op, collection; kwargs...)

`op` reduced over `collection` across threads.
"""
function treduce end

"""
    tmap!(f, out, collection; kwargs...)

`f` mapped over `collection` across threads, written into `out`.
"""
function tmap! end

"""
    tcollect(generator; kwargs...)

A generator collected across threads.
"""
function tcollect end
