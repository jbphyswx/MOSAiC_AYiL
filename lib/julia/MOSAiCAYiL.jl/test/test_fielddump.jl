using MOSAiCAYiL: MOSAiCAYiL as MA
using Test: Test

include("fielddump_fixture.jl")

Test.@testset "fielddump tiles stitch onto the global grid" begin
    mktempdir() do dir
        f = write_fielddump_tiles(dir)
        fd = MA.open_fielddump(dir)
        try
            Test.@test fd.tiles == f.n_tiles
            Test.@test sort(collect(keys(fd.vars))) == ["n_rain", "thl", "v", "w"]

            # the staggered axes survive: each variable keeps the axis it is stored on
            Test.@test fd.dims["thl"] == ("xt", "yt", "zt", "time")
            Test.@test fd.dims["v"] == ("xt", "ym", "zt", "time")
            Test.@test fd.dims["w"] == ("xt", "yt", "zm", "time")

            # `v` lives on `ym` and is stitched along it, not truncated to one tile
            Test.@test size(fd.vars["v"]) == (f.nx, f.ny, f.nz, f.nt)
            Test.@test size(fd.vars["thl"]) == (f.nx, f.ny, f.nz, f.nt)

            Test.@test fd.vars["thl"][:, :, :, :] == f.expected["thl"]
            Test.@test fd.vars["v"][:, :, :, :] == f.expected["v"]
            Test.@test fd.vars["w"][:, :, :, :] == f.expected["w"]
            Test.@test fd.vars["n_rain"][:, :, :, :] == f.expected["sv001"]

            Test.@test length(fd.coords["yt"]) == f.ny
            Test.@test issorted(fd.coords["yt"])
        finally
            MA.close_fielddump(fd)
        end
    end
end

Test.@testset "indexing reads only what is asked, with Base's semantics" begin
    mktempdir() do dir
        f = write_fielddump_tiles(dir)
        MA.open_fielddump(dir) do fd
            v = fd.vars["thl"]
            want = f.expected["thl"]

            # an axis indexed by a scalar is dropped, as it is for an Array
            Test.@test size(v[:, :, 2, 1]) == (f.nx, f.ny)
            Test.@test v[:, :, 2, 1] == want[:, :, 2, 1]
            Test.@test size(v[1:2, 1:2, :, 1]) == (2, 2, f.nz)
            Test.@test v[1:2, 1:2, :, 1] == want[1:2, 1:2, :, 1]
            Test.@test v[2, 3, 1, 2] === want[2, 3, 1, 2]
            Test.@test v[:, :, :, 1] == want[:, :, :, 1]

            # a request inside one tile is served without the others
            Test.@test v[:, 1:2, :, :] == want[:, 1:2, :, :]
            # and one that straddles the tile boundary is stitched
            Test.@test v[:, 3:6, :, :] == want[:, 3:6, :, :]

            Test.@test_throws ErrorException v[[1, 3], :, :, :]
        end
    end
end

Test.@testset "load_fielddump selects, and matches the lazy read" begin
    mktempdir() do dir
        f = write_fielddump_tiles(dir)
        all_vars = MA.load_fielddump(dir)
        Test.@test sort(collect(keys(all_vars.fields))) == ["n_rain", "thl", "v", "w"]
        Test.@test all_vars.fields["thl"] == f.expected["thl"]

        one = MA.load_fielddump(dir; vars = ["thl"], time_indices = 1:1)
        Test.@test collect(keys(one.fields)) == ["thl"]
        Test.@test size(one.fields["thl"]) == (f.nx, f.ny, f.nz, 1)
        Test.@test one.fields["thl"] == f.expected["thl"][:, :, :, 1:1]
        Test.@test length(one.coords["time"]) == 1

        Test.@test_throws ErrorException MA.load_fielddump(dir; vars = ["nope"])
    end
end

Test.@testset "tile files are opened once and closed" begin
    mktempdir() do dir
        write_fielddump_tiles(dir)
        fd = MA.open_fielddump(dir)
        Test.@test length(fd.handles.open) == fd.tiles
        fd.vars["thl"][:, :, 1, 1]
        Test.@test length(fd.handles.open) == fd.tiles     # no reopening
        MA.close_fielddump(fd)
        Test.@test isempty(fd.handles.open)

        # the do-block closes even when its body throws
        escaped = Ref{Any}(nothing)
        Test.@test_throws ErrorException MA.open_fielddump(dir) do g
            escaped[] = g
            error("boom")
        end
        Test.@test isempty(escaped[].handles.open)
    end
end

Test.@testset "fielddump names and units" begin
    # the twelve SB3 scalars resolve; everything else passes through
    Test.@test MA.fielddump_physical_name("sv001") == "n_rain"
    Test.@test MA.fielddump_physical_name("sv005") == "q_cloud_liquid"
    Test.@test MA.fielddump_physical_name("thl") == "thl"
    Test.@test_throws ErrorException MA.fielddump_physical_name("sv013")

    # a number scalar is per unit mass, whatever the file's `(kg/kg)` says
    Test.@test MA.fielddump_units("sv001", "(kg/kg)") == "kg^-1"
    Test.@test MA.fielddump_units("sv002", "(kg/kg)") == "kg/kg"
    Test.@test MA.fielddump_units("qt", "1e-5kg/kg") == "kg/kg"
    Test.@test MA.fielddump_units("thl", "K") == "K"
end

Test.@testset "a single global file is one tile" begin
    mktempdir() do dir
        f = write_fielddump_tiles(dir; n_tiles = 1, ny_per_tile = 6)
        path = only(filter(endswith(".nc"), readdir(dir; join = true)))
        MA.open_fielddump(path) do fd
            Test.@test fd.tiles == 1
            Test.@test size(fd.vars["thl"]) == (f.nx, f.ny, f.nz, f.nt)
            Test.@test fd.vars["thl"][:, :, :, :] == f.expected["thl"]
        end
    end
end
