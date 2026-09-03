"""
    microphysics.jl

The Seifert–Beheng two-moment scheme the AYiL runs used, `imicro = 11`
(`modmicrodata3.f90`, `modmicrodata.f90`, `modbulkmicro3.f90`).

Species are keyed by the package's physical names throughout —
`:cloud_liquid`, `:rain`, `:cloud_ice`, `:snow`, `:graupel` — the same names
[`SB3_TO_PHYSICAL`](@ref) resolves the twelve scalars onto.

Every value here is a literal of the Fortran, cited to its line. What DALES *derives* from
these at start-up is a separate matter: those constants are Γ-function ratios, and
`SB3_DERIVED` carries them.
"""

"""
Which scalar slot each SB3 quantity occupies, `modmicrodata3.f90:106-118`.

`sv004` (`in_in`, the INP number) is carried by no process — see [`SB3_UNUSED`](@ref).
"""
const SB3_SCALAR_INDEX = (;
    n_rain = 1, q_rain = 2, n_cloud_liquid = 3, n_inp = 4, q_cloud_liquid = 5,
    n_ccn = 6, n_cloud_ice = 7, q_cloud_ice = 8, n_snow = 9, q_snow = 10,
    n_graupel = 11, q_graupel = 12,
)

"""Number of prognostic SB3 scalars, `sb3nsv` (`modmicrodata3.f90:119`)."""
const SB3_N_SCALARS = 12

"""
Single-particle parameters of the five SB3 species, Seifert & Beheng Table 1 as
`modmicrodata3.f90:196-236` declares them.

Mean particle mass `x` [kg] maps to diameter as `D = a x^b` and to fall speed as
`v = α x^β (ρ_ref/ρ)^γ`, with `x` clamped to `[x_min, x_max]`. `c` is the capacitance the
deposition rate divides `4π` by. `ν` and `μ` are the shape parameters of the generalised
gamma distribution, and `σ_v` its fall-speed variance (`:328-332`).

`μ = 0.33333` and `ν_rain = −0.66667` are DALES's truncated decimals and are **load-bearing**:
at exact `1/3` and `−2/3` the rain ventilation argument `(ν + b)/μ` is exactly `−1`, a pole of
Γ, and `aven_0r` becomes infinite.

Rain's bounds are `modmicrodata.f90`'s `xrmin = xcmax` and `xrmax`, not
`modmicrodata3.f90`'s `x_hr_bmin` — those are what `integrals_bulk3` and `sedim_rain3` read.
"""
const SB3_PARTICLES = (;
    cloud_liquid = (;
        a = 0.124, b = 0.33333, c = 2.0, α = 3.75e5, β = 0.66667, γ = 1.0,
        ν = 1.0, μ = 1.0, σ_v = 0.0,
        x_min = 4.20e-15, x_max = 1.01e-11, q_min = 1.0e-14,
    ),
    rain = (;
        a = 0.124, b = 0.33333, c = 2.0, α = 159.0, β = 0.266, γ = 0.5,
        ν = -0.66667, μ = 0.33333, σ_v = 0.0,
        x_min = 2.6e-10, x_max = 5.0e-6, q_min = 1.0e-14,
    ),
    cloud_ice = (;
        a = 0.217, b = 0.302115, c = 3.14159, α = 41.9, β = 0.36, γ = 0.5,
        ν = 0.0, μ = 0.33333, σ_v = 0.2,
        x_min = 1.0e-12, x_max = 1.0e-7, q_min = 1.0e-14,
    ),
    snow = (;
        a = 8.156, b = 0.526, c = 2.0, α = 27.7, β = 0.216, γ = 0.5,
        ν = 1.0, μ = 0.33333, σ_v = 0.2,
        x_min = 1.73e-9, x_max = 1.0e-6, q_min = 1.0e-14,
    ),
    graupel = (;
        a = 0.190, b = 0.323, c = 2.0, α = 40.0, β = 0.230, γ = 0.5,
        ν = 1.0, μ = 0.33333, σ_v = 0.0,
        x_min = 2.6e-10, x_max = 1.0e-4, q_min = 1.0e-14,
    ),
)

