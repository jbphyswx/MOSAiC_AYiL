```@meta
CurrentModule = MOSAiCAYiL
```

# What the reference runs did

The JAMES paper, the AYiL DALES source and the Zenodo namelists disagree in places. **The
Fortran that wrote the archive is what this package implements**, and where a disagreement
matters both numbers are kept so neither is lost.

Source paths below are `MOSAiC_AYiL/dales_ayil/src/`.

## Three run lengths

| | seconds | |
|---|---|---|
| [`MOSAiCAYiL.PUBLISHED_RUNTIME_S`](@ref) | 7200 | the Zenodo `profiles.001.nc` and its `namoptions` |
| [`MOSAiCAYiL.PAPER_RUNTIME_S`](@ref) | 10800 | the paper protocol, §2.3.1 |
| [`MOSAiCAYiL.EVALUATION_S`](@ref) | 5400 | the paper's Appendix C evaluation time |

`t_end(case)` is the published 7200 s, which is the clock any comparison against the archive
runs on.

## Two ice initialization diameters

Paper §2.3.2 initializes pre-existing ice at **55 μm**. The AYiL DALES `d_ci` the runs used is **60 μm**. Both are stored, as [`MOSAiCAYiL.PAPER_ICE_INIT_DIAMETER_M`](@ref) and
[`MOSAiCAYiL.DALES_D_CI_M`](@ref).

## Two inversion definitions

Paper eq. (7) writes max `∂Θ_v/∂z`. `modtestbed.f90` `testbednudge` (`:1521-1543`) takes the
centred `∂θ_l/∂z` on 100–5000 m, with liquid-only `θ_l`.
[`MOSAiCAYiL.inversion_height`](@ref) implements the subroutine that ran.

## Namelist values DALES overwrote

On all 190 days the namelist writes `xlat = 78.41`, `xlon = 8.47`, `z0mav`, `z0hav`,
`albedoav`, `seaicefrct`, `ps = 100805.48` and `thls = 278.61`. DALES replaces all eight every
substep from `scm_in` (`modtimedep.f90:206-208`, `:522-538`), so they describe nothing the runs
did. The per-day values are in the day-scalar table — see [Facts with no I/O](facts.md).

`ps` and `thls` are the two that read most plausibly and are most wrong: on 2020-05-03 the
namelist's `ps` is 100805.48 Pa against the day's 101772.62, and `thls` is a **potential**
temperature — `modtestbed.f90:574-578` divides the `scm_in` skin temperature by `Π(p_s)` — so
278.61 stands against `surface_pottemp` of 257.48. [`MOSAiCAYiL.namelist_value`](@ref) refuses
all eight and names the accessor that supersedes each.

`xday` is the only namelist key that varies between days, and it equals `Dates.dayofyear` on
190/190, so [`MOSAiCAYiL.xday`](@ref) needs no file.

The nudging entries are the opposite case: `tb_taunudge = 10800`, `tb_zmidnudge = 300` and
`tb_zminnudge = -1` are what ran, on 190/190 days. `tb_minzinv`/`tb_maxzinv` are Fortran
defaults (100 m, 5000 m) and appear in no namelist.

## The clear-sky radiation was never written

`tmser.001.nc` declares `SW_up_ca_TOA`, `SW_dn_ca_TOA`, `LW_up_ca_TOA` and `LW_dn_ca_TOA`,
and all four hold zero on every day. No cloud radiative effect can be formed from this
archive: differencing the all-sky flux against them returns the all-sky flux.

`LW_dn_TOA` is zero for a physical reason rather than a missing diagnostic, and both
shortwave fields are zero through the polar night. `SW_dn_TOA` is stored negative.
[`MOSAiCAYiL.toa_radiation`](@ref) returns the three that carry data.

## One day ships a fielddump

`20191101` carries `fielddump.000.000.001.nc`, one MPI rank's slab — `xt = 320` by `yt = 4` by
`zt = 200`, four records from 1800 s to 7200 s, holding all twelve SB3 scalars alongside
`thl`, `qt`, `ql`, the winds and `buoy`. No other day has one.

Four rows of 320 is 1.25 % of the domain, so a mean over it samples the slab mean
`profiles.001.nc` reports rather than reproducing it.


## Where the archive contradicts its own labels

| label | what it holds |
|---|---|
| `sv001`…`sv012` as `(kg/kg)` | numbers per unit **mass**; `modmicrodata3.f90:106-117` declares them `[kg^{-1}]` |
| `precep_*`/`*_rate` as `kg/m2` | `sed_q/ρ`, a mixing ratio times a fall speed |
| `dth*` tendencies as `K/kg/s` | `K/s`; they are `(L_v/(c_p Π)) dq/dt` |
| `presh` on the `zt` axis | the **half**-level pressure |
| fielddump `qt`/`ql` as `1e-5kg/kg` | plain `kg/kg`; the `1.0E5` applies to the legacy binary path |
| `scm_in` `q_skin` | its units and long name sit in each other's attribute |
| `scm_in` `sv` | labelled `whatever` |

[Reading a variable](reading.md) corrects each of these.

## Declared and never read

Four things exist in the source or the input and act on nothing:

- `modglobal.f90:78` declares `riv = 2.84e6` for sublimation and never references it. The
  microphysics used SB3's `rlvi = 2.834e6`, which is what
  [`MOSAiCAYiL.DALES_CONSTANTS`](@ref) carries.
- `scm_in`'s `in_a_inuc` and `in_b_inuc` reach `a_inuc`/`b_inuc`
  (`modbulkmicro3.f90:147-148`), while the Meyers rate is formed from the module's own
  `a_M92`/`b_M92` (`:3648`). [`MOSAiCAYiL.INP_MEYERS_AB_UNUSED`](@ref) records them.
- `qtpaccr` carries an "accretion total water content tendency" long name with its `slabsum`
  commented out (`modbulkmicrostat3.f90:1445-1448`), so it is zero on every day. `qtpsed` is
  a deliberate zero.
- `dvrmn` sums `modmicrodata`'s `Dvr`, which SB3 never fills — its `imicro` guard is
  commented out.

## Moisture

DALES's `qt` is `q + ql`, with ice a separate scalar, and its saturation adjustment is
liquid-only. ClimaAtmos `q_tot` is `q + ql + qi`, which is what `testbed_forcing` returns as
`hus`.

Thermodynamic horizontal advection — `tadv`, and `qadv + ladv + iadv` — is identically zero
on 190/190 days. Momentum advection is not.

## The two clocks in the output

`profiles.001.nc` is 24 records of 300 s averages; `tmser.001.nc` is 120 records of 60 s. A
`tmser` bar averages over five samples before it compares with a profile integral.
