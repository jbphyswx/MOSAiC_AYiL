"""
    MOSAiCAYiLDistributedExt

Loads when `Distributed` is loaded. Defines [`MOSAiCAYiL.ayil_pmap`](@ref) for
mapping a reader or table extraction over a collection of AYiL days.

Workers must have this package loaded (`@everywhere using MOSAiCAYiL`).
"""
module MOSAiCAYiLDistributedExt

using Distributed: Distributed
using MOSAiCAYiL: MOSAiCAYiL

"""
    ayil_pmap(f, dates; kwargs...)

[`Distributed.pmap`](@ref) over `dates`. `f` is applied to each element — typically
a `MOSAiCAYiLCase`, a `yyyymmdd` string, or a `Date`. Extra keywords are forwarded
to `pmap`.
"""
function MOSAiCAYiL.ayil_pmap(f, dates; kwargs...)
    return Distributed.pmap(f, dates; kwargs...)
end

end
