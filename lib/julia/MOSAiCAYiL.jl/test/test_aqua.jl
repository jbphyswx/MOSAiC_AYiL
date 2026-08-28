using Aqua: Aqua
using MOSAiCAYiL: MOSAiCAYiL
using Test: Test

Test.@testset "Aqua.jl" begin
    Aqua.test_all(
        MOSAiCAYiL;
        ambiguities = true,
        unbound_args = true,
        undefined_exports = true,
        project_extras = true,
        stale_deps = true,
        deps_compat = true,
        persistent_tasks = false,
    )
end
