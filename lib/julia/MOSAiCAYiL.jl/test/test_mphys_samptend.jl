using MOSAiCAYiL: MOSAiCAYiL as MA
using NCDatasets: NCDatasets as NC
using Test: Test

const COORD_NAMES = ("time", "zt", "zm")

Test.@testset "every mphys and samptend variable reads at default settings" begin
    date = "20200503"
    for (file, path) in
        ((:mphys, MA.mphys_path(date)), (:samptend, MA.samptend_path(date)))
        names, needs_density = NC.NCDataset(path, "r") do ds
            ns = [n for n in keys(ds) if !(n in COORD_NAMES)]
            (ns, count(n -> MA.ρ_power(ds, n; file) != 0, ns))
        end
        Test.@test !isempty(names)
        # neither file carries `rhof`, so these are the ones a self-contained read cannot do
        Test.@test needs_density > 0
        failed = filter(names) do n
            try
                MA.read_variable(n, date; file)
                false
            catch
                true
            end
        end
        Test.@test isempty(failed)
    end
end

Test.@testset "a per-mass number is converted by the day's rhof" begin
    date = "20200503"
    ρ = MA.dales_slab_column(date).rhof
    for (name, file, stored, converted) in (
        ("dn_i_inuc", :mphys, "#/kg/s", "m^-3 s^-1"),
        ("sv007", :profiles, "kg/kg", "m^-3"),
    )
        translated = MA.read_variable(name, date; file)
        untranslated = MA.read_variable(name, date; file, translate_units = false)
        Test.@test translated.units == converted
        Test.@test untranslated.units == stored
        Test.@test translated.data == untranslated.data .* ρ
    end
end

Test.@testset "the open-dataset method takes the density as an argument" begin
    date = "20200503"
    ρ = MA.dales_slab_column(date).rhof
    NC.NCDataset(MA.mphys_path(date), "r") do ds
        Test.@test MA.ρ_power(ds, "dn_i_inuc"; file = :mphys) == 1
        # refuses rather than handing back unconverted values under converted units
        Test.@test_throws ErrorException MA.read_variable(ds, "dn_i_inuc"; file = :mphys)
        Test.@test MA.read_variable(ds, "dn_i_inuc"; file = :mphys, density = ρ).data ==
                   MA.read_variable("dn_i_inuc", date; file = :mphys).data
        Test.@test MA.read_variable(
            ds, "dn_i_inuc"; file = :mphys, translate_units = false,
        ).units == "#/kg/s"
    end
    NC.NCDataset(MA.les_profiles_path(date), "r") do ds
        Test.@test MA.ρ_power(ds, "sv0072r"; file = :profiles) == 2   # a number variance
        Test.@test MA.ρ_power(ds, "thl"; file = :profiles) == 0
    end
end

Test.@testset "mphys, samptend and profiles share one time and height axis" begin
    date = "20200503"
    axes_of(path) = NC.NCDataset(path, "r") do ds
        (
            vec(Array(NC.variable(ds, "time"))),
            vec(Array(ds["zt"])),
            vec(Array(ds["zm"])),
        )
    end
    reference = axes_of(MA.les_profiles_path(date))
    for path in (MA.mphys_path(date), MA.samptend_path(date))
        Test.@test axes_of(path) == reference
    end
end

# Autoconversion is the one process the archive records twice through different code paths:
# `mphysprofiles.001.nc` writes the cloud-side tendency from `modbulkmicrostat3`, and
# `profiles.001.nc` writes the rain-side one through BULKMICROSTAT3 at genstat's shared
# counter. Comparing them exercises the record alignment, the two time axes, the slab-mean
# convention and the sign table, with no ported physics involved.
Test.@testset "autoconversion agrees across its two archive paths" begin
    date = "20200503"
    cloud = MA.read_variable("dq_c_au", date; file = :mphys, translate_units = false)
    rain = MA.read_variable("qrpauto", date; file = :profiles, translate_units = false)

    # the BULKMICROSTAT3 variable is displaced by one record and `read_variable` undoes it,
    # leaving one sample fewer
    Test.@test length(rain.time) == length(cloud.time) - 1
    Test.@test first(rain.time) > first(cloud.time)

    shared = intersect(Float64.(cloud.time), Float64.(rain.time))
    Test.@test length(shared) == length(rain.time)
    at(v, times) = [findfirst(==(t), Float64.(times)) for t in shared]
    a = Float64.(cloud.data[:, at(cloud, cloud.time)])
    b = Float64.(rain.data[:, at(rain, rain.time)])

    active = abs.(b) .> 1.0e-20
    Test.@test count(active) > 500          # the day must actually autoconvert somewhere

    # the cloud loses exactly what the rain gains, to the bit
    Test.@test all(a[active] ./ b[active] .== -1.0)
    Test.@test maximum(abs, a[active] .+ b[active]) == 0.0

    # the number tendencies are related by the scheme's own factor of two — autoconversion
    # removes two cloud droplets per rain drop (`modbulkmicro3.f90:2696-2698`) — and by the
    # density, `dn_c_au` being per unit mass and `npauto` per unit volume
    cloud_n = MA.read_variable("dn_c_au", date; file = :mphys, translate_units = false)
    rain_n = MA.read_variable("npauto", date; file = :profiles, translate_units = false)
    column = MA.dales_slab_column(date, Float64)
    ρ = column.rhof[:, at(column, column.time)]
    an = Float64.(cloud_n.data[:, at(cloud_n, cloud_n.time)])
    bn = Float64.(rain_n.data[:, at(rain_n, rain_n.time)])

    active_n = abs.(bn) .> 1.0e-20
    Test.@test count(active_n) > 500
    Test.@test (an .* ρ)[active_n] ≈ (-2 .* bn)[active_n] rtol = 1.0e-3

    # the two paths carry different units, which is why the density belongs in the check:
    # the mphys number is per unit mass, and the BULKMICROSTAT3 one per unit volume
    Test.@test cloud_n.units == "#/kg/s"
    Test.@test rain_n.units == "m^-3 s^-1"
end
