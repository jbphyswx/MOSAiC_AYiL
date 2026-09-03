using MOSAiCAYiL: MOSAiCAYiL as MA
using Test: Test

Test.@testset "lacz_gamma reproduces the gamma function" begin
    Γ = MA.lacz_gamma

    # exact values
    Test.@test Γ(1.0) == 1.0
    Test.@test Γ(2.0) == 1.0
    Test.@test Γ(3.0) == 2.0
    Test.@test Γ(5.0) == 24.0
    Test.@test Γ(0.5) ≈ sqrt(pi)
    Test.@test Γ(-0.5) ≈ -2 * sqrt(pi)

    # Γ(n) = (n-1)!, crossing the branch boundary at 12
    for n in 2:20
        Test.@test Γ(Float64(n)) ≈ Float64(factorial(big(n - 1))) rtol = 1.0e-13
    end

    # the recurrence ties the four branches together
    for x in (0.001, 0.3, 0.9, 1.1, 3.7, 11.5, 11.9, 12.5, 30.0, 100.0, 170.0)
        Test.@test Γ(x + 1) ≈ x * Γ(x) rtol = 1.0e-12
    end

    # and the reflection formula exercises the negative branch
    for x in (0.1, 0.25, 0.4, 0.7, -0.3, -1.4, -2.7, -5.5)
        Test.@test Γ(x) * Γ(1 - x) ≈ pi / sin(pi * x) rtol = 1.0e-12
    end

    # poles and overflow return the Fortran's error value rather than throwing
    Test.@test Γ(0.0) == 1.79e308
    Test.@test Γ(-1.0) == 1.79e308
    Test.@test Γ(-4.0) == 1.79e308
    Test.@test Γ(200.0) == 1.79e308
    # but a point just off a pole is finite
    Test.@test isfinite(Γ(-1.0000300003000029))
end

Test.@testset "the kernels satisfy their own algebra" begin
    p = MA.SB3_PARTICLES

    for s in keys(p)
        # the zeroth moment is one by construction
        Test.@test MA.sb3_cons_mmt(0, p[s].μ, p[s].ν) ≈ 1.0
        # the fall-speed constant is linear in alpha
        Test.@test MA.sb3_cons_v(0, p[s].μ, p[s].ν, 2 * p[s].α, p[s].β) ≈
                   2 * MA.sb3_cons_v(0, p[s].μ, p[s].ν, p[s].α, p[s].β)
        # ventilation is linear in its coefficient
        Test.@test MA.sb3_avent(1, p[s].μ, p[s].ν, p[s].b; a_v = 2.0) ≈
                   2 * MA.sb3_avent(1, p[s].μ, p[s].ν, p[s].b; a_v = 1.0)
        Test.@test MA.sb3_bvent(1, p[s].μ, p[s].ν, p[s].b, p[s].β, 2.0) ≈
                   2 * MA.sb3_bvent(1, p[s].μ, p[s].ν, p[s].b, p[s].β, 1.0)
    end

    # at k = 0 the pair integrals are symmetric under swapping the two species; the k index
    # attaches to the first, so this fails on a transposed argument
    for a in (:cloud_ice, :snow, :graupel), b in (:cloud_liquid, :rain, :cloud_ice)
        pa, pb = p[a], p[b]
        Test.@test MA.sb3_delta(0, pa.μ, pa.ν, pa.b, pb.μ, pb.ν, pb.b) ≈
                   MA.sb3_delta(0, pb.μ, pb.ν, pb.b, pa.μ, pa.ν, pa.b)
        Test.@test MA.sb3_theta(0, pa.μ, pa.ν, pa.b, pa.β, pb.μ, pb.ν, pb.b, pb.β) ≈
                   MA.sb3_theta(0, pb.μ, pb.ν, pb.b, pb.β, pa.μ, pa.ν, pa.b, pa.β)
    end
    # and at k = 1 they are not, which is what makes the k = 0 symmetry a real check
    ci, cl = p.cloud_ice, p.cloud_liquid
    Test.@test !isapprox(
        MA.sb3_delta(1, ci.μ, ci.ν, ci.b, cl.μ, cl.ν, cl.b),
        MA.sb3_delta(1, cl.μ, cl.ν, cl.b, ci.μ, ci.ν, ci.b),
    )
end

