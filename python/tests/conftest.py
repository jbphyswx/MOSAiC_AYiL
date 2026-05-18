"""Pytest fixtures: synthetic DALES-like fielddump tiles."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest
import xarray as xr


def _write_tile(
    path: Path,
    *,
    ix: int,
    iy: int,
    nx: int,
    ny: int,
    nz: int = 4,
    nt: int = 2,
    x0: float = 0.0,
    y0: float = 0.0,
) -> None:
    """Write one MPI tile mimicking DALES fielddump layout."""
    xt = x0 + (np.arange(nx) + 0.5) * 100.0
    yt = y0 + (np.arange(ny) + 0.5) * 100.0
    xm = x0 + np.arange(nx) * 100.0
    ym = y0 + np.arange(ny) * 100.0
    zt = (np.arange(nz) + 0.5) * 50.0
    zm = np.arange(nz) * 50.0
    time = np.arange(nt, dtype=np.float32) * 1800.0

    ds = xr.Dataset(
        data_vars={
            "qt": (("time", "zt", "yt", "xt"), np.random.randn(nt, nz, ny, nx).astype("f4")),
            "ql": (("time", "zt", "yt", "xt"), np.random.randn(nt, nz, ny, nx).astype("f4")),
            "thl": (("time", "zt", "yt", "xt"), np.random.randn(nt, nz, ny, nx).astype("f4")),
            "u": (("time", "zt", "yt", "xm"), np.random.randn(nt, nz, ny, nx).astype("f4")),
        },
        coords={
            "time": time,
            "xt": xt.astype("f4"),
            "yt": yt.astype("f4"),
            "xm": xm.astype("f4"),
            "ym": ym.astype("f4"),
            "zt": zt.astype("f4"),
            "zm": zm.astype("f4"),
        },
    )
    ds.to_netcdf(path, engine="netcdf4")


@pytest.fixture
def synthetic_run_dir(tmp_path: Path) -> Path:
    """2x2 tiles, 3x3 cells each -> 6x6 global when merged."""
    run = tmp_path / "runs" / "20990101"
    run.mkdir(parents=True)
    nx = ny = 3
    for ix, iy in ((0, 0), (1, 0), (0, 1), (1, 1)):
        _write_tile(
            run / f"fielddump.{ix:03d}.{iy:03d}.001.nc",
            ix=ix,
            iy=iy,
            nx=nx,
            ny=ny,
            x0=ix * nx * 100.0,
            y0=iy * ny * 100.0,
        )
    return run
