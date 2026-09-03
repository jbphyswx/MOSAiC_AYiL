using MOSAiCAYiL: MOSAiCAYiL as MA
using Test: Test

Test.@testset "the namelist keeps its groups" begin
    nl = MA.namelist("20200503")
    Test.@test length(nl) == 21
    Test.@test sum(length, values(nl)) == 99
    Test.@test length(unique(k for group in values(nl) for k in keys(group))) == 86

    # group identity is load-bearing: one key, nine groups, two values
    dtav = MA.namelist_groups_with(nl, :dtav)
    Test.@test length(dtav) == 9
    Test.@test length(unique(nl[g][:dtav] for g in dtav)) == 2
    timeav = MA.namelist_groups_with(nl, :timeav)
    Test.@test length(timeav) == 5
    Test.@test length(unique(nl[g][:timeav] for g in timeav)) == 2
    Test.@test isempty(MA.namelist_groups_with(nl, :not_a_key))
end

Test.@testset "the constants are checkable against the namelist" begin
    nl = MA.namelist("20200503")
    Test.@test MA.namelist_value(Float64, nl, :namfielddump, :dtav) == MA.FIELDDUMP_DT_S
    Test.@test MA.namelist_value(Int, nl, :namfielddump, :khigh) == MA.FIELDDUMP_NZ
    Test.@test MA.namelist_value(Float64, nl, :namgenstat, :timeav) == MA.PROFILES_DT_S
    Test.@test MA.namelist_value(Float64, nl, :namtimestat, :dtav) == MA.TMSER_DT_S
    Test.@test MA.namelist_value(Float64, nl, :run, :runtime) == MA.PUBLISHED_RUNTIME_S

    Test.@test MA.namelist_value(Bool, nl, :namsurface, :larcticstab) ===
               MA.NAMELIST.larcticstab
    Test.@test MA.namelist_value(Bool, nl, :namsurface, :lmostlocal) ===
               MA.NAMELIST.lmostlocal
    Test.@test MA.namelist_value(Int, nl, :nammicrophysics, :imicro) == MA.NAMELIST.imicro
    Test.@test MA.namelist_value(Int, nl, :run, :nsv) == MA.NAMELIST.nsv
    Test.@test MA.namelist_value(Float64, nl, :nambulk3, :nc0) == MA.NAMELIST.nc0
    Test.@test MA.namelist_value(Float64, nl, :namtestbed, :tb_taunudge) ==
               MA.NAMELIST.tb_taunudge
    Test.@test MA.namelist_value(String, nl, :run, :startfile) ==
               "initd002h00mx000y000.001"
end

Test.@testset "an ambiguous key names its groups" begin
    nl = MA.namelist("20200503")
    err = try
        MA.namelist_value(nl, :dtav)
        ""
    catch e
        sprint(showerror, e)
    end
    Test.@test occursin("namfielddump", err)
    Test.@test occursin("namgenstat", err)
    Test.@test_throws ErrorException MA.namelist_value(nl, :not_a_key)
    Test.@test_throws ErrorException MA.namelist_value(nl, :not_a_group, :dtav)
    Test.@test_throws ErrorException MA.namelist_value(nl, :namfielddump, :not_a_key)

    # unambiguous keys need no group
    Test.@test MA.namelist_value(Int, nl, :imicro) == MA.NAMELIST.imicro
end

Test.@testset "placeholders refuse to be read as physics" begin
    nl = MA.namelist("20200503")
    c = MA.case("20200503")
    Test.@test length(MA.NAMELIST_PLACEHOLDERS) == 8
    for accessor in values(MA.NAMELIST_PLACEHOLDERS)
        Test.@test isdefined(MA, accessor)
    end
    for (group, key) in keys(MA.NAMELIST_PLACEHOLDERS)
        Test.@test_throws ErrorException MA.namelist_value(nl, group, key)
        Test.@test MA.namelist_placeholder(nl, group, key) isa String
    end
    Test.@test_throws ErrorException MA.namelist_placeholder(nl, :run, :runtime)

    # the two the audit found were returning a silently wrong number
    Test.@test parse(Float64, MA.namelist_placeholder(nl, :physics, :ps)) !=
               Float64(MA.ps(c))
    Test.@test parse(Float64, MA.namelist_placeholder(nl, :physics, :thls)) !=
               Float64(MA.surface_pottemp(c))

    # `thls` is a potential temperature, which is why `t_skin` is not its accessor
    Test.@test MA.surface_pottemp(c) != MA.t_skin(c)
    Test.@test MA.surface_pottemp(c) ≈
               MA.t_skin(c) / MA.exner(MA.DefaultThermodynamicsBackend(), Float64(MA.ps(c)))

    Test.@test MA.namelist_latitude("20200503") != MA.latitude(c)
