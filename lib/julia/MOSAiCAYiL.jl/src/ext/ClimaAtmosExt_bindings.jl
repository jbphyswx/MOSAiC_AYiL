# --- Optional weak-dep API (methods added when MOSAiCAYiLClimaAtmosExt loads) ---

"""The `ClimaAtmos` version the extension is running against."""
function climaatmos_pkg_version end

"""
    ClimaAtmosMOSAiCAYiLForcing(FT, case; forcing, nudging, z_inv_min, z_inv_max, q_tot_threshold)

Large-scale forcing for one AYiL day: relaxation of temperature, total water and horizontal
wind toward the ERA5 profiles above a diagnosed inversion, horizontal advection, and
subsidence.

Only DALES's diagnosed-inversion mode is implemented; a positive `nudging.z_min` errors.
"""
function ClimaAtmosMOSAiCAYiLForcing end

"""
    ClimaAtmosMOSAiCAYiLSetup(FT, case; forcing_data, density, tke, insolation, T_sfc, z0, albedo)

Initial state of one AYiL day, with the forcing, insolation and surface values a
`ClimaAtmos.AtmosSimulation` needs.

`density` defaults to [`scm_in_air_density`](@ref); pass [`les_density`](@ref) for the
archive's `rhof` at t = 300 s.
"""
function ClimaAtmosMOSAiCAYiLSetup end

"""
    ClimaAtmos_MOSAiCAYiL_toml_overrides([case]; ccn, params)

ClimaParams override dict holding DALES's constants, plus the day's CCN number when a case
is given. `params` is a further dict that wins.
"""
function ClimaAtmos_MOSAiCAYiL_toml_overrides end

"""
    ClimaAtmos_MOSAiCAYiL_params(FT, case; microphysics_model, kwargs...)

`ClimaAtmosParameters` built on [`ClimaAtmos_MOSAiCAYiL_toml_overrides`](@ref), so the
thermodynamics runs on DALES's own constants.
"""
function ClimaAtmos_MOSAiCAYiL_params end

"""Callback keywords for an AYiL run: radiation every 10 minutes, as the archive did."""
function ClimaAtmos_MOSAiCAYiL_callback_kwargs end

"""
    ClimaAtmos_MOSAiCAYiL_scm_coriolis(FT, case; params, forcing, latitude, omega)

ClimaAtmos `scm_coriolis` for one day: the geostrophic wind from `scm_in` and the Coriolis
parameter at that day's drift position.
"""
function ClimaAtmos_MOSAiCAYiL_scm_coriolis end

"""
    ClimaAtmos_MOSAiCAYiL_grid(FT; faces = LES_FACES, kwargs...)

A ClimaAtmos `ColumnGrid` from a face vector. The faces are the whole specification —
compose [`truncate_faces_to_top`](@ref) and [`coarsen_faces_to_dz_min`](@ref) first.
"""
function ClimaAtmos_MOSAiCAYiL_grid end

"""Centre-level heights [m] of a grid, ascending."""
function ClimaAtmos_MOSAiCAYiL_z end

"""
    ClimaAtmos_MOSAiCAYiL_register_condensate_totals!(; registry)

Register the `ql_all` and `qi_all` diagnostics — cloud liquid plus rain, and cloud ice plus
snow, per mass of moist air. Idempotent.
"""
function ClimaAtmos_MOSAiCAYiL_register_condensate_totals! end

"""
    ClimaAtmos_MOSAiCAYiL_field(short_name, date; root)

A ClimaAtmos diagnostic short name built out of the archive, as `(; z, time, data, units)`,
so both sides of a comparison carry the same name and units.
[`ClimaAtmos_MOSAiCAYiL_translated_names`](@ref) lists what is available.
"""
function ClimaAtmos_MOSAiCAYiL_field end

"""The ClimaAtmos short names [`ClimaAtmos_MOSAiCAYiL_field`](@ref) can build from the archive."""
function ClimaAtmos_MOSAiCAYiL_translated_names end

"""
    ClimaAtmosMOSAiCAYiLInsolation(FT, case; reference_time, latitude, longitude, insolation_params)

Insolation held at a fixed zenith angle, as the reference runs did
(`lcnstzenithtime = .true.`, `cnstzenithtime = 11` on all 190 days). Polar night is
`(eps(FT), 0)`.
"""
function ClimaAtmosMOSAiCAYiLInsolation end
