"""
    MOSAiCAYiL

Facts and archive access for Schnierstein et al. (2024) MOSAiC "A Year in LES"
(AYiL): 190 Arctic days of DALES large-eddy simulations.

This package owns the *data* and *facts* of the ensemble — the catalog, the DALES
constants and grid, the variable translation, and the readers. Archive files come from
the lazy Zenodo artifact, or from an explicit `root` keyword.

Extensions add methods on the types defined here: `using ClimaAtmos` for the
single-column forcing, setup and diagnostics; `using Distributed` or `using OhMyThreads`
for sweeping a function over the 190 days.
"""
module MOSAiCAYiL

using Artifacts: Artifacts
using Dates: Dates
using LazyArtifacts: LazyArtifacts
using NCDatasets: NCDatasets as NC

include("cases.jl")
using .Cases

include("dales.jl")
include("constants.jl")
include("configuration.jl")
include("lacz_gamma.jl")
include("microphysics.jl")
include("sb3_derived.jl")
include("microphysics_processes.jl")
include("thermodynamics.jl")
include("grid.jl")
include("anelastic.jl")
include("nudge.jl")
include("surface.jl")
include("monin_obukhov.jl")
include("paths.jl")
include("generated/day_scalars.jl")
include("day_scalars.jl")
include("generated/day_metadata.jl")
include("generated/cloud_tops.jl")
include("generated/cloud_liquid_optics.jl")
include("radiation_tables.jl")
include("day_metadata.jl")
include("ayil_info.jl")
include("ice_filters.jl")
include("readers.jl")
include("variable_translations.jl")
include("slab_column.jl")
include("fielddump.jl")
include("fielddump_thermodynamics.jl")
include("diagnostics.jl")
include("io.jl")

# Distributed / OhMyThreads extension bindings
include("ext/ParallelExt_bindings.jl")

# Zarr extension bindings
include("ext/ZarrExt_bindings.jl")

# ClimaAtmos extension bindings (also uses Thermodynamics.jl instead of default backend)
include("ext/ClimaAtmosExt_bindings.jl")

end # module
