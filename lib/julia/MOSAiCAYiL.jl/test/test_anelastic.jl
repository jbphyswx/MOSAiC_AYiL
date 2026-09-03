using MOSAiCAYiL: MOSAiCAYiL as MA
using Test: Test

Test.@testset "the shipped baseprof is one day's" begin
    file = MA.read_baseprof("20200503")
    Test.@test length(file.rhobf) == 286
    Test.@test length(file.z) == 286
    Test.@test issorted(file.rhobf; rev = true)

    # the archive ships the same file in every day directory
    Test.@test MA.read_baseprof("20200720").rhobf == file.rhobf

    # and it is the construction of exactly one day, by a wide margin
    fits = map(collect(MA.MOSAiCAYiL_dates)) do d
        ρ = MA.anelastic_base_density(MA.case(MA.date_string(d)))
        (maximum(abs, (ρ .- file.rhobf) ./ file.rhobf), MA.date_string(d))
    end
    sort!(fits)
    Test.@test last(first(fits)) == MA.ARCHIVE_BASEPROF_DATE
    Test.@test first(first(fits)) < 1.0e-5
    # the next-best day is orders of magnitude worse, so this is not a loose fit
    Test.@test first(fits[2]) > 1.0e-3

    # a day that is not it misses by percent, which is why the per-day function exists
    other = MA.anelastic_base_density(MA.case("20200503"))
    Test.@test maximum(abs, (other .- file.rhobf) ./ file.rhobf) > 1.0e-2
end

Test.@testset "anelastic_base_state follows DALES's recursion" begin
    ρ = MA.anelastic_base_density(MA.case(MA.ARCHIVE_BASEPROF_DATE))
    kmax = length(MA.LES_CENTRES)
    state = MA.anelastic_base_state(ρ, MA.LES_CENTRES)

    Test.@test length(state.rhobf) == kmax + 1
    Test.@test length(state.rhobh) == kmax + 1
    Test.@test length(state.drhobdzf) == kmax + 1
    Test.@test length(state.drhobdzh) == kmax + 1

    Test.@test state.rhobf[1:kmax] == ρ
    # the surface half level sits below the first centre, so it is denser
    Test.@test state.rhobh[1] > state.rhobf[1]
    # density falls monotonically through a standard atmosphere
    Test.@test all(<(0), state.drhobdzf)
    Test.@test issorted(state.rhobh; rev = true)

    Test.@test_throws ErrorException MA.anelastic_base_state(ρ, MA.LES_CENTRES[1:(end - 1)])
end

Test.@testset "the base state is not air density" begin
    date = MA.ARCHIVE_BASEPROF_DATE
    rhob = MA.anelastic_base_density(MA.case(date))
    _, rhof = MA.les_density(date)
    # `rhobf` is a dry reference profile and `rhof` is the thermodynamic density; the
    # package warns against conflating them, so they must actually differ
    Test.@test maximum(abs, (rhob .- Float64.(rhof)) ./ Float64.(rhof)) > 1.0e-3
end

Test.@testset "STANDARD_ATMOSPHERE" begin
    Test.@test length(MA.STANDARD_ATMOSPHERE.z) == length(MA.STANDARD_ATMOSPHERE.lapse_rate)
    Test.@test issorted(MA.STANDARD_ATMOSPHERE.z)
    Test.@test MA.STANDARD_ATMOSPHERE.lapse_rate[1] < 0        # the troposphere
    Test.@test MA.STANDARD_ATMOSPHERE.lapse_rate[2] == 0       # the isothermal branch
    # the LES column stays inside the first breakpoint's layer and the one above it
    Test.@test last(MA.LES_CENTRES) < MA.STANDARD_ATMOSPHERE.z[2]
end
