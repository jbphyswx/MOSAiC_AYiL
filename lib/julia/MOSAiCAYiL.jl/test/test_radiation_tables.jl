using MOSAiCAYiL: MOSAiCAYiL as MA
using Test: Test

Test.@testset "the cloud-liquid optical table" begin
    t = MA.CLOUD_LIQUID_OPTICS
    Test.@test size(t.extinction) == (8, 18)
    Test.@test size(t.single_scattering_albedo) == (8, 18)
    Test.@test size(t.asymmetry) == (8, 18)
    Test.@test length(t.r_eff) == 8
    Test.@test length(t.water_content) == 8
    Test.@test length(t.band_centre) == 18
    Test.@test issorted(t.r_eff)
    Test.@test all(>(0), t.extinction)
    Test.@test all(0 .< t.single_scattering_albedo .<= 1)
    Test.@test all(-1 .< t.asymmetry .< 1)
    Test.@test issorted(t.band_centre; rev = true)
end

Test.@testset "cloud_liquid_optics reproduces the table at its own radii" begin
    t = MA.CLOUD_LIQUID_OPTICS
    wc = 1.0e-4                       # kg/m^3, well above the cutoff
    for band in axes(t.extinction, 2), j in 2:(length(t.r_eff) - 1)
        got = MA.cloud_liquid_optics(band, wc, t.r_eff[j])
        # at a tabulated radius the interpolation must return that row exactly
        Test.@test got.single_scattering_albedo ≈ t.single_scattering_albedo[j, band]
        Test.@test got.asymmetry ≈ t.asymmetry[j, band]
        Test.@test got.extinction ≈ wc * t.extinction[j, band] / t.water_content[j]
    end
end

Test.@testset "cloud_liquid_optics interpolates as modradfull does" begin
    t = MA.CLOUD_LIQUID_OPTICS
    wc = 1.0e-4
    band, j = 5, 3
    j1 = j + 1

    # the albedo and the asymmetry are linear in r_eff
    r_mid = (t.r_eff[j] + t.r_eff[j1]) / 2
    mid = MA.cloud_liquid_optics(band, wc, r_mid)
    Test.@test mid.single_scattering_albedo ≈
               (t.single_scattering_albedo[j, band] + t.single_scattering_albedo[j1, band]) / 2
    Test.@test mid.asymmetry ≈ (t.asymmetry[j, band] + t.asymmetry[j1, band]) / 2

    # the mass extinction is linear in 1/r_eff, which is a different point
    r_harmonic = 2 / (1 / t.r_eff[j] + 1 / t.r_eff[j1])
    harmonic = MA.cloud_liquid_optics(band, wc, r_harmonic)
    β(i) = t.extinction[i, band] / t.water_content[i]
    Test.@test harmonic.extinction ≈ wc * (β(j) + β(j1)) / 2
    # and the two conventions disagree, so this is a real test of which one is used
    Test.@test !isapprox(mid.extinction, wc * (β(j) + β(j1)) / 2; rtol = 1.0e-6)
end

Test.@testset "cloud_liquid_optics clamps rather than extrapolating" begin
    t = MA.CLOUD_LIQUID_OPTICS
    wc = 1.0e-4
    band = 7
    below = MA.cloud_liquid_optics(band, wc, first(t.r_eff) / 2)
    Test.@test below.single_scattering_albedo == t.single_scattering_albedo[1, band]
    Test.@test below.asymmetry == t.asymmetry[1, band]

    above = MA.cloud_liquid_optics(band, wc, last(t.r_eff) * 2)
    n = length(t.r_eff)
    Test.@test above.single_scattering_albedo == t.single_scattering_albedo[n, band]
    Test.@test above.asymmetry == t.asymmetry[n, band]
end

Test.@testset "below the water cutoff everything is zero" begin
    zeroed = MA.cloud_liquid_optics(4, 1.0e-9, 10.0)
    Test.@test zeroed.extinction == 0
    Test.@test zeroed.single_scattering_albedo == 0
    Test.@test zeroed.asymmetry == 0
    # and just above it, it is not
    Test.@test MA.cloud_liquid_optics(4, 1.0e-7, 10.0).extinction > 0

    Test.@test_throws ErrorException MA.cloud_liquid_optics(0, 1.0e-4, 10.0)
    Test.@test_throws ErrorException MA.cloud_liquid_optics(19, 1.0e-4, 10.0)
end

Test.@testset "the radiation band structure" begin
    b = MA.RADIATION_BANDS
    Test.@test length(b.edge) == 19
    Test.@test length(b.power) == 18
    Test.@test issorted(b.edge; rev = true)
    Test.@test last(b.edge) == 0
    Test.@test count(>(0), b.power) == 6            # the solar bands
    Test.@test count(==(0), b.power) == 12          # the infrared ones
    Test.@test sum(b.power) ≈ MA.SOLAR_TOTAL_POWER
    Test.@test length(MA.RADIATION_GASES) == 23
    Test.@test all(1 .<= last.(MA.RADIATION_GASES) .<= 18)
    Test.@test length(unique(last.(MA.RADIATION_GASES))) == 18
    # the cloud table is matched to this band structure, which is what DALES checks on load
    Test.@test length(MA.CLOUD_LIQUID_OPTICS.band_centre) == length(b.power)
    for i in eachindex(MA.CLOUD_LIQUID_OPTICS.band_centre)
        Test.@test MA.CLOUD_LIQUID_OPTICS.band_centre[i] ≈ (b.edge[i] + b.edge[i + 1]) / 2
    end
end

Test.@testset "extinction scales with water content" begin
    a = MA.cloud_liquid_optics(9, 1.0e-4, 8.0)
    b = MA.cloud_liquid_optics(9, 2.0e-4, 8.0)
    Test.@test b.extinction ≈ 2 * a.extinction
    Test.@test b.single_scattering_albedo == a.single_scattering_albedo
end
