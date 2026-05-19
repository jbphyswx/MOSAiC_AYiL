"""Unit tests for predetermined Zarr chunking and round-trip."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pytest
import xarray as xr
import zarr

from ayil.convert import convert_run
from ayil.zarr_store import (
    DEFAULT_BLOSC,
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
    zarr_encoding,
)
from zarr.codecs import BloscCodec


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


def test_zarr_v3_encoding_uses_compressors_not_deprecated_key(
    tmp_path: Path,
) -> None:
    """
    Zarr v3 + xarray contract (each failure mode gets its own store path).

    - Production: encoding[\"compressors\"] + zarr.codecs.BloscCodec → OK
    - Wrong: encoding[\"compressor\"] (deprecated) + numcodecs → warning + TypeError
    - Wrong: encoding[\"compressors\"] + numcodecs → TypeError (no deprecation warning)
    - FileExistsError only if reusing a path without mode=\"w\" (not tested here)
    """
    from numcodecs import Blosc

    ds = xr.Dataset({"a": (("x",), [1.0])}, coords={"x": [0]})
    enc = zarr_encoding(ds)
    assert "compressor" not in enc["a"]
    assert enc["a"]["compressors"] == [DEFAULT_BLOSC]
    assert isinstance(enc["a"]["compressors"][0], BloscCodec)

    good = tmp_path / "blosc_codec.zarr"
    ds.to_zarr(
        good,
        mode="w",
        zarr_format=3,
        encoding=enc,
        consolidated=False,
    )
    assert (good / "a").is_dir()

    nc = Blosc(cname="zstd", clevel=1)
    with pytest.warns(
        UserWarning, match=r"The `compressor` argument is deprecated"
    ):
        with pytest.raises(TypeError, match="BytesBytesCodec"):
            ds.to_zarr(
                tmp_path / "numcodecs_deprecated_key.zarr",
                mode="w",
                zarr_format=3,
                encoding={"a": {"compressor": nc}},
                consolidated=False,
            )

    with pytest.raises(TypeError, match="BytesBytesCodec"):
        ds.to_zarr(
            tmp_path / "numcodecs_wrong_codec_type.zarr",
            mode="w",
            zarr_format=3,
            encoding={"a": {"compressors": [nc]}},
            consolidated=False,
        )


def test_write_dataset_zarr_consolidated_kwarg(tmp_path: Path) -> None:
    ds = xr.Dataset({"a": (("x",), [1.0])}, coords={"x": [0]})
    out = tmp_path / "cons.zarr"
    write_dataset_zarr(ds, out, consolidated=True)
    assert "consolidated_metadata" in json.loads((out / "zarr.json").read_text())

    out2 = tmp_path / "nocon.zarr"
    write_dataset_zarr(ds, out2, consolidated=False)
    assert "consolidated_metadata" not in json.loads((out2 / "zarr.json").read_text())


def test_zarr_roundtrip(synthetic_run_dir: Path, tmp_path: Path) -> None:
    from ayil.fielddump import merge_fielddump

    ds = merge_fielddump(synthetic_run_dir, include_staggered=False)
    out = tmp_path / "data.zarr"
    write_dataset_zarr(ds, out)

    root = zarr.open_group(out, mode="r")
    assert "qt" in root

    meta = json.loads((out / "zarr.json").read_text())
    assert "consolidated_metadata" in meta

    back = xr.open_zarr(out)
    assert back.sizes["x"] == ds.sizes["x"]
    np.testing.assert_allclose(back["qt"].values, ds["qt"].values, rtol=1e-5)


def test_convert_run_integration(synthetic_run_dir: Path) -> None:
    out = convert_run(
        synthetic_run_dir, overwrite=True, require_complete=False
    )
    assert out.is_dir()
    assert (out / "qt").exists() or ".zarray" in str(list(out.rglob(".zarray"))[0])
