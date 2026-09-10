"""
    ayil_info.jl

Curated ice-usable domain tops. Not re-derived at runtime: the heights are a
filter plus a per-day hand check collapsed onto 2500 m / 5000 m / the full
column. Days absent from the table error on [`best_simulation_top`](@ref).
"""

"""
Filter-output centres [m] before snapping to a face. Regenerate with
[`best_z_maxs`](@ref) in `ice_filters.jl`.
"""
const RAW_BEST_SIMULATION_TOP_C = Dict{String, Float64}(
    "20191016" => 11857.2,
    "20191022" => 4248.64,
    "20191024" => 11857.2,
    "20191028" => 6864.91,
    "20191029" => 11857.2,
    "20191030" => 11857.2,
    "20191031" => 11857.2,
    "20191101" => 11857.2,
    "20191103" => 11857.2,
    "20191108" => 11857.2,
    "20191114" => 11857.2,
    "20191115" => 11857.2,
    "20191125" => 11857.2,
    "20191201" => 11857.2,
    "20191209" => 11857.2,
    "20191210" => 11857.2,
    "20191213" => 6512.34,
    "20191217" => 11857.2,
    "20191218" => 11857.2,
    "20191219" => 4823.92,
    "20191221" => 11857.2,
    "20191225" => 11857.2,
    "20191230" => 11857.2,
    "20200103" => 11857.2,
    "20200110" => 11857.2,
    "20200124" => 3158.57,
    "20200127" => 11857.2,
    "20200209" => 4166.48,
    "20200210" => 2808.79,
    "20200211" => 11857.2,
    "20200216" => 3032.35,
    "20200224" => 11857.2,
    "20200227" => 4823.92,
    "20200304" => 11857.2,
    "20200307" => 11857.2,
    "20200409" => 3802.57,
    "20200410" => 4248.64,
    "20200415" => 4717.19,
    "20200416" => 11857.2,
    "20200418" => 11857.2,
    "20200419" => 4517.39,
    "20200420" => 11857.2,
    "20200425" => 11857.2,
    "20200429" => 665.0,
    "20200502" => 11857.2,
    "20200503" => 11857.2,
    "20200702" => 2273.43,
    "20200706" => 4823.92,
    "20200707" => 3737.98,
    "20200708" => 11857.2,
    "20200709" => 11857.2,
    "20200710" => 11857.2,
    "20200713" => 11857.2,
    "20200714" => 11857.2,
    "20200715" => 11857.2,
    "20200717" => 875.0,
    "20200720" => 11857.2,
    "20200721" => 2099.65,
    "20200723" => 11857.2,
    "20200724" => 6177.97,
    "20200725" => 8157.23,
    "20200726" => 11857.2,
    "20200826" => 11857.2,
    "20200827" => 2992.58,
    "20200828" => 11857.2,
    "20200829" => 11857.2,
    "20200830" => 11857.2,
    "20200831" => 11857.2,
    "20200901" => 3802.57,
    "20200902" => 11857.2,
    "20200903" => 11857.2,
    "20200905" => 11857.2,
    "20200906" => 1983.08,
    "20200907" => 11857.2,
    "20200909" => 11857.2,
    "20200911" => 11857.2,
)


"""Filter centres snapped to the [`LES_FACES`](@ref) face at or above each."""
const RAW_BEST_SIMULATION_TOP_F = Dict{String, Float64}(
    k => Float64(face_above_center(v)) for (k, v) in RAW_BEST_SIMULATION_TOP_C
)

"""
Hand-collapsed domain tops [m] for the 76 days with comparable reference ice.

19 days are hand-set to 1000 m (2), 2500 m (12) or 5000 m (7) and 52 run the full column. 
"""


