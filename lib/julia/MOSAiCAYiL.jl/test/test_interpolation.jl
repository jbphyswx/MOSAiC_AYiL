using MOSAiCAYiL: MOSAiCAYiL as MA
using Test: Test

const ASC_X = [0.0, 1.0, 2.0, 3.0]
const ASC_F = [0.0, 10.0, 20.0, 30.0]

Test.@testset "linear interpolation is the same on an ascending and a descending axis" begin
    bc = MA.ErrorBoundaryCondition()
    for x in (0.0, 0.5, 1.5, 2.25, 3.0)
        Test.@test MA.interpolate_1d(x, ASC_X, ASC_F; bc) ==
                   MA.interpolate_1d(x, reverse(ASC_X), reverse(ASC_F); bc)
    end
    # the nodes come back exactly, so the interval search is not off by one
    Test.@test MA.interpolate_1d(ASC_X, ASC_X, ASC_F; bc) == ASC_F
    Test.@test MA.interpolate_1d(1.5, ASC_X, ASC_F; bc) == 15.0
end

Test.@testset "every boundary condition on both ends of both orientations" begin
    below, above = -1.0, 4.0
    for (xp, fp) in ((ASC_X, ASC_F), (reverse(ASC_X), reverse(ASC_F)))
        for x in (below, above)
            Test.@test_throws ErrorException MA.interpolate_1d(
                x, xp, fp; bc = MA.ErrorBoundaryCondition(),
            )
        end
        # linear off the end segment, which is the slope of 10 per unit
        Test.@test MA.interpolate_1d(below, xp, fp; bc = MA.ExtrapolateBoundaryCondition()) ==
                   -10.0
        Test.@test MA.interpolate_1d(above, xp, fp; bc = MA.ExtrapolateBoundaryCondition()) ==
                   40.0
        # the value at the nearer end, not the nearer node's neighbour
        Test.@test MA.interpolate_1d(below, xp, fp; bc = MA.NearestBoundaryCondition()) == 0.0
        Test.@test MA.interpolate_1d(above, xp, fp; bc = MA.NearestBoundaryCondition()) == 30.0
        # a constant boundary returns the constant rather than erroring
        for x in (below, above)
            Test.@test MA.interpolate_1d(
                x, xp, fp; bc = MA.ConstantBoundaryCondition(-7.0),
            ) == -7.0
        end
    end
end

Test.@testset "a single node" begin
    xp, fp = [2.0], [5.0]
    for bc in (MA.ExtrapolateBoundaryCondition(), MA.NearestBoundaryCondition())
        Test.@test MA.interpolate_1d(2.0, xp, fp; bc) == 5.0
        Test.@test MA.interpolate_1d(9.0, xp, fp; bc) == 5.0
    end
    Test.@test MA.interpolate_1d(2.0, xp, fp; bc = MA.ErrorBoundaryCondition()) == 5.0
    Test.@test_throws ErrorException MA.interpolate_1d(
        9.0, xp, fp; bc = MA.ErrorBoundaryCondition(),
    )
    bc = MA.ConstantBoundaryCondition(-7.0)
    Test.@test MA.interpolate_1d(2.0, xp, fp; bc) == 5.0
    Test.@test MA.interpolate_1d(9.0, xp, fp; bc) == -7.0
end

Test.@testset "the return type does not depend on where x falls" begin
    for bc in (
        MA.ExtrapolateBoundaryCondition(),
        MA.NearestBoundaryCondition(),
        MA.ConstantBoundaryCondition(-7.0),
    )
        inside = MA.interpolate_1d(1.5, ASC_X, ASC_F; bc)
        outside = MA.interpolate_1d(9.0, ASC_X, ASC_F; bc)
        Test.@test typeof(inside) === typeof(outside)
        Test.@test Base.return_types(
            (x, s) -> s(x),
            (Float64, MA.Linear1DInterpolant{Vector{Float64}, Vector{Float64}, typeof(bc)}),
        ) == [Float64]
    end
    # the eltype follows the data rather than the Float64 literals of the algorithm
    Test.@test MA.interpolate_1d(
        1.5f0, Float32.(ASC_X), Float32.(ASC_F); bc = MA.NearestBoundaryCondition(),
    ) isa Float32
end

Test.@testset "evaluating allocates nothing" begin
    s = MA.Linear1DInterpolant(ASC_X, ASC_F; bc = MA.ExtrapolateBoundaryCondition())
    s(1.5)
    s(9.0)
    Test.@test (@allocated s(1.5)) == 0
    Test.@test (@allocated s(9.0)) == 0
end

Test.@testset "a missing node or value drops the pair" begin
    xp = Union{Missing, Float64}[0.0, missing, 2.0, 3.0]
    fp = Union{Missing, Float64}[0.0, 10.0, 20.0, missing]
    # what survives is (0, 0) and (2, 20), so the midpoint is 10
    Test.@test MA.interpolate_1d(1.0, xp, fp; bc = MA.ErrorBoundaryCondition()) == 10.0
    Test.@test MA.interpolate_1d(1.0, xp, fp; bc = MA.ErrorBoundaryCondition()) isa Float64
end

Test.@testset "the shape of the nodes and values is checked" begin
    Test.@test_throws ErrorException MA.Linear1DInterpolant(ASC_X, ASC_F[1:2])
    Test.@test_throws ErrorException MA.Linear1DInterpolant(Float64[], Float64[])
end
