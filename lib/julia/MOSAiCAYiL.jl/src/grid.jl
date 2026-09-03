"""
    grid.jl

PRODUCTION and TEST horizontal grids, the stored DALES vertical faces, a formula
constructor that is *not* bit-identical in the stretch, and helpers for cutting and
thinning a face vector.
"""

"""
PRODUCTION grid (paper Table 2 / §2.3.1): 6.4 km domain, 20 m horizontal,
286 vertical levels.
"""
const PRODUCTION_GRID = (;
    lx = 6400.0,
    ly = 6400.0,
    dx = 20.0,
    dy = 20.0,
    nx = 320,
    ny = 320,
    nz = 286,
)

"""
TEST grid (paper Table 2, not a default): 800 m domain, 25 m horizontal,
same vertical grid as PRODUCTION.
"""
const TEST_GRID = (;
    lx = 800.0,
    ly = 800.0,
    dx = 25.0,
    dy = 25.0,
    nx = 32,
    ny = 32,
    nz = 286,
)

"""Paper Appendix A stretch parameters, used by [`stretch_faces`](@ref)."""
const STRETCH = (; kT = 120, s = 0.0125, ΔzStart = 10.0, kM = 260, ΔzEnd = 185.0, nz = 286)

"""
The 287 cell faces [m] of the DALES grid: uniform 10 m to 1220 m, geometric stretch,
then uniform ~185 m above 7139 m.

Written out because it is the same grid on all 190 days, and it is what every domain
top and every model grid is resolved against. These are the file's own `Float32`
values, so the literal reproduces it exactly rather than nearly.

`zm` holds the *lower* faces, so the top one is `zh(287) = 2 zt(286) - zm(286)`. Not
`zt[end] + 185/2`: the face recursion is unstable and leaves the thicknesses
alternating 184.147 / 185.853, so the last cell is 184.149 m thick and the nominal
half-spacing misses by 0.43 m.
"""
const LES_FACES = Float32[
    0.0f0, 10.0f0, 20.0f0, 30.0f0, 40.0f0, 50.0f0, 60.0f0, 70.0f0,
    80.0f0, 90.0f0, 100.0f0, 110.0f0, 120.0f0, 130.0f0, 140.0f0, 150.0f0,
    160.0f0, 170.0f0, 180.0f0, 190.0f0, 200.0f0, 210.0f0, 220.0f0, 230.0f0,
    240.0f0, 250.0f0, 260.0f0, 270.0f0, 280.0f0, 290.0f0, 300.0f0, 310.0f0,
    320.0f0, 330.0f0, 340.0f0, 350.0f0, 360.0f0, 370.0f0, 380.0f0, 390.0f0,
    400.0f0, 410.0f0, 420.0f0, 430.0f0, 440.0f0, 450.0f0, 460.0f0, 470.0f0,
    480.0f0, 490.0f0, 500.0f0, 510.0f0, 520.0f0, 530.0f0, 540.0f0, 550.0f0,
    560.0f0, 570.0f0, 580.0f0, 590.0f0, 600.0f0, 610.0f0, 620.0f0, 630.0f0,
    640.0f0, 650.0f0, 660.0f0, 670.0f0, 680.0f0, 690.0f0, 700.0f0, 710.0f0,
    720.0f0, 730.0f0, 740.0f0, 750.0f0, 760.0f0, 770.0f0, 780.0f0, 790.0f0,
    800.0f0, 810.0f0, 820.0f0, 830.0f0, 840.0f0, 850.0f0, 860.0f0, 870.0f0,
    880.0f0, 890.0f0, 900.0f0, 910.0f0, 920.0f0, 930.0f0, 940.0f0, 950.0f0,
    960.0f0, 970.0f0, 980.0f0, 990.0f0, 1000.0f0, 1010.0f0, 1020.0f0, 1030.0f0,
    1040.0f0, 1050.0f0, 1060.0f0, 1070.0f0, 1080.0f0, 1090.0f0, 1100.0f0, 1110.0f0,
    1120.0f0, 1130.0f0, 1140.0f0, 1150.0f0, 1160.0f0, 1170.0f0, 1180.0f0, 1190.0f0,
    1200.0f0, 1210.0f0, 1220.0f0, 1230.1648f0, 1240.3326f0, 1250.6676f0, 1261.0084f0, 1271.5194f0,
    1282.039f0, 1292.732f0, 1303.4366f0, 1314.3176f0, 1325.2136f0, 1336.2894f0, 1347.3834f0, 1358.6608f0,
    1369.96f0, 1381.4462f0, 1392.9583f0, 1404.6608f0, 1416.3932f0, 1428.3206f0, 1440.2819f0, 1452.4423f0,
    1464.6407f0, 1477.0436f0, 1489.489f0, 1502.1432f0, 1514.8455f0, 1527.7614f0, 1540.7306f0, 1553.9188f0,
    1567.1663f0, 1580.6382f0, 1594.1752f0, 1607.943f0, 1621.782f0, 1635.8586f0, 1650.0128f0, 1664.4116f0,
    1678.8951f0, 1693.6309f0, 1708.4587f0, 1723.5466f0, 1738.7347f0, 1754.1917f0, 1769.7572f0, 1785.6006f0,
    1801.5618f0, 1817.811f0, 1834.1874f0, 1850.8624f0, 1867.6757f0, 1884.798f0, 1902.0706f0, 1919.6642f0,
    1937.4204f0, 1955.5106f0, 1973.7769f0, 1992.391f0, 2011.1958f0, 2030.3634f0, 2049.7373f0, 2069.4907f0,
    2089.4675f0, 2109.8413f0, 2130.4575f0, 2151.4895f0, 2172.784f0, 2194.5159f0, 2216.532f0, 2239.0088f0,
    2261.7937f0, 2285.0647f0, 2308.6702f0, 2332.7896f0, 2357.2727f0, 2382.2998f0, 2407.7227f0, 2433.7236f0,
    2460.1553f0, 2487.2026f0, 2514.7195f0, 2542.8936f0, 2571.5808f0, 2600.9707f0, 2630.9229f0, 2661.6287f0,
    2692.9504f0, 2725.0835f0, 2757.8933f0, 2791.5786f0, 2826.0088f0, 2861.3867f0, 2897.5864f0, 2934.816f0,
    2972.9534f0, 3012.2136f0, 3052.4802f0, 3093.9746f0, 3136.5872f0, 3180.5476f0, 3225.754f0, 3272.444f0,
    3320.5269f0, 3370.2495f0, 3421.5315f0, 3474.6328f0, 3529.485f0, 3586.3616f0, 3645.2085f0, 3706.315f0,
    3769.6426f0, 3835.498f0, 3903.8604f0, 3975.0554f0, 4049.08f0, 4126.28f0, 4206.671f0, 4290.615f0,
    4378.146f0, 4469.64f0, 4565.141f0, 4665.0317f0, 4769.3564f0, 4878.4907f0, 4992.4624f0, 5111.62f0,
    5235.9517f0, 5365.7534f0, 5500.947f0, 5641.746f0, 5787.9805f0, 5939.7627f0, 6096.813f0, 6259.134f0,
    6426.3413f0, 6598.34f0, 6774.6636f0, 6955.1543f0, 7139.301f0, 7325.1543f0, 7509.301f0, 7695.1543f0,
    7879.301f0, 8065.1543f0, 8249.301f0, 8435.154f0, 8619.301f0, 8805.154f0, 8989.301f0, 9175.154f0,
    9359.301f0, 9545.154f0, 9729.301f0, 9915.154f0, 10099.301f0, 10285.154f0, 10469.301f0, 10655.154f0,
    10839.301f0, 11025.154f0, 11209.301f0, 11395.154f0, 11579.301f0, 11765.154f0, 11949.301f0,
]

