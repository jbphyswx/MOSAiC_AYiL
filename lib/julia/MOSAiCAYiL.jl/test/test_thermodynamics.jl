using MOSAiCAYiL: MOSAiCAYiL as MA
using Test: Test

const B = MA.DefaultThermodynamicsBackend()

Test.@testset "DALES_CONSTANTS is transcribed from the Fortran" begin
    # a typo here is silent and corrupts every derived quantity, so the whole table is
    # pinned to `modglobal.f90:73-101` and `modmicrodata3.f90:163-164`
    Test.@test MA.DALES_CONSTANTS == (;
        grav = 9.81,                    # modglobal:73
        R_d = 287.04,                   # :74  rd
        R_v = 461.5,                    # :75  rv
        cp_d = 1004.0,                  # :76  cp
        L_v = 2.53e6,                   # :77  rlv
        L_s = 2.834e6,                  # modmicrodata3:163  rlvi
        L_f = 3.337e5,                  # modmicrodata3:164  rlme
        p_ref = 1.0e5,                  # :89  pref0
        T_melt = 273.16,                # :90  tmelt
        ρ_water = 998.0,                # :88  rhow
        von_karman = 0.4,               # :98  fkar
        stefan_boltzmann = 5.67e-8,     # :101 boltz
        e_s0 = 610.78,                  # :91  es0
        a_liquid = 17.27,               # :92  at
        b_liquid = 35.86,               # :93  bt
        a_ice = 21.8745584,             # :94  at_i
        b_ice = 7.66,                   # :95  bt_i
        e12_min = 5.0e-5,               # :97  e12min
        T_mixed_high = 268.0,           # :79  tup
        T_mixed_low = 253.0,            # :80  tdn
    )
    # modglobal's own riv = 2.84e6 is declared and never referenced; the sublimation heat
    # the microphysics used is SB3's rlvi, which is what is stored
    Test.@test MA.DALES_CONSTANTS.L_s != 2.84e6
end

Test.@testset "every constant is DALES's own, not a restatement" begin
    for (f, name) in (
        (MA.R_d, :R_d), (MA.R_v, :R_v), (MA.cp_d, :cp_d), (MA.grav, :grav),
        (MA.p_ref, :p_ref), (MA.L_v0, :L_v), (MA.L_s0, :L_s), (MA.e_ref, :e_s0),
        (MA.T_freeze, :T_melt), (MA.T_mixed_high, :T_mixed_high),
        (MA.T_mixed_low, :T_mixed_low), (MA.a_liquid, :a_liquid),
        (MA.b_liquid, :b_liquid), (MA.a_ice, :a_ice), (MA.b_ice, :b_ice),
    )
        Test.@test f(B) === Float64(getfield(MA.DALES_CONSTANTS, name))
        Test.@test f(B, Float32) === Float32(getfield(MA.DALES_CONSTANTS, name))
    end
end

Test.@testset "molmass_ratio is Mv/Md, not its reciprocal" begin
    # DALES writes this as rd/rv everywhere; the reciprocal 1.608 is equally common and
    # would be silently wrong
    Test.@test MA.molmass_ratio(B) == MA.R_d(B) / MA.R_v(B)
    Test.@test 0.62 < MA.molmass_ratio(B) < 0.63
    Test.@test MA.molmass_ratio(B, Float32) isa Float32
end

Test.@testset "saturation vapour pressure" begin
    T_melt = MA.T_freeze(B)

    # Tetens is anchored at the melting point, where its exponent is exactly zero
    Test.@test MA.tetens_saturation_vapor_pressure(B, T_melt) == MA.e_ref(B)
    Test.@test MA.tetens_saturation_vapor_pressure(B, T_melt, MA.Ice()) == MA.e_ref(B)

    # liquid and ice agree at the melting point and separate below it
    Test.@test MA.saturation_vapor_pressure_liq(B, T_melt) ≈
               MA.saturation_vapor_pressure_ice(B, T_melt) rtol = 2.0e-3
    Test.@test MA.saturation_vapor_pressure_ice(B, 250.0) <
               MA.saturation_vapor_pressure_liq(B, 250.0)

    # both rise with temperature over the whole Arctic range
    Ts = 220.0:5.0:290.0
    Test.@test issorted(MA.saturation_vapor_pressure_liq.(B, Ts))
    Test.@test issorted(MA.saturation_vapor_pressure_ice.(B, Ts))

    Test.@test_throws ErrorException MA.saturation_vapor_pressure(B, 273.0, MA.Vapor())
    Test.@test MA.saturation_vapor_pressure_liq(B, 273.0f0) isa Float32
end

