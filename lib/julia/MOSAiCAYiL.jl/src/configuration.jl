"""
    configuration.jl

What every non-microphysics scheme ran with on all 190 days: the subgrid closure, the
radiation settings, the advection and time stepping, the sponge layer, the surface-layer
switches, the initial perturbations and the Coriolis terms.

Values reach these tables three ways, and the docstrings say which: set in `namoptions`, a
Fortran default the namelist never touches, or computed at init from the others.
"""

"""
Prognostic-TKE (Deardorff) subgrid closure, `modsubgrid.f90`.

The namelist has **no `&NAMSUBGRID` group**, so every input is the Fortran default of
`modsubgriddata.f90:35-51`. `cm`, `ceps`, `ce1` and `ce2` are then recomputed at init
(`modsubgrid.f90:62-70`) and are computed here the same way rather than pinned: the declared
`cm = 0.12`, `ce1 = 0.19` and `ce2 = 0.51` are **not** what ran. `ch2` is recomputed too and
lands back on its declared 2.0.

`sgs_surface_fix` is broadcast (`modsubgrid.f90:128`) but is absent from the `NAMSUBGRID`
list (`:108-109`), so no namelist can reach it and it is always false.
"""
const SUBGRID = let cf = 2.5,
    cn = 0.76,
    ch1 = 1.0,
    Rigc = 0.25,
    Prandtl = 1.0 / 3.0,
    alpha_kolm = 1.5,
    beta_kolm = 1.0

    cm = cf / (2 * pi) * (1.5 * alpha_kolm)^(-1.5)
    ch = 1 / Prandtl
    ceps = 2 * pi / cf * (1.5 * alpha_kolm)^(-1.5)
    ce1 = cn^2 * (cm / Rigc - ch1 * cm)
    (;
        cf, cn, ch1, Rigc, Prandtl, alpha_kolm, beta_kolm,
        cm, ch, ch2 = ch - ch1, ceps, ce1, ce2 = ceps - ce1,
        ekmin = 1.0e-6,
        cs = -1.0,
        nmason = 2.0,
        ldelta = false,
        lmason = false,
        lsmagorinsky = false,
        sgs_surface_fix = false,
    )
end

"""
Radiation settings of the AYiL runs, `iradiation = 1` (`irad_full`, `modradfull`): a
four-stream double-Gauss correlated-k solver.

`emissurf` and `l_radfullice` come from `&namradiation`; the rest are Fortran defaults.
`timerad = 0` means radiation is called every timestep.

`Nc_0` is the droplet number the **radiation** uses for its effective radius
(`modmicrodata.f90:46`) and is a different symbol from `&nambulk3 nc0 = 1e7`.
`modradfull.f90:56 SolarConstant = 1.365e3` is declared and never read — the solar constant
that ran is `sw0`.
"""
const RADIATION = (;
    iradiation = 1,
    sw0 = 1368.22,
    emissurf = 0.985,
    timerad = 0.0,
    rad_ls = false,
    l_radfullice = true,
    l_nc_const = true,
    l_nci_const = false,
    lcnstzenithtime = true,
    cnstzenithtime = 11.0,
    useMcICA = true,
    minSolarZenithCosForVis = 1.0e-4,
    Nc_0 = 70.0e6,
)

"""Advection scheme codes of `modglobal.f90:130-140`, by name."""
const ADVECTION_SCHEMES = (;
    null = 0, upwind = 1, cd2 = 2, fifth = 5, cd6 = 6, sixty_two = 62, fifty_two = 52,
    kappa = 7, kappa_f = 77, hybrid = 55, hybrid_f = 555,
)

"""
Advection and time stepping, `&dynamics` and the Fortran defaults around it.

`courant = 0.7` is **derived, not set**: `iadv_mom = 5` gives 1.0, and the scalars' `kappa_f`
then applies `min(courant, 0.7)` (`modglobal.f90:252-289`). `iadv_mom = 5` is reduced to
second order at `k = 1, 2, 3, kmax-1, kmax` (`advec_5th.f90:54-113`).

See [`scalar_advection_schemes`](@ref) for what the twelve microphysics scalars actually got.
"""
const ADVECTION = (;
    iadv_mom = 5,
    iadv_tke = 77,
    iadv_thl = 77,
    iadv_qt = 77,
    iadv_sv_namelist = 77,
    courant = 0.7,
    peclet = 0.15,
    dtmax = 20.0,
    tres = 1.0e-3,
    ladaptive = true,
    ih = 3,
    jh = 3,
    cu = 0.0,
    cv = 0.0,
    llsadv = false,
)

