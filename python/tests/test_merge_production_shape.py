"""Regression: production-scale merge has global winds, not per-tile variables."""

from __future__ import annotations

from pathlib import Path

import pytest

from ayil.fielddump import merge_fielddump

PROD_RUN = Path(__file__).resolve().parents[2] / "runs" / "20200720"


@pytest.mark.skipif(
    not PROD_RUN.is_dir() or not list(PROD_RUN.glob("fielddump.*.*.001.nc")),
    reason="production run not available",
)
def test_production_merge_global_grid() -> None:
    ds = merge_fielddump(PROD_RUN, include_staggered=True)
    assert ds.sizes["x"] == 320
    assert ds.sizes["y"] == 320
    assert ds.sizes["z"] == 200
    assert ds.sizes["time"] == 4
    assert "u" in ds and "v" in ds and "w" in ds
    assert not any(v.startswith("u_tile_") for v in ds.data_vars)
    assert "n_rain" in ds
    u = ds["u"]
    assert "xu" in u.dims and u.sizes["y"] == 320
