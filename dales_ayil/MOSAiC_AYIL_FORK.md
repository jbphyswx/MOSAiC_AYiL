# `dales_ayil`: changes from upstream DALES

This tree is **not** vanilla [dalesteam/dales](https://github.com/dalesteam/dales). MOSAiC_AYIL ships a fork under `dales_ayil/` for AYIL LES reproduction. **Rebuild after pulling:** `./scripts/build_dales.sh`.

Upstream docs (namoptions PDF, wiki) do **not** describe these edits.

---

## 1. `src/modfielddump.f90` — warm-start fielddump schedule (required for short Slurm chunks)

**File:** `src/modfielddump.f90`, subroutine `initfielddump`.

**Upstream behavior:** after a warm start, the next 3D dump is scheduled as

`tnext = dtav + btime`

(in internal time steps), i.e. **current sim time + one dump interval**.

**Problem with MOSAiC Slurm chunking:** each chunk is a **new** `dales4` process. If `namfielddump` `dtav = 1800` s (30 min snapshots) but `AYIL_CHUNK_SIM_SEC` is **shorter** (e.g. 300 s or 600 s), the job ends before `tnext`. Sim time still advances via `initdlatest` restarts, but **`fielddump.*.nc` stays at `time = 0`** (~39 KiB shells). Column output (`profiles.001.nc`, `dtav = 60`) is unaffected.

**Fork change:** set `tnext` to the **next `dtav` boundary at or after `btime`** (e.g. `btime = 1500` s → next dump at `1800` s, not `3300` s).

**Without this patch you must either:**

- set `AYIL_CHUNK_SIM_SEC=1800` (must divide `AYIL_DAY_RUNTIME_SEC`), or  
- run `--no-chunked` (one job per day), or  
- lower `namfielddump` `dtav` to match chunk length (changes the science product — **not** the AYIL 6-snapshots-per-day spec).

**Verify after a chunk:** `ncdump -h runs/YYYYMMDD/fielddump.000.000.001.nc | grep 'time ='` should show `(N currently)` with `N > 0` and tiles ~tens of MiB per rank, not `(0 currently)`.

---

## 2. `src/modfielddump.f90` — extra NetCDF fields (output schema)

Same file; extends 3D fielddump beyond upstream variables.

| Added variables | Meaning |
|-----------------|--------|
| `pressure`, `exner`, `temperature` | Thermo on cell centers (`presf`, `exnf`, `tmp0`) |
| `wqtt`, `wthlt`, `wqlt`, `wtemp`, `wqit`, `wthvt` | Vertical fluxes at w levels |

Zarr conversion (`python/ayil/`) expects these when present; see `python/README.md`.

---

## Other pipeline code (not in `dales_ayil/src`)

Slurm chunk orchestration (`scripts/lib/chunk_run.sh`, `namoptions_patch.sh`) lives in **`scripts/`** — see [scripts/README.md](../scripts/README.md) and [README.md](../README.md). That bash layer is separate from the Fortran fork but must stay consistent with **`dtav`** and **`AYIL_CHUNK_SIM_SEC`**.

---

## Rebuild

```bash
./scripts/build_dales.sh
```

Use the resulting `dales_ayil/build/src/dales4` on HPC and locally. Do not assume a system-wide `dales4` matches this fork.
