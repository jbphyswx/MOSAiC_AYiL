"""Discover and merge DALES fielddump.*.*.expnr.nc MPI tiles."""

from __future__ import annotations

import re
from pathlib import Path

import xarray as xr

FIELDDUMP_PATTERN = re.compile(
    r"^fielddump\.(?P<ix>\d{3})\.(?P<iy>\d{3})\.(?P<exp>\d{3})\.nc$"
)

# Variables on cell-centered (zt, yt, xt) vs staggered dims in DALES output.
STAGGERED_DIMS = {
    "u": ("time", "zt", "yt", "xm"),
    "v": ("time", "zt", "ym", "xt"),
    "w": ("time", "zm", "yt", "xt"),
}

CENTER_VARS = ("qt", "ql", "thl", "buoy")
CENTER_DIMS = ("time", "zt", "yt", "xt")


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


def _rename_center_vars(ds: xr.Dataset) -> xr.Dataset:
    """Use analysis-friendly dimension names for cell-centered fields."""
    rename = {}
    if "zt" in ds.dims:
        rename["zt"] = "z"
    if "yt" in ds.dims:
        rename["yt"] = "y"
    if "xt" in ds.dims:
        rename["xt"] = "x"
    out = ds.rename(rename)
    coord_rename = {}
    if "zt" in out.coords:
        coord_rename["zt"] = "z"
    if "yt" in out.coords:
        coord_rename["yt"] = "y"
    if "xt" in out.coords:
        coord_rename["xt"] = "x"
    return out.rename(coord_rename)


def _combine_tiles(tiles: list[xr.Dataset]) -> xr.Dataset:
    """Merge MPI tiles by concatenating along x then y (non-overlapping coords)."""
    if not tiles:
        raise ValueError("no tiles to combine")
    if len(tiles) == 1:
        return tiles[0]

    by_iy: dict[int, list[xr.Dataset]] = {}
    for ds in tiles:
        iy = int(ds.attrs.get("tile_iy", 0))
        by_iy.setdefault(iy, []).append(ds)

    rows: list[xr.Dataset] = []
    for iy in sorted(by_iy):
        row_tiles = sorted(by_iy[iy], key=lambda d: int(d.attrs.get("tile_ix", 0)))
        rows.append(
            xr.concat(
                row_tiles,
                dim="x",
                data_vars="all",
                coords="all",
                combine_attrs="drop",
            )
        )
    return xr.concat(rows, dim="y", data_vars="all", coords="all", combine_attrs="drop")


def merge_fielddump(
    run_dir: Path,
    *,
    expnr: str = "001",
    include_staggered: bool = True,
) -> xr.Dataset:
    """
  Open all fielddump tiles under ``run_dir`` and merge into one Dataset.

  Cell-centered scalars (qt, ql, thl, buoy, sv*) are renamed to (time, z, y, x).
  Staggered wind components keep native DALES dimension names (xm, ym, zm, …).
  """
    paths = find_fielddump_tiles(run_dir, expnr=expnr)
    if not paths:
        raise FileNotFoundError(f"no fielddump tiles in {run_dir}")

    center_parts: list[xr.Dataset] = []
    staggered: dict[str, xr.DataArray] = {}

    for path in paths:
        ix, iy = parse_tile_index(path)
        try:
            ds = xr.open_dataset(path, engine="netcdf4")
        except OSError as exc:
            raise OSError(
                f"cannot read {path} (file may still be writing): {exc}"
            ) from exc

        with ds:
            # Cell-centered fields
            center_vars = [v for v in CENTER_VARS if v in ds]
            center_vars += sorted(
                v for v in ds.data_vars if v.startswith("sv") and v in ds
            )
            if center_vars:
                part = ds[center_vars]
                part = _rename_center_vars(part)
                part.attrs["tile_ix"] = ix
                part.attrs["tile_iy"] = iy
                center_parts.append(part)

            if include_staggered:
                for name, dims in STAGGERED_DIMS.items():
                    if name not in ds:
                        continue
                    da = ds[name].load()
                    da.attrs["tile_ix"] = ix
                    da.attrs["tile_iy"] = iy
                    staggered[f"{name}_tile_{ix:03d}_{iy:03d}"] = da

    if not center_parts:
        raise ValueError(f"no cell-centered variables found in {run_dir}")

    merged = _combine_tiles(center_parts)

    for name, da in staggered.items():
        merged[name] = da

    merged.attrs.update(
        {
            "source": "DALES fielddump",
            "run_dir": str(run_dir),
            "expnr": expnr,
            "n_tiles": len(paths),
        }
    )
    return merged
