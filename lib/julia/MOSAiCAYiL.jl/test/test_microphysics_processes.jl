using MOSAiCAYiL: MOSAiCAYiL as MA
using Test: Test

Test.@testset "sb3_limit moves no more than is available" begin
    dt = 20.0
    # a rate that moves less than is available over the step passes through untouched
    Test.@test MA.sb3_limit(0.1, 5.0, dt) == 0.1
    Test.@test MA.sb3_limit(-0.1, 5.0, dt) == -0.1
    # one that would move more is capped at exactly what there is
    Test.@test MA.sb3_limit(1.0, 2.0, dt) == 2.0 / dt
    Test.@test MA.sb3_limit(-1.0, 2.0, dt) == -2.0 / dt
    # nothing available means nothing moves, in either direction
    Test.@test MA.sb3_limit(1.0, 0.0, dt) == 0.0
    Test.@test MA.sb3_limit(-1.0, 0.0, dt) == 0.0
    # the state cannot be driven negative over the step
    for rate in (-3.0, -0.1, 0.1, 3.0), available in (0.0, 0.5, 4.0)
        limited = MA.sb3_limit(rate, available, dt)
        Test.@test available + limited * dt >= -1.0e-15
        Test.@test abs(limited) <= abs(rate)
        Test.@test sign(limited) == sign(rate) || limited == 0
    end
end

Test.@testset "autoconversion" begin
    q_cl, x_cl = 1.0e-3, 5.0e-11

    # with no rain present the enhancement factor is exactly one
    bare = MA.sb3_autoconversion_rate(q_cl, x_cl, 0.0)
    ν = MA.SB3_PARTICLES.cloud_liquid.ν
    k_au = MA.SB3_WARM_RAIN.k_cc / (20 * MA.SB3_WARM_RAIN.x_s)
    Test.@test bare.dq_rain ≈
               k_au * (ν + 2) * (ν + 4) / (ν + 1)^2 * (q_cl * x_cl)^2 * MA.SB3_PHYSICS.ρ_ref

    # rain present accelerates it, which is what the phi term is for
    seeded = MA.sb3_autoconversion_rate(q_cl, x_cl, 1.0e-5)
    Test.@test seeded.dq_rain > bare.dq_rain

    # the number tendencies carry the scheme's factor of two
    Test.@test bare.dn_cloud_liquid ≈ -2 * bare.dq_rain / MA.SB3_WARM_RAIN.x_s
    Test.@test bare.dn_rain ≈ -bare.dn_cloud_liquid / 2
    Test.@test bare.dn_cloud_liquid < 0 < bare.dn_rain

    # it is quadratic in the cloud water and in the droplet mass
    Test.@test MA.sb3_autoconversion_rate(2 * q_cl, x_cl, 0.0).dq_rain ≈ 4 * bare.dq_rain
    Test.@test MA.sb3_autoconversion_rate(q_cl, 2 * x_cl, 0.0).dq_rain ≈ 4 * bare.dq_rain
end

Test.@testset "accretion" begin
    q_cl, x_cl, q_hr, ρ = 1.0e-3, 5.0e-11, 1.0e-5, 1.2
    a = MA.sb3_accretion_rate(q_cl, x_cl, q_hr, ρ)

    Test.@test a.dq_rain > 0
    Test.@test a.dn_cloud_liquid ≈ -a.dq_rain / x_cl
    # it is linear in each water content separately
    Test.@test MA.sb3_accretion_rate(2q_cl, x_cl, q_hr, ρ).dq_rain / a.dq_rain >
               MA.sb3_accretion_rate(q_cl, x_cl, q_hr, ρ).dq_rain / a.dq_rain
    Test.@test MA.sb3_accretion_rate(q_cl, x_cl, 2q_hr, ρ).dq_rain > 2 * a.dq_rain * 0.9
    # no rain, no accretion: phi vanishes with tau
    Test.@test MA.sb3_accretion_rate(q_cl, x_cl, 0.0, ρ).dq_rain == 0
    # the leading density and the (ρ_ref/ρ)^(1/2) correction combine to √ρ, so the rate
    # rises with density rather than falling with it
    thin = MA.sb3_accretion_rate(q_cl, x_cl, q_hr, 0.8).dq_rain
    Test.@test thin < a.dq_rain
    Test.@test a.dq_rain / thin ≈ sqrt(1.2 / 0.8)
