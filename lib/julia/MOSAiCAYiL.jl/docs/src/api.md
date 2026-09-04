# API

```@meta
CurrentModule = MOSAiCAYiL
```

## The catalog

```@docs
MOSAiCAYiLCase
case
MOSAiCAYiL_dates
n_cases
date_string
date_index
is_MOSAiCAYiL_date
parse_MOSAiCAYiL_date
case_name
```

## Paths and the artifact

```@docs
data_root
artifact_root
artifact_installed
data_available
available_dates
day_dir
day_files
```

## The namelist

```@docs
namelist
NamelistGroups
namelist_value
namelist_groups_with
namelist_placeholder
NAMELIST_PLACEHOLDERS
namelist_latitude
namelist_longitude
```

## Reading

```@docs
read_variable
open_archive
ρ_power
variable_product
physical_name
dales_variable_attributes
spelled_units
mphys_name
samptend_name
testbed_forcing
dales_slab_column
dales_rhof
les_density
les_faces
scm_in_air_density
```

### Derived

```@docs
dales_radiative_heating
dales_fall_speed
surface_heat_fluxes
column_water_path
column_water_path!
```

### The naming and unit tables

```@docs
SCM_IN
TMSER
BULKMICROSTAT3
SB3_TO_PHYSICAL
SB3_DESCRIPTION
SB3_SPECIES
MPHYS_PROCESS
MPHYS_DIAGNOSTIC
THETA_PROCESS
SAMPTEND_FIELD
SAMPTEND_PROCESS
SAMPTEND_SAMPLES
SAMPTEND_IRREGULAR
AMBIGUOUS_RAW_NAMES
NUMBER_UNITS
MISLABELLED_UNITS
UNIT_SPELLINGS
SCM_IN_LONG_NAME
SCM_IN_LEVEL_AXIS
```

## The 3D fields

```@docs
open_fielddump
load_fielddump
close_fielddump
FielddumpVariable
FielddumpTile
FielddumpHandles
fielddump_tiles
fielddump_decomposition
fielddump_physical_name
fielddump_units
fielddump_long_name
DerivedFielddumpVariable
fielddump_thermodynamics
```

## Serialization

```@docs
write_forcing_file
read_forcing_file
FORCING_PROFILE_UNITS
FORCING_SURFACE_UNITS
```

## Extensions

Methods appear when the corresponding package is loaded.

### Zarr

```@docs
open_zarr
load_zarr
write_zarr
```

### Distributed and OhMyThreads

```@docs
pmap
pforeach
pmapreduce
addprocs
tmap
tmap!
tforeach
tmapreduce
treduce
tcollect
```

### ClimaAtmos

```@docs
ClimaAtmos_MOSAiCAYiL_params
ClimaAtmos_MOSAiCAYiL_toml_overrides
ClimaAtmos_MOSAiCAYiL_callback_kwargs
ClimaAtmosMOSAiCAYiLForcing
ClimaAtmosMOSAiCAYiLSetup
ClimaAtmosMOSAiCAYiLInsolation
ClimaAtmos_MOSAiCAYiL_grid
ClimaAtmos_MOSAiCAYiL_z
ClimaAtmos_MOSAiCAYiL_scm_coriolis
ClimaAtmos_MOSAiCAYiL_field
ClimaAtmos_MOSAiCAYiL_translated_names
ClimaAtmos_MOSAiCAYiL_register_condensate_totals!
climaatmos_pkg_version
```

## Per-day facts

```@docs
day_scalars
day_metadata
latitude
longitude
albedo
albedo_snow
snow
mom_rough
heat_rough
sea_ice_frct
t_skin
t_skin_ocean
t_skin_seaice
open_sst
ps
n_ccn
scm_in_levels
inversion_height
cloud_top
tskin_obs
tskin_seaice_correction
inp_fletcher_n
inp_fletcher_b
xday
CLOUD_TOP_M
CLOUD_TOP_UNDETERMINED
```

## The ice filters

```@docs
best_dates
best_simulation_top
best_z_maxs
get_cloud_tops
ice_fields
ice_size_floor
ice_fall_speed_floor
identity_filter
extreme_n_ice
CANONICAL_ICE_FILTERS
BEST_SIMULATION_TOP_F
RAW_BEST_SIMULATION_TOP_C
RAW_BEST_SIMULATION_TOP_F
z_max_below_flagged
trim_top_adjacent_cloud
has_cloud_below
```

## Thermodynamics

```@docs
DefaultThermodynamicsBackend
AbstractThermodynamicsBackend
saturation_vapor_pressure
saturation_vapor_pressure_liq
saturation_vapor_pressure_ice
tetens_saturation_vapor_pressure
q_vap_saturation
q_vap_saturation_liq
q_vap_saturation_ice
q_vap_saturation_from_pressure
surface_q_vap_saturation
saturation_specific_humidity_from_pT
saturation_mixing_ratio_from_pT
liquid_fraction
equilibrium_condensate
saturation_adjust_pθq
exner
dry_pottemp
liquid_pottemp
liquid_ice_pottemp
temperature_from_liquid_pottemp
temperature_from_liquid_ice_pottemp
virtual_temperature
air_density
latent_heat_vapor
latent_heat_sublim
latent_heat_generic
molmass_ratio
R_d
R_v
cp_d
grav
p_ref
T_freeze
T_mixed_high
T_mixed_low
L_v0
L_s0
e_ref
a_liquid
b_liquid
a_ice
b_ice
```

