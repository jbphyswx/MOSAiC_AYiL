# Building MOSAiC_AYiL

Do **not** follow `INSTALL.md` in this folder for AYiL runs—that file describes cloning upstream [dalesteam/dales](https://github.com/dalesteam/dales).

Use the repo pipeline instead (from `MOSAiC_AYiL` root):

```bash
./scripts/reproduce.sh      # check, bootstrap, build, smoke test
# or step by step:
./scripts/build_dales.sh
```

Committed here for Zenodo-minimal trees:

- `CMakeLists.txt` — from `config/github_CMakeLists.txt`
- `findnetcdf` — NetCDF include path for CMake
- `cases/standard/moduser.f90` — default case user module

Binary output: `build/src/dales4`
