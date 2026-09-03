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

Test.@testset "the surface stitches onto the column" begin
    c = MA.case("20200503")
    f = MA.testbed_forcing(c)
    s = MA.surface_state(f)

    Test.@test s.z == 0
    Test.@test s.p == f.surface.ps
    Test.@test s.ta == MA.surface_temperature(f)
    Test.@test s.q == s.hus == MA.qseaicefrctsurf(f)
    Test.@test s.ql == s.qi == s.ua == s.va == s.wa == 0
    Test.@test eltype(f.ta) === typeof(s.ta)

    g = MA.forcing_with_surface(f)
    Test.@test length(g.z) == length(f.z) + 1
    Test.@test first(g.z) == 0
    Test.@test issorted(g.z)
    Test.@test g.z[2:end] == f.z
    for name in (:ta, :hus, :q, :ql, :qi, :ua, :va, :p, :wa)
        Test.@test getproperty(g, name)[1] == getproperty(s, name)
        Test.@test getproperty(g, name)[2:end] == getproperty(f, name)
    end
    # the terms with no surface value hold the lowest level
    for name in (:o3, :n_ccn, :tntha, :tnhusha, :tnua, :tnva, :ug, :vg)
        Test.@test getproperty(g, name)[1] == first(getproperty(f, name))
        Test.@test getproperty(g, name)[2:end] == getproperty(f, name)
    end
    Test.@test g.surface === f.surface

    # `ps` is the LES column's own surface pressure, not a second one
    presh = MA.read_variable("presh", c; file = :profiles, translate_units = false)
    Test.@test presh.data[1, 1] == f.surface.ps

    # the skin-to-air step is a surface layer, not a smooth continuation
    Test.@test s.ta != f.ta[1]
end

Test.@testset "interpolating the forcing onto a grid" begin
    f = MA.testbed_forcing("20200503")

    # exact at the source levels
    same = MA.interpolate_forcing(f, f.z)
    Test.@test same.z == f.z
    for name in (:ta, :q, :ua, :p, :ug)
        Test.@test getproperty(same, name) ≈ getproperty(f, name)
    end

    # linear between them: the midpoint of a cell is the mean of its ends
    k = 100
    zmid = (f.z[k] + f.z[k + 1]) / 2
    mid = MA.interpolate_forcing(f, [zmid])
    Test.@test mid.ta[1] ≈ (f.ta[k] + f.ta[k + 1]) / 2
    Test.@test mid.q[1] ≈ (f.q[k] + f.q[k + 1]) / 2

    # onto the LES grid, which starts at 5 m — inside the ERA5 column
    les = MA.interpolate_forcing(f, Float64.(MA.stretch_centres()))
    Test.@test length(les.z) == 286
    Test.@test all(isfinite, les.ta)
    Test.@test issorted(les.z)
    Test.@test minimum(les.ta) > 150 && maximum(les.ta) < 350

    # below the lowest ERA5 level it extrapolates the air, as DALES's unclamped `fac` does
    below = MA.interpolate_forcing(f, [0.0])
    Test.@test isfinite(below.ta[1])
    Test.@test below.ta[1] != MA.surface_state(f).ta   # the air, not the skin

    Test.@test f.surface === les.surface
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
