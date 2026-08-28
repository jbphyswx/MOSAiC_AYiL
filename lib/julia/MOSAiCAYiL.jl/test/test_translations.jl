using MOSAiCAYiL: MOSAiCAYiL as MA
using Test: Test

Test.@testset "naming rules (no files)" begin
    Test.@test MA.dales_description("sv005") == "q_cloud_liquid"
    Test.@test MA.dales_description("sv006") == "n_ccn"
    Test.@test MA.dales_description("svp008") == "q_cloud_ice_tendency"
    Test.@test MA.dales_description("wsv002r") == "q_rain_flux_resolved"
    Test.@test MA.dales_description("dq_i_dep") == "q_ice_tendency_deposition"
    Test.@test_throws ErrorException MA.dales_description("dq_zz_dep")
    Test.@test_throws ErrorException MA.dales_description("thltendmicro")
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

Test.@testset "dales_presf / temperature on synthetic columns" begin
    zc = [5.0, 15.0]
    zf = [0.0, 10.0]
    ρ = [1.2, 1.1]
    p_face = [1.0e5, 9.9e4]
    p = MA.dales_presf(p_face, ρ, zc, zf)
    Test.@test all(p .< p_face)
    θ_l = [270.0, 271.0]
    q_l = [0.0, 1.0e-4]
    T = MA.dales_temperature(θ_l, q_l, p_face, ρ, zc, zf)
    Test.@test all(isfinite, T)
    Test.@test T[2] > MA.dales_exner(p[2]) * θ_l[2]  # liquid warms θ_l → T
end
