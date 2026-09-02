# Verifies MOSAiCAYiLClimaAtmosExt. Not part of the default `test/runtests.jl`.
#
#   julia --project=test/environments/clima test/environments/clima/clima_ext.jl
#
# Does not call `solve_atmos!`.

using Test: Test
using ClimaAtmos: ClimaAtmos
using MOSAiCAYiL: MOSAiCAYiL as MA

Test.@testset "MOSAiCAYiLClimaAtmosExt (ClimaAtmos $(MA.climaatmos_pkg_version()))" begin
    Test.@test Base.get_extension(MA, :MOSAiCAYiLClimaAtmosExt) !== nothing
    Test.@test MA.data_available()

    FT = Float64
    c = MA.case("20200503")
    fd = MA.testbed_forcing(c)

    Test.@testset "params" begin
        params = MA.ClimaAtmos_MOSAiCAYiL_params(FT, c)
        th = ClimaAtmos.Parameters.thermodynamics_params(params)
        TP = ClimaAtmos.TD.Parameters
        Test.@test TP.R_d(th) == 287.04
        Test.@test TP.R_d(th) == MA.DALES_CONSTANTS.R_d
        Test.@test TP.cp_d(th) == MA.DALES_CONSTANTS.cp_d
        Test.@test TP.LH_v0(th) == MA.DALES_CONSTANTS.L_v
    end

    Test.@testset "forcing cache is finite" begin
        forcing = MA.ClimaAtmosMOSAiCAYiLForcing(FT, c; forcing = fd)
        Test.@test forcing.inv_τ ≈ 1 / 10800
        Test.@test all(iszero, forcing.dTdt_hadv)
        Test.@test all(iszero, forcing.dqtdt_hadv)
        Test.@test !all(iszero, forcing.dudt_hadv)
        Test.@test_throws ErrorException MA.ClimaAtmosMOSAiCAYiLForcing(
            FT,
            c;
            forcing = fd,
            nudging = (; timescale = 10800.0, ramp_depth = 300.0, z_min = 500.0),
        )

        faces = MA.coarsen_faces_to_dz_min(MA.LES_FACES, 50)
        grid = MA.mosaic_grid(FT; faces)
        sp = ClimaAtmos.get_spaces(grid)
        coords = ClimaAtmos.CC.Fields.coordinate_field(sp.center_space)
        Y = (; c = map(_ -> (; ρ = FT(1)), coords))
        params = MA.ClimaAtmos_MOSAiCAYiL_params(FT, c)
        cache = ClimaAtmos.external_forcing_cache(Y, forcing, params, nothing)
        for k in keys(cache)
            Test.@test all(isfinite, parent(cache[k]))
        end
        Test.@test hasmethod(
            ClimaAtmos.external_forcing_tendency!,
            Tuple{Any, Any, Any, Any, typeof(forcing)},
        )
    end

    Test.@testset "setup condensate split" for date in ("20200503", "20200219")
        day = MA.case(date)
        forcing_data = MA.testbed_forcing(day)
        faces = MA.coarsen_faces_to_dz_min(MA.LES_FACES, 50)
        grid = MA.mosaic_grid(FT; faces)
        z = MA.mosaic_z(grid)
        params = MA.ClimaAtmos_MOSAiCAYiL_params(FT, day)
        setup = MA.ClimaAtmosMOSAiCAYiLSetup(FT, day; forcing_data)
        lg = ClimaAtmos.CC.Fields.local_geometry_field(
            ClimaAtmos.get_spaces(grid).center_space,
        )
        states = [
            ClimaAtmos.Setups.center_initial_condition(setup, lg[k], params) for
            k in 1:length(z)
        ]
        q_liq = [s.q_liq for s in states]
        q_ice = [s.q_ice for s in states]
        Test.@test all(>=(0), q_liq)
        Test.@test all(>=(0), q_ice)
        thermo = ClimaAtmos.Parameters.thermodynamics_params(params)
        for k in eachindex(z)
            q_sat_liq = ClimaAtmos.TD.q_vap_saturation(
                thermo,
                states[k].T,
                states[k].ρ,
                ClimaAtmos.TD.Liquid(),
            )
            Test.@test states[k].q_liq ≈
                       max(0.0, (states[k].q_tot - states[k].q_ice) - q_sat_liq)
        end
        Test.@test ClimaAtmos.Setups.external_forcing(setup, FT) isa
                   typeof(setup.forcing)
        Test.@test ClimaAtmos.Setups.insolation_model(setup) === setup.insolation
        # default density is scm_in_air_density interpolated onto the model levels
        z_scm, ρ_scm = MA.scm_in_air_density(forcing_data)
        spl = ClimaAtmos.Intp.extrapolate(
            ClimaAtmos.Intp.interpolate(
                (collect(FT, z_scm),),
                collect(FT, ρ_scm),
                ClimaAtmos.Intp.Gridded(ClimaAtmos.Intp.Linear()),
            ),
            ClimaAtmos.Intp.Flat(),
        )
        Test.@test states[1].ρ ≈ spl(z[1]) rtol = 1.0e-5
        Test.@test states[end].ρ ≈ spl(z[end]) rtol = 1.0e-5
        if date == "20200503"
            Test.@test count(>(1.0e-9), q_liq) > 0
            Test.@test all(iszero, q_ice)
        else
            Test.@test count(>(1.0e-9), q_ice) > 0
        end
    end

    Test.@testset "polar-night insolation" begin
        may = MA.MOSAiCInsolation(FT, MA.case("20200503"))
        Test.@test may.cos_zenith > 0
        Test.@test may.toa_flux > 1000
        december = MA.MOSAiCInsolation(FT, MA.case("20191219"))
        Test.@test december.toa_flux == 0
        Test.@test december.cos_zenith == eps(FT)
    end

    Test.@testset "forcing NetCDF round-trip into ClimaAtmos type" begin
        mktempdir() do dir
            path = MA.write_forcing_file(joinpath(dir, "forcing.nc"), c)
            back = MA.read_forcing_file(path)
            a = MA.ClimaAtmosMOSAiCAYiLForcing(FT, c; forcing = fd)
            b = MA.ClimaAtmosMOSAiCAYiLForcing(
                FT,
                c;
                forcing = back,
                nudging = back.nudging,
            )
            for f in fieldnames(typeof(a))
                Test.@test getfield(a, f) == getfield(b, f)
            end
        end
    end

    Test.@testset "archive → ClimaAtmos short names" begin
        ext = Base.get_extension(MA, :MOSAiCAYiLClimaAtmosExt)
        qt = [1.0e-3, 2.0e-3, 1.5e-3]
        sv005 = [0.0, 1.0e-5, 0.0]
        sv008 = [0.0, 0.0, 2.0e-6]
        sv002 = zeros(3)
        sv010 = zeros(3)
        sv012 = zeros(3)
        store = Dict(
            "sv005" => sv005,
            "sv008" => sv008,
            "sv002" => sv002,
            "sv010" => sv010,
            "sv012" => sv012,
            "qt" => qt,
        )
        read = name -> store[name]
        Test.@test ext.CLIMAATMOS_FROM_DALES["clw"].f(read) == sv005
        Test.@test ext.CLIMAATMOS_FROM_DALES["cli"].f(read) == sv008
        hus = ext.CLIMAATMOS_FROM_DALES["hus"].f(read)
        Test.@test hus == qt .+ sv008 .+ sv002 .+ sv010 .+ sv012
        Test.@test "clw" in MA.climaatmos_translated_names()
    end
end
