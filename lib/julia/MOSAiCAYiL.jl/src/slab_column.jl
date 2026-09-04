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
    path = les_profiles_path(date; root)
    isfile(path) || error("No DALES output at $path")
    z, t, presh, rhof, θ_l, θ_v, q_tot, q_liq, u, v = NC.NCDataset(path, "r") do ds
        (
            FT.(vec(Array(ds["zt"]))),
            FT.(vec(Array(NC.variable(ds, "time")))),
            FT.(_read_oriented(ds, "presh")),
            FT.(_read_oriented(ds, "rhof")),
            FT.(_read_oriented(ds, "thl")),
            FT.(_read_oriented(ds, "thv")),
            FT.(_read_oriented(ds, "qt")),
            FT.(_read_oriented(ds, "ql")),
            FT.(_read_oriented(ds, "u")),
            FT.(_read_oriented(ds, "v")),
        )
    end::Tuple{
        Vector{FT}, Vector{FT}, Matrix{FT}, Matrix{FT}, Matrix{FT},
        Matrix{FT}, Matrix{FT}, Matrix{FT}, Matrix{FT}, Matrix{FT},
    }

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
        z, time = t, ps, presh, presf, exner = Π, rhof,
        θ, θ_l, θ_v, T, q_tot, q_liq, u, v,
    )
end

dales_slab_column(c::MOSAiCAYiLCase, ::Type{FT} = Float32; kwargs...) where {FT} =
    dales_slab_column(date_string(c), FT; kwargs...)