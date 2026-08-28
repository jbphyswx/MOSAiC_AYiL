"""
    MOSAiCAYiLOhMyThreadsExt

Loads when `OhMyThreads` is available. Defines [`MOSAiCAYiL.ayil_tmap`](@ref).
"""
module MOSAiCAYiLOhMyThreadsExt

using OhMyThreads: OhMyThreads
using MOSAiCAYiL: MOSAiCAYiL

"""
    ayil_tmap(f, collection; kwargs...)

Threaded `map` via `OhMyThreads.tmap`. Extra keywords (`scheduler`, `ntasks`,
`chunksize`, …) are forwarded.
"""
function MOSAiCAYiL.ayil_tmap(f, collection; kwargs...)
    return OhMyThreads.tmap(f, collection; kwargs...)
end

end
