"""
    constants.jl

Ensemble-wide clocks, namelist physics (used vs placeholders), and ice-init diameters.
None of this needs a NetCDF or the artifact. The SB3 parameters are `microphysics.jl`.
"""

# --- Clocks ----------------------------------------------------------------- #

"""Published Zenodo `namoptions` / `profiles.001.nc` run length [s]."""
const PUBLISHED_RUNTIME_S = 7200

"""Paper protocol run length [s] (Schnierstein et al. 2024 §2.3.1; 3 h)."""
const PAPER_RUNTIME_S = 10800

"""First `profiles.001.nc` output time [s]."""
const PROFILES_T0_S = 300

"""`profiles.001.nc` output interval [s], `&namgenstat timeav`."""
const PROFILES_DT_S = 300

"""Published profile times: `300:300:7200`."""
const PROFILES_TIME = PROFILES_T0_S:PROFILES_DT_S:PUBLISHED_RUNTIME_S

"""`tmser.001.nc` output interval [s], `&namtimestat dtav`."""
const TMSER_DT_S = 60

"""Fielddump interval [s], `&namfielddump dtav`, for this repo's 3 h regeneration."""
const FIELDDUMP_DT_S = 1800

"""Paper Appendix C evaluation time [s] (1.5 h)."""
const EVALUATION_S = 5400

"""Scoring against the published Zenodo profiles sits in this closed interval [s]."""
const ZENODO_SCORING_WINDOW_S = (PROFILES_T0_S, PUBLISHED_RUNTIME_S)

"""
    t_end(case)

Run length [s] used for comparison against the published archive:
[`PUBLISHED_RUNTIME_S`](@ref) (7200), not a namelist read and not the paper's 3 h.
"""
t_end(::MOSAiCAYiLCase) = PUBLISHED_RUNTIME_S

# --- Regeneration fielddump ----------------------------------- #

"""`&namfielddump khigh`: vertical levels written to fielddump."""
const FIELDDUMP_NZ = 200


# --- scm_in global attributes that are the same on all 190 days -------------- #

"""
`N` [m^-3] of the Meyers ice-nucleus formula, `scm_in`'s `in_n_inuc`.

DALES reads it as `N_inuc` and forms `n = N exp(a + b min(s_ice, s_lim)) / rho`
(`modbulkmicro3.f90:3648`). The per-day Fletcher coefficients are
[`inp_fletcher_n`](@ref) and [`inp_fletcher_b`](@ref).
"""
const INP_MEYERS_N = 1000.0

"""
`scm_in`'s `in_a_inuc` and `in_b_inuc`, which DALES assigns and never reads.

They reach `a_inuc`/`b_inuc` (`modbulkmicro3.f90:147-148`), but the nucleation rate is
formed from the module's own `a_M92`/`b_M92` (`:3648-3649`, `:3690-3691`, `:3741-3742`), so
changing them changes nothing. Recorded because they describe the archive, not the run.
"""
const INP_MEYERS_AB_UNUSED = (a = -0.639, b = 12.96)

"""`scm_in` soil moisture bounds [m^3/m^3]: `wilting_point` and `field_capacity`."""
const SOIL_MOISTURE_BOUNDS = (wilting_point = 0.1715, field_capacity = 0.32275)

"""The window [h UTC] each day's forcing is a composite average over."""
const COMPOSITE_WINDOW_UTC = (5.0, 11.0)

# --- Ice initialization diameters ------------------------------------------- #

"""Paper §2.3.2: ice placed at 55 μm."""
const PAPER_ICE_INIT_DIAMETER_M = 55.0e-6

"""AYiL DALES `d_ci` default used by the runs that wrote the archive [m]."""
const DALES_D_CI_M = 60.0e-6

# --- Namelist: used on 190/190 days ----------------------------------------- #

