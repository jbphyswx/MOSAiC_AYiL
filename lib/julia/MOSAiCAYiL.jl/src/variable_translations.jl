#=

    Machinery to convert between the raw DALES archive names and readable
    physical names, with the archive's unit mislabelling corrected.

    The archive carries 607 variables across its four netCDF files, so the naming is
    handled by rule rather than by list: the SB3 scalar families, the microphysics
    species x process grid, and the tendency-budget process x sample grid each follow
    a scheme, and every name in them is covered. `tmser` is the exception and needs a
    table, its names being irregular.

    Units are corrected in one place, because the files get three things wrong:
    the number scalars are per unit mass but labelled with the mass family's
    units, `precep_*`/`*_rate` claim kg/m2 but are a mixing ratio times a fall
    speed, and the potential-temperature tendencies claim K/kg/s but are K/s.

=#

# --- SB3 scalars ------------------------------------------------------------ #

"""DALES SB3 scalar index → what that scalar holds, as a description."""
const SB3_TO_PHYSICAL = Dict{String, String}(
    "sv001" => "n_rain",
    "sv002" => "q_rain",
    "sv003" => "n_cloud_liquid",
    "sv004" => "n_inp",
    "sv005" => "q_cloud_liquid",
    "sv006" => "n_ccn",
    "sv007" => "n_cloud_ice",
    "sv008" => "q_cloud_ice",
    "sv009" => "n_snow",
    "sv010" => "q_snow",
    "sv011" => "n_graupel",
    "sv012" => "q_graupel",
)

"""
What each SB3 scalar is in prose, replacing the `scalar NNN` the archive puts in
every `sv`-family long name.
"""
const SB3_DESCRIPTION = Dict{String, String}(
    "sv001" => "rain number",
    "sv002" => "rain mass",
    "sv003" => "cloud droplet number",
    "sv004" => "ice nucleating particle number",
    "sv005" => "cloud liquid mass",
    "sv006" => "CCN number",
    "sv007" => "cloud ice number",
    "sv008" => "cloud ice mass",
    "sv009" => "snow number",
    "sv010" => "snow mass",
    "sv011" => "graupel number",
    "sv012" => "graupel mass",
)

_sb3_physical(index) =
    get(SB3_TO_PHYSICAL, "sv" * index) do
        error("sv$index is not one of DALES's twelve SB3 scalars")
    end

# --- Microphysics process rates --------------------------------------------- #

"""SB3 species code in an `mphysprofiles` name → the species."""
const SB3_SPECIES = Dict{String, String}(
    "c" => "cloud_liquid",
    "r" => "rain",
    "i" => "ice",
    "s" => "snow",
    "g" => "graupel",
    "ccn" => "ccn",
)

"""
SB3 process code → the process.

Keyed on the code in the variable name, never on the archive's long name:
`dq_i_col_rig` is announced as a graupel tendency but is filled from the *ice*
loss in that collision.
"""
const MPHYS_PROCESS = Dict{String, String}(
    "nuc" => "nucleation",
    "inuc" => "nucleation",
    "dep" => "deposition",
    "sub" => "sublimation",
    "hom" => "freezing_homogeneous",
    "het" => "freezing_heterogeneous",
    "cond" => "condensation",
    "ev" => "evaporation",
    "sc" => "self_collection",
    "br" => "breakup",
    "au" => "autoconversion",
    "ac" => "accretion",
    "agg" => "aggregation",
    "rime" => "riming",
    "rime_ic" => "riming_by_cloud_liquid",
    "rime_sc" => "riming_by_cloud_liquid",
    "rime_gc" => "riming_by_cloud_liquid",
    "rime_gr" => "riming_by_rain",
    "col_rig" => "collision_rain_ice_to_graupel",
    "col_rsg" => "collision_rain_snow_to_graupel",
    "col_si" => "collection_by_snow",
    "col_gsg" => "collection_by_graupel",
    "eme_ic" => "enhanced_melting_by_cloud_liquid",
    "eme_sc" => "enhanced_melting_by_cloud_liquid",
    "eme_gc" => "enhanced_melting_by_cloud_liquid",
    "eme_ri" => "enhanced_melting_by_rain",
    "eme_rs" => "enhanced_melting_by_rain",
    "eme_gr" => "enhanced_melting_by_rain",
    "me" => "melting",
    "cv_ig" => "conversion_to_graupel",
    "cv_sg" => "conversion_to_graupel",
    "mul" => "ice_multiplication",
    "sadj" => "saturation_adjustment",
    "sed" => "sedimentation",
    "tot" => "microphysics",
    "totf" => "all_processes",
)

"""Potential-temperature process code in a `dth*` name → the process."""
const THETA_PROCESS = Dict{String, String}(
    "mphys" => "microphysics",
    "freeze" => "freezing",
    "melt" => "melting",
    "cond" => "condensation",
    "ev" => "evaporation",
    "dep" => "deposition",
    "sub" => "sublimation",
)