const BEST_SIMULATION_TOP_F = let
    d = Dict{String, Float64}(RAW_BEST_SIMULATION_TOP_F)

    d["20191022"] = 2500.0 # 5000 is too high
    d["20191028"] = 2500.0
    d["20191213"] = 2500.0
    d["20191219"] = 5000.0
    d["20200124"] = 2500.0
    d["20200210"] = 2500.0
    d["20200216"] = 2500.0
    d["20200227"] = 5000.0
    d["20200409"] = 2500.0
    d["20200410"] = 2500.0 # 5000 is too high
    d["20200415"] = 5000.0
    d["20200419"] = 2500.0
    d["20200706"] = 2500.0
    d["20200707"] = 2500.0
    d["20200717"] = 1000.0
    d["20200721"] = 1000.0
    d["20200724"] = 2500.0
    d["20200725"] = 2500.0
    d["20200827"] = 2500.0
    d["20200901"] = 2500.0 # 5000 is too high

    delete!(d, "20191029") # cloud top too short
    # delete!(d, "20191031") # cloud top too short
    delete!(d, "20191125") # has a miniscule cloud near 5km but majority is below 200m
    # delete!(d, "20191213") # cloud top too short (3-400m)
    # delete!(d, "20191219") # cloud top too short (250m)
    delete!(d, "20200103") # cloud top too short (150m)
    # delete!(d, "20200110") # cloud top too short (400m)
    delete!(d, "20200124") # cloud top too short (165m)
    delete!(d, "20200209") # 5000 is too high, very minor cloud between 2500 and 5000m that is essentially attached to it.
    delete!(d, "20200211") # cloud top too short
    delete!(d, "20200425") # cloud top too short 
    delete!(d, "20200429") # transitions from all liq to all preexisting ice right about about 665. There's no physically good split.
    delete!(d, "20200702") # strong ice multiplication, could reasonably go to 5000-5700, but no good split btween that and the anomalous initial ice
    delete!(d, "20200706") # cloud top too short (has elevated ice but invalid)
    # delete!(d, "20200707") # cloud top too short (250m)
    delete!(d, "20200708") # cloud top too short (has elevated ice but invalid)
    # delete!(d, "20200714") # cloud top too short
    delete!(d, "20200725") # cloud top too short (165m)
    delete!(d, "20200726") # cloud top too short
    delete!(d, "20200902") # cloud top too short
    delete!(d, "20200906") # transitions from all liq to all preexisting ice right about about 1983. There's no physically good split.
    delete!(d, "20200910") # cloud top too short
    delete!(d, "20200911") # cloud top too short

    d
end

"""Days a comparison against the reference is meaningful on, ascending."""
best_dates() = sort!(collect(keys(BEST_SIMULATION_TOP_F)))

"""
    best_simulation_top(case)

The height [m] `case` is best simulated to, from [`BEST_SIMULATION_TOP_F`](@ref).

Errors on a day that table has no entry for: those are the days whose reference
ice is not easily reproducible at any height.
"""
function best_simulation_top(c::MOSAiCAYiLCase)
    key = date_string(c)
    return get(BEST_SIMULATION_TOP_F, key) do
        error(
            "AYiL day $key is not one of the $(length(BEST_SIMULATION_TOP_F)) \
             days a best simulation top is provided for.",
        )
    end
end






# ==================================================================================== #
#  Trimming low days (last-hour 99% of q_l+q_i mass below 400 m, only below the
#  ice-usable cap). Scoring window: t ≥ t_end − 3600 s (3600:300:7200).
# ------------------------------------------------------------------------------------ #
#=

| date     | z₉₉ max (m) | z₉₉ last (m) | path max (g/m²) | best |
| -------- | ----------: | -----------: | --------------: | :--: |
| 20191026 |         115 |          105 |           0.902 |      |
| 20191027 |         205 |          195 |            1.67 |      |
| 20191029 |         215 |          195 |            24.2 |  yes |
| 20191031 |         375 |          375 |            9.92 |  yes |
| 20191102 |         185 |          185 |            1.53 |      |
| 20191105 |         175 |          175 |            2.00 |      |
| 20191112 |         115 |          105 |         0.00352 |      |
| 20191113 |          55 |           55 |         0.00140 |      |
| 20191213 |         305 |          305 |            5.56 |  yes |
| 20191219 |         225 |          215 |            15.4 |  yes |
| 20191227 |         165 |          165 |           0.901 |      |
| 20200101 |         165 |          165 |            2.38 |      |
| 20200103 |         135 |          135 |           0.188 |  yes |
| 20200110 |         385 |          375 |            13.6 |  yes |
| 20200121 |         165 |          155 |            2.44 |      |
| 20200124 |         165 |          165 |            1.55 |  yes |
| 20200202 |         135 |          135 |         0.00586 |      |
| 20200205 |         135 |          135 |          0.0123 |      |
| 20200211 |         125 |          125 |          0.0239 |  yes |
| 20200215 |          85 |           85 |           0.106 |      |
| 20200226 |         205 |          205 |            2.82 |      |
| 20200228 |         115 |          115 |            1.18 |      |
| 20200308 |         205 |          205 |            4.10 |      |
| 20200324 |          75 |           75 |         0.00251 |      |
| 20200326 |         185 |          185 |            4.33 |      |
| 20200404 |         175 |          175 |            3.25 |      |
| 20200407 |         375 |          345 |           0.304 |      |
| 20200412 |         325 |          325 |          0.0806 |      |
| 20200425 |         205 |          205 |         0.00621 |  yes |
| 20200706 |         275 |          275 |            51.5 |  yes |
| 20200707 |         205 |          205 |            15.7 |  yes |
| 20200708 |         325 |          325 |            80.9 |  yes |
| 20200714 |         375 |          365 |            42.9 |  yes |
| 20200725 |         165 |          155 |            35.9 |  yes |
| 20200726 |         105 |          105 |            18.4 |  yes |
| 20200902 |         255 |          255 |            69.9 |  yes |
| 20200910 |         245 |          195 |            2.02 |      |
| 20200911 |         135 |          135 |            17.3 |  yes |



