using MOSAiCAYiL: MOSAiCAYiL as MA
using Test: Test

Test.@testset "190 days present" begin
    dates = MA.available_dates()
    Test.@test length(dates) == 190
    Test.@test dates == collect(MA.MOSAiCAYiL_dates)
    Test.@test issorted(dates)
end

Test.@testset "scm_in 20200503" begin
    c = MA.case("20200503")
    fd = MA.read_scm_in(c)
    Test.@test eltype(fd.z) === Float32
    Test.@test issorted(fd.z)
    Test.@test length(fd.z) == 3040
    Test.@test fd.hus ≈ fd.q .+ fd.ql .+ fd.qi
    Test.@test fd.surface.sensible_heat_flux === missing
    Test.@test fd.surface.latent_heat_flux === missing
    Test.@test -180 <= fd.surface.trajectory_longitude < 180
    Test.@test MA.read_scm_in(c; time_index = 1).ta ==
               MA.read_scm_in(c; time_index = 2).ta
    Test.@test MA.surface_temperature(fd) ≈ fd.surface.t_skin atol = 1.0e-4
end

Test.@testset "day scalars vs scm_in" begin
    c = MA.case("20200503")
    fd = MA.read_scm_in(c)
    Test.@test MA.latitude(c) == fd.surface.trajectory_latitude
    Test.@test MA.longitude(c) == fd.surface.trajectory_longitude
    Test.@test MA.n_ccn(c) == first(fd.n_ccn)
    Test.@test extrema(fd.n_ccn) == (MA.n_ccn(c), MA.n_ccn(c))
end

Test.@testset "every day's n_ccn and thermo hadv" begin
    disagreeing_ccn = String[]
    disagreeing_hadv = String[]
    for d in MA.MOSAiCAYiL_dates
        ymd = MA.date_string(d)
        fd = MA.read_scm_in(ymd)
        tabulated = MA.n_ccn(ymd)
        lo, hi = extrema(fd.n_ccn)
        (lo == hi == tabulated) || push!(disagreeing_ccn, ymd)
        if !all(iszero, fd.tntha) || !all(iszero, fd.tnhusha)
            push!(disagreeing_hadv, ymd)
        end
    end
    Test.@test isempty(disagreeing_ccn)
    Test.@test isempty(disagreeing_hadv)
end

Test.@testset "forcing file round-trip" begin
    c = MA.case("20200503")
    direct = MA.read_scm_in(c)
    mktempdir() do dir
        path = MA.write_forcing_file(joinpath(dir, "forcing.nc"), c)
        back = MA.read_forcing_file(path)
        for name in keys(MA.FORCING_PROFILE_UNITS)
            a, b = getproperty(direct, name), getproperty(back, name)
            Test.@test eltype(a) == eltype(b)
            Test.@test a == b
        end
        for name in keys(MA.FORCING_SURFACE_UNITS)
            Test.@test isequal(
                getproperty(direct.surface, name),
                getproperty(back.surface, name),
            )
        end
        Test.@test back.nudging == MA.nudging_parameters(c)
    end
end