"""Top face [m] of the DALES grid, the last of [`LES_FACES`](@ref)."""
const LES_TOP_FACE = last(LES_FACES)

"""
The 286 cell-centre heights [m] of the DALES grid, `(zh[k] + zh[k+1])/2` over
[`LES_FACES`](@ref).

That is the exact inverse of the recursion `zh[k+1] = zh[k] + 2(zf[k] − zh[k])` DALES builds
its faces with (`modglobal.f90:429-431`), so this recurses back to `LES_FACES` bit for bit.
The heights DALES read are `prof.inp.001` column 1, which these reproduce to 2.1e-4 m — the
scale of the archive's own `zt` rounding.
"""
const LES_CENTRES = [
    (Float64(LES_FACES[k]) + Float64(LES_FACES[k + 1])) / 2
    for k in 1:(length(LES_FACES) - 1)
]

"""First centre [m] of the DALES grid (`zt[1]`)."""
const LES_Z_CENTRE_BOTTOM = 5.0f0

"""Last centre [m] of the DALES grid (`zt[end]`)."""
const LES_Z_CENTRE_TOP = 11857.228f0

"""
    stretch_dz([FT = Float64]; kT, s, ΔzStart, kM, ΔzEnd, nz)

Cell thicknesses [m] from paper Appendix A / `modglobal.f90`: `Δz = 10 m` for
`k ≤ kT`, then `10·(1+s)^(k−kT−1)`, then `ΔzEnd` for `k ≥ kM`.
"""
function stretch_dz(
    ::Type{FT} = Float64
    ;
    kT::Int = STRETCH.kT,
    s::FT = FT(STRETCH.s),
    ΔzStart::FT = FT(STRETCH.ΔzStart),
    kM::Int = STRETCH.kM,
    ΔzEnd::FT = FT(STRETCH.ΔzEnd),
    nz::Int = STRETCH.nz,
) where {FT}
    dz = Vector{FT}(undef, nz)
    for k in 1:nz
        dz[k] = if k <= kT
            FT(ΔzStart)
        elseif k >= kM
            FT(ΔzEnd)
        else
            FT(ΔzStart) * (1 + FT(s))^(k - kT - 1)
        end
    end
    return dz
