using MOSAiCAYiL: MOSAiCAYiL as MA
using Test: Test

Test.@testset "the centres and the faces are one grid" begin
    Test.@test length(MA.LES_CENTRES) == 286
    Test.@test issorted(MA.LES_CENTRES)
    Test.@test first(MA.LES_CENTRES) == 5.0

    # the centres recurse back to the stored faces exactly, which is what ties the two
    # independently-stated constants together
    Test.@test Float32.(MA.vertical_metrics(MA.LES_CENTRES).zh) == MA.LES_FACES

    Test.@test Float32(first(MA.LES_CENTRES)) == MA.LES_Z_CENTRE_BOTTOM
    Test.@test Float32(last(MA.LES_CENTRES)) == MA.LES_Z_CENTRE_TOP
end

Test.@testset "vertical_metrics reports the faces it builds" begin
    vm = MA.vertical_metrics(MA.LES_CENTRES)
    kmax = length(MA.LES_CENTRES)
    Test.@test length(vm.zh) == kmax + 1
    Test.@test length(vm.zf) == kmax + 1
    Test.@test length(vm.dzf) == kmax + 1
    Test.@test length(vm.dzh) == kmax + 1
    Test.@test vm.zh[1] == 0
    Test.@test issorted(vm.zh)
    # dzf is the thickness between the faces it returns
    Test.@test vm.dzf[1:kmax] ≈ diff(vm.zh)
    # and the centres sit midway between them, DALES's own relation
    Test.@test vm.zf[1:kmax] ≈ (vm.zh[1:kmax] .+ vm.zh[2:(kmax + 1)]) ./ 2
end
