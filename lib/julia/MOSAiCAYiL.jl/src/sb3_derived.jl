"""
    sb3_derived.jl

The constants `initbulkmicro3` derives at start-up from [`SB3_PARTICLES`](@ref)
(`modbulkmicro3.f90:360-518`).

DALES stores none of these: each is a ratio of Γ functions over a species' shape parameters,
from Seifert & Beheng Appendices B and C. The nine kernels are here, so a caller can derive
the set for particle parameters of their own, and [`SB3_DERIVED`](@ref) is DALES's own set,
evaluated with [`lacz_gamma`](@ref) — the routine that produced the archive's.
"""

_sb3_shape(μ, ν) = lacz_gamma((ν + 1) / μ) / lacz_gamma((ν + 2) / μ)

"""
    sb3_cons_mmt(k, μ, ν)

`Γ((ν+1+k)/μ)/Γ((ν+1)/μ) · [Γ((ν+1)/μ)/Γ((ν+2)/μ)]^k`, the constant part of the `k`-th
moment (`modbulkmicro3.f90:10769`).
"""
sb3_cons_mmt(k::Integer, μ, ν) =
    lacz_gamma((ν + 1 + k) / μ) / lacz_gamma((ν + 1) / μ) * _sb3_shape(μ, ν)^k

"""
    sb3_cons_v(k, μ, ν, α, β)

`α · Γ((ν+β+1+k)/μ)/Γ((ν+1+k)/μ) · [Γ((ν+1)/μ)/Γ((ν+2)/μ)]^β`
(`modbulkmicro3.f90:10802`).

These **are** the sedimentation speeds: `w = c_v x^β`, with `k = 0` for the number and
`k = 1` for the mass.
"""
sb3_cons_v(k::Integer, μ, ν, α, β) =
    α * lacz_gamma((ν + β + 1 + k) / μ) / lacz_gamma((ν + 1 + k) / μ) * _sb3_shape(μ, ν)^β

"""
    sb3_avent(n, μ, ν, b; a_v)

`a_v · Γ((ν+n+b)/μ)/Γ((ν+1)/μ) · [Γ((ν+1)/μ)/Γ((ν+2)/μ)]^(b+n−1)`, the constant part of the
ventilation factor (`modbulkmicro3.f90:10551`).

`a_v` defaults to `SB3_PHYSICS.a_v`, which is what DALES uses: `calc_avent` takes a
per-species `a_v` and **ignores it**, so cloud ice ventilates on 0.78 rather than its own
0.86 — see [`SB3_UNUSED`](@ref).
"""
sb3_avent(n::Integer, μ, ν, b; a_v = SB3_PHYSICS.a_v) =
    a_v * lacz_gamma((ν + n + b) / μ) / lacz_gamma((ν + 1) / μ) *
    _sb3_shape(μ, ν)^(b + n - 1)

"""
    sb3_bvent(n, μ, ν, b, β, b_v)

`b_v · Γ((ν+n+3b/2+β/2)/μ)/Γ((ν+1)/μ) · [Γ((ν+1)/μ)/Γ((ν+2)/μ)]^(3b/2+β/2+n−1)`
(`modbulkmicro3.f90:10582`). Unlike [`sb3_avent`](@ref), this one uses its `b_v`.
"""
sb3_bvent(n::Integer, μ, ν, b, β, b_v) =
    b_v * lacz_gamma((ν + n + 3b / 2 + β / 2) / μ) / lacz_gamma((ν + 1) / μ) *
    _sb3_shape(μ, ν)^(3b / 2 + β / 2 + n - 1)

"""
    sb3_delta(k, μ, ν, b)
    sb3_delta(k, μ_a, ν_a, b_a, μ_b, ν_b, b_b)

The collision integral `δ` of S&B Appendix C, for one species and for a pair
(`modbulkmicro3.f90:10616`, `:10647`). The pair form carries a factor of two the self form
does not.
"""
sb3_delta(k::Integer, μ, ν, b) =
    lacz_gamma((2b + ν + 1 + k) / μ) / lacz_gamma((ν + 1) / μ) * _sb3_shape(μ, ν)^(2b + k)

sb3_delta(k::Integer, μ_a, ν_a, b_a, μ_b, ν_b, b_b) =
    2 *
    (lacz_gamma((b_a + ν_a + 1 + k) / μ_a) / lacz_gamma((ν_a + 1) / μ_a)) *
    (lacz_gamma((b_b + ν_b + 1) / μ_b) / lacz_gamma((ν_b + 1) / μ_b)) *
    _sb3_shape(μ_a, ν_a)^(b_a + k) *
    _sb3_shape(μ_b, ν_b)^b_b