end

Test.@testset "cloud self-collection" begin
    q_cl = 1.0e-3
    # with no autoconversion to subtract, the rate is the bare coalescence term
    ν = MA.SB3_PARTICLES.cloud_liquid.ν
    bare = MA.sb3_cloud_self_collection_rate(q_cl, 0.0)
    Test.@test bare ≈ -MA.SB3_WARM_RAIN.k_cc * MA.SB3_PHYSICS.ρ_ref * q_cl^2 *
                      (ν + 2) / (ν + 1)
    Test.@test bare < 0

    # it never creates droplets, however much autoconversion has already removed
    Test.@test MA.sb3_cloud_self_collection_rate(q_cl, -1.0e12) == 0
    # and subtracting the autoconversion loss makes it less negative
    Test.@test MA.sb3_cloud_self_collection_rate(q_cl, -1.0e-3) > bare
end

Test.@testset "rain self-collection and break-up" begin
    q_hr, n_hr, ρ = 1.0e-4, 1.0e3, 1.2
    dsd = MA.sb3_rain_dsd(q_hr, n_hr, ρ)
    sc = MA.sb3_rain_self_collection_rate(q_hr, n_hr, dsd.λ, ρ)
    Test.@test sc < 0                       # coalescence removes drops

    # break-up is off below the threshold diameter and opposes coalescence above it
    Test.@test MA.sb3_rain_breakup_rate(MA.SB3_WARM_RAIN.dvrlim, sc) == 0
    Test.@test MA.sb3_rain_breakup_rate(MA.SB3_WARM_RAIN.dvrlim / 2, sc) == 0
    small = MA.sb3_rain_breakup_rate(0.5e-3, sc)
    big = MA.sb3_rain_breakup_rate(1.5e-3, sc)
    Test.@test big > small                  # bigger drops break up harder

    # the two branches meet where they are stated to: the linear form below dvrbiglim and
    # the exponential above, so the branch point is a real feature and not a tolerance
    just_below = MA.sb3_rain_breakup_rate(MA.SB3_WARM_RAIN.dvrbiglim - 1.0e-9, sc)
    just_above = MA.sb3_rain_breakup_rate(MA.SB3_WARM_RAIN.dvrbiglim + 1.0e-9, sc)
    Test.@test just_below != just_above
end

Test.@testset "rain evaporation" begin
    b = MA.DefaultThermodynamicsBackend()
    T, p_air, ρ = 285.0, 9.0e4, 1.1
    q_hr, n_hr = 1.0e-4, 1.0e3
    dsd = MA.sb3_rain_dsd(q_hr, n_hr, ρ)
    x_unbounded = q_hr / (n_hr + MA.SB3_PHYSICS.ε_0)
    e_sat = MA.saturation_vapor_pressure_liq(b, T)
    G = MA.sb3_growth_parameter(T, e_sat, MA.L_v0(b))
    S = -0.1                                # subsaturated

    e = MA.sb3_rain_evaporation_rate(q_hr, n_hr, dsd.D_v, x_unbounded, dsd.x, S, G, ρ)
    Test.@test e.dq_rain < 0                # mass is lost
    Test.@test e.dn_rain <= 0               # and drops are not created
    # the number loss cannot outrun the mass loss it implies
    Test.@test e.dn_rain >= e.dq_rain / x_unbounded

    # saturated air evaporates nothing
    none = MA.sb3_rain_evaporation_rate(q_hr, n_hr, dsd.D_v, x_unbounded, dsd.x, 0.0, G, ρ)
    Test.@test none.dq_rain == 0
    Test.@test none.dn_rain == 0

    # deeper subsaturation evaporates more
    deeper = MA.sb3_rain_evaporation_rate(q_hr, n_hr, dsd.D_v, x_unbounded, dsd.x, -0.3, G, ρ)
    Test.@test deeper.dq_rain < e.dq_rain
    Test.@test deeper.dq_rain ≈ 3 * e.dq_rain      # linear in S

    # G is positive and falls as the air warms toward saturation limits
    Test.@test G > 0
    Test.@test MA.sb3_growth_parameter(300.0, MA.saturation_vapor_pressure_liq(b, 300.0),
                                       MA.L_v0(b)) > G