"""
    scalar_advection_schemes(nsv; namelist_value = ADVECTION.iadv_sv_namelist,
                             fallback = ADVECTION.iadv_mom)

The advection scheme each of the `nsv` scalars ran with.

`&dynamics iadv_sv = 77` supplies **one** value for a 100-element array whose default is `-1`
(`modglobal.f90:129`), and `initglobal` replaces every remaining `-1` with `iadv_mom`
(`:368-372`). So scalar 1 gets the flux-limited `kappa_f` and scalars 2 onward get the
non-monotone fifth-order scheme — eleven of the twelve SB3 scalars, on every archived day.
"""
function scalar_advection_schemes(
    nsv::Integer;
    namelist_value::Integer = ADVECTION.iadv_sv_namelist,
    fallback::Integer = ADVECTION.iadv_mom,
)
    nsv >= 1 || error("`nsv` must be at least 1, got $nsv.")
    return [k == 1 ? Int(namelist_value) : Int(fallback) for k in 1:nsv]
end

"""
Sponge layer and gravity-wave damping, `modboundary.f90`.

`ksp = -1` in the namelist, so the base level is [`sponge_base_level`](@ref). `rnu0` is a
module variable in no namelist (`modboundary.f90:38`), so the shortest damping timescale — the
one at the domain top — is `1/rnu0 = 363.6 s`.

`igrw_damp = 2` relaxes `u` and `v` toward the **geostrophic** wind, `w` toward zero, and
`thl`/`qt` toward their slab means (`:173-179`). Independently of the sponge, `grwdamp` sets
`thl0`, `qt0` and every `sv0` at `k = kmax` to the slab mean on every call (`:199-203`).
"""
const SPONGE = (;
    ksp_namelist = -1,
    rnu0 = 2.75e-3,
    igrw_damp = 2,
    geodamptime = 7200.0,
    kav = 5,
)

"""
    sponge_base_level(kmax; ksp = SPONGE.ksp_namelist)

Lowest level of the sponge layer, `min(3 kmax/4, kmax - 15)` when the namelist leaves `ksp`
at `-1` (`modboundary.f90:51-53`). Integer division, as the Fortran does it.
"""
function sponge_base_level(kmax::Integer; ksp::Integer = SPONGE.ksp_namelist)
    ksp == -1 || return Int(ksp)
    kmax >= 16 || error("A sponge needs kmax of at least 16, got $kmax.")
    return min(3 * kmax ÷ 4, kmax - 15)
end

"""
    sponge_damping_rate(zf; ksp, rnu0)

The damping rate [1/s] at each height, `rnu0 sin²(½π (z − z_ksp)/(z_top − z_ksp))` above the
sponge base and zero below it (`modboundary.f90:56-62`).
"""
function sponge_damping_rate(
    zf::AbstractVector{FT};
    ksp::Integer = sponge_base_level(length(zf)),
    rnu0::FT = FT(SPONGE.rnu0),
) where {FT}
    1 <= ksp < length(zf) ||
        error("The sponge base $ksp is not inside a column of $(length(zf)) levels.")
    base, top = zf[ksp], last(zf)
    return [
        k < ksp ? zero(FT) :
        rnu0 * sin(FT(0.5) * FT(pi) * (zf[k] - base) / (top - base))^2
        for k in eachindex(zf)
    ]
end

"""
Surface-layer switches, `&namsurface`.

`isurf = 2` prescribes the skin temperature and computes the fluxes. `lmostlocal = false`
solves **one domain-mean Obukhov length** per step and copies it everywhere
(`modsurface.f90:1508-1555`); the wind entering it is floored at `wind_floor`.
`larcticstab = true` selects the Grachev et al. (2007) stable branch — those coefficients and
the solver live in `monin_obukhov.jl`.

`z0mav`, `z0hav`, `albedoav` and `seaicefrct` are in this group but are
[`NAMELIST_PLACEHOLDERS`](@ref); the per-day values are the day-scalar table.
"""
const SURFACE_LAYER = (;
    isurf = 2,
    lmostlocal = false,
    lsmoothflux = false,
    l_surficefrac = true,
    larcticstab = true,
    wind_floor = 0.1,
    f_sal = 1.0,
)

"""
Initial perturbations, `&run` (`modstartup.f90:41-43`, applied at `:540-560`).

`krand` defaults to `huge(0)` and is cut to `kmax` (`:551`), so **every** level is perturbed.
`krandumin = 1 > krandumax = 0` leaves the wind unperturbed.
"""
const PERTURBATIONS = (;
    irandom = 43,
    randthl = 0.1,
    randqt = 2.5e-5,
    krandumin = 1,
    krandumax = 0,
)

"""
Earth rotation, hard-coded at `modglobal.f90:378-379`.

`om22 = 2Ω cos φ` and `om23 = 2Ω sin φ`; the large-scale pressure gradient DALES forms from
the geostrophic wind is `dpdxl = om23 vg`, `dpdyl = −om23 ug`.
"""
const CORIOLIS = (; omega = 7.292e-5, lcoriol = true, lpressgrad = true)

"""
    coriolis_parameters(latitude_degrees; omega = CORIOLIS.omega)

`(; om22, om23)` [1/s] at a latitude, `modglobal.f90:378-379`.
"""
function coriolis_parameters(latitude_degrees::FT; omega::FT = FT(CORIOLIS.omega)) where {FT}
    φ = latitude_degrees * FT(pi) / 180
    return (; om22 = 2 * omega * cos(φ), om23 = 2 * omega * sin(φ))
end
