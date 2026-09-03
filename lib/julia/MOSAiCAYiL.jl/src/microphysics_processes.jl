"""
    microphysics_processes.jl

The SB3 process rates of `modbulkmicro3.f90`, on the `l_sb_classic` branch the AYiL runs took.

Every rate here is **pure and unlimited**: it is a function of the state at a point and
nothing else, and it does not see the previous time level, the accumulated tendency or the
timestep. [`sb3_limit`](@ref) is the only place a limiter lives, and it takes what it needs
explicitly. A rate that quietly returned a limited answer would look right and be wrong, which
is the failure this separation exists to prevent.

Signs are as the Fortran writes them into its `d*_*` variables. The netCDF relabelling is a
property of the archive, not of the physics — see `MPHYS_PROCESS`.

Every rate assumes its species are present; apply [`sb3_present`](@ref) first.
"""

"""
    sb3_limit(rate, available, dt)

`rate` limited so it cannot move more than `available` over `dt`, in whichever direction it
acts: `min(rate, available/dt)` for a gain and `max(rate, −available/dt)` for a loss.

DALES applies this at each rate's own call site with its own `available`, which is why it is
separate here. Passing a state snapshot to a rate and receiving a limited answer would hide
which of the two happened.
"""
sb3_limit(rate::FT, available::FT, dt::FT) where {FT} =
    rate >= zero(FT) ? min(rate, available / dt) : max(rate, -available / dt)

"""
    sb3_growth_parameter(T, e_sat, L; D_v, K_t, R_v)

The condensation–evaporation parameter `G` of a drop, `1/[(R_v T)/(D_v e_sat) +
L/(K_t T)·(L/(R_v T) − 1)]` (`modbulkmicro3.f90:5150`, `:5295`).

`L` is the latent heat of the transition: vaporisation for rain, sublimation for the ice
species, which is why it is an argument rather than a constant.
"""
function sb3_growth_parameter(
    T::FT, e_sat::FT, L::FT;
    D_v::FT = FT(SB3_PHYSICS.D_v),
    K_t::FT = FT(SB3_PHYSICS.K_t),
    R_v::FT = FT(DALES_CONSTANTS.R_v),
) where {FT}
    inverse = (R_v * T) / (D_v * e_sat) + L / (K_t * T) * (L / (R_v * T) - one(FT))
    return one(FT) / inverse
end

"""
    sb3_autoconversion_rate(q_cloud, x_cloud, q_rain; particle, p)

Cloud water converting to rain, as `(; dq_rain, dn_cloud_liquid, dn_rain)` [per second]
(`modbulkmicro3.f90:2673-2698`).

```
k_au  = k_cc/(20 x_s)
τ     = 1 − q_cl/(q_cl + q_hr)
φ     = k_1 τ^k_2 (1 − τ^k_2)³
dq    = k_au (ν+2)(ν+4)/(ν+1)² (q_cl x_cl)² ρ_ref · [1 + φ/(1−τ)²]
```

The number tendencies follow the scheme's own factor of two: `dn_cloud_liquid = −2 dq/x_s`
and `dn_rain = −dn_cloud_liquid/2`, so two droplets leave for each drop formed.
"""
function sb3_autoconversion_rate(
    q_cloud::FT, x_cloud::FT, q_rain::FT;
    particle::NamedTuple = SB3_PARTICLES.cloud_liquid,
    p::NamedTuple = SB3_WARM_RAIN,
    ρ_ref::FT = FT(SB3_PHYSICS.ρ_ref),
) where {FT}
    ν = FT(particle.ν)
    x_s = FT(p.x_s)
    k_au = FT(p.k_cc) / (20 * x_s)
    τ = one(FT) - q_cloud / (q_cloud + q_rain)
    φ = FT(p.k_1) * τ^FT(p.k_2) * (one(FT) - τ^FT(p.k_2))^3
    dq_rain =
        k_au * (ν + 2) * (ν + 4) / (ν + one(FT))^2 * (q_cloud * x_cloud)^2 * ρ_ref *
        (one(FT) + φ / (one(FT) - τ)^2)
    dn_cloud_liquid = (-2 / x_s) * dq_rain
    return (; dq_rain, dn_cloud_liquid, dn_rain = -dn_cloud_liquid / 2)
end

