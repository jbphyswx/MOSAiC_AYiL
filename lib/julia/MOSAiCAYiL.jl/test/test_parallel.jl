using MOSAiCAYiL: MOSAiCAYiL as MA
using Test: Test

using OhMyThreads: OhMyThreads
using Distributed: Distributed

Test.@testset "collection normalization" begin
    # `MOSAiCAYiL_dates` is a Tuple and `keys(...)` a KeySet; `OhMyThreads.tmap` takes an
    # `AbstractArray`, so the catalog cannot be handed to it unmaterialized.
    Test.@test MA._parallel_items(MA.MOSAiCAYiL_dates) isa Vector
    Test.@test length(MA._parallel_items(MA.MOSAiCAYiL_dates)) == MA.n_cases()
    Test.@test MA._parallel_items(keys(MA.BEST_SIMULATION_TOP_F)) isa Vector{String}
    Test.@test MA._parallel_items(d for d in 1:3) == [1, 2, 3]
    v = [1, 2, 3]
    Test.@test MA._parallel_items(v) === v          # an array is passed through, not copied
end

Test.@testset "OhMyThreads extension" begin
    Test.@test Base.get_extension(MA, :MOSAiCAYiLOhMyThreadsExt) !== nothing

    # the wrapper's reason to exist: the raw function rejects the catalog's own container
    Test.@test_throws MethodError OhMyThreads.tmap(identity, MA.MOSAiCAYiL_dates)
    Test.@test MA.tmap(MA.date_string, MA.MOSAiCAYiL_dates) ==
               map(MA.date_string, collect(MA.MOSAiCAYiL_dates))

    Test.@test MA.tmap(identity, keys(MA.BEST_SIMULATION_TOP_F)) ==
               collect(keys(MA.BEST_SIMULATION_TOP_F))
    Test.@test MA.tmap(x -> x^2, Float64, 1:8) == Float64[x^2 for x in 1:8]

    counter = Threads.Atomic{Int}(0)
    Test.@test MA.tforeach(_ -> Threads.atomic_add!(counter, 1), 1:16) === nothing
    Test.@test counter[] == 16

    Test.@test MA.tmapreduce(x -> x^2, +, 1:100) == sum(x -> x^2, 1:100)
    Test.@test MA.treduce(+, 1:100) == sum(1:100)

    out = zeros(Int, 8)
    Test.@test MA.tmap!(x -> 2x, out, 1:8) === out
    Test.@test out == collect(2:2:16)

    Test.@test MA.tcollect(x^2 for x in 1:8) == [x^2 for x in 1:8]

    # scheduler keywords reach OhMyThreads
    Test.@test MA.tmap(identity, 1:8; scheduler = :static) == collect(1:8)
    Test.@test MA.tmap(identity, 1:8; scheduler = :serial) == collect(1:8)
end

Test.@testset "Distributed extension" begin
    Test.@test Base.get_extension(MA, :MOSAiCAYiLDistributedExt) !== nothing

    dates = collect(MA.MOSAiCAYiL_dates)
    # with no workers `pmap` runs locally, so ordering and normalization are still testable
    Test.@test MA.pmap(MA.date_string, MA.MOSAiCAYiL_dates) ==
               map(MA.date_string, dates)
    Test.@test MA.pmap(identity, keys(MA.BEST_SIMULATION_TOP_F)) ==
               collect(keys(MA.BEST_SIMULATION_TOP_F))

    Test.@test MA.pforeach(identity, 1:8) === nothing
    Test.@test MA.pmapreduce(x -> x^2, +, 1:100) == sum(x -> x^2, 1:100)
    Test.@test MA.pmapreduce(identity, +, Int[]; init = 0) == 0

    # a failing item does not abort the sweep when `on_error` is given
    bad(x) = x == 3 ? error("day 3") : x
    Test.@test_throws Exception MA.pmap(bad, 1:5)
    # `==` on arrays holding `missing` is `missing`, never a Bool
    Test.@test isequal(
        MA.pmap(bad, 1:5; on_error = _ -> missing), [1, 2, missing, 4, 5],
    )

    Test.@test_throws ErrorException MA.addprocs(0)
end

Test.@testset "a fielddump sweep runs on workers" begin
    include("fielddump_fixture.jl")
    mktempdir() do root
        dirs = [joinpath(root, "run$i") for i in 1:3]
        expected = map(dirs) do d
            mkpath(d)
            write_fielddump_tiles(d; nx = 6, ny_per_tile = 3, n_tiles = 2, nz = 2, nt = 2)
        end

        ids = MA.addprocs(2)
        try
            got = MA.pmap(MA.load_fielddump, dirs)
            Test.@test length(got) == length(dirs)
            for i in eachindex(dirs)
                Test.@test got[i].fields["thl"] == expected[i].expected["thl"]
                Test.@test got[i].fields["v"] == expected[i].expected["v"]
                Test.@test got[i].dims["v"] == ("xt", "ym", "zt", "time")
            end
        finally
            Distributed.rmprocs(ids)
        end
    end
end

if MA.data_available()
    Test.@testset "sweeps accept a mapper" begin
        days = collect(MA.MOSAiCAYiL_dates)[1:4]
        serial = MA.best_z_maxs(days)
        Test.@test serial == MA.best_z_maxs(days; mapper = MA.tmap)
        Test.@test serial == MA.best_z_maxs(days; mapper = MA.pmap)
    end
else
    @info "Skipping mapper sweep tests: the lazy artifact is not installed."
end