"""
    BULKMICROSTAT3

The 23 variables `modbulkmicrostat3` contributes to `profiles.001.nc`, as
`raw => (description, units)`.

They need their own table because two things about them are wrong as stored.

**They are one record late, and the first and last samples are gone.**
`writebulkmicrostat3` writes at modgenstat's record counter
(`modbulkmicrostat3.f90:2301`), which profile writes take as `intent(in)` while
only genstat's time write increments it (`modstat_nc.f90:425,437`) — but the module
runs from `microsources` (`modbulkmicro3.f90:1944`, `program.f90:235`), *before*
`genstat` (`program.f90:272`) in the same iteration. So the k-th sample is written
to record k−1: the first goes to record 0 and is lost, the value at `time[t]` is
the sample for `time[t+1]`, and the last record is never written. Verified against
the data: `qrmn[t]` matches genstat's own `sv002[t+1]` to 5e-4 relative against
0.6 at every other offset, and the final record is fill on 190/190 days.
[`read_variable`](@ref) puts them back on the times they are averages for.

**Five state the wrong units**, sharing the label `W/m^2` with the two that really
are fluxes: `qrmn` is `sum(q_hr)` (`:1126`); `nrrain` is `rhof*sum(n_hr)` (`:1122`),
so per volume already; `raincount` and `preccount` are column fractions
(`:1116,1118`); `dvrmn` divides a diameter sum by a count (`:1129`). Only
`rainrate` and `precmn` carry the `rhof*rlv` that makes a flux (`:2273,2277`). The
tendencies' own `#/m3/s` is right — `Npav = rhof*avfield` (`:1416`).

`rainrate`, `precmn` and `preccount` come from `precep_l`, so they are liquid
precipitation and not total. `dvrmn` sums `modmicrodata`'s `Dvr`, which SB3 never
fills — its `imicro` guard is commented out (`:1128`) — so it carries no
information here.

**Two of the `qt` tendencies are constant zero.** `qtpaccr` is announced as the accretion
tendency but the `slabsum` that would fill it is commented out (`:1445-1448`), leaving the
zeroed `avfield`, so like `dvrmn` it carries no information. `qtpsed` is zero deliberately
(`:1462-1464`, "rain sedimentation does not change qt"). The other three are real:
`qtpauto = -sum(dq_hr_au)` (`:1428`), `qtpevap = -sum(dq_hr_ev)` (`:1479`), and `qtptot`
their sum (`:2299`). `qt` here is DALES's total water, `q_v + q_l` — its saturation
adjustment is liquid-only and ice is a separate scalar, so its total holds fewer species
than the name suggests.
"""
const BULKMICROSTAT3 = Dict{String, Tuple{String, String}}(
    "cfrac" => ("cloud_fraction", "1"),
    "rainrate" => ("rain_rate_precipitating_columns", "W/m^2"),
    "preccount" => ("precipitating_fraction", "1"),
    "nrrain" => ("n_rain", "m^-3"),
    "raincount" => ("rain_fraction", "1"),
    "precmn" => ("rain_rate", "W/m^2"),
    "dvrmn" => ("rain_mean_volume_diameter", "m"),
    "qrmn" => ("q_rain", "kg/kg"),
    "npauto" => ("n_rain_tendency_autoconversion", "m^-3 s^-1"),
    "npaccr" => ("n_rain_tendency_accretion", "m^-3 s^-1"),
    "npsed" => ("n_rain_tendency_sedimentation", "m^-3 s^-1"),
    "npevap" => ("n_rain_tendency_evaporation", "m^-3 s^-1"),
    "nptot" => ("n_rain_tendency_microphysics", "m^-3 s^-1"),
    "qrpauto" => ("q_rain_tendency_autoconversion", "kg/kg/s"),
    "qrpaccr" => ("q_rain_tendency_accretion", "kg/kg/s"),
    "qrpsed" => ("q_rain_tendency_sedimentation", "kg/kg/s"),
    "qrpevap" => ("q_rain_tendency_evaporation", "kg/kg/s"),
    "qrptot" => ("q_rain_tendency_microphysics", "kg/kg/s"),
    "qtpauto" => ("q_tot_tendency_autoconversion", "kg/kg/s"),
    "qtpaccr" => ("q_tot_tendency_accretion", "kg/kg/s"),
    "qtpsed" => ("q_tot_tendency_sedimentation", "kg/kg/s"),
    "qtpevap" => ("q_tot_tendency_evaporation", "kg/kg/s"),
    "qtptot" => ("q_tot_tendency_microphysics", "kg/kg/s"),
)

"""
    TMSER

The 52 variables of `tmser.001.nc`, as `raw => (description, units)`.

They need a table rather than a rule: the names are irregular, and the file is on its own
120-record 60 s axis where the profiles are 24 records of 300 s averages, so a bar must be
averaged over five samples before it is compared with a profile integral.

Units are the archive's own except `qtstr`, which the file labels `K` while calling it a
humidity scale: it is `q* = -wq/ustar`, and the file's own `wq` (`kg/kg m/s`) and `ustar`
(`m/s`) fix it at `kg/kg`.

Two of the archive's long names are unreliable, so the description is keyed on the variable
name: `giwp_max` is announced as "Graupel Snow Ice-water path" and `sfc_precw_av` shares
"Average surface precipitation" with `sfc_prec_av`, which is a different quantity in
different units.

`vtke` keeps its stated `kg/s` even though a vertical integral of a specific kinetic energy
is `kg/s^2`; nothing in the archive settles which the values are.
"""
const TMSER = Dict{String, Tuple{String, String}}(
    "cfrac" => ("cloud_fraction", "1"),
    "zb" => ("cloud_base_height", "m"),
    "zc_av" => ("cloud_top_height_mean", "m"),
    "zc_max" => ("cloud_top_height_max", "m"),
    "zi" => ("boundary_layer_height", "m"),
    "we" => ("entrainment_velocity", "m/s"),
    "lwp_bar" => ("liquid_water_path_thermodynamic", "kg/m^2"),
    "lwp_max" => ("liquid_water_path_thermodynamic_max", "kg/m^2"),
    "wmax" => ("w_max", "m/s"),
    "vtke" => ("tke_vertical_integral", "kg/s"),
    "lmax" => ("q_liquid_max", "kg/kg"),
    "ustar" => ("friction_velocity", "m/s"),
    "tstr" => ("temperature_scale", "K"),
    "qtstr" => ("humidity_scale", "kg/kg"),
    "obukh" => ("obukhov_length", "m"),
    "thlskin" => ("thetal_skin", "K"),
    "z0" => ("z0_unfilled_sentinel", "m"),
    "wtheta" => ("surface_kinematic_temperature_flux", "K m/s"),
    "wthetav" => ("surface_kinematic_virtual_temperature_flux", "K m/s"),
    "wq" => ("surface_kinematic_moisture_flux", "kg/kg m/s"),
    "cl_frac" => ("cloud_fraction_column_liquid", "1"),
    "ci_frac" => ("cloud_fraction_column_ice", "1"),
    "ctot_frac" => ("cloud_fraction_column_total", "1"),
    "zb_l_av" => ("cloud_base_height_liquid_mean", "m"),
    "zb_l_min" => ("cloud_base_height_liquid_min", "m"),
    "zc_l_av" => ("cloud_top_height_liquid_mean", "m"),
    "zc_l_max" => ("cloud_top_height_liquid_max", "m"),
    "zb_i_av" => ("cloud_base_height_ice_mean", "m"),
    "zb_i_min" => ("cloud_base_height_ice_min", "m"),
    "zc_i_av" => ("cloud_top_height_ice_mean", "m"),
    "zc_i_max" => ("cloud_top_height_ice_max", "m"),
    "clwp_bar" => ("q_cloud_liquid_path", "kg/m^2"),
    "clwp_max" => ("q_cloud_liquid_path_max", "kg/m^2"),
    "rlwp_bar" => ("q_rain_path", "kg/m^2"),
    "rlwp_max" => ("q_rain_path_max", "kg/m^2"),
    "icwp_bar" => ("q_cloud_ice_path", "kg/m^2"),
    "icwp_max" => ("q_cloud_ice_path_max", "kg/m^2"),
    "siwp_bar" => ("q_snow_path", "kg/m^2"),
    "siwp_max" => ("q_snow_path_max", "kg/m^2"),
    "giwp_bar" => ("q_graupel_path", "kg/m^2"),
    "giwp_max" => ("q_graupel_path_max", "kg/m^2"),
    "sfc_precw_av" => ("surface_precipitation_mass_flux", "kg/m^2/s"),
    "sfc_prec_av" => ("surface_precipitation_energy_flux", "W/m^2"),
    "SW_up_ca_TOA" => ("rsu_toa_clear", "W/m^2"),
    "SW_dn_ca_TOA" => ("rsd_toa_clear", "W/m^2"),
    "LW_up_ca_TOA" => ("rlu_toa_clear", "W/m^2"),
    "LW_dn_ca_TOA" => ("rld_toa_clear", "W/m^2"),
    "SW_up_TOA" => ("rsu_toa", "W/m^2"),
    "SW_dn_TOA" => ("rsd_toa", "W/m^2"),
    "LW_up_TOA" => ("rlu_toa", "W/m^2"),
    "LW_dn_TOA" => ("rld_toa", "W/m^2"),
)

