using MOSAiCAYiL: MOSAiCAYiL as MA
using Test: Test

Test.@testset "the subgrid closure is the one init computed" begin
    s = MA.SUBGRID
    # the declared values are NOT what ran; a transcription of the declaration fails here
    Test.@test s.cm ≈ 0.11789255043844099
    Test.@test s.cm != 0.12
    Test.@test s.ce1 ≈ 0.20428421139973055
    Test.@test s.ce1 != 0.19
    Test.@test s.ce2 ≈ 0.54038960278451664
    Test.@test s.ce2 != 0.51
    Test.@test s.ceps ≈ 0.74467381418424716
    Test.@test s.ch == 3.0
    Test.@test s.ch2 == 2.0                       # recomputed onto its declared value

    # and they are consistent with the inputs they are computed from
    Test.@test s.cm ≈ s.cf / (2π) * (1.5 * s.alpha_kolm)^(-1.5)
    Test.@test s.ceps ≈ 2π / s.cf * (1.5 * s.alpha_kolm)^(-1.5)
    Test.@test s.ce1 ≈ s.cn^2 * (s.cm / s.Rigc - s.ch1 * s.cm)
    Test.@test s.ce2 ≈ s.ceps - s.ce1
    Test.@test s.ch ≈ 1 / s.Prandtl

    # prognostic TKE, not Smagorinsky
    Test.@test s.lsmagorinsky === false
    Test.@test s.sgs_surface_fix === false        # unreachable: absent from NAMSUBGRID
end

Test.@testset "the sponge layer" begin
    Test.@test MA.sponge_base_level(286) == 214
    Test.@test MA.sponge_base_level(286) == min(3 * 286 ÷ 4, 286 - 15)
    Test.@test MA.sponge_base_level(286; ksp = 100) == 100
    Test.@test MA.SPONGE.igrw_damp == 2

    zf = MA.LES_CENTRES
    ksp = MA.sponge_base_level(length(zf))
    Test.@test zf[ksp] ≈ 2879.4866
    Test.@test 1 / MA.SPONGE.rnu0 ≈ 363.6363636363636

    rate = MA.sponge_damping_rate(zf)
    Test.@test length(rate) == length(zf)
    Test.@test all(iszero, rate[1:(ksp - 1)])     # nothing below the base
    Test.@test rate[ksp] == 0                     # sin(0) at the base itself
    Test.@test last(rate) ≈ MA.SPONGE.rnu0        # the full rate at the top
    Test.@test issorted(rate)
end

Test.@testset "eleven of the twelve scalars are not flux-limited" begin
    schemes = MA.scalar_advection_schemes(MA.NAMELIST.nsv)
    Test.@test length(schemes) == 12
    Test.@test schemes[1] == MA.ADVECTION_SCHEMES.kappa_f
    Test.@test all(==(MA.ADVECTION_SCHEMES.fifth), schemes[2:end])
    Test.@test count(==(MA.ADVECTION_SCHEMES.fifth), schemes) == 11

    Test.@test MA.ADVECTION.iadv_mom == MA.ADVECTION_SCHEMES.fifth
    Test.@test MA.ADVECTION.iadv_thl == MA.ADVECTION_SCHEMES.kappa_f
    # courant is derived from the scheme mix, not set in the namelist
    Test.@test MA.ADVECTION.courant == 0.7
end

Test.@testset "radiation settings" begin
    Test.@test MA.RADIATION.iradiation == 1
    Test.@test MA.RADIATION.sw0 == 1368.22
    Test.@test MA.RADIATION.timerad == 0          # every timestep
    # the radiation's droplet number is a different symbol from the microphysics one
    Test.@test MA.RADIATION.Nc_0 != MA.NAMELIST.nc0
    Test.@test MA.RADIATION.emissurf == MA.NAMELIST.emissurf
    # the scaling DALES applies to its shortwave fluxes
    Test.@test MA.RADIATION.sw0 / MA.SOLAR_TOTAL_POWER > 1
end

Test.@testset "coriolis" begin
    (; om22, om23) = MA.coriolis_parameters(90.0)
    Test.@test om23 ≈ 2 * MA.CORIOLIS.omega
    Test.@test isapprox(om22, 0.0; atol = 1.0e-15)
    Test.@test MA.coriolis_parameters(0.0).om23 ≈ 0.0
    # an Arctic day: the vertical component dominates
    high = MA.coriolis_parameters(85.0)
    Test.@test high.om23 > high.om22
end

Test.@testset "perturbations reach every level and no wind" begin
    p = MA.PERTURBATIONS
    Test.@test p.krandumin > p.krandumax          # so no wind perturbation is applied
    Test.@test p.randthl == 0.1
    Test.@test p.randqt == 2.5e-5
end

