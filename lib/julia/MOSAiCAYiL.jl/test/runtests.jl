using Test: Test
using MOSAiCAYiL: MOSAiCAYiL

# Aqua first, before weak-dep `using`s load extensions.
include("test_aqua.jl")
include("test_catalog.jl")
include("test_constants.jl")
include("test_thermodynamics.jl")
include("test_nudge.jl")
include("test_translations.jl")
include("test_day_tables.jl")
include("test_fielddump.jl")

if MOSAiCAYiL.data_available()
    include("test_data.jl")
else
    @info "Skipping archive tests: the lazy artifact is not installed."
end

include("test_parallel.jl")
include("test_zarr.jl")
