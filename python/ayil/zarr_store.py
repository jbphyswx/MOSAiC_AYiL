"""Write xarray Datasets to Zarr v3 with fixed, predetermined chunk shapes."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import xarray as xr
from zarr.codecs import BloscCodec

# Blosc for v3 writes: xarray passes encoding["compressors"] to zarr, which expects
# zarr.codecs.* instances. numcodecs.Blosc is the Zarr v2 codec API and raises
# TypeError if passed on a v3 write (even under the "compressors" key).
DEFAULT_BLOSC = BloscCodec(cname="zstd", clevel=3, shuffle="bitshuffle")

# ---------------------------------------------------------------------------
# AYIL fielddump grid (from namoptions: itot=jtot=320, khigh=200, runtime=10800,
# fielddump dtav=1800). These are fixed for every MOSAiC_AYIL day in this repo.
# ---------------------------------------------------------------------------
FIELDDUMP_NX = 320
FIELDDUMP_NY = 320
FIELDDUMP_NZ = 200  # namfielddump khigh
FIELDDUMP_TIME_STEP_S = 1800
FIELDDUMP_RUNTIME_S = 10800
FIELDDUMP_N_TIME = FIELDDUMP_RUNTIME_S // FIELDDUMP_TIME_STEP_S  # 6 dumps per day

# Preset B (repo default): full 3 h of output per time chunk; even tiles in x,y,z.
# float32 payload per chunk: 6 × 100 × 80 × 80 × 4 B = 15_360_000 B (~14.6 MiB, before compression).
FIELDDUMP_CHUNKS_TIME = 6
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
        "zm": FIELDDUMP_CHUNKS_Z,
        "zw": FIELDDUMP_CHUNKS_Z,
        "y": FIELDDUMP_CHUNKS_Y,
        "yt": FIELDDUMP_CHUNKS_Y,
        "yv": FIELDDUMP_CHUNKS_Y,
        "ym": FIELDDUMP_CHUNKS_Y,
        "x": FIELDDUMP_CHUNKS_X,
        "xt": FIELDDUMP_CHUNKS_X,
        "xu": FIELDDUMP_CHUNKS_X,
        "xm": FIELDDUMP_CHUNKS_X,
    }
    return tuple(lookup.get(d, 1) for d in dims)


def zarr_encoding(
    ds: xr.Dataset,
    *,
    chunks_center: tuple[int, int, int, int] = FIELDDUMP_CHUNKS_CENTER,
    codec: BloscCodec | None = None,
) -> dict[str, dict[str, Any]]:
    """Build xarray→Zarr v3 encoding using fixed chunk shapes (no runtime sizing)."""
    if codec is None:
        codec = DEFAULT_BLOSC

    encoding: dict[str, dict[str, Any]] = {}
    for name, da in ds.data_vars.items():
        if da.dims == ("time", "z", "y", "x"):
            chunk_tuple = chunks_center
        else:
            chunk_tuple = fielddump_chunks_for_dims(da.dims)

        enc: dict[str, Any] = {"chunks": chunk_tuple}
        if codec is not None:
            # Zarr v3 encoding key is "compressors" (list), not deprecated "compressor".
            enc["compressors"] = [codec]
        encoding[name] = enc
    return encoding


def write_dataset_zarr(
    ds: xr.Dataset,
    store_path: Path,
    *,
    mode: str = "w",
    chunks_center: tuple[int, int, int, int] = FIELDDUMP_CHUNKS_CENTER,
    group: str | None = None,
    codec: BloscCodec | None = None,
    consolidated: bool = True,
    zarr_format: int = 3,
) -> Path:
    """
    Write ``ds`` to a Zarr store (directory) with predetermined chunking.

    Parameters
    ----------
    chunks_center:
        Chunk shape for variables on ``(time, z, y, x)``; defaults to preset B.
    codec:
        Zarr v3 Blosc codec (default ``DEFAULT_BLOSC``). Must be ``zarr.codecs.BloscCodec``.
    consolidated:
        If True (default), embed consolidated metadata in root ``zarr.json`` for fast
        ``xr.open_zarr`` (supported by zarr-python/xarray; not part of the Zarr v3 spec).
    zarr_format:
        Zarr store format version. Only ``3`` is supported by this repo.
    """
    if zarr_format != 3:
        raise ValueError(
            f"Only Zarr format 3 is supported; got zarr_format={zarr_format!r}"
        )

    store_path = Path(store_path)
    if store_path.suffix != ".zarr":
        store_path = store_path.with_suffix(".zarr")

    encoding = zarr_encoding(ds, chunks_center=chunks_center, codec=codec)
    ds.to_zarr(
        store_path,
        mode=mode,
        encoding=encoding,
        group=group,
        consolidated=consolidated,
        zarr_format=zarr_format,
    )
    return store_path
