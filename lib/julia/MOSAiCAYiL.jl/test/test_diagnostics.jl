using MOSAiCAYiL: MOSAiCAYiL as MA
using Test: Test

const DIAG_DATE = "20200503"

Test.@testset "the nudging rate DALES applied" begin
    z = collect(100.0:100.0:3000.0)
    q_tot = fill(5.0e-3, length(z))
    z_inv = 800.0
    rate = MA.dales_nudging_rate(z, q_tot, z_inv)

    # nothing is nudged below the inversion, everything above the ramp is
    Test.@test all(iszero, rate.heat[z .<= z_inv])
    top = z .>= z_inv + MA.NAMELIST.tb_zmidnudge
    Test.@test all(rate.heat[top] .≈ 1 / MA.NAMELIST.tb_taunudge)
    Test.@test issorted(rate.heat)

    # heat and moisture agree in moist air
    Test.@test rate.heat == rate.moisture

    # dry air relaxes moisture at the timestep instead, which is much faster
    dry = MA.dales_nudging_rate(z, fill(1.0e-8, length(z)), z_inv; dt = 20.0)
    Test.@test dry.moisture[end] ≈ 1 / 20.0
    Test.@test dry.moisture[end] > dry.heat[end]
    Test.@test dry.heat == rate.heat        # the heat rate is unaffected by dryness

    # the relaxation never outruns one step
    fast = MA.dales_nudging_rate(z, q_tot, z_inv; timescale = 1.0, dt = 20.0)
    Test.@test fast.heat[end] ≈ 1 / 20.0

    Test.@test_throws ErrorException MA.dales_nudging_rate(z, q_tot[1:(end - 1)], z_inv)
end

Test.@testset "the total forcing tendency" begin
    n = 5
    T = fill(270.0, n)
    q = fill(4.0e-3, n)
    u = fill(5.0, n)
    v = fill(-2.0, n)
    targets = (; T = fill(272.0, n), q_tot = fill(5.0e-3, n),
                 u = fill(7.0, n), v = fill(-1.0, n))
    advection = (; T = fill(1.0e-5, n), q_tot = fill(2.0e-9, n),
                   u = zeros(n), v = zeros(n))
    rate = (; heat = fill(1.0e-4, n), moisture = fill(1.0e-4, n))

    t = MA.dales_forcing_tendency(; T, q_tot = q, u, v, targets, advection, rate)
    # the column is colder and drier than its target, so both are nudged upward
    Test.@test all(t.dT_dt .> 0)
    Test.@test all(t.dq_dt .> 0)
    Test.@test all(t.du_dt .> 0)
    Test.@test all(t.dv_dt .> 0)

    # switching the nudging off leaves only the advection
    off = MA.dales_forcing_tendency(;
        T, q_tot = q, u, v, targets, advection,
        rate = (; heat = zeros(n), moisture = zeros(n)),
    )
    Test.@test off.dT_dt == advection.T
    Test.@test off.dq_dt == advection.q_tot

    # a column already at its target feels only the advection too
    at_target = MA.dales_forcing_tendency(;
        T = targets.T, q_tot = targets.q_tot, u = targets.u, v = targets.v,
        targets, advection, rate,
    )
    Test.@test at_target.dT_dt ≈ advection.T
end

Test.@testset "the surface energy budget" begin
    sfs = MA.surface_fluxes(DIAG_DATE)
    total = MA.surface_fluxes(DIAG_DATE; resolved = true)

    Test.@test length(sfs.time) == length(sfs.hfss)
    Test.@test all(isfinite, sfs.hfss)
    Test.@test all(isfinite, sfs.buoyancy)

    # the subfilter part is what the surface scheme produced, so at the lowest face the
    # total and the subfilter agree closely
    Test.@test sfs.hfss ≈ total.hfss rtol = 0.05

    # it agrees with the older accessor it supersedes
    old = MA.surface_heat_fluxes(DIAG_DATE)
    Test.@test sfs.hfss ≈ old.hfss
    Test.@test sfs.hfls ≈ old.hfls
    # and adds the buoyancy flux, which the old one has no way to report
    Test.@test !haskey(old, :buoyancy)
    Test.@test any(!iszero, sfs.wθ_v)
end