"""
Ventilation coefficients, `modmicrodata3.f90:285-292`.

Only `b_v` is live: `calc_avent` ignores its `a_v` argument and uses the module constant
`avf = 0.78` (`modmicrodata.f90:114`), so cloud ice ventilates on 0.78 rather than its own
0.86 — see [`SB3_UNUSED`](@ref). Cloud liquid does not ventilate.
"""
const SB3_VENTILATION = (;
    rain = (; b_v = 0.308),
    cloud_ice = (; b_v = 0.208),
    snow = (; b_v = 0.308),
    graupel = (; b_v = 0.308),
)

"""
Physical constants the SB3 rates share.

`rlvi`, `rlme`, `c_water` and `ρ_ref` are `modmicrodata3.f90:163-166`; the transport
coefficients and `avf` are `modmicrodata.f90:106-119`. `c_water` is liquid water despite the
Fortran comment calling it water vapour.

`T_3 = 273.15` is SB3's own freezing point and is **not** `DALES_CONSTANTS.T_melt`, which is
273.16.
"""
const SB3_PHYSICS = (;
    L_s = 2.834e6,
    L_f = 3.337e5,
    c_water = 4.186e3,
    ρ_ref = 1.225,
    T_3 = 273.15,
    D_v = 2.4e-5,
    K_t = 2.5e-2,
    ν_air = 1.41e-5,
    Sc = 0.71,
    a_v = 0.78,
    ε_0 = 1.0e-20,
    ρ_water = 998.0,
    k1nuc = 1.58,
    k2nuc = 0.72,
)

"""
Every logical of `modmicrodata3.f90:34-67` at the value the AYiL runs used.

`&nammicrophysics` sets only `imicro = 11` and `&nambulk3` only `l_setccn`, so every switch
here is a source default. `l_sb_classic = true` selects the Seifert & Beheng branch of
autoconversion, accretion and rain sedimentation throughout.

`l_setinp` is **not** the flag that supplies this ensemble's per-day ice-nucleus numbers —
that is `ltb_setinp` in `modtestbed`, which defaults true and overwrites `N_inuc`,
`N_inuc_R` and `b_inuc_R` from `scm_in`.
"""
const SB3_SWITCHES = (;
    l_sb_classic = true, l_sb_dumpall = true, l_sb_all_or = true,
    l_setclouds = true, l_setccn = false, l_setinp = false,
    l_corr_neg_qt = true, l_icenucle = true, l_hetfreeze = true, l_icemulti = true,
    l_sb_dbg = false, l_sb_dbg_extra = false,
    l_sb_lim_aggr = true, l_snow = true, l_sb_stickyice = false,
    l_sb_clnuc_first = true, l_sb_conv_par = true,
    l_c_ccn = false, l_c_inp = true,
    l_sb_nuc_sat = false, l_sb_sat_max = true, l_sb_nuc_expl = true, l_sb_nuc_diff = true,
    l_sb_inuc_sat = false, l_sb_inuc_expl = false, l_sb_cl_noinuc = false,
    l_sb_reisner = true,
    l_lognormal = false, l_mur_cst = false,
)

"""
Mixing-ratio and number thresholds below which a process is skipped,
`modmicrodata3.f90:122-160` and `modmicrodata.f90:54-58`.

`q_min` is `1e-14` for all five species. `qcmin = 1e-7` is the legacy mask of the
one-moment scheme and is a different, much larger threshold.
"""
const SB3_THRESHOLDS = (;
    q_min = 1.0e-14,
    n_c_min = 1.0,
    q_c_legacy_min = 1.0e-7,
    q_rain_legacy_min = 1.0e-13,
    ssice_min = 1.0e-15,
    ssice_lim = 0.1,
    cc_min_ratio = 0.2,
    rem_n_cl_min = 0.1,
    rem_n_ci_min = 0.2,
    rem_n_hr_min = 0.1,
    rem_n_hs_min = 0.3,
    rem_n_min_cv = 0.3,
    eps_hprec = 1.0e-8,
    ε_0 = 1.0e-20,
)

