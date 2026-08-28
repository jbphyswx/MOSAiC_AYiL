using Dates: Dates
using MOSAiCAYiL: MOSAiCAYiL as MA
using Test: Test

Test.@testset "catalog" begin
    Test.@test MA.n_cases() == 190
    Test.@test length(MA.MOSAiCAYiL_dates) == 190
    ymd = map(MA.date_string, MA.MOSAiCAYiL_dates)
    Test.@test issorted(MA.MOSAiCAYiL_dates)
    Test.@test first(ymd) == "20191016"
    Test.@test last(ymd) == "20200911"
    Test.@test allunique(ymd)

    c = MA.case("20200503")
    Test.@test c isa MA.MOSAiCAYiLCase
    Test.@test MA.date_string(c) == "20200503"
    Test.@test MA.case_name(c) == "AYiL_20200503"
    Test.@test MA.date_index(c) == MA.date_index("20200503")
    Test.@test MA.is_MOSAiCAYiL_date("20200503")
    Test.@test !MA.is_MOSAiCAYiL_date("20190101")
    Test.@test_throws ErrorException MA.case("20190101")
    Test.@test_throws ErrorException MA.case("05-03-2020")
    Test.@test MA.case(c) === c
    Test.@test Dates.Date(c) == Dates.Date(2020, 5, 3)
end