end

"""
    stretch_centres([FT = Float64]; kwargs...)

Cell-centre heights [m] from [`stretch_dz`](@ref). First centre is `Δz[1]/2`.
"""
function stretch_centres(::Type{FT} = Float64; kwargs...) where {FT}
    dz = stretch_dz(FT; kwargs...)
    zt = similar(dz)
    zt[1] = dz[1] / FT(2)
    for k in 2:length(dz)
        zt[k] = zt[k - 1] + (dz[k - 1] + dz[k]) / FT(2)
    end
    return zt
end

"""
    stretch_faces([FT = Float64]; kwargs...)

Cell faces [m] from the formula centres via `zh(1)=0`, `zh(k+1)=2·zt(k)−zh(k)`.

Not bit-identical to [`LES_FACES`](@ref) in the stretch and in the
alternating-thickness region of the 185 m layers. Use [`LES_FACES`](@ref) as the
production grid.
"""
function stretch_faces(::Type{FT} = Float64; kwargs...) where {FT}
    zt = stretch_centres(FT; kwargs...)
    zh = Vector{eltype(zt)}(undef, length(zt) + 1)
    zh[1] = zero(eltype(zt))
    for k in 1:length(zt)
        zh[k + 1] = 2 * zt[k] - zh[k]
    end
    return zh
end

"""
    face_above_center(z, faces = LES_FACES)

The face at or above `z` [m]. Errors if `z` is above the top face.
"""
function face_above_center(z, faces::AbstractVector = LES_FACES)
    k = findfirst(>=(z), faces)
    isnothing(k) && error("$z m is above the faces top face $(last(faces)) m.")
    return faces[k]
end

"""
    truncate_faces_to_top(faces, z_top)

`faces` cut at `z_top`: every face below it, then `z_top` itself as the new top
face. `nothing` leaves the column alone.
"""
function truncate_faces_to_top(faces::AbstractVector, z_top)
    isnothing(z_top) && return faces
    top = convert(eltype(faces), z_top)
    top > first(faces) || error(
        "A domain top of $top m is not above the surface face $(first(faces)) m.",
    )
    kept = filter(<(top), faces)
    push!(kept, top)
    length(kept) >= 2 ||
        error("A domain top of $top m leaves no cells above $(first(faces)) m.")
    return kept
end

"""
    coarsen_faces_to_dz_min(faces, dz_min)

`faces` with interior faces dropped so every cell is at least `dz_min` thick,
keeping the bottom and top.
"""
function coarsen_faces_to_dz_min(faces::AbstractVector, dz_min)
    length(faces) >= 2 || error("A grid needs at least two faces, got $(length(faces))")
    isnothing(dz_min) && return faces
    minimum(diff(faces)) >= dz_min && return faces
    kept = [first(faces)]
    for f in faces[2:(end - 1)]
        (f - last(kept)) >= dz_min && push!(kept, f)
    end
    (last(faces) - last(kept)) >= dz_min ? push!(kept, last(faces)) :
    (kept[end] = last(faces))
    length(kept) >= 2 || error(
        "dz_min = $dz_min m leaves no cells in a column of depth \
         $(last(faces) - first(faces)) m.",
    )
    return kept
end

"""Native DALES faces of a case — the same [`LES_FACES`](@ref) on every day."""
native_faces(::MOSAiCAYiLCase) = LES_FACES

"""Domain top [m]: the top face of the DALES grid."""
z_max(::MOSAiCAYiLCase) = LES_TOP_FACE

# --- Hydrostatic column ----------------------------------------------------- #

"""
    pressure_from_face(p_face, ρ, z_center, z_face; backend)

Cell-centre pressure [Pa], which the archive does not carry, as one hydrostatic step up from
the face below.

`profiles.001.nc`'s `presh` is DALES's **half**-level pressure, not centre. 

Use this when a face pressure is what you have; [`pressure_fromztop`](@ref) is the other
route, DALES's own bottom-up integration from `ps`, which needs the whole column.
"""
function pressure_from_face(
    p_face, ρ, z_center, z_face; backend = DefaultThermodynamicsBackend(),
)
    FT = float(
        promote_type(
            nonmissingtype(eltype(p_face)), nonmissingtype(eltype(ρ)),
            nonmissingtype(eltype(z_center)), nonmissingtype(eltype(z_face)),
        ),
    )
    g = grav(backend, FT)
    return @. p_face - ρ * g * (z_center - z_face)
