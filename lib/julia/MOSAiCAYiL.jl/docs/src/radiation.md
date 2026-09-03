```@meta
CurrentModule = MOSAiCAYiL
```

# Radiation

`iradiation = 1` selects `modradfull`, a four-stream double-Gauss correlated-k solver, called
**every timestep** (`timerad = 0`). Its two input files are both consumed, and both are
byte-identical on all 190 days.

## Band structure and trace gases

```@example radiation
using MOSAiCAYiL: MOSAiCAYiL as MA
(; count = length(MA.RADIATION_BANDS.power),
   solar = count(>(0), MA.RADIATION_BANDS.power),
   total_power = MA.SOLAR_TOTAL_POWER)
```

Six of the eighteen bands carry solar power. `modradfull` scales its shortwave fluxes by
`sw0/totalpower` with `sw0 = 1368.22` — and `modradfull.f90:56`'s `SolarConstant = 1.365e3`
is declared and never read.

```@example radiation
MA.TRACE_GAS_CONCENTRATIONS
```

CO₂ arrives through the two `OVRLP` blocks of bands 14 and 15. Water vapour and ozone carry
zero here and come from the column instead.

## Cloud-liquid optics

[`MOSAiCAYiL.CLOUD_LIQUID_OPTICS`](@ref) is `cldwtr.inp.001`, committed: eight effective radii
by eighteen bands of extinction, single-scattering albedo and asymmetry.

```@example radiation
MA.cloud_liquid_optics(5, 1.0e-4, 9.0)
```

The interpolation is `modradfull`'s own, and the two conventions are not the same: the **mass
extinction** is linear in `1/r_eff`, while the albedo and the asymmetry are linear in
`r_eff`. Outside the table the end rows are held rather than extrapolated, and everything is
zero below `1e-8 kg/m³`.

`extinction` is per metre, so a layer's optical depth is `extinction * dz`.

## The correlated-k tables

The k-distributions are 6820 numbers across 23 gas blocks, and nothing in this package
computes radiation, so they are behind a reader rather than committed:

```julia
ckd = MA.read_ckd("20200503")
ckd.gases[1].xk        # (nt, np, ng, noverlap)
```

`sum(hk) ≈ 1` for every gas, which is the condition DALES stops the run on
(`modradfull.f90:2716`) and therefore a real check on the parse.

## Ice optics and droplet number

`l_radfullice = true` selects in-source Fu-type ice optics, so there is no ice input file. The
effective-radius branch uses `Nc_0 = 70e6` from `modmicrodata.f90:46` — **a different symbol**
from `&nambulk3`'s `nc0 = 1e7`, which is what the microphysics used.

## What the archive does not carry

The clear-sky top-of-atmosphere fluxes are declared and identically zero, so no cloud
radiative effect can be formed — see [What the reference runs did](archive.md).
[`MOSAiCAYiL.toa_radiation`](@ref) returns the three fields that hold data.
