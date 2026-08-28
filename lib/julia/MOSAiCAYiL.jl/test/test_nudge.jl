using MOSAiCAYiL: MOSAiCAYiL as MA
using Test: Test

Test.@testset "nudging ramp" begin
    z_inv, depth = 700.0, 300.0
    z_mid = z_inv + depth
    Test.@test MA.nudge_ramp(0.0, z_inv, z_mid) == 0
    Test.@test MA.nudge_ramp(z_inv, z_inv, z_mid) == 0
    Test.@test MA.nudge_ramp(z_inv + 150, z_inv, z_mid) ≈ 0.5
    Test.@test MA.nudge_ramp(z_mid, z_inv, z_mid) ≈ 1
    Test.@test MA.nudge_ramp(z_mid + 5000, z_inv, z_mid) ≈ 1
    Test.@test MA.nudge_ramp(z_inv, z_inv, z_inv) == 0
    Test.@test MA.nudge_ramp(z_inv + 1, z_inv, z_inv) == 1
end

Test.@testset "inversion height" begin
    # a θ_l profile with a sharp jump: the centred difference peaks one level
    # *below* the jump (`modtestbed.f90:1521-1543`).
    z = collect(50.0:100.0:1950.0)
    θ = 280.0 .+ 0.001 .* z
    k_jump = 8
    θ[k_jump] += 10.0
    Test.@test MA.inversion_height(θ, z, 100.0, 2000.0) == z[k_jump - 1]

    z_above = MA.inversion_height(θ, z, 1200.0, 2000.0)
    Test.@test 1200.0 < z_above < 2000.0

    Test.@test MA.inversion_height(θ, z, 100.0, 120.0) == 0
    Test.@test MA.inversion_height(θ, z, 1900.0, 100.0) == 0
    Test.@test MA.inversion_height(θ, z, 0.0, 1.0e5) > first(z)
    Test.@test MA.inversion_height(θ, z, 0.0, 1.0e5) < last(z)
    Test.@test MA.inversion_height(280.0 .+ 0.001 .* z, z, 100.0, 2000.0) > 0
end