"""
    SCM_IN

The 77 variables of `scm_in.a_year_in_les.<date>.nc`, as `raw => (description, units)`.

The ERA5 testbed forcing DALES was driven with, on its own axes: `nlev` full levels stored
**top-down** from about 85 km, `nlevp1` faces, `nlevs` soil levels, and two time records.
[`read_variable`](@ref) returns the atmospheric levels ascending. The level count is a
property of the day, not of the ensemble — 3037 on 9 days, 3038 on 79, 3039 on 48, 3040 on
21, 3041 on 24 and 3042 on 9.

Every variable is bitwise identical between the two time records on all 190 days except
`time`, `second` and `base_time`, the file being one 05:00–11:00 UTC composite written twice.

`q_skin` carries its units and its long name in each other's attribute (`units` reads "skin
reservoir content", `long_name` reads "m of water"), so both are given here. `sv` is labelled
`whatever`.

The names ending `_local` are the value at the domain midpoint and the ones without are the
domain average; DALES reads the midpoint set (`modtestbed.f90:630-631`). Neither is the
unmarked default here, so both carry a qualifier.
"""
const SCM_IN = Dict{String, Tuple{String, String}}(
    # axes and time
    "nlev" => ("level_index", "1"),
    "nlevp1" => ("level_index_face", "1"),
    "nlevs" => ("soil_level_index", "1"),
    "time" => ("time", "s"),
    "second" => ("second_of_sequence", "s"),
    "date" => ("date", "yyyymmdd"),
    "base_time" => ("epoch_time", "s"),
    "height_f" => ("height", "m"),
    "height_h" => ("height_face", "m"),
    "pressure_f" => ("pressure", "Pa"),
    "pressure_h" => ("pressure_face", "Pa"),
    "gz_f" => ("geopotential", "m^2/s^2"),
    # state, domain averaged
    "t" => ("temperature_domain_mean", "K"),
    "q" => ("q_vapor_domain_mean", "kg/kg"),
    "ql" => ("q_cloud_liquid_domain_mean", "kg/kg"),
    "qi" => ("q_cloud_ice_domain_mean", "kg/kg"),
    "u" => ("u_domain_mean", "m/s"),
    "v" => ("v_domain_mean", "m/s"),
    "cloud_fraction" => ("cloud_fraction_domain_mean", "1"),
    "o3" => ("q_ozone", "kg/kg"),
    "omega" => ("pressure_velocity", "Pa/s"),
    # state, at the domain midpoint
    "t_local" => ("temperature_midpoint", "K"),
    "q_local" => ("q_vapor_midpoint", "kg/kg"),
    "ql_local" => ("q_cloud_liquid_midpoint", "kg/kg"),
    "qi_local" => ("q_cloud_ice_midpoint", "kg/kg"),
    "u_local" => ("u_midpoint", "m/s"),
    "v_local" => ("v_midpoint", "m/s"),
    "cc_local" => ("cloud_fraction_midpoint", "1"),
    # large-scale forcing
    "tadv" => ("temperature_tendency_advection_horizontal", "K/s"),
    "qadv" => ("q_vapor_tendency_advection_horizontal", "kg/kg/s"),
    "ladv" => ("q_cloud_liquid_tendency_advection_horizontal", "kg/kg/s"),
    "iadv" => ("q_cloud_ice_tendency_advection_horizontal", "kg/kg/s"),
    "uadv" => ("u_tendency_advection_horizontal", "m/s^2"),
    "vadv" => ("v_tendency_advection_horizontal", "m/s^2"),
    "aadv" => ("cloud_fraction_tendency_advection_horizontal", "s^-1"),
    "ug" => ("u_geostrophic", "m/s"),
    "vg" => ("v_geostrophic", "m/s"),
    # radiation and microphysics input
    "fradLWnet" => ("radiative_flux_net_longwave_face", "W/m^2"),
    "fradSWnet" => ("radiative_flux_net_shortwave_face", "W/m^2"),
    "n_ccn" => ("n_ccn", "m^-3"),
    "sv" => ("sv", ""),
    # surface
    "ps" => ("surface_pressure", "Pa"),
    "lat" => ("trajectory_latitude", "degrees_north"),
    "lon" => ("trajectory_longitude", "degrees_east"),
    "lat_grid" => ("grid_latitude", "degrees_north"),
    "lon_grid" => ("grid_longitude", "degrees_east"),
    "albedo" => ("albedo", "1"),
    "albedo_snow" => ("albedo_snow", "1"),
    "snow" => ("snow_depth_liquid_equivalent", "m"),
    "density_snow" => ("snow_density", "kg/m^3"),
    "t_snow" => ("snow_temperature", "K"),
    "mom_rough" => ("z0_momentum", "m"),
    "heat_rough" => ("z0_heat", "m"),
    "sea_ice_frct" => ("sea_ice_fraction", "1"),
    "t_skin" => ("t_skin", "K"),
    "t_skin_ocean" => ("t_skin_ocean", "K"),
    "t_skin_seaice" => ("t_skin_seaice", "K"),
    "open_sst" => ("open_sst", "K"),
    "lsm" => ("land_sea_mask", "1"),
    "sfc_sens_flx" => ("surface_sensible_heat_flux", "W/m^2"),
    "sfc_lat_flx" => ("surface_latent_heat_flux", "W/m^2"),
    "q_skin" => ("skin_reservoir_content", "m"),
    # soil and sea ice
    "h_soil" => ("soil_layer_thickness", "m"),
    "q_soil" => ("soil_moisture", "m^3/m^3"),
    "t_soil" => ("soil_temperature", "K"),
    "t_sea_ice" => ("sea_ice_temperature", "K"),
    # vegetation
    "low_veg_cover" => ("vegetation_cover_low", "1"),
    "low_veg_lai" => ("leaf_area_index_low", "1"),
    "low_veg_type" => ("vegetation_type_low", "1"),
    "high_veg_cover" => ("vegetation_cover_high", "1"),
    "high_veg_lai" => ("leaf_area_index_high", "1"),
    "high_veg_type" => ("vegetation_type_high", "1"),
    # orography
    "orog" => ("surface_geopotential", "m^2/s^2"),
    "sdor" => ("orography_subgrid_standard_deviation", "m^2/s^2"),
    "anor" => ("orography_subgrid_angle", "degrees"),
    "isor" => ("orography_subgrid_anisotropy", "1"),
    "slor" => ("orography_subgrid_slope", "m/m"),
)

