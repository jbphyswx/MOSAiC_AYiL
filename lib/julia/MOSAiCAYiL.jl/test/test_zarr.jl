using MOSAiCAYiL: MOSAiCAYiL as MA
using Test: Test
using Zarr: Zarr

include("fielddump_fixture.jl")

Test.@testset "a fielddump written to Zarr reads back unchanged" begin
    mktempdir() do dir
        f = write_fielddump_tiles(dir)
        store = joinpath(dir, "out.zarr")
        chunks = (f.nx, 2, f.nz, f.nt)
        MA.open_fielddump(dir) do fd
            Test.@test MA.write_zarr(store, fd; chunks) == store
        end
        Test.@test isdir(store)

        z = MA.open_zarr(store)
        Test.@test sort(collect(keys(z.vars))) ==
                   ["n_rain", "ql", "qt", "thl", "v", "w"]

        # the stagger survives the round trip through `dimension_names`
        Test.@test z.dims["thl"] == ("xt", "yt", "zt", "time")
        Test.@test z.dims["v"] == ("xt", "ym", "zt", "time")
        Test.@test z.dims["w"] == ("xt", "yt", "zm", "time")

        Test.@test size(z.vars["v"]) == (f.nx, f.ny, f.nz, f.nt)
        Test.@test z.vars["thl"][:, :, :, :] == f.expected["thl"]
        Test.@test z.vars["v"][:, :, :, :] == f.expected["v"]
        Test.@test z.vars["w"][:, :, :, :] == f.expected["w"]
        Test.@test z.vars["n_rain"][:, :, :, :] == f.expected["sv001"]

        # the corrected units are stored, not the archive's `(kg/kg)`
        Test.@test z.units["n_rain"] == "kg^-1"
        Test.@test z.units["thl"] == "K"
        Test.@test z.variable_attrs["n_rain"]["dales_fielddump_name"] == "sv001"

        Test.@test z.attrs["n_tiles"] == f.n_tiles
        for axis in ("xt", "xm", "yt", "ym", "zt", "zm", "time")
            Test.@test haskey(z.coords, axis)
        end
        Test.@test length(z.coords["yt"]) == f.ny

        loaded = MA.load_zarr(store; vars = ["thl"], time_indices = 1:1)
        Test.@test collect(keys(loaded.fields)) == ["thl"]
        Test.@test loaded.fields["thl"] == f.expected["thl"][:, :, :, 1:1]
        Test.@test length(loaded.coords["time"]) == 1
    end
end

Test.@testset "the store is Zarr v3 with usable consolidated metadata" begin
    mktempdir() do dir
        f = write_fielddump_tiles(dir)
        store = joinpath(dir, "out.zarr")
        MA.open_fielddump(dir) do fd
            MA.write_zarr(store, fd; chunks = (f.nx, 2, f.nz, f.nt), vars = ["thl"])
        end

        root = Zarr.JSON.parse(read(joinpath(store, "zarr.json"), String))
        Test.@test root["zarr_format"] == 3
        Test.@test root["node_type"] == "group"

        # every array is listed, so a reader never has to walk the directory
        members = root["consolidated_metadata"]["metadata"]
        Test.@test root["consolidated_metadata"]["kind"] == "inline"
        Test.@test issubset(["thl", "xt", "yt", "zt", "time"], keys(members))
        Test.@test members["thl"]["shape"] == [f.nt, f.nz, f.ny, f.nx]

        # `dimension_names` is written in the store's own axis order
        Test.@test members["thl"]["dimension_names"] == ["time", "zt", "yt", "xt"]

        # reading with and without the consolidated block agrees
        a = MA.open_zarr(store; consolidated = true)
        b = MA.open_zarr(store; consolidated = false)
        Test.@test a.dims["thl"] == b.dims["thl"]
        Test.@test a.units["thl"] == b.units["thl"]
        Test.@test a.attrs["n_tiles"] == b.attrs["n_tiles"]
        Test.@test a.vars["thl"][:, :, :, :] == b.vars["thl"][:, :, :, :]
    end
end

Test.@testset "write_zarr refuses to guess" begin
    mktempdir() do dir
        f = write_fielddump_tiles(dir)
        store = joinpath(dir, "out.zarr")
        MA.open_fielddump(dir) do fd
            # a chunk shape of the wrong rank names the axes it should have had,
            # and leaves nothing behind to block the next attempt
            Test.@test_throws ErrorException MA.write_zarr(store, fd; chunks = (2, 2))
            Test.@test !ispath(store)
            Test.@test_throws ErrorException MA.write_zarr(
                store, fd; chunks = (f.nx, 2, f.nz, f.nt), vars = ["nope"],
            )
            Test.@test !ispath(store)

            MA.write_zarr(store, fd; chunks = (f.nx, 2, f.nz, f.nt), vars = ["thl"])
            # and an existing path is never written over
            Test.@test_throws ErrorException MA.write_zarr(
                store, fd; chunks = (f.nx, 2, f.nz, f.nt),
            )
        end
    end
end
