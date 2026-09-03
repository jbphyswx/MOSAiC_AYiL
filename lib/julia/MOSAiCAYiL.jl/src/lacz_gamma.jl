"""
    lacz_gamma.jl

DALES's own Γ, ported from `modglobal.f90:503-743`. The SB3 microphysics constants are
ratios of it, so the package derives them with the same routine that produced the archive's.
"""

# Rational-minimax coefficients over (1, 2), `modglobal.f90:625-634`.
const _LACZ_P = (
    -1.71618513886549492533811e+0, 2.47656508055759199108314e+1,
    -3.79804256470945635097577e+2, 6.29331155312818442661052e+2,
    8.66966202790413211295064e+2, -3.14512729688483675254357e+4,
    -3.61444134186911729807069e+4, 6.64561438202405440627855e+4,
)
const _LACZ_Q = (
    -3.08402300119738975254353e+1, 3.15350626979604161529144e+2,
    -1.01515636749021914166146e+3, -3.10777167157231109440444e+3,
    2.25381184209801510330112e+4, 4.75584627752788110767815e+3,
    -1.34659959864969306392456e+5, -1.15132259675553483497211e+5,
)

# Minimax coefficients over (12, ∞), `:638-642`.
const _LACZ_C = (
    -1.910444077728e-03, 8.4171387781295e-04, -5.952379913043012e-04,
    7.93650793500350248e-04, -2.777777777777681622553e-03,
    8.333333333333333331554247e-02, 5.7083835261e-03,
)

# `sqrtpi` in the Fortran is log(sqrt(2π)), not a square root of π; the name is the
# original's. `:614-620`.
const _LACZ_LOG_SQRT_2PI = 0.9189385332046727417803297
const _LACZ_XBIG = 171.624
const _LACZ_XMININ = 2.23e-308
const _LACZ_EPS = 2.22e-16
const _LACZ_XINF = 1.79e308

"""
    lacz_gamma(x)

Γ(x) for a real argument, as `modglobal.f90:503-743` computes it — the Cody & Stoltz
rational-minimax GAMMA, accurate to at least 20 significant digits.

Returns `1.79e308` at a pole or on overflow, which is the Fortran's error value rather than
an exception. `Float64` throughout, as DALES declares it `REAL(dp)`.

This is the routine that produced the archive's SB3 constants, so [`SB3_DERIVED`](@ref)
reproduces them by construction.
"""
function lacz_gamma(x::FT) where {FT}
    y = Float64(x)
    parity = false
    fact = 1.0
    n = 0

    if y <= 0
        y = -Float64(x)
        y1 = trunc(y)
        fractional = y - y1
        iszero(fractional) && return _LACZ_XINF   # a pole at every non-positive integer
        # the reflection changes sign on an odd integer part
        y1 != trunc(y1 * 0.5) * 2 && (parity = true)
        fact = -pi / sin(pi * fractional)
        y += 1
    end

    result = if y < _LACZ_EPS
        y >= _LACZ_XMININ ? 1 / y : return _LACZ_XINF
    elseif y < 12
        y1 = y
        z = if y < 1
            held = y
            y += 1
            held
        else
            n = Int(trunc(y)) - 1
            y -= n
            y - 1
        end
        numerator = 0.0
        denominator = 1.0
        for i in 1:8
            numerator = (numerator + _LACZ_P[i]) * z
            denominator = denominator * z + _LACZ_Q[i]
        end
        value = numerator / denominator + 1
        if y1 < y                       # 0 < x < 1
            value /= y1
        elseif y1 > y                   # 2 < x < 12
            for _ in 1:n
                value *= y
                y += 1
            end
        end
        value
    else
        y > _LACZ_XBIG && return _LACZ_XINF
        squared = y * y
        series = _LACZ_C[7]
        for i in 1:6
            series = series / squared + _LACZ_C[i]
        end
        series = series / y - y + _LACZ_LOG_SQRT_2PI
        exp(series + (y - 0.5) * log(y))
    end

    parity && (result = -result)
    return fact == 1 ? FT(result) : FT(fact / result)
end