Test.@testset "the two saturation-humidity conventions differ as DALES has them" begin
    p, T = 1.0e5, 270.0
    e = MA.saturation_vapor_pressure_liq(B, T)
    interior = MA.q_vap_saturation_from_pressure(B, e, p)
    surface = MA.surface_q_vap_saturation(B, e, p)
    # the surface form drops the (1-eps)e the interior keeps, so it is the smaller
    Test.@test surface < interior
    Test.@test surface == MA.molmass_ratio(B) * e / p
    Test.@test interior == MA.molmass_ratio(B) * e / (p - (1 - MA.molmass_ratio(B)) * e)

    # air that cannot be saturated returns 1 rather than a negative humidity
    Test.@test MA.q_vap_saturation_from_pressure(B, 2.0e5, 1.0e3) == 1.0
end

Test.@testset "liquid fraction over the mixed-phase range" begin
    lo, hi = MA.T_mixed_low(B), MA.T_mixed_high(B)
    Test.@test MA.liquid_fraction(B, lo - 1.0) == 0.0
    Test.@test MA.liquid_fraction(B, lo) == 0.0
    Test.@test MA.liquid_fraction(B, hi) == 1.0
    Test.@test MA.liquid_fraction(B, hi + 1.0) == 1.0
    Test.@test MA.liquid_fraction(B, (lo + hi) / 2) ≈ 0.5
    Test.@test issorted(MA.liquid_fraction.(B, lo:1.0:hi))
end

Test.@testset "exner and the potential temperatures invert" begin
    Test.@test MA.exner(B, MA.p_ref(B)) == 1.0
    for p in (1.0e5, 9.0e4, 5.0e4), θ_l in (250.0, 270.0, 290.0), q_l in (0.0, 1.0e-4)
        T = MA.temperature_from_liquid_pottemp(B, θ_l, p, q_l)
        Test.@test MA.liquid_pottemp(B, T, p, q_l) ≈ θ_l
        # liquid warms the temperature relative to the dry relation
        q_l == 0 ? Test.@test(T == MA.exner(B, p) * θ_l) :
                   Test.@test(T > MA.exner(B, p) * θ_l)
    end
    Test.@test MA.dry_pottemp(B, 270.0, MA.p_ref(B)) == 270.0
end

Test.@testset "saturation adjustment closes the round trip" begin
    worst = 0.0
    for p in (1.0e5, 9.0e4, 7.0e4), θ_l in (245.0, 260.0, 275.0, 290.0),
        q_tot in (0.0, 1.0e-4, 2.0e-3, 1.0e-2)

        (; T, q_liq, q_ice) = MA.saturation_adjust_pθq(B, p, θ_l, q_tot)
        back = MA.liquid_pottemp(B, T, p, q_liq + q_ice)
        worst = max(worst, abs(back - θ_l))
        Test.@test q_liq >= 0
        Test.@test q_ice >= 0
        Test.@test q_liq + q_ice <= q_tot + 1.0e-12
    end
    Test.@test worst < 1.0e-6

    # dry air is untouched: no condensate, and T is exactly the dry relation
    (; T, q_liq, q_ice) = MA.saturation_adjust_pθq(B, 1.0e5, 270.0, 0.0)
    Test.@test q_liq == 0.0
    Test.@test q_ice == 0.0
    Test.@test T == MA.exner(B, 1.0e5) * 270.0

    # supersaturated air condenses and warms above the dry relation
    (; T, q_liq) = MA.saturation_adjust_pθq(B, 1.0e5, 275.0, 1.0e-2)
    Test.@test q_liq > 0
    Test.@test T > MA.exner(B, 1.0e5) * 275.0
end

Test.@testset "latent heats are the constants DALES holds them at" begin
    # DALES does not vary them with temperature, so the backend returns the reference
    # value at every T, and the temperature-dependent form is there for a caller with a Δcp
    for T in (240.0, 273.16, 300.0)
        Test.@test MA.latent_heat_vapor(B, T) == MA.L_v0(B)
        Test.@test MA.latent_heat_sublim(B, T) == MA.L_s0(B)
    end
    Test.@test MA.latent_heat_generic(B, MA.T_freeze(B), MA.L_v0(B), 100.0) == MA.L_v0(B)
    Test.@test MA.latent_heat_generic(B, MA.T_freeze(B) + 10.0, MA.L_v0(B), 100.0) ==
               MA.L_v0(B) + 1000.0
    Test.@test MA.latent_heat_vapor(B, 273.16f0) isa Float32
end