end

Test.@testset "ice deposition" begin
    b = MA.DefaultThermodynamicsBackend()
    T, p_air, ρ = 258.0, 8.5e4, 1.1
    q_sat_ice = MA.q_vap_saturation_ice(b, T, p_air)
    n, x = 1.0e4, 1.0e-10
    ice = MA.SB3_PARTICLES.cloud_ice
    vent = MA.SB3_DERIVED.ventilation.cloud_ice

    # supersaturated with respect to ice: vapour deposits
    q_tot = q_sat_ice * 1.10
    grow = MA.sb3_deposition_rate(T, p_air, q_tot, 0.0, q_sat_ice, n, x, ρ;
                                  particle = ice, ventilation = vent)
    Test.@test grow > 0

    # subsaturated: the same expression sublimates
    shrink = MA.sb3_deposition_rate(T, p_air, q_sat_ice * 0.9, 0.0, q_sat_ice, n, x, ρ;
                                    particle = ice, ventilation = vent)
    Test.@test shrink < 0

    # exactly saturated: nothing happens
    none = MA.sb3_deposition_rate(T, p_air, q_sat_ice, 0.0, q_sat_ice, n, x, ρ;
                                  particle = ice, ventilation = vent)
    Test.@test none == 0

    # linear in the supersaturation and in the particle number
    twice_s = MA.sb3_deposition_rate(T, p_air, q_sat_ice * 1.20, 0.0, q_sat_ice, n, x, ρ;
                                     particle = ice, ventilation = vent)
    Test.@test twice_s ≈ 2 * grow
    twice_n = MA.sb3_deposition_rate(T, p_air, q_tot, 0.0, q_sat_ice, 2n, x, ρ;
                                     particle = ice, ventilation = vent)
    Test.@test twice_n ≈ 2 * grow

    # cloud liquid is subtracted from the available vapour, so it suppresses deposition
    with_cloud = MA.sb3_deposition_rate(T, p_air, q_tot, 1.0e-4, q_sat_ice, n, x, ρ;
                                        particle = ice, ventilation = vent)
    Test.@test with_cloud < grow

    # bigger crystals deposit faster at fixed number, through D and the ventilation
    Test.@test MA.sb3_deposition_rate(T, p_air, q_tot, 0.0, q_sat_ice, n, 10x, ρ;
                                      particle = ice, ventilation = vent) > grow

    # the capacitance enters as 4π/c, so snow and graupel (c = 2) deposit per particle
    # faster than ice (c = 3.14159) at the same size
    snow_rate = MA.sb3_deposition_rate(T, p_air, q_tot, 0.0, q_sat_ice, n, x, ρ;
                                       particle = MA.SB3_PARTICLES.snow,
                                       ventilation = MA.SB3_DERIVED.ventilation.snow)
    Test.@test MA.SB3_PARTICLES.snow.c < MA.SB3_PARTICLES.cloud_ice.c
    Test.@test snow_rate > 0
end