generated with ::




using MOSAiCAYiL: MOSAiCAYiL as MA

MA.data_available() || error("AYiL archive is not installed")

FRAC = 0.99
ZCUT = 400.0
PATH_MIN = 1.0e-6   # kg m^-2
SCORE_S = 3600.0    # last hour of PROFILES_TIME

tsec = collect(MA.PROFILES_TIME)
inds = findall(>=(maximum(tsec) - SCORE_S), tsec)

# Ice-usable cap: snapped RAW tops plus the 19 hand 2500/5000 values.
# Do not use BEST_SIMULATION_TOP_F after the low-cloud delete!s.
caps = Dict{String, Float64}(MA.RAW_BEST_SIMULATION_TOP_F)
for (k, v) in (
    "20200210" => 2500.0, "20200827" => 2500.0, "20200216" => 2500.0,
    "20200124" => 2500.0, "20200707" => 2500.0, "20200409" => 2500.0,
    "20200901" => 5000.0, "20200209" => 5000.0, "20191022" => 5000.0,
    "20200410" => 5000.0, "20200419" => 2500.0, "20200415" => 5000.0,
    "20191219" => 5000.0, "20200227" => 5000.0, "20200706" => 2500.0,
    "20200724" => 2500.0, "20191213" => 2500.0, "20191028" => 2500.0,
    "20200725" => 2500.0,
)
    caps[k] = v
end

function z99_column(z, ρ, q, faces, t, inside; frac = FRAC)
    tot = 0.0
    for k in inside
        tot += ρ[k, t] * q[k, t] * (faces[k + 1] - faces[k])
    end
    tot < PATH_MIN && return (NaN, tot)
    c = 0.0
    for k in inside
        c += ρ[k, t] * q[k, t] * (faces[k + 1] - faces[k])
        if c >= frac * tot
            return (Float64(z[k]), tot)
        end
    end
    return (Float64(z[inside[end]]), tot)
end

function day_z99(date)
    fields = MA.ice_fields(date, Float64; time_inds = Colon())
    key = MA.date_string(date)
    zcap = get(caps, key, last(fields.z))
    inside = findall(<=(zcap), fields.z)
    q = fields.q_liq .+ fields.q_ice
    faces = MA.vertical_metrics(fields.z).zh
    z_last, _ = z99_column(fields.z, fields.ρ, q, faces, last(inds), inside)
    z_max = -Inf
    path_max = 0.0
    n_cloud = 0
    for t in inds
        z99, path = z99_column(fields.z, fields.ρ, q, faces, t, inside)
        path > path_max && (path_max = path)
        isnan(z99) && continue
        n_cloud += 1
        z99 > z_max && (z_max = z99)
    end
    return (;
        date = key,
        z99_max = n_cloud == 0 ? NaN : z_max,
        z99_last = z_last,
        path_max,
        best = haskey(MA.RAW_BEST_SIMULATION_TOP_C, key),
    )
end

rows = [day_z99(date) for date in MA.MOSAiCAYiL_dates]
low = filter(r -> !isnan(r.z99_max) && r.z99_max < ZCUT, rows)

=#