"""
    sb3_accretion_rate(q_cloud, x_cloud, q_rain, ρ; p)

Rain collecting cloud water, as `(; dq_rain, dn_cloud_liquid)` [per second]
(`modbulkmicro3.f90:2848-2858`).

```
τ  = 1 − q_cl/(q_cl + q_hr)
φ  = [τ/(τ + k_l)]⁴
dq = k_cr ρ q_cl q_hr φ (ρ_ref/ρ)^(1/2)
```

Accretion changes no rain number: it moves mass into drops that already exist.
"""
function sb3_accretion_rate(
    q_cloud::FT, x_cloud::FT, q_rain::FT, ρ::FT;
    p::NamedTuple = SB3_WARM_RAIN,
    ρ_ref::FT = FT(SB3_PHYSICS.ρ_ref),
) where {FT}
    τ = one(FT) - q_cloud / (q_cloud + q_rain)
    φ = (τ / (τ + FT(p.k_l)))^4
    dq_rain = FT(p.k_cr) * ρ * q_cloud * q_rain * φ * sqrt(ρ_ref / ρ)
    return (; dq_rain, dn_cloud_liquid = -dq_rain / x_cloud)
end

"""
    sb3_cloud_self_collection_rate(q_cloud, dn_cloud_autoconversion; particle, p)

Cloud droplets coalescing without forming rain, as a number tendency [per second]
(`modbulkmicro3.f90:3054-3062`).

`−k_cc ρ_ref q_cl² (ν+2)/(ν+1)`, **less** the droplet loss autoconversion has already
accounted for, then floored at zero so self-collection cannot create droplets. It therefore
takes the autoconversion number tendency as an argument: DALES runs `cloud_self3` after
`autoconversion3` and subtracts its result.
"""
function sb3_cloud_self_collection_rate(
    q_cloud::FT, dn_cloud_autoconversion::FT;
    particle::NamedTuple = SB3_PARTICLES.cloud_liquid,
    p::NamedTuple = SB3_WARM_RAIN,
    ρ_ref::FT = FT(SB3_PHYSICS.ρ_ref),
) where {FT}
    ν = FT(particle.ν)
    rate = -FT(p.k_cc) * ρ_ref * q_cloud^2 * (ν + 2) / (ν + one(FT)) -
           dn_cloud_autoconversion
    return min(zero(FT), rate)
end

"""
    sb3_rain_self_collection_rate(q_rain, n_rain, λ, ρ; p)

Rain drops coalescing, as a number tendency [per second] (`modbulkmicro3.f90:2918-2920`).

`−k_rr ρ q_hr n_hr (1 + κ_r/λ)^(−9) (ρ_ref/ρ)^(1/2)`, with `λ` from
[`sb3_rain_dsd`](@ref).

The `l_sb_classic` branch omits the `πρ_w^(1/3)` factor the other branch applies to
`κ_r/λ`.
"""
function sb3_rain_self_collection_rate(
    q_rain::FT, n_rain::FT, λ::FT, ρ::FT;
    p::NamedTuple = SB3_WARM_RAIN,
    ρ_ref::FT = FT(SB3_PHYSICS.ρ_ref),
) where {FT}
    return -FT(p.k_rr) * ρ * q_rain * n_rain *
           (one(FT) + FT(p.kappa_r) / λ)^(-9) * sqrt(ρ_ref / ρ)
end

"""
    sb3_rain_breakup_rate(D_v, dn_self_collection; p)

Large rain drops breaking up, as a number tendency [per second]
(`modbulkmicro3.f90:2924-2934`).

Zero at or below `dvrlim`. Above it `φ_br` is linear in `D_v − D_eq` up to `dvrbiglim` and
exponential beyond, and the rate is `−(φ_br + 1)` times the self-collection tendency — so
break-up opposes coalescence and can exceed it once the drops are large.
"""
function sb3_rain_breakup_rate(
    D_v::FT, dn_self_collection::FT; p::NamedTuple = SB3_WARM_RAIN,
) where {FT}
    D_v > FT(p.dvrlim) || return zero(FT)
    φ_br = if D_v > FT(p.dvrbiglim)
        2 * exp(FT(p.kappa_br) * (D_v - FT(p.D_eq))) - one(FT)
    else
        FT(p.k_br) * (D_v - FT(p.D_eq))
    end
    return -(φ_br + one(FT)) * dn_self_collection
