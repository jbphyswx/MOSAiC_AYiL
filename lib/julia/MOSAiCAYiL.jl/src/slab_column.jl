"""
    slab_column.jl

The slab-mean column of one AYiL day, including the full-level pressure the archive
does not store.
"""

"""
    dales_slab_column(date, [FT = Float32]; root, backend)

The slab-mean column of one AYiL day, as
`(; z, time, ps, presh, presf, exner, rhof, θ, θ_l, θ_v, T, q_tot, q_liq, u, v)`.

`z` is `zt` [m] and `time` [s]; every other field is `(length(z), length(time))`.
`FT` defaults to the archive's own `Float32`.

`presf` is the full-level pressure, which `profiles.001.nc` does not carry:
[`pressure_fromztop`](@ref) integrated from `ps = presh[1, t]` through the dry potential
temperature `θ`, which comes from the stored `θ_v` as
`θ_v / (1 + (R_v/R_d − 1) q_tot − (R_v/R_d) q_liq)`.

`q_tot` is DALES's `qt`, which is `q_vapour + q_liquid`; ice is carried as a separate
scalar. `rhof` is the thermodynamic air density, not the anelastic `rhobf`.
"""
function dales_slab_column(
    date,
    ::Type{FT} = Float32;
    root = data_root(),
    backend = DefaultThermodynamicsBackend(),
) where {FT}
    return open_archive(:profiles, date; root) do ds
        dales_slab_column(ds, FT; backend)
    end
end

function dales_slab_column(
    ds::NC.NCDataset,
    ::Type{FT} = Float32;
    backend = DefaultThermodynamicsBackend(),
) where {FT}
    return dales_slab_column(;
        z = FT.(vec(Array(ds["zt"]))),
        time = FT.(vec(Array(NC.variable(ds, "time")))),
        presh = FT.(_read_oriented(ds, "presh")),
        rhof = FT.(_read_oriented(ds, "rhof")),
        θ_l = FT.(_read_oriented(ds, "thl")),
        θ_v = FT.(_read_oriented(ds, "thv")),
        q_tot = FT.(_read_oriented(ds, "qt")),
        q_liq = FT.(_read_oriented(ds, "ql")),
        u = FT.(_read_oriented(ds, "u")),
        v = FT.(_read_oriented(ds, "v")),
        backend,
    )
end

function dales_slab_column(;
    z::AbstractVector{FT},
    time::AbstractVector{FT},
    presh::AbstractMatrix{FT},
    rhof::AbstractMatrix{FT},
    θ_l::AbstractMatrix{FT},
    θ_v::AbstractMatrix{FT},
    q_tot::AbstractMatrix{FT},
    q_liq::AbstractMatrix{FT},
    u::AbstractMatrix{FT},
    v::AbstractMatrix{FT},
    backend = DefaultThermodynamicsBackend(),
) where {FT}
    rvord = R_v(backend, FT) / R_d(backend, FT)
    θ = θ_v ./ (one(FT) .+ (rvord - one(FT)) .* q_tot .- rvord .* q_liq)

    ps = presh[1, :]
    presf = similar(θ)
    for k in eachindex(ps)
        presf[:, k] =
            pressure_fromztop(ps[k], θ[:, k], q_tot[:, k], q_liq[:, k], z; backend).presf
    end
    Π = exner.(backend, presf)
    T = temperature_from_liquid_pottemp.(backend, θ_l, presf, q_liq)

    return (;
        z, time, ps, presh, presf, exner = Π, rhof,
        θ, θ_l, θ_v, T, q_tot, q_liq, u, v,
    )
end

dales_slab_column(c::MOSAiCAYiLCase, ::Type{FT} = Float32; kwargs...) where {FT} =
    dales_slab_column(date_string(c), FT; kwargs...)

"""
    dales_rhof(date, [FT = Float32]; root = data_root())

`(; z, time, rhof)`: the slab-mean air density [kg/m³] of every level and time,
`profiles.001.nc`'s own `rhof`, on the axes it sits on.

This is the density [`read_variable`](@ref) converts a per-mass number with, and the
`rhof` of [`dales_slab_column`](@ref) without the pressure and temperatures that column
also derives. Not `rhobf` — that is [`anelastic_base_density`](@ref).
"""
dales_rhof(date, ::Type{FT} = Float32; root = data_root()) where {FT} =
    open_archive(:profiles, date; root) do ds
        dales_rhof(ds, FT)
    end

dales_rhof(ds::NC.NCDataset, ::Type{FT} = Float32) where {FT} = (;
    z = FT.(vec(Array(ds["zt"]))),
    time = FT.(vec(Array(NC.variable(ds, "time")))),
    rhof = FT.(_read_oriented(ds, "rhof")),
)

dales_rhof(c::MOSAiCAYiLCase, ::Type{FT} = Float32; kwargs...) where {FT} =
    dales_rhof(date_string(c), FT; kwargs...)