"""
    sb3_theta(k, μ, ν, b, β)
    sb3_theta(k, μ_a, ν_a, b_a, β_a, μ_b, ν_b, b_b, β_b)

The collision integral `ϑ` of S&B Appendix C, for one species and for a pair
(`modbulkmicro3.f90:10692`, `:10725`).
"""
sb3_theta(k::Integer, μ, ν, b, β) =
    lacz_gamma((2β + 2b + ν + 1 + k) / μ) / lacz_gamma((2b + ν + 1 + k) / μ) *
    _sb3_shape(μ, ν)^(2β)

sb3_theta(k::Integer, μ_a, ν_a, b_a, β_a, μ_b, ν_b, b_b, β_b) =
    2 *
    (lacz_gamma((β_a + b_a + ν_a + 1 + k) / μ_a) /
     lacz_gamma((b_a + ν_a + 1 + k) / μ_a)) *
    (lacz_gamma((β_b + b_b + ν_b + 1) / μ_b) / lacz_gamma((b_b + ν_b + 1) / μ_b)) *
    _sb3_shape(μ_a, ν_a)^β_a *
    _sb3_shape(μ_b, ν_b)^β_b

"""
    sb3_cons_lbd(μ, ν)

`[Γ((ν+1)/μ)/Γ((ν+2)/μ)]^(−μ)` (`modbulkmicro3.f90:10838`).

DALES computes one of these, with rain's `μ` and **snow's** `ν`, and never reads it — see
[`SB3_UNUSED`](@ref).
"""
sb3_cons_lbd(μ, ν) = _sb3_shape(μ, ν)^(-μ)

"""
Which species collect which, `modbulkmicro3.f90:429-443`, as collector => the species it
collects.

Snow has no graupel partner, which is why `dlt_s0g` is declared and never assigned. Cloud
liquid and rain collect nothing: they are collected.
"""
const SB3_COLLISION_PAIRS = (;
    cloud_ice = (:cloud_liquid, :rain, :cloud_ice),
    rain = (:cloud_ice, :snow, :graupel),
    snow = (:cloud_liquid, :rain, :cloud_ice, :snow),
    graupel = (:cloud_liquid, :rain, :cloud_ice, :snow, :graupel),
)

function _sb3_build_derived()
    p = SB3_PARTICLES
    moment = NamedTuple(
        s => (; k1 = sb3_cons_mmt(1, p[s].μ, p[s].ν), k2 = sb3_cons_mmt(2, p[s].μ, p[s].ν))
        for s in (:cloud_liquid, :rain)
    )
    fall_speed = NamedTuple(
        s => (;
            k0 = sb3_cons_v(0, p[s].μ, p[s].ν, p[s].α, p[s].β),
            k1 = sb3_cons_v(1, p[s].μ, p[s].ν, p[s].α, p[s].β),
        )
        for s in (:cloud_liquid, :cloud_ice, :snow, :graupel)
    )
    ventilation = NamedTuple(
        s => (;
            a0 = sb3_avent(0, p[s].μ, p[s].ν, p[s].b),
            a1 = sb3_avent(1, p[s].μ, p[s].ν, p[s].b),
            b0 = sb3_bvent(0, p[s].μ, p[s].ν, p[s].b, p[s].β, SB3_VENTILATION[s].b_v),
            b1 = sb3_bvent(1, p[s].μ, p[s].ν, p[s].b, p[s].β, SB3_VENTILATION[s].b_v),
        )
        for s in keys(SB3_VENTILATION)
    )
    δ_self = NamedTuple(
        s => (; k0 = sb3_delta(0, p[s].μ, p[s].ν, p[s].b),
                k1 = sb3_delta(1, p[s].μ, p[s].ν, p[s].b))
        for s in keys(p)
    )
    θ_self = NamedTuple(
        s => (; k0 = sb3_theta(0, p[s].μ, p[s].ν, p[s].b, p[s].β),
                k1 = sb3_theta(1, p[s].μ, p[s].ν, p[s].b, p[s].β))
        for s in keys(p)
    )
    δ_pair = NamedTuple(
        a => NamedTuple(
            b => (;
                k0 = sb3_delta(0, p[a].μ, p[a].ν, p[a].b, p[b].μ, p[b].ν, p[b].b),
                k1 = sb3_delta(1, p[a].μ, p[a].ν, p[a].b, p[b].μ, p[b].ν, p[b].b),
            )
            for b in SB3_COLLISION_PAIRS[a]
        )
        for a in keys(SB3_COLLISION_PAIRS)
    )
    θ_pair = NamedTuple(
        a => NamedTuple(
            b => (;
                k0 = sb3_theta(
                    0, p[a].μ, p[a].ν, p[a].b, p[a].β, p[b].μ, p[b].ν, p[b].b, p[b].β,
                ),
                k1 = sb3_theta(
                    1, p[a].μ, p[a].ν, p[a].b, p[a].β, p[b].μ, p[b].ν, p[b].b, p[b].β,
                ),
            )
            for b in SB3_COLLISION_PAIRS[a]
        )
        for a in keys(SB3_COLLISION_PAIRS)
    )
    return (; moment, fall_speed, ventilation, δ_self, δ_pair, θ_self, θ_pair)
