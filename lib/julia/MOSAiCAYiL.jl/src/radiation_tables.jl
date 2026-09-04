"""
    radiation_tables.jl

The optical tables `modradfull` ran on, and the interpolation it reaches them with.
"""

"""
The 18 bands of the AYiL radiation, from `ckd.inp.001` (`modradfull.f90:2670-2687`).

`edge` [cm^-1] is 19 long and descending, so band `i` spans `edge[i + 1]` to `edge[i]` and its
centre is their mean. `power` [W/m^2] is 18 long and zero on the twelve infrared bands; the six
solar bands sum to [`SOLAR_TOTAL_POWER`](@ref).
"""
const RADIATION_BANDS = (;
    edge = (
        50000.0, 14500.0, 7700.0, 5250.0, 4000.0, 2850.0, 2500.0, 1900.0, 1700.0,
        1400.0, 1250.0, 1100.0, 980.0, 800.0, 670.0, 540.0, 400.0, 280.0, 0.0,
    ),
    power = (
        619.6, 484.3, 149.8, 48.73, 31.66, 5.799, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    ),
)

"""
Sum of the solar band powers [W/m^2], DALES's `totalpower`.

`modradfull` scales its shortwave fluxes by `sw0/totalpower`, with `sw0 = 1368.22`
(`modraddata.f90:59`).
"""
const SOLAR_TOTAL_POWER = 1339.889

"""
Trace-gas volume mixing ratios the AYiL radiation used, `ckd.inp.001`'s `default_conc`.

CO2 is carried by the two `OVRLP` blocks of bands 14 and 15, CH4 and N2O by their blocks in
bands 10 and 11. H2O and O3 carry zero here and come from the column instead.
"""
const TRACE_GAS_CONCENTRATIONS = (; CO2 = 3.3e-4, CH4 = 1.6e-6, N2O = 2.8e-7)

"""
The 23 `(gas, band)` blocks of `ckd.inp.001`, in file order.

`OVRLP` is a two-gas overlap block, which is why the count exceeds the 18 bands.
"""
const RADIATION_GASES = (
    ("O3", 1), ("H2O", 2), ("H2O", 3), ("H2O", 4), ("H2O", 5), ("H2O", 6),
    ("H2O", 7), ("H2O", 8), ("H2O", 9), ("H2O", 10), ("CH4", 10), ("N2O", 10),
    ("H2O", 11), ("CH4", 11), ("N2O", 11), ("O3", 12), ("H2O", 12), ("H2O", 13),
    ("OVRLP", 14), ("OVRLP", 15), ("H2O", 16), ("H2O", 17), ("H2O", 18),
)

# `read (66,'(300(6E12.4,/))')` spreads a record over as many lines as it needs and consumes a
# trailing newline, so a numeric record is taken by count rather than by line.
function _ckd_reader(lines::AbstractVector{<:AbstractString}, source)
    cursor = Ref(1)
    function next_line()
        while cursor[] <= length(lines) && isempty(strip(lines[cursor[]]))
            cursor[] += 1
        end
        cursor[] <= length(lines) || error("$source ended early.")
        line = lines[cursor[]]
        cursor[] += 1
        return line
    end
    function reals(n::Integer)
        out = Float64[]
        while length(out) < n
            append!(out, parse.(Float64, split(strip(next_line()))))
        end
        length(out) == n ||
            error("Wanted $n values from $source and the record held $(length(out)).")
        return out
    end
    return (; next_line, reals, integers = () -> parse.(Int, split(strip(next_line()))))
end