"""
Warm-rain constants: autoconversion, accretion, self-collection and break-up, the rain
size distribution and rain evaporation.

`k_cc`, `k_cr` and `kappa_br` are `modmicrodata3.f90:170-172`; the rest are
`modmicrodata.f90:85-158`. `x_s = xcmax` is the mass separating the cloud and rain parts of
the distribution, and the autoconversion kernel is `k_cc/(20 x_s)`.

`D_eq` and `k_br` are the break-up parameters of `modmicrodata.f90:157-158`; `dvrlim` and
`dvrbiglim` the diameters that switch it on.
"""
const SB3_WARM_RAIN = (;
    k_cc = 4.44e9,
    k_cr = 5.25,
    k_rr = 7.12,
    kappa_r = 60.7,
    kappa_br = 2.3e3,
    k_1 = 4.0e2,
    k_2 = 0.70,
    k_l = 5.0e-5,
    x_s = 2.6e-10,
    D_eq = 1.1e-3,
    k_br = 1000.0,
    dvrlim = 0.35e-3,
    dvrbiglim = 0.9e-3,
    N_0min = 2.5e5,
    N_0max = 2.0e7,
    lbdr_min = 1.0e3,
    lbdr_max = 1.0e4,
    c_ccn_ev_r = 0.0,
)

"""
Sedimentation constants, `modmicrodata3.f90:237-241` and `:154`.

The terminal-velocity coefficients are the `*_tvsbc` set, which `sedim_rain3` reads on the
`l_sb_classic` branch together with a `(ρ_ref/ρ)^(1/2)` correction
(`modbulkmicro3.f90:4121-4124`). `modmicrodata.f90`'s `a_tvsb`/`b_tvsb`/`c_tvsb`, with
`b = 9.8` and no density correction, belong to the other branch and are dead here.

`w_fall_max` is `d_wfallmax_hr` for rain, cloud liquid, ice and snow; graupel instead takes
`max(c_v_g0, c_v_g1)` from the derived fall-speed moments.
"""
const SB3_SEDIMENTATION = (;
    a_tvsbc = 9.65,
    b_tvsbc = 10.3,
    c_tvsbc = 600.0,
    split_factor = 1.5,
    w_fall_max = 9.9,
)

"""
Droplet and ice nucleation, `modmicrodata3.f90:246-260` and `:341-351`.

Droplet nucleation is the Seifert & Beheng CCN activation with `κ = 0.462`; `sat_min` and
`sat_max` are supersaturations in **percent**.

Ice nucleation is Meyers (1992) `n = N_inuc exp(a_M92 + b_M92 min(s_i, ssice_lim))/ρ`,
followed by the Reisner (1998) clamp and a cap at `n_i_max`. The AYiL runs overwrote
`N_inuc`, `N_inuc_R` and `b_inuc_R` per day from `scm_in`, so `N_M92`, `N_R98` and `b_R98`
here are the module defaults rather than what ran — [`inp_fletcher_n`](@ref) and
[`inp_fletcher_b`](@ref) carry the per-day values, and `n_i_max` came from `&nambulk3`.
"""
const SB3_NUCLEATION = (;
    kappa_ccn = 0.462,
    sat_min = 1.0e-5,
    sat_max = 1.1,
    x_cnuc = 1.0e-12,
    x_inuc = 1.0e-12,
    N_M92 = 1.0e3,
    a_M92 = -0.639,
    b_M92 = 12.96,
    tmp_inuc = 268.15,
    n_i_max = 200.0e3,
    n_i_max_default = 1100.0,
    N_R98 = 0.01,
    c_R98 = 246.15,
    b_R98 = 0.6,
    a1_R98 = 0.1,
    a2_R98 = 10.0,
    Nc0 = 1.0e7,
    Nc0_default = 70.0e6,
)