"""
The `scm_in` long name of a variable whose file attributes hold each other's value.
"""
const SCM_IN_LONG_NAME = Dict{String, String}("q_skin" => "skin reservoir content")

"""
Raw names the archive uses for a *different* quantity in more than one file, and the files
carrying them.

`cfrac` is a `(zt, time)` profile in `profiles.001.nc` and a `(time,)` column series in
`tmser.001.nc`; `time` is 24 records of 300 s in one and 120 of 60 s in the other. Resolving
either by name alone returns the wrong array rather than an error, so
[`variable_product`](@ref) refuses and the caller names the file.

`u`, `v` and `ql` are DALES slab means on 286 LES levels in `profiles.001.nc` and ERA5
domain averages on 3037–3042 testbed levels in `scm_in`. They are the only three of
`scm_in`'s 77 names that another file also carries.

`zt` and `zm` are not here: they are the same coordinate in every file that carries them.
"""
const AMBIGUOUS_RAW_NAMES = Dict{String, Tuple{Vararg{Symbol}}}(
    "cfrac" => (:profiles, :tmser),
    "time" => (:profiles, :mphys, :samptend, :tmser, :scm_in),
    "u" => (:profiles, :scm_in),
    "v" => (:profiles, :scm_in),
    "ql" => (:profiles, :scm_in),
)

"""`mphysprofiles` names that are not tendencies."""
const MPHYS_DIAGNOSTIC = Dict{String, String}(
    "cfrac_l" => "cloud_fraction_liquid",
    "cfrac_i" => "cloud_fraction_ice",
    "cfrac_tot" => "cloud_fraction_total",
    "ice_rate" => "ice_fall_rate",
    "snow_rate" => "snow_fall_rate",
    "rain_rate" => "rain_fall_rate",
    "graupel_rate" => "graupel_fall_rate",
)

# --- Tendency budgets ------------------------------------------------------- #

"""
`samptend` field code → the field. `qr`/`nr` index `iqr`/`inr`, which SB3 aliases
onto rain.
"""
const SAMPTEND_FIELD = Dict{String, String}(
    "u" => "u", "v" => "v", "w" => "w", "thl" => "thl", "qt" => "qt",
    "qr" => "q_rain", "nr" => "n_rain",
)

"""`samptend` process code → the process."""
const SAMPTEND_PROCESS = Dict{String, String}(
    "adv" => "advective",
    "dif" => "diffusive",
    "for" => "forces",
    "cor" => "coriolis",
    "ls" => "large_scale",
    "top" => "top_boundary",
    "pois" => "pressure_gradient",
    "addon" => "addons",
    "rad" => "radiative",
    "micro" => "microphysics",
    "tot" => "total",
    "leib" => "total_leibniz",
)

"""Conditional-sample suffixes, longest first so `cldcr` is not read as `cld`."""
const SAMPTEND_SAMPLES = ("cldcr", "cldup", "buup", "cld", "upd", "all")

const SAMPTEND_SAMPLE_NAME = Dict{String, String}(
    "all" => "all",
    "upd" => "updraft",
    "buup" => "buoyant_updraft",
    "cld" => "cloud",
    "cldcr" => "cloud_core",
    "cldup" => "cloud_updraft",
)

"""
`samptend` names carrying no sample suffix.

`modsamptend.f90:184` registers `utendcor` without a sample suffix — every sample
writes to the one variable — so which sample survives is not recoverable from the
file, and the name says so rather than claiming `all`.
"""
const SAMPTEND_IRREGULAR =
    Dict{String, String}("utendcor" => "u_tendency_coriolis_unknown_sample")

# --- The general translator ------------------------------------------------- #