end

"""
    vertical_metrics(zf) -> (; zf, zh, dzf, dzh)

DALES's full-level metrics from the `kmax` full-level heights (`modglobal.f90` `initglobal`).

Half levels come from `zh[k+1] = zh[k] + 2(zf[k] − zh[k])` with `zh[1] = 0`; the returned
`zf` is extended by one level so it is `k1 = kmax + 1` long, matching the Fortran. `zh` is
`kmax + 1` long, the faces of the `kmax` cells.
"""
function vertical_metrics(zf_in::AbstractVector{FT}) where {FT}
    kmax = length(zf_in)
    kmax >= 1 || error("zf must have at least one level")
    zh = zeros(FT, kmax + 1)
    for k in 1:kmax
        zh[k + 1] = zh[k] + 2 * (zf_in[k] - zh[k])
    end
    zf = Vector{FT}(undef, kmax + 1)
    zf[1:kmax] .= zf_in
    zf[kmax + 1] = zf_in[kmax] + 2 * (zh[kmax + 1] - zf_in[kmax])
    dzf = Vector{FT}(undef, kmax + 1)
    for k in 1:kmax
        dzf[k] = zh[k + 1] - zh[k]
    end
    dzf[kmax + 1] = dzf[kmax]
    dzh = Vector{FT}(undef, kmax + 1)
    dzh[1] = 2 * zf[1]
    for k in 2:(kmax + 1)
        dzh[k] = zf[k] - zf[k - 1]
    end
    return (; zf, zh, dzf, dzh)
end

"""
    pressure_fromztop(ps, θ, q_tot, q_liq, zf; backend) -> (; presf, presh)

Hydrostatic pressure [Pa] on the full and half levels, integrated upward from `ps` — a port
of DALES's `fromztop` (`modthermodynamics.f90:321-384`), which is how the archive's pressure
was formed.

`θ` is the **dry** potential temperature on the full levels, DALES's `th0av`, which it forms
from the liquid-ice one as `θ = θ_l + (L_v/c_p) q_l / Π` (`:263`). Passing `θ_l` instead is
wrong wherever there is liquid. `q_tot` and `q_liq` are the domain means beside it, and `zf`
is the full-level height array [`vertical_metrics`](@ref) is built from.

The two are different quantities and neither substitutes for the other: `presf` steps
through half-level `θ_v` over `dzh`, while `presh` starts at `ps` and steps through
full-level `θ_v` over `dzf`. The archive's stored `presh` is the half-level one despite
sitting on `zt`
"""
function pressure_fromztop(
    ps::FT,
    θ::AbstractVector{FT},
    q_tot::AbstractVector{FT},
    q_liq::AbstractVector{FT},
    zf_in::AbstractVector{FT};
    backend = DefaultThermodynamicsBackend(),
) where {FT}
    k1 = length(θ)
    (length(q_tot) == k1 && length(q_liq) == k1) || error(
        "θ, q_tot and q_liq must have the same length; got $k1, $(length(q_tot)), \
         $(length(q_liq)).",
    )
    (; zf, dzf, dzh) = vertical_metrics(zf_in)
    length(zf) >= k1 || error("zf gives $(length(zf)) levels for $k1 profile levels.")

    κ = R_d(backend, FT) / cp_d(backend, FT)
    g = grav(backend, FT)
    cp = cp_d(backend, FT)
    p0 = p_ref(backend, FT)
    rvord = R_v(backend, FT) / R_d(backend, FT)
    θ_v(k) = θ[k] * (one(FT) + (rvord - one(FT)) * q_tot[k] - rvord * q_liq[k])

    presf = Vector{FT}(undef, k1)
    presf[1] = (ps^κ - g * (p0^κ) * zf[1] / (cp * θ_v(1)))^(one(FT) / κ)
    for k in 2:k1
        θh = (θ[k] * dzf[k - 1] + θ[k - 1] * dzf[k]) / (2 * dzh[k])
        qth = (q_tot[k] * dzf[k - 1] + q_tot[k - 1] * dzf[k]) / (2 * dzh[k])
        qlh = (q_liq[k] * dzf[k - 1] + q_liq[k - 1] * dzf[k]) / (2 * dzh[k])
        thvh = θh * (one(FT) + (rvord - one(FT)) * qth - rvord * qlh)
        presf[k] = (presf[k - 1]^κ - g * (p0^κ) * dzh[k] / (cp * thvh))^(one(FT) / κ)
    end

    presh = Vector{FT}(undef, k1)
    presh[1] = ps
    for k in 2:k1
        presh[k] = (presh[k - 1]^κ - g * (p0^κ) * dzf[k - 1] / (cp * θ_v(k - 1)))^(one(FT) / κ)
    end
    return (; presf, presh)
end
