"""Write xarray Datasets to Zarr with fixed, predetermined chunk shapes."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import xarray as xr

# Zarr v2 + numcodecs works with xarray; env has zarr 3.x which retains v2 API.
ZARR_FORMAT = 2

# ---------------------------------------------------------------------------
# AYIL fielddump grid (from namoptions: itot=jtot=320, khigh=200, runtime=7200,
# fielddump dtav=1800). These are fixed for every MOSAiC_AYIL day in this repo.
# ---------------------------------------------------------------------------
FIELDDUMP_NX = 320
FIELDDUMP_NY = 320
FIELDDUMP_NZ = 200  # namfielddump khigh
FIELDDUMP_TIME_STEP_S = 1800
FIELDDUMP_RUNTIME_S = 7200
FIELDDUMP_N_TIME = FIELDDUMP_RUNTIME_S // FIELDDUMP_TIME_STEP_S  # 4 dumps per day

# Preset B (repo default): full 2 h of output per time chunk; even tiles in x,y,z.
# float32 payload per chunk: 4 × 100 × 80 × 80 × 4 B = 10_240_000 B (~9.77 MiB, before compression).
FIELDDUMP_CHUNKS_TIME = 4
FIELDDUMP_CHUNKS_Z = 100
FIELDDUMP_CHUNKS_Y = 80
FIELDDUMP_CHUNKS_X = 80

# Tuple order matches merged center-field dims (time, z, y, x).
FIELDDUMP_CHUNKS_CENTER: tuple[int, int, int, int] = (
    FIELDDUMP_CHUNKS_TIME,
    FIELDDUMP_CHUNKS_Z,
    FIELDDUMP_CHUNKS_Y,
    FIELDDUMP_CHUNKS_X,
)

FIELDDUMP_CHUNK_BYTES_FLOAT32 = (
    FIELDDUMP_CHUNKS_TIME
    * FIELDDUMP_CHUNKS_Z
    * FIELDDUMP_CHUNKS_Y
    * FIELDDUMP_CHUNKS_X
    * 4
)


def fielddump_chunks_for_dims(dims: tuple[str, ...]) -> tuple[int, ...]:
    """
  Map dimension names to the predetermined fielddump chunk lengths.

  Center scalars use (time, z, y, x). Unknown dims get length 1.
  """
    lookup = {
        "time": FIELDDUMP_CHUNKS_TIME,
        "z": FIELDDUMP_CHUNKS_Z,
        "zt": FIELDDUMP_CHUNKS_Z,
        "y": FIELDDUMP_CHUNKS_Y,
        "yt": FIELDDUMP_CHUNKS_Y,
        "x": FIELDDUMP_CHUNKS_X,
        "xt": FIELDDUMP_CHUNKS_X,
    }
    return tuple(lookup.get(d, 1) for d in dims)


def zarr_encoding(
    ds: xr.Dataset,
    *,
    chunks_center: tuple[int, int, int, int] = FIELDDUMP_CHUNKS_CENTER,
    compressor: Any | None = None,
) -> dict[str, dict[str, Any]]:
    """Build xarray→zarr encoding using fixed chunk shapes (no runtime sizing)."""
    if compressor is None and ZARR_FORMAT == 2:
        from numcodecs import Blosc

        compressor = Blosc(cname="zstd", clevel=3, shuffle=Blosc.BITSHUFFLE)

    encoding: dict[str, dict[str, Any]] = {}
    for name, da in ds.data_vars.items():
        if da.dims == ("time", "z", "y", "x"):
            chunk_tuple = chunks_center
        else:
            chunk_tuple = fielddump_chunks_for_dims(da.dims)

        enc: dict[str, Any] = {"chunks": chunk_tuple}
        if compressor is not None:
            enc["compressor"] = compressor
        encoding[name] = enc
    return encoding


def write_dataset_zarr(
    ds: xr.Dataset,
    store_path: Path,
    *,
    mode: str = "w",
    chunks_center: tuple[int, int, int, int] = FIELDDUMP_CHUNKS_CENTER,
    group: str | None = None,
    compressor: Any | None = None,
) -> Path:
    """
  Write ``ds`` to a Zarr store (directory) with predetermined chunking.

  Parameters
  ----------
  chunks_center:
      Chunk shape for variables on ``(time, z, y, x)``; defaults to preset B.
  """
    store_path = Path(store_path)
    if store_path.suffix != ".zarr":
        store_path = store_path.with_suffix(".zarr")

    encoding = zarr_encoding(
        ds, chunks_center=chunks_center, compressor=compressor
    )
    ds.to_zarr(
        store_path,
        mode=mode,
        encoding=encoding,
        group=group,
        consolidated=True,
        zarr_format=ZARR_FORMAT,
    )
    return store_path
