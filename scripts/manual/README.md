# Manual LES checks (not part of `./test/run_tests.sh`)

These scripts run **real** `dales4` MPI on the full 320×320 domain. They are for human verification on a **compute node** with enough memory — not for CI, laptops, or login nodes.

The automated test suite uses `test/fixtures/bin/mock_dales4` instead.

| Script | Purpose |
|--------|---------|
| `smoke_test.sh` | Cold start, short patched runtime, checks log |
| `chunk_warmstart_smoke_test.sh` | Two chunks, real restart I/O |

```bash
./scripts/build_dales.sh   # once
srun --pty -n 1 -t 30 --mem=64G bash -lc '
  cd /path/to/MOSAiC_AYIL && source scripts/setup_env.sh
  ./scripts/manual/smoke_test.sh 20200720 4 120
'
```
