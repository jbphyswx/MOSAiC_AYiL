using MOSAiCAYiL: MOSAiCAYiL as MA
using Test: Test

const SB3_ORDER = (:cloud_liquid, :rain, :cloud_ice, :snow, :graupel)

Test.@testset "SB3_PARTICLES is Seifert-Beheng Table 1 as DALES declares it" begin
    Test.@test keys(MA.SB3_PARTICLES) == SB3_ORDER

    # modmicrodata3.f90:196-236, species in the order above
    Test.@test [MA.SB3_PARTICLES[s].a for s in SB3_ORDER] ==
               [0.124, 0.124, 0.217, 8.156, 0.190]
    Test.@test [MA.SB3_PARTICLES[s].b for s in SB3_ORDER] ==
               [0.33333, 0.33333, 0.302115, 0.526, 0.323]
    Test.@test [MA.SB3_PARTICLES[s].c for s in SB3_ORDER] ==
               [2.0, 2.0, 3.14159, 2.0, 2.0]
    Test.@test [MA.SB3_PARTICLES[s].α for s in SB3_ORDER] ==
               [3.75e5, 159.0, 41.9, 27.7, 40.0]
    Test.@test [MA.SB3_PARTICLES[s].β for s in SB3_ORDER] ==
               [0.66667, 0.266, 0.36, 0.216, 0.230]
    Test.@test [MA.SB3_PARTICLES[s].γ for s in SB3_ORDER] == [1.0, 0.5, 0.5, 0.5, 0.5]
    Test.@test [MA.SB3_PARTICLES[s].ν for s in SB3_ORDER] ==
               [1.0, -0.66667, 0.0, 1.0, 1.0]
    Test.@test [MA.SB3_PARTICLES[s].μ for s in SB3_ORDER] ==
               [1.0, 0.33333, 0.33333, 0.33333, 0.33333]
    Test.@test [MA.SB3_PARTICLES[s].σ_v for s in SB3_ORDER] == [0.0, 0.0, 0.2, 0.2, 0.0]

    # mass bounds; rain takes modmicrodata.f90's xrmin/xrmax, not x_hr_bmin
    Test.@test [MA.SB3_PARTICLES[s].x_min for s in SB3_ORDER] ==
               [4.20e-15, 2.6e-10, 1.0e-12, 1.73e-9, 2.6e-10]
    Test.@test [MA.SB3_PARTICLES[s].x_max for s in SB3_ORDER] ==
               [1.01e-11, 5.0e-6, 1.0e-7, 1.0e-6, 1.0e-4]
    Test.@test MA.SB3_PARTICLES.rain.x_min != MA.SB3_UNUSED.x_hr_bmin.value
    for s in SB3_ORDER
        Test.@test MA.SB3_PARTICLES[s].x_min < MA.SB3_PARTICLES[s].x_max
        Test.@test MA.SB3_PARTICLES[s].q_min == MA.SB3_THRESHOLDS.q_min
    end
end

Test.@testset "the truncated shape parameters are load-bearing" begin
    # at exact 1/3 and -2/3 the rain ventilation argument (nu + b)/mu is exactly -1,
    # a pole of the gamma function; DALES's decimals miss it by 3e-5
    rain = MA.SB3_PARTICLES.rain
    Test.@test rain.ν === -0.66667
    Test.@test rain.μ === 0.33333
    Test.@test rain.b === 0.33333
    argument = (rain.ν + rain.b) / rain.μ
    Test.@test argument != -1.0
    Test.@test isapprox(argument, -1.0; atol = 1.0e-4)
    # the exact fractions would land on the pole
    Test.@test (-2 / 3 + 1 / 3) / (1 / 3) ≈ -1.0
end

Test.@testset "SB3 carries its own freezing point" begin
    # a reader will assume these agree; they do not
    Test.@test MA.SB3_PHYSICS.T_3 == 273.15
    Test.@test MA.DALES_CONSTANTS.T_melt == 273.16
    Test.@test MA.SB3_PHYSICS.T_3 != MA.DALES_CONSTANTS.T_melt
end

Test.@testset "the scalar map matches the archive's own naming" begin
    Test.@test MA.SB3_N_SCALARS == 12
    Test.@test length(MA.SB3_SCALAR_INDEX) == MA.SB3_N_SCALARS
    Test.@test sort(collect(values(MA.SB3_SCALAR_INDEX))) == collect(1:12)
    # every slot resolves to the same physical name the fielddump translation gives
    for (name, slot) in pairs(MA.SB3_SCALAR_INDEX)
        raw = "sv" * lpad(slot, 3, '0')
        Test.@test MA.SB3_TO_PHYSICAL[raw] == String(name)
    end
end