Test.@testset "SB3_DERIVED holds the 108 constants DALES computes" begin
    d = MA.SB3_DERIVED
    leaves(x) = x isa NamedTuple ? sum(leaves, values(x); init = 0) : 1

    Test.@test leaves(d) == 108
    Test.@test leaves(d.moment) == 4
    Test.@test leaves(d.fall_speed) == 8
    Test.@test leaves(d.ventilation) == 16
    Test.@test leaves(d.δ_self) == 10
    Test.@test leaves(d.θ_self) == 10
    Test.@test leaves(d.δ_pair) == 30
    Test.@test leaves(d.θ_pair) == 30

    # every one is a usable number
    values_of(x) =
        x isa NamedTuple ? reduce(vcat, values_of.(collect(values(x))); init = Float64[]) :
        [Float64(x)]
    all_values = values_of(d)
    Test.@test length(all_values) == 108
    Test.@test all(isfinite, all_values)

    # exactly one is negative: rain's zeroth ventilation coefficient, because its gamma
    # argument falls in (-1, 0) where the gamma function itself is negative
    Test.@test count(<(0), all_values) == 1
    Test.@test d.ventilation.rain.b0 < 0
    rain = MA.SB3_PARTICLES.rain
    argument = (rain.ν + 3 * rain.b / 2 + rain.β / 2) / rain.μ
    Test.@test -1 < argument < 0
    Test.@test MA.lacz_gamma(argument) < 0

    # rain sediments through the a_tvsbc form, so it has no fall-speed moment
    Test.@test !haskey(d.fall_speed, :rain)
    Test.@test keys(d.fall_speed) == (:cloud_liquid, :cloud_ice, :snow, :graupel)
    # and cloud liquid does not ventilate
    Test.@test !haskey(d.ventilation, :cloud_liquid)

    # snow has no graupel collision partner, which is why dlt_s0g is never assigned
    Test.@test !haskey(d.δ_pair.snow, :graupel)
    Test.@test haskey(d.δ_pair.graupel, :snow)
end

Test.@testset "the rain ventilation sits just off a pole" begin
    rain = MA.SB3_PARTICLES.rain
    argument = (rain.ν + rain.b) / rain.μ

    Test.@test argument ≈ -1.0000300003000029
    Test.@test isfinite(MA.SB3_DERIVED.ventilation.rain.a0)
    # it is large precisely because it is near the pole
    Test.@test MA.SB3_DERIVED.ventilation.rain.a0 > 1.0e4
    # the exact fractions land on the pole, where the gamma routine returns its error value
    Test.@test MA.lacz_gamma((-2 / 3 + 1 / 3) / (1 / 3)) == 1.79e308
    # so tidying the literals would destroy rain evaporation rather than perturb it
    tidy = MA.sb3_avent(0, 1 / 3, -2 / 3, 1 / 3)
    Test.@test tidy > 1.0e300
end

Test.@testset "the fall-speed moments are the sedimentation velocities" begin
    d = MA.SB3_DERIVED
    p = MA.SB3_PARTICLES

    # graupel's cap is the larger of its two moments, not the bypassed 11.9
    Test.@test MA.sb3_max_fall_speed(:graupel) ==
               max(d.fall_speed.graupel.k0, d.fall_speed.graupel.k1)
    Test.@test MA.sb3_max_fall_speed(:graupel) != MA.SB3_UNUSED.d_wfallmax_hg.value
    for s in (:rain, :cloud_liquid, :cloud_ice, :snow)
        Test.@test MA.sb3_max_fall_speed(s) == MA.SB3_SEDIMENTATION.w_fall_max
    end
    Test.@test_throws ErrorException MA.sb3_max_fall_speed(:not_a_species)

    # the sedimentation speed carries no density correction, unlike the diagnostic one
    x = 1.0e-9
    ice = p.cloud_ice
    Test.@test MA.sb3_sedimentation_speed(x, d.fall_speed.cloud_ice.k1, ice) ≈
               d.fall_speed.cloud_ice.k1 * x^ice.β
    Test.@test MA.sb3_sedimentation_speed(x, d.fall_speed.cloud_ice.k1, ice) !=
               MA.sb3_fall_speed(x, 1.0, ice)
    # the max(0, ·) guards a negative coefficient, which this scheme does produce
    Test.@test MA.sb3_sedimentation_speed(x, -5.0, ice) == 0
    Test.@test MA.sb3_sedimentation_speed(x, 0.0, ice) == 0
end