end

"""
    sb3_rain_evaporation_rate(q_rain, n_rain, D_v, x_rain, x_rain_clamped, S, G, ρ; …)

Rain evaporating into subsaturated air, as `(; dq_rain, dn_rain)` [per second]
(`modbulkmicro3.f90:5136-5155`).

```
Re = D_v · α_hr (ρ_ref/ρ)^(1/2) x_clamped^β_hr / ν_air
f0 = max(0, aven_0r + bven_0r Sc^(1/3) Re^(1/2))
f1 =        aven_1r + bven_1r Sc^(1/3) Re^(1/2)
dq = 2π n G D_v f1 S
dn = 2π n G D_v f0 S / x_rain
```

`S` is the subsaturation, already floored at zero by the caller, and `G` is
[`sb3_growth_parameter`](@ref). `x_rain` is the **unbounded** `q/(n+ε₀)`, while the Reynolds
number uses the clamped mean mass — DALES uses both, and they are not interchangeable.

The number tendency is then floored at zero and at `dq/x_rain`, so evaporation cannot create
drops and cannot remove them faster than it removes their mass.
"""
function sb3_rain_evaporation_rate(
    q_rain::FT, n_rain::FT, D_v::FT, x_rain::FT, x_rain_clamped::FT,
    S::FT, G::FT, ρ::FT;
    particle::NamedTuple = SB3_PARTICLES.rain,
    ventilation::NamedTuple = SB3_DERIVED.ventilation.rain,
    ρ_ref::FT = FT(SB3_PHYSICS.ρ_ref),
    ν_air::FT = FT(SB3_PHYSICS.ν_air),
    Sc::FT = FT(SB3_PHYSICS.Sc),
) where {FT}
    v = FT(particle.α) * sqrt(ρ_ref / ρ) * x_rain_clamped^FT(particle.β)
    N_re = D_v * v / ν_air
    enhancement = Sc^(one(FT) / 3) * sqrt(N_re)
    f0 = max(zero(FT), FT(ventilation.a0) + FT(ventilation.b0) * enhancement)
    f1 = FT(ventilation.a1) + FT(ventilation.b1) * enhancement

    dq_rain = 2 * FT(pi) * n_rain * G * D_v * f1 * S
    dn_rain = 2 * FT(pi) * n_rain * G * D_v * f0 * S / x_rain
    dn_rain = min(zero(FT), dn_rain)
    dn_rain = max(dn_rain, dq_rain / x_rain)
    return (; dq_rain, dn_rain)
end

"""
    sb3_ice_supersaturation(q_tot, q_cloud, q_sat_ice)

Supersaturation with respect to ice, `(q_tot − q_cl − q_sat,i)/q_sat,i`
(`modbulkmicro3.f90:5290-5292`).

The cloud liquid is removed and the ice content is **not**, which is what DALES does here.
"""
sb3_ice_supersaturation(q_tot::FT, q_cloud::FT, q_sat_ice::FT) where {FT} =
    (q_tot - q_cloud - q_sat_ice) / q_sat_ice

