using MOSAiCAYiL: MOSAiCAYiL as MA
using Test: Test

# The committed tables are checked against the archive when they are regenerated, which is
# the only moment they can change. What can go wrong here is the lookup: a date resolving
# to the wrong row gives a plausible number for the wrong day.

Test.@testset "generated tables cover the catalog" begin
    n = MA.n_cases()
    for column in MA.DAY_SCALARS
        Test.@test length(column) == n
    end
    for column in MA.DAY_METADATA
        Test.@test length(column) == n
    end
end

Test.@testset "a date resolves to its own row" begin
    dates = collect(MA.MOSAiCAYiL_dates)
    for i in (1, 2, 95, MA.n_cases() - 1, MA.n_cases())
        d = dates[i]
        Test.@test MA.scm_in_levels(d) === MA.DAY_METADATA.n_levels[i]
        Test.@test MA.tskin_obs(d) === MA.DAY_METADATA.tskin_obs[i]
        Test.@test MA.inp_fletcher_n(d) === MA.DAY_METADATA.in_n_inucr[i]
        Test.@test MA.latitude(d) === MA.DAY_SCALARS.lat[i]
        Test.@test MA.ps(d) === MA.DAY_SCALARS.ps[i]

        # the same day named three ways is the same row
        Test.@test MA.scm_in_levels(MA.date_string(d)) === MA.scm_in_levels(d)
        Test.@test MA.scm_in_levels(MA.case(MA.date_string(d))) === MA.scm_in_levels(d)
    end
end

Test.@testset "the NamedTuple agrees with the accessors" begin
    d = MA.MOSAiCAYiL_dates[42]
    m = MA.day_metadata(d)
    Test.@test m.n_levels === MA.scm_in_levels(d)
    Test.@test m.tskin_obs === MA.tskin_obs(d)
    Test.@test m.tskin_seaice_correction === MA.tskin_seaice_correction(d)
    Test.@test m.in_n_inucr === MA.inp_fletcher_n(d)
    Test.@test m.in_b_inucr === MA.inp_fletcher_b(d)

    s = MA.day_scalars(d)
    Test.@test s.lat === MA.latitude(d)
    Test.@test s.n_ccn === MA.n_ccn(d)
end

Test.@testset "every day has an inversion inside the search window" begin
    # `inversion_height` returns 0 when no level lies in the window, so a zero here would
    # mean the tabulated day has no diagnosable inversion at all
    h = MA.DAY_METADATA.inversion_height
    Test.@test !any(iszero, h)
    Test.@test all(x -> MA.INVERSION_SEARCH_MIN < x < MA.INVERSION_SEARCH_MAX, h)
    d = MA.MOSAiCAYiL_dates[7]
    Test.@test MA.inversion_height(d) === h[7]
    Test.@test MA.day_metadata(d).inversion_height === MA.inversion_height(d)
end

Test.@testset "cloud tops are defined only where they exist" begin
    tabulated = sort(collect(keys(MA.CLOUD_TOP_M)))
    undetermined = sort(collect(MA.CLOUD_TOP_UNDETERMINED))

    # together they account for exactly the days a domain top is known for
    Test.@test sort(vcat(tabulated, undetermined)) == MA.best_dates()
    Test.@test isempty(intersect(tabulated, undetermined))

    # a tabulated top sits below that day's domain top, which is what makes it a top
    for d in tabulated
        Test.@test 0 < MA.cloud_top(d) <= MA.BEST_SIMULATION_TOP_F[d]
    end

    # a day whose cloud reaches the boundary errors rather than returning the boundary
    for d in undetermined
        Test.@test_throws ErrorException MA.cloud_top(d)
    end
    # and so does a day outside the set entirely
    Test.@test_throws ErrorException MA.cloud_top("20191017")
end

Test.@testset "the level count is a property of the day" begin
    # code that assumed one level count for the ensemble would be wrong on 169 of 190 days
    Test.@test length(unique(MA.DAY_METADATA.n_levels)) > 1
    Test.@test all(>(0), MA.DAY_METADATA.n_levels)
end
