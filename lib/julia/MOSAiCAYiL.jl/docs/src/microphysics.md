```@meta
CurrentModule = MOSAiCAYiL
```

# Microphysics

`imicro = 11` selects SB3, the Seifert–Beheng two-moment scheme with five species and twelve
prognostic scalars. `&nammicrophysics` sets only `imicro`, and `&nambulk3` only five values,
so **every other switch is a Fortran default** — the scheme ran on `l_sb_classic = true`
throughout.

## The parameters

```@example micro
using MOSAiCAYiL: MOSAiCAYiL as MA
MA.SB3_PARTICLES.snow
```

Mean mass maps to diameter as `D = a x^b` and to fall speed as `v = α x^β (ρ_ref/ρ)^γ`, with
`x` clamped to `[x_min, x_max]`. Alongside `SB3_PARTICLES` sit
[`MOSAiCAYiL.SB3_PHYSICS`](@ref), [`MOSAiCAYiL.SB3_SWITCHES`](@ref),
[`MOSAiCAYiL.SB3_WARM_RAIN`](@ref), [`MOSAiCAYiL.SB3_COLLISION`](@ref) and the rest — one
table per group of the Fortran.

Two literals are load-bearing rather than approximate. Rain's `ν = −0.66667` and
`μ = 0.33333` put the ventilation argument `(ν+b)/μ` at `−1.00003`, a hair off a pole of Γ:

```@example micro
rain = MA.SB3_PARTICLES.rain
((rain.ν + rain.b) / rain.μ, MA.SB3_DERIVED.ventilation.rain.a0)
```

At exact `1/3` and `−2/3` that argument is exactly `−1` and the coefficient is infinite, so
tidying the decimals would destroy rain evaporation rather than perturb it.

## The constants DALES derives

DALES stores none of the collision, ventilation, moment or fall-speed constants: it computes
108 of them at start-up from ratios of Γ functions over the shape parameters. This package
does the same, with [`MOSAiCAYiL.lacz_gamma`](@ref) — a port of `modglobal.f90:503-743`, the
routine that produced the archive's own.

```@example micro
MA.SB3_DERIVED.fall_speed.graupel
```

Those two **are** the sedimentation velocities: `w = c_v x^β` with `k0` for the number and
`k1` for the mass. The nine kernels are public, so the set can be derived for other particle
parameters:

```@example micro
MA.sb3_avent(1, rain.μ, rain.ν, rain.b)
```

One of the 108 is negative — rain's `b0`, because its Γ argument falls in `(−1, 0)` where Γ
itself is negative. That is faithful, not a defect.

## The process rates

Every rate is **pure and unlimited**: a function of the state at a point, with no timestep, no
previous time level and no accumulated tendency. [`MOSAiCAYiL.sb3_limit`](@ref) is the only
place a limiter lives.

```@example micro
MA.sb3_autoconversion_rate(1.0e-3, 5.0e-11, 1.0e-5)
```

That separation is the point: a rate that silently returned a limited answer would look right
and be wrong, and no comparison against the archive could tell.

The ten collision routines share one kernel:

```julia
pair = MA.sb3_collision_pair(:cloud_ice, :cloud_liquid)
MA.sb3_collision_rates(n_a, q_b, n_b, D_a, D_b, v_a, v_b, ρ, E, pair)
```

The mass tendency takes the `k = 1` pair moments and the number tendency the `k = 0` ones.
The efficiency is a separate argument because the same pair collides differently in different
routines — `ice_aggr3` uses `E_ee_m` where `coll_ici3` uses `E_i_m`.

## Two velocities, two names

[`MOSAiCAYiL.sb3_fall_speed`](@ref) carries the `(ρ_ref/ρ)^γ` correction and is the
diagnostic velocity; [`MOSAiCAYiL.sb3_sedimentation_speed`](@ref) does not and is what
sedimentation uses. Rain is the exception again — it has no `c_v` moments and falls through
the `a_tvsbc` form, **with** a density correction.

## What is declared and never runs

```@example micro
keys(MA.SB3_UNUSED)
```

Each entry carries its value and why it is dead. Two would change a rate if taken for live
settings: `E_ii_m = 0.1` is superseded by `E_ee_m = 1.0`, a factor of ten; and `a_v = 0.86`
for cloud ice is ignored because `calc_avent` uses the module's `avf = 0.78` regardless of its
argument.