"""
    sb3_deposition_rate(T, p_air, q_tot, q_cloud, q_sat_ice, n, x, ρ; particle, ventilation, …)

Vapour depositing onto an ice species, as a mass tendency [1/s]
(`modbulkmicro3.f90:5283-5310`, and the same code for snow and graupel with their own
constants).

```
S_i  = (q_tot − q_cl − q_sat,i)/q_sat,i
e_si = q_sat,i p / (ε + (1−ε) q_sat,i)
G    = 1/[(R_v T)/(D_v e_si) + L_s/(K_t T)·(L_s/(R_v T) − 1)]
D    = a x^b,   v = α (ρ_ref/ρ)^(1/2) x^β,   Re = D v/ν_air
F    = aven_1 + bven_1 Sc^(1/3) Re^(1/2)
dq   = (4π/c) n G D F S_i
```

Negative `S_i` gives sublimation, which is the same expression with the sign of `S_i`. `n` is
per unit mass and `x` the clamped mean mass, as [`sb3_mean_mass`](@ref) returns.

Cloud liquid and rain do not deposit — their capacitances are in [`SB3_UNUSED`](@ref).
"""
function sb3_deposition_rate(
    T::FT, p_air::FT, q_tot::FT, q_cloud::FT, q_sat_ice::FT, n::FT, x::FT, ρ::FT;
    particle::NamedTuple,
    ventilation::NamedTuple,
    backend = DefaultThermodynamicsBackend(),
    L_s::FT = FT(SB3_PHYSICS.L_s),
    ρ_ref::FT = FT(SB3_PHYSICS.ρ_ref),
    ν_air::FT = FT(SB3_PHYSICS.ν_air),
    Sc::FT = FT(SB3_PHYSICS.Sc),
) where {FT}
    ε = molmass_ratio(backend, FT)
    S_i = sb3_ice_supersaturation(q_tot, q_cloud, q_sat_ice)
    e_si = q_sat_ice * p_air / (ε + (one(FT) - ε) * q_sat_ice)
    G = sb3_growth_parameter(T, e_si, L_s; R_v = R_v(backend, FT))

    D = sb3_diameter(x, particle)
    v = FT(particle.α) * sqrt(ρ_ref / ρ) * x^FT(particle.β)
    N_re = D * v / ν_air
    F = FT(ventilation.a1) + FT(ventilation.b1) * Sc^(one(FT) / 3) * sqrt(N_re)

    k_depos = 4 * FT(pi) / FT(particle.c)
    return k_depos * n * G * D * F * S_i
end

"""
    sb3_deposition_correction(demanded, q_tot, q_cloud, q_sat_ice, dt; ε_0)

The factor `cond_cf` that rescales the three ice deposition rates when together they would
take more vapour than there is (`modbulkmicro3.f90:3872-3890`).

`demanded` is their sum. The corrected rate of each species is
`dq + cond_cf · max(0, dq)`, so only deposition is scaled and sublimation passes through.
Zero unless the demand is both positive and larger than the supply, and clamped to `[−1, 0]`
so a rate can be cancelled but never reversed.
"""
function sb3_deposition_correction(
    demanded::FT, q_tot::FT, q_cloud::FT, q_sat_ice::FT, dt::FT;
    ε_0::FT = FT(SB3_PHYSICS.ε_0),
) where {FT}
    available = (q_tot - q_cloud - q_sat_ice) / dt
    (demanded > zero(FT) && available - demanded < zero(FT)) || return zero(FT)
    return clamp(available / (demanded + ε_0) - one(FT), -one(FT), zero(FT))
end

"""
    sb3_collision_efficiency(D_a, D_b, E_max; D_a_min, D_b_lower, D_b_upper)

Collision efficiency between a collector of diameter `D_a` and a collected particle of
diameter `D_b` (`modbulkmicro3.f90:6987-6994`).

Zero unless the collector exceeds `D_a_min` and the collected exceeds `D_b_lower`; then it
ramps linearly to `E_max` across `[D_b_lower, D_b_upper]` and holds there. The defaults are
the cloud-droplet thresholds `D_c_a`, `D_c_b` and the ice floor `D_i0`; the ice–ice routines
pass `D_i_a` and `D_i_b` instead.
"""
function sb3_collision_efficiency(
    D_a::FT, D_b::FT, E_max::FT;
    D_a_min::FT = FT(SB3_COLLISION.D_i0),
    D_b_lower::FT = FT(SB3_COLLISION.D_c_a),
    D_b_upper::FT = FT(SB3_COLLISION.D_c_b),
) where {FT}
    (D_b > D_b_lower && D_a > D_a_min) || return zero(FT)
    D_b > D_b_upper && return E_max
    return E_max / (D_b_upper - D_b_lower) * (D_b - D_b_lower)
end

