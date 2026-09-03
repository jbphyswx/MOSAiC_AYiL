using MOSAiCAYiL: MOSAiCAYiL as MA
using Test: Test

include("fielddump_fixture.jl")

# `fielddump_thermodynamics` needs only these four fields of a column, which is the whole
# contract between it and `dales_slab_column`.
function fixture_column(f; nz, nt)
    z = collect(Float64.(1:nz) .* 10 .- 5)          # matches the fixture's `zt`
    time = collect(Float64.(1:nt) .* 1800)
    b = MA.DefaultThermodynamicsBackend()
    presf = [1.0e5 - 12.0 * z[k] + 100.0 * t for k in 1:nz, t in 1:nt]
    return (; z, time, presf, exner = MA.exner.(b, presf))
end

Test.@testset "the derived thermodynamics are the stated formulas" begin
    mktempdir() do dir
        f = write_fielddump_tiles(dir)
        MA.open_fielddump(dir) do fd
            column = fixture_column(f; nz = f.nz, nt = f.nt)
            th = MA.fielddump_thermodynamics(fd, column)
            b = MA.DefaultThermodynamicsBackend()

            Test.@test size(th.pressure) == (f.nz, f.nt)
            Test.@test size(th.exner) == (f.nz, f.nt)
            Test.@test size(th.temperature) == (f.nx, f.ny, f.nz, f.nt)
            Test.@test size(th.density) == (f.nx, f.ny, f.nz, f.nt)

            thl, qt, ql = f.expected["thl"], f.expected["qt"], f.expected["ql"]
            # the fixture must actually exercise a positive vapour content
            Test.@test all(qt .> ql)

            want_T = [
                th.exner[k, t] * thl[i, j, k, t] +
                (MA.L_v0(b) / MA.cp_d(b)) * ql[i, j, k, t]
                for i in 1:f.nx, j in 1:f.ny, k in 1:f.nz, t in 1:f.nt
            ]
            Test.@test th.temperature[:, :, :, :] ≈ want_T

            want_ρ = [
                MA.air_density(
                    b, want_T[i, j, k, t], th.pressure[k, t],
                    Float64(qt[i, j, k, t]), Float64(ql[i, j, k, t]), 0.0,
                )
                for i in 1:f.nx, j in 1:f.ny, k in 1:f.nz, t in 1:f.nt
            ]
            Test.@test th.density[:, :, :, :] ≈ want_ρ
            Test.@test all(>(0), th.density[:, :, :, :])
        end
    end
end

Test.@testset "a derived variable indexes like an Array" begin
    mktempdir() do dir
        f = write_fielddump_tiles(dir)
        MA.open_fielddump(dir) do fd
            column = fixture_column(f; nz = f.nz, nt = f.nt)
            th = MA.fielddump_thermodynamics(fd, column)
            full = th.temperature[:, :, :, :]

            # scalar-indexed axes are dropped, as they are for an Array
            Test.@test size(th.temperature[:, :, 2, 1]) == (f.nx, f.ny)
            Test.@test th.temperature[:, :, 2, 1] ≈ full[:, :, 2, 1]
            Test.@test size(th.temperature[1:2, 1:2, :, 1]) == (2, 2, f.nz)
            Test.@test th.temperature[1:2, 1:2, :, 1] ≈ full[1:2, 1:2, :, 1]
            Test.@test th.temperature[2, 3, 1, 2] ≈ full[2, 3, 1, 2]
            Test.@test th.temperature[2, 3, 1, 2] isa Real

            # a column: the level axis is kept, the horizontal ones are dropped
            Test.@test size(th.density[1, 1, :, :]) == (f.nz, f.nt)
            Test.@test th.density[1, 1, :, :] ≈ th.density[:, :, :, :][1, 1, :, :]
        end
    end
end

Test.@testset "an unmatched level or time errors" begin
    mktempdir() do dir
        f = write_fielddump_tiles(dir)
        MA.open_fielddump(dir) do fd
            good = fixture_column(f; nz = f.nz, nt = f.nt)
            # a column whose times do not include the fielddump's
            shifted = (; good.z, time = good.time .+ 1.0, good.presf, good.exner)
            Test.@test_throws ErrorException MA.fielddump_thermodynamics(fd, shifted)
            # and one whose levels do not
            lifted = (; z = good.z .+ 1.0, good.time, good.presf, good.exner)
            Test.@test_throws ErrorException MA.fielddump_thermodynamics(fd, lifted)
        end
    end
end

Test.@testset "it derives rather than shadowing what a run wrote" begin
    mktempdir() do dir
        f = write_fielddump_tiles(dir)
        MA.open_fielddump(dir) do fd
            column = fixture_column(f; nz = f.nz, nt = f.nt)
            th = MA.fielddump_thermodynamics(fd, column)
            # nothing is added to or replaced in the file's own variables
            Test.@test !haskey(fd.vars, "temperature")
            Test.@test !haskey(fd.vars, "pressure")
            Test.@test sort(collect(keys(fd.vars))) ==
                       ["n_rain", "ql", "qt", "thl", "v", "w"]
            Test.@test th.temperature isa MA.DerivedFielddumpVariable
            Test.@test th.density isa MA.DerivedFielddumpVariable
        end
    end
end

Test.@testset "the fielddump thl long name is corrected" begin
    # the netCDF path writes the full theta_l; "above 300K" is the binary path's offset
    Test.@test MA.fielddump_long_name(
        "thl", "Liquid water potential temperature above 300K",
    ) == "Liquid water potential temperature"
    Test.@test MA.fielddump_long_name("qt", "Total water specific humidity") ==
               "Total water specific humidity"
end