## Surface

```@docs
surface_temperature
surface_pottemp
qseaicefrctsurf
surface_state
forcing_with_surface
interpolate_forcing
```

## The surface layer

```@docs
psim
psih
phim
phih
STABILITY
surface_virtual_pottemp
bulk_richardson
obukhov_length
drag_coefficients
surface_layer_fluxes
dales_surface_layer
```

## The grid

```@docs
LES_FACES
LES_CENTRES
LES_TOP_FACE
LES_Z_CENTRE_BOTTOM
LES_Z_CENTRE_TOP
PRODUCTION_GRID
TEST_GRID
STRETCH
stretch_dz
stretch_centres
stretch_faces
face_above_center
native_faces
z_max
vertical_metrics
pressure_from_face
pressure_fromztop
```

## The anelastic base state

```@docs
anelastic_base_density
anelastic_base_state
read_baseprof
STANDARD_ATMOSPHERE
ARCHIVE_BASEPROF_DATE
```

## What every scheme ran with

```@docs
SUBGRID
ADVECTION
ADVECTION_SCHEMES
scalar_advection_schemes
SPONGE
sponge_base_level
sponge_damping_rate
SURFACE_LAYER
PERTURBATIONS
CORIOLIS
coriolis_parameters
RADIATION
```

## Radiation

```@docs
CLOUD_LIQUID_OPTICS
cloud_liquid_optics
RADIATION_BANDS
SOLAR_TOTAL_POWER
TRACE_GAS_CONCENTRATIONS
RADIATION_GASES
read_ckd
```

## Diagnostics

```@docs
dales_nudging_rate
dales_forcing_tendency
surface_fluxes
flux_partition
turbulence_kinetic_energy
toa_radiation
water_paths
surface_precipitation
phase_partition
```

## Nudging

```@docs
nudging_parameters
inversion_height(::Any, ::Any, ::Any, ::Any)
nudge_ramp
INVERSION_SEARCH_MIN
INVERSION_SEARCH_MAX
DRY_AIR_NUDGE_THRESHOLD
```

## Constants

```@docs
DALES_CONSTANTS
NAMELIST
PUBLISHED_RUNTIME_S
PAPER_RUNTIME_S
EVALUATION_S
PROFILES_T0_S
PROFILES_DT_S
PROFILES_TIME
TMSER_DT_S
FIELDDUMP_DT_S
FIELDDUMP_NZ
ZENODO_SCORING_WINDOW_S
t_end
PAPER_ICE_INIT_DIAMETER_M
DALES_D_CI_M
INP_MEYERS_N
INP_MEYERS_AB_UNUSED
SOIL_MOISTURE_BOUNDS
COMPOSITE_WINDOW_UTC
dales_tke_seed
reference_datetime
SB3_PARTICLES
SB3_VENTILATION
SB3_PHYSICS
SB3_SWITCHES
SB3_THRESHOLDS
SB3_WARM_RAIN
SB3_SEDIMENTATION
SB3_NUCLEATION
SB3_FREEZING
SB3_COLLISION
SB3_CONVERSION
SB3_MULTIPLICATION
SB3_MELTING
SB3_UNUSED
SB3_SCALAR_INDEX
SB3_N_SCALARS
sb3_mean_mass
sb3_diameter
sb3_fall_speed
sb3_sedimentation_speed
sb3_max_fall_speed
sb3_present
SB3_INCLUSIVE_PRESENCE
sb3_reynolds
sb3_ventilation
sb3_rain_dsd
sb3_collision_pair
```

### The constants DALES derives at start-up

```@docs
SB3_DERIVED
SB3_COLLISION_PAIRS
lacz_gamma
sb3_cons_mmt
sb3_cons_v
sb3_avent
sb3_bvent
sb3_delta
sb3_theta
sb3_cons_lbd
```

### Process rates

```@docs
sb3_limit
sb3_growth_parameter
sb3_autoconversion_rate
sb3_accretion_rate
sb3_cloud_self_collection_rate
sb3_rain_self_collection_rate
sb3_rain_breakup_rate
sb3_rain_evaporation_rate
sb3_ice_supersaturation
sb3_deposition_rate
sb3_deposition_correction
sb3_collision_efficiency
sb3_collision_rates
sb3_sticking_efficiency
sb3_enhanced_melting_coefficient
sb3_ice_nucleus_target
sb3_homogeneous_nucleation_rate
sb3_heterogeneous_nucleation_rate
sb3_droplet_freezing_rate
sb3_ice_multiplication_rate
sb3_rain_terminal_velocity
sb3_sedimentation_flux
sb3_sedimentation_substeps
```

## Index

```@index
```