"""
    sb3_collision_rates(n_a, q_b, n_b, D_a, D_b, v_a, v_b, ρ, E, pair)

One collection of species `b` by species `a`, as `(; dq_a, dn_b)` [per second] — the kernel
the ten collision routines share (`modbulkmicro3.f90:7002-7011`).

```
dq_a =  (ρπ/4) E n_a q_b (δ_0a D_a² + δ_1ab D_a D_b + δ_1b D_b²)
                        · (θ_0a v_a² − θ_1ab v_a v_b + θ_1b v_b² + σ_a² + σ_b²)^(1/2)
dn_b = −(ρπ/4) E n_a n_b (δ_0a D_a² + δ_0ab D_a D_b + δ_0b D_b²)
                        · (θ_0a v_a² − θ_0ab v_a v_b + θ_0b v_b² + σ_a² + σ_b²)^(1/2)
```

The mass tendency takes the `k = 1` pair moments and the number tendency the `k = 0` ones,
which is the whole reason [`sb3_collision_pair`](@ref) carries both. `E` is the process's own
efficiency — see [`sb3_collision_efficiency`](@ref) — because the same pair collides with
different efficiencies in different routines.

The collector gains mass and the collected loses number; what becomes of the collector's
number and the collected's mass is the calling process's business, and differs between riming,
aggregation and conversion.
"""
function sb3_collision_rates(
    n_a::FT, q_b::FT, n_b::FT, D_a::FT, D_b::FT, v_a::FT, v_b::FT, ρ::FT, E::FT,
    pair::NamedTuple,
) where {FT}
    prefactor = ρ * FT(pi) / 4 * E * n_a
    σ² = FT(pair.σ_a)^2 + FT(pair.σ_b)^2

    size_mass = FT(pair.δ_0a) * D_a^2 + FT(pair.δ_1ab) * D_a * D_b + FT(pair.δ_1b) * D_b^2
    speed_mass = sqrt(
        FT(pair.θ_0a) * v_a^2 - FT(pair.θ_1ab) * v_a * v_b + FT(pair.θ_1b) * v_b^2 + σ²,
    )

    size_number = FT(pair.δ_0a) * D_a^2 + FT(pair.δ_0ab) * D_a * D_b + FT(pair.δ_0b) * D_b^2
    speed_number = sqrt(
        FT(pair.θ_0a) * v_a^2 - FT(pair.θ_0ab) * v_a * v_b + FT(pair.θ_0b) * v_b^2 + σ²,
    )

    return (;
        dq_a = prefactor * q_b * size_mass * speed_mass,
        dn_b = -prefactor * n_b * size_number * speed_number,
    )
end

"""
    sb3_sticking_efficiency(T; B, C, E_max, offset)

Ice–ice sticking efficiency, `min(E_max, exp(B (T + offset) + C))`
(`modbulkmicro3.f90:6963` and the constants at `modmicrodata3.f90:322-327`).

`offset = −273.15`, so the exponent is in degrees Celsius. `E_max` is `E_ii_maxst` for ice
and `E_ss_maxst` for snow.
"""
function sb3_sticking_efficiency(
    T::FT;
    B::FT = FT(SB3_COLLISION.B_stick_ii),
    C::FT = FT(SB3_COLLISION.C_stick_ii),
    E_max::FT = FT(SB3_COLLISION.E_ii_maxst),
    offset::FT = FT(SB3_COLLISION.stick_off),
) where {FT}
    return min(E_max, exp(B * (T + offset) + C))
end

"""
    sb3_enhanced_melting_coefficient(; c_water, L_f)

`k_enhm = c_water/L_f` (`modbulkmicro3.f90:6964`), the coefficient converting the sensible
heat a rimed drop carries into melted mass.
"""
sb3_enhanced_melting_coefficient(;
    c_water = SB3_PHYSICS.c_water, L_f = SB3_PHYSICS.L_f,
) = c_water / L_f

"""
    sb3_ice_nucleus_target(T, s_ice, ρ; p, reisner)

The ice-nucleus number concentration [kg⁻¹] the scheme relaxes toward
(`modbulkmicro3.f90:3736-3741`).

Meyers (1992) gives `n = N_inuc exp(a_M92 + b_M92 min(s_i, ssice_lim))/ρ`; with `reisner`
this is then held between `a1` and `a2` times the Reisner (1998) estimate
`n_tid = N_inuc_R exp(b_inuc_R (T_3 − max(T, c_R98)))/ρ`, and finally capped at `n_i_max`.

Zero unless `T < tmp_inuc` and `s_i > ssice_min`.

This returns the **target**, not a tendency: DALES forms `(n_target − n_ice)/Δt` and nucleates
only when the target is the larger, which is a bookkeeping step rather than a rate.

The AYiL runs overwrote `N_inuc`, `N_inuc_R` and `b_inuc_R` per day from `scm_in`, so pass
[`inp_fletcher_n`](@ref) and [`inp_fletcher_b`](@ref) for a specific day rather than relying
on the module defaults in [`SB3_NUCLEATION`](@ref).
"""
function sb3_ice_nucleus_target(
    T::FT, s_ice::FT, ρ::FT;
    p::NamedTuple = SB3_NUCLEATION,
    thresholds::NamedTuple = SB3_THRESHOLDS,
    reisner::Bool = SB3_SWITCHES.l_sb_reisner,
    N_inuc::FT = FT(p.N_M92),
    N_inuc_R::FT = FT(p.N_R98),
    b_inuc_R::FT = FT(p.b_R98),
    T_3::FT = FT(SB3_PHYSICS.T_3),
) where {FT}
    (T < FT(p.tmp_inuc) && s_ice > FT(thresholds.ssice_min)) || return zero(FT)
    n = (one(FT) / ρ) * N_inuc *
        exp(FT(p.a_M92) + FT(p.b_M92) * min(s_ice, FT(thresholds.ssice_lim)))
    if reisner
        n_tid = (one(FT) / ρ) * N_inuc_R *
                exp(b_inuc_R * (T_3 - max(T, FT(p.c_R98))))
        n = max(FT(p.a1_R98) * n_tid, min(FT(p.a2_R98) * n_tid, n))
    end
    return min(FT(p.n_i_max), n)
