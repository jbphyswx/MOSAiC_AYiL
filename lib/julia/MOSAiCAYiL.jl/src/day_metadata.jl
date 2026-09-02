"""
    day_metadata.jl

Accessors for the committed structure-of-arrays in `generated/day_metadata.jl`: the
`scm_in` level count and the global attributes that differ between days, with no I/O.
"""

_meta(field, i) = getfield(DAY_METADATA, field)[i]

"""
    scm_in_levels(c)

Full levels in this day's `scm_in`, which is a property of the day: 3037 on 9 days, 3038 on
79, 3039 on 48, 3040 on 21, 3041 on 24 and 3042 on 9.
"""
scm_in_levels(c) = _meta(:n_levels, _day_index(c))

"""
    inversion_height(c)

The inversion height [m] of this day's first LES record, the tabulated result of
[`inversion_height(ᶜθ_l, z, z_min, z_max)`](@ref) over
[`INVERSION_SEARCH_MIN`](@ref)–[`INVERSION_SEARCH_MAX`](@ref).
"""
inversion_height(c) = _meta(:inversion_height, _day_index(c))

"""Observed skin temperature [K] the day's `tskin_seaice_correction` was built against."""
tskin_obs(c) = _meta(:tskin_obs, _day_index(c))

"""Correction [K] added to the ERA5 sea-ice skin temperature to match the MOSAiC observations."""
tskin_seaice_correction(c) = _meta(:tskin_seaice_correction, _day_index(c))

"""
    inp_fletcher_n(c)

`N` [m^-3] of this day's Fletcher ice-nucleus formula, estimated from the Polarstern
observations. DALES reads it as `N_inuc_R` and forms
`n = N exp(b (T_3 - max(T, c_inuc_R))) / rho` (`modbulkmicro3.f90:3652`).
"""
inp_fletcher_n(c) = _meta(:in_n_inucr, _day_index(c))

"""`b` [K^-1] of the same formula, DALES's `b_inuc_R`."""
inp_fletcher_b(c) = _meta(:in_b_inucr, _day_index(c))

"""
    cloud_top(c)

Cloud top [m] of this day, below its [`best_simulation_top`](@ref), with no I/O.

Defined on the 73 of [`best_dates`](@ref)'s 76 days whose cloud stops below the domain top;
the other three are [`CLOUD_TOP_UNDETERMINED`](@ref) and error rather than returning the
boundary itself.
"""
function cloud_top(c)
    key = date_string(c)
    return get(CLOUD_TOP_M, key) do
        key in CLOUD_TOP_UNDETERMINED && error(
            "AYiL day $key has cloud reaching its domain top, so no cloud top below it \
             is defined.",
        )
        error(
            "AYiL day $key is not one of the $(length(CLOUD_TOP_M)) days a cloud top is \
             tabulated for; `best_dates()` lists the days it is derived on.",
        )
    end
end

"""Per-day `scm_in` metadata as a NamedTuple, with no I/O."""
day_metadata(c) = (;
    n_levels = scm_in_levels(c),
    inversion_height = inversion_height(c),
    tskin_obs = tskin_obs(c),
    tskin_seaice_correction = tskin_seaice_correction(c),
    in_n_inucr = inp_fletcher_n(c),
    in_b_inucr = inp_fletcher_b(c),
)
