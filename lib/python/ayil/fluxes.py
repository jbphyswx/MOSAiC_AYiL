"""
Vertical kinematic fluxes from DALES fielddump (w-level / ``zw`` stagger).

DALES defines total fluxes at vertical velocity points (half levels), e.g.
``wqtt = wqts + wqtr`` (subgrid diffusion plus resolved ``w * qt`` at half level).
See ``modfielddump.f90`` and ``modgenstat.f90`` (``do_genstat``).

``wtemp`` is the total temperature flux consistent with
``T = exner * thl + (L_v/c_p) * ql`` (same ``t0h`` chain as ``wqlt`` in DALES).

``wqit`` is the total flux of ice mixing ratio (SB3 scalar index ``iq_ci`` / ``sv008``),
using the same resolved + subgrid formula as other scalars in ``modgenstat``.

Cell-center values are **not** ``w_center * qt_center``; they are a vertical
average of fluxes on adjacent ``zw`` interfaces.
"""

from __future__ import annotations

import logging
from pathlib import Path

import numpy as np
import xarray as xr

from ayil.thermo import DalesThermoConstants, add_thermo_derivatives_for_run

# Native DALES names on zw (same stagger as ``w``).
FIELDDUMP_FLUX_VARS_ZW = (
    "wqtt",
    "wthlt",
    "wqlt",
    "wtemp",
    "wqit",
    "wthvt",
)

# Long names for Zarr attributes.
FLUX_LONG_NAMES = {
    "wqtt": "total water flux (w level)",
    "wthlt": "total liquid-water potential temperature flux (w level)",
    "wqlt": "total liquid water flux (w level)",
    "wtemp": "total temperature flux (w level)",
    "wqit": "total ice mixing ratio flux (w level)",
    "wthvt": "total virtual potential temperature (buoyancy) flux (w level)",
}

FLUX_UNITS = {
    "wqtt": "kg kg-1 m s-1",
    "wthlt": "K m s-1",
    "wqlt": "kg kg-1 m s-1",
    "wtemp": "K m s-1",
    "wqit": "kg kg-1 m s-1",
    "wthvt": "K m s-1",
}

WTEMP_FORMULA = "wtemp = exner(zw) * wthlt + (L_v/c_p) * wqlt"


def interface_flux_to_cell_center(da: xr.DataArray) -> xr.DataArray:
    """
    Average flux on ``zw`` onto cell-center ``z``.

    Interior: ``0.5 * (F_k + F_{k+1})`` along ``zw``. Top: replicate top interface.
    """
    if "zw" not in da.dims:
        raise ValueError(f"expected zw dimension, got dims={da.dims}")
    if "zw" not in da.coords:
        raise ValueError("coordinate zw required")

    nz = da.sizes["zw"]
    z_ax = da.dims.index("zw")
    arr = np.asarray(da.values, dtype=np.float32)
    out = np.empty_like(arr)
    sl = [slice(None)] * arr.ndim

    if nz >= 2:
        for k in range(nz - 1):
            sl_lo = sl.copy()
            sl_hi = sl.copy()
            sl_lo[z_ax] = k
            sl_hi[z_ax] = k + 1
            out[tuple(sl_lo)] = 0.5 * (arr[tuple(sl_lo)] + arr[tuple(sl_hi)])
        sl_top = sl.copy()
        sl_top[z_ax] = nz - 1
        out[tuple(sl_top)] = arr[tuple(sl_top)]
    else:
        out[...] = arr

    dims = tuple("z" if d == "zw" else d for d in da.dims)
    coords = {k: v for k, v in da.coords.items() if k != "zw"}
    coords["z"] = ("z", np.asarray(da.coords["zw"].values))
    return xr.DataArray(
        out,
        dims=dims,
        coords=coords,
        attrs={
            **da.attrs,
            "vertical_stagger": "cell center (mean of flux at zw[k] and zw[k+1]; top=zw top)",
            "source_stagger": "zw",
        },
    )


def vertical_center_to_interface(
    da: xr.DataArray,
    *,
    z_dim: str = "z",
    out_dim: str = "zw",
    out_coord: xr.DataArray | None = None,
) -> xr.DataArray:
    """
    Map a cell-centered vertical field to w-levels (same geometry as flux averaging).

    Used for ``exner(z)`` → ``exner(zw)`` when deriving ``wtemp`` offline.
    """
    if z_dim not in da.dims:
        raise ValueError(f"expected {z_dim} dimension, got dims={da.dims}")

    nz = da.sizes[z_dim]
    z_ax = da.dims.index(z_dim)
    arr = np.asarray(da.values, dtype=np.float32)
    out = np.empty_like(arr)
    sl = [slice(None)] * arr.ndim

    if nz >= 2:
        for k in range(nz - 1):
            sl_lo = sl.copy()
            sl_hi = sl.copy()
            sl_lo[z_ax] = k
            sl_hi[z_ax] = k + 1
            out[tuple(sl_lo)] = 0.5 * (arr[tuple(sl_lo)] + arr[tuple(sl_hi)])
        sl_top = sl.copy()
        sl_top[z_ax] = nz - 1
        out[tuple(sl_top)] = arr[tuple(sl_top)]
    else:
        out[...] = arr

    dims = tuple(out_dim if d == z_dim else d for d in da.dims)
    coords = {k: v for k, v in da.coords.items() if k != z_dim}
    if out_coord is not None:
        coords[out_dim] = out_coord
    elif out_dim in da.coords:
        coords[out_dim] = da.coords[out_dim]
    return xr.DataArray(out, dims=dims, coords=coords, attrs=dict(da.attrs))