"""
    mphys_name(raw) -> String or nothing

The name for an `mphysprofiles` variable, or `nothing` when it is not one. A name
that *is* of the family but carries an unknown species or process errors rather
than passing through.
"""
function mphys_name(raw::AbstractString)
    haskey(MPHYS_DIAGNOSTIC, raw) && return MPHYS_DIAGNOSTIC[raw]
    m = match(r"^d(q|n)_([a-z]+)_(.+)$", raw)
    if m !== nothing
        kind, species_code, process_code = m.captures
        species = get(SB3_SPECIES, species_code) do
            error("$raw: species code `$species_code` is not an SB3 species")
        end
        process = get(MPHYS_PROCESS, process_code) do
            error("$raw: process code `$process_code` is not an SB3 process")
        end
        return string(kind, "_", species, "_tendency_", process)
    end
    m = match(r"^dth(l?)_(.+)$", raw)
    if m !== nothing
        liquid, process_code = m.captures
        process = get(THETA_PROCESS, process_code) do
            error("$raw: process code `$process_code` is not a theta process")
        end
        return string(isempty(liquid) ? "theta" : "thetal", "_tendency_", process)
    end
    return nothing
end

"""
    samptend_name(raw) -> String or nothing

The name for a `samptend` variable, `<field>_tendency_<process>_<sample>`, or
`nothing` when it is not one.
"""
function samptend_name(raw::AbstractString)
    haskey(SAMPTEND_IRREGULAR, raw) && return SAMPTEND_IRREGULAR[raw]
    m = match(r"^(thl|qt|qr|nr|u|v|w)tend([a-z]+)$", raw)
    m === nothing && return nothing
    field_code, rest = m.captures
    for sample_code in SAMPTEND_SAMPLES
        endswith(rest, sample_code) || continue
        process_code = rest[1:(end - length(sample_code))]
        isempty(process_code) && continue
        process = get(SAMPTEND_PROCESS, process_code) do
            error("$raw: process code `$process_code` is not a samptend process")
        end
        return string(
            SAMPTEND_FIELD[field_code], "_tendency_", process, "_",
            SAMPTEND_SAMPLE_NAME[sample_code],
        )
    end
    error("$raw: no known sample suffix, and not one of the irregular names")
end

"""
    physical_name(raw) -> String

A readable name for any variable the archive carries, or the name unchanged when
it belongs to no renamed family.

`svNNN` alone is unreadable downstream, and every form the archive uses is
covered:

| archive | becomes | from |
|---|---|---|
| `svNNN` | `q_ice` | mixing ratio or number |
| `svNNN2r` | `q_ice_variance_resolved` | resolved variance |
| `svpNNN` | `q_ice_tendency` | scalar tendency |
| `svptNNN` | `q_ice_tendency_turbulence` | turbulence tendency |
| `wsvNNNr/s/t` | `q_ice_flux_resolved/sfs/total` | fluxes |

An `svNNN` index that is not one of the twelve errors: a raw `sv004` downstream is
indistinguishable from a variable deliberately left alone.

`file` names the archive file `raw` came from, which only [`TMSER`](@ref) needs: its names
are irregular and two of them collide with `profiles.001.nc`.
"""
physical_name(raw::AbstractString) =
    physical_name(raw, variable_product(raw))

function physical_name(raw::AbstractString, file::Symbol)
    if file === :tmser
        haskey(TMSER, raw) && return first(TMSER[raw])
        return String(raw)          # the file's own `time` axis
    end
    if file === :scm_in
        haskey(SCM_IN, raw) || error("`$raw` is not one of the 77 `scm_in` variables")
        return first(SCM_IN[raw])
    end
    haskey(BULKMICROSTAT3, raw) && return first(BULKMICROSTAT3[raw])
    m = match(r"^sv(\d{3})$", raw)
    m === nothing || return _sb3_physical(m.captures[1])
    m = match(r"^sv(\d{3})2r$", raw)
    m === nothing || return _sb3_physical(m.captures[1]) * "_variance_resolved"
    m = match(r"^svp(\d{3})$", raw)
    m === nothing || return _sb3_physical(m.captures[1]) * "_tendency"
    m = match(r"^svpt(\d{3})$", raw)
    m === nothing || return _sb3_physical(m.captures[1]) * "_tendency_turbulence"
    m = match(r"^wsv(\d{3})([rst])$", raw)
    if m !== nothing
        kind = Dict("r" => "resolved", "s" => "sfs", "t" => "total")
        return _sb3_physical(m.captures[1]) * "_flux_" * kind[m.captures[2]]
    end
    name = mphys_name(raw)
    name === nothing || return name
    name = samptend_name(raw)
    name === nothing || return name
    return String(raw)
end

"""
    raw_name(physical, date; root, file)
    raw_name(physical, ds; file)

The archive variable name that [`physical_name`](@ref) maps onto `physical`, the inverse
of that translation for one file.

Inverts `physical_name` over the file's own variables rather than reimplementing the
mapping, so the two cannot drift apart. Errors when nothing matches, and errors naming
every candidate when more than one does: `profiles.001.nc` carries `q_rain` as both
`sv002` and `qrmn`, and `n_rain` as both `sv001` and `nrrain` — the scalar output and
`BULKMICROSTAT3` writing one quantity on two different time axes.
"""
function raw_name(
    physical::AbstractString, date; root = data_root(), file::Symbol = :profiles,
)
    return open_archive(file, date; root) do ds
        raw_name(physical, ds; file)
    end
end

function raw_name(
    physical::AbstractString, ds::NC.NCDataset; file::Symbol = :profiles,
)
    hits = String[]
    for raw in keys(ds)
        got = try
            physical_name(raw, file)
        catch
            continue
        end
        got == physical && push!(hits, String(raw))
    end
    isempty(hits) && error(
        "No variable of $(NC.path(ds)) has the physical name `$physical`.",
    )
    length(hits) == 1 || error(
        "`$physical` is the physical name of $(join(sort(hits), ", ")) in \
         $(NC.path(ds)); ask for the one you want by its archive name.",
    )
    return only(hits)
end

# --- Units ------------------------------------------------------------------ #