end

"""
    sb3_homogeneous_nucleation_rate(T; p)

The Cotton & Field (2002) homogeneous freezing rate `J_hom` [kg⁻¹ s⁻¹] of a droplet
(`modbulkmicro3.f90:5919-5931`).

Three branches in temperature: an exponential above `tmp_lim1`, a quartic polynomial in
`T − 273.15` between the limits, and a constant below `tmp_lim2`. The leading `1e3` converts
the published per-gram rate to per kilogram.
"""
function sb3_homogeneous_nucleation_rate(T::FT; p::NamedTuple = SB3_FREEZING) where {FT}
    per_kg = FT(1.0e3)
    T > FT(p.tmp_lim1_CF02) &&
        return per_kg * exp(FT(p.C_CF02) + FT(p.B_CF02) * (T + FT(p.CC_CF02)))
    T < FT(p.tmp_lim2_CF02) && return per_kg * exp(FT(p.C_30_CF02))
    δ = T - FT(p.offset_CF02)
    return per_kg * exp(
        FT(p.C_20_CF02) + FT(p.B_21_CF02) * δ + FT(p.B_22_CF02) * δ^2 +
        FT(p.B_23_CF02) * δ^3 + FT(p.B_24_CF02) * δ^4,
    )
end

"""
    sb3_heterogeneous_nucleation_rate(T; p)

The heterogeneous freezing rate `J_het = A_het exp[B_het (T_3 − max(tlimhetfreeze, T)) − 1]`
(`modbulkmicro3.f90:5762`).

`tlimhetfreeze` floors the temperature, so the rate saturates below it rather than growing
without bound. The AYiL runs set it to 258.15 from `&nambulk3`; the module default is 238.0.
"""
sb3_heterogeneous_nucleation_rate(
    T::FT; p::NamedTuple = SB3_FREEZING, T_3::FT = FT(SB3_PHYSICS.T_3),
) where {FT} =
    FT(p.A_het) * exp(FT(p.B_het) * (T_3 - max(FT(p.tlimhetfreeze), T)) - one(FT))

"""
    sb3_droplet_freezing_rate(n_cloud, q_cloud, x_cloud, J; moment)

Cloud droplets freezing at rate `J`, as `(; dn_cloud_liquid, dq_cloud_liquid)` [per second]
(`modbulkmicro3.f90:5944-5945` and `:5766-5767`, which are the same two lines with a different
`J`).

```
dn = −c_mmt_1cl n_cl x_cl J
dq = −c_mmt_2cl q_cl x_cl J
```

`J` is [`sb3_homogeneous_nucleation_rate`](@ref) or
[`sb3_heterogeneous_nucleation_rate`](@ref); the moments come from
[`SB3_DERIVED`](@ref)`.moment`. Both tendencies are losses, and the frozen mass and number
appear as cloud ice.
"""
function sb3_droplet_freezing_rate(
    n_cloud::FT, q_cloud::FT, x_cloud::FT, J::FT;
    moment::NamedTuple = SB3_DERIVED.moment.cloud_liquid,
) where {FT}
    return (;
        dn_cloud_liquid = -FT(moment.k1) * n_cloud * x_cloud * J,
        dq_cloud_liquid = -FT(moment.k2) * q_cloud * x_cloud * J,
    )
