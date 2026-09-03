using Test: Test
using MOSAiCAYiL: MOSAiCAYiL

# Aqua first, before weak-dep `using`s load extensions.
include("test_aqua.jl")
include("test_catalog.jl")
include("test_constants.jl")
include("test_microphysics.jl")
include("test_sb3_derived.jl")
include("test_microphysics_processes.jl")
include("test_grid_provenance.jl")
include("test_configuration.jl")
include("test_monin_obukhov.jl")
include("test_radiation_tables.jl")
include("test_thermodynamics.jl")
include("test_nudge.jl")
include("test_translations.jl")
include("test_day_tables.jl")
include("test_fielddump.jl")
include("test_fielddump_thermodynamics.jl")

if MOSAiCAYiL.data_available()
    include("test_data.jl")
    include("test_slab_column.jl")
    include("test_mphys_samptend.jl")
    include("test_namelist.jl")
    include("test_anelastic.jl")
    include("test_ckd.jl")
    include("test_diagnostics.jl")
    include("test_surface_layer.jl")
else
    @info "Skipping archive tests: the lazy artifact is not installed."
end

include("test_parallel.jl")
include("test_zarr.jl")