"""
Per-volume units of a number quantity, and the power of density that converts it,
by every spelling the archive reaches it with.

DALES carries the `sv` scalars as specific quantities — number per unit *mass* —
and labels all twelve with the mass units of the family, so a number arrives as
`(kg/kg)`. Multiplying a variance by `ρ^2` treats the density as having no
fluctuation of its own; on a slab mean that is a good approximation, not an
identity.
"""
const NUMBER_UNITS = Dict{String, Tuple{String, Int}}(
    "kg/kg" => ("m^-3", 1),
    "(kg/kg)" => ("m^-3", 1),
    "#/kg" => ("m^-3", 1),
    "/kg" => ("m^-3", 1),
    "(kg/kg/s)" => ("m^-3 s^-1", 1),
    "#/kg/s" => ("m^-3 s^-1", 1),
    "/kg/s" => ("m^-3 s^-1", 1),
    "(kg/kg)^2" => ("m^-6", 2),
    "kg/kg m/s" => ("m^-3 m/s", 1),
)

"""
Units the archive states wrongly, and what they are.

`precep_*`/`*_rate` is `sed_q/ρ`, a mixing ratio times a fall speed, not the
`kg/m2` claimed. The `K/kg/s` on the potential-temperature tendencies is likewise
wrong: they are formed as `(L_v/(c_p Π)) dq/dt`, and `L_v/c_p` is kelvin per unit
mixing ratio, so the product is `K/s`.
"""
const MISLABELLED_UNITS =
    Dict{String, String}("kg/m2" => "kg/kg m/s", "K/kg/s" => "K/s")

"""One spelling for each unit the archive writes more than one way."""
const UNIT_SPELLINGS = Dict{String, String}(
    "(kg/kg)" => "kg/kg",
    "(kg/kg/s)" => "kg/kg/s",
    "kg/m^2 /s" => "kg/m^2/s",
    "Km/s" => "K m/s",
    "#/m3/s" => "m^-3 s^-1",
    "-" => "1",
)

"""
    dales_variable_attributes(raw, name, units, long_name)

`(units, long_name, ρ_power)` for a translated variable: the units it is really
in, a long name with `scalar NNN` replaced by what that scalar is, and the power
of air density that converts its values.

`ρ_power` is 0 for a relabelling, 1 for a number, 2 for a number variance. A
number carrying units in no known spelling errors rather than being mislabelled.
The [`BULKMICROSTAT3`](@ref) and [`TMSER`](@ref) groups state their own units and need no
conversion — their numbers were multiplied by density where they were formed.

`file` only selects whether [`TMSER`](@ref) is consulted; every other result is the same in
every file.
"""
function dales_variable_attributes(
    raw::AbstractString,
    name::AbstractString,
    units::AbstractString,
    long_name::AbstractString,
    file::Symbol = :profiles,
)
    if file === :tmser
        haskey(TMSER, raw) && return (last(TMSER[raw]), long_name, 0)
        return (spelled_units(units), String(long_name), 0)
    end
    if file === :scm_in
        return (
            last(SCM_IN[raw]),
            get(SCM_IN_LONG_NAME, raw, String(long_name)),
            0,
        )
    end
    haskey(BULKMICROSTAT3, raw) && return (last(BULKMICROSTAT3[raw]), long_name, 0)
    out = String(long_name)
    m = match(r"[Ss]calar (\d{3})", out)
    if m !== nothing
        description = get(SB3_DESCRIPTION, "sv" * m.captures[1]) do
            error("$raw: sv$(m.captures[1]) has no description")
        end
        out = replace(out, m.match => description)
        startswith(m.match, "S") && (out = uppercasefirst(out))
    end
    if startswith(name, "n_")
        converted, ρ_power = get(NUMBER_UNITS, units) do
            error("$name is a number but is labelled `$units`")
        end
        return (converted, out, ρ_power)
    end
    return (spelled_units(units), out, 0)
end

"""
    spelled_units(units)

The archive's own units, mislabellings corrected and one spelling per unit.

A relabelling only: nothing here implies a change to the values, which is what lets
it stand in for the converted units when a caller asked for untranslated data.
"""
function spelled_units(units::AbstractString)
    corrected = get(MISLABELLED_UNITS, units, String(units))
    return get(UNIT_SPELLINGS, corrected, corrected)
end

_archive_path(::Val{:scm_in}, date, root) = scm_in_path(date; root)
_archive_path(::Val{:profiles}, date, root) = les_profiles_path(date; root)
_archive_path(::Val{:mphys}, date, root) = mphys_path(date; root)
_archive_path(::Val{:samptend}, date, root) = samptend_path(date; root)
_archive_path(::Val{:tmser}, date, root) = tmser_path(date; root)

"""
    open_archive(f, file, date; root)

Run `f(ds)` on `file` of `date` — `:profiles`, `:tmser`, `:mphys`, `:samptend` or `:scm_in`
— opened once and closed after, returning whatever `f` returns.

Several variables of one day cost one open through the [`read_variable`](@ref) method that
takes an open dataset, against one open each through the method that takes a date.
"""
function open_archive(f, file::Symbol, date; root = data_root())
    path = _archive_path(Val(file), date, root)
    isfile(path) || error("No archive file at $path")
    return NC.NCDataset(f, path, "r")
end

"""
    variable_product(raw)

Which archive file a raw variable lives in.

Errors on a name [`AMBIGUOUS_RAW_NAMES`](@ref) carries rather than picking one: resolving
those by name alone hands back a different quantity, not an error. Pass `file` to
[`read_variable`](@ref) instead.
"""
function variable_product(raw::AbstractString)
    files = get(AMBIGUOUS_RAW_NAMES, raw, nothing)
    isnothing(files) || error(
        "`$raw` is a different quantity in each of $(join(files, ", ")); pass \
         `file = :$(first(files))` (or another) to say which one.",
    )
    haskey(TMSER, raw) && return :tmser
    haskey(SCM_IN, raw) && return :scm_in
    samptend_name(raw) === nothing || return :samptend
    mphys_name(raw) === nothing || return :mphys
    return :profiles
end

# 2D fields are stored vertical-axis-first, but take the orientation from the
# declared dimensions rather than from which axis is longer: that is a property of
# the run, not of the layout.
function _read_oriented(ds, name)
    var = ds[name]
    a = Array(var)
    ndims(a) == 2 || return a
    return first(NC.dimnames(var)) == "time" ? permutedims(a, (2, 1)) : a