end

"""
    sb3_ice_multiplication_rate(T, dq_riming; p)

Hallett–Mossop rime splintering, as `(; dn_ice, dq_ice)` [per second]
(`modbulkmicro3.f90:9148-9157`).

`dn = c_spl · m₁ · m₂ · dq_riming` with two ramps clamped to `[0, 1]`: `m₁` rises from zero at
`tmp_min` to one at `tmp_opt`, and `m₂` falls from one at `tmp_opt` to zero at `tmp_max`. So
splintering is confined to roughly −8 °C to −3 °C and peaks at `tmp_opt`.

Zero unless riming is actually depositing mass. Each splinter carries `x_ci_spl`.
"""
function sb3_ice_multiplication_rate(
    T::FT, dq_riming::FT;
    p::NamedTuple = SB3_MULTIPLICATION, T_3::FT = FT(SB3_PHYSICS.T_3),
) where {FT}
    (dq_riming > zero(FT) && T < T_3) || return (; dn_ice = zero(FT), dq_ice = zero(FT))
    rising = (T - FT(p.tmp_min_hm74)) / (FT(p.tmp_opt_hm74) - FT(p.tmp_min_hm74))
    falling = (T - FT(p.tmp_max_hm74)) / (FT(p.tmp_opt_hm74) - FT(p.tmp_max_hm74))
    weight = clamp(rising, zero(FT), one(FT)) * clamp(falling, zero(FT), one(FT))
    dn_ice = FT(p.c_spl_hm74) * weight * dq_riming
    return (; dn_ice, dq_ice = FT(p.x_ci_spl) * dn_ice)
end

"""
    sb3_rain_terminal_velocity(λ, ρ; moment, p)

Rain fall speed [m/s] on the `l_sb_classic` branch
(`modbulkmicro3.f90:4121-4124`).

`max(0, (ρ_ref/ρ)^(1/2) [a_tvsbc − b_tvsbc (1 + c_tvsbc/λ)^(−e)])`, with `e = 4` for the mass
(`moment = 1`) and `e = 1` for the number (`moment = 0`). `λ` is the slope from
[`sb3_rain_dsd`](@ref).

Rain is the one species that does **not** sediment through
[`sb3_sedimentation_speed`](@ref): it has no `c_v` moments in [`SB3_DERIVED`](@ref), and
unlike the ice species it carries a density correction.
"""
function sb3_rain_terminal_velocity(
    λ::FT, ρ::FT;
    moment::Integer = 1,
    p::NamedTuple = SB3_SEDIMENTATION,
    ρ_ref::FT = FT(SB3_PHYSICS.ρ_ref),
) where {FT}
    exponent = moment == 1 ? 4 : moment == 0 ? 1 :
               error("`moment` is 1 for the mass or 0 for the number, got $moment.")
    shape = (one(FT) + FT(p.c_tvsbc) / λ)^(-exponent)
    return max(zero(FT), sqrt(ρ_ref / ρ) * (FT(p.a_tvsbc) - FT(p.b_tvsbc) * shape))
end

"""
    sb3_sedimentation_flux(w, content, ρ)

Downward flux of a species through a level, `w · content · ρ`
(`modbulkmicro3.f90:4378-4379`).

`content` is per unit mass — a mixing ratio for the mass flux, a specific number for the
number flux — so the density converts it to per unit volume.
"""
sb3_sedimentation_flux(w::FT, content::FT, ρ::FT) where {FT} = w * content * ρ

"""
    sb3_sedimentation_substeps(w_max, dt, dz_min; split_factor)

How many sub-steps sedimentation is split into,
`ceil(split_factor · w_max · Δt / min(Δz))` (`modbulkmicro3.f90:4095`).

The Courant number of the fastest-falling particle over the thinnest layer, times a safety
factor. `w_max` is [`sb3_max_fall_speed`](@ref) for the species.
"""
function sb3_sedimentation_substeps(
    w_max::FT, dt::FT, dz_min::FT; split_factor::FT = FT(SB3_SEDIMENTATION.split_factor),
) where {FT}
    dz_min > zero(FT) || error("`dz_min` must be positive, got $dz_min.")
    return ceil(Int, split_factor * w_max * dt / dz_min)
end