end

"""
The 108 constants `initbulkmicro3` derives from [`SB3_PARTICLES`](@ref) at start-up
(`modbulkmicro3.f90:360-506`), evaluated here with [`lacz_gamma`](@ref).

`moment` and `fall_speed` are `k0`/`k1`/`k2` by species; `ventilation` is `a0`, `a1`, `b0`,
`b1`; `δ_self` and `θ_self` are `k0`/`k1` for all five species; `δ_pair` and `θ_pair` are
nested by collector then collected, over the pairs of [`SB3_COLLISION_PAIRS`](@ref).

`fall_speed` has no rain entry — rain sediments through
[`SB3_SEDIMENTATION`](@ref)'s `a_tvsbc` form instead.

Two rain entries look wrong and are not. `ventilation.rain.a0` is large because `(ν+b)/μ` is
`−1.00003`, just off a pole of Γ — at exact `1/3` and `−2/3` it would be infinite, see
[`SB3_PARTICLES`](@ref). `ventilation.rain.b0` is **negative**, the only one of the 108 that
is, because its argument `(ν + 3b/2 + β/2)/μ` is `−0.101`, and Γ is negative on `(−1, 0)`.
"""
const SB3_DERIVED = _sb3_build_derived()

"""
    sb3_collision_pair(a, b)

The twelve constants a collision between species `a` and `b` is built from, as
`modbulkmicro3.f90:6938-6960` assembles them: `(; σ_a, σ_b, δ_0a, δ_0ab, δ_0b, δ_1ab, δ_1b,
θ_0a, θ_0ab, θ_0b, θ_1ab, θ_1b)`.

`a` is the collector and `b` the collected, so the pair is ordered — `sb3_collision_pair(:snow,
:cloud_liquid)` is riming, and the reverse is not a pair DALES forms.

The collision efficiency is **not** here: it depends on the process rather than the pair, with
`ice_aggr3` using `E_ee_m` where `coll_ici3` uses `E_i_m` for the same two species.
"""
function sb3_collision_pair(a::Symbol, b::Symbol)
    haskey(SB3_COLLISION_PAIRS, a) ||
        error("`$a` collects nothing in SB3; the collectors are \
               $(join(keys(SB3_COLLISION_PAIRS), ", ")).")
    b in SB3_COLLISION_PAIRS[a] || error(
        "SB3 forms no `$a`–`$b` pair; `$a` collects \
         $(join(SB3_COLLISION_PAIRS[a], ", ")).",
    )
    d, θ = SB3_DERIVED.δ_pair[a][b], SB3_DERIVED.θ_pair[a][b]
    return (;
        σ_a = SB3_PARTICLES[a].σ_v,
        σ_b = SB3_PARTICLES[b].σ_v,
        δ_0a = SB3_DERIVED.δ_self[a].k0,
        δ_0ab = d.k0,
        δ_0b = SB3_DERIVED.δ_self[b].k0,
        δ_1ab = d.k1,
        δ_1b = SB3_DERIVED.δ_self[b].k1,
        θ_0a = SB3_DERIVED.θ_self[a].k0,
        θ_0ab = θ.k0,
        θ_0b = SB3_DERIVED.θ_self[b].k0,
        θ_1ab = θ.k1,
        θ_1b = SB3_DERIVED.θ_self[b].k1,
    )
end

"""
    sb3_sedimentation_speed(x, c_v, particle)

Sedimentation speed [m/s], `max(0, c_v x^β)`, with `c_v` from
[`SB3_DERIVED`](@ref)`.fall_speed`.

This carries **no** density correction, unlike the diagnostic [`sb3_fall_speed`](@ref); the
two are different quantities and DALES uses them in different places.
"""
sb3_sedimentation_speed(x::FT, c_v::FT, p::NamedTuple) where {FT} =
    max(zero(FT), c_v * x^FT(p.β))

"""
    sb3_max_fall_speed(species)

The sedimentation speed cap [m/s] (`modbulkmicro3.f90:510-515`).

Rain, cloud liquid, cloud ice and snow all take `d_wfallmax_hr`; graupel instead takes
`max(c_v_g0, c_v_g1)` from the derived fall-speed moments, and `d_wfallmax_hg = 11.9` is
bypassed — see [`SB3_UNUSED`](@ref).
"""
function sb3_max_fall_speed(species::Symbol)
    species === :graupel &&
        return max(SB3_DERIVED.fall_speed.graupel.k0, SB3_DERIVED.fall_speed.graupel.k1)
    haskey(SB3_PARTICLES, species) || error("`$species` is not an SB3 species.")
    return SB3_SEDIMENTATION.w_fall_max
end