end

"""`scm_in` level dimension → the variable carrying its heights [m]."""
const SCM_IN_LEVEL_AXIS =
    Dict{String, String}("nlev" => "height_f", "nlevp1" => "height_h")

# `scm_in` puts its heights on a variable of their own rather than on the level index, and
# stores them per time record; the records are bitwise identical on all 190 days.
function _vertical_axis(ds, file::Symbol, dims, ::Type{T}) where {T}
    if file === :scm_in
        for d in dims
            haskey(SCM_IN_LEVEL_AXIS, d) || continue
            h = Array(NC.variable(ds, SCM_IN_LEVEL_AXIS[d]))
            return reverse(vec(view(h, :, 1)))
        end
        return T[]
    end
    length(dims) < 2 && return T[]
    vertical = first(dims) == "time" ? dims[2] : first(dims)
    return haskey(ds, vertical) ? vec(Array(ds[vertical])) : T[]
end

# The atmospheric levels are stored top-down; the soil levels are not turned around.
function _ascending_levels(data, file::Symbol, dims)
    file === :scm_in || return data
    k = findfirst(d -> haskey(SCM_IN_LEVEL_AXIS, d), collect(dims))
    return k === nothing ? data : reverse(data; dims = k)
end

"""
    ρ_power(ds, raw; file)

The power of air density that converts `raw` to per-volume units, `0` when the values stand
as the archive holds them: `1` for a number, `2` for a number variance.

Reads the variable's attributes, not its data.
"""
function ρ_power(
    ds::NC.NCDataset, raw::AbstractString; file::Symbol = variable_product(raw),
)::Int
    var = ds[raw]
    return last(
        dales_variable_attributes(
            raw,
            physical_name(raw, file),
            get(var.attrib, "units", ""),
            get(var.attrib, "longname", get(var.attrib, "long_name", raw)),
            file,
        ),
    )
end

"""
    read_variable(raw, date; root, translate_units)

One raw archive variable, as `(; raw, description, z, time, data, units, long_name)`.

`description` is its [`physical_name`](@ref). With `translate_units` the values are
converted to the units [`dales_variable_attributes`](@ref) reports — a number
becomes per volume — so a caller never handles the archive's mislabelling itself.

A number per unit mass is converted by the day's `rhof`, taken from
[`dales_slab_column`](@ref). `mphysprofiles.001.nc` and `samptend.001.nc` carry no `rhof` of
their own and share `profiles.001.nc`'s `time`, `zt` and `zm` exactly.

A [`BULKMICROSTAT3`](@ref) variable comes back on the times it is an average for,
which is one record on from where it is stored, so it has one sample fewer than
the rest of the file and none of them missing. That displacement is a property of
`profiles.001.nc` alone and is not applied to any other file.

`file` says which archive file to read, and is required for the names
[`AMBIGUOUS_RAW_NAMES`](@ref) carries: `:scm_in`, `:profiles`, `:tmser`, `:mphys` or
`:samptend`. `tmser.001.nc` has no vertical axis, so `z` comes back empty for its
variables, as it does for `scm_in`'s soil levels and its per-time scalars.

An [`SCM_IN`](@ref) variable comes back on an ascending height axis, the file storing its
atmospheric levels top-down; its soil levels are left as they are. Both of its time records
are returned.
"""
function read_variable(
    raw::AbstractString,
    date;
    root = data_root(),
    file::Symbol = variable_product(raw),
    translate_units::Bool = true,
)
    return open_archive(file, date; root) do ds
        density =
            translate_units && ρ_power(ds, raw; file) != 0 ?
            dales_rhof(date; root).rhof : nothing
        read_variable(ds, raw; file, translate_units, density)
    end
end

"""
    read_variable(ds, raw; file, translate_units, density)

The same, from an archive file already open, so a caller reading many variables of one
day opens it once.

`density` is the day's `rhof`, required when [`ρ_power`](@ref) is not `0` and
`translate_units` is set; the date-taking method supplies it.
"""
function read_variable(
    ds::NC.NCDataset,
    raw::AbstractString;
    file::Symbol = variable_product(raw),
    translate_units::Bool = true,
    density = nothing,
)
    var = ds[raw]
    data = _read_oriented(ds, raw)
    description = physical_name(raw, file)
    raw_units = get(var.attrib, "units", "")
    long_name = get(var.attrib, "longname", get(var.attrib, "long_name", raw))
    units, long_name, power =
        dales_variable_attributes(raw, description, raw_units, long_name, file)
    if power != 0
        if translate_units
            isnothing(density) && error(
                "`$raw` is a number per unit mass; converting it needs the day's `rhof`. \
                 Pass `density = dales_rhof(date; root).rhof`, or read it with \
                 `translate_units = false`.",
            )
            data = data .* density .^ power
        else
            # the values were left as the archive holds them, so the units must
            # say so too rather than reporting the conversion that did not happen
            units = spelled_units(raw_units)
        end
    end
    dims = NC.dimnames(var)
    data = _ascending_levels(data, file, dims)
    z = _vertical_axis(ds, file, dims, eltype(data))
    time = vec(Array(NC.variable(ds, "time")))
    if file === :profiles && haskey(BULKMICROSTAT3, raw)
        data = identity.(data[:, 1:(end - 1)])   # the dropped record was the only fill
        time = time[2:end]
    end
    return (; raw, description, z, time, data, units, long_name)
end

# --- Derived quantities ----------------------------------------------------- #

"""
    dales_radiative_heating(date; root, band = :total)

Radiative heating rate [K/s] of the reference column, as `(; z, time, data)`, for
`:longwave`, `:shortwave` or `:total`.

The archive's `thllwtend`/`thlswtend`/`thltend` are labelled K/s but are **potential**
temperature tendencies: `modradstat.f90:256` forms each as a face-flux divergence
over `rhof*exnf*cp*dzf`, so the `exnf` has to be put back to get a temperature
tendency. Π comes from [`pressure_from_face`](@ref), the archive's centre pressure being
absent.

This is the quantity a radiation scheme is judged on, `thltend` being the sum of the
two bands and `thlradls` a prescribed large-scale term that is separate from both.
"""
dales_radiative_heating(
    date;
    root = data_root(),
    band::Symbol = :total,
    backend = DefaultThermodynamicsBackend(),
) = open_archive(:profiles, date; root) do ds
    dales_radiative_heating(ds; band, backend)
