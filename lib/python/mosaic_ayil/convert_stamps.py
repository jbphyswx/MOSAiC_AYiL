"""Fingerprints for fielddump sources vs written Zarr stores."""

from __future__ import annotations

from pathlib import Path

import xarray as xr
import zarr

from ayil.fielddump import fielddump_n_time, find_fielddump_tiles

STAMP_ATTRS = (
    "ayil_fielddump_tiles",
    "ayil_fielddump_max_mtime",
    "ayil_fielddump_n_time",
    "ayil_fielddump_time_end",
)


def fielddump_source_stamp(run_dir: Path, *, expnr: str = "001") -> dict[str, int | float]:
    """Lightweight fielddump fingerprint (one tile opened for the time axis)."""
    tiles = find_fielddump_tiles(run_dir, expnr=expnr)
    if not tiles:
        raise FileNotFoundError(f"no fielddump tiles in {run_dir}")

    max_mtime = max(p.stat().st_mtime for p in tiles)
    n_time = fielddump_n_time(run_dir, expnr=expnr)
    time_end = 0.0
    if n_time > 0:
        rep = tiles[len(tiles) // 2]
        with xr.open_dataset(rep, engine="netcdf4") as ds:
            time_end = float(ds["time"].values[-1])

    return {
        "fielddump_tiles": len(tiles),
        "fielddump_max_mtime": max_mtime,
        "fielddump_n_time": n_time,
        "fielddump_time_end": time_end,
    }


def stamp_to_attrs(stamp: dict[str, int | float]) -> dict[str, int | float]:
    return {f"ayil_{k}": v for k, v in stamp.items()}


def read_zarr_source_stamp(zarr_path: Path) -> dict[str, int | float] | None:
    """Read conversion stamp from Zarr root attrs; None if missing or unreadable."""
    zarr_path = Path(zarr_path)
    if not zarr_path.exists():
        return None
    try:
        root = zarr.open_group(zarr_path, mode="r")
        attrs = dict(root.attrs)
    except (OSError, ValueError, KeyError):
        return None

    if STAMP_ATTRS[0] not in attrs:
        return None

    return {
        "fielddump_tiles": int(attrs["ayil_fielddump_tiles"]),
        "fielddump_max_mtime": float(attrs["ayil_fielddump_max_mtime"]),
        "fielddump_n_time": int(attrs["ayil_fielddump_n_time"]),
        "fielddump_time_end": float(attrs["ayil_fielddump_time_end"]),
    }


def zarr_n_time_legacy(zarr_path: Path) -> int | None:
    """Time length from store when stamp attrs are absent (older conversions)."""
    try:
        with xr.open_zarr(zarr_path, consolidated=True) as ds:
            if "time" not in ds.dims:
                return None
            return int(ds.sizes["time"])
    except (OSError, ValueError, KeyError):
        return None


def fielddump_newer_than_zarr(
    run_dir: Path,
    zarr_path: Path,
    *,
    expnr: str = "001",
) -> bool:
    """True if fielddump has grown since the Zarr was written (or Zarr is missing)."""
    zarr_path = Path(zarr_path)
    src = fielddump_source_stamp(run_dir, expnr=expnr)
    if int(src["fielddump_n_time"]) == 0:
        return False

    if not zarr_path.exists():
        return True
    old = read_zarr_source_stamp(zarr_path)
    if old is None:
        legacy_n = zarr_n_time_legacy(zarr_path)
        if legacy_n is None:
            return True
        return int(src["fielddump_n_time"]) > legacy_n

    if int(src["fielddump_n_time"]) > int(old["fielddump_n_time"]):
        return True
    if float(src["fielddump_max_mtime"]) > float(old["fielddump_max_mtime"]) + 1e-6:
        return True
    if int(src["fielddump_tiles"]) > int(old["fielddump_tiles"]):
        return True
    return False
