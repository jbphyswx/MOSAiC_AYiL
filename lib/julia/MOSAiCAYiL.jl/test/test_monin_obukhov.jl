using MOSAiCAYiL: MOSAiCAYiL as MA
using Test: Test

Test.@testset "the stability functions are continuous at neutral" begin
    # the branch boundary is the easiest thing to get wrong, and psim/psih switch at
    # `ζ <= 0` while phim/phih switch at `ζ < 0`
    Test.@test MA.psim(0.0) == 0
    Test.@test MA.psih(0.0) == 0
    Test.@test MA.phim(0.0) == 1
    Test.@test MA.phih(0.0) == 1
    for arctic_stable in (true, false)
        Test.@test MA.psim(-1.0e-12; arctic_stable) ≈ MA.psim(1.0e-12; arctic_stable) atol =
            1.0e-9
        Test.@test MA.psih(-1.0e-12; arctic_stable) ≈ MA.psih(1.0e-12; arctic_stable) atol =
            1.0e-9
        Test.@test MA.phim(-1.0e-12; arctic_stable) ≈ MA.phim(1.0e-12; arctic_stable) atol =
            1.0e-9
        Test.@test MA.phih(-1.0e-12; arctic_stable) ≈ MA.phih(1.0e-12; arctic_stable) atol =
            1.0e-9
    end
end

Test.@testset "the arctic branch is uncapped and the other is not" begin
    # the non-arctic branch is a hard cap for every stable zeta at or above one
    for ζ in (1.0, 5.0, 20.0, 50.0)
        Test.@test MA.phim(ζ; arctic_stable = false) == MA.STABILITY.phi_cap
        Test.@test MA.phih(ζ; arctic_stable = false) == MA.STABILITY.phi_cap
    end

    # the arctic momentum function grows without bound, so it passes the cap and keeps going
    Test.@test MA.phim(5.0) > MA.STABILITY.phi_cap
    Test.@test MA.phim(50.0) > MA.phim(5.0)
    # at zeta = 1 it is still *below* the cap, so the cap is not a clamp of this function
    Test.@test MA.phim(1.0) < MA.STABILITY.phi_cap

    # the arctic heat function approaches the cap from below and never reaches it:
    # (5z + 5z^2)/(1 + 3z + z^2) -> 5 as z -> infinity
    for ζ in (1.0, 5.0, 20.0, 50.0, 1.0e4)
        Test.@test 1 < MA.phih(ζ) < MA.STABILITY.phi_cap
    end
    Test.@test MA.phih(1.0e6) ≈ MA.STABILITY.phi_cap rtol = 1.0e-4

    # both increase monotonically on the stable side
    Test.@test issorted([MA.phim(ζ) for ζ in 0.0:0.5:50.0])
    Test.@test issorted([MA.phih(ζ) for ζ in 0.0:0.5:50.0])
    # and the unstable side falls below one
    Test.@test MA.phim(-1.0) < 1
    Test.@test MA.phih(-1.0) < 1
end

Test.@testset "obukhov_length inverts its own relation" begin
    z, z0m, z0h = 5.0, 2.2e-3, 2.2e-4
    for L in (0.5, 2.0, 10.0, 100.0, 1.0e4, -0.5, -2.0, -10.0, -100.0, -1.0e4)
        heat = log(z / z0h) - MA.psih(z / L) + MA.psih(z0h / L)
        momentum = log(z / z0m) - MA.psim(z / L) + MA.psim(z0m / L)
        Rib = z / L * heat / momentum^2
        Test.@test MA.obukhov_length(Rib, z, z0m, z0h) ≈ L rtol = 1.0e-3
    end

    # no surface flux, so DALES returns its cap
    Test.@test MA.obukhov_length(0.0, z, z0m, z0h) == 1.0e6
    # the logarithms need z above both roughness lengths
    Test.@test_throws ErrorException MA.obukhov_length(0.5, 1.0e-4, z0m, z0h)
    Test.@test_throws ErrorException MA.obukhov_length(0.5, z, z0m, 10.0)
    # a sign convention: stable air gives a positive length
    Test.@test MA.obukhov_length(0.05, z, z0m, z0h) > 0
    Test.@test MA.obukhov_length(-0.05, z, z0m, z0h) < 0
end

Test.@testset "drag coefficients and the neutral limit" begin
    z, z0m, z0h = 5.0, 2.2e-3, 2.2e-4
    κ = MA.DALES_CONSTANTS.von_karman
    neutral = MA.drag_coefficients(1.0e12, z, z0m, z0h)
    Test.@test neutral.C_m ≈ κ^2 / log(z / z0m)^2 rtol = 1.0e-6
    Test.@test neutral.C_s ≈ κ^2 / (log(z / z0m) * log(z / z0h)) rtol = 1.0e-6
    # heat is rougher to transfer than momentum here, so C_s is the smaller
    Test.@test neutral.C_s < neutral.C_m

    # stable air suppresses the exchange, unstable enhances it
    Test.@test MA.drag_coefficients(50.0, z, z0m, z0h).C_m < neutral.C_m
    Test.@test MA.drag_coefficients(-50.0, z, z0m, z0h).C_m > neutral.C_m
end

Test.@testset "surface_layer_fluxes signs and scaling" begin
    common = (;
        q_tot = 1.0e-3, wind_speed = 5.0, z = 5.0, q_skin = 1.2e-3,
        z0m = 2.2e-3, z0h = 2.2e-4,
    )
    # air colder than the skin: heat flows up
    warm = MA.surface_layer_fluxes(; θ_l = 265.0, θ_l_skin = 268.0, common...)
    Test.@test warm.θ_l_flux > 0
    Test.@test warm.Rib < 0
    Test.@test warm.L < 0
    Test.@test warm.ustar > 0
    Test.@test warm.θ_l_scale < 0                       # -flux/ustar

    # air warmer than the skin: heat flows down
    cold = MA.surface_layer_fluxes(; θ_l = 270.0, θ_l_skin = 268.0, common...)
    Test.@test cold.θ_l_flux < 0
    Test.@test cold.Rib > 0
    Test.@test cold.L > 0

    # r_a and ustar follow the wind
    windy = MA.surface_layer_fluxes(;
        θ_l = 265.0, θ_l_skin = 268.0, q_tot = 1.0e-3, q_skin = 1.2e-3,
        wind_speed = 10.0, z = 5.0, z0m = 2.2e-3, z0h = 2.2e-4,
    )
    Test.@test windy.ustar > warm.ustar
    Test.@test windy.r_a < warm.r_a
    Test.@test windy.ζ ≈ 5.0 / windy.L
end
