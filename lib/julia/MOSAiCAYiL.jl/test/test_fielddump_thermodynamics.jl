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

Test.@testset "a column that does not cover the fielddump" begin
    mktempdir() do dir
        f = write_fielddump_tiles(dir)
        MA.open_fielddump(dir) do fd
            good = fixture_column(f; nz = f.nz, nt = f.nt)
            # shifting either axis up leaves the fielddump's last level/time off the end
            shifted = (; good.z, time = good.time .+ 1.0, good.presf, good.exner)
            lifted = (; z = good.z .+ 1.0, good.time, good.presf, good.exner)
            for column in (shifted, lifted)
                Test.@test_throws ErrorException MA.fielddump_thermodynamics(fd, column)
                # naming what to do about it is the point of the boundary condition
                out = MA.fielddump_thermodynamics(
                    fd, column; bc = MA.ExtrapolateBoundaryCondition(),
                )
                Test.@test all(isfinite, out.pressure)
                Test.@test size(out.pressure) == (f.nz, f.nt)
            end
        end
    end
end

Test.@testset "the column is interpolated onto the fielddump, not matched to it" begin
    mktempdir() do dir
        f = write_fielddump_tiles(dir)
        MA.open_fielddump(dir) do fd
            exact = fixture_column(f; nz = f.nz, nt = f.nt)
            reference = MA.fielddump_thermodynamics(fd, exact)

            # a column on twice as many levels, spanning the same range: interpolating it
            # back onto the fielddump's levels must return what the exact column gave
            b = MA.DefaultThermodynamicsBackend()
            fine_z = collect(range(first(exact.z), last(exact.z); length = 2 * f.nz - 1))
            fine_p = [1.0e5 - 12.0 * zk + 100.0 * t for zk in fine_z, t in 1:(f.nt)]
            fine = (; z = fine_z, exact.time, presf = fine_p, exner = MA.exner.(b, fine_p))
            got = MA.fielddump_thermodynamics(fd, fine)
            Test.@test got.pressure ≈ reference.pressure
            Test.@test got.exner ≈ reference.exner

            # a Float32 column against Float64 coordinates, which exact matching could not do
            cheap = (;
                z = Float32.(exact.z), time = Float32.(exact.time),
                presf = Float32.(exact.presf), exner = Float32.(exact.exner),
            )
            Test.@test MA.fielddump_thermodynamics(fd, cheap).pressure ≈
                       reference.pressure rtol = 1.0e-6
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

Test.@testset "the level axis may follow the time axis" begin
    # an assembled global file carries (time, zt, yt, xt); `reshape` preserves linear order,
    # so a level-major column block would land transposed. nz == nt is the one shape where
    # that transpose has the right element count and would corrupt silently.
    for (nz, nt) in ((3, 2), (3, 3))
        mktempdir() do dir
            forward = joinpath(dir, "fwd")
            reversed = joinpath(dir, "rev")
            mkpath(forward)
            mkpath(reversed)
            f = write_fielddump_tiles(forward; nz, nt)
            r = write_fielddump_tiles(reversed; nz, nt, time_first = true)
            column = fixture_column(f; nz, nt)

            MA.open_fielddump(forward) do fwd
                MA.open_fielddump(reversed) do rev
                    Test.@test MA.fielddump_thermodynamics isa Function
                    a = MA.fielddump_thermodynamics(fwd, column)
                    b = MA.fielddump_thermodynamics(rev, column)

                    Test.@test fwd.dims["thl"] == ("xt", "yt", "zt", "time")
                    Test.@test rev.dims["thl"] == ("time", "zt", "yt", "xt")
                    Test.@test size(a.temperature) == (f.nx, f.ny, nz, nt)
                    Test.@test size(b.temperature) == (nt, nz, r.ny, r.nx)

                    # the same physical field, written along opposite axes
                    Test.@test a.temperature[:, :, :, :] ≈
                               permutedims(b.temperature[:, :, :, :], (4, 3, 2, 1))
                    Test.@test a.density[:, :, :, :] ≈
                               permutedims(b.density[:, :, :, :], (4, 3, 2, 1))
                    Test.@test a.pressure == b.pressure
                end
            end
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