Test.@testset "c_lbdr is computed with the wrong species' shape" begin
    p = MA.SB3_PARTICLES
    as_dales = MA.sb3_cons_lbd(p.rain.μ, p.snow.ν)
    as_rain = MA.sb3_cons_lbd(p.rain.μ, p.rain.ν)
    Test.@test as_dales ≈ 6.952127722818531
    # rain's own shape gives a different number, so the mix-up is not harmless in principle
    Test.@test !isapprox(as_dales, as_rain)
    Test.@test MA.SB3_UNUSED.c_lbdr.value ≈ as_dales
end

Test.@testset "the per-species diagnostics" begin
    p = MA.SB3_PARTICLES

    # the presence mask is inclusive for the two cloud species and strict for the rest,
    # which only shows at a mixing ratio exactly on the threshold
    for s in keys(p)
        q_min = p[s].q_min
        inclusive = s in MA.SB3_INCLUSIVE_PRESENCE
        Test.@test MA.sb3_present(q_min, 1.0, s) == inclusive
        Test.@test MA.sb3_present(2 * q_min, 1.0, s)
        Test.@test !MA.sb3_present(q_min / 2, 1.0, s)
        # a species with no number is absent however much mass it has
        Test.@test !MA.sb3_present(1.0, 0.0, s)
    end
    Test.@test MA.SB3_INCLUSIVE_PRESENCE == (:cloud_liquid, :cloud_ice)
    Test.@test_throws ErrorException MA.sb3_present(1.0, 1.0, :not_a_species)

    # Reynolds and the ventilation factor
    Test.@test MA.sb3_reynolds(1.0e-4, 1.0) ≈ 1.0e-4 / MA.SB3_PHYSICS.ν_air
    Test.@test MA.sb3_ventilation(0.0, 0.6, 0.2) == 0.6      # no flow, no enhancement
    Test.@test MA.sb3_ventilation(4.0, 0.6, 0.2) ≈
               0.6 + 0.2 * MA.SB3_PHYSICS.Sc^(1 / 3) * 2.0
    Test.@test MA.sb3_ventilation(100.0, 0.6, 0.2) > MA.sb3_ventilation(1.0, 0.6, 0.2)

    # the rain size distribution
    dsd = MA.sb3_rain_dsd(1.0e-4, 1.0e3, 1.2)
    Test.@test p.rain.x_min <= dsd.x <= p.rain.x_max
    Test.@test MA.SB3_WARM_RAIN.N_0min <= dsd.N_0 <= MA.SB3_WARM_RAIN.N_0max
    Test.@test MA.SB3_WARM_RAIN.lbdr_min <= dsd.λ <= MA.SB3_WARM_RAIN.lbdr_max
    Test.@test p.rain.x_min <= dsd.x_dsd <= p.rain.x_max
    # D_v is the volume-mean diameter of the clamped mean mass, on DALES's 3.14159
    Test.@test dsd.D_v ≈ (dsd.x / (3.14159 * MA.SB3_PHYSICS.ρ_water / 6))^(1 / 3)
    # more mass at fixed number means bigger drops
    Test.@test MA.sb3_rain_dsd(2.0e-4, 1.0e3, 1.2).x > dsd.x
end

Test.@testset "sb3_collision_pair assembles the twelve terms" begin
    pair = MA.sb3_collision_pair(:cloud_ice, :cloud_liquid)
    Test.@test length(pair) == 12
    Test.@test pair.σ_a == MA.SB3_PARTICLES.cloud_ice.σ_v
    Test.@test pair.σ_b == MA.SB3_PARTICLES.cloud_liquid.σ_v
    Test.@test pair.δ_0a == MA.SB3_DERIVED.δ_self.cloud_ice.k0
    Test.@test pair.δ_0b == MA.SB3_DERIVED.δ_self.cloud_liquid.k0
    Test.@test pair.δ_0ab == MA.SB3_DERIVED.δ_pair.cloud_ice.cloud_liquid.k0
    Test.@test pair.θ_1ab == MA.SB3_DERIVED.θ_pair.cloud_ice.cloud_liquid.k1

    # the pair is ordered: collector then collected
    Test.@test_throws ErrorException MA.sb3_collision_pair(:cloud_liquid, :cloud_ice)
    # snow collects no graupel, which is the gap dlt_s0g leaves
    Test.@test_throws ErrorException MA.sb3_collision_pair(:snow, :graupel)
    Test.@test MA.sb3_collision_pair(:graupel, :snow) isa NamedTuple

    # every pair DALES forms is assembled without error
    for a in keys(MA.SB3_COLLISION_PAIRS), b in MA.SB3_COLLISION_PAIRS[a]
        Test.@test MA.sb3_collision_pair(a, b) isa NamedTuple
    end
end
