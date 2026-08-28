using MOSAiCAYiL: MOSAiCAYiL as MA
using Test: Test

Test.@testset "clocks" begin
    Test.@test MA.PUBLISHED_RUNTIME_S == 7200
    Test.@test MA.PAPER_RUNTIME_S == 10800
    Test.@test MA.EVALUATION_S == 5400
    Test.@test MA.PROFILES_TIME == 300:300:7200
    Test.@test MA.t_end(MA.case("20200503")) == MA.PUBLISHED_RUNTIME_S
    Test.@test MA.reference_datetime(MA.case("20200503")) ==
               MA.Dates.DateTime(2020, 5, 3, 11)
end

Test.@testset "namelist used vs placeholders" begin
    Test.@test MA.NAMELIST.tb_taunudge == 10800.0
    Test.@test MA.NAMELIST.tb_zmidnudge == 300.0
    Test.@test MA.NAMELIST.tb_zminnudge == -1.0
    Test.@test MA.NAMELIST.tb_minzinv == 100.0
    Test.@test MA.NAMELIST.tb_maxzinv == 5000.0
    n = MA.nudging_parameters(MA.case("20200503"))
    Test.@test n.timescale == 10800.0
    Test.@test n.ramp_depth == 300.0
    Test.@test n.z_min == -1.0
end

Test.@testset "ice-init diameters" begin
    Test.@test MA.PAPER_ICE_INIT_DIAMETER_M == 55.0e-6
    Test.@test MA.DALES_D_CI_M == 60.0e-6
end

Test.@testset "grid faces" begin
    Test.@test length(MA.LES_FACES) == 287
    Test.@test first(MA.LES_FACES) == 0
    Test.@test last(MA.LES_FACES) == 11949.301f0
    Test.@test MA.PRODUCTION_GRID.nz == 286
    Test.@test MA.TEST_GRID.nz == 286
    Test.@test MA.native_faces(MA.case("20200503")) === MA.LES_FACES
    Test.@test MA.z_max(MA.case("20200503")) == MA.LES_TOP_FACE

    stretched = MA.stretch_faces()
    Test.@test length(stretched) == length(MA.LES_FACES)
    Test.@test first(stretched) == 0
    # the formula constructor is not bit-identical to the stored DALES faces
    Test.@test stretched != MA.LES_FACES
    Test.@test last(stretched) ≠ last(MA.LES_FACES)
end

Test.@testset "TKE seed" begin
    Test.@test MA.dales_tke_seed(0.0) ≈ (MA.DALES_CONSTANTS.e12_min + 1)^2
    Test.@test MA.dales_tke_seed(50.0) < MA.dales_tke_seed(0.0)
    Test.@test MA.dales_tke_seed(5000.0) ≈ MA.DALES_CONSTANTS.e12_min^2 rtol = 1.0e-6
end

Test.@testset "surface blend (file-free)" begin
    Test.@test MA.surface_temperature(0.4, 271.0, 250.0) ≈ 0.6 * 271.0 + 0.4 * 250.0
    q = MA.qseaicefrctsurf(0.5, 271.35, 250.0, 1.0e5)
    Test.@test q > 0
    # not q_sat of the blended temperature: e_s is exponential in T
    T_blend = MA.surface_temperature(0.5, 271.35, 250.0)
    es_blend = MA.esat_liquid(T_blend)
    q_blend =
        (MA.DALES_CONSTANTS.R_d / MA.DALES_CONSTANTS.R_v) * es_blend / 1.0e5
    Test.@test q ≠ q_blend
end
