"""Discover and merge DALES fielddump.*.*.expnr.nc MPI tiles."""

from __future__ import annotations

import logging
import re
from pathlib import Path

import xarray as xr

from ayil.logging_utils import human_bytes
from ayil.scalar_names import AYIL_SB3_SCALAR_LONG_NAMES, rename_scalar_variables

FIELDDUMP_PATTERN = re.compile(
    r"^fielddump\.(?P<ix>\d{3})\.(?P<iy>\d{3})\.(?P<exp>\d{3})\.nc$"
)

CENTER_VARS = ("qt", "ql", "thl", "buoy")
WIND_SPECS = {
    "u": ("yt", "xm", {"zt": "z", "yt": "y", "xm": "xu"}),
    "v": ("ym", "xt", {"zt": "z", "ym": "yv", "xt": "x"}),
    "w": ("yt", "xt", {"zm": "zw", "yt": "y", "xt": "x"}),
}


def find_fielddump_tiles(run_dir: Path, expnr: str = "001") -> list[Path]:
    """Return sorted fielddump tile paths for one experiment number."""
    run_dir = Path(run_dir)
    tiles = sorted(
        p
        for p in run_dir.glob(f"fielddump.*.*.{expnr}.nc")
        if FIELDDUMP_PATTERN.match(p.name)
    )
    return tiles


def parse_tile_index(path: Path) -> tuple[int, int]:
    m = FIELDDUMP_PATTERN.match(path.name)
    if m is None:
        raise ValueError(f"not a fielddump tile: {path}")
    return int(m.group("ix")), int(m.group("iy"))


def _rename_dims(da: xr.DataArray | xr.Dataset, rename: dict[str, str]) -> xr.DataArray | xr.Dataset:
    out = da.rename({k: v for k, v in rename.items() if k in da.dims})
    coord_rename = {k: v for k, v in rename.items() if k in out.coords}
    if coord_rename:
        out = out.rename(coord_rename)
    return out


def _combine_mpi_tiles(
    parts: list[xr.Dataset] | list[xr.DataArray],
    *,
    y_dim: str,
    x_dim: str,
) -> xr.Dataset | xr.DataArray:
    """
    Stitch MPI tiles: concat along ``x_dim`` within a row, then along ``y_dim``.

    AYIL production runs use y-only decomposition (``ix`` fixed, ``iy`` 0–39).
    General enough for test fixtures with 2×2 tiling.
    """
    if not parts:
        raise ValueError("no tiles to combine")

    by_iy: dict[int, list] = {}
    for part in parts:
        iy = int(part.attrs.get("tile_iy", 0))
        by_iy.setdefault(iy, []).append(part)

    rows = []
    for iy in sorted(by_iy):
        row_tiles = sorted(by_iy[iy], key=lambda d: int(d.attrs.get("tile_ix", 0)))
        rows.append(
            xr.concat(
                row_tiles,
                dim=x_dim,
                coords="all",
                combine_attrs="drop",
            )
        )
    merged = (
        rows[0]
        if len(rows) == 1
        else xr.concat(rows, dim=y_dim, coords="all", combine_attrs="drop")
    )
    return merged


def _merge_center_fields(parts: list[xr.Dataset]) -> xr.Dataset:
    merged = _combine_mpi_tiles(parts, y_dim="yt", x_dim="xt")
    merged = _rename_dims(merged, {"zt": "z", "yt": "y", "xt": "x"})
    return merged


def _merge_wind(
    parts: list[xr.DataArray],
    *,
    y_dim: str,
    x_dim: str,
    dim_rename: dict[str, str],
) -> xr.DataArray:
    merged = _combine_mpi_tiles(parts, y_dim=y_dim, x_dim=x_dim)
    return _rename_dims(merged, dim_rename)


