"""
    read_the_archive.jl

What the package reads, end to end.

    julia --project=examples examples/read_the_archive.jl

Facts come from the committed tables with no I/O; the archive parts need the lazy artifact,
and are skipped when it is not installed.
"""

using MOSAiCAYiL: MOSAiCAYiL as MA

function facts_without_reading_anything()
    c = MA.case("20200503")
    println("-- ", MA.date_string(c), ", from the committed tables (no files opened) --")
    println("  latitude              ", MA.latitude(c), " degrees_north")
    println("  sea ice fraction      ", MA.sea_ice_frct(c))
    println("  skin temperature      ", MA.t_skin(c), " K")
    println("  CCN                   ", MA.n_ccn(c), " m^-3")
    println("  scm_in levels         ", MA.scm_in_levels(c))
    println("  Fletcher INP N, b     ", MA.inp_fletcher_n(c), ", ", MA.inp_fletcher_b(c))
    println("  days in the catalog   ", MA.n_cases())
    return nothing
end

function one_variable_from_each_product()
    println("\n-- one variable from each archive product --")
    for (product, raw) in (
        (:scm_in, "t_local"), (:profiles, "sv008"), (:tmser, "lwp_bar"),
        (:mphys, "ice_rate"), (:samptend, "thltendmicroall"),
    )
        f = MA.read_variable(raw, "20200503"; file = product)
        println(
            "  ", rpad(String(product), 9), rpad(raw, 18), rpad(f.description, 34),
            rpad(f.units, 10), "size ", size(f.data),
        )
    end
    return nothing
end

function the_forcing_a_day_was_run_with()
    println("\n-- testbed forcing, on an ascending height axis --")
    f = MA.testbed_forcing("20200503")
    println("  levels     ", length(f.z), "  from ", round(first(f.z), digits = 1),
            " m to ", round(last(f.z), digits = 1), " m")
    println("  surface    ps = ", f.surface.ps, " Pa, t_skin = ", f.surface.t_skin, " K")
    println("  q_tot      ", extrema(f.hus), " kg/kg")
    z, ρ = MA.scm_in_air_density(f)
    println("  density    ", round(first(ρ), digits = 3), " kg/m^3 at ",
            round(first(z), digits = 1), " m")
    return nothing
end

"""
    the_3d_fields(run_dir)

Open a fielddump without reading it, slice it, and write it to Zarr.

`run_dir` holds `fielddump.III.JJJ.NNN.nc` tiles, or is a single assembled file. The
fields are not in the artifact, so this takes a path of your own. `using Zarr` first for
the last part.
"""
function the_3d_fields(run_dir::AbstractString, zarr_dest = nothing)
    MA.open_fielddump(run_dir) do fd
        println("\n-- ", run_dir, " --")
        println("  tiles      ", fd.tiles)
        println("  variables  ", join(sort(collect(keys(fd.vars))), ", "))
        for name in sort(collect(keys(fd.vars)))
            println("    ", rpad(name, 14), rpad(string(size(fd.vars[name])), 22),
                    rpad(string(fd.dims[name]), 32), fd.units[name])
        end

        # nothing above read a field; these read only the tiles they touch
        v = fd.vars["thl"]
        println("  one level  ", size(v[:, :, 1, 1]))
        println("  one column ", size(v[1, 1, :, :]))

        if zarr_dest !== nothing
            nx, ny, nz, nt = size(v)
            MA.write_zarr(zarr_dest, fd; chunks = (nx, cld(ny, 4), nz, nt))
            z = MA.open_zarr(zarr_dest)
            println("  wrote      ", zarr_dest, " with ", length(z.vars), " variables")
        end
    end
    return nothing
end

function main()
    facts_without_reading_anything()
    if MA.data_available()
        one_variable_from_each_product()
        the_forcing_a_day_was_run_with()
    else
        println("\n(skipping the archive: the lazy artifact is not installed)")
    end
    println("\nFor the 3D fields, call `the_3d_fields(\"/path/to/a/run\")`.")
    return nothing
end

main()
