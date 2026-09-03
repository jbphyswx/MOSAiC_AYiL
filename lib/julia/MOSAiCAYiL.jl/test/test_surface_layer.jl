using MOSAiCAYiL: MOSAiCAYiL as MA
using Test: Test

# `tmser.001.nc` samples every 60 s and `profiles.001.nc` every 300 s, so t = 1200 s is
# tmser record 20 and profiles record 4.
const SURFACE_COMPARISON_TIME_S = 1200.0f0
const SURFACE_PROFILES_INDEX = 4

Test.@testset "dales_surface_layer reproduces the archive's own surface time series" begin
    # a stable day and an unstable one, so a sign error cannot pass
    for (date, stable) in (("20200503", false), ("20200720", true))
        series = MA.read_variable("obukh", date; file = :tmser, translate_units = false)
        k = findfirst(==(SURFACE_COMPARISON_TIME_S), series.time)
        Test.@test k !== nothing
        reference(name) = Float64(
            MA.read_variable(name, date; file = :tmser, translate_units = false).data[k],
        )

        got = MA.dales_surface_layer(date; time_index = SURFACE_PROFILES_INDEX)

        Test.@test (got.Rib > 0) == stable
        Test.@test sign(got.L) == sign(reference("obukh"))
        Test.@test MA.surface_pottemp(MA.case(date)) ≈ reference("thlskin") rtol = 1.0e-4

        # 10 %: the reference is a 60 s sample of a limited scheme carrying the previous
        # step's Obukhov length, and this is a 300 s slab mean solved from the reset
        Test.@test got.L ≈ reference("obukh") rtol = 0.10
        Test.@test got.ustar ≈ reference("ustar") rtol = 0.10
        Test.@test got.θ_l_flux ≈ reference("wtheta") rtol = 0.10
        Test.@test got.q_tot_flux ≈ reference("wq") rtol = 0.10

        # the returned parts hang together
        column = MA.dales_slab_column(date, Float64)
        wind = max(
            hypot(
                column.u[1, SURFACE_PROFILES_INDEX], column.v[1, SURFACE_PROFILES_INDEX],
            ),
            MA.SURFACE_LAYER.wind_floor,
        )
        Test.@test got.r_a ≈ 1 / (got.C_s * wind)
        Test.@test got.ustar ≈ sqrt(got.C_m) * wind
        Test.@test got.θ_l_scale ≈ -got.θ_l_flux / got.ustar
        Test.@test got.q_scale ≈ -got.q_tot_flux / got.ustar
    end
end

Test.@testset "the surface layer is evaluated at the model's own first level" begin
    date = "20200503"
    column = MA.dales_slab_column(date, Float64)
    got = MA.dales_surface_layer(date; time_index = SURFACE_PROFILES_INDEX)
    # ζ = z/L at DALES's first level, 5 m, not at ERA5's lowest level of 2 m
    Test.@test got.ζ ≈ column.z[1] / got.L
    Test.@test column.z[1] ≈ 5.0
end
