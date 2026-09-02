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
    fd = MA.testbed_forcing(c)
    Test.@test eltype(fd.z) === Float32
    Test.@test issorted(fd.z)
    Test.@test length(fd.z) == 3040
    Test.@test fd.hus ≈ fd.q .+ fd.ql .+ fd.qi
    Test.@test fd.surface.sensible_heat_flux === missing
    Test.@test fd.surface.latent_heat_flux === missing
    Test.@test -180 <= fd.surface.trajectory_longitude < 180
    Test.@test MA.testbed_forcing(c; time_index = 1).ta ==
               MA.testbed_forcing(c; time_index = 2).ta
    Test.@test MA.surface_temperature(fd) ≈ fd.surface.t_skin atol = 1.0e-4
end

Test.@testset "fromztop reproduces the archive's own pressure" begin
    b = MA.DefaultThermodynamicsBackend()
    date = "20200503"
    rd(v) = Float64.(MA.read_variable(v, date; file = :profiles, translate_units = false).data)
    zt = vec(rd("zt"))
    thl, qt, ql = rd("thl")[:, 1], rd("qt")[:, 1], rd("ql")[:, 1]
    thv, presh = rd("thv")[:, 1], rd("presh")[:, 1]
    ps = presh[1]                       # DALES starts the half-level branch at the surface

    # DALES integrates the dry potential temperature, which it forms from theta_l; the
    # exner it needs is the pressure being solved for, so this iterates as DALES does
    theta_dry(p) = thl .+ (MA.L_v0(b) / MA.cp_d(b)) .* ql ./ MA.exner.(b, p)
    p = copy(presh)
    local out
    for _ in 1:12
        out = MA.pressure_fromztop(ps, theta_dry(p), qt, ql, zt)
        p = out.presf
    end
    Test.@test maximum(abs, (out.presh .- presh) ./ presh) < 1.0e-5

    # the archive's `thv` is the full-level theta_v the half-level branch steps through
    (; dzf) = MA.vertical_metrics(zt)
    κ, g = MA.R_d(b) / MA.cp_d(b), MA.grav(b)
    cp, p0 = MA.cp_d(b), MA.p_ref(b)
    ph = similar(presh)
    ph[1] = ps
    for k in 2:length(ph)
        ph[k] = (ph[k - 1]^κ - g * p0^κ * dzf[k - 1] / (cp * thv[k - 1]))^(1 / κ)
    end
    Test.@test maximum(abs, (ph .- presh) ./ presh) < 1.0e-5

    # `presf` is a different quantity: using it as the stored `presh` is a 1% error
    Test.@test maximum(abs, (out.presf .- presh) ./ presh) > 1.0e-2

    # the adjustment closes on every level of a real column
    for k in eachindex(zt)
        (; T, q_liq, q_ice) = MA.saturation_adjust_pθq(b, out.presf[k], thl[k], qt[k])
        Test.@test MA.liquid_ice_pottemp(b, T, out.presf[k], q_liq + q_ice) ≈ thl[k] atol = 1.0e-6
    end
end

Test.@testset "the tabulated inversion is the one the package computes" begin
    date = "20200503"
    thl = MA.read_variable("thl", date; file = :profiles, translate_units = false)
    live = MA.inversion_height(
        Float64.(thl.data[:, 1]), Float64.(thl.z),
        MA.INVERSION_SEARCH_MIN, MA.INVERSION_SEARCH_MAX,
    )
    Test.@test MA.inversion_height(date) == live
end

Test.@testset "day scalars vs scm_in" begin
    c = MA.case("20200503")
    fd = MA.testbed_forcing(c)
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
        fd = MA.testbed_forcing(ymd)
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
    direct = MA.testbed_forcing(c)
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