"""
    read_ckd(date; root = data_root())

The correlated-k tables of `ckd.inp.001` as `(; nbands, edge, power, gases)`, parsed the way
`init_ckd` reads them (`modradfull.f90:2668-2725`).

Each gas carries `name, band, noverlap, ng, np, nt, molar_mass, default_concentration, tbase,
hk, sp, xk`, with `xk` shaped `(nt, np, ng, noverlap)` as the Fortran dimensions it. `hk` sums
to one for every gas, which is the condition DALES stops the run on.

A reader rather than a committed table: the k-distributions are 6820 numbers and nothing in
this package computes radiation. [`RADIATION_BANDS`](@ref),
[`TRACE_GAS_CONCENTRATIONS`](@ref) and [`RADIATION_GASES`](@ref) carry what describes the run.
"""
function read_ckd(date; root = data_root())
    path = ckd_inp_path(date; root)
    isfile(path) || error("No ckd.inp.001 at $path")
    return read_ckd(readlines(path); source = path)
end

function read_ckd(
    lines::AbstractVector{<:AbstractString}; source = "the given lines",
)
    (; next_line, reals, integers) = _ckd_reader(lines, source)

    nbands, ngases = integers()
    edge = reals(nbands + 1)
    power = reals(nbands)

    gases = map(1:ngases) do _
        header = next_line()
        name = String(strip(header[1:min(5, length(header))]))
        band = parse(Int, strip(header[6:min(9, length(header))]))
        noverlap, ng, np, nt = integers()
        molar_mass, default_concentration, tbase = reals(3)
        hk = reals(ng)
        sp = reals(np)
        # the file runs ng fastest, then np, then nt, then noverlap; `xk` is dimensioned
        # `(nt, np, ng, noverlap)`
        xk = permutedims(
            reshape(reals(ng * np * nt * noverlap), ng, np, nt, noverlap), (3, 2, 1, 4),
        )
        (;
            name, band, noverlap, ng, np, nt,
            molar_mass, default_concentration, tbase, hk, sp, xk,
        )
    end
    return (; nbands, edge, power, gases)
end

"""
    cloud_liquid_optics(band, water_content, r_eff; table, cutoff)

`(; extinction, single_scattering_albedo, asymmetry)` for cloud liquid in `band`, as
`modradfull.f90:3092-3113` interpolates [`CLOUD_LIQUID_OPTICS`](@ref): the mass extinction
linearly in `1/r_eff`, the albedo and the asymmetry linearly in `r_eff`, and the end row
outside the table rather than an extrapolation.

`water_content` is [kg/m³] and `r_eff` [μm]. `extinction` is [1/m], so a layer's optical
depth is `extinction * dz`. Below `cutoff` everything is zero, which is DALES's own
`cwmks < 1e-8` branch.
"""
function cloud_liquid_optics(
    band::Integer,
    water_content::FT,
    r_eff::FT;
    table = CLOUD_LIQUID_OPTICS,
    cutoff::FT = FT(1e-8),
) where {FT}
    nsizes, nbands = size(table.extinction)
    1 <= band <= nbands ||
        error("`band` must be in 1:$nbands, got $band.")
    water_content >= cutoff || return (;
        extinction = zero(FT),
        single_scattering_albedo = zero(FT),
        asymmetry = zero(FT),
    )

    radius(i) = FT(table.r_eff[i])
    mass_extinction(i) = FT(table.extinction[i, band]) / FT(table.water_content[i])
    albedo(i) = FT(table.single_scattering_albedo[i, band])
    asymmetry(i) = FT(table.asymmetry[i, band])

    j = 0
    while j < nsizes && r_eff > radius(j + 1)
        j += 1
    end

    β, ω, g = if 1 <= j < nsizes
        j1 = j + 1
        weight = (r_eff - radius(j)) / (radius(j1) - radius(j))
        (
            mass_extinction(j) +
            (mass_extinction(j1) - mass_extinction(j)) /
            (inv(radius(j1)) - inv(radius(j))) * (inv(r_eff) - inv(radius(j))),
            albedo(j) + (albedo(j1) - albedo(j)) * weight,
            asymmetry(j) + (asymmetry(j1) - asymmetry(j)) * weight,
        )
    else
        j0 = max(j, 1)
        (mass_extinction(j0), albedo(j0), asymmetry(j0))
    end

    return (;
        extinction = max(zero(FT), water_content * β),
        single_scattering_albedo = ω,
        asymmetry = g,
    )
end
