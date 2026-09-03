```@meta
CurrentModule = MOSAiCAYiL
```

# Reading a variable

[`MOSAiCAYiL.read_variable`](@ref) reaches every variable of all five archive files through
one call, under a readable name and in corrected units.

```julia
using MOSAiCAYiL: MOSAiCAYiL as MA

f = MA.read_variable("sv008", "20200503")
f.description   # "q_cloud_ice"
f.units         # "kg/kg"
f.data          # (286, 24), levels × times
f.z, f.time
```

The result is always `(; raw, description, z, time, data, units, long_name)`.

## Which file

`file` selects the product, and defaults to the one carrying that name:

```@example reading
using MOSAiCAYiL: MOSAiCAYiL as MA

MA.variable_product("lwp_bar"), MA.variable_product("t_local"),
MA.variable_product("thltendmicroall"), MA.variable_product("dq_i_dep")
```

| `file` | the file |
|---|---|
| `:scm_in` | `scm_in.a_year_in_les.<date>.nc`, the ERA5 testbed forcing |
| `:profiles` | `profiles.001.nc` |
| `:tmser` | `tmser.001.nc` |
| `:mphys` | `mphysprofiles.001.nc` |
| `:samptend` | `samptend.001.nc` |

Four names mean different things in different files, and they ask you to say which:

```@example reading
try
    MA.variable_product("ql")
catch e
    e.msg
end
```

`u`, `v` and `ql` are DALES slab means on 286 LES levels in `profiles.001.nc`, and ERA5
domain averages on 3037–3042 testbed levels in `scm_in`. `cfrac` is a profile in one file
and a column series in another. Naming the file resolves them:

```julia
MA.read_variable("ql", "20200503"; file = :profiles)   # the LES slab mean
MA.read_variable("ql", "20200503"; file = :scm_in)     # the ERA5 domain average
```

Hand `read_variable` an open dataset to read many variables of a day through one file
handle:

```julia
using NCDatasets
NCDataset(MA.les_profiles_path("20200503"), "r") do ds
    thl = MA.read_variable(ds, "thl"; file = :profiles)
    qt  = MA.read_variable(ds, "qt";  file = :profiles)
end
```

## Numbers per unit mass

DALES stores the SB3 scalars as number per unit *mass*, so reaching a number per unit volume
means multiplying by the day's air density. `MOSAiCAYiL.ρ_power` says what a variable needs —
`1` for a number, `2` for a number variance, `0` for everything else — and the date-taking
method supplies the density itself:

```julia
MA.read_variable("dn_i_inuc", "20200503"; file = :mphys)   # m^-3 s^-1
```

`mphysprofiles.001.nc` and `samptend.001.nc` carry no `rhof` of their own; the density comes
from `profiles.001.nc`, whose `time`, `zt` and `zm` they share exactly.

The open-dataset method takes the density as an argument rather than looking for one, so it
refuses instead of quietly handing back unconverted values:

```julia
NCDataset(MA.mphys_path("20200503"), "r") do ds
    ρ = MA.dales_slab_column("20200503").rhof
    MA.read_variable(ds, "dn_i_inuc"; file = :mphys, density = ρ)
end
```

`translate_units = false` returns the archive's own values and its own units.

## Names

The twelve SB3 scalars and the families built on them resolve to what they hold:

```@example reading
MA.physical_name.(["sv005", "sv008", "svp008", "wsv002r", "sv003"])
```

| archive | becomes |
|---|---|
| `svNNN` | `q_cloud_ice` |
| `svNNN2r` | `q_cloud_ice_variance_resolved` |
| `svpNNN` | `q_cloud_ice_tendency` |
| `svptNNN` | `q_cloud_ice_tendency_turbulence` |
| `wsvNNNr/s/t` | `q_cloud_ice_flux_resolved/sfs/total` |

The microphysics rates and the tendency budgets each follow a scheme, and are resolved by
rule:

```@example reading
MA.physical_name.(["dq_i_dep", "dn_c_au", "dthl_freeze", "thltendmicroall"])
```

An index or a process code outside DALES's own is an error:

```@example reading
try
    MA.physical_name("sv013")
catch e
    e.msg
end
```

`tmser.001.nc` and `scm_in` have irregular names, and are tables:
[`MOSAiCAYiL.TMSER`](@ref) with 52 entries and [`MOSAiCAYiL.SCM_IN`](@ref) with 77.

## Units

The archive mislabels three groups, and `read_variable` corrects each.

**Number scalars are per unit mass.** DALES carries `sv001`…`sv012` as specific quantities
and labels all twelve with the mass family's units, so a number arrives as `(kg/kg)`. Under
the default `translate_units = true` the values are multiplied by air density and reported
per volume:

```@example reading
MA.dales_variable_attributes("sv007", "n_cloud_ice", "kg/kg", "Scalar 007")
```

The third element is the power of density applied. With `translate_units = false` the values
are the archive's own, and the reported units are the archive's own too.

**Two labels are wrong**, and are corrected in one place:

```@example reading
MA.spelled_units("kg/m2"), MA.spelled_units("K/kg/s"), MA.spelled_units("-")
```

`precep_*`/`*_rate` is DALES's `sed_q/ρ`, a mixing ratio times a fall speed. The
potential-temperature tendencies are formed as `(L_v/(c_p Π)) dq/dt`, which is `K/s`.

**One group is written a record late.** The 23 variables `modbulkmicrostat3` contributes to
`profiles.001.nc` are written at a counter only `genstat` increments, from a module that runs
earlier in the same iteration, so the k-th sample lands in record k−1: the first goes to
record 0 and the last record holds fill. `read_variable` returns them on the times they
average, one sample shorter than the rest of the file.
[`MOSAiCAYiL.BULKMICROSTAT3`](@ref) lists them, including the two that are constant zero
because the `slabsum` that fills them is commented out.

## Derived quantities

```julia
MA.dales_radiative_heating("20200503"; band = :longwave)  # K/s, with exner put back
MA.dales_fall_speed(:ice, "20200503")                     # m/s, rate ÷ mixing ratio
MA.surface_heat_fluxes("20200503")                        # W/m^2, upward positive
MA.column_water_path(q, ρ, faces)                         # kg/m^2
```

A water path is derived on both sides of any comparison: the reference's own bars were
integrated by DALES over its 286 levels with its `ρ` and `Δz`. Build both sides with
`column_water_path`, from profiles on one grid.
