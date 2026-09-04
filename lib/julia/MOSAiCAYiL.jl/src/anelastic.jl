"""
    anelastic.jl

DALES's anelastic base state at `ibas_prf = 3` (`modstartup.f90:1320-1450`), and the
`baseprof.inp.001` the archive ships.
"""

"""
US standard-atmosphere breakpoints DALES steps through at `ibas_prf = 3`
(`modstartup.f90:1274-1275`): heights [m] and lapse rates [K/m].
"""
const STANDARD_ATMOSPHERE = (;
    z = (11000.0, 20000.0, 32000.0, 47000.0),
    lapse_rate = (-6.5e-3, 0.0, 1.0e-3, 2.8e-3),
)

"""The day whose `baseprof.inp.001` the archive ships in all 190 directories."""
const ARCHIVE_BASEPROF_DATE = "20200216"

# One isothermal-layer step of the standard atmosphere; DALES splits on the lapse rate
# because the pressure integral is a different closed form when it is zero.
function _standard_layer_pressure(p0::FT, T0::FT, z0::FT, z::FT, Γ::FT, R::FT, g::FT) where {FT}
    iszero(Γ) && return exp((log(p0) * T0 * R + z0 * g - z * g) / (T0 * R))
    return exp(
        (log(p0) * Γ * R + log(T0 + z0 * Γ) * g - log(T0 + z * Γ) * g) / (Γ * R),
    )
end

"""
    anelastic_base_density(ps, T_surface, z; backend, atmosphere)
    anelastic_base_density(case, [FT = Float64]; z = LES_CENTRES, backend, atmosphere)

DALES's anelastic base-state density `rhobf` [kg/m³] at `ibas_prf = 3`
(`modstartup.f90:1320-1356`) on the heights `z`: a **dry** standard atmosphere anchored on the
surface pressure and the surface temperature, `ρ = p / (R_d T)`.

The case method takes [`ps`](@ref) and [`t_skin`](@ref) from the day-scalar table and reads no
file. DALES anchors on `tsurf = thls (p_s/p_ref)^(R_d/c_p)`, which is the skin temperature
back again, since `thls` is that temperature divided by the same Exner factor.

This is a reference profile for the dynamics, the SFS diffusion and the Poisson solver. It is
not air density, which is `rhof` — see [`dales_slab_column`](@ref).
"""
function anelastic_base_density(
    ps::FT,
    T_surface::FT,
    z::AbstractVector{FT};
    backend = DefaultThermodynamicsBackend(),
    atmosphere = STANDARD_ATMOSPHERE,
) where {FT}
    R, g = R_d(backend, FT), grav(backend, FT)
    z_break = FT.(atmosphere.z)
    lapse = FT.(atmosphere.lapse_rate)
    length(z_break) == length(lapse) || error(
        "The atmosphere needs one lapse rate per breakpoint; got $(length(z_break)) and \
         $(length(lapse)).",
    )
    z_surface = zero(FT)

    p_break = Vector{FT}(undef, length(z_break))
    T_break = Vector{FT}(undef, length(z_break))
    p_break[1] = _standard_layer_pressure(
        ps, T_surface, z_surface, z_break[1], lapse[1], R, g,
    )
    T_break[1] = T_surface + lapse[1] * (z_break[1] - z_surface)
    for j in 2:length(z_break)
        p_break[j] = _standard_layer_pressure(
            p_break[j - 1], T_break[j - 1], z_break[j - 1], z_break[j], lapse[j], R, g,
        )
        T_break[j] = T_break[j - 1] + lapse[j] * (z_break[j] - z_break[j - 1])
    end

    ρ = Vector{FT}(undef, length(z))
    for (k, z_k) in pairs(z)
        p, T = if z_k < z_break[1]
            (
                _standard_layer_pressure(
                    ps, T_surface, z_surface, z_k, lapse[1], R, g,
                ),
                T_surface + lapse[1] * (z_k - z_surface),
            )
        else
            j = findfirst(>(z_k), z_break)
            isnothing(j) && error(
                "$z_k m is above the top standard-atmosphere breakpoint \
                 $(last(z_break)) m.",
            )
            (
                _standard_layer_pressure(
                    p_break[j - 1], T_break[j - 1], z_break[j - 1], z_k, lapse[j], R, g,
                ),
                T_break[j - 1] + lapse[j] * (z_k - z_break[j - 1]),
            )
        end
        ρ[k] = p / (R * T)
    end
    return ρ
