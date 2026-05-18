# AYIL Python post-processing

Merge DALES `fielddump.*.*.001.nc` MPI tiles into a single [Zarr](https://zarr.dev/) store per run day.

## Environment (conda-forge)

Uses the **`MOSAiC_AYIL`** conda env:

```bash
conda env update -n MOSAiC_AYIL -f python/environment.yml
```

Dependencies: `xarray`, `zarr`, `netcdf4`, `numcodecs`, `pytest` (all from conda-forge).

## Convert one run (after simulation completes)

```bash
./scripts/convert_to_zarr.sh runs/20200720
# -> runs/20200720/data.zarr/
```

Options: `python -m ayil.convert --help` (`--no-staggered`, `--overwrite`).

## Zarr chunking (fixed preset B)

See the root [README.md](../README.md#simulation-length-paper-vs-zenodo-configs) for the **2 h vs 3 h** discrepancy between Zenodo `namoptions` and the JAMES paper.

Predetermined for the AYIL domain (`320×320` horizontal, `200` vertical levels, `1800 s` fielddump cadence, `4` dumps per `7200 s` run):

| Dim | Chunk | Tiles |
|-----|-------|-------|
| time | 4 | full 2 h run per chunk |
| z | 100 | 2 |
| y | 80 | 4 |
| x | 80 | 4 |

~9.77 MiB uncompressed per `(time, z, y, x)` float32 chunk (10_240_000 B, before Blosc). Constants live in `ayil/zarr_store.py` as `FIELDDUMP_CHUNKS_*`.

## Tests

```bash
cd python
conda run -n MOSAiC_AYIL pytest
```

Tests use synthetic NetCDF tiles only (no live run required).

## Output layout

- Cell-centered scalars (`qt`, `ql`, `thl`, `buoy`, `sv*`) → dimensions `(time, z, y, x)` with ~25 MB chunks and Blosc compression.
- Staggered winds (`u`, `v`, `w`) are stored per tile as `u_tile_IX_IY` until a full staggered merge is implemented.
