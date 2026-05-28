# Fielddump and Slurm chunking

MOSAiC_AYIL’s main product is **3D `fielddump`** (`namfielddump` `dtav = 1800` s → **6** snapshots per **10800** s day). Slurm runs many short **warm-started** segments per day. That combination needs clear rules.

**Fork changes in DALES:** [dales_ayil/MOSAiC_AYIL_FORK.md](../dales_ayil/MOSAiC_AYIL_FORK.md) — read before editing Fortran or blaming “sync/Zarr”.

---

## Symptom: big run dir, empty fielddump

| Observation | Meaning |
|-------------|--------|
| `du` ~10–15G, `initdlatest*`, `profiles.001.nc` with many times | LES + restarts + column stats **worked** |
| `fielddump.*.nc` ~39K, `ncdump` → `time = 0` | **No 3D snapshot was ever written** (not deleted in sync) |

---

## Rule

**Each Slurm chunk must reach the next fielddump time before the job exits**, or use the **`modfielddump` `tnext` patch** in this repo’s `dales_ayil` (rebuild `dales4`).

| Approach | `AYIL_CHUNK_SIM_SEC` | Rebuild `dales4`? |
|----------|----------------------|-------------------|
| **Default (recommended)** | **1800** (6 chunks/day) | Patch still recommended; 1800 s aligns with stock DALES scheduling |
| Short chunks (e.g. 300) | &lt; `dtav` | **Required** — use patched `dales_ayil` |
| One job per day | N/A (`--no-chunked`) | Optional |

Do **not** set `AYIL_CHUNK_SIM_SEC=300` (or 600) with `dtav=1800` on **unpatched** upstream DALES.

---

## Check on HPC before burning queue

```bash
ncdump -h runs/YYYYMMDD/fielddump.000.000.001.nc | grep 'time ='
ls -lh runs/YYYYMMDD/fielddump.000.000.001.nc
```

Expect `(N currently)` with `N >= 1` and ~90M per tile (order of magnitude), not `(0 currently)` and 39K.

---

## Re-runs

Days already run with empty `fielddump` must be **integrated again** after fixing chunk length and/or rebuilding `dales4`. `initdlatest` does **not** backfill missing dump times.

```bash
rm -f runs/YYYYMMDD/fielddump.*.*.001.nc
# fix env / rebuild, then resubmit that date
```
