# shellcheck shell=bash
# Mirror DALES initd restart naming (MOSAiC_AYiL/src/modstartup.f90).
# Used by tests and chunk_run docs; keep in sync with do_writerestartfiles / readrestartfiles.

# 1-based Fortran-style splice: replace positions [start, start+len-1] with repl.
ayil_str_splice() {
  local s="$1" start="$2" len="$3" repl="$4"
  local i=$((start - 1))
  echo "${s:0:i}${repl}${s:i+len}"
}

# Timed restart written at simulation time rtimee (seconds); matches initdXXXhXXm template.
ayil_dales_timed_initd_name() {
  local rtimee="$1" cmyid="$2" expnr="${3:-001}"
  local ihour=$(( rtimee / 3600 ))
  local imin=$(( (rtimee - ihour * 3600) * 60 / 3600 ))
  local name='initdXXXhXXmXXXXXXXX.XXX'
  name="$(ayil_str_splice "${name}" 6 3 "$(printf '%03d' "${ihour}")")"
  name="$(ayil_str_splice "${name}" 10 2 "$(printf '%02d' "${imin}")")"
  name="$(ayil_str_splice "${name}" 13 8 "${cmyid}")"
  name="$(ayil_str_splice "${name}" 22 3 "${expnr}")"
  echo "${name}"
}

# File copied to after do_writerestartfiles: linkname(6:11) = "latest".
ayil_dales_latest_initd_name() {
  local rtimee="$1" cmyid="$2" expnr="${3:-001}"
  local name
  name="$(ayil_dales_timed_initd_name "$rtimee" "$cmyid" "$expnr")"
  ayil_str_splice "${name}" 6 6 'latest'
}

# Path DALES opens on warm start (readrestartfiles: name=startfile; name(13:20)=cmyid).
ayil_dales_resolve_initd_startfile() {
  local startfile="$1" cmyid="$2"
  ayil_str_splice "${startfile}" 13 8 "${cmyid}"
}

# cmyid format from modmpi.f90: write(cmyid,'(a,i3.3,a,i3.3)') 'x', myidx, 'y', myidy
ayil_dales_cmyid() {
  local myidx="$1" myidy="$2"
  printf 'x%03dy%03d\n' "${myidx}" "${myidy}"
}

# Enumerate all rank IDs for a Cartesian MPI mesh (balanced factorization, like MPI_DIMS_CREATE).
ayil_dales_cmyids_for_nproc() {
  local nprocs="$1"
  local nprocx=1 nprocy="${nprocs}" d other span
  local best_span="${nprocs}"
  for d in 1 2 4 5 8 10 16 20 32 40 64 80 160 320; do
    if (( nprocs % d != 0 )); then
      continue
    fi
    other=$(( nprocs / d ))
    if (( d <= other )); then
      span=$(( other - d ))
    else
      span=$(( d - other ))
    fi
    if (( span < best_span )); then
      best_span="${span}"
      if (( d <= other )); then
        nprocx="${d}"
        nprocy="${other}"
      else
        nprocx="${other}"
        nprocy="${d}"
      fi
    fi
  done
  if (( nprocx * nprocy != nprocs )); then
    echo "ERROR: cannot factor nprocs=${nprocs}" >&2
    return 1
  fi
  local ix iy
  for ((ix = 0; ix < nprocx; ix++)); do
    for ((iy = 0; iy < nprocy; iy++)); do
      ayil_dales_cmyid "${ix}" "${iy}"
    done
  done
}