"""
Freezing constants.

Homogeneous freezing is Cotton & Field (2002), `modmicrodata3.f90:263-274`; the rate carries
an extra hard-coded `1e3` gram-to-kilogram factor at its three branches
(`modbulkmicro3.f90:5921`, `:5924`, `:5926`).

Heterogeneous freezing is `J = A_het exp(B_het (T_3 − max(tlimhetfreeze, T)) − 1)`
(`:277-278`). `tlimhetfreeze = 258.15` came from `&nambulk3`; the module default is 238.0.
"""
const SB3_FREEZING = (;
    A_het = 0.2,
    B_het = 0.65,
    tlimhetfreeze = 258.15,
    tlimhetfreeze_default = 238.0,
    C_CF02 = -7.36,
    B_CF02 = -2.996,
    CC_CF02 = -243.15,
    tmp_lim1_CF02 = 243.15,
    tmp_lim2_CF02 = 208.15,
    offset_CF02 = 273.15,
    C_20_CF02 = -243.4,
    B_21_CF02 = -14.75,
    B_22_CF02 = -0.307,
    B_23_CF02 = -0.00287,
    B_24_CF02 = -102.0e-7,
    C_30_CF02 = 25.63,
)

"""
Collision, collection and riming constants, `modmicrodata3.f90:305-338`.

`E_ii_m = 0.1` is superseded: `ice_aggr3` sets the collection efficiency to `E_ee_m = 1.0`
(`modbulkmicro3.f90:6031`), a factor of ten — see [`SB3_UNUSED`](@ref).

Sticking efficiency follows `exp(B_stick_ii (T + stick_off) + C_stick_ii)`, capped at
`E_ii_maxst` for ice and `E_ss_maxst` for snow. `k_enhm = c_water/L_f` is the enhanced-melting
coefficient.
"""
const SB3_COLLISION = (;
    E_i_m = 0.8,
    E_s_m = 0.8,
    E_g_m = 1.0,
    E_er_m = 1.0,
    E_ee_m = 1.0,
    E_ii_m = 0.1,
    E_is_m = 1.0,
    E_gg_s = 0.0,
    E_gi_s = 0.0,
    c_E_o_s = 1.0,
    stick_off = -273.15,
    B_stick = 0.09,
    B_stick_ii = 0.08059,
    C_stick_ii = -0.7,
    E_ii_maxst = 0.2,
    E_ss_maxst = 0.1,
    D_c_a = 15.0e-6,
    D_c_b = 40.0e-6,
    D_i_a = 75.0e-6,
    D_i_b = 398.0e-6,
    D_i0 = 150.0e-6,
    D_crit_ii = 100.0e-6,
    q_crit_ii = 1.0e-6,
)

"""
Partial conversion of rimed ice and snow to graupel, `modmicrodata3.f90:189` and
`:279-336` (`conv_partial3`).
"""
const SB3_CONVERSION = (;
    rhoeps = 900.0,
    al_0ice = 0.68,
    al_0snow = 0.01,
    D_mincv_ci = 500.0e-6,
    D_mincv_hs = 500.0e-6,
    x_ci_cvmin = 0.1e-9,
    x_hs_cvmin = 0.1e-9,
)

"""
Hallett–Mossop rime splintering, `modmicrodata3.f90:296-301`.

`ice_multi3` applies it to six riming channels; the splinter mass is `x_ci_bmin`.
"""
const SB3_MULTIPLICATION = (;
    c_spl_hm74 = 3.5e8,
    tmp_min_hm74 = 265.0,
    tmp_opt_hm74 = 268.0,
    tmp_max_hm74 = 270.0,
    x_ci_spl = 1.0e-12,
    rem_q_e_hm = 0.5,
)

"""
Melting, evaporation of the ice species, and CCN recovery, `modmicrodata3.f90:342` and
`modbulkmicro3.f90:9271-9422`.

`c_rec_cc` is how many evaporated cloud droplets return to the CCN pool; `c_ccn_ev_r = 0.0`
means evaporating rain returns none.
"""
const SB3_MELTING = (; c_rec_cc = 1.0, c_ccn_ev_c = 1.0, c_ccn_ev_r = 0.0)

