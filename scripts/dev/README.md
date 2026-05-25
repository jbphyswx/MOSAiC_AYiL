# Development / bootstrap scripts

Tools used while **filling** [`sim_dt/`](../sim_dt/README.md) on disk during bootstrap.

**Not for routine production** once `sim_dt/.corpus_complete` exists: remove these scripts, set `AYIL_SIM_DT_RECORD=0`, and keep the CSVs in `sim_dt/` as the fixed record (pipeline reads only).

| Script | Purpose |
|--------|---------|
| `ingest_sim_dt.sh` | Backfill `sim_dt/*.csv` from `runs/*/logs/dales.log` |
