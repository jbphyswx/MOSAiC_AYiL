# shellcheck shell=bash
# Resolve MOSAiC_AYiL repository root on login and batch nodes.
#
# Slurm copies job scripts to /var/spool/slurmd/.../slurm_script, so
# BASH_SOURCE there does NOT point into the checkout. Use MOSAiC_AYiL_ROOT
# (sbatch --export), SLURM_SUBMIT_DIR, or a script path under scripts/.

# Print absolute repo root or return 1.
ayil_resolve_repo_root() {
  local cand caller script_dir parent

  for cand in "${MOSAiC_AYiL_ROOT:-}" "${SLURM_SUBMIT_DIR:-}"; do
    if [[ -n "${cand}" && -f "${cand}/scripts/config.sh" ]]; then
      (cd "${cand}" && pwd)
      return 0
    fi
  done

  caller="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
  script_dir="$(cd "$(dirname "${caller}")" && pwd)"
  if [[ "${script_dir}" == */scripts/slurm ]]; then
    parent="$(cd "${script_dir}/../.." && pwd)"
    if [[ -f "${parent}/scripts/config.sh" ]]; then
      echo "${parent}"
      return 0
    fi
  fi

  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  parent="$(cd "${lib_dir}/../.." && pwd)"
  if [[ -f "${parent}/scripts/config.sh" ]]; then
    echo "${parent}"
    return 0
  fi

  echo "ERROR: cannot find MOSAiC_AYiL repo root." >&2
  echo "  Set MOSAiC_AYiL_ROOT, sbatch from the repo, or use ./scripts/slurm_submit.sh" >&2
  echo "  (Slurm job scripts cannot use BASH_SOURCE under /var/spool/slurmd/.)" >&2
  return 1
}
