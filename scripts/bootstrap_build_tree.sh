#!/usr/bin/env bash
# One-time (idempotent) setup of files missing from the Zenodo dales_ayil zip.
# Called automatically by build_dales.sh. Safe to run by hand.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

cd "${DALES_SRC}"

if [[ ! -f CMakeLists.txt ]]; then
  echo "Creating CMakeLists.txt from config/github_CMakeLists.txt"
  cp -f config/github_CMakeLists.txt CMakeLists.txt
fi

if [[ ! -x findnetcdf ]]; then
  chmod +x findnetcdf 2>/dev/null || true
fi
if [[ ! -x findnetcdf ]]; then
  echo "ERROR: ${DALES_SRC}/findnetcdf is missing or not executable." >&2
  exit 1
fi

mkdir -p cases/standard
if [[ ! -f cases/standard/moduser.f90 ]]; then
  echo "Creating cases/standard/moduser.f90 from src/moduser.f90"
  cp -f src/moduser.f90 cases/standard/moduser.f90
fi

# CMake git-version.cmake needs this template (Zenodo zip often omits it; *.in was gitignored).
if [[ ! -f src/modversion.f90.in ]]; then
  if [[ -f config/modversion.f90.in ]]; then
    echo "Creating src/modversion.f90.in from config/modversion.f90.in"
    cp -f config/modversion.f90.in src/modversion.f90.in
  else
    echo "ERROR: missing src/modversion.f90.in and config/modversion.f90.in" >&2
    exit 1
  fi
fi

echo "Build tree OK under ${DALES_SRC}"
