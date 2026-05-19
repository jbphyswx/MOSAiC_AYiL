# AYIL Python post-processing

Merge DALES `fielddump.*.*.001.nc` MPI tiles into a single [Zarr](https://zarr.dev/) store per run day.

## Environment (conda-forge)

Uses the **`MOSAiC_AYIL`** conda env:

```bash
conda env update -n MOSAiC_AYIL -f python/environment.yml
```

Dependencies: `xarray`, `zarr`, `netcdf4`, `pytest` (all from conda-forge). Compression uses `zarr.codecs.BloscCodec` (Zarr v3 API), not `numcodecs` in encoding.

## Convert one run (after simulation completes)

```bash
./scripts/convert_to_zarr.sh runs/20200720
# -> runs/20200720/data.zarr/
```

**Primary entry point** (paths, progress, and logs are in Python — `convert_to_zarr.sh` only activates conda):

```bash
cd python
conda run -n MOSAiC_AYIL python -m ayil.convert runs/20200720
conda run -n MOSAiC_AYIL python -m ayil.convert runs/20200720 -v --overwrite
```

- Resolves `runs/YYYYMMDD` relative to the repo root (no bash path hacks).
- Logs to stderr and `runs/YYYYMMDD/convert.log` by default.
- Per-tile progress at INFO; use `-v` for DEBUG.
- Requires `.ayil_complete` unless `--allow-incomplete`.

Options: `--help` (`--no-staggered`, `--no-consolidated`, `--overwrite`, `-q`, `--log-file`, …).

Programmatic API: `convert_run(..., consolidated=True)` and `write_dataset_zarr(..., consolidated=True, zarr_format=3, codec=None)` — defaults match the CLI; no module globals to edit.

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

Stores are **Zarr v3** with Blosc (zstd, bitshuffle) via `zarr.codecs.BloscCodec`. Writes use **consolidated metadata** (embedded in root `zarr.json` — not part of the v3 spec, but supported by zarr-python/xarray and much faster to open than per-array metadata walks).

| Variable class | Examples | Dimensions |
|----------------|----------|------------|
| Cell-centered | `qt`, `ql`, `thl`, `buoy`, microphysics scalars | `(time, z, y, x)` |
| Staggered winds | `u`, `v`, `w` (MPI tiles stitched) | `u`: `(time, z, y, xu)`; `v`: `(time, z, yv, x)`; `w`: `(time, zw, y, x)` |

Passive tracers from `sv001`–`sv012` in NetCDF are renamed to SB3 bulk micro names (e.g. `n_rain`, `q_rain`, …) per `ayil/scalar_names.py` and `dales_ayil/src/modmicrodata3.f90`.

There are **no** `u_tile_*` / per-rank variables in the store — only global merged fields and a single coordinate set (`time`, `z`, `y`, `x`, plus staggered `xu`, `yv`, `zw` when winds are included).

Re-convert existing days with `--overwrite` after upgrading the merge code.