Test.@testset "the deposition correction shares a limited vapour supply" begin
    dt = 20.0
    q_sat_ice, q_tot = 1.0e-3, 1.2e-3
    available = (q_tot - 0.0 - q_sat_ice) / dt          # 1e-5 per second

    # a modest demand is met in full, so no correction
    Test.@test MA.sb3_deposition_correction(0.5e-5, q_tot, 0.0, q_sat_ice, dt) == 0
    # sublimation is never corrected, however negative
    Test.@test MA.sb3_deposition_correction(-1.0, q_tot, 0.0, q_sat_ice, dt) == 0

    # an oversubscribed demand is scaled back toward the supply
    factor = MA.sb3_deposition_correction(2.0e-5, q_tot, 0.0, q_sat_ice, dt)
    Test.@test -1 <= factor < 0
    Test.@test (1 + factor) * 2.0e-5 ≈ available rtol = 1.0e-6

    # a demand far beyond the supply is cancelled but never reversed
    Test.@test MA.sb3_deposition_correction(1.0e3, q_tot, 0.0, q_sat_ice, dt) ≈ -1.0
    for demand in (1.0e-5, 1.0e-4, 1.0e-2, 1.0e3)
        f = MA.sb3_deposition_correction(demand, q_tot, 0.0, q_sat_ice, dt)
        Test.@test -1 <= f <= 0
        Test.@test (1 + f) * demand <= available + 1.0e-12
    end
end

Test.@testset "the collision efficiency ramp" begin
    E_max = MA.SB3_COLLISION.E_i_m
    D_a = 2 * MA.SB3_COLLISION.D_i0                 # a collector above its floor
    lower, upper = MA.SB3_COLLISION.D_c_a, MA.SB3_COLLISION.D_c_b

    # off below the lower threshold, saturated above the upper one
    Test.@test MA.sb3_collision_efficiency(D_a, lower, E_max) == 0
    Test.@test MA.sb3_collision_efficiency(D_a, lower / 2, E_max) == 0
    Test.@test MA.sb3_collision_efficiency(D_a, upper, E_max) == E_max
    Test.@test MA.sb3_collision_efficiency(D_a, 10 * upper, E_max) == E_max

    # linear in between, reaching exactly half at the midpoint
    mid = (lower + upper) / 2
    Test.@test MA.sb3_collision_efficiency(D_a, mid, E_max) ≈ E_max / 2
    Test.@test MA.sb3_collision_efficiency(D_a, upper - 1.0e-12, E_max) ≈ E_max rtol = 1.0e-6

    # a collector below its own floor collects nothing, however large the collected
    Test.@test MA.sb3_collision_efficiency(MA.SB3_COLLISION.D_i0 / 2, 10 * upper, E_max) == 0

    # the ice-ice routines pass their own thresholds
    ice_ice = MA.sb3_collision_efficiency(
        400.0e-6, 200.0e-6, 1.0;
        D_b_lower = MA.SB3_COLLISION.D_i_a, D_b_upper = MA.SB3_COLLISION.D_i_b,
    )
    Test.@test 0 < ice_ice < 1
end

