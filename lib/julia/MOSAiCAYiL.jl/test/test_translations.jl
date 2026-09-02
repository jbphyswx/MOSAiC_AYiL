using MOSAiCAYiL: MOSAiCAYiL as MA
using Test: Test

Test.@testset "naming rules (no files)" begin
    Test.@test MA.physical_name("sv005") == "q_cloud_liquid"
    Test.@test MA.physical_name("sv006") == "n_ccn"
    Test.@test MA.physical_name("svp008") == "q_cloud_ice_tendency"
    Test.@test MA.physical_name("wsv002r") == "q_rain_flux_resolved"
    Test.@test MA.physical_name("dq_i_dep") == "q_ice_tendency_deposition"
    Test.@test_throws ErrorException MA.physical_name("dq_zz_dep")
    Test.@test_throws ErrorException MA.physical_name("thltendmicro")
end

Test.@testset "scm_in naming and routing (no files)" begin
    Test.@test MA.physical_name("t_local", :scm_in) == "temperature_midpoint"
    Test.@test MA.physical_name("t", :scm_in) == "temperature_domain_mean"
    Test.@test MA.physical_name("pressure_h", :scm_in) == "pressure_face"
    Test.@test MA.physical_name("sea_ice_frct", :scm_in) == "sea_ice_fraction"
    Test.@test_throws ErrorException MA.physical_name("not_a_variable", :scm_in)

    # the file states `n_ccn` per volume already, unlike the `sv` families
    Test.@test last(MA.SCM_IN["n_ccn"]) == "m^-3"
    _, _, ρ_power =
        MA.dales_variable_attributes("n_ccn", "n_ccn", "/m3", "CCN", :scm_in)
    Test.@test ρ_power == 0

    # `q_skin` carries its units and long name in each other's attribute
    units, long_name, _ = MA.dales_variable_attributes(
        "q_skin", "skin_reservoir_content", "skin reservoir content", "m of water", :scm_in,
    )
    Test.@test units == "m"
    Test.@test long_name == "skin reservoir content"

    Test.@test MA.variable_product("t_local") === :scm_in
    Test.@test MA.variable_product("omega") === :scm_in
    # the three names `profiles.001.nc` also carries have to be asked for by file
    for raw in ("u", "v", "ql")
        Test.@test_throws ErrorException MA.variable_product(raw)
        Test.@test MA.physical_name(raw, :scm_in) == first(MA.SCM_IN[raw])
    end
end

Test.@testset "a written forcing states the package's units (no files)" begin
    # every forcing field that is an `scm_in` variable must be written in the units
    # `read_variable` reports for it, or the package states two units for one quantity
    from_scm_in = (
        z = "height_f", ta = "t_local", q = "q_local", ql = "ql_local", qi = "qi_local",
        ua = "u_local", va = "v_local", p = "pressure_f", o3 = "o3", n_ccn = "n_ccn",
        tntha = "tadv", tnua = "uadv", tnva = "vadv", ug = "ug", vg = "vg",
    )
    for (field, raw) in pairs(from_scm_in)
        Test.@test getproperty(MA.FORCING_PROFILE_UNITS, field) == last(MA.SCM_IN[raw])
    end

    surface_from_scm_in = (
        ps = "ps", trajectory_latitude = "lat", trajectory_longitude = "lon",
        albedo = "albedo", albedo_snow = "albedo_snow", snow = "snow",
        z0_momentum = "mom_rough", z0_heat = "heat_rough",
        sea_ice_fraction = "sea_ice_frct", t_skin = "t_skin",
        t_skin_ocean = "t_skin_ocean", t_skin_seaice = "t_skin_seaice",
        open_sst = "open_sst", land_sea_mask = "lsm",
        sensible_heat_flux = "sfc_sens_flx", latent_heat_flux = "sfc_lat_flx",
    )
    for (field, raw) in pairs(surface_from_scm_in)
        Test.@test getproperty(MA.FORCING_SURFACE_UNITS, field) == last(MA.SCM_IN[raw])
    end

    # `hus`, `wa` and `tnhusha` are derived and have no single `scm_in` counterpart
    Test.@test MA.FORCING_PROFILE_UNITS.hus == "kg/kg"
    Test.@test MA.FORCING_PROFILE_UNITS.wa == "m/s"
    Test.@test MA.FORCING_PROFILE_UNITS.tnhusha == last(MA.SCM_IN["qadv"])
end

Test.@testset "unit attributes on synthetic labels" begin
    u, _, ρ_power = MA.dales_variable_attributes(
        "sv007",
        "n_cloud_ice",
        "kg/kg",
        "Scalar 007",
    )
    Test.@test u == "m^-3"
    Test.@test ρ_power == 1
    Test.@test MA.spelled_units("K/kg/s") == "K/s"
    Test.@test MA.spelled_units("kg/m2") == "kg/kg m/s"
end

Test.@testset "centre pressure / temperature on synthetic columns" begin
    b = MA.DefaultThermodynamicsBackend()
    zc = [5.0, 15.0]
    zf = [0.0, 10.0]
    ρ = [1.2, 1.1]
    p_face = [1.0e5, 9.9e4]
    p = MA.pressure_from_face(p_face, ρ, zc, zf)
    Test.@test all(p .< p_face)
    θ_l = [270.0, 271.0]
    q_l = [0.0, 1.0e-4]
    T = MA.temperature_from_liquid_ice_pottemp.(b, θ_l, p, q_l)
    Test.@test all(isfinite, T)
    Test.@test T[2] > MA.exner(b, p[2]) * θ_l[2]        # liquid warms θ_l → T
    Test.@test T[1] ≈ MA.exner(b, p[1]) * θ_l[1]        # no liquid, no warming
    # the inverse recovers θ_l
    Test.@test MA.liquid_ice_pottemp.(b, T, p, q_l) ≈ θ_l
end
