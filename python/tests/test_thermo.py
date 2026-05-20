"""Tests for offline thermodynamic derivatives."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest
import xarray as xr

from ayil.fielddump import merge_fielddump
from ayil.thermo import (
    add_thermo_derivatives_for_run,
    exner_from_presf,
    presf_fromztop,
    read_prof_inp_zf,
    temperature_from_thl_ql,
)


def test_read_prof_inp(synthetic_run_dir: Path) -> None:
    zf = read_prof_inp_zf(synthetic_run_dir / "prof.inp.001", n_levels=4)
    assert zf.shape == (4,)
    assert zf[0] == pytest.approx(25.0)


def test_presf_decreases_with_height(synthetic_run_dir: Path) -> None:
    zf = read_prof_inp_zf(synthetic_run_dir / "prof.inp.001", n_levels=4)
    n = 4
    thl = np.full(n, 280.0)
    qt = np.full(n, 0.005)
    ql = np.zeros(n)
    presf = presf_fromztop(100805.48, thl, qt, ql, zf)
    assert presf[0] > presf[-1]
    assert np.all(np.diff(presf) < 0)


def test_add_thermo_derivatives(synthetic_run_dir: Path) -> None:
    ds = merge_fielddump(synthetic_run_dir, include_staggered=False)
    # constant fields for predictable temperature
    ds["thl"] = xr.full_like(ds["thl"], 280.0)
    ds["ql"] = xr.zeros_like(ds["ql"])
    out = add_thermo_derivatives_for_run(ds, synthetic_run_dir, expnr="001")
    assert "pressure" in out and "temperature" in out and "exner" in out
    assert out["pressure"].dims == ("z",)
    assert out["temperature"].dims == ("time", "z", "y", "x")
    expected = (280.0 * out["exner"]).broadcast_like(out["temperature"])
    xr.testing.assert_allclose(out["temperature"], expected, rtol=1e-5)


def test_temperature_matches_formula() -> None:
    z = np.array([25.0, 75.0, 125.0, 175.0])
    thl = xr.DataArray(
        np.ones((2, 4, 3, 3), dtype=np.float32) * 280.0,
        dims=("time", "z", "y", "x"),
        coords={"z": z, "time": [0, 1], "y": [0, 1, 2], "x": [0, 1, 2]},
    )
    ql = xr.zeros_like(thl)
    presf = np.array([1.0e5, 9.5e4, 9.0e4, 8.5e4])
    exner = exner_from_presf(presf)
    temp = temperature_from_thl_ql(thl, ql, exner)
    np.testing.assert_allclose(temp.isel(time=0, y=0, x=0).values, 280.0 * exner)