"""
Namelist / Fortran-default values that DALES actually used on every archived day.

`tb_minzinv` / `tb_maxzinv` are Fortran defaults, absent from the namelists.
Placeholders DALES overwrote from `scm_in` (`xlat`, `xlon`, `z0mav`, `z0hav`,
`albedoav`) must not be used as physics; per-day values are the day-scalar table.
"""
const NAMELIST = (;
    tb_taunudge = 10800.0,
    tb_zmidnudge = 300.0,
    tb_zminnudge = -1.0,           # diagnosed-inversion mode
    tb_minzinv = 100.0,            # Fortran default
    tb_maxzinv = 5000.0,           # Fortran default
    qtthres = 1.0e-6,
    iradiation = 1,
    l_radfullice = true,
    lcnstzenithtime = true,
    cnstzenithtime = 11,
    isurf = 2,
    l_surficefrac = true,
    larcticstab = true,
    lmostlocal = false,
    imicro = 11,
    nsv = 12,
    emissurf = 0.985,
    nc0 = 1.0e7,
    lcoriol = true,
    lmomsubs = false,
    llsadv = false,
    scm_ls_advection_zero = true,
)

"""
Namelist entries written on all 190 days and overwritten from `scm_in` every substep
(`modtimedep.f90:206-208`, `:522-538`), as `(group, key) => the accessor carrying the value
the run used`.

Not physics: `albedoav = 0.06` is an open-ocean albedo that applies to none of these days.
`thls` is a *potential* temperature — `modtestbed.f90:574-578` divides the `scm_in` skin
temperature by `Π(ps)` — so its accessor is [`surface_pottemp`](@ref), not [`t_skin`](@ref).
"""
const NAMELIST_PLACEHOLDERS = Dict{Tuple{Symbol, Symbol}, Symbol}(
    (:domain, :xlat) => :latitude,
    (:domain, :xlon) => :longitude,
    (:namsurface, :z0mav) => :mom_rough,
    (:namsurface, :z0hav) => :heat_rough,
    (:namsurface, :albedoav) => :albedo,
    (:namsurface, :seaicefrct) => :sea_ice_frct,
    (:physics, :ps) => :ps,
    (:physics, :thls) => :surface_pottemp,
)

"""
    xday(case)

Day of year the run's insolation used (`&domain xday`), which is `Dates.dayofyear` on
190/190 days. The only namelist key that varies between days.
"""
xday(c::MOSAiCAYiLCase) = Dates.dayofyear(c.date)


"""
    nudging_parameters(case)

The DALES testbed nudging parameters used on every archived day: relaxation
timescale `τ` [s], ramp depth [m] above the diagnosed inversion, and `z_min` [m]
(`z_min < 0` is DALES's flag for diagnosed-inversion mode).

Taken from [`NAMELIST`](@ref), not from a namelist read: the three numbers
are identical on 190/190 days.
"""
nudging_parameters(::MOSAiCAYiLCase) = (;
    timescale = NAMELIST.tb_taunudge,
    ramp_depth = NAMELIST.tb_zmidnudge,
    z_min = NAMELIST.tb_zminnudge,
)

"""
    dales_tke_seed(z::FT; e12_min::FT = FT(DALES_CONSTANTS.e12_min), decay_length::FT = FT(50)) where {FT}

DALES's cold-start turbulence seed as a specific kinetic energy [m²/s²]:
`(e12_min + exp(-z / decay_length))²`, from `modstartup.f90:449`.
"""
dales_tke_seed(z::FT; e12_min::FT = FT(DALES_CONSTANTS.e12_min), decay_length::FT = FT(50)) where {FT} = (e12_min + exp(-z / decay_length))^2

"""
    reference_datetime(case; hour = 11)

The case's reference time: `cnstzenithtime` UTC on its date — the hour the frozen
zenith angle and the initializing radiosonde both refer to.
"""
reference_datetime(c::MOSAiCAYiLCase; hour::Integer = NAMELIST.cnstzenithtime) = Dates.DateTime(c.date) + Dates.Hour(hour)