end

function dales_radiative_heating(
    ds::NC.NCDataset;
    band::Symbol = :total,
    backend = DefaultThermodynamicsBackend(),
)
    name = get(
        Dict(:longwave => "thllwtend", :shortwave => "thlswtend", :total => "thltend"),
        band,
    ) do
        error("No radiative heating for `$band`; try :longwave, :shortwave or :total")
    end
    raw(v) = read_variable(ds, v; translate_units = false)
    f = raw(name)
    return dales_radiative_heating(;
        f.z, f.time, tendency = f.data, presh = raw("presh").data,
        rhof = raw("rhof").data, zt = raw("zt").data, zm = raw("zm").data, backend,
    )
end

function dales_radiative_heating(;
    z::AbstractVector,
    time::AbstractVector,
    tendency::AbstractArray,
    presh::AbstractArray,
    rhof::AbstractArray,
    zt::AbstractArray,
    zm::AbstractArray,
    backend = DefaultThermodynamicsBackend(),
)
    p = pressure_from_face(presh, rhof, zt, zm; backend)
    return (; z, time, data = tendency .* exner.(backend, p), units = "K s^-1")
end

"""
    dales_fall_speed(species, date; root, q_min)

Mass-weighted fall speed [m/s] of `:ice`, `:snow`, `:rain` or `:graupel`, as the
reference realized it.

`<species>_rate` is DALES's `sed_q/ρ` — a mixing ratio times a fall speed, whatever
the archive's `kg/m2` label says — so dividing out the mixing ratio leaves the
speed. `NaN` where there is too little of the species for the ratio to mean
anything.
"""
function dales_fall_speed(
    species::Symbol,
    date;
    root = data_root(),
    q_min::Real = 1.0e-8,
)
    raw_rate = Dict(
        :ice => "ice_rate", :snow => "snow_rate",
        :rain => "rain_rate", :graupel => "graupel_rate",
    )
    raw_mass = Dict(
        :ice => "sv008", :snow => "sv010", :rain => "sv002", :graupel => "sv012",
    )
    haskey(raw_rate, species) ||
        error("No fall speed for `$species`; try :ice, :snow, :rain or :graupel")
    rate = read_variable(raw_rate[species], date; root, translate_units = false)
    q = read_variable(raw_mass[species], date; root, translate_units = false).data
    return dales_fall_speed(; rate.z, rate.time, rate = rate.data, q, q_min)
end

function dales_fall_speed(;
    z::AbstractVector,
    time::AbstractVector,
    rate::AbstractArray,
    q::AbstractArray,
    q_min::Real = 1.0e-8,
)
    return (; z, time, data = ifelse.(q .> q_min, rate ./ q, NaN), units = "m s^-1")
end

"""
    surface_heat_fluxes(date; root)

`(; time, hfss, hfls)` [W m^-2], upward positive, from the reference's own surface
kinematic fluxes.

`wthls` and `wqts` are the subfilter θ_l and total-water fluxes at the lowest
face, so the energy fluxes are `ρ c_p wθ_l` and `ρ L_v wq_t`. DALES computes these
itself at `isurf = 2`; `scm_in`'s `sfc_*_flx` are netCDF fill and are not them.
"""
function surface_heat_fluxes(date; root = data_root())
    return open_archive(:profiles, date; root) do ds
        surface_heat_fluxes(ds)
    end
end

function surface_heat_fluxes(ds::NC.NCDataset)
    f = surface_fluxes(ds; resolved = false)
    return (; f.time, f.hfss, f.hfls)
end

"""
    column_water_path(q, ρ, faces)

`∫ ρ q dz` [kg m^-2].

`q` and `ρ` are one column as `AbstractVector`s, giving a scalar, or `(level, time)`
`AbstractMatrix`es, giving one value per time. `faces` are the `nz + 1` cell faces [m].

A water path is a *derived* quantity on both sides of a comparison, never a stored
one: the reference's own bars were integrated by DALES over its 286 levels with
its `ρ` and `Δz`, a model's `lwp` over the model's levels, so
differencing them mixes a physical difference with an integration one. Build both
with this, from profiles on one grid.
"""
function column_water_path(q::AbstractVector, ρ::AbstractVector, faces::AbstractVector)
    length(ρ) == length(q) ||
        error("Got $(length(q)) mixing ratios for $(length(ρ)) densities.")
    _check_faces(faces, length(q))
    return _column_integral(q, ρ, faces)
end

column_water_path(q::AbstractMatrix, ρ::AbstractMatrix, faces::AbstractVector) =
    column_water_path!(
        similar(q, promote_type(eltype(q), eltype(ρ), eltype(faces)), size(q, 2)),
        q, ρ, faces,
    )

"""
    column_water_path!(out, q, ρ, faces)

[`column_water_path`](@ref) for a `(level, time)` `q` and `ρ`, written into `out`, one
value per time. Allocates nothing.
"""
function column_water_path!(
    out::AbstractVector, q::AbstractMatrix, ρ::AbstractMatrix, faces::AbstractVector,
)
    size(ρ) == size(q) ||
        error("Got $(size(q)) mixing ratios and $(size(ρ)) densities.")
    length(out) == size(q, 2) ||
        error("Got $(length(out)) slots for $(size(q, 2)) times.")
    _check_faces(faces, size(q, 1))
    for t in axes(q, 2)
        out[t] = _column_integral(view(q, :, t), view(ρ, :, t), faces)
    end
    return out
end

function _check_faces(faces::AbstractVector, nz::Integer)
    length(faces) == nz + 1 || error(
        "A column of $nz cells needs $(nz + 1) faces, got $(length(faces)).",
    )
    return nothing
end

# the cell depth is formed per level rather than as a `diff`, which would allocate
_column_integral(q, ρ, faces) =
    sum(q[k] * ρ[k] * (faces[k + 1] - faces[k]) for k in eachindex(q))