def temperature_flux_from_thl_ql(
    wthlt: xr.DataArray,
    wqlt: xr.DataArray,
    exner_zw: xr.DataArray,
    *,
    constants: DalesThermoConstants | None = None,
) -> xr.DataArray:
    """``wtemp = exner * wthlt + (L_v/c_p) * wqlt`` on ``zw``."""
    c = constants or DalesThermoConstants()
    exner_b = exner_zw.broadcast_like(wthlt)
    return (exner_b * wthlt + c.rlv_over_cp * wqlt).astype(np.float32)


def _exner_on_zw_from_dataset(
    ds: xr.Dataset,
    *,
    run_dir: Path | None,
    expnr: str,
    repo_root: Path | None,
    log: logging.Logger,
) -> xr.DataArray:
    if "exner" in ds:
        exner_z = ds["exner"]
    else:
        if run_dir is None:
            raise ValueError("exner missing and no run_dir to compute hydrostatic exner")
        thermo = add_thermo_derivatives_for_run(
            ds,
            run_dir,
            expnr=expnr,
            repo_root=repo_root,
            log=log,
        )
        exner_z = thermo["exner"]

    zw_coord = None
    if "wthlt" in ds and "zw" in ds["wthlt"].coords:
        zw_coord = ds["wthlt"].coords["zw"]
    elif "w" in ds and "zw" in ds["w"].coords:
        zw_coord = ds["w"].coords["zw"]

    if exner_z.dims == ("z",):
        return vertical_center_to_interface(exner_z, out_coord=zw_coord)
    return vertical_center_to_interface(exner_z, out_coord=zw_coord)


def add_missing_fluxes(
    ds: xr.Dataset,
    *,
    run_dir: Path | None = None,
    expnr: str = "001",
    repo_root: Path | None = None,
    log: logging.Logger | None = None,
) -> xr.Dataset:
    """
    Add ``wtemp`` (and document ``wqit``) when older fielddump tiles omit them.

    ``wtemp`` is derived from ``wthlt``, ``wqlt``, and hydrostatic ``exner`` when absent.
    ``wqit`` requires a DALES rebuild (needs subgrid ``ekh``); cannot be recovered offline.
    """
    log = log or logging.getLogger("ayil")
    out = ds.copy()

    if "wtemp" not in out and "wthlt" in out and "wqlt" in out:
        log.info("Derive wtemp from wthlt, wqlt, and exner (%s)", WTEMP_FORMULA)
        exner_zw = _exner_on_zw_from_dataset(
            out,
            run_dir=run_dir,
            expnr=expnr,
            repo_root=repo_root,
            log=log,
        )
        wtemp = temperature_flux_from_thl_ql(out["wthlt"], out["wqlt"], exner_zw)
        out["wtemp"] = wtemp.assign_attrs(
            {
                "long_name": FLUX_LONG_NAMES["wtemp"],
                "units": FLUX_UNITS["wtemp"],
                "formula": WTEMP_FORMULA,
                "derived_offline": True,
            }
        )

    if "wqit" not in out:
        log.warning(
            "wqit (ice mass flux) not in fielddump; rebuild dales4 with updated "
            "modfielddump.f90 and re-run to include it"
        )

    return out


def add_cell_center_fluxes(
    ds: xr.Dataset,
    *,
    flux_vars: tuple[str, ...] = FIELDDUMP_FLUX_VARS_ZW,
    suffix: str = "",
) -> xr.Dataset:
    """
    Add cell-centered flux variables derived from zw-staggered fielddump fluxes.

    New names: ``{name}{suffix}`` on dimension ``z`` (default suffix ``_c`` → ``wqtt_c``).
    """
    out = ds.copy()
    if suffix == "":
        suffix = "_c"
    for name in flux_vars:
        if name not in ds:
            continue
        centered = interface_flux_to_cell_center(ds[name])
        out_name = f"{name}{suffix}"
        out[out_name] = centered.assign_attrs(
            {
                "long_name": FLUX_LONG_NAMES.get(name, name) + " (cell center)",
                "units": FLUX_UNITS.get(name, ""),
                "standard_name": ds[name].attrs.get("standard_name", ""),
            }
        )
    return out