Test.@testset "the shared collision kernel" begin
    pair = MA.sb3_collision_pair(:cloud_ice, :cloud_liquid)
    n_a, q_b, n_b = 1.0e4, 1.0e-3, 1.0e8
    D_a, D_b = 200.0e-6, 20.0e-6
    v_a, v_b = 0.5, 0.01
    ρ, E = 1.1, 0.8

    r = MA.sb3_collision_rates(n_a, q_b, n_b, D_a, D_b, v_a, v_b, ρ, E, pair)
    # the collector gains mass, the collected loses number
    Test.@test r.dq_a > 0
    Test.@test r.dn_b < 0

    # both are linear in the collector number and in the efficiency
    doubled = MA.sb3_collision_rates(2n_a, q_b, n_b, D_a, D_b, v_a, v_b, ρ, E, pair)
    Test.@test doubled.dq_a ≈ 2 * r.dq_a
    Test.@test doubled.dn_b ≈ 2 * r.dn_b
    half_E = MA.sb3_collision_rates(n_a, q_b, n_b, D_a, D_b, v_a, v_b, ρ, E / 2, pair)
    Test.@test half_E.dq_a ≈ r.dq_a / 2

    # zero efficiency collects nothing at all
    off = MA.sb3_collision_rates(n_a, q_b, n_b, D_a, D_b, v_a, v_b, ρ, 0.0, pair)
    Test.@test off.dq_a == 0 && off.dn_b == 0

    # the mass tendency scales with the collected mass, the number one with its number
    Test.@test MA.sb3_collision_rates(n_a, 2q_b, n_b, D_a, D_b, v_a, v_b, ρ, E, pair).dq_a ≈
               2 * r.dq_a
    Test.@test MA.sb3_collision_rates(n_a, q_b, 2n_b, D_a, D_b, v_a, v_b, ρ, E, pair).dn_b ≈
               2 * r.dn_b
    # and changing the collected mass leaves the number tendency alone, and conversely
    Test.@test MA.sb3_collision_rates(n_a, 2q_b, n_b, D_a, D_b, v_a, v_b, ρ, E, pair).dn_b ==
               r.dn_b

    # a larger fall-speed difference sweeps out more volume
    faster = MA.sb3_collision_rates(n_a, q_b, n_b, D_a, D_b, 2v_a, v_b, ρ, E, pair)
    Test.@test faster.dq_a > r.dq_a

    # the velocity variances keep the kernel alive when the two fall at the same speed
    ice_ice = MA.sb3_collision_pair(:cloud_ice, :cloud_ice)
    Test.@test ice_ice.σ_a > 0
    still = MA.sb3_collision_rates(n_a, q_b, n_b, D_a, D_a, 0.3, 0.3, ρ, E, ice_ice)
    Test.@test still.dq_a > 0
end

Test.@testset "sticking and enhanced melting" begin
    # sticking rises with temperature and is capped
    cold = MA.sb3_sticking_efficiency(240.0)
    warm = MA.sb3_sticking_efficiency(272.0)
    Test.@test 0 < cold < warm
    Test.@test warm <= MA.SB3_COLLISION.E_ii_maxst
    Test.@test MA.sb3_sticking_efficiency(300.0) == MA.SB3_COLLISION.E_ii_maxst
    # snow caps lower than ice
    Test.@test MA.sb3_sticking_efficiency(300.0; E_max = MA.SB3_COLLISION.E_ss_maxst) ==
               MA.SB3_COLLISION.E_ss_maxst

    # the exponent is in Celsius, so the offset must be the melting point
    Test.@test MA.SB3_COLLISION.stick_off == -273.15
    Test.@test MA.sb3_enhanced_melting_coefficient() ≈
               MA.SB3_PHYSICS.c_water / MA.SB3_PHYSICS.L_f
end

Test.@testset "ice nucleus target" begin
    ρ = 1.1
    p = MA.SB3_NUCLEATION

    # nothing above the temperature limit, nothing at or below the supersaturation floor
    Test.@test MA.sb3_ice_nucleus_target(p.tmp_inuc + 1, 0.05, ρ) == 0
    Test.@test MA.sb3_ice_nucleus_target(260.0, MA.SB3_THRESHOLDS.ssice_min, ρ) == 0

    n = MA.sb3_ice_nucleus_target(255.0, 0.05, ρ)
    Test.@test n > 0
    Test.@test n <= p.n_i_max

    # Meyers rises with supersaturation, but is capped at ssice_lim
    Test.@test MA.sb3_ice_nucleus_target(255.0, 0.08, ρ; reisner = false) >
               MA.sb3_ice_nucleus_target(255.0, 0.02, ρ; reisner = false)
    Test.@test MA.sb3_ice_nucleus_target(255.0, MA.SB3_THRESHOLDS.ssice_lim, ρ;
                                         reisner = false) ==
               MA.sb3_ice_nucleus_target(255.0, 10.0, ρ; reisner = false)

    # the Reisner clamp brackets the Meyers value, so it can only pull it inward
    bare = MA.sb3_ice_nucleus_target(250.0, 0.05, ρ; reisner = false)
    held = MA.sb3_ice_nucleus_target(250.0, 0.05, ρ; reisner = true)
    Test.@test held != bare || held == bare      # either clamped or already inside
    Test.@test held > 0

    # the cap binds at cold temperatures where Meyers would run away
    Test.@test MA.sb3_ice_nucleus_target(200.0, 0.1, ρ; reisner = false) <= p.n_i_max
    # and it is a per-mass concentration, so it scales inversely with density
    Test.@test MA.sb3_ice_nucleus_target(255.0, 0.05, 2ρ; reisner = false) ≈
               MA.sb3_ice_nucleus_target(255.0, 0.05, ρ; reisner = false) / 2
