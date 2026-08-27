"""Tests for vertical flux center averaging and derived wtemp."""

from __future__ import annotations

import numpy as np
import xarray as xr

from ayil.fluxes import (
    add_cell_center_fluxes,
    add_missing_fluxes,
    interface_flux_to_cell_center,
    temperature_flux_from_thl_ql,
)


def test_interface_flux_to_cell_center() -> None:
    zw = np.array([10.0, 30.0, 50.0, 70.0], dtype=np.float32)
    flux = xr.DataArray(
        np.array([1.0, 3.0, 5.0, 7.0], dtype=np.float32),
        dims=("zw",),
        coords={"zw": zw},
    )
    centered = interface_flux_to_cell_center(flux)
    assert centered.dims == ("z",)
    np.testing.assert_allclose(centered.values, [2.0, 4.0, 6.0, 7.0])


def test_add_cell_center_fluxes_4d() -> None:
    nt, nz, ny, nx = 2, 4, 3, 3
    z = np.arange(nz, dtype=np.float32) * 50 + 25
    ds = xr.Dataset(
        {
            "wqtt": (
                ("time", "zw", "y", "x"),
                np.ones((nt, nz, ny, nx), dtype=np.float32),
            ),
        },
        coords={"time": [0, 1800], "zw": z, "y": [0, 1, 2], "x": [0, 1, 2]},
    )
    out = add_cell_center_fluxes(ds)
    assert "wqtt_c" in out
    assert out["wqtt_c"].dims == ("time", "z", "y", "x")


def test_temperature_flux_from_thl_ql() -> None:
    zw = np.array([100.0, 200.0], dtype=np.float32)
    wthlt = xr.DataArray(
        np.full((2, 2, 3, 3), 2.0, dtype=np.float32),
        dims=("time", "zw", "y", "x"),
    )
    wqlt = xr.DataArray(
        np.full((2, 2, 3, 3), 1.0, dtype=np.float32),
        dims=("time", "zw", "y", "x"),
    )
    exner = xr.DataArray(np.array([0.9, 0.85], dtype=np.float32), dims=("zw",), coords={"zw": zw})
    wtemp = temperature_flux_from_thl_ql(wthlt, wqlt, exner)
    # 0.9*2 + (Lv/cp)*1
    from ayil.thermo import DalesThermoConstants

    c = DalesThermoConstants()
    expected = 0.9 * 2.0 + c.rlv_over_cp * 1.0
    np.testing.assert_allclose(float(wtemp.isel(time=0, zw=0, y=0, x=0)), expected, rtol=1e-5)


def test_add_missing_fluxes_wtemp() -> None:
    nt, nz, ny, nx = 1, 3, 2, 2
    z = np.array([50.0, 150.0, 250.0], dtype=np.float32)
    ds = xr.Dataset(
        {
            "thl": (("time", "z", "y", "x"), np.full((nt, nz, ny, nx), 280.0, np.float32)),
            "qt": (("time", "z", "y", "x"), np.full((nt, nz, ny, nx), 0.01, np.float32)),
            "ql": (("time", "z", "y", "x"), np.zeros((nt, nz, ny, nx), np.float32)),
            "wthlt": (("time", "zw", "y", "x"), np.ones((nt, nz, ny, nx), np.float32)),
            "wqlt": (("time", "zw", "y", "x"), np.zeros((nt, nz, ny, nx), np.float32)),
            "exner": (("z",), np.full(nz, 0.95, np.float32)),
        },
        coords={"time": [0.0], "z": z, "zw": z, "y": [0, 1], "x": [0, 1]},
    )
    out = add_missing_fluxes(ds)
    assert "wtemp" in out
    np.testing.assert_allclose(
        out["wtemp"].values,
        0.95 * out["wthlt"].values,
        rtol=1e-5,
    )