Test.@testset "saturation humidity at a temperature and pressure" begin
    p, T = 1.0e5, 270.0
    Test.@test MA.q_vap_saturation_liq(B, T, p) == MA.q_vap_saturation_from_pressure(
        B, MA.saturation_vapor_pressure_liq(B, T), p,
    )
    Test.@test MA.q_vap_saturation_ice(B, T, p) < MA.q_vap_saturation_liq(B, T, p)
    Test.@test MA.q_vap_saturation(B, T, p, MA.Liquid()) == MA.q_vap_saturation_liq(B, T, p)
    Test.@test MA.q_vap_saturation(B, T, p, MA.Ice()) == MA.q_vap_saturation_ice(B, T, p)

    # the blended form sits between the two, at the mixed-phase liquid fraction
    blended = MA.q_vap_saturation(B, T, p)
    Test.@test MA.q_vap_saturation_ice(B, T, p) <= blended <= MA.q_vap_saturation_liq(B, T, p)
    Test.@test MA.q_vap_saturation(B, MA.T_mixed_high(B), p) ≈
               MA.q_vap_saturation_liq(B, MA.T_mixed_high(B), p)
    Test.@test MA.q_vap_saturation(B, MA.T_mixed_low(B), p) ≈
               MA.q_vap_saturation_ice(B, MA.T_mixed_low(B), p)
end

Test.@testset "the surface forms use Tetens, not Murphy-Koop" begin
    p_s, T = 1.0e5, 265.0
    q = MA.saturation_specific_humidity_from_pT(B, p_s, T)
    Test.@test q == MA.surface_q_vap_saturation(
        B, MA.tetens_saturation_vapor_pressure(B, T), p_s,
    )
    # the interior formulation would give a different number at the same state
    Test.@test q != MA.surface_q_vap_saturation(
        B, MA.saturation_vapor_pressure_liq(B, T), p_s,
    )
    Test.@test MA.saturation_specific_humidity_from_pT(B, p_s, T, MA.Ice()) < q

    # a mixing ratio is per mass of dry air, so it exceeds the specific humidity
    r = MA.saturation_mixing_ratio_from_pT(B, p_s, T)
    Test.@test r > q
    Test.@test r == MA.molmass_ratio(B) * MA.tetens_saturation_vapor_pressure(B, T) /
                    (p_s - MA.tetens_saturation_vapor_pressure(B, T))
end

Test.@testset "equilibrium condensate partitions by liquid fraction" begin
    p, T = 1.0e5, 260.0
    q_sat = MA.q_vap_saturation(B, T, p; λ = MA.liquid_fraction(B, T))
    q_tot = q_sat + 1.0e-3

    (; q_liq, q_ice) = MA.equilibrium_condensate(B, T, p, q_tot)
    Test.@test q_liq + q_ice ≈ 1.0e-3
    λ = MA.liquid_fraction(B, T)
    Test.@test q_liq ≈ λ * (q_liq + q_ice)
    Test.@test q_ice ≈ (1 - λ) * (q_liq + q_ice)

    # unsaturated air holds no condensate
    dry = MA.equilibrium_condensate(B, T, p, q_sat / 2)
    Test.@test dry.q_liq == 0.0
    Test.@test dry.q_ice == 0.0

    # the archive ran liquid-only: everything the adjustment condenses is liquid
    all_liquid = MA.equilibrium_condensate(B, T, p, q_tot; λ = 1.0)
    Test.@test all_liquid.q_ice == 0.0
    Test.@test all_liquid.q_liq > 0.0
end

Test.@testset "density and virtual temperature" begin
    T, p, q_tot = 270.0, 1.0e5, 2.0e-3
    Test.@test MA.virtual_temperature(B, T, 0.0, 0.0, 0.0) == T
    Test.@test MA.virtual_temperature(B, T, q_tot, 0.0, 0.0) > T   # vapour is lighter
    ρ = MA.air_density(B, T, p, q_tot, 0.0, 0.0)
    Test.@test ρ ≈ p / (MA.R_d(B) * MA.virtual_temperature(B, T, q_tot, 0.0, 0.0))
    Test.@test 1.2 < ρ < 1.4
    Test.@test MA.air_density(B, 270.0f0, 1.0f5, 2.0f-3, 0.0f0, 0.0f0) isa Float32
end

Test.@testset "fromztop on a synthetic column" begin
    zf = collect(10.0:20.0:2010.0)
    n = length(zf)
    θ = fill(270.0, n)
    q_tot = fill(1.0e-3, n)
    q_liq = zeros(n)
    ps = 1.0e5
    (; presf, presh) = MA.pressure_fromztop(ps, θ, q_tot, q_liq, zf)

    Test.@test length(presf) == n
    Test.@test length(presh) == n
    Test.@test presh[1] == ps                 # the half-level branch starts at the surface
    Test.@test presf[1] < ps                  # the full-level branch starts half a cell up
    Test.@test issorted(presf; rev = true)    # pressure falls with height
    Test.@test issorted(presh; rev = true)
    # the two are different quantities and neither substitutes for the other
    Test.@test presf != presh

    Test.@test_throws ErrorException MA.pressure_fromztop(ps, θ, q_tot[1:2], q_liq, zf)
end