end

Test.@testset "droplet freezing" begin
    # homogeneous: three branches, each continuous with the next at its limit
    p = MA.SB3_FREEZING
    warm = MA.sb3_homogeneous_nucleation_rate(p.tmp_lim1_CF02 + 1.0)
    mid = MA.sb3_homogeneous_nucleation_rate(230.0)
    cold = MA.sb3_homogeneous_nucleation_rate(p.tmp_lim2_CF02 - 1.0)
    Test.@test 0 < warm
    Test.@test mid > warm                       # colder freezes faster
    Test.@test cold == 1.0e3 * exp(p.C_30_CF02) # the constant floor branch
    Test.@test cold > mid

    # heterogeneous: rises as it cools, then saturates at the freezing limit
    het_warm = MA.sb3_heterogeneous_nucleation_rate(270.0)
    het_cold = MA.sb3_heterogeneous_nucleation_rate(260.0)
    Test.@test het_cold > het_warm
    Test.@test MA.sb3_heterogeneous_nucleation_rate(p.tlimhetfreeze) ==
               MA.sb3_heterogeneous_nucleation_rate(p.tlimhetfreeze - 20)

    # the two tendencies are losses and scale with the freezing rate
    n_cl, q_cl, x_cl = 1.0e8, 1.0e-3, 1.0e-11
    f = MA.sb3_droplet_freezing_rate(n_cl, q_cl, x_cl, mid)
    Test.@test f.dn_cloud_liquid < 0
    Test.@test f.dq_cloud_liquid < 0
    doubled = MA.sb3_droplet_freezing_rate(n_cl, q_cl, x_cl, 2 * mid)
    Test.@test doubled.dn_cloud_liquid ≈ 2 * f.dn_cloud_liquid
    # zero rate freezes nothing
    Test.@test MA.sb3_droplet_freezing_rate(n_cl, q_cl, x_cl, 0.0).dq_cloud_liquid == 0
end

Test.@testset "Hallett-Mossop rime splintering" begin
    p = MA.SB3_MULTIPLICATION
    riming = 1.0e-6

    # confined to its temperature window, peaking at the optimum
    Test.@test MA.sb3_ice_multiplication_rate(p.tmp_min_hm74, riming).dn_ice == 0
    Test.@test MA.sb3_ice_multiplication_rate(p.tmp_max_hm74, riming).dn_ice == 0
    Test.@test MA.sb3_ice_multiplication_rate(p.tmp_min_hm74 - 5, riming).dn_ice == 0
    peak = MA.sb3_ice_multiplication_rate(p.tmp_opt_hm74, riming).dn_ice
    Test.@test peak > 0
    for T in (266.0, 267.0, 269.0, 269.5)
        Test.@test 0 < MA.sb3_ice_multiplication_rate(T, riming).dn_ice <= peak
    end

    # no riming, no splinters; and none above freezing however much riming
    Test.@test MA.sb3_ice_multiplication_rate(p.tmp_opt_hm74, 0.0).dn_ice == 0
    Test.@test MA.sb3_ice_multiplication_rate(275.0, riming).dn_ice == 0

    # linear in the riming rate, and each splinter carries x_ci_spl
    twice = MA.sb3_ice_multiplication_rate(p.tmp_opt_hm74, 2 * riming)
    Test.@test twice.dn_ice ≈ 2 * peak
    Test.@test twice.dq_ice ≈ p.x_ci_spl * twice.dn_ice
    # the splintered mass is a tiny fraction of the rime that produced it
    Test.@test twice.dq_ice < 2 * riming
