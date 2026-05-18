"""Unit tests for predetermined Zarr chunking and round-trip."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest
import xarray as xr
import zarr

from ayil.convert import convert_run
from ayil.zarr_store import (
    FIELDDUMP_CHUNK_BYTES_FLOAT32,
    FIELDDUMP_CHUNKS_CENTER,
    FIELDDUMP_CHUNKS_TIME,
    FIELDDUMP_CHUNKS_X,
    FIELDDUMP_CHUNKS_Y,
    FIELDDUMP_CHUNKS_Z,
    FIELDDUMP_NX,
    FIELDDUMP_NY,
    FIELDDUMP_NZ,
    FIELDDUMP_N_TIME,
    fielddump_chunks_for_dims,
    write_dataset_zarr,
)


def test_domain_and_chunks_divide_grid() -> None:
    assert FIELDDUMP_NX % FIELDDUMP_CHUNKS_X == 0
    assert FIELDDUMP_NY % FIELDDUMP_CHUNKS_Y == 0
    assert FIELDDUMP_NZ % FIELDDUMP_CHUNKS_Z == 0
    assert FIELDDUMP_N_TIME % FIELDDUMP_CHUNKS_TIME == 0
    assert FIELDDUMP_CHUNKS_CENTER == (
        FIELDDUMP_CHUNKS_TIME,
        FIELDDUMP_CHUNKS_Z,
        FIELDDUMP_CHUNKS_Y,
        FIELDDUMP_CHUNKS_X,
    )


def test_preset_b_chunk_bytes() -> None:
    # Preset B: 4×100×80×80 float32 → 10_240_000 B (~9.77 MiB)
    assert FIELDDUMP_CHUNK_BYTES_FLOAT32 == 4 * 100 * 80 * 80 * 4
    assert FIELDDUMP_CHUNK_BYTES_FLOAT32 == 10_240_000


def test_fielddump_chunks_for_dims_center() -> None:
    assert fielddump_chunks_for_dims(("time", "z", "y", "x")) == FIELDDUMP_CHUNKS_CENTER


def test_zarr_roundtrip(synthetic_run_dir: Path, tmp_path: Path) -> None:
    from ayil.fielddump import merge_fielddump

    ds = merge_fielddump(synthetic_run_dir, include_staggered=False)
    out = tmp_path / "data.zarr"
    write_dataset_zarr(ds, out)

    root = zarr.open_group(out, mode="r")
    assert "qt" in root
    assert root["qt"].chunks == FIELDDUMP_CHUNKS_CENTER

    back = xr.open_zarr(out, consolidated=True)
    assert back.sizes["x"] == ds.sizes["x"]
    np.testing.assert_allclose(back["qt"].values, ds["qt"].values, rtol=1e-5)


def test_convert_run_integration(synthetic_run_dir: Path) -> None:
    out = convert_run(synthetic_run_dir, overwrite=True)
    assert out.is_dir()
    assert (out / "qt").exists() or ".zarray" in str(list(out.rglob(".zarray"))[0])
