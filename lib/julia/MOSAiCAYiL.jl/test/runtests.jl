using Test: Test
using MOSAiCAYiL: MOSAiCAYiL

# Aqua first, before weak-dep `using`s load extensions.
include("test_aqua.jl")
include("test_catalog.jl")
include("test_constants.jl")
include("test_nudge.jl")
include("test_translations.jl")

if MOSAiCAYiL.data_available()
    include("test_data.jl")
else
    @info "Skipping archive tests: the lazy artifact is not installed."
end

Test.@testset "OhMyThreads extension" begin
    using OhMyThreads: OhMyThreads
    Test.@test Base.get_extension(MOSAiCAYiL, :MOSAiCAYiLOhMyThreadsExt) !== nothing
    Test.@test MOSAiCAYiL.ayil_tmap(identity, 1:4) == collect(1:4)
end

Test.@testset "Distributed extension" begin
    using Distributed: Distributed
    Test.@test Base.get_extension(MOSAiCAYiL, :MOSAiCAYiLDistributedExt) !== nothing
    Test.@test MOSAiCAYiL.ayil_pmap(identity, ["20191016", "20200503"]) ==
               ["20191016", "20200503"]
end