Test.@testset "the resolved and subfilter flux partition" begin
    cutoff = 1.0e-6
    p = MA.flux_partition("wthl", DIAG_DATE; floor = cutoff)
    Test.@test size(p.resolved) == size(p.subfilter) == size(p.total)
    Test.@test p.resolved .+ p.subfilter ≈ p.total rtol = 1.0e-4

    # the lowest face has no resolved flux at all: the surface flux is entirely subfilter
    Test.@test all(iszero, p.resolved[1, :])
    Test.@test p.subfilter[1, :] ≈ p.total[1, :]
    Test.@test all(iszero, p.resolved_fraction[1, :])

    # the fraction is exactly the resolved share where the total is meaningful, and zero
    # where it is not. It is *unbounded*: where the two parts are large and cancelling the
    # total passes through zero, so no range assertion would be honest here
    active = abs.(p.total) .> cutoff
    Test.@test count(active) > 0
    Test.@test p.resolved_fraction[active] .* p.total[active] ≈ p.resolved[active]
    Test.@test all(iszero, p.resolved_fraction[.!active])
end

Test.@testset "turbulence kinetic energy" begin
    tke = MA.turbulence_kinetic_energy(DIAG_DATE)
    Test.@test size(tke.resolved) == size(tke.subfilter)
    Test.@test length(tke.z) == size(tke.resolved, 1)
    Test.@test all(tke.resolved .>= 0)
    Test.@test all(tke.subfilter .>= 0)
    Test.@test tke.total == tke.resolved .+ tke.subfilter
    # a real boundary layer has energy somewhere
    Test.@test maximum(tke.total) > 0
end

Test.@testset "top-of-atmosphere radiation" begin
    r = MA.toa_radiation(DIAG_DATE)
    Test.@test length(r.time) == length(r.longwave_up)
    Test.@test all(r.longwave_up .> 0)              # the planet always emits
    Test.@test r.net_shortwave == r.shortwave_up .+ r.shortwave_down

    # the clear-sky fields exist in the file and hold nothing, so no cloud effect is
    # derivable; this asserts the archive fact rather than a property of the code
    for name in ("SW_up_ca_TOA", "SW_dn_ca_TOA", "LW_up_ca_TOA", "LW_dn_ca_TOA")
        v = MA.read_variable(name, DIAG_DATE; file = :tmser, translate_units = false)
        Test.@test all(iszero, collect(skipmissing(v.data)))
    end
    # and the downwelling longwave at TOA is zero for a physical reason
    Test.@test all(iszero, collect(skipmissing(
        MA.read_variable("LW_dn_TOA", DIAG_DATE; file = :tmser,
                         translate_units = false).data)))

    # polar night: 2019-11-01 has no shortwave at all
    dark = MA.toa_radiation("20191101")
    Test.@test all(iszero, dark.net_shortwave)
    Test.@test all(dark.longwave_up .> 0)
end

Test.@testset "water paths and precipitation" begin
    w = MA.water_paths(DIAG_DATE)
    for name in (:cloud_liquid, :rain, :cloud_ice, :snow, :graupel)
        Test.@test all(getproperty(w, name) .>= 0)
    end
    Test.@test w.liquid == w.cloud_liquid .+ w.rain
    Test.@test w.ice == w.cloud_ice .+ w.snow .+ w.graupel
    # `lwp_bar` is the liquid path, not the sum over every species
    Test.@test w.total ≈ w.liquid rtol = 1.0e-3

    p = MA.surface_precipitation(DIAG_DATE)
    Test.@test p.total == p.liquid .+ p.ice
    Test.@test all(p.total .>= 0)
end

Test.@testset "the realized phase partition" begin
    φ = MA.phase_partition(DIAG_DATE)
    Test.@test all(0 .<= φ.liquid_fraction .<= 1)
    Test.@test size(φ.liquid_fraction) == size(φ.q_liquid)
    # where there is no condensate the fraction is zero rather than undefined
    empty = (φ.q_liquid .+ φ.q_ice) .<= 1.0e-12
    Test.@test all(iszero, φ.liquid_fraction[empty])
    # a mixed-phase Arctic day has both phases present somewhere
    Test.@test any(φ.q_ice .> 0)
end