def _rename_scalars_in_dataset(ds: xr.Dataset) -> xr.Dataset:
    """Rename ``sv001``… to SB3 microphysics names; keep unknown ``sv*`` as-is."""
    renames: dict[str, str] = {}
    for name in list(ds.data_vars):
        if name.startswith("sv"):
            new_name = rename_scalar_variables(name)
            if new_name != name:
                renames[name] = new_name
    if not renames:
        return ds
    out = ds.rename(renames)
    for old_name, new_name in renames.items():
        if new_name in AYIL_SB3_SCALAR_LONG_NAMES:
            out[new_name].attrs.setdefault(
                "long_name", AYIL_SB3_SCALAR_LONG_NAMES[new_name]
            )
        out[new_name].attrs.setdefault("units", "kg kg-1")
        out[new_name].attrs["dales_fielddump_name"] = old_name
    return out


def merge_fielddump(
    run_dir: Path,
    *,
    expnr: str = "001",
    include_staggered: bool = True,
    log: logging.Logger | None = None,
) -> xr.Dataset:
    """
    Merge all fielddump tiles into one xarray Dataset on the global grid.

    Cell-centered fields use ``(time, z, y, x)``. Winds use Arakawa-C stagger
    coordinates ``xu``, ``yv``, and ``zw`` respectively. Scalars ``sv001``… are
    renamed to SB3 bulk-microphysics names (see ``scalar_names.py``).
    """
    log = log or logging.getLogger("ayil")
    paths = find_fielddump_tiles(run_dir, expnr=expnr)
    if not paths:
        raise FileNotFoundError(f"no fielddump tiles in {run_dir}")

    total_bytes = sum(p.stat().st_size for p in paths)
    log.info(
        "Found %d fielddump tiles (%s total)",
        len(paths),
        human_bytes(total_bytes),
    )

    center_parts: list[xr.Dataset] = []
    wind_parts: dict[str, list[xr.DataArray]] = {k: [] for k in WIND_SPECS}

    for n, path in enumerate(paths, start=1):
        ix, iy = parse_tile_index(path)
        if log.isEnabledFor(logging.INFO):
            log.info(
                "Tile %d/%d  %s  %s",
                n,
                len(paths),
                path.name,
                human_bytes(path.stat().st_size),
            )
        try:
            ds = xr.open_dataset(path, engine="netcdf4")
        except OSError as exc:
            raise OSError(
                f"cannot read {path} (file may still be writing): {exc}"
            ) from exc

        with ds:
            center_vars = [v for v in CENTER_VARS if v in ds]
            center_vars += sorted(
                v for v in ds.data_vars if v.startswith("sv") and v in ds
            )
            if center_vars:
                part = ds[center_vars].load()
                part.attrs["tile_ix"] = ix
                part.attrs["tile_iy"] = iy
                center_parts.append(part)

            if include_staggered:
                for name, (y_dim, x_dim, dim_rename) in WIND_SPECS.items():
                    if name not in ds:
                        continue
                    da = ds[name].load()
                    da.attrs["tile_ix"] = ix
                    da.attrs["tile_iy"] = iy
                    wind_parts[name].append(da)

    if not center_parts:
        raise ValueError(f"no cell-centered variables found in {run_dir}")

    log.info("Stitching center fields along y (%d tiles)", len(center_parts))
    merged = _merge_center_fields(center_parts)
    merged = _rename_scalars_in_dataset(merged)

    if include_staggered:
        for name, (y_dim, x_dim, dim_rename) in WIND_SPECS.items():
            parts = wind_parts[name]
            if not parts:
                log.warning("Wind component %s missing from all tiles", name)
                continue
            log.info(
                "Stitching %s along %s then %s (%d tiles)",
                name,
                x_dim,
                y_dim,
                len(parts),
            )
            merged[name] = _merge_wind(
                parts, y_dim=y_dim, x_dim=x_dim, dim_rename=dim_rename
            )

    merged.attrs.update(
        {
            "source": "DALES fielddump",
            "run_dir": str(run_dir),
            "expnr": expnr,
            "n_tiles": len(paths),
            "decomposition": "y-only (40 ranks × 8 cells)",
        }
    )
    return merged
