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
    "20200419" => 4517.39,
    "20200127" => 11857.2,
    "20200706" => 4823.92,
    "20200110" => 11857.2,
    "20200710" => 11857.2,
    "20200503" => 11857.2,
    "20200713" => 11857.2,
    "20191029" => 11857.2,
    "20200709" => 11857.2,
    "20200209" => 4166.48,
    "20200724" => 6177.97,
    "20200211" => 11857.2,
    "20200715" => 11857.2,
    "20191201" => 11857.2,
    "20200714" => 11857.2,
    "20191022" => 4248.64,
    "20191108" => 11857.2,
    "20200304" => 11857.2,
    "20200903" => 11857.2,
    "20191031" => 11857.2,
    "20191114" => 11857.2,
    "20191230" => 11857.2,
    "20200723" => 11857.2,
    "20200829" => 11857.2,
    "20191209" => 11857.2,
    "20200227" => 4823.92,
    "20200909" => 11857.2,
    "20200420" => 11857.2,
    "20200416" => 11857.2,
    "20200429" => 665.0,
    "20200911" => 11857.2,
    "20200418" => 11857.2,
    "20191218" => 11857.2,
    "20200831" => 11857.2,
    "20200826" => 11857.2,
    "20200103" => 11857.2,
    "20200827" => 2992.58,
    "20200707" => 3737.98,
    "20200409" => 3802.57,
    "20191219" => 4823.92,
    "20191213" => 6512.34,
    "20200905" => 11857.2,
    "20200124" => 3158.57,
    "20200828" => 11857.2,
    "20191221" => 11857.2,
    "20191225" => 11857.2,
    "20200726" => 11857.2,
    "20200502" => 11857.2,
    "20200901" => 3802.57,
    "20200224" => 11857.2,
    "20200210" => 2808.79,
    "20191210" => 11857.2,
    "20191103" => 11857.2,
    "20200307" => 11857.2,
    "20200410" => 4248.64,
    "20200708" => 11857.2,
    "20200907" => 11857.2,
    "20191125" => 11857.2,
    "20191016" => 11857.2,
    "20200830" => 11857.2,
    "20200425" => 11857.2,
    "20191028" => 6864.91,
    "20191030" => 11857.2,
    "20191024" => 11857.2,
    "20191101" => 11857.2,
    "20200216" => 3032.35,
    "20200415" => 4717.19,
    "20200717" => 875.0,
    "20191217" => 11857.2,
    "20200702" => 2273.43,
    "20200720" => 11857.2,
    "20200721" => 2099.65,
    "20200725" => 8157.23,
    "20200906" => 1983.08,
    "20191115" => 11857.2,
    "20200902" => 11857.2,
)

"""Filter centres snapped to the [`LES_FACES`](@ref) face at or above each."""
const RAW_BEST_SIMULATION_TOP_F = Dict{String, Float64}(
    k => Float64(face_above_center(v)) for (k, v) in RAW_BEST_SIMULATION_TOP_C
)

"""
Hand-collapsed domain tops [m] for the 76 days with comparable reference ice.

19 days are hand-set to 2500 m (12) or 5000 m (7) and 52 run the full column. 
"""
const BEST_SIMULATION_TOP_F = let
    d = Dict{String, Float64}(RAW_BEST_SIMULATION_TOP_F)
    d["20200210"] = 2500.0
    d["20200827"] = 2500.0
    d["20200216"] = 2500.0
    d["20200124"] = 2500.0
    d["20200707"] = 2500.0
    d["20200409"] = 2500.0
    d["20200901"] = 5000.0
    d["20200209"] = 5000.0
    d["20191022"] = 5000.0
    d["20200410"] = 5000.0
    d["20200419"] = 2500.0
    d["20200415"] = 5000.0
    d["20191219"] = 5000.0
    d["20200227"] = 5000.0
    d["20200706"] = 2500.0
    d["20200724"] = 2500.0
    d["20191213"] = 2500.0
    d["20191028"] = 2500.0
    d["20200725"] = 2500.0
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