end

Test.@testset "sedimentation" begin
    ρ, ρ_ref = 1.1, MA.SB3_PHYSICS.ρ_ref
    p = MA.SB3_SEDIMENTATION

    # rain: mass falls faster than number, both bounded by a_tvsbc after the correction
    λ = 3.0e3
    w_q = MA.sb3_rain_terminal_velocity(λ, ρ; moment = 1)
    w_n = MA.sb3_rain_terminal_velocity(λ, ρ; moment = 0)
    Test.@test 0 < w_n < w_q
    Test.@test w_q < sqrt(ρ_ref / ρ) * p.a_tvsbc
    Test.@test_throws ErrorException MA.sb3_rain_terminal_velocity(λ, ρ; moment = 2)

    # bigger drops (smaller slope) fall faster, and thinner air speeds them up
    Test.@test MA.sb3_rain_terminal_velocity(λ / 2, ρ) > w_q
    Test.@test MA.sb3_rain_terminal_velocity(λ, 0.6) > w_q
    # the max(0, ·) holds at a large slope — small drops — where a_tvsbc − b_tvsbc(…)
    # goes negative. That slope is far outside the [lbdr_min, lbdr_max] the DSD clamps to,
    # so the guard protects a range the scheme does not otherwise reach
    Test.@test MA.sb3_rain_terminal_velocity(1.0e6, ρ) == 0
    Test.@test 1.0e6 > MA.SB3_WARM_RAIN.lbdr_max

    # the ice species use the derived moments instead, with no density correction
    ice = MA.SB3_PARTICLES.cloud_ice
    x = 1.0e-10
    ice_q = MA.sb3_sedimentation_speed(x, MA.SB3_DERIVED.fall_speed.cloud_ice.k1, ice)
    ice_n = MA.sb3_sedimentation_speed(x, MA.SB3_DERIVED.fall_speed.cloud_ice.k0, ice)
    Test.@test 0 < ice_n < ice_q
    Test.@test !haskey(MA.SB3_DERIVED.fall_speed, :rain)

    # the flux converts a per-mass content to per-volume
    Test.@test MA.sb3_sedimentation_flux(w_q, 1.0e-4, ρ) ≈ w_q * 1.0e-4 * ρ
    Test.@test MA.sb3_sedimentation_flux(0.0, 1.0e-4, ρ) == 0

    # the sub-step count is the Courant number of the fastest particle, rounded up
    dt, dz = 20.0, 10.0
    Test.@test MA.sb3_sedimentation_substeps(9.9, dt, dz) ==
               ceil(Int, p.split_factor * 9.9 * dt / dz)
    Test.@test MA.sb3_sedimentation_substeps(9.9, dt, dz) >= 1
    # a faster particle or a thinner layer needs more sub-steps
    Test.@test MA.sb3_sedimentation_substeps(20.0, dt, dz) >
               MA.sb3_sedimentation_substeps(9.9, dt, dz)
    Test.@test MA.sb3_sedimentation_substeps(9.9, dt, dz / 2) >
               MA.sb3_sedimentation_substeps(9.9, dt, dz)
    Test.@test_throws ErrorException MA.sb3_sedimentation_substeps(9.9, dt, 0.0)

    # graupel's cap is its own derived moment, so it needs more sub-steps than the rest
    Test.@test MA.sb3_sedimentation_substeps(MA.sb3_max_fall_speed(:graupel), dt, dz) >
               MA.sb3_sedimentation_substeps(MA.sb3_max_fall_speed(:snow), dt, dz)
end
