"""
    MOSAiCAYiL

Facts, archive access, and ClimaAtmos methods for Schnierstein et al. (2024)
MOSAiC "A Year in LES" (AYiL): 190 Arctic days of DALES large-eddy simulations.

This package owns the *data* and *facts* of the ensemble, plus ClimaAtmos methods
on types it defines. It does not assemble an `AtmosModel` / `AtmosSimulation`.

Load the ClimaAtmos extension with `using ClimaAtmos`. Archive files come from
the lazy Zenodo artifact, or from an explicit `root` keyword.
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
include("grid.jl")
include("nudge.jl")
include("surface.jl")
include("paths.jl")
include("generated/day_scalars.jl")
include("day_scalars.jl")
include("ayil_info.jl")
include("ice_filters.jl")
include("readers.jl")
include("variable_translations.jl")
include("io.jl")

# Optional weak-dep APIs (methods added when extensions load)
function ayil_tmap end
function ayil_pmap end

include("ext/ClimaAtmosExt_bindings.jl")

end # module
