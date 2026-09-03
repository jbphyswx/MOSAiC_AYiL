using MOSAiCAYiL: MOSAiCAYiL as MA
using Test: Test

Test.@testset "read_ckd parses the k-distributions" begin
    ckd = MA.read_ckd("20200503")
    Test.@test ckd.nbands == 18
    Test.@test length(ckd.gases) == 23
    Test.@test collect(ckd.edge) == collect(MA.RADIATION_BANDS.edge)
    Test.@test collect(ckd.power) == collect(MA.RADIATION_BANDS.power)

    for g in ckd.gases
        # DALES stops the run when this fails, so it is a real check on the parse
        Test.@test sum(g.hk) ≈ 1
        Test.@test length(g.hk) == g.ng
        Test.@test length(g.sp) == g.np
        Test.@test size(g.xk) == (g.nt, g.np, g.ng, g.noverlap)
    end

    # the constants are checked against the file rather than asserted
    Test.@test [(g.name, g.band) for g in ckd.gases] == collect(MA.RADIATION_GASES)

    by_name(n) = unique(
        g.default_concentration for g in ckd.gases if g.name == n && g.default_concentration != 0
    )
    Test.@test only(by_name("CH4")) == MA.TRACE_GAS_CONCENTRATIONS.CH4
    Test.@test only(by_name("N2O")) == MA.TRACE_GAS_CONCENTRATIONS.N2O
    Test.@test only(by_name("OVRLP")) == MA.TRACE_GAS_CONCENTRATIONS.CO2
    # water vapour and ozone come from the column, not from a fixed concentration
    Test.@test all(
        g.default_concentration == 0 for g in ckd.gases if g.name in ("H2O", "O3")
    )

    Test.@test sum(g -> length(g.xk), ckd.gases) == 6820
end

Test.@testset "the ckd file is the same on every day" begin
    a = MA.read_ckd("20200503")
    b = MA.read_ckd("20200720")
    Test.@test collect(a.power) == collect(b.power)
    Test.@test [g.hk for g in a.gases] == [g.hk for g in b.gases]
    Test.@test [g.xk for g in a.gases] == [g.xk for g in b.gases]
end