end

function anelastic_base_density(
    c::MOSAiCAYiLCase, ::Type{FT} = Float64; z = LES_CENTRES, kwargs...,
) where {FT}
    return anelastic_base_density(FT(ps(c)), FT(t_skin(c)), FT.(z); kwargs...)
end

"""
    anelastic_base_state(ρ_f, z) -> (; rhobf, rhobh, drhobdzf, drhobdzh)

The four base-state arrays DALES carries, from the full-level density
(`modstartup.f90:1430-1450`). Each is `k1 = kmax + 1` long, matching the Fortran: `rhobf` is
extrapolated one level, `rhobh` interpolates it onto the half levels by `dzf` weight, and the
two derivatives follow.
"""
function anelastic_base_state(ρ_f::AbstractVector{FT}, z::AbstractVector{FT}) where {FT}
    kmax = length(ρ_f)
    kmax >= 2 || error("The base state needs at least two levels; got $kmax.")
    length(z) == kmax ||
        error("Got $kmax densities for $(length(z)) heights.")
    (; zf, zh, dzf, dzh) = vertical_metrics(z)
    k1 = kmax + 1

    rhobf = Vector{FT}(undef, k1)
    rhobf[1:kmax] .= ρ_f
    rhobf[k1] =
        ρ_f[kmax] +
        (zf[k1] - zf[kmax]) / (zf[kmax] - zf[kmax - 1]) * (ρ_f[kmax] - ρ_f[kmax - 1])

    rhobh = Vector{FT}(undef, k1)
    for k in 2:k1
        rhobh[k] =
            (rhobf[k] * dzf[k - 1] + rhobf[k - 1] * dzf[k]) / (dzf[k] + dzf[k - 1])
    end
    rhobh[1] = rhobf[1] - (rhobf[2] - rhobf[1]) * (zf[1] - zh[1]) / (zf[2] - zf[1])

    drhobdzf = Vector{FT}(undef, k1)
    for k in 1:kmax
        drhobdzf[k] = (rhobh[k + 1] - rhobh[k]) / dzf[k]
    end
    drhobdzf[k1] = drhobdzf[kmax]

    drhobdzh = Vector{FT}(undef, k1)
    drhobdzh[1] = 2 * (rhobf[1] - rhobh[1]) / dzh[1]
    for k in 2:k1
        drhobdzh[k] = (rhobf[k] - rhobf[k - 1]) / dzh[k]
    end

    return (; rhobf, rhobh, drhobdzf, drhobdzh)
end

"""
    read_baseprof(date; root = data_root())

The day directory's `baseprof.inp.001` as `(; z, rhobf)`.

The archive ships one file in all 190 directories, and it is
[`ARCHIVE_BASEPROF_DATE`](@ref)'s: DALES writes this file at start-up from the run's own
surface pressure and skin temperature and then re-reads it unconditionally
(`modstartup.f90:1357`, `:1419`), so every run overwrote it with its own.
[`anelastic_base_density`](@ref) gives the profile a given day ran on.

`z` is the file's own height column, which is written to one decimal (`1f7.1`);
[`LES_CENTRES`](@ref) carries the grid at full precision.
"""
function read_baseprof(date; root = data_root())
    path = baseprof_inp_path(date; root)
    isfile(path) || error("No baseprof.inp.001 at $path")
    return read_baseprof(eachline(path); source = path)
end

function read_baseprof(
    lines::Union{Base.EachLine, AbstractVector{<:AbstractString}};
    source = "the given lines",
)
    z, rhobf = Float64[], Float64[]
    for (i, line) in enumerate(lines)
        i <= 2 && continue
        stripped = strip(line)
        isempty(stripped) && continue
        parts = split(stripped)
        length(parts) >= 2 || continue
        push!(z, parse(Float64, parts[1]))
        push!(rhobf, parse(Float64, parts[2]))
    end
    isempty(rhobf) && error("Parsed no rows from $source")
    return (; z, rhobf)
end