end

Test.@testset "the configuration record agrees with the namelist it came from" begin
    nl = MA.namelist("20200503")
    Test.@test MA.namelist_value(Int, nl, :dynamics, :iadv_mom) == MA.ADVECTION.iadv_mom
    Test.@test MA.namelist_value(Int, nl, :dynamics, :iadv_thl) == MA.ADVECTION.iadv_thl
    Test.@test MA.namelist_value(Int, nl, :dynamics, :iadv_sv) ==
               MA.ADVECTION.iadv_sv_namelist
    Test.@test MA.namelist_value(Int, nl, :physics, :iradiation) == MA.RADIATION.iradiation
    Test.@test MA.namelist_value(Float64, nl, :namradiation, :emissurf) ==
               MA.RADIATION.emissurf
    Test.@test MA.namelist_value(Int, nl, :namsurface, :isurf) == MA.SURFACE_LAYER.isurf
    Test.@test MA.namelist_value(Bool, nl, :namsurface, :lmostlocal) ===
               MA.SURFACE_LAYER.lmostlocal
    Test.@test MA.namelist_value(Bool, nl, :namsurface, :larcticstab) ===
               MA.SURFACE_LAYER.larcticstab
    Test.@test MA.namelist_value(Int, nl, :run, :irandom) == MA.PERTURBATIONS.irandom
    Test.@test MA.namelist_value(Float64, nl, :run, :randthl) == MA.PERTURBATIONS.randthl
    Test.@test MA.namelist_value(Float64, nl, :run, :randqt) == MA.PERTURBATIONS.randqt
    Test.@test MA.namelist_value(Bool, nl, :physics, :lcoriol) === MA.CORIOLIS.lcoriol
    Test.@test MA.namelist_value(Bool, nl, :dynamics, :llsadv) === MA.ADVECTION.llsadv
    Test.@test MA.namelist_value(Float64, nl, :dynamics, :cu) == MA.ADVECTION.cu

    # the sponge is in no namelist group, which is why it is recorded in the package
    Test.@test isempty(MA.namelist_groups_with(nl, :ksp))
    Test.@test isempty(MA.namelist_groups_with(nl, :rnu0))
    # and there is no &NAMSUBGRID group at all, so every subgrid input is a Fortran default
    Test.@test !haskey(nl, :namsubgrid)
end

Test.@testset "xday is the only per-day key" begin
    reference = MA.namelist(MA.date_string(first(MA.MOSAiCAYiL_dates)))
    numeric(s) = tryparse(Float64, replace(s, "d" => "e", "D" => "e"))
    disagreeing = String[]
    xday_mismatch = String[]
    for d in MA.MOSAiCAYiL_dates
        ymd = MA.date_string(d)
        nl = MA.namelist(ymd)
        MA.namelist_value(Int, nl, :domain, :xday) == MA.xday(MA.case(ymd)) ||
            push!(xday_mismatch, ymd)
        for (group, entries) in nl, (key, value) in entries
            (group, key) == (:domain, :xday) && continue
            other = get(get(reference, group, Dict{Symbol, String}()), key, nothing)
            if isnothing(other)
                push!(disagreeing, "$ymd &$group $key absent from the reference day")
                continue
            end
            # typed, so "10800" and "10800.0" are the same value
            a, b = numeric(value), numeric(other)
            same = isnothing(a) || isnothing(b) ? value == other : a == b
            same || push!(disagreeing, "$ymd &$group $key: $value vs $other")
        end
    end
    Test.@test isempty(disagreeing)
    Test.@test isempty(xday_mismatch)
end