"""
SB3 quantities that are declared and never reach a rate, with why.

Recorded because a reader comparing this configuration against the Seifert & Beheng papers
will otherwise take them for settings that ran.
"""
const SB3_UNUSED = (;
    a_v_cloud_ice = (; value = 0.86,
        reason = "calc_avent ignores its a_v argument and uses avf = 0.78"),
    a_v_rain = (; value = 0.78, reason = "same; equal to avf by coincidence"),
    c_cloud_liquid = (; value = 2.0, reason = "capacitance; cloud liquid does not deposit"),
    c_rain = (; value = 2.0, reason = "capacitance; rain does not deposit"),
    E_ii_m = (; value = 0.1, reason = "ice_aggr3 uses E_ee_m = 1.0 instead"),
    c_lbdr = (; value = 6.952127722818531,
        reason = "computed as sb3_cons_lbd(μ_rain, ν_snow) and never read"),
    d_wfallmax_hg = (; value = 11.9,
        reason = "commented out; graupel uses max(c_v_g0, c_v_g1)"),
    x_hr_bmin = (; value = 1.0e-10, reason = "superseded by xrmin = 2.6e-10"),
    n_clmax = (; value = 5.0e8, reason = "namelist value read only when l_c_ccn is true"),
    n_inp_slot = (; value = 4, reason = "the INP scalar slot; no process reads it"),
    k_c = (; value = 10.58e9, reason = "non-classic autoconversion kernel"),
    b_tvsb = (; value = 9.8, reason = "non-classic rain terminal velocity"),
    mur0_G09b = (; value = 30.0, reason = "non-classic rain size distribution"),
    c_G09b = (; value = 0.008, reason = "non-classic rain size distribution"),
    exp_G09b = (; value = 0.6, reason = "non-classic rain size distribution"),
    n_h_min = (; value = 1.0e-4, reason = "declared; the rates mask on q_min instead"),
    D_convmin = (; value = 5.0e-4, reason = "superseded by D_mincv_ci and D_mincv_hs"),
    D_s0 = (; value = 150.0e-6, reason = "declared; no rate reads it"),
    D_g0 = (; value = 150.0e-6, reason = "declared; no rate reads it"),
    E_is_m = (; value = 1.0, reason = "declared; coll_sis3 uses E_ee_m"),
    rime_min = (; value = 1.0e-18, reason = "declared; no rate reads it"),
)

"""
    sb3_mean_mass(q, n, particle; ε_0)

Mean particle mass [kg], `q/(n + ε₀)` clamped to the species' `[x_min, x_max]`
(`modbulkmicro3.f90:2473-2632`, the same form for all five species).

Both arguments are per unit *mass*, which is how DALES carries the scalars. `ε₀` is DALES's
own guard against dividing by zero, not a tolerance.
"""
sb3_mean_mass(q::FT, n::FT, p::NamedTuple; ε_0::FT = FT(SB3_PHYSICS.ε_0)) where {FT} =
    clamp(q / (n + ε_0), FT(p.x_min), FT(p.x_max))

"""
    sb3_diameter(x, particle)

Mean diameter [m] from the mean particle mass, `D = a x^b`.
"""
sb3_diameter(x::FT, p::NamedTuple) where {FT} = FT(p.a) * x^FT(p.b)

"""
    sb3_fall_speed(x, ρ, particle; ρ_ref)

Mean fall speed [m/s] from the mean particle mass and the air density,
`v = α x^β (ρ_ref/ρ)^γ`.

This is the **diagnostic** velocity, which carries the density correction. The velocity
sedimentation uses is a different quantity — see `sb3_sedimentation_speed`.
"""
sb3_fall_speed(
    x::FT, ρ::FT, p::NamedTuple; ρ_ref::FT = FT(SB3_PHYSICS.ρ_ref),
) where {FT} = FT(p.α) * x^FT(p.β) * (ρ_ref / ρ)^FT(p.γ)