Test.@testset "the namelist values that overrode the module defaults" begin
    # &nambulk3 set these; the module defaults are different numbers
    Test.@test MA.SB3_NUCLEATION.n_i_max == 200.0e3
    Test.@test MA.SB3_NUCLEATION.n_i_max != MA.SB3_NUCLEATION.n_i_max_default
    Test.@test MA.SB3_FREEZING.tlimhetfreeze == 258.15
    Test.@test MA.SB3_FREEZING.tlimhetfreeze != MA.SB3_FREEZING.tlimhetfreeze_default
    Test.@test MA.SB3_NUCLEATION.Nc0 == MA.NAMELIST.nc0
    Test.@test MA.SB3_NUCLEATION.Nc0 != MA.SB3_NUCLEATION.Nc0_default
    # and the radiation's droplet number is that module default, a different symbol
    Test.@test MA.RADIATION.Nc_0 == MA.SB3_NUCLEATION.Nc0_default
end

Test.@testset "switches select the classic branch" begin
    Test.@test MA.SB3_SWITCHES.l_sb_classic === true
    Test.@test MA.SB3_SWITCHES.l_c_ccn === false
    Test.@test MA.SB3_SWITCHES.l_lognormal === false
    Test.@test MA.SB3_SWITCHES.l_mur_cst === false
    # `&nambulk3` sets l_setccn explicitly, and to the same value as the module default
    Test.@test MA.SB3_SWITCHES.l_setccn === false
    # this is modmicrodata3's own flag, not modtestbed's ltb_setinp
    Test.@test MA.SB3_SWITCHES.l_setinp === false
end

Test.@testset "the dead register names a value and a reason" begin
    Test.@test !isempty(MA.SB3_UNUSED)
    for (name, entry) in pairs(MA.SB3_UNUSED)
        Test.@test haskey(entry, :value)
        Test.@test haskey(entry, :reason)
        Test.@test !isempty(entry.reason)
    end
    # the two that would change a rate if a reader took them for live settings
    Test.@test MA.SB3_UNUSED.E_ii_m.value == 0.1
    Test.@test MA.SB3_UNUSED.E_ii_m.value != MA.SB3_COLLISION.E_ee_m
    Test.@test MA.SB3_UNUSED.a_v_cloud_ice.value == 0.86
    Test.@test MA.SB3_UNUSED.a_v_cloud_ice.value != MA.SB3_PHYSICS.a_v
end

Test.@testset "the per-species helpers" begin
    ice = MA.SB3_PARTICLES.cloud_ice

    # the mean mass is clamped to the species bounds
    Test.@test MA.sb3_mean_mass(1.0e-6, 1.0e3, ice) ≈ 1.0e-9
    Test.@test MA.sb3_mean_mass(1.0, 1.0, ice) == ice.x_max
    Test.@test MA.sb3_mean_mass(1.0e-30, 1.0, ice) == ice.x_min

    # D = a x^b, and it is strictly increasing in x
    x = 1.0e-9
    Test.@test MA.sb3_diameter(x, ice) ≈ ice.a * x^ice.b
    Test.@test MA.sb3_diameter(2x, ice) > MA.sb3_diameter(x, ice)

    # v = alpha x^beta (rho_ref/rho)^gamma: heavier falls faster, thinner air falls faster
    ρ = 1.0
    Test.@test MA.sb3_fall_speed(x, ρ, ice) ≈
               ice.α * x^ice.β * (MA.SB3_PHYSICS.ρ_ref / ρ)^ice.γ
    Test.@test MA.sb3_fall_speed(2x, ρ, ice) > MA.sb3_fall_speed(x, ρ, ice)
    Test.@test MA.sb3_fall_speed(x, 0.5, ice) > MA.sb3_fall_speed(x, 1.5, ice)

    # they work for every species, which is the point of the rename
    for s in SB3_ORDER
        p = MA.SB3_PARTICLES[s]
        Test.@test MA.sb3_diameter(p.x_min, p) > 0
        Test.@test MA.sb3_fall_speed(p.x_min, 1.0, p) > 0
        Test.@test MA.sb3_diameter(p.x_max, p) > MA.sb3_diameter(p.x_min, p)
    end
    # snow has both the largest prefactor (8.156) and the largest exponent (0.526), so it
    # crosses graupel rather than dominating it everywhere
    snow, graupel = MA.SB3_PARTICLES.snow, MA.SB3_PARTICLES.graupel
    Test.@test snow.a == maximum(MA.SB3_PARTICLES[s].a for s in SB3_ORDER)
    Test.@test snow.b == maximum(MA.SB3_PARTICLES[s].b for s in SB3_ORDER)
    Test.@test MA.sb3_diameter(1.0e-9, snow) < MA.sb3_diameter(1.0e-9, graupel)
    Test.@test MA.sb3_diameter(1.0e-7, snow) > MA.sb3_diameter(1.0e-7, graupel)
end