"""
Species whose presence mask admits a mixing ratio exactly equal to the threshold.

`modbulkmicro3.f90:1312-1370` masks cloud liquid and cloud ice with `≥ q_min` and rain, snow
and graupel with `> q_min`. All five additionally require `n > 0`.
"""
const SB3_INCLUSIVE_PRESENCE = (:cloud_liquid, :cloud_ice)

"""
    sb3_present(q, n, species; q_min)

Whether a species is present at a point, as DALES masks it
(`modbulkmicro3.f90:1312-1370`).

The comparison is `≥` for the two cloud species and `>` for the precipitating ones — see
[`SB3_INCLUSIVE_PRESENCE`](@ref). The number must exceed zero either way.
"""
function sb3_present(
    q::FT, n::FT, species::Symbol; q_min::FT = FT(SB3_PARTICLES[species].q_min),
) where {FT}
    haskey(SB3_PARTICLES, species) || error("`$species` is not an SB3 species.")
    n > zero(FT) || return false
    return species in SB3_INCLUSIVE_PRESENCE ? q >= q_min : q > q_min
end

"""
    sb3_reynolds(D, v; ν_air)

Particle Reynolds number, `D v / ν_air` (`modbulkmicro3.f90:5296`).
"""
sb3_reynolds(D::FT, v::FT; ν_air::FT = FT(SB3_PHYSICS.ν_air)) where {FT} = D * v / ν_air

"""
    sb3_ventilation(N_re, a_vent, b_vent; Sc)

Ventilation factor `a + b · Sc^(1/3) · Re^(1/2)` (`modbulkmicro3.f90:5298`).

`a_vent` and `b_vent` are the `a1`/`b1` of [`SB3_DERIVED`](@ref)`.ventilation` for a mass
tendency, `a0`/`b0` for a number one.
"""
sb3_ventilation(
    N_re::FT, a_vent::FT, b_vent::FT; Sc::FT = FT(SB3_PHYSICS.Sc),
) where {FT} = a_vent + b_vent * Sc^(one(FT) / 3) * sqrt(N_re)

"""
    sb3_rain_dsd(q, n, ρ; particle, p)

The rain size distribution of the `l_sb_classic` branch
(`modbulkmicro3.f90:2472-2492`), as `(; x, D_v, N_0, λ, x_dsd)`.

`x` is the clamped mean mass the diameter and fall speed are taken from; `D_v` is the
volume-mean diameter `(x/πρ_w)^(1/3)`; `N_0` and `λ` are the intercept and slope, each clamped
to [`SB3_WARM_RAIN`](@ref)'s bounds; and `x_dsd` is the mass the distribution itself implies.

The clamping is not uniform, and reproducing it matters: `λ` is formed from the **clamped**
`N_0` while `x_dsd` is formed from the **unclamped** one. `πρ_w` uses DALES's truncated
`3.14159`, not `π`.
"""
function sb3_rain_dsd(
    q::FT, n::FT, ρ::FT;
    particle::NamedTuple = SB3_PARTICLES.rain,
    p::NamedTuple = SB3_WARM_RAIN,
    ε_0::FT = FT(SB3_PHYSICS.ε_0),
    ρ_water::FT = FT(SB3_PHYSICS.ρ_water),
) where {FT}
    πρ_w = FT(3.14159) * ρ_water / 6
    x = clamp(q / (n + ε_0), FT(particle.x_min), FT(particle.x_max))
    D_v = (x / πρ_w)^(one(FT) / 3)
    N_0_raw = ρ * n / D_v
    N_0 = clamp(N_0_raw, FT(p.N_0min), FT(p.N_0max))
    λ = clamp((πρ_w * N_0 / (ρ * q))^FT(0.25), FT(p.lbdr_min), FT(p.lbdr_max))
    x_dsd = clamp(ρ * q * λ / N_0_raw, FT(particle.x_min), FT(particle.x_max))
    return (; x, D_v, N_0, λ, x_dsd)
